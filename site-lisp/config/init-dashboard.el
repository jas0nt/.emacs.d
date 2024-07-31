(use-package dashboard
  :custom
  (dashboard-center-content t)
  (dashboard-vertically-center-content t)
  (dashboard-image-banner-max-height 800)
  (dashboard-icon-type 'all-the-icons)
  (dashboard-set-heading-icons t)
  (dashboard-set-file-icons t)
  (dashboard-projects-backend 'projectile)
  (dashboard-items '((recents . 14)
		     (projects . 7)
		     (bookmarks . 7)))
  :config
  (defun my-dashboard-random-banner (directory)
    "Select a random image from the DIRECTORY to use as the dashboard banner."
    (let* ((files (directory-files directory t ".*\\.png\\|.*\\.jpg\\|.*\\.jpeg\\|.*\\.svg"))
           (selected (nth (random (length files)) files)))
      (setq dashboard-startup-banner selected)))
  ;; Set the directory containing your banner images
  (setq my-banner-directory "~/.emacs.d/banners/")
  ;; Call the function to select a random image
  (my-dashboard-random-banner my-banner-directory)
  (dashboard-setup-startup-hook))
  

(provide 'init-dashboard)
