(use-package eglot
  :ensure t
  :hook
  ((python-mode-hook
    nix-mode-hook
    rustic-mode-hook) . eglot-ensure)
  :config
  ;; (add-to-list 'eglot-server-programs '(python-mode . ("pyright")))
  ;; Optional: Format code on save
  (add-hook 'python-mode-hook (lambda () (add-hook 'before-save-hook 'eglot-format-buffer nil t))))


(use-package yasnippet
  :init
  (yas-global-mode 1))

(use-package nix-mode
  :mode "\\.nix\\'")


(provide 'init-lsp)
