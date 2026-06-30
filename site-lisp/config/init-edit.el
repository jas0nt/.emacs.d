(use-package markmacro
  :vc (:url "https://github.com/manateelazycat/markmacro" :rev "master")
  :bind
  ("C-c C-m w" . markmacro-mark-words)
  ("C-c C-m W" . markmacro-mark-symbols)
  ("C-c C-m l" . markmacro-mark-lines)
  ("C-c C-m ," . markmacro-apply-all)
  ("C-c C-m ." . markmacro-apply-all-except-first)
  ("C-c C-m m" . markmacro-rect-set)
  ("C-c C-m d" . markmacro-rect-delete)
  ("C-c C-m r" . markmacro-rect-replace)
  ("C-c C-m i" . markmacro-rect-insert)
  ("C-c C-m c" . markmacro-rect-mark-columns)
  ("C-c C-m s" . markmacro-rect-mark-symbols))

(use-package vundo
  :bind ("C-x u" . vundo)
  :config
  (setq vundo-glyph-alist vundo-unicode-symbols))

(use-package rainbow-delimiters
  :config
  (rainbow-delimiters-mode)
  (add-hook 'prog-mode-hook #'rainbow-delimiters-mode))

(use-package rainbow-mode
  :hook (prog-mode . rainbow-mode))

(use-package evil-nerd-commenter)

(use-package expand-region)


(provide 'init-edit)
