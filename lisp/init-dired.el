;;; init-dired.el --- Dired configuration -*- lexical-binding: t -*-

(use-package dired
  :ensure nil ; Built-in package
  :custom
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-movement-style 'bounded-files)
  (dired-dwim-target t)
  (dired-listing-switches
   "-l --almost-all --human-readable --group-directories-first --no-group")
  :hook (dired-mode . hl-line-mode)
  :config
  (put 'dired-find-alternate-file 'disabled nil)

  ;; -----------------------------------------------------------------------
  ;; Favorites
  ;; -----------------------------------------------------------------------
  (defvar my-dired-favorites
    '(("Home"      . "~/")
      ("Downloads" . "~/Downloads/")
      ("X"         . "/run/media")
      ("Trash"     . "~/.local/share/Trash/files/"))
    "Alist of (NAME . DIRECTORY) favorite locations.")

  (defun my-dired-goto-favorite (&optional other-window)
    "Jump to a favorite directory in Dired."
    (interactive "P")
    (let* ((names (mapcar #'car my-dired-favorites))
           (choice (completing-read "Favorite: " names nil t))
           (dir (expand-file-name (cdr (assoc choice my-dired-favorites)))))
      (if other-window
          (dired-other-window dir)
        (dired dir))))

  ;; -----------------------------------------------------------------------
  ;; Open file / external terminal
  ;; -----------------------------------------------------------------------
  (defun my-dired-do-open-current-only ()
    "Open the file at point using an external app, ignoring any marked files."
    (interactive)
    (let ((dired-marker-char ?\0))
      (dired-do-open)))

  (defun my-dired-open-kitty-here ()
    "Open a Kitty terminal in the current directory without blocking Emacs."
    (interactive)
    (let ((current-dir (dired-current-directory)))
      ;; `start-process' avoids the annoying *Async Shell Command* buffer.
      (start-process "kitty" nil "kitty" "-d" current-dir)
      (message "Launched Kitty in: %s" current-dir)))

  ;; -----------------------------------------------------------------------
  ;; Misc toggles menu
  ;; -----------------------------------------------------------------------
  (transient-define-prefix my-dired-toggle-transient ()
    [
     ["Toggle"
      :if-derived 'dired-mode
      ;; ("T" "Tab list"    dired-shortcuts-tab-list-show)
      ("R" "Tab rm"      dired-shortcuts-tab-remove-current)
      ("t" "thumbnail"   media-thumbnail-dired-mode)
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
        ("<f5>" . revert-buffer)
        ("C"    . dired-do-compress-to)
        ("t"    . my-dired-toggle-transient)

        ;; Navigation
        ("h" . dired-up-directory)
        ("j" . dired-next-line)
        ("k" . dired-previous-line)
        ("l" . dired-find-file)
        ("]" . scroll-up-command)
        ("[" . scroll-down-command)
        ("n" . my-dired-goto-favorite)
        ("'" . bookmark-jump)
        ("z" . dired-jump-with-zoxide)
        ("/" . consult-line)
        ("f" . consult-fd)

        ;; Open
        ("<RET>"      . my-dired-do-open-current-only)
        ("C-<return>" . dired-do-open)
        ("T"          . my-dired-open-kitty-here)
        ("O"          . dired-do-shell-command)

        ;; Create
        ("a" . dired-create-empty-file)
        ("A" . dired-create-directory)

        ;; Edit mode
        ("r" . wdired-change-to-wdired-mode)))

(use-package dired-shortcuts
  :ensure nil
  :load-path "site-lisp"
  :after dired
  :commands (dired-shortcuts-tab-remove-current)
  :init
  (add-to-list 'savehist-additional-variables 'dired-shortcuts-tab-list)
  :bind
  (:map dired-mode-map
        ;; Copy transient
        ("c" . dired-shortcuts-copy-transient)
        ;; Numbered tabs
        ("C-1" . dired-shortcuts-tab-bind-1)
        ("C-2" . dired-shortcuts-tab-bind-2)
        ("C-3" . dired-shortcuts-tab-bind-3)
        ("C-4" . dired-shortcuts-tab-bind-4)
        ("C-5" . dired-shortcuts-tab-bind-5)
        ("C-6" . dired-shortcuts-tab-bind-6)
        ("C-7" . dired-shortcuts-tab-bind-7)
        ("C-8" . dired-shortcuts-tab-bind-8)
        ("C-9" . dired-shortcuts-tab-bind-9)
        ("C-0" . dired-shortcuts-tab-bind-0)
        ("1"   . dired-shortcuts-tab-switch-1)
        ("2"   . dired-shortcuts-tab-switch-2)
        ("3"   . dired-shortcuts-tab-switch-3)
        ("4"   . dired-shortcuts-tab-switch-4)
        ("5"   . dired-shortcuts-tab-switch-5)
        ("6"   . dired-shortcuts-tab-switch-6)
        ("7"   . dired-shortcuts-tab-switch-7)
        ("8"   . dired-shortcuts-tab-switch-8)
        ("9"   . dired-shortcuts-tab-switch-9)
        ("0"   . dired-shortcuts-tab-switch-0)))

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
  (dolist (cmd '(revert-buffer satchel-action-flag-deletion))
    (add-to-list 'dired-preview-trigger-commands cmd t))
  (defun my-dired-preview-to-the-right ()
    "Display dired-preview window on the right side."
    `((display-buffer-in-side-window)
      (side . right)
      (slot . 0)
      (window-width . 0.4)
      (preserve-size . (t . nil))))
  (setq dired-preview-display-action-alist #'my-dired-preview-to-the-right))

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
        ("s" . dired-quick-sort-transient)))

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
