;;; init-evil.el -*- lexical-binding: t -*-

(require 'cl-lib)

;; ---------------------------------------------------------------
;; Mode -> state table, with an O(1) cache
;; ---------------------------------------------------------------

(defvar my/evil-mode-states
  '((dired-mode       . none)     ; Evil never enabled
    (comint-mode      . emacs)
    (term-mode        . emacs)
    (eshell-mode      . emacs)
    (vterm-mode       . emacs)
    (eat-mode         . emacs)
    (fundamental-mode . normal)
    (prog-mode        . normal)
    (text-mode        . normal)
    (conf-mode        . normal))
  "Alist of (MAJOR-MODE . EVIL-STATE); first match wins, derived modes included.
`none' means Evil is disabled. Unlisted modes fall back to motion state.")

(defvar my/evil--state-cache (make-hash-table :test #'eq)
  "Cache of major-mode -> Evil state.")

(defun my/evil-reset-state-cache ()
  "Clear the cache. Call this after changing `my/evil-mode-states'."
  (interactive)
  (clrhash my/evil--state-cache))

(defun my/evil-state-for-mode (mode)
  "Return the Evil state for major MODE (always a non-nil symbol)."
  (or (gethash mode my/evil--state-cache)
      (puthash mode
               (or (cl-loop for (m . s) in my/evil-mode-states
                            when (provided-mode-derived-p mode m)
                            return s)
                   'motion)
               my/evil--state-cache)))

;; Evil asks this predicate from every entry point (mode hooks,
;; `set-window-buffer', ...), so one rule covers all of them.
;; Advising a not-yet-defined function is fine, so this can live at top level.
(define-advice evil-disabled-buffer-p (:around (orig &optional buffer) my/modes)
  (let ((buf (get-buffer (or buffer (current-buffer)))))
    (or (and buf
             (eq (my/evil-state-for-mode (buffer-local-value 'major-mode buf))
                 'none))
        (funcall orig buffer))))

(defun my/evil-smart-state ()
  (when (and evil-local-mode (not (minibufferp)))
    (let ((state (my/evil-state-for-mode major-mode)))
      (unless (eq state 'none)
        (evil-change-state state)))))
(add-hook 'after-change-major-mode-hook #'my/evil-smart-state 100)

;; wdired switches modes by hand and does not run
;; `after-change-major-mode-hook', so handle both ends ourselves.
(with-eval-after-load 'wdired
  (advice-add 'wdired-change-to-wdired-mode :after
              (lambda (&rest _)
                (evil-local-mode 1)
                (evil-normal-state)))
  (advice-add 'wdired-change-to-dired-mode :after
              (lambda (&rest _)
                (evil-local-mode -1))))

;; ---------------------------------------------------------------
;; Packages
;; ---------------------------------------------------------------

(use-package evil
  :init
  (setq evil-want-minibuffer nil
        evil-want-integration t
        evil-want-keybinding nil
        evil-disable-insert-state-bindings t
        evil-want-C-i-jump nil
        evil-want-C-u-scroll t
        ;; Native undo (Emacs 28+): no extra package, no overhead.
        ;; Must be set before Evil loads.
        evil-undo-system 'undo-redo
        ;; Don't highlight every match of a search in the window; with
        ;; pinyin expansion that regexp is the most expensive thing here.
        evil-ex-search-highlight-all nil
        evil-ex-interactive-search-highlight 'selected
        ;; No minibuffer message on every state change.
        evil-echo-state nil)
  :config
  (defun cxc/apply-macro-to-lines (reg)
    "Run the macro in register REG on every line of the selection."
    (interactive (list (read-char "Macro register: ")))
    (when (evil-visual-state-p)
      (evil-exit-visual-state))   ; this sets the '< and '> marks
    (evil-ex-execute (format "'<,'>normal @%c" reg)))

  (evil-mode 1)

  (defun cxc/evil-update-cursors (&rest _)
    "Set Evil cursor colors from the current doom theme's palette."
    (when (fboundp 'doom-color)
      (let ((insert (ignore-errors (doom-color 'yellow)))
            (normal (ignore-errors (doom-color 'green)))
            (motion (ignore-errors (doom-color 'violet))))
	(setq evil-insert-state-cursor `(hollow ,(or insert "yellow"))
              evil-normal-state-cursor `(box ,(or normal "green"))
              evil-motion-state-cursor `(box ,(or motion "purple")))
	(when (fboundp 'evil-refresh-cursor)
          (evil-refresh-cursor)))))

  (advice-add 'load-theme :after #'cxc/evil-update-cursors))

(use-package evil-surround
  :after evil
  :defer 0.5
  :config
  (global-evil-surround-mode 1))

(use-package evil-pinyin
  :after evil
  :defer 0.5
  :init
  (setq-default evil-pinyin-scheme 'simplified-xiaohe-all)
  (setq-default evil-pinyin-with-search-rule 'always)
  :config
  (evil-select-search-module 'evil-search-module 'evil-search)
  (global-evil-pinyin-mode))

(use-package evil-exchange
  :after evil
  :defer 0.5
  :config
  (evil-exchange-install))

(use-package evil-smartparens
  :after (evil smartparens)
  :hook (smartparens-enabled . evil-smartparens-mode))

(use-package evil-keypad
  :after evil
  :config
  (setq evil-keypad-activation-states '(normal visual motion emacs))
  (evil-keypad-global-mode 1))

(general-define-key
 :states 'visual
 "@" #'cxc/apply-macro-to-lines)

(general-define-key
 :states '(normal visual)
 "=" 'er/expand-region
 "s" 'cxc/transient-er-mark
 "g=" 'cxc/er-mark
 "g." 'evil-repeat)

(provide 'init-evil)
