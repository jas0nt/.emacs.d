;;; init-completion.el --- Completion configuration -*- lexical-binding: t -*-

;; -----------------------------------------------------------------------
;; In-Buffer Completion (Corfu)
;; -----------------------------------------------------------------------
(use-package corfu
  :init
  (global-corfu-mode)
  :custom
  (corfu-auto t)                 ; Enable auto completion
  (corfu-cycle t)                ; Enable cycling for `corfu-next/previous'
  (corfu-preselect 'prompt)      ; Always preselect the prompt
  (corfu-quit-no-match 'separator) ; Quit if no match (easier to type new things)
  
  ;; Optional: optimize display for speed
  ;; (corfu-echo-documentation nil) 
  
  :bind
  (:map corfu-map
        ("TAB" . corfu-next)
        ([tab] . corfu-next)
        ("S-TAB" . corfu-previous)
        ([backtab] . corfu-previous)))

;; Add icons to the completion popup (optional, looks great)
(use-package kind-icon
  :ensure t
  :after corfu
  :custom
  (kind-icon-default-face 'corfu-default)
  :config
  (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

;; -----------------------------------------------------------------------
;; Minibuffer Completion (Vertico + Orderless)
;; -----------------------------------------------------------------------

(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

(use-package vertico
  :init
  (vertico-mode))

(use-package marginalia
  :init
  (marginalia-mode t))

;; -----------------------------------------------------------------------
;; Actions & Context Menu (Embark)
;; -----------------------------------------------------------------------

(use-package embark
  :ensure t
  :bind
  (("C-." . embark-act)         ;; The main trigger
   ("C-;" . embark-dwim)        ;; "Do What I Mean"
   ("C-h B" . embark-bindings)) ;; Alternative for `describe-bindings`
  :init
  ;; Replace the key help with a completing-read interface
  (setq prefix-help-command #'embark-prefix-help-command)
  :config
  ;; Hide the mode line of the Embark live/completions buffers
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none)))))

(use-package embark-consult
  :ensure t
  :after (embark consult)
  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

;; -----------------------------------------------------------------------
;; Core Emacs Completion Tweaks
;; -----------------------------------------------------------------------

(use-package dabbrev
  ;; Swap M-/ and C-M-/
  :bind (("M-/" . dabbrev-completion)
         ("C-M-/" . dabbrev-expand)))

(use-package emacs
  :init
  ;; TAB cycle if there are only few candidates
  (setq completion-cycle-threshold 3)
  ;; TAB tries to indent, then completes
  (setq tab-always-indent 'complete))

(use-package savehist
  :init
  (savehist-mode)
  :custom
  (savehist-file (expand-file-name "history" my-emacs-cache-dir)))

;; -----------------------------------------------------------------------
;; Consult & Search
;; -----------------------------------------------------------------------

(use-package consult)
(use-package consult-projectile)
(use-package posframe)

(provide 'init-completion)
