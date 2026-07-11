;;; init-term.el --- Terminal configuration -*- lexical-binding: t -*-

(use-package ghostel
  :config
  ;; -----------------------------------------------------------------------
  ;; Custom commands
  ;; -----------------------------------------------------------------------
  (defun my-ghostel-send-C-k-and-kill ()
    "Send `C-k' to Ghostel, also saving the killed text to the kill ring."
    (interactive)
    (kill-ring-save (point) (line-end-position))
    (ghostel-send-key "k" "ctrl"))

  ;; -----------------------------------------------------------------------
  ;; Project integration
  ;; -----------------------------------------------------------------------
  (add-to-list 'project-switch-commands '(ghostel-project "Ghostel") t)
  (add-to-list 'project-switch-commands '(ghostel-project-list-buffers "Ghostel buffers") t)

  ;; -----------------------------------------------------------------------
  ;; Eval commands (open files/magit from inside the terminal)
  ;; -----------------------------------------------------------------------
  (add-to-list 'ghostel-eval-cmds '("magit-status-setup-buffer" magit-status-setup-buffer))

  :bind
  (("C-`" . ghostel)
   :map ghostel-semi-char-mode-map
   ("C-`" . my-prev-buffer)
   ("C-s" . consult-line)
   ("C-k" . my-ghostel-send-C-k-and-kill)))

(provide 'init-term)
;;; init-term.el ends here
