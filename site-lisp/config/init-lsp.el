(require 'yasnippet)
(yas-global-mode 1)

(require 'lsp-bridge)
(global-lsp-bridge-mode)
(setq lsp-bridge-nix-lsp-server "nil")

(unless (display-graphic-p)
  (with-eval-after-load 'acm
    (require 'acm-terminal)))

(require 'nix-mode)
(add-to-list 'auto-mode-alist '("\\.nix\\'" . nix-mode))


(provide 'init-lsp)
