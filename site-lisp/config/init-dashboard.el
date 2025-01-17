(use-package dashboard
  :custom
  (dashboard-center-content t)
  (dashboard-vertically-center-content t)
  (dashboard-image-banner-max-height 1000)
  (dashboard-icon-type 'all-the-icons)
  (dashboard-set-heading-icons t)
  (dashboard-set-file-icons t)
  (dashboard-projects-backend 'projectile)
  (dashboard-items '((recents . 14)
		     (projects . 7)
		     (bookmarks . 7)))
  :config
  (defun my-dashboard-random-banner ()
    "Select a random image from the DIRECTORY to use as the dashboard banner."
    (let* ((directory "~/.emacs.d/banners/")
	   (filter (if (display-graphic-p)
		       ".*\\.png\\|.*\\.jpg\\|.*\\.jpeg\\|.*\\.svg"
		     ".*\\.txt"))
	   (files (directory-files directory t filter))
           (selected (nth (random (length files)) files)))
      (setq dashboard-startup-banner selected)))

  (my-dashboard-random-banner)
  (dashboard-setup-startup-hook))
  

(provide 'init-dashboard)
