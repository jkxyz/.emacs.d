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

;;; Customizations

(setopt custom-file (no-littering-expand-etc-file-name "custom.el"))

(when (file-exists-p custom-file)
  (load custom-file))

;;; meow

(use-package meow
  :ensure t)

(use-package enso-meow
  :after meow
  :config
  (enso-meow-setup)
  (meow-global-mode 1))

;;; Modeline

(use-package emacs
  :custom
  ;; Remove unnecessary information from the modeline
  (mode-line-format
   '("%e"
     mode-line-front-space
     (:propertize
      ("" mode-line-mule-info mode-line-client mode-line-modified
       mode-line-remote mode-line-window-dedicated)
      display (min-width (6.0)))
     mode-line-frame-identification
     mode-line-buffer-identification
     (project-mode-line project-mode-line-format)
     mode-line-modes
     mode-line-misc-info
     mode-line-end-spaces)))

;; Allows hiding modes in the mode list
(use-package delight
  :ensure t)

(use-package autorevert
  :delight auto-revert-mode)

(use-package eldoc
  :delight)

;;; Keybindings

(use-package which-key
  :hook after-init
  :delight)

(use-package emacs
  :custom
  ;; Fix integration with the system clipboard. This seems to be
  ;; something that Evil also does when entering visual mode.
  (select-active-regions nil))

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

(defun enso-project-vterm ()
  (interactive)
  (let ((default-directory (project-root (project-current t))))
    (vterm)))

(use-package project
  :demand t
  :bind
  (("C-x p s" . enso-project-ripgrep)
   ("C-x p g" . magit-project-status)
   ("C-x p b" . consult-project-buffer)
   ("C-x p v" . enso-project-vterm))
  :custom
  (project-switch-commands
   '((project-find-file "Find file")
     (magit-project-status "Git status")
     (enso-project-ripgrep "Search")
     (enso-project-vterm "Vterm"))))

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

;;; Dired

(use-package dired
  :custom
  (dired-listing-switches "-al --group-directories-first"))

;;; Line Numbers

(use-package display-line-numbers
  :hook prog-mode)

;;; Whitespace

(use-package ws-butler
  :ensure t
  :hook (after-init . ws-butler-global-mode)
  :delight)

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

;;; Tramp

(use-package tramp
  :config
  (tramp-enable-run0-method))

;;; Rust

(use-package rust-mode
  :ensure t
  :mode "\\.rs"
  :hook (rust-mode . eglot-ensure)
  :init
  (add-to-list 'exec-path "~/.cargo/bin" t)
  (setopt rust-mode-treesitter-derive t))

;;; Themes

(use-package doom-themes
  :ensure t
  :config
  (load-theme 'doom-1337))

;;; vterm

(use-package vterm
  :ensure t)

(provide 'init)

;;; init.el ends here
