(require 'undo-tree)
(require 'rainbow-mode)
(require 'rainbow-delimiters)


(rainbow-delimiters-mode)
(add-hook 'prog-mode-hook #'rainbow-delimiters-mode)

(global-undo-tree-mode)


(provide 'init-edit)