(use-package evil
  :init
  (setq evil-want-integration t) ;; This is optional since it's already set to t by default.
  (setq evil-want-keybinding nil)
  (setq evil-disable-insert-state-bindings t)
  (setq evil-want-C-i-jump nil)
  (setq evil-want-C-u-scroll t)
  :config
  (evil-mode 1)
  (setq evil-insert-state-cursor '(hollow "yellow")
      evil-normal-state-cursor '(box "#50fa7b")))

(use-package evil-collection
  :after (evil)
  :init
  (setq evil-collection-company-use-tng nil)
  :config
  (evil-collection-init))

(use-package evil-snipe
  :after (evil)
  :config
  (evil-snipe-mode +1)
  (evil-snipe-override-mode +1))

(use-package evil-surround
  :ensure t
  :config
  (global-evil-surround-mode 1))

(use-package evil-nerd-commenter
  :after (evil))

(use-package evil-pinyin
  :after (evil)
  :init
  (setq-default evil-pinyin-scheme 'simplified-xiaohe-all)
  (setq-default evil-pinyin-with-search-rule 'always)
  :config
  (evil-select-search-module 'evil-search-module 'evil-search)
  (global-evil-pinyin-mode))

(use-package evil-exchange
  :after (evil)
  :config
  (evil-exchange-install))

(use-package evil-smartparens
  :after (evil smartparens)
  :hook (smartparens-enabled-hook . evil-smartparens-mode))

(use-package god-mode)


(defconst my-leader-key "<SPC>")
(general-create-definer my-leader-def
  :states '(normal insert visual emacs)
  :keymaps 'override
  :prefix my-leader-key
  :non-normal-prefix "C-,")

(general-define-key
 :states '(normal visual)
 "gl" 'evil-avy-goto-line
 "gn" 'evil-next-buffer
 "gp" 'evil-prev-buffer
 "g." 'evil-repeat
 ";" 'switch-to-buffer
 "," 'evil-switch-to-windows-last-buffer)

;; Define generic function
(defun my/god-execute-with-key (key)
  "Invoke `god-execute-with-current-bindings` and simulate pressing KEY."
  (interactive)
  (call-interactively 'god-execute-with-current-bindings)
  (setq unread-command-events (listify-key-sequence key)))

;; Bind keys dynamically
(dolist (key-command '(("x" . "x")
                       ("c" . "c")
                       ("h" . "h")
                       ("m" . "g")))
  (let ((key (car key-command))
        (simulated-key (cdr key-command)))
    (eval
     `(my-leader-def
       ,key
       (lambda () (interactive) (my/god-execute-with-key ,simulated-key))))))

(my-leader-def
  "<SPC>" 'execute-extended-command
  "q" '(jst/kill-current-buffer :wk "kill-buffer")
  "e" 'dirvish-side
  "/" 'evilnc-comment-or-uncomment-lines
  "f" 'my-transient-file
  "j" 'my-transient-jump
  "<ESC>" 'my-transient-quit
  "s" 'my-transient-search
  "w" 'my-transient-window)


(provide 'init-evil)
