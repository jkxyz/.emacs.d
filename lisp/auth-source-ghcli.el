;;; auth-source-ghcli.el --- GitHub CLI authentication for Forge -*- lexical-binding: t; -*-

;;; Commentary:

;; Add `gh-cli' to `auth-sources' to reuse `gh auth login --web' in Forge.
;; Set Git's github.user to the corresponding GitHub username.  Exact
;; host and USERNAME^forge queries are supported; other searches fall
;; through to the remaining auth sources.  Credentials are read only.
;;
;; Based on the approach discussed at:
;; https://github.com/magit/forge/discussions/544
;; Tokens are fetched when used, so auth-source caching does not prevent
;; GitHub CLI from refreshing expiring credentials.

;;; Code:

(require 'auth-source)
(require 'cl-lib)
(require 'subr-x)

(defgroup auth-source-ghcli nil
  "Forge authentication using an existing GitHub CLI login."
  :group 'auth-source)

(defcustom auth-source-ghcli-executable "gh"
  "GitHub CLI executable."
  :type 'string)

(defcustom auth-source-ghcli-hosts
  '(("api.github.com" . "github.com") ("github.com" . "github.com"))
  "Map Forge API hosts to GitHub CLI login hosts.
Add a mapping for each GitHub Enterprise instance, for example
(\"github.example.com/api/v3\" . \"github.example.com\")."
  :type '(alist :key-type string :value-type string))

(defun auth-source-ghcli--token (hostname username)
  "Retrieve the current token for USERNAME on HOSTNAME without logging it."
  (let ((default-directory temporary-file-directory))
    (with-temp-buffer
      (unless (and (eql 0 (call-process
                           auth-source-ghcli-executable nil '(t nil) nil
                           "auth" "token" "--hostname" hostname "--user" username))
                   (not (string-empty-p (string-trim (buffer-string)))))
        (user-error "Cannot get GitHub CLI token for %s on %s; run gh auth login --hostname %s"
                    username hostname hostname))
      (string-trim (buffer-string)))))

(cl-defun auth-source-ghcli--search (&rest spec
					   &key backend host user port require create delete
					   (max 1) &allow-other-keys)
  "Return a Forge credential matching SPEC, or nil for unsupported searches."
  (when-let* ((hostname (and (stringp host)
                             (alist-get host auth-source-ghcli-hosts nil nil #'equal)))
              (_ (and (stringp user) (string-match "\\`\\(.+\\)\\^forge\\'" user)))
              (username (match-string 1 user))
              (_ (member port '(nil t 443 "443" "https")))
              (_ (not (plist-get spec :label)))
              (_ (> (or max 1) 0)))
    (when (or create delete)
      (user-error "Manage GitHub CLI credentials with gh auth login or gh auth logout"))
    (let ((record (list :backend backend :host host :user user :port (or port "https")
                        :secret (lambda () (auth-source-ghcli--token hostname username)))))
      (when (and (cl-every (lambda (key) (plist-member record key)) require)
                 (cl-every (lambda (key) (memq key '(:host :user :port)))
                           (auth-source-search-keys spec)))
        (list record)))))

(defun auth-source-ghcli--parse (entry)
  "Recognize the `gh-cli' authentication source ENTRY."
  (when (eq entry 'gh-cli)
    (auth-source-backend :type 'gh-cli :source "GitHub CLI"
                         :search-function #'auth-source-ghcli--search)))

(add-hook 'auth-source-backend-parser-functions #'auth-source-ghcli--parse)

(provide 'auth-source-ghcli)

;;; auth-source-ghcli.el ends here
