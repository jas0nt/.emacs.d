;;; init-python.el --- Python -*- lexical-binding: t -*-

;; Defines `python-mode' and populates auto-mode-alist for .py files, so the
;; older elpa `python-mode' package is never loaded (it would only shadow
;; this one, and costs ~0.4s the first time it is required).
(require 'python)

(use-package pyvenv
  :defer t
  :init
  (setenv "WORKON_HOME" "~/.venv")
  :config
  ;; `pyvenv-mode' is a global minor mode, so no per-buffer hook is needed.
  (pyvenv-mode 1)
  ;; Activating a venv at startup costs ~0.1s; do it on the first Python
  ;; buffer instead, and only once.
  (defvar my-pyvenv-initialized nil)
  (defun my-pyvenv-ensure-base ()
    (unless my-pyvenv-initialized
      (setq my-pyvenv-initialized t)
      (pyvenv-workon "base")))
  (add-hook 'python-mode-hook #'my-pyvenv-ensure-base))

(use-package flymake-python-pyflakes
  :defer t)

(provide 'init-python)
;;; init-python.el ends here
