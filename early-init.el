(require 'xdg)

(startup-redirect-eln-cache (expand-file-name "emacs/eln-cache/" (xdg-cache-home)))

(setq gc-cons-threshold most-positive-fixnum)

(add-hook 'emacs-startup-hook
          (lambda () (setq gc-cons-threshold (* 50 1024 1024))))

(menu-bar-mode -1)
(tool-bar-mode -1)
