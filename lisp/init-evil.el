;;; init-evil.el -*- lexical-binding: t -*-

(require 'cl-lib)

(defvar evil-local-mode)
(declare-function evil-change-state "evil-core")
(declare-function evil-refresh-cursor "evil-core")

;; ---------------------------------------------------------------
;; Mode -> state table (cached)
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
(define-advice evil-disabled-buffer-p (:around (orig &optional buffer) my/modes)
  (let ((buf (get-buffer (or buffer (current-buffer)))))
    (or (and buf
             (eq (my/evil-state-for-mode (buffer-local-value 'major-mode buf))
                 'none))
        (funcall orig buffer))))

(defun my/evil-smart-state ()
  "Switch to the Evil state configured for the current major mode."
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
;; State colors (shared by the cursor and the mode line)
;; ---------------------------------------------------------------

(defun cxc/evil-state-color (state)
  "Return the doom palette color for Evil STATE."
  (or (and (fboundp 'doom-color)
           (ignore-errors
             (doom-color (pcase state
                           ('insert 'yellow)
                           ('normal 'green)
                           ('motion 'violet)
                           (_       'cyan)))))
      (face-foreground 'default nil t)))

(defun cxc/evil-update-cursors (&rest _)
  "Set Evil cursor colors from the current theme."
  (setq evil-insert-state-cursor `(hollow ,(cxc/evil-state-color 'insert))
        evil-normal-state-cursor `(box    ,(cxc/evil-state-color 'normal))
        evil-motion-state-cursor `(box    ,(cxc/evil-state-color 'motion)))
  (when (fboundp 'evil-refresh-cursor)
    (evil-refresh-cursor)))

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
        ;; Native undo (Emacs 28+). Must be set before Evil loads.
        evil-undo-system 'undo-redo
        ;; Highlighting every match is expensive with pinyin expansion.
        evil-ex-search-highlight-all nil
        evil-ex-interactive-search-highlight 'selected
        evil-echo-state nil)
  :config
  (evil-mode 1)

  (defun cxc/apply-macro-to-lines (reg)
    "Run the macro in register REG on every line of the selection."
    (interactive (list (read-char "Macro register: ")))
    (when (evil-visual-state-p)
      (evil-exit-visual-state))         ; sets the '< and '> marks
    (evil-ex-execute (format "'<,'>normal @%c" reg)))

  (with-eval-after-load 'evil
    ;; Swap [ <-> {  and  ] <-> }
    (dolist (state '(normal visual motion))
      (let ((map (symbol-value (intern (format "evil-%s-state-map" state)))))
	;; Save the original bindings first so they aren't overwritten during the swap
	(let ((lb  (lookup-key map "["))
              (rb  (lookup-key map "]"))
              (lbr (lookup-key map "{"))
              (rbr (lookup-key map "}")))
          (define-key map "[" lbr)
          (define-key map "]" rbr)
          (define-key map "{" lb)
          (define-key map "}" rb)))))

  (advice-add 'load-theme :after #'cxc/evil-update-cursors)
  (cxc/evil-update-cursors))            ; theme already loaded at this point

(use-package evil-surround
  :after evil
  :defer 0.5
  :config
  (global-evil-surround-mode 1))

(use-package evil-pinyin
  :after evil
  :defer 0.5
  :init
  (setq-default evil-pinyin-scheme 'simplified-xiaohe-all
                evil-pinyin-with-search-rule 'always)
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
 "g." #'evil-repeat
 "s" #'my/er-expand)


(provide 'init-evil)
