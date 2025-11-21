(use-package magit
  :bind
  (("C-x C-v" . magit)))

(use-package magit-delta)

(use-package diff-hl
  :after 'magit
  :config
  (add-hook 'magit-post-refresh-hook 'diff-hl-magit-post-refresh))

(provide 'init-vc)
