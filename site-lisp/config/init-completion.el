(use-package orderless
  :init
  (setq completion-styles '(orderless)
	completion-category-defaults nil
	completion-category-overrides '((file (styles partial-completion)))))

(use-package emacs
  :init
  (setq completion-cycle-threshold 3)
  (setq tab-always-indent 'complete))

(use-package vertico
  :init
  (vertico-mode))

(use-package marginalia
  :init
  (marginalia-mode))

(use-package consult
  :config
  (consult-customize
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file consult-xref))

(use-package embark
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)
   ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command)
  :config
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none)))))

(use-package embark-consult
  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

(use-package consult-ag)
(use-package consult-projectile)

(use-package savehist
  :init
  (savehist-mode))

(provide 'init-completion)
