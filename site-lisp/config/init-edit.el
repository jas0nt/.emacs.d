(use-package markmacro
  :vc (:url "https://github.com/manateelazycat/markmacro" :rev "master")
  :bind
  ("C-c C-m w" . markmacro-mark-words)
  ("C-c C-m W" . markmacro-mark-symboles)
  ("C-c C-m l" . markmacro-mark-lines)
  ("C-c C-m <" . markmacro-apply-all)
  ("C-c C-m >" . markmacro-apply-all-except-first)
  ("C-c C-m m" . markmacro-rect-set)
  ("C-c C-m d" . markmacro-rect-delete)
  ("C-c C-m r" . markmacro-rect-replace)
  ("C-c C-m i" . markmacro-rect-insert)
  ("C-c C-m c" . markmacro-rect-mark-columns)
  ("C-c C-m s" . markmacro-rect-mark-symbols)

  :config
  (dolist (cmd '(markmacro-mark-words
                 markmacro-mark-symboles
                 markmacro-mark-lines
                 markmacro-rect-set
                 markmacro-rect-mark-columns
                 markmacro-rect-mark-symbols
                 markmacro-rect-insert))
    (advice-add cmd :after (lambda (&rest _) (evil-insert-state)))
    (advice-add 'markmacro-apply-all :after (lambda (&rest _) (evil-normal-state)))
    (advice-add 'markmacro-apply-all-except-first :after (lambda (&rest _) (evil-normal-state)))

    (defvar my/recording-macro-map (make-sparse-keymap))
    (add-to-list 'emulation-mode-map-alists
		 `((defining-kbd-macro . ,my/recording-macro-map)))

    (define-key my/recording-macro-map (kbd "<escape>") (lambda ()
							  (interactive)
							  (ignore-errors (markmacro-apply-all))
							  (setq my/markmacro-is-recording nil)
							  (evil-normal-state)))
    (define-key my/recording-macro-map (kbd "C-<escape>") (lambda ()
							  (interactive)
							  (ignore-errors (markmacro-apply-all-except-first))
							  (setq my/markmacro-is-recording nil)
							  (evil-normal-state)))

    ))

(use-package vundo
  :bind ("C-x u" . vundo)
  :config
  (setq vundo-glyph-alist vundo-unicode-symbols))

(use-package rainbow-delimiters
  :config
  (rainbow-delimiters-mode)
  (add-hook 'prog-mode-hook #'rainbow-delimiters-mode))

(use-package rainbow-mode
  :hook (prog-mode . rainbow-mode))

(use-package recentf
  :config
  (recentf-mode 1)
  (setq recentf-max-menu-items 25))

(use-package evil-nerd-commenter)

(use-package expand-region)


(provide 'init-edit)
