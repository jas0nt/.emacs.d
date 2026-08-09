(use-package markdown-mode)

(use-package yasnippet
  :init
  (yas-global-mode 1))

(use-package lsp-bridge
  :disabled t
  :vc (:url "https://github.com/manateelazycat/lsp-bridge" :rev "master")
  :config
  (global-lsp-bridge-mode))

(use-package nix-mode
  :mode "\\.nix\\'")


(provide 'init-lsp-bridge)
