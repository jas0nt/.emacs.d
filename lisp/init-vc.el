;;; init-vc.el --- Version control -*- lexical-binding: t -*-

(use-package magit
  :bind (("C-x C-v" . magit)))

;; `magit-delta' requires magit when it loads, so a bare
;; `(use-package magit-delta)' pulls the whole of magit (~50 features,
;; 0.13s) into the startup path just to make it available.
(use-package magit-delta
  :after magit
  :defer t)

(use-package diff-hl
  :after magit
  :config
  (add-hook 'magit-post-refresh-hook 'diff-hl-magit-post-refresh))

(use-package blamer
  :defer t)

(provide 'init-vc)
;;; init-vc.el ends here
