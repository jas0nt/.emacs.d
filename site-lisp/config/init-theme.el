(use-package all-the-icons)

(use-package dracula-theme
  :init
  (load-theme 'dracula t))

(use-package doom-modeline
  :after (all-the-icons)
  :init (doom-modeline-mode 1)
  :config
  (setq doom-modeline-major-mode-icon nil)
  (setq doom-modeline-height 1)
  (set-face-attribute 'mode-line nil :family "FiraCode Nerd Font" :height 120)
  (set-face-attribute 'mode-line-inactive nil :family "FiraCode Nerd Font" :height 120))


(defconst jst/modeline-bg (face-attribute 'mode-line :background))
(defun jst/flash-mode-line ()
  (let ((bell-color "#ff5555"))
    (set-face-background 'mode-line bell-color)
    (run-with-timer 0.1 nil #'set-face-background 'mode-line jst/modeline-bg)))

(setq visible-bell nil
  ring-bell-function 'jst/flash-mode-line)


(provide 'init-theme)
