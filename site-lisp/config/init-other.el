(use-package all-the-icons-ibuffer
  :hook (ibuffer-mode . all-the-icons-ibuffer-mode))
(use-package ibuffer-vc
  :hook (ibuffer-mode . ibuffer-vc-set-filter-groups-by-vc-root))
(use-package google-this)
(use-package deadgrep)
(use-package ace-window
  :config
  (setq aw-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l)))
(use-package try)


(provide 'init-other)
