(require 'package)

(setq package-archives '(("elpa"   . "https://elpa.gnu.org/packages/")
		   ("melpa" . "https://melpa.org/packages/")))

(package-initialize)
;; install use-package
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package-ensure)
(setq use-package-always-ensure t)

(defvar bootstrap-version)
(let ((bootstrap-file
 (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
(bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
  (url-retrieve-synchronously
   "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
   'silent 'inhibit-cookies)
(goto-char (point-max))
(eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(provide 'init-pkgs)
