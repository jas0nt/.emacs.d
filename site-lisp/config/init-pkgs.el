(require 'package)

(setq package-archives '(("elpa"   . "https://elpa.gnu.org/packages/")
		   ("melpa" . "https://melpa.org/packages/")))

(package-initialize)

(require 'use-package-ensure)
(setq use-package-always-ensure t)

(provide 'init-pkgs)
