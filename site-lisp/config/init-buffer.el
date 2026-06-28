(use-package ibuffer
  ;; :hook (ibuffer-mode . olivetti-mode)
  :bind
  ("C-x C-b" . ibuffer)
  (
   :map ibuffer-mode-map
   ("h" . ibuffer-backward-filter-group)
   ("j" . ibuffer-forward-line)
   ("k" . ibuffer-backward-line)
   ("l" . ibuffer-forward-filter-group)
   ("z" . dired-jump-with-zoxide)
   ("<tab>" . ibuffer-toggle-filter-group))
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

(use-package ibuffer-project
  :after (ibuffer)
  :config
  (add-hook
   'ibuffer-hook
   (lambda ()
     (setq ibuffer-filter-groups (ibuffer-project-generate-filter-groups))
     (unless (eq ibuffer-sorting-mode 'project-file-relative)
       (ibuffer-do-sort-by-project-file-relative)))))

(use-package nerd-icons-ibuffer
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

(use-package ibuffer-vc
 :hook (ibuffer-mode . ibuffer-vc-set-filter-groups-by-vc-root))


(provide 'init-buffer)
