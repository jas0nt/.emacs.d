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

(use-package evil-keypad
  :after evil
  :config
  (setq evil-keypad-activation-states '(normal visual emacs))
  (evil-keypad-global-mode 1))


(general-define-key
 :states '(normal visual)
 "=" 'er/expand-region
 "gl" 'evil-avy-goto-line
 "g/" 'evil-avy-goto-char-timer
 "gw" 'ace-window
 "gn" 'evil-next-buffer
 "gp" 'evil-prev-buffer
 "g." 'evil-repeat
 ";" 'switch-to-buffer
 "," 'evil-switch-to-windows-last-buffer)


(provide 'init-evil)
