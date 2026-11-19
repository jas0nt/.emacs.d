;;; init-edit.el --- Editing helpers -*- lexical-binding: t -*-

;; Keep markmacro's commands in one prefix map so that the global `C-c C-m'
;; binding and orbyte's Normal-state `m' (see init-orbyte.el) stay in sync.
;; A keymap variable is not followed when used as a prefix key, so give the
;; symbol a keymap function definition as well.
(defvar-keymap markmacro-command-map
  :doc "Prefix map for markmacro commands."
  "w" #'markmacro-mark-words
  "W" #'markmacro-mark-symbols
  "l" #'markmacro-mark-lines
  "," #'markmacro-apply-all
  "." #'markmacro-apply-all-except-first
  "m" #'markmacro-rect-set
  "d" #'markmacro-rect-delete
  "r" #'markmacro-rect-replace
  "i" #'markmacro-rect-insert
  "c" #'markmacro-rect-mark-columns
  "s" #'markmacro-rect-mark-symbols)
(fset 'markmacro-command-map markmacro-command-map)

(use-package markmacro
  :vc (:url "https://github.com/manateelazycat/markmacro" :rev "master")
  :demand t
  :bind ("C-c C-m" . markmacro-command-map))

(use-package pcre2el
  :config
  (pcre-mode 1)

  ;; Emacs 29.1 and later highlight `query-replace-regexp' matches live
  ;; while the regexp is being typed, through
  ;; `minibuffer-lazy-highlight-setup'.
  ;; That preview is built straight from the minibuffer text, outside
  ;; `read-regexp', so `pcre-mode' does not translate it: typing "\d"
  ;; previews a literal "d" even though the replacement that follows
  ;; uses the translated `[[:digit:]]'.  Translate the preview string
  ;; as well, but leave isearch's own minibuffer editing alone.
  (defun my/pcre-lazy-highlight-transform (orig &rest args)
    (when (and pcre-mode
               (not isearch-mode)
               (eq (plist-get args :regexp) t)
               (null (plist-get args :regexp-function)))
      (let ((transform (or (plist-get args :transform) #'identity)))
        (plist-put args :transform
                   (lambda (string)
                     (let ((from (funcall transform string)))
                       (condition-case nil
                           (pcre-to-elisp/cached from)
                         (error from)))))))
    (apply orig args))

  (when (and (fboundp 'minibuffer-lazy-highlight-setup)
             (not (advice-member-p #'my/pcre-lazy-highlight-transform
                                   'minibuffer-lazy-highlight-setup)))
    (advice-add 'minibuffer-lazy-highlight-setup :around
                #'my/pcre-lazy-highlight-transform)))

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
