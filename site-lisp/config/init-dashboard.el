(use-package dashboard
  :init
  (setq dashboard-center-content t)
  (setq dashboard-startup-banner "~/.emacs.d/banners/dark_knight.png")
  (setq dashboard-image-banner-max-height 800)
  (setq dashboard-projects-backend 'projectile)
  (setq dashboard-items '((recents . 14)
			    (projects . 7)
			    (bookmarks . 7))))
  (dashboard-setup-startup-hook)


(provide 'init-dashboard)
