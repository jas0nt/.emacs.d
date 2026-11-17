;;; init-edit.el --- Editing helpers -*- lexical-binding: t -*-

(use-package markmacro
  :vc (:url "https://github.com/manateelazycat/markmacro" :rev "master")
  :bind
  ("C-c C-m w" . markmacro-mark-words)
  ("C-c C-m W" . markmacro-mark-symbols)
  ("C-c C-m l" . markmacro-mark-lines)
  ("C-c C-m ," . markmacro-apply-all)
  ("C-c C-m ." . markmacro-apply-all-except-first)
  ("C-c C-m m" . markmacro-rect-set)
  ("C-c C-m d" . markmacro-rect-delete)
  ("C-c C-m r" . markmacro-rect-replace)
  ("C-c C-m i" . markmacro-rect-insert)
  ("C-c C-m c" . markmacro-rect-mark-columns)
  ("C-c C-m s" . markmacro-rect-mark-symbols))

(use-package pcre2el
  :config
  (pcre-mode 1))

(use-package vundo
  :bind ("C-x u" . vundo)
  :config
  (setq vundo-glyph-alist vundo-unicode-symbols))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; `rainbow-mode' colours colour literals in the buffer; running it in every
;; prog-mode buffer just makes it scan code for nothing.
(use-package rainbow-mode
  :hook ((css-mode html-mode svg-mode scss-mode less-css-mode) . rainbow-mode))

(use-package evil-nerd-commenter)

(use-package evil-matchit
  :defer t)

(use-package expand-region
  :init
  (setq expand-region-fast-keys-enabled t)
  :config
  (defun my/er-expand ()
    "Expand region, then keep expanding with `m' and contracting with `n'."
    (interactive)
    (er/expand-region 1)
    (set-transient-map
     (let ((map (make-sparse-keymap)))
       (define-key map (kbd "s") #'er/expand-region)
       (define-key map (kbd "S") #'er/contract-region)
       map)
     t)))

(use-package hideshow
  :hook (prog-mode . hs-minor-mode)
  :bind (:map hs-minor-mode-map
         ("C-c TAB" . hs-toggle-hiding)))


(provide 'init-edit)
;;; init-edit.el ends here
