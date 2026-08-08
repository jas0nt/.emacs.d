(use-package doom-themes
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (load-theme 'doom-dracula t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))

(setq-default mode-line-format
	      '("%e"
		mode-line-front-space
		;; Modified / read-only / unmodified indicator
		mode-line-modified
		"  "
		;; File name (without path), or buffer name if not visiting a file
		(:propertize (:eval (if buffer-file-name
					(file-name-nondirectory buffer-file-name)
				      (buffer-name)))
			     face mode-line-buffer-id)
		"  |  "
		;; Line:column
		(:propertize "%l:%c" face font-lock-keyword-face)
		mode-line-format-right-align  ;; everything after this is right-aligned
		;; Major mode name
		mode-name
		"  |  "
		;; Misc info: includes global-mode-string
		mode-line-misc-info
		" "))

;; ;; Remove mode-line top/bottom borders and background
(set-face-attribute 'mode-line nil :box nil :background 'unspecified)
(set-face-attribute 'mode-line-inactive nil :box nil :background 'unspecified)


(use-package nerd-icons)

(use-package pulsar
  :custom
  (pulsar-pulse t)
  (pulsar-delay 0.05)
  (pulsar-iterations 10)
  :config
  (defface my-pulsar-face
    `((t :background ,(face-attribute 'success :foreground nil t)))
    "Pulse highlight color, auto-derived from current theme's face.")
  (setq pulsar-face 'my-pulsar-face)
  (pulsar-global-mode 1)
  (advice-add 'keyboard-quit :before #'pulsar-pulse-line))


(provide 'init-theme)
