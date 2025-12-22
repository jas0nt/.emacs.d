(use-package all-the-icons)

(use-package doom-themes
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (load-theme 'doom-dracula t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))

(use-package doom-modeline
  :after (all-the-icons)
  :init (doom-modeline-mode 1)
  :config
  (setq doom-modeline-major-mode-icon nil)
  (setq doom-modeline-height 1)
  (set-face-attribute 'mode-line nil :family "FiraCode Nerd Font" :height 170)
  (set-face-attribute 'mode-line-inactive nil :family "FiraCode Nerd Font" :height 170))

;; (set-cursor-color "#50fa7b")
;; (defconst jst/modeline-bg (face-attribute 'mode-line :background))
;; (defun jst/flash-mode-line ()
;;   (let ((bell-color "#ff5555"))
;;     (set-face-background 'mode-line bell-color)
;;     (run-with-timer 0.1 nil #'set-face-background 'mode-line jst/modeline-bg)))

;; (setq visible-bell nil
;;       ring-bell-function 'jst/flash-mode-line)

(use-package beacon
  :init
  (setq beacon-color "#50fa7b")
  (beacon-mode 1))


(provide 'init-theme)
