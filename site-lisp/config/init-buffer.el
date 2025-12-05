(use-package ibuffer
   :custom
   (ibuffer-saved-filters
    '(("My-Dired"
       (or (mode . dired-mode)
	   (mode . dirvish-mode)))
      ("My-Emacs-Internals"
       (or (name . "^\\*Messages\\*$")
	   (name . "^\\*Help\\*$")
	   (name . "^\\*scratch\\*$")))))
  :config
  (setq ibuffer-expert t)
  (setq ibuffer-display-summary nil)
  (setq ibuffer-use-other-window nil)
  (setq ibuffer-show-empty-filter-groups nil)
  (setq ibuffer-default-sorting-mode 'filename/process)
  (setq ibuffer-title-face 'font-lock-doc-face)
  (setq ibuffer-use-header-line t)
  (setq ibuffer-default-shrink-to-minimum-size nil)
  (setq ibuffer-formats
        '((mark modified read-only locked " "
                (name 30 30 :left :elide)
                " "
                (size 9 -1 :right)
                " "
                (mode 16 16 :left :elide)
                " " filename-and-process)
          (mark " "
                (name 16 -1)
                " " filename))))

(use-package olivetti
  :ensure t
  :hook (ibuffer-mode . olivetti-mode)
  :config
  (setq olivetti-body-width 100))

(use-package all-the-icons-ibuffer
  :hook (ibuffer-mode . all-the-icons-ibuffer-mode))

(use-package ibuffer-vc
 :hook (ibuffer-mode . ibuffer-vc-set-filter-groups-by-vc-root))


(provide 'init-buffer)
