;;; eglot-python.el --- Python server setup for Eglot -*- lexical-binding: t; -*-

;;; Commentary:

;; Use BasedPyright, installing it on demand inside Docker containers,
;; i.e. for DevContainer environments.

;;; Code:

(require 'subr-x)

(defun eglot-python--install-server ()
  "Ensure BasedPyright is installed in the container's Python environment."
  (let ((python (or (executable-find "python" t)
                    (executable-find "python3" t)
                    (error "No Python in container PATH")))
        (uv (executable-find "uv" t)))
    (with-temp-buffer
      (unless (eq 0 (process-file python nil t nil "-c"
				  "import sysconfig; print(sysconfig.get_path('scripts'))"))
        (error "Cannot locate Python scripts: %s" (buffer-string)))
      (let ((server (concat (string-trim (buffer-string))
                            "/basedpyright-langserver")))
        (unless (file-executable-p
                 (concat (file-remote-p default-directory) server))
          (erase-buffer)
          (message "Installing BasedPyright...")
          (unless (eq 0 (if uv
                            (process-file uv nil t nil "pip" "install"
                                          "--python" python "basedpyright")
                          (process-file python nil t nil "-m" "pip"
                                        "install" "basedpyright")))
            (error "BasedPyright install failed: %s" (buffer-string))))
        server))))

(defun eglot-python-contact (&rest _)
  "Return the BasedPyright command, installing it if missing in Docker."
  (list (if (equal (file-remote-p default-directory 'method) "docker")
            (or (executable-find "basedpyright-langserver" t)
                (eglot-python--install-server))
          "basedpyright-langserver")
        "--stdio"))

(provide 'eglot-python)

;;; eglot-python.el ends here
