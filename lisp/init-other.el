;;; init-other.el --- Miscellaneous packages -*- lexical-binding: t -*-

;; Everything here is invoked on demand; only the keybindings/autoloads
;; should exist at startup.
(use-package google-this
  :defer t)

(use-package deadgrep
  :defer t)

(use-package fzf
  :defer t
  :config
  (setq fzf/args "-x --color bw --print-query --margin=1,0 --no-hscroll"
        fzf/executable "fzf"
        fzf/git-grep-args "-i --line-number %s"
        fzf/grep-command "rg --no-heading -nH"
        fzf/position-bottom t
        fzf/window-height 15))

(use-package ace-window
  :defer t
  :config
  (setq aw-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l)))

(use-package try
  :defer t)

(provide 'init-other)
;;; init-other.el ends here
