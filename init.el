;;; init.el --- Emacs init file -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'xdg)
(require 'project)

(defvar jkxyz-lisp-dir
  (expand-file-name "lisp" (file-name-directory user-init-file))
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

;;; Startup

(use-package dashboard
  :ensure t
  :custom
  (initial-buffer-choice 'dashboard-open)
  (dashboard-items '((projects . 10) (recents . 5) (bookmarks . 5)))
  :functions
  dashboard-setup-startup-hook
  :config
  (dashboard-setup-startup-hook))

;;; Environment

(use-package exec-path-from-shell
  :ensure t
  :functions exec-path-from-shell-initialize
  :config
  ;; Unset this so so the Nix profile script always adds the Nix paths.
  (setenv "__ETC_PROFILE_NIX_SOURCED" nil)
  (exec-path-from-shell-initialize))

(use-package mise
  :ensure t
  :hook (after-init . global-mise-mode))

;;; Theme

(use-package doom-themes
  :ensure t
  :config
  (load-theme 'doom-one :no-confirm))

;;; Modeline

;; Use Delight to hide extraneous minor modes from the modeline.

(use-package delight
  :ensure t)

(use-package autorevert
  :delight auto-revert-mode)

(use-package eldoc
  :delight)

(use-package outline
  :delight outline-minor-mode)

;;; Evil

(use-package evil
  :ensure t
  :init
  (setopt evil-want-keybinding nil ; Required for `evil-collection'.
	  evil-respect-visual-line-mode t)
  :custom
  (evil-undo-system 'undo-tree)
  :hook
  (after-init . evil-mode))

(use-package undo-tree
  :ensure t
  :delight
  :hook (after-init . global-undo-tree-mode)
  :custom
  (undo-tree-history-directory-alist
   (list (cons "." (expand-file-name "emacs/undo-tree/" (xdg-state-home))))))

(use-package evil-collection
  :ensure t
  :after evil
  :delight evil-collection-unimpaired-mode
  :functions evil-collection-init
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
  (treesit-enabled-modes t)
  :config
  (make-directory (car treesit-extra-load-path) t))

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
  (eglot-documentation-renderer 'markdown-ts-view-mode)
  :bind
  (:map eglot-mode-map
	("C-c l a" . eglot-code-actions)
	("C-c l r" . eglot-rename)
	("C-c l h" . eldoc)
	("C-c l f" . eglot-format)
	("C-c l F" . eglot-format-buffer)
	("C-c l d" . xref-find-definitions-at-mouse)
	("C-c l R" . eglot-reconnect)))

(use-package eldoc
  :config
  ;; `eldoc--format-doc-buffer' unconditionally enables `visual-line-mode'
  ;; in *eldoc*, after `special-mode' has run.  There is no hook or option
  ;; to opt out, so undo it on the way out.
  (define-advice eldoc--format-doc-buffer
      (:filter-return (buffer) no-visual-line)
    (with-current-buffer buffer
      (visual-line-mode -1))
    buffer))

;;; Linting

(use-package flymake-jsts
  :vc (:url "https://github.com/orzechowskid/flymake-jsts" :rev :newest)
  :functions
  flymake-jsts-eslint-enable
  :hook
  (typescript-ts-base-mode
   . (lambda ()
       (flymake-jsts-eslint-enable)
       (add-hook 'eglot-managed-mode-hook #'flymake-jsts-eslint-enable nil t))))

;; Using the Flymake Emacs Lisp bytecode linter puts a bunch of trash
;; in the config directory.
;; (use-package flymake
;;   :hook emacs-lisp-mode)

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
  :functions
  consult-ripgrep
  :bind
  (("C-s" . consult-line)
   ("C-r" . consult-line)
   ("M-g g" . consult-goto-line)
   ("M-g i" . consult-imenu)
   ("M-g o" . consult-outline)))

;;; Formatting

(use-package apheleia
  :ensure t
  :delight
  :hook (after-init . apheleia-global-mode)
  :custom (apheleia-remote-algorithm 'local))

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
   ("C-x p S" . consult-grep)
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

(use-package browse-at-remote
  :ensure t
  :custom
  (browse-at-remote-add-line-number-if-no-region-selected nil))

(use-package auth-source-ghcli
  :load-path jkxyz-lisp-dir
  :demand t
  :custom
  (auth-sources '(gh-cli default)))

(use-package forge
  :ensure t
  :after magit
  :init
  (setq forge-add-default-bindings nil))

;;; Clojure

(use-package cape
  :ensure t)

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

;;; Terminal Emulation

(use-package ghostel
  ;; Install ghostel via Portage
  :ensure nil
  :bind
  (("C-x m" . ghostel)

   :map project-prefix-map
   ("m" . ghostel-project)
   ("M" . ghostel-project-list-buffers)))

(use-package evil-ghostel
  :ensure t
  :after (ghostel evil)
  :hook ghostel-mode)

;;; Claude Code

(use-package claude-code-ide
  :vc (:url "https://github.com/manzaltu/claude-code-ide.el" :rev :newest)
  :bind ("C-c C-'" . claude-code-ide-menu)
  :custom
  (claude-code-ide-terminal-backend 'ghostel)
  :functions claude-code-ide-emacs-tools-setup
  :config
  (claude-code-ide-emacs-tools-setup))

;;; Nix

(use-package nix-mode
  :ensure t
  :mode "\\.nix\\'")

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
         "\\.nspawn\\'"
         "\\.container\\'"))

(use-package nftables-mode
  :ensure t
  :mode "\\.nft\\'")

;;; Typst

(use-package typst-ts-mode
  :vc (:url "https://codeberg.org/meow_king/typst-ts-mode.git")
  :mode "\\.typ\\'")

;;; Markdown

(use-package visual-fill-column
  :ensure t
  :hook (visual-line-mode . visual-fill-column-for-vline)
  :hook (markdown-ts-mode . visual-line-mode))

(defun jkxyz-markdown-preview ()
  "Render the current Markdown file with Pandoc and open it in a browser."
  (interactive)
  (let* ((source
          (or buffer-file-name
              (user-error "This buffer is not visiting a file")))
         (pandoc
          (or (executable-find "pandoc")
              (user-error "Pandoc is not available in this buffer")))
         (output
          (expand-file-name
           (format "emacs-markdown-preview-%s.html"
                   (substring (secure-hash 'sha256 source) 0 16))
           temporary-file-directory))
         (log (get-buffer-create "*Markdown render*")))
    (save-buffer)
    (with-current-buffer log
      (erase-buffer))
    (if (zerop
         (call-process pandoc nil log nil
                       "--standalone"
                       "--embed-resources"
                       "--to=html5"
                       "--output" output
                       source))
        (browse-url-of-file output)
      (display-buffer log)
      (user-error "Pandoc failed; see %s" (buffer-name log)))))

(use-package markdown-ts-mode
  :bind (:map markdown-ts-mode-map
              ("C-c C-e" . jkxyz-markdown-preview)))

;;; Python

(use-package project
  :custom
  (project-vc-extra-root-markers '(".vscode" ".devcontainer")))

(use-package eglot-python
  :load-path jkxyz-lisp-dir
  :commands eglot-python-contact)

(use-package eglot
  :hook ((python-mode python-ts-mode) . eglot-ensure)
  :config
  (add-to-list 'eglot-server-programs
               '((python-mode python-ts-mode) . eglot-python-contact)))

;;; Fonts

(use-package emacs
  ;; Could use text-mode here, but lots of config modes derive from
  ;; text-mode directly, so it looks a little odd.
  :hook ((markdown-ts-mode git-commit-mode) . variable-pitch-mode)
  :config
  (if (and (eq system-type 'gnu/linux) (getenv "WSL_DISTRO_NAME"))
      ;; Font sizes for WSLg following Windows' 200% display scaling
      (progn
	(set-face-attribute 'default nil :family "Fira Code" :height 90)
	(set-face-attribute 'variable-pitch nil :family "iA Writer Mono S" :height 100))
    ;; Default font sizes
    (progn
      (set-face-attribute 'default nil :family "Fira Code")
      (set-face-attribute 'variable-pitch nil :family "iA Writer Mono S" :height 100))))

;;; PowerShell

(use-package powershell
  :ensure t
  :defer t)

;;; Code Folding

(use-package hideshow
  :delight hs-minor-mode
  :hook (yaml-ts-mode . hs-minor-mode)
  :hook (yaml-ts-mode . hs-indentation-mode))

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
  (after-init . global-display-line-numbers-mode)
  (after-init . global-auto-revert-mode)

  :custom
  (dired-listing-switches "-al --group-directories-first")
  ;; Always use xdg-open to open URLs (GTK doesn't work on WSL).
  (browse-url--inhibit-pgtk t)

  ;; Increase the default frame's size and disable the scroll bar.
  ;; The scroll bar must be set here because this `default-frame-alist'
  ;; value replaces the whole list, clobbering the `(vertical-scroll-bars
  ;; . nil)' entry that `set-scroll-bar-mode' adds in early-init.el. Daemon
  ;; client frames are created after this runs, so they would otherwise be
  ;; born with scroll bars.
  (default-frame-alist '((width . 80) (height . 40) (vertical-scroll-bars . nil))))

;; Navigate between windows with keybindings.
(use-package windmove
  :config
  (windmove-default-keybindings))

(use-package tramp
  :functions tramp-enable-run0-method
  :config
  (tramp-enable-run0-method)
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path))

(use-package tramp-sh
  :if (getenv "WSL_DISTRO_NAME")
  :config
  ;; Use Windows OpenSSH so the 1Password SSH agent is available.  WSL
  ;; starts it with pipes rather than a console, so force a remote pty.
  (let ((ssh (cdr (assoc "ssh" tramp-methods))))
    (setf (cadr (assq 'tramp-login-program ssh)) "ssh.exe")
    (unless (member '("-t" "-t") (cadr (assq 'tramp-login-args ssh)))
      (push '("-t" "-t") (cadr (assq 'tramp-login-args ssh)))))
  ;; Windows OpenSSH doesn't support ControlMaster.
  (setopt tramp-use-connection-share nil))

(use-package devcontainer
  :load-path jkxyz-lisp-dir
  :demand t
  :custom
  (devcontainer-command-prefix '("fnox" "exec" "--")))

(use-package editorconfig
  :hook after-init)

(provide 'init)

;;; init.el ends here
