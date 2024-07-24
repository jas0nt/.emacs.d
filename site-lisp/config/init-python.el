(require 'python)

(use-package python-mode
  :mode "\\.py\\'")

(use-package pyvenv
  :config
  ;(pyvenv-mode 1)
  (add-hook 'python-mode-hook #'pyvenv-mode)
  (setenv "WORKON_HOME" "~/.venv")
  (pyvenv-workon "base"))

(use-package flymake-python-pyflakes)


(provide 'init-python)
