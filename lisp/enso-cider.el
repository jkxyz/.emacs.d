;;; enso-cider.el --- Extensions to CIDER -*- lexical-binding: t -*-

;;; Commentary:

;; This package adds some extensions to CIDER for Clojure development.

;;; Code:

(require 'cider)
(require 'eglot)
(require 'cape)

(defun enso-cider-open-portal ()
  "Initialize and open a Portal inspector."
  (interactive)
  (cider-interactive-eval "(add-tap (requiring-resolve 'portal.api/submit))(portal.api/open)"))

(defvar enso-cider-eglot-combined-completion-at-point
  (cape-capf-super #'cider-complete-at-point
                   #'eglot-completion-at-point)
  "A completion at point function combining CIDER and Eglot backends.")

(defun enso-cider-setup-combined-completion ()
  "Enable or disable combined completions when Eglot and CIDER are both active."
  (if (and (bound-and-true-p cider-mode)
           (eglot-managed-p))
      (progn
        (add-hook 'completion-at-point-functions enso-cider-eglot-combined-completion-at-point nil t)
        (remove-hook 'completion-at-point-functions #'cider-complete-at-point t)
        (remove-hook 'completion-at-point-functions #'eglot-completion-at-point t))
    (progn
      (remove-hook 'completion-at-point-functions enso-cider-eglot-combined-completion-at-point t)
      (when (bound-and-true-p cider-mode)
        (add-hook 'completion-at-point-functions #'cider-complete-at-point nil t))
      (when (eglot-managed-p)
        (add-hook 'completion-at-point-functions #'eglot-completion-at-point nil t)))))

(provide 'enso-cider)

;;; enso-cider.el ends here
