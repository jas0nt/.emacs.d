(use-package evil
  :init
  (setq evil-want-minibuffer nil)
  (setq evil-want-integration t) ;; This is optional since it's already set to t by default.
  (setq evil-want-keybinding nil)
  (setq evil-disable-insert-state-bindings t)
  (setq evil-want-C-i-jump nil)
  (setq evil-want-C-u-scroll t)
  (setq evil-insert-state-cursor '(hollow "yellow")
	evil-normal-state-cursor '(box "#50fa7b"))
  :config
  (evil-mode 1)
  (defun my/evil-smart-state ()
    (unless (minibufferp)
      (if (or (derived-mode-p 'prog-mode)
	      (derived-mode-p 'text-mode)
	      (derived-mode-p 'conf-mode))
	  (evil-normal-state)
	(evil-emacs-state))))
  (add-hook 'after-change-major-mode-hook #'my/evil-smart-state))

(use-package evil-snipe
  :after (evil)
  :config
  (evil-snipe-mode +1)
  (evil-snipe-override-mode +1))

(use-package evil-surround
  :config
  (global-evil-surround-mode 1))

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
 "g." 'evil-repeat)


(provide 'init-evil)
