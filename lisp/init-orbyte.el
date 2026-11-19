;;; init-orbyte.el --- orbyte configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; orbyte lives in site-lisp.  Cursor shapes, mode-line indicators, keypad
;; keys and the Insert/search behaviour are fixed in the package, so only
;; the mode list and personal key bindings live here.

;;; Code:

(use-package orbyte
  :ensure nil
  :load-path "site-lisp"
  :demand t
  :bind
  ((:map orbyte-normal-map
         ("s" . my/er-expand)
         ("m" . markmacro-command-map)
         ("K" . (lambda ()
		  (interactive)
		  (if-let ((word (thing-at-point 'word t)))
		      (bing-dict-brief word)
		    (user-error "No word at point")))))
   (:map orbyte-g-map
         ("l" . avy-goto-line)
         ("m" . evilmi-jump-items-native))
   (:map orbyte-motion-map
         ("j" . next-line)
         ("k" . previous-line)))
  :config
  ;; Normal state for modes that edit text.  Motion state is picked
  ;; automatically for buffers where letters do not insert text (dired, help,
  ;; magit, ...), so SPC is the leader there too; terminals are excluded by
  ;; the package.  Set before enabling the global mode, since the state of
  ;; existing buffers is chosen when it is turned on.
  (setq orbyte-modes '(text-mode
                       prog-mode
                       conf-mode
                       fundamental-mode))
  ;; Search highlights are buffer-local hi-lock patterns.  Clear them when
  ;; leaving the editing states for a state that has no `n'/`N' bindings.
  (defun my/orbyte-clear-search-highlight ()
    (unless (or orbyte-normal-mode orbyte-insert-mode)
      (when (fboundp 'orbyte-clear-search-highlight)
        (orbyte-clear-search-highlight))))
  (add-hook 'orbyte-normal-mode-hook #'my/orbyte-clear-search-highlight)
  (add-hook 'orbyte-insert-mode-hook #'my/orbyte-clear-search-highlight)
  (orbyte-global-mode 1))

(provide 'init-orbyte)
;;; init-orbyte.el ends here
