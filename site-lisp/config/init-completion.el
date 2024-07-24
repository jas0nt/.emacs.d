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

(use-package consult
  :config
  (consult-customize
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file consult-xref))

(use-package consult-ag)
(use-package consult-projectile)

(provide 'init-completion)
