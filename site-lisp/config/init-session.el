(setq desktop-path (list desktop-dirname)
      desktop-base-file-name "emacs-desktop"
      desktop-save t
      desktop-load-locked-desktop t
      desktop-auto-save-timeout 30)

(desktop-save-mode 1)
(save-place-mode 1)


(provide 'init-session)
