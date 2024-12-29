(use-package yasnippet
  :init
  (yas-global-mode 1))

(use-package popon
  :straight '(popon :type git :repo "https://codeberg.org/akib/emacs-popon.git"))

(use-package acm-terminal
  :after (acm)
  :if (not (display-graphic-p))
  :straight '(acm-terminal :type git :host github :repo "twlz0ne/acm-terminal"))

(use-package lsp-bridge
  :straight '(lsp-bridge :type git :host github :repo "manateelazycat/lsp-bridge"
			 :files (:defaults "*.el" "*.py" "acm" "core" "langserver" "multiserver" "resources")
			 :build (:not compile))
  :init
  (global-lsp-bridge-mode)
  (setq lsp-bridge-nix-lsp-server "nil")
  (setq lsp-bridge-enable-hover-diagnostic t))


(use-package nix-mode
  :mode "\\.nix\\'")


(provide 'init-lsp)
