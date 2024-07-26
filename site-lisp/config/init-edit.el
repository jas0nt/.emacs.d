
(use-package undo-tree
  :init
  (global-undo-tree-mode))

(use-package rainbow-mode)

(use-package rainbow-delimiters
  :config
  (rainbow-delimiters-mode)
  (add-hook 'prog-mode-hook #'rainbow-delimiters-mode))

(use-package evil-nerd-commenter)


(provide 'init-edit)
