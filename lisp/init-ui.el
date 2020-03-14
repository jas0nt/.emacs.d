;;not show tool bar
(tool-bar-mode -1)

;;not show scroll bar
(scroll-bar-mode -1)

;;not show menu bar
(menu-bar-mode -1)

;;show line number
(global-linum-mode t)

;;not show welcome page
(setq inhibit-splash-screen t)

;;default open with full screen
(setq initial-frame-alist (quote ((fullscreen . maximized))))

;;set cursor type
(setq-default cursor-type 'box)
(set-cursor-color "#ff69b4")
(blink-cursor-mode 0)

;;show match ()
(add-hook 'emacs-lisp-mode-hook 'show-paren-mode)

;;show parent fun
(defadvice show-paren-function (around fix-show-paren-function activate)
  (cond ((looking-at-p "\\s(") ad-do-it)
	(t (save-excursion
	     (ignore-errors (backward-up-list))
	     ad-do-it)))
  )

;;highlight current line
(global-hl-line-mode)


(provide 'init-ui)
