;;; devcontainer.el --- Dev Container CLI workspaces over Tramp -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "32.0.50"))
;; Keywords: tools, files

;;; Commentary:

;; M-x devcontainer-up starts the nearest Dev Container configuration.
;; M-x devcontainer-reopen-in-container starts it and reopens the current
;; file through Tramp.  The `devcontainer' method uses percent-encoded host
;; workspace paths, not container IDs, so filenames survive rebuilds.
;; Example: /devcontainer:%2Fhome%2Fme%2Fproject:/workspaces/project/main.py
;; Existing Tramp hops are preserved; the CLI must be available on the
;; machine hosting the source workspace.  No project.el advice is needed.
;; Requires Emacs 32.0.50 or later for the Tramp filename API used here.

;;; Code:

(require 'cl-lib)
(require 'ansi-color)
(require 'comint)
(require 'compile)
(require 'json)
(require 'subr-x)
(require 'tramp)
(require 'tramp-sh)
(require 'url-util)

(defgroup devcontainer nil
  "Dev Container CLI workspaces over Tramp."
  :group 'tramp
  :prefix "devcontainer-")

(defcustom devcontainer-executable "devcontainer"
  "Dev Container CLI executable on the source workspace's host."
  :type 'string)

(defcustom devcontainer-docker-executable "docker"
  "Docker executable used to inspect mounts on the workspace's host."
  :type 'string)

(defcustom devcontainer-startup-timeout 600
  "Seconds allowed for startup during a direct Tramp connection.
Explicit `devcontainer-up' and reopening run startup asynchronously."
  :type 'integer)

