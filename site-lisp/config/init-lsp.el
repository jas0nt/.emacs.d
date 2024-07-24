(use-package yasnippet
  :init
  (yas-global-mode 1))

(require 'lsp-bridge)
(global-lsp-bridge-mode)
(setq lsp-bridge-nix-lsp-server "nil")

;(use-package lsp-bridge
;  :straight '(lsp-bridge :type git :host github :repo "manateelazycat/lsp-bridge"
;            :files (:defaults "*.el" "*.py" "acm" "core" "langserver" "multiserver" "resources")
;            :build (:not compile))
;  :init
;  (global-lsp-bridge-mode)
;  (setq lsp-bridge-nix-lsp-server "nil"))


(use-package acm-terminal
  :after (acm)
  :if (not (display-graphic-p)))

(use-package nix-mode
  :mode "\\.nix\\'")


(provide 'init-lsp)
