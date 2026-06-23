;;; init.el --- Emacs init file -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'xdg)

(defvar jkxyz-lisp-dir
  (expand-file-name "lisp/" (file-name-directory user-init-file))
  "Directory containing additional Emacs Lisp files for this config.")

;;; Local Files

;; Ensure that local state files are stored outside of the config
;; directory so that it stays clean. Most of these files are
;; redirected to XDG directories.

(use-package no-littering
  ;; `no-littering' is vendored so that it can be loaded first without
  ;; setting up paths for package.el.
  :load-path jkxyz-lisp-dir
  :init
  ;; These options need to be set before `no-littering' is loaded.
  (setopt no-littering-etc-directory (expand-file-name "emacs/" (xdg-data-home))
	  no-littering-var-directory (expand-file-name "emacs/" (xdg-state-home))))

(use-package package
  :custom
  (package-user-dir (expand-file-name "emacs/elpa/" (xdg-state-home)))
  (package-gnupghome-dir (expand-file-name "gnupg/" package-user-dir)))

(use-package emacs
  :custom
  (custom-file (expand-file-name "emacs/custom.el" (xdg-data-home)))
  (backup-directory-alist (list (cons "." (expand-file-name "emacs/backup/" (xdg-state-home)))))
  (auto-save-file-name-transforms `((".*" ,(expand-file-name "emacs/auto-save" (xdg-state-home)) t)))
  :config
  (when (file-exists-p custom-file)
    (load custom-file)))

;;; package.el

(use-package package
  :config
  (add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
  (package-initialize))

;;; Environment

(use-package exec-path-from-shell
  :ensure t
  :config
  ;; Unset this so so the Nix profile script always adds the Nix paths.
  (setenv "__ETC_PROFILE_NIX_SOURCED" nil)
  (exec-path-from-shell-initialize))

(use-package envrc
  :ensure t
  :hook (after-init . envrc-global-mode))

(use-package doom-themes
  :ensure t
  :config
  (load-theme 'doom-one))

;;; Modeline

;; Use Delight to hide extraneous minor modes from the modeline.

(use-package delight
  :ensure t)

(use-package autorevert
  :delight auto-revert-mode)

(use-package eldoc
  :delight)

;;; Evil

(use-package undo-tree
  :ensure t
  :delight
  :hook (after-init . global-undo-tree-mode)
  :custom
  (undo-tree-history-directory-alist
   (list (cons "." (expand-file-name "emacs/undo-tree/" (xdg-state-home))))))

(use-package evil
  :ensure t
  :init
  ;; Required for `evil-collection'.
  (setopt evil-want-keybinding nil)
  :custom
  (evil-undo-system 'undo-tree)
  :hook
  (after-init . evil-mode))

(use-package evil-collection
  :ensure t
  :after evil
  :delight evil-collection-unimpaired-mode
  :config
  (evil-collection-init))

;;; Paredit

(use-package smartparens
  :ensure t
  :delight
  :hook (after-init . smartparens-global-mode)
  :config
  (require 'smartparens-config)
  (require 'smartparens-clojure)
  (require 'smartparens-rust))

(use-package evil-cleverparens
  :ensure t
  :after smartparens
  :hook clojure-mode emacs-lisp-mode
  :delight evil-cleverparens-mode)

;;; Tree-Sitter

(use-package treesit
  :custom
  (treesit-auto-install-grammar 'always)
  (treesit-enabled-modes t))

;;; LSP

(use-package eglot
  :hook
  (typescript-ts-base-mode . eglot-ensure)
  (rust-ts-mode . eglot-ensure)
  (clojure-mode . eglot-ensure)
  :custom
  (eglot-code-action-indications nil)
  ;; clojure-lsp takes a while to startup
  (eglot-connect-timeout (* 5 60))
  :bind
  (:map eglot-mode-map
	("C-c l a" . eglot-code-actions)
	("C-c l r" . eglot-rename)
	("C-c l h" . eldoc)
	("C-c l f" . eglot-format)
	("C-c l F" . eglot-format-buffer)
	("C-c l d" . xref-find-definitions-at-mouse)
	("C-c l R" . eglot-reconnect)))

;;; Completions

;; Display minibuffer completions in a nice vertical list.
(use-package vertico
  :ensure t
  :hook after-init)

;; Display in-buffer completions in a nice vertical list.
(use-package corfu
  :ensure t
  :hook
  (after-init . global-corfu-mode)
  (after-init . corfu-popupinfo-mode))

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
  (tab-always-indent 'complete))

(use-package marginalia
  :ensure t
  :hook after-init)

(use-package consult
  :ensure t
  :bind
  (("C-s" . consult-line)
   ("C-r" . consult-line)
   ("M-g g" . consult-goto-line)
   ("M-g i" . consult-imenu)
   ("M-g o" . consult-outline)))

;;; Project

(defun jkxyz-project-ripgrep ()
  "Search within current project using `rg'."
  (interactive)
  (let ((default-directory (project-root (project-current t))))
    (consult-ripgrep)))

(use-package project
  :demand t
  :bind
  (("C-x p s" . jkxyz-project-ripgrep)
   ("C-x p g" . magit-project-status)
   ("C-x p b" . consult-project-buffer))
  :custom
  (project-switch-commands
   '((project-find-file "Find file")
     (jkxyz-project-ripgrep "Search with ripgrep")
     (magit-project-status "Magit status"))))

;;; Git

(use-package magit
  :ensure t)

(use-package diff-hl
  :ensure t
  :hook (after-init . global-diff-hl-mode)
  :hook (magit-post-refresh . diff-hl-magit-post-refresh))

;;; Clojure

(use-package clojure-mode
  :ensure t
  :mode
  ("\\.clj\\'" . clojure-mode)
  ("\\.cljs\\'" . clojurescript-mode)
  ("\\.cljc\\'" . clojurec-mode)
  ("\\.edn\\'" . edn-mode)
  :custom
  (clojure-toplevel-inside-comment-form t))

(use-package cider
  :ensure t
  :hook clojure-mode
  :custom
  (cider-xref-fn-depth 90))

(use-package enso-cider
  :load-path jkxyz-lisp-dir
  :after cider
  :hook (cider-mode . enso-cider-setup-combined-completion))

;;; Claude Code

(use-package eat
  :ensure t)

(use-package claude-code-ide
  :vc (:url "https://github.com/manzaltu/claude-code-ide.el" :rev :newest)
  :bind ("C-c C-'" . claude-code-ide-menu)
  :custom
  (claude-code-ide-terminal-backend 'eat)
  :config
  (claude-code-ide-emacs-tools-setup))

;;; System Configuration Files

;; Enable `conf-mode' for systemd unit files.
(use-package conf-mode
  :mode ("\\.automount\\'"
         "\\.busname\\'"
         "\\.mount\\'"
         "\\.service\\'"
         "\\.slice\\'"
         "\\.socket\\'"
         "\\.swap\\'"
         "\\.target\\'"
         "\\.timer\\'"
         "\\.link\\'"
         "\\.netdev\\'"
         "\\.network\\'"
         "\\.nspawn\\'"))

(use-package nftables-mode
  :ensure t
  :mode "\\.nft\\'")

;;; Miscellaneous

;; Highlight TODO comments in code.
(use-package hl-todo
  :ensure t
  :hook (after-init . global-hl-todo-mode))

;; Show keybindings for command completions in the minibuffer.
(use-package which-key
  :hook after-init
  :delight)

(use-package emacs
  :hook
  ;; Enable the context menu on right click.
  (after-init . context-menu-mode)
  (prog-mode . display-line-numbers-mode)

  :custom
  (dired-listing-switches "-al --group-directories-first")

  ;; Increase the default frame's size.
  (default-frame-alist '((width . 80) (height . 40))))

;; Navigate between windows with keybindings.
(use-package windmove
  :config
  (windmove-default-keybindings))

(use-package tramp
  :custom
  ;; Use the remote login shell's PATH to find executables.
  (tramp-remote-path '(tramp-own-remote-path tramp-default-remote-path)))

(use-package editorconfig
  :hook after-init)

(provide 'init)

;;; init.el ends here
