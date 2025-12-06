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

;;; Backup files

(use-package emacs
  :custom
  ;; Put backup files in central directory
  (backup-directory-alist (list (cons "." (no-littering-expand-var-file-name "backup/"))))
  (auto-save-file-name-transforms `((".*" ,(no-littering-expand-var-file-name "auto-save") t))))

;;; Path

(add-to-list 'exec-path (expand-file-name "pnpm" (xdg-data-home)))
(setenv "PATH" (concat (expand-file-name "pnpm" (xdg-data-home)) ":" (getenv "PATH")))

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
   '(;; "%e"

     ;; (:propertize
     ;;  ("" mode-line-mule-info mode-line-client mode-line-modified
     ;;   mode-line-remote mode-line-window-dedicated)
     ;;  display (min-width (6.0)))

     ""
     mode-line-mule-info
     mode-line-client
     mode-line-modified
     mode-line-remote
     mode-line-window-dedicated

     mode-line-frame-identification

     mode-line-buffer-identification

     " "

     ;; mode-line-position

     (project-mode-line project-mode-line-format)

     ;; (vc-mode vc-mode)

     ;; "  "

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

(use-package marginalia
  :ensure t
  :hook after-init)

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
  (meow-leader-define-key
   '("w h" . windmove-left)
   '("w j" . windmove-down)
   '("w k" . windmove-up)
   '("w l" . windmove-right)))

(use-package emacs
  :custom
  ;; Maximize the window when opening Emacs
  (default-frame-alist
   '((width . 80)
     (height . 40))))

;;; Dired

(use-package dired
  :custom
  (dired-listing-switches "-al --group-directories-first"))

;;; Line Numbers

(use-package display-line-numbers
  :hook prog-mode)

;;; Whitespace

(use-package emacs
  :config
  (setq-default indent-tabs-mode nil))

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
  :commands (eglot-ensure)
  :custom
  (eglot-connect-timeout (* 5 60))
  :config
  (meow-leader-define-key
   '("c l a" . eglot-code-actions)
   '("c l r" . eglot-rename)
   '("c l f" . eglot-format)))

;;; Markdown

(use-package markdown-mode
  :ensure t
  :after eglot)

;;; Tree Sitter

(use-package treesit
  :config
  (setq treesit--install-language-grammar-out-dir-history
	(list (no-littering-expand-var-file-name "treesit/"))))

;;; Tramp

(use-package tramp
  :config
  (tramp-enable-run0-method))

;;; Formatting

(use-package apheleia
  :ensure t
  :hook prog-mode
  :delight
  :config
  ;; Let prettier detect the parser to use
  (setf (alist-get 'prettier-json apheleia-formatters)
        '("apheleia-npx" "prettier" "--stdin-filepath" file)))

;;; Rust

(use-package rust-mode
  :ensure t
  :mode "\\.rs\\'"
  :hook (rust-mode . eglot-ensure)
  :init
  (add-to-list 'exec-path "~/.cargo/bin" t)
  (setopt rust-mode-treesitter-derive t))

;;; TypeScript

(use-package typescript-ts-mode
  :mode "\\.ts\\'"
  :hook (typescript-ts-mode . eglot-ensure)
  :config
  (add-to-list 'treesit-language-source-alist
	       '(typescript . ("https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src"))))

(use-package json-ts-mode
  :mode "\\.json\\'"
  :config
  (add-to-list 'treesit-language-source-alist
	       '(json . ("https://github.com/tree-sitter/tree-sitter-json"))))

(use-package js
  :custom
  (js-indent-level 2))

;;; Paredit

(use-package smartparens
  :ensure t
  :delight
  :hook (prog-mode . smartparens-global-mode)
  :config
  (sp-use-smartparens-bindings))

;;; Clojure

(use-package clojure-mode
  :ensure t
  :mode ("\\.clj\\'" . clojure-mode)
  :mode ("\\.cljs\\'" . clojurescript-mode)
  :mode ("\\.cljc\\'" . clojurec-mode)
  :mode ("\\.edn\\'" . clojure-mode)
  :hook (clojure-mode . eglot-ensure))

(use-package cider
  :ensure t
  :hook clojure-mode
  :custom
  (cider-xref-fn-depth 90))

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
