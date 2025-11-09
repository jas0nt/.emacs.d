(use-package projectile
  :init
  (projectile-mode +1)
  :custom
  (projectile-known-projects-file (expand-file-name "projectile-bookmarks.eld" my-emacs-cache-dir))
  (projectile-project-search-path '("~/" "~/code/")))


(provide 'init-project)
