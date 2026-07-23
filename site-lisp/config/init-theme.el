(use-package doom-themes
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (load-theme 'doom-dracula t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))

(use-package nerd-icons)

(use-package beacon
  :custom
  (beacon-color "#50fa7b")
  (beacon-size 20)
  :init
  (beacon-mode 1))


(provide 'init-theme)
