;;; eglot-config.el --- Eglot config migrated from lsp-bridge -*- lexical-binding: t; -*-

(use-package eglot
  :ensure nil
  :hook ((python-mode         . eglot-ensure)
         (python-ts-mode      . eglot-ensure)
         (rust-mode           . eglot-ensure)
         (rust-ts-mode        . eglot-ensure)
         (sh-mode             . eglot-ensure))
  :custom
  (eglot-report-progress nil)            ;; less UI noise
  (eglot-autoshutdown t)                 ;; kill server when last buffer closes
  (eglot-sync-connect nil)               ;; connect asynchronously
  (eglot-events-buffer-size 0)           ;; disable event log (set >0 to debug)
  (eglot-extend-to-xref t)
  (eglot-send-changes-idle-time 0.3)     ;; debounce for sending changes
  :bind (:map eglot-mode-map
              ("C-c l r" . eglot-rename)
              ("C-c l a" . eglot-code-actions)
              ("C-c l f" . eglot-format-buffer)
              ("C-c l d" . eldoc)
              ("C-c l i" . eglot-find-implementation)
              ("C-c l t" . eglot-find-typeDefinition)
              ("C-c l n" . flymake-goto-next-error)
              ("C-c l p" . flymake-goto-prev-error)
              ("M-."     . xref-find-definitions)
              ("M-,"     . xref-go-back))
  :config
  ;; explicit server declarations, add/remove as needed
  (add-to-list 'eglot-server-programs
               '((python-mode python-ts-mode) . ("pyright-langserver" "--stdio")))
  (add-to-list 'eglot-server-programs
               '((rust-mode rust-ts-mode) . ("rust-analyzer")))

  ;; format on save (remove hook per-mode if unwanted)
  (defun my-eglot-format-on-save ()
    (add-hook 'before-save-hook #'eglot-format-buffer nil t))
  (add-hook 'eglot-managed-mode-hook #'my-eglot-format-on-save))

(use-package flymake
  :ensure nil
  :hook (eglot-managed-mode . flymake-mode)
  :custom
  (flymake-no-changes-timeout 0.5)
  (flymake-fringe-indicator-position 'right-fringe))

(use-package eldoc
  :ensure nil
  :custom
  (eldoc-echo-area-use-multiline-p nil)
  (eldoc-idle-delay 0.2))

(use-package consult-eglot
  :after (eglot consult)
  :bind (:map eglot-mode-map
              ("C-c s" . consult-eglot-symbols)))

(use-package yasnippet
  :hook (eglot-managed-mode . yas-minor-mode))

;;; Performance tuning
(setq read-process-output-max (* 1024 1024))  ;; 1MB, improves LSP throughput
(setq gc-cons-threshold (* 100 1024 1024))    ;; fewer GC pauses

(provide 'init-lsp)
;;; init-lsp.el ends here