(defcustom devcontainer-tramp-method "devcontainer"
  "Tramp method used by `devcontainer-reopen-in-container'.
The default provides stable workspace filenames and starts the environment
when connecting.  An alternative such as \"docker\" uses the current
container ID and requires the container to remain running."
  :type 'string)

(defcustom devcontainer-filename-resolver-function #'devcontainer--resolve-filename
  "Function mapping a host filename to a container filename.
Called with an absolute host FILE (without any Tramp prefix) and the
container's MOUNTS, a list of JSON alists with symbol keys.  Return an
absolute container filename or signal an error.  The default uses bind
mounts, preferring the most specific source and checking for overlays."
  :type 'function)

(defvar devcontainer--running (make-hash-table :test #'equal)
  "Startup processes keyed by source workspace and configuration.")

(defvar devcontainer--up-completed-host nil)

(defun devcontainer--configs-in (directory)
  "Return configurations directly associated with DIRECTORY."
  (let ((standard (expand-file-name ".devcontainer/devcontainer.json" directory))
        (alternate (expand-file-name ".devcontainer.json" directory))
        (folder (expand-file-name ".devcontainer/" directory)))
    (cond
     ((file-regular-p standard) (list standard))
     ((file-regular-p alternate) (list alternate))
     ((file-directory-p folder)
      (cl-loop for entry in (directory-files folder t directory-files-no-dot-files-regexp)
               for config = (expand-file-name "devcontainer.json" entry)
               when (and (file-directory-p entry) (file-regular-p config))
               collect config)))))

(defun devcontainer--source-prefix (filename)
  "Return the Tramp prefix preceding the final hop in FILENAME."
  (let* ((vec (tramp-dissect-file-name filename))
         (hops (butlast (tramp-compute-multi-hops vec))))
    (when hops
      (concat "/"
              (mapconcat
               (lambda (hop)
                 (let ((copy (copy-tramp-file-name hop)))
                   (setf (tramp-file-name-hop copy) nil)
                   (substring (tramp-make-tramp-file-name copy 'noloc) 1 -1)))
               hops "|")
              ":"))))

(defun devcontainer--find-context (&optional directory)
  "Find the nearest devcontainer above DIRECTORY or `default-directory'.
Return a plist with :workspace and :config, preserving any Tramp prefix.
When several named configurations occur at the nearest level, ask which
one to use.  Discovery does not depend on project.el or a Git root."
  (let ((directory (file-name-as-directory
                    (expand-file-name (or directory default-directory)))))
    (if (equal (file-remote-p directory 'method) "devcontainer")
        (pcase-let* ((`(,workspace ,config)
                      (devcontainer--decode-host (file-remote-p directory 'host)))
                     (prefix (or (devcontainer--source-prefix directory) "")))
          (if config
              (list :workspace (file-name-as-directory (concat prefix workspace))
                    :config (concat prefix config))
            (devcontainer--find-context (concat prefix workspace))))
      (let ((start directory) configs)
        (while (and directory
                    (not (setq configs (devcontainer--configs-in directory))))
          (let ((parent (file-name-directory (directory-file-name directory))))
            (setq directory (unless (equal parent directory) parent))))
        (unless configs
          (user-error "No devcontainer configuration above %s" start))
        (list :workspace directory
              :config
              (if (cdr configs)
                  (let* ((choices (mapcar (lambda (file)
                                           (file-relative-name file directory))
                                         configs))
                         (choice (completing-read "Devcontainer configuration: "
                                                  choices nil t)))
                    (expand-file-name choice directory))
                (car configs)))))))

(defun devcontainer--path-within-p (file directory)
  "Whether absolute FILE equals DIRECTORY or is beneath it."
  (or (equal file (directory-file-name directory))
      (string-prefix-p (file-name-as-directory directory) file)))

(defun devcontainer--resolve-filename (file mounts)
  "Map absolute host FILE into MOUNTS, respecting bind-mount overlays."
  (let ((prefix (or (file-remote-p default-directory) ""))
        candidates)
    (setq file (file-local-name (file-truename (concat prefix file))))
    (dolist (mount mounts)
      (let* ((raw-source (alist-get 'Source mount))
             (source (when (and (equal (alist-get 'Type mount) "bind")
                                (stringp raw-source))
                       (file-local-name (file-truename (concat prefix raw-source)))))
            (destination (alist-get 'Destination mount)))
        (when (and (equal (alist-get 'Type mount) "bind")
                   (stringp source) (stringp destination)
                   (devcontainer--path-within-p file source))
          (let ((target (if (equal file (directory-file-name source))
                            destination
                          (expand-file-name
                           (file-relative-name file (file-name-as-directory source))
                           (file-name-as-directory destination)))))
            (push (list (length (directory-file-name source)) target mount)
                  candidates)))))
    (unless candidates
      (user-error "File is not in a container bind mount: %s" file))
    (setq candidates (sort candidates (lambda (a b) (> (car a) (car b)))))
    (let* ((best (car candidates))
           (target (nth 1 best))
           (chosen (nth 2 best)))
      (when (cl-some (lambda (candidate)
                       (and (= (car candidate) (car best))
                            (not (equal (nth 1 candidate) target))))
                     (cdr candidates))
        (user-error "File has several equally specific container mappings: %s" file))
      (dolist (mount mounts)
        (let ((destination (alist-get 'Destination mount)))
          (when (and (not (eq mount chosen)) (stringp destination)
                     (devcontainer--path-within-p target destination)
                     (>= (length (directory-file-name destination))
                         (length (directory-file-name (alist-get 'Destination chosen)))))
            (user-error "Container mount at %s obscures the mapped file" destination))))
      target)))

(defvar devcontainer--log-buffers (make-hash-table :test #'equal)
  "Log buffers keyed by their full source workspace and configuration.")

(defvar-local devcontainer--log-context nil
  "Source workspace and configuration represented by this log.")

(defvar-local devcontainer--log-process nil
  "CLI process or native startup output sink displayed in this log.")

(define-derived-mode devcontainer-log-mode compilation-mode "Devcontainer"
  "Display Dev Container CLI output using Compilation mode.
Press \\[quit-window] to bury the log while the command continues running.
Press \\[devcontainer-log-restart] to start this workspace again."
  (visual-line-mode -1)
  (setq-local truncate-lines t
              word-wrap nil
              compilation-scroll-output t
              compilation-max-output-line-length nil
              revert-buffer-function #'devcontainer--revert-log)
  (add-hook 'compilation-filter-hook #'ansi-color-compilation-filter nil t))

(define-key devcontainer-log-mode-map (kbd "q") #'quit-window)
(define-key devcontainer-log-mode-map (kbd "g") #'devcontainer-log-restart)
(define-key devcontainer-log-mode-map [remap recompile] #'devcontainer-log-restart)
(define-key devcontainer-log-mode-map [remap kill-compilation] #'devcontainer-log-stop)

(defun devcontainer--context-key (context)
  "Return the full workspace and configuration identity for CONTEXT."
  (let* ((tramp-show-ad-hoc-proxies t)
         (workspace (file-name-as-directory
                     (expand-file-name (plist-get context :workspace))))
         (config (plist-get context :config)))
    (list workspace (and config (expand-file-name config workspace)))))

(defun devcontainer--log-buffer (context &optional reset)
  "Return the reusable log for CONTEXT.
When RESET is non-nil, clear output and initialize a new startup run."
  (let* ((key (devcontainer--context-key context))
         (buffer (gethash key devcontainer--log-buffers))
         (fresh (not (buffer-live-p buffer))))
    (when fresh
      (setq buffer
            (generate-new-buffer
             (format "*devcontainer %s [%s]*"
                     (abbreviate-file-name (directory-file-name (car key)))
                     (if (cadr key)
                         (file-relative-name (cadr key) (car key))
                       "default"))))
      (puthash key buffer devcontainer--log-buffers))
    (with-current-buffer buffer
      (when (or fresh reset)
        (let ((inhibit-read-only t)) (erase-buffer))
        (devcontainer-log-mode)
        (setq-local default-directory (car key)
                    devcontainer--log-context (copy-tree context))
        (goto-char (point-max))))
    buffer))

(defun devcontainer-log-restart ()
  "Start the workspace associated with this log again."
  (interactive)
  (unless devcontainer--log-context
    (user-error "This buffer has no devcontainer workspace"))
  (devcontainer--start
   (copy-tree devcontainer--log-context)
   (lambda (result log)
     (devcontainer--log log "Ready: %s" (alist-get 'containerId result))
     (message "Devcontainer ready: %s" (alist-get 'containerId result)))))

(defun devcontainer--revert-log (_ignore-auto _noconfirm)
  "Restart this log's devcontainer instead of a generic compilation."
  (devcontainer-log-restart))

(defun devcontainer-log-stop ()
  "Stop the startup command displayed in this log."
  (interactive)
  (let ((process devcontainer--log-process))
    (unless (and (processp process) (process-live-p process))
      (user-error "No devcontainer command is running"))
    (if-let* ((transport (process-get process 'devcontainer-transport)))
        (delete-process transport)
      (interrupt-process process))))

(defun devcontainer--insert-output (buffer text)
  "Append TEXT to BUFFER through its active output endpoint's compilation filter."
  (when (and (buffer-live-p buffer) (not (string-empty-p text)))
    (with-current-buffer buffer
      (if (and (processp devcontainer--log-process)
               (eq (process-buffer devcontainer--log-process) buffer))
          (compilation-filter devcontainer--log-process text)
        ;; Before process creation, or when reporting a spawn failure, there
        ;; is no process filter to call.  Do not create an artificial process.
        (let ((inhibit-read-only t)
              (follow (= (point) (point-max))))
          (save-excursion
            (goto-char (point-max))
            (let ((start (copy-marker (point))))
              (unwind-protect
                  (progn
                    (insert text)
                    (ansi-color-apply-on-region start (point-max))
                    (comint-carriage-motion start (point-max)))
                (set-marker start nil))))
          (when follow (goto-char (point-max))))))))

(defun devcontainer--log (buffer format-string &rest args)
  "Append a complete log entry using FORMAT-STRING and ARGS to BUFFER."
  (when (buffer-live-p buffer)
    (let ((separator (with-current-buffer buffer
                       (if (or (= (point-min) (point-max))
                               (eq (char-before (point-max)) ?\n))
                           "" "\n"))))
      (devcontainer--insert-output
       buffer (concat separator (apply #'format format-string args) "\n")))))

(defun devcontainer--output-line (log line terminated)
  "Render one stderr LINE in LOG; TERMINATED means it had a newline.
Recognized CLI JSON events contain text.  Preserve all other lines."
  (let* ((record (ignore-errors
                   (json-parse-string line :object-type 'alist :array-type 'list
                                      :null-object nil :false-object nil)))
         (type (and (listp record) (alist-get 'type record)))
         (text (and (listp record) (alist-get 'text record))))
    (devcontainer--insert-output
     log
     (if (and (member type '("raw" "text" "start" "stop")) (stringp text))
         (let ((rendered
                (pcase type
                  ("start" (concat "Start: " text))
                  ("stop"
                   (let ((start (alist-get 'startTimestamp record))
                         (stop (alist-get 'timestamp record)))
                     (concat (if (and (numberp start) (numberp stop))
                                 (format "Stop (%s ms): " (- stop start))
                               "Stop: ")
                             text)))
                  (_ text))))
           ;; Raw events are fragments of one stream, not complete lines.
           ;; Preserve every level: the CLI includes diagnostics at debug level.
           (if (or (equal type "raw") (string-suffix-p "\n" rendered))
               rendered
             (concat rendered "\n")))
       (concat line (if terminated "\n" ""))))))

(defun devcontainer--output-chunk (log state chunk &optional final)
  "Render stderr CHUNK in LOG, retaining partial lines in STATE.
STATE is a one-element list containing the pending wire data.  When FINAL
is non-nil, also render its last unterminated line."
  (let ((pending (concat (car state) chunk))
        (start 0))
    (while (string-match "\n" pending start)
      (let ((end (match-beginning 0)))
        (setq start (match-end 0))
        (devcontainer--output-line log (substring pending 0 end) t)
        (setq pending (substring pending start) start 0)))
    (when (and final (not (string-empty-p pending)))
      (devcontainer--output-line log pending nil)
      (setq pending ""))
    (setcar state pending)))

(defun devcontainer--run (context command callback &optional log)
  "Run COMMAND in CONTEXT asynchronously, passing parsed JSON to CALLBACK.
Render streamed stderr and retain stdout in LOG.  COMMAND is an argument
list, never a shell command.  Preserve the invoking buffer's environment
in callbacks, and wait asynchronously for both output streams to finish."
  (let* ((default-directory (plist-get context :workspace))
         (cli-executable devcontainer-executable)
         (environment (copy-sequence process-environment))
         (paths (copy-sequence exec-path))
         (stdout (generate-new-buffer " *devcontainer-json*"))
         (stderr (generate-new-buffer " *devcontainer-stderr*"))
         (stderr-state (list ""))
         (log (or log (devcontainer--log-buffer context)))
         main-process main-done stderr-done stderr-ready
         (finished nil))
    (with-current-buffer log
      (unless (derived-mode-p 'devcontainer-log-mode) (devcontainer-log-mode))
      (setq-local default-directory (plist-get context :workspace)
                  devcontainer--log-context (copy-tree context)
                  devcontainer-executable cli-executable
                  process-environment (copy-sequence environment)
                  exec-path (copy-sequence paths)))
    (devcontainer--log log "$ %s" (mapconcat #'shell-quote-argument command " "))
    (cl-labels
        ((complete
          ()
          (unwind-protect
              (let ((process-environment environment)
                    (exec-path paths)
                    (default-directory (plist-get context :workspace)))
                (condition-case failure
                    (let ((output (with-current-buffer stdout (buffer-string))))
                      ;; Log before parsing, including malformed JSON and failures.
                      (unless (string-empty-p output) (devcontainer--log log "%s" output))
                      (unless (and (eq (process-status main-process) 'exit)
                                   (zerop (process-exit-status main-process)))
                        (error "Command failed (%s)" (process-exit-status main-process)))
                      (funcall callback
                               (json-parse-string
                                output :object-type 'alist :array-type 'list
                                :null-object nil :false-object nil)
                               log))
                  (error
                   (devcontainer--log log "Error: %s" (error-message-string failure))
                   (display-buffer log)
                   (message "Devcontainer: %s (see %s)"
                            (error-message-string failure) (buffer-name log)))))
            (when (buffer-live-p stdout) (kill-buffer stdout))
            (when (buffer-live-p stderr) (kill-buffer stderr))
            (process-put main-process 'devcontainer-pending nil)))
         (maybe-complete
          ()
          (when (and main-done stderr-ready stderr-done (not finished))
            (setq finished t)
            ;; Let TRAMP's own process-sentinel cleanup return before callbacks
            ;; start another remote command.  Never block to drain stderr here.
            (run-at-time 0 nil #'complete)))
         (stderr-ended
          ()
          (unless stderr-done
            (setq stderr-done t)
            (devcontainer--output-chunk log stderr-state "" t))
          (maybe-complete)))
      (condition-case err
          (progn
            (setq main-process
                  (make-process
                   :name "devcontainer" :buffer log :stderr stderr
                   :command command :connection-type 'pipe :file-handler t
                   :noquery t
                   :filter
                   (lambda (_process chunk)
                     (when (buffer-live-p stdout)
                       (with-current-buffer stdout
                         (goto-char (point-max))
                         (insert chunk))))
                   :sentinel
                   (lambda (process _event)
                     (when (memq (process-status process) '(exit signal))
                       (setq main-process process main-done t)
                       (maybe-complete)))))
            (unless (processp main-process)
              (error "Tramp could not start the Dev Container CLI"))
            (process-put main-process 'devcontainer-pending t)
            (with-current-buffer log
              (setq-local devcontainer--log-process main-process)
              (set-marker (process-mark main-process) (point-max) log))
            ;; Remote make-process temporarily uses stderr's buffer for its
            ;; shell handshake.  Attach only after that setup has completed.
            (let ((stderr-process (get-buffer-process stderr)))
              (when (processp stderr-process)
                (let ((original-sentinel (process-sentinel stderr-process)))
                  (set-process-filter
                   stderr-process
                   (lambda (_process chunk)
                     (devcontainer--output-chunk log stderr-state chunk)))
                  (set-process-sentinel
                   stderr-process
                   (lambda (process event)
                     (unwind-protect
                         (when original-sentinel (funcall original-sentinel process event))
                       (unless (process-live-p process) (stderr-ended)))))))
              (when (buffer-live-p stderr)
                (devcontainer--output-chunk
                 log stderr-state (with-current-buffer stderr (buffer-string))))
              (setq stderr-ready t)
              (unless (and (processp stderr-process) (process-live-p stderr-process))
                (stderr-ended)))
            (when (memq (process-status main-process) '(exit signal))
              (setq main-done t))
            (maybe-complete)
            main-process)
        (error
         (setq finished t)
         (when (processp main-process)
           (process-put main-process 'devcontainer-pending nil)
           (when (process-live-p main-process) (delete-process main-process)))
         (unless stderr-ready
           (when (buffer-live-p stderr)
             (devcontainer--output-chunk
              log stderr-state (with-current-buffer stderr (buffer-string)) t)))
         (dolist (buffer (list stdout stderr))
           (when (buffer-live-p buffer)
             (when-let* ((process (get-buffer-process buffer))) (delete-process process))
             (kill-buffer buffer)))
         (devcontainer--log log "Error: %s" (error-message-string err))
         (display-buffer log)
         (signal (car err) (cdr err)))))))

(defun devcontainer--start (context callback)
  "Start CONTEXT and call CALLBACK with the CLI result and log buffer."
  (let* ((cli-executable devcontainer-executable)
         (environment (copy-sequence process-environment))
         (paths (copy-sequence exec-path))
         (key (devcontainer--context-key context))
         (existing (gethash key devcontainer--running)))
    (when (and (processp existing)
               (or (process-live-p existing)
                   (process-get existing 'devcontainer-pending)))
      (user-error "This devcontainer is already starting; see its log buffer"))
    (let* ((log (devcontainer--log-buffer context))
           (previous (buffer-local-value 'devcontainer--log-process log)))
      ;; Include later phases such as inspect and stderr draining, even when
      ;; the startup command itself has exited or its callback has run.
      (when (and (processp previous)
                 (or (process-live-p previous)
                     (process-get previous 'devcontainer-pending)))
        (user-error "This devcontainer command is still finishing; see its log buffer"))
      (devcontainer--log-buffer context t)
      ;; A rerun can originate in this same log.  Save its source settings
      ;; before the mode reset above, then restore them for this and later runs.
      (with-current-buffer log
        (setq-local devcontainer-executable cli-executable
                    process-environment environment
                    exec-path paths))
      (let ((window (display-buffer log)))
        (with-current-buffer log
          (goto-char (point-max))
          (when (window-live-p window)
            (set-window-point window (point-max)))))
      (puthash
       key
       (devcontainer--run
        context
        (append
         (list cli-executable "up"
               "--workspace-folder" (directory-file-name
                                     (file-local-name (plist-get context :workspace))))
         (when-let* ((config (plist-get context :config)))
           (list "--config" (file-local-name config)))
         '("--log-format" "json"))
        (lambda (result log)
          (remhash key devcontainer--running)
          (unless (and (equal (alist-get 'outcome result) "success")
                       (stringp (alist-get 'containerId result))
                       (not (string-empty-p (alist-get 'containerId result))))
            (error "CLI did not report a successful container startup: %S" result))
          (funcall callback result log))
        log)
       devcontainer--running))))

;;;###autoload
(defun devcontainer-up ()
  "Start the nearest devcontainer without changing the current buffer.
The source may be local or reached through Tramp.  Progress and errors
appear in a *devcontainer* buffer.  Return the startup process."
  (interactive)
  (devcontainer--start
   (devcontainer--find-context)
   (lambda (result log)
     (devcontainer--log log "Ready: %s" (alist-get 'containerId result))
     (message "Devcontainer ready: %s" (alist-get 'containerId result)))))

(defun devcontainer--target (context result path)
  "Construct a Tramp filename for PATH using CONTEXT and CLI RESULT."
  (unless (and (stringp path) (string-prefix-p "/" path))
    (error "Filename resolver must return an absolute container path"))
  (let* ((workspace (plist-get context :workspace))
         (source-vec (when (file-remote-p workspace)
                       (tramp-dissect-file-name workspace)))
         (hop (when source-vec (tramp-make-tramp-hop-name source-vec)))
         (native (equal devcontainer-tramp-method "devcontainer"))
         (vec (make-tramp-file-name
               :method devcontainer-tramp-method
               :host (if native
                         (devcontainer--encode-workspace workspace (plist-get context :config))
                       (alist-get 'containerId result))
               :user (unless native (alist-get 'remoteUser result))
               :localname path :hop hop))
         (tramp-show-ad-hoc-proxies t))
    (tramp-make-tramp-file-name vec)))

(defun devcontainer--check-source (buffer file tick)
  "Require BUFFER to still visit FILE unmodified since TICK."
  (unless (buffer-live-p buffer) (user-error "Source buffer was closed during startup"))
  (with-current-buffer buffer
    (unless (and buffer-file-name (equal (expand-file-name buffer-file-name) file))
      (user-error "Source buffer changed its visited file during startup"))
    (when (or (buffer-modified-p) (/= tick (buffer-chars-modified-tick)))
      (user-error "Source buffer changed during startup; run reopen again"))))

(defun devcontainer--reopen (buffer file target position window start tick)
  "Open TARGET for BUFFER visiting FILE after checking TICK.
Restore POSITION and WINDOW's START when WINDOW still displays BUFFER.
Keep BUFFER open so the source file remains available."
  (devcontainer--check-source buffer file tick)
  (unless (file-exists-p target)
    (user-error "Mapped file does not exist in the container: %s" target))
  (let ((remote-buffer (find-file-noselect target)))
    (devcontainer--check-source buffer file tick)
    (when (eq buffer remote-buffer)
      (user-error "The target is already the current buffer"))
    (when (buffer-modified-p remote-buffer)
      (user-error "The container buffer already has unsaved edits: %s" target))
    (let ((show (and (window-live-p window) (eq (window-buffer window) buffer))))
      (with-current-buffer remote-buffer
        (goto-char (min position (point-max))))
      (when show
        (with-selected-window window
          (switch-to-buffer remote-buffer nil t))
        (set-window-point window (with-current-buffer remote-buffer (point)))
        (set-window-start window (with-current-buffer remote-buffer (min start (point-max))) t))
    remote-buffer)))

;;;###autoload
(defun devcontainer-reopen-in-container ()
  "Start the nearest devcontainer and switch to this file through Tramp.
Keep the local source buffer open.
Offer to save modified files first.  If edits occur while startup runs,
leave the source buffer intact and ask the user to invoke this again."
  (interactive)
  (unless buffer-file-name (user-error "This buffer is not visiting a file"))
  (when (equal (file-remote-p buffer-file-name 'method) "devcontainer")
    (user-error "This file is already in a devcontainer"))
  (when (buffer-modified-p)
    (unless (y-or-n-p "Save this buffer before reopening in the container? ")
      (user-error "Reopening cancelled; buffer has unsaved edits"))
    (save-buffer))
  (let* ((buffer (current-buffer))
         (file (expand-file-name buffer-file-name))
         (context (devcontainer--find-context (file-name-directory file)))
         (position (point)) (window (selected-window)) (start (window-start))
         (tick (buffer-chars-modified-tick))
         (resolver devcontainer-filename-resolver-function)
         (method devcontainer-tramp-method)
         (docker-executable devcontainer-docker-executable)
         (cli-executable devcontainer-executable)
         ;; Canonicalize on the source host, before stripping its prefix.
         (host-file (file-local-name (file-truename file))))
    (devcontainer--start
     context
     (lambda (result log)
       (let ((devcontainer-executable cli-executable))
         (devcontainer--check-source buffer file tick)
         (devcontainer--run
          context
          (list docker-executable "inspect" "--type" "container"
                "--format" "{{json .Mounts}}" (alist-get 'containerId result))
          (lambda (mounts log)
            (let* ((devcontainer-tramp-method method)
                   (devcontainer-executable cli-executable)
                   (path (funcall resolver host-file mounts))
                   (target (devcontainer--target context result path))
                   (devcontainer--up-completed-host (file-remote-p target 'host)))
              (devcontainer--reopen buffer file target position window start tick)
              (devcontainer--log log "Opened %s" target)
              (message "Opened file in devcontainer")))
          log))))))

(defvar devcontainer--up-completed-host nil
  "Host token whose startup the current command has already completed.
Bind this while opening a file after explicitly running `devcontainer up'.")

(defconst devcontainer--host-safe-characters
  (append (number-sequence ?a ?z) (number-sequence ?A ?Z)
          (number-sequence ?0 ?9) '(?. ?_ ?-))
  "Characters that can appear unescaped in a devcontainer host token.
Unlike ordinary URL encoding, a tilde must be encoded for TRAMP.")

(defun devcontainer--check-host-path (path)
  "Reject PATH if it contains characters unsuitable for a file name."
  (when (string-match-p "[\0\r\n]" path)
    (user-error "Devcontainer paths cannot contain NUL, CR or LF"))
  path)

(defun devcontainer--encode-component (component)
  "Encode COMPONENT as a part of a TRAMP host token."
  (url-hexify-string (devcontainer--check-host-path component)
                    devcontainer--host-safe-characters))

(defun devcontainer--decode-component (component)
  "Decode COMPONENT, rejecting malformed percent escapes."
  (unless (string-match-p
           "\\`\\(?:[A-Za-z0-9._-]\\|%[[:xdigit:]][[:xdigit:]]\\)+\\'"
           component)
    (user-error "Malformed devcontainer host component: %s" component))
  (devcontainer--check-host-path
   (decode-coding-string (url-unhex-string component t) 'utf-8)))

(defun devcontainer--encode-workspace (workspace config)
  "Return a TRAMP host token for WORKSPACE and optional CONFIG.
WORKSPACE is an absolute directory, optionally with a TRAMP prefix.
CONFIG can be absolute on that same host or relative to WORKSPACE.
The token contains the percent-encoded workspace path, followed by
`%%' and the encoded relative configuration path when CONFIG is non-nil.
The caller retains any TRAMP hops separately from this token."
  (let* ((remote (file-remote-p workspace))
         (local-workspace (file-local-name workspace))
         (config-remote (and config (file-remote-p config)))
         (local-config (and config (file-local-name config))))
    (unless (string-prefix-p "/" local-workspace)
      (user-error "Devcontainer workspace must be an absolute host path"))
    (when (and config-remote (not (equal remote config-remote)))
      (user-error "Devcontainer configuration and workspace are on different hosts"))
    ;; These are paths on the CLI host.  Normalize them lexically without
    ;; interpreting another remote prefix or expanding this Emacs's home.
    (let* ((file-name-handler-alist nil)
           (directory (file-name-as-directory
                       (expand-file-name local-workspace)))
           (relative-config
            (when local-config
              (when (string-empty-p local-config)
                (user-error "Devcontainer configuration path is empty"))
              (file-relative-name
               (expand-file-name
                (if (string-prefix-p "/" local-config)
                    local-config
                  (concat directory local-config)))
               directory))))
      (concat (devcontainer--encode-component (directory-file-name directory))
              (when relative-config
                (concat "%%" (devcontainer--encode-component relative-config)))))))

(defun devcontainer--decode-host (host)
  "Return (WORKSPACE CONFIG) decoded from devcontainer HOST.
Both paths are absolute on the CLI host; CONFIG is nil when omitted.
No filesystem access or container startup is performed."
  (unless (stringp host)
    (user-error "A devcontainer workspace must be specified"))
  (let* ((parts (split-string host "%%"))
         (workspace (devcontainer--decode-component (car parts)))
         (config (and (cadr parts)
                      (devcontainer--decode-component (cadr parts)))))
    (when (> (length parts) 2)
      (user-error "A devcontainer host can contain only one configuration separator"))
    (unless (string-prefix-p "/" workspace)
      (user-error "Devcontainer host must encode an absolute workspace path"))
    (when (and config (string-prefix-p "/" config))
      (user-error "Encoded devcontainer configuration must be workspace-relative"))
    (let* ((file-name-handler-alist nil)
           (directory (file-name-as-directory (expand-file-name workspace))))
      (list (directory-file-name directory)
            (and config (expand-file-name (concat directory config)))))))

(defun devcontainer--name-file-buffer ()
  "Include the devcontainer workspace in this file buffer's name."
  (when (and buffer-file-name
             (equal (file-remote-p buffer-file-name 'method)
                    "devcontainer"))
    (let* ((host (file-remote-p buffer-file-name 'host))
           (workspace (car (devcontainer--decode-host host)))
           (label (file-name-nondirectory
                   (directory-file-name workspace)))
           (name (format "%s [devcontainer:%s]"
                         (file-name-nondirectory buffer-file-name)
                         (if (string-empty-p label) workspace label))))
      (unless (equal (buffer-name) name)
        ;; Keep the label in uniquify's base name so it survives when
        ;; other buffers close, while directory suffixes remain automatic.
        (rename-buffer name t)))))

(cl-defstruct (devcontainer--bootstrap (:constructor devcontainer--make-bootstrap))
  "One framed native connection startup and its separate output endpoint."
  transport sink log begin end (pending "") (decoder (list ""))
  started finished filter sentinel)

(defun devcontainer--bootstrap-finish (state &optional failed)
  "Finish STATE's log without changing the transport buffer.
FAILED means the transport exited before reaching the container shell."
  (unless (devcontainer--bootstrap-finished state)
    (setf (devcontainer--bootstrap-finished state) t)
    (let ((transport (devcontainer--bootstrap-transport state))
          (sink (devcontainer--bootstrap-sink state))
          (log (devcontainer--bootstrap-log state)))
      (unwind-protect
          (progn
            (when (devcontainer--bootstrap-started state)
              (devcontainer--output-chunk
               log (devcontainer--bootstrap-decoder state)
               (devcontainer--bootstrap-pending state) t))
            (devcontainer--log
             log (if failed "Error: container connection ended before shell startup"
                   "Container shell ready.")))
        (set-process-filter transport (devcontainer--bootstrap-filter state))
        (set-process-sentinel transport (devcontainer--bootstrap-sentinel state))
        (process-put sink 'devcontainer-pending nil)
        (when (buffer-live-p log)
          (with-current-buffer log
            (when (eq devcontainer--log-process sink)
              (setq devcontainer--log-process nil))))
        (delete-process sink)))))

(defun devcontainer--bootstrap-output (state chunk)
  "Copy only framed bootstrap bytes from CHUNK into STATE's log."
  (unless (devcontainer--bootstrap-finished state)
    (save-match-data
      (let* ((pending (concat (devcontainer--bootstrap-pending state) chunk))
             (marker (if (devcontainer--bootstrap-started state)
                         (devcontainer--bootstrap-end state)
                       (devcontainer--bootstrap-begin state))))
        (if (string-match (regexp-quote marker) pending)
            (let ((before (substring pending 0 (match-beginning 0)))
                  (after (substring pending (match-end 0))))
              (setf (devcontainer--bootstrap-pending state) "")
              (if (devcontainer--bootstrap-started state)
                  (progn
                    (devcontainer--output-chunk
                     (devcontainer--bootstrap-log state)
                     (devcontainer--bootstrap-decoder state) before)
                    (devcontainer--bootstrap-finish state))
                (setf (devcontainer--bootstrap-started state) t)
                (devcontainer--bootstrap-output state after)))
          ;; Retain only a possible partial marker across process chunks.
          (let ((keep (min (length pending) (1- (length marker)))))
            (while (and (> keep 0)
                        (not (string-suffix-p (substring marker 0 keep) pending)))
              (setq keep (1- keep)))
            (when (devcontainer--bootstrap-started state)
              (devcontainer--output-chunk
               (devcontainer--bootstrap-log state)
               (devcontainer--bootstrap-decoder state)
               (substring pending 0 (- (length pending) keep))))
            (setf (devcontainer--bootstrap-pending state)
                  (if (zerop keep) "" (substring pending (- keep))))))))))

(defun devcontainer--bootstrap-prepare (vec already-up)
  "Observe VEC's new main transport, preserving its filter and sentinel.
ALREADY-UP keeps the existing explicit startup log instead of clearing it."
  (when-let* ((transport (tramp-get-connection-process vec))
              ((process-live-p transport)))
    (or (process-get transport 'devcontainer-bootstrap)
        (let* ((cli devcontainer-executable)
               (environment (copy-sequence process-environment))
               (paths (copy-sequence exec-path))
               (decoded (devcontainer--decode-host (tramp-file-name-host vec)))
               (prefix (or (devcontainer--source-prefix
                            (let ((tramp-show-ad-hoc-proxies t))
                              (tramp-make-tramp-file-name vec))) ""))
               (context (list :workspace (file-name-as-directory
                                          (concat prefix (car decoded)))
                              :config (and (cadr decoded)
                                           (concat prefix (cadr decoded)))))
               (log
                (let* ((buffer (devcontainer--log-buffer context))
                       (previous (buffer-local-value 'devcontainer--log-process buffer)))
                  (unless already-up
                    (when (and (processp previous)
                               (or (process-live-p previous)
                                   (process-get previous 'devcontainer-pending)))
                      (user-error "This devcontainer command is still finishing; see its log buffer"))
                    (devcontainer--log-buffer context t))
                  buffer))
               (sink (make-pipe-process
                      :name "devcontainer-startup-log" :buffer log
                      :filter #'compilation-filter :sentinel #'ignore :noquery t))
               (nonce (md5 (format "%s:%s:%s" (float-time) (random) transport)))
               (state (devcontainer--make-bootstrap
                       :transport transport :sink sink :log log
                       :begin (concat "\036devcontainer-" nonce "-begin\037")
                       :end (concat "\036devcontainer-" nonce "-end\037")
                       :filter (process-filter transport)
                       :sentinel (process-sentinel transport))))
          (process-put transport 'devcontainer-bootstrap state)
          (process-put sink 'devcontainer-transport transport)
          (process-put sink 'devcontainer-pending t)
          (with-current-buffer log
            (setq-local devcontainer-executable cli
                        process-environment environment exec-path paths
                        devcontainer--log-process sink)
            (set-marker (process-mark sink) (point-max))
            (goto-char (point-max))
            (let ((window (display-buffer log)))
              (when (window-live-p window)
                (set-window-point window (point-max)))))
          (devcontainer--log log (if already-up "Attaching to container..."
                                  "Starting and attaching to container..."))
          (set-process-filter
           transport
           (lambda (process chunk)
             ;; Observing output must not consume or modify TRAMP's stream.
             (unwind-protect
                 (condition-case failure
                     (devcontainer--bootstrap-output state chunk)
                   (error (message "Devcontainer log: %s"
                                   (error-message-string failure))))
               (funcall (or (devcontainer--bootstrap-filter state)
                            #'internal-default-process-filter)
                        process chunk))))
          (set-process-sentinel
           transport
           (lambda (process event)
             (unwind-protect
                 (unless (process-live-p process)
                   (devcontainer--bootstrap-finish state t))
               (when-let* ((sentinel (devcontainer--bootstrap-sentinel state)))
                 (funcall sentinel process event)))))
          state))))

(defun devcontainer--bootstrap-printf (marker)
  "Return shell code emitting MARKER without echoing its literal framing."
  (format "printf '\\036%s\\037' >&2"
          (substring marker 1 -1)))

(defun devcontainer--login-command (vec)
  "Return the shell command used to connect to devcontainer VEC.
The command runs on the preceding TRAMP hop, or locally for a first hop.
Run `up' for the main connection, then attach with `exec'.  Auxiliary
TRAMP processes attach to the existing container without rerunning its
lifecycle commands.  The shell supplied by TRAMP is passed through
the shell's argument vector."
  (when (or (tramp-file-name-user vec) (tramp-file-name-port vec))
    (user-error "Specify the container user in devcontainer.json; only SSH hops accept user or port"))
  (let* ((host (tramp-file-name-host vec))
         (paths (devcontainer--decode-host host))
         (workspace (car paths))
         (config (cadr paths))
         (cli (tramp-shell-quote-argument devcontainer-executable))
         (arguments
          (mapconcat #'tramp-shell-quote-argument
                     (append (list "--workspace-folder" workspace)
                             (and config (list "--config" config)))
                     " "))
         (auxiliary (tramp-get-connection-property vec " process-name"))
         (already-up
          (or (equal host devcontainer--up-completed-host)
              auxiliary))
         (bootstrap (unless auxiliary
                      (devcontainer--bootstrap-prepare vec already-up))))
    (concat (when bootstrap
              (concat (devcontainer--bootstrap-printf
                       (devcontainer--bootstrap-begin bootstrap)) "; "))
            (unless already-up
              (format "%s up %s --log-format json >&2 && " cli arguments))
            (if bootstrap
                (format "exec %s exec %s /bin/sh -c %s devcontainer \"$@\""
                        cli arguments
                        (tramp-shell-quote-argument
                         (concat (devcontainer--bootstrap-printf
                                  (devcontainer--bootstrap-end bootstrap))
                                 "; exec \"$@\"")))
              (format "exec %s exec %s \"$@\"" cli arguments)))))

(defun devcontainer--login-script (vec)
  "Return a shell-quoted login script for devcontainer VEC."
  (tramp-shell-quote-argument (devcontainer--login-command vec)))

(defun devcontainer--register-tramp-method ()
  "Register the native devcontainer TRAMP method and argument expansion."
  (setf (alist-get "devcontainer" tramp-methods nil nil #'equal)
        `((tramp-login-program "/bin/sh")
          ;; The literal %h marks this method as a distinct destination
          ;; for TRAMP's standard multi-hop validation.  Its expansion
          ;; produces the script rather than passing the token to a shell.
          (tramp-login-args (("-c") ("%h") ("devcontainer") ("%l")))
          (tramp-remote-shell "/bin/sh")
          (tramp-remote-shell-login ("-l"))
          (tramp-remote-shell-args ("-i" "-c"))
          (tramp-connection-timeout ,devcontainer-startup-timeout)))
  ;; Do not opt into tramp-direct-async: its argument expansion splits
  ;; strings at spaces, whereas this method passes a quoted shell script.
  ;; The standard tramp-sh asynchronous path also supports SSH hops.
  (connection-local-set-profile-variables
   'devcontainer-tramp-profile
   '((tramp-extra-expand-args
      ?h (devcontainer--login-script (car tramp-current-connection)))))
  (connection-local-set-profiles
   '(:application tramp :protocol "devcontainer")
   'devcontainer-tramp-profile)
  (add-to-list 'tramp-completion-multi-hop-methods "devcontainer"))


(devcontainer--register-tramp-method)

(add-hook 'find-file-hook #'devcontainer--name-file-buffer)
(add-hook 'after-set-visited-file-name-hook
          #'devcontainer--name-file-buffer)

;; Also label already open files when the package is loaded or reloaded.
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (devcontainer--name-file-buffer)))

(provide 'devcontainer)
;;; devcontainer.el ends here
