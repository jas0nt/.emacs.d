(require 'package)
;;elpa
(setq package-archives '(("gnu"   . "http://elpa.emacs-china.org/gnu/")
			 ("melpa" . "http://elpa.emacs-china.org/melpa/")))
(package-initialize)


(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

;;(use-package company
;;  :ensure t
;;  :config (global-company-mode t))

(use-package god-mode
  :ensure t
  :bind (("<escape>" . god-local-mode)))

(use-package helm
  :ensure t
  :bind (("M-x" . helm-M-x)
	 ("C-s" . helm-occur)
	 ("C-x C-r" . helm-recentf)
	 ("C-x C-f" . helm-find-files)))

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

(use-package ace-window
  :ensure t
  :init
  (progn
    (global-set-key [remap other-window] 'ace-window)
    (custom-set-faces
     '(aw-leading-char-face
       ((t (:inhrit ace-jump-face-foreground :height 3.0)))))
    ))

(use-package avy
  :ensure t
  :bind (("C-;" . avy-goto-char)))



(provide 'init-package)
