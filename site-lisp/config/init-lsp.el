(use-package markdown-mode)

(use-package yasnippet
  :init
  (yas-global-mode 1))

(require 'lsp-bridge)
(global-lsp-bridge-mode)

(use-package nix-mode
  :mode "\\.nix\\'")


(provide 'init-lsp)
