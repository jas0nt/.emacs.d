(require 'consult)
(require 'orderless)
(require 'vertico)

(setq completion-styles '(orderless)
	  completion-category-defaults nil
	  completion-category-overrides '((file (styles partial-completion)))
    completion-cycle-threshold 3
    tab-always-indent 'complete)

(vertico-mode)

(consult-customize
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file consult-xref
   :preview-key (kbd "M-."))


(provide 'init-completion)