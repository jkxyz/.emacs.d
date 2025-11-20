;;; init.el --- Emacs init file -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

;;; Load Path:

;; Add `lisp/' to the load path.

(defvar enso-lisp-dir
  (expand-file-name "lisp/" (file-name-directory user-init-file))
  "Directory containing additional lisp files for this config.")

(add-to-list 'load-path (directory-file-name enso-lisp-dir) t)

;;; Directories:

;; Set options to avoid putting local files into this directory.

(require 'xdg)

;; Load no-littering to set various useful defaults.
(eval-and-compile
  (setopt no-littering-etc-directory (expand-file-name "emacs/" (xdg-data-home))
	  no-littering-var-directory (expand-file-name "emacs/" (xdg-state-home)))
  (require 'no-littering))

;;; package.el

;; Set options to put packages outside of this directory.
(setopt package-user-dir (no-littering-expand-var-file-name "elpa/")
	package-gnupghome-dir (expand-file-name "gnupg/" package-user-dir))

;; Enable MELPA.
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

(package-initialize)

;;; meow

(use-package meow
  :ensure t)

(use-package enso-meow
  :after meow
  :config
  (enso-meow-setup)
  (meow-global-mode 1))

;;; Keybindings

(use-package which-key
  :hook after-init)

;;; Completion

(use-package vertico
  :ensure t
  :hook after-init)

(use-package orderless
  :ensure t
  :after vertico
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion))))
  (completion-category-defaults nil)
  (completion-pcm-leading-wildcard t))

(use-package savehist
  :hook after-init)

(use-package emacs
  :custom
  (enable-recursive-minibuffers t)
  (read-extended-command-predicate #'command-completion-default-include-p)

  :config
  (context-menu-mode 1))

(use-package corfu
  :ensure t
  :hook (prog-mode . global-corfu-mode))

(use-package consult
  :ensure t
  :bind
  (("C-s" . consult-line)
   ("C-r" . consult-line)
   ("M-g g" . consult-goto-line)
   ("M-g i" . consult-imenu)
   ("M-g o" . consult-outline)))

;;; Projects

(defun enso-project-ripgrep ()
  "Search within current project using `rg'."
  (interactive)
  (let ((default-directory (project-root (project-current t))))
    (consult-ripgrep)))

(use-package project
  :demand t
  :bind
  (("C-x p s" . enso-project-ripgrep)
   ("C-x p g" . magit-project-status)
   ("C-x p b" . consult-project-buffer))
  :custom
  (project-switch-commands
   '((magit-project-status "Git status")
     (project-find-file "Find file")
     (enso-project-ripgrep "Search"))))

;;; Magit

(use-package magit
  :ensure t
  :commands
  (magit-status
   magit-project-status))

;;; Windows

(use-package windmove
  :config
  (windmove-default-keybindings))

(use-package emacs
  :custom
  (default-frame-alist
   '((fullscreen . maximized))))

;;; Line Numbers

(use-package display-line-numbers
  :hook prog-mode)

;;; Whitespace

(use-package ws-butler
  :ensure t
  :hook (after-init . ws-butler-global-mode))

;;; Scrolling

(use-package ultra-scroll
  :ensure t
  :hook after-init
  :custom
  (scroll-conservatively 3))

;;; Eglot (LSP)

(use-package eglot
  :bind
  (:map eglot-mode-map
	("C-c l a" . eglot-code-actions)
	("C-c l r" . eglot-rename)
	("C-c l h" . eldoc)
	("C-c l f" . eglot-format)
	("C-c l F" . eglot-format-buffer)
	("C-c l d" . xref-find-definitions-at-mouse)
	("C-c l R" . eglot-reconnect)))

;;; Rust

(use-package rust-mode
  :ensure t
  :mode "\\.rs"
  :hook (rust-mode . eglot-ensure)
  :init
  (add-to-list 'exec-path "~/.cargo/bin" t)
  (setopt rust-mode-treesitter-derive t))

;;; Customizations

(setopt custom-file (no-littering-expand-etc-file-name "custom.el"))

(when (file-exists-p custom-file)
  (load custom-file))

(provide 'init)

;;; init.el ends here
