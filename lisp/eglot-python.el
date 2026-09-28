;;; eglot-python.el --- Python server setup for Eglot -*- lexical-binding: t; -*-

;;; Commentary:

;; Use BasedPyright, installing it on demand in a private, user-owned
;; environment inside Docker and DevContainer environments.

;; TODO Generalize this or find an existing package that gets Eglot to
;; prompt to install the LSP server.

;;; Code:

(require 'subr-x)

(defun eglot-python--container-p ()
  "Return non-nil in a Docker or DevContainer buffer."
  (member (file-remote-p default-directory 'method)
          '("docker" "devcontainer")))

(defun eglot-python--python ()
  "Find Python on the container PATH for creating the tool environment."
  (or (executable-find "python" t)
      (executable-find "python3" t)
      (error "No Python in container PATH")))

(defun eglot-python--run (program &rest args)
  "Run PROGRAM with ARGS through TRAMP, reporting failures."
  (with-temp-buffer
    (unless (eq 0 (apply #'process-file program nil t nil args))
      (error "%s failed: %s" program (string-trim (buffer-string))))))

(defun eglot-python--install-server ()
  "Install BasedPyright in a private environment in the container."
  (let* ((directory
          (expand-file-name
           (concat (file-remote-p default-directory)
                   "~/.cache/emacs/basedpyright/")))
         (server (concat directory "bin/basedpyright-langserver")))
    (unless (file-executable-p server)
      (let* ((python (eglot-python--python))
             (uv (executable-find "uv" t))
             ;; Commands take container paths; file checks take TRAMP paths.
             (venv (file-local-name directory))
             (venv-python (concat venv "bin/python")))
        (message "Installing BasedPyright in %s..." venv)
        (eglot-python--run python "-m" "venv" venv)
        (if uv
            (eglot-python--run uv "pip" "install"
                               "--python" venv-python "basedpyright")
          (eglot-python--run venv-python "-m" "pip"
                             "install" "basedpyright"))
        (unless (file-executable-p server)
          (error "Installation did not produce %s" server))))
    (file-local-name server)))

(defun eglot-python-contact (&rest _)
  "Return the server command, installing it if missing in Docker."
  (list (if (eglot-python--container-p)
            (or (executable-find "basedpyright-langserver" t)
                (eglot-python--install-server))
          "basedpyright-langserver")
        "--stdio"))

(provide 'eglot-python)

;;; eglot-python.el ends here
