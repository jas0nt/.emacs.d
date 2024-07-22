(require 'dashboard)

(dashboard-setup-startup-hook)
(setq dashboard-center-content t)
(setq dashboard-startup-banner "~/.emacs.d/banners/dark_knight.png")
(setq dashboard-image-banner-max-height 800)
(setq dashboard-items '((recents . 15)
			(projects . 7)
			(bookmarks . 7)))


(provide 'init-dashboard)
