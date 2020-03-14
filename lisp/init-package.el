(require 'package)
;;elpa
(setq package-archives '(("gnu"   . "http://elpa.emacs-china.org/gnu/")
			 ("melpa" . "http://elpa.emacs-china.org/melpa/")))
(package-initialize)


(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(use-package company
  :ensure t
  :config (global-company-mode t))

(use-package god-mode
  :ensure t
  :bind (("<escape>" . god-local-mode)))

(use-package helm
  :ensure t
  :bind (("M-x" . helm-M-x)))

(use-package which-key
  :ensure t
  :config (which-key-mode))

(use-package neotree
  :ensure t
  :bind (("C-x t" . neotree-toggle)))

(use-package solarized-theme
  :ensure t
  :config (load-theme 'solarized-light t))

(use-package youdao-dictionary
  :ensure t
  :bind (("C-c d" . youdao-dictionary-search-at-point-tooltip)))

(use-package google-this
  :ensure t)


(provide 'init-package)
