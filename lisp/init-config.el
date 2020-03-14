;;custom file
(setq custom-file (expand-file-name "lisp/custom.el" user-emacs-directory))
(load-file custom-file)

;;configs

;;ido mode
(setq indo-enable-flex-matching t)
(setq ido-everywhere t)
(ido-mode t)

;;buffer
(defalias 'list-buffers 'ibuffer)

;;diable error tone
(setq ring-bell-function 'ignore)

;;set no backup file
(setq make-backup-files nil)
(setq auto-save-default nil)

;;shortcut
(setq-default abbrev-mode t)
(define-abbrev-table 'global-abbrev-table '(
					    ("j" "jason")
					    ))

;;show recent file
(recentf-mode 1)
(setq recentf-max-menu-items 15)

;;delete selection
(delete-selection-mode 1)

;;paste from clipboard
(setq x-select-enable-clipboard t)

;;replace Yes/No with y/n
(fset 'yes-or-no-p 'y-or-n-p)

;;only open one buffer in dired mode
(put 'dired-find-alternate-file 'disabled nil)

;; lazy load
(with-eval-after-load 'dired
    (define-key dired-mode-map (kbd "RET") 'dired-find-alternate-file))


(provide 'init-config)
