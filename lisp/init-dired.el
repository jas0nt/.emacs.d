;;; init-dired.el --- Dired configuration -*- lexical-binding: t -*-

(use-package dired
  :ensure nil ; Built-in package
  :custom
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-movement-style 'bounded-files)
  (dired-dwim-target t)
  (dired-listing-switches
   "-l --almost-all --human-readable --group-directories-first --no-group")
  (dired-free-space nil)
  :hook (dired-mode . hl-line-mode)
  :config
  (put 'dired-find-alternate-file 'disabled nil)

  ;; -----------------------------------------------------------------------
  ;; Open file
  ;; -----------------------------------------------------------------------
  (defun my-dired-do-open-current-only ()
    "Open the file at point using an external app, ignoring any marked files."
    (interactive)
    (let ((dired-marker-char ?\0))
      (dired-do-open)))

  ;; -----------------------------------------------------------------------
  ;; Misc toggles menu
  ;; -----------------------------------------------------------------------
  (transient-define-prefix my-dired-toggle-transient ()
    [
     ["Toggle"
      :if-derived 'dired-mode
      ("t" "Tab new"     dired-tabs-new)
      ("c" "Tab close"   dired-tabs-close)
      ("T" "thumbnail"   media-thumbnail-dired-mode)
      ("d" "detail"      dired-hide-details-mode)
      ("u" "du"          dired-du-mode)
      ("g" "git"         dired-k)
      ("p" "preview"     dired-preview-global-mode)
      ("s" "script mode" satchel-toggle-script-mode)]
     ["Thumbnail"
      :if-derived 'dired-mode
      ("j" "Next Line"    dired-next-line :transient t)
      ("k" "Prev Line"    dired-previous-line :transient t)
      ("l" "Forward 5%"   (lambda () (interactive) (my-ready-player--adjust-thumbnail-percent 5)) :transient t)
      ("h" "Backward 5%"  (lambda () (interactive) (my-ready-player--adjust-thumbnail-percent -5)) :transient t)
      ("L" "Forward 1%"   (lambda () (interactive) (my-ready-player--adjust-thumbnail-percent 1)) :transient t)
      ("H" "Backward 1%"  (lambda () (interactive) (my-ready-player--adjust-thumbnail-percent -1)) :transient t)
      ("P" "batch generate" my-ready-player-batch-generate-thumbnails)]
     ["Actions"
      ("q" "Quit" transient-quit-all)]
     ])

  :bind
  ("C-x C-d" . (lambda () (interactive) (dired default-directory)))
  (:map dired-mode-map
        ("<SPC>" . evil-keypad-start)
        ("q"     . dired-tabs-toggle)
        ("<f5>"  . revert-buffer)
        ("C"     . dired-do-compress-to)
        ("t"     . my-dired-toggle-transient)

        ;; Navigation
        ("h" . dired-up-directory)
        ("j" . dired-next-line)
        ("k" . dired-previous-line)
        ("l" . dired-find-file)
        ("]" . scroll-up-command)
        ("[" . scroll-down-command)
        ("'" . bookmark-jump)
        ("z" . dired-jump-with-zoxide)
        ("/" . consult-line)
        ("f" . consult-fd)

        ;; Open
        ("<RET>"      . my-dired-do-open-current-only)
        ("C-<return>" . dired-do-open)
        ("`"          . dired-shortcuts-open-terminal)
        ("O"          . dired-do-shell-command)

        ;; Create
        ("a" . dired-create-empty-file)
        ("A" . dired-create-directory)

        ;; Edit mode
        ("r" . wdired-change-to-wdired-mode)))

(use-package dired-shortcuts
  :ensure nil
  :load-path "site-lisp"
  :demand t
  :after dired
  :bind
  (:map dired-mode-map
	("c" . dired-shortcuts-copy-transient)
	("n" . dired-shortcuts-goto-transient)
	("o" . dired-shortcuts-open-transient)))

(use-package dired-tabs
  :ensure nil
  :load-path "site-lisp"
  :demand t
  :custom
  (dired-tabs-save-file (expand-file-name "dired-tabs" my-emacs-cache-dir))
  :bind
  (:map dired-mode-map
	("1" . dired-tabs-goto) ("2" . dired-tabs-goto) ("3" . dired-tabs-goto)
	("4" . dired-tabs-goto) ("5" . dired-tabs-goto) ("6" . dired-tabs-goto)
	("7" . dired-tabs-goto) ("8" . dired-tabs-goto) ("9" . dired-tabs-goto)
	("0" . dired-tabs-goto) ("H" . dired-tabs-prev) ("L" . dired-tabs-next)
	("{" . dired-tabs-move-left) ("}" . dired-tabs-move-right)))

(use-package dired-satchel
  :ensure nil
  :load-path "site-lisp"
  :after dired
  :commands (satchel-toggle-script-mode)
  :bind
  (:map dired-mode-map
        ("d" . satchel-action-flag-deletion)
        ("y" . satchel-pack)
        ("Y" . satchel-unpack)
        ("p" . satchel-action-copy-here)
        ("P" . satchel-action-move-here)
        ("x" . satchel-action-execute)
        ("v" . satchel-transient)))

(use-package media-thumbnail
  :after dired
  :custom
  (media-thumbnail-max-processes 4)
  (media-thumbnail-cache-dir
   (expand-file-name "media-thumbnails/" my-emacs-cache-dir))
  :config
  (with-eval-after-load 'media-thumbnail
    (declare-function ready-player--cached-thumbnail-path "ready-player")

    (defun my-media-thumbnail-get-cache-path (file)
      "Reuse `ready-player's thumbnail cache path/naming, so both
packages share the exact same cached thumbnail file on disk."
      ;; (require 'ready-player)
      (ready-player--cached-thumbnail-path (expand-file-name file)))
    (advice-add 'media-thumbnail-get-cache-path :override
		#'my-media-thumbnail-get-cache-path)))

(use-package dired-preview
  :after dired
  :custom
  (dired-preview-delay 0.3)
  (dired-preview-max-size (* 50 1024 1024))
  :config
  (dolist (cmd '(revert-buffer
		 satchel-action-flag-deletion
		 dired-tabs-goto
		 dired-tabs-prev
		 dired-tabs-next))
    (add-to-list 'dired-preview-trigger-commands cmd t))
  (defun my-dired-preview-to-the-right ()
    "Display dired-preview window on the right side."
    `((display-buffer-in-side-window)
      (side . right)
      (slot . 0)
      (window-width . 0.45)
      (preserve-size . (t . nil))))
  (setq dired-preview-display-action-alist #'my-dired-preview-to-the-right)
  (dired-preview-global-mode 1))

(use-package dired-du
  :after dired
  :custom
  (dired-du-size-format t)
  :hook
  (dired-mode . (lambda () (when (bound-and-true-p dired-du-mode)
                             (dired-du-mode -1)))))

(use-package dired-quick-sort
  :after dired
  :config
  (dired-quick-sort)
  :bind
  (:map dired-mode-map
        ("," . dired-quick-sort-transient)))

(use-package dired-k
  :custom
  (dired-k-style 'git))

(use-package zoxide
  :after dired
  :config
  (defun dired-jump-with-zoxide (&optional other-window)
    (interactive "P")
    (zoxide-open-with nil (lambda (file) (find-alternate-file file)) t)))


(provide 'init-dired)
;;; init-dired.el ends here
