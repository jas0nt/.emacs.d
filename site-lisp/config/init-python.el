(require 'python)
(require 'python-mode)
(require 'pyvenv)

(add-to-list 'auto-mode-alist '("\\.py\\'" . python-mode))
(add-hook 'python-mode-hook #'pyvenv-mode)
(setenv "WORKON_HOME" "~/.venv")

(pyvenv-workon "base")

(provide 'init-python)