;;; init-dired.el --- Dired configuration -*- lexical-binding: t -*-

(use-package dired
  :ensure nil ; Built-in package
  :custom
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-dwim-target t)
  (dired-listing-switches
   "-l --almost-all --human-readable --group-directories-first --no-group")
  :hook (dired-mode . hl-line-mode)
  :config
  (put 'dired-find-alternate-file 'disabled nil)

  ;; -----------------------------------------------------------------------
  ;; Shared helpers
  ;; -----------------------------------------------------------------------
  (defun my--dired-file-at-point ()
    "Return the absolute path of the file at point, ignoring any marks.
Falls back to `default-directory' if point is not on a file line."
    (let ((f (dired-get-filename nil t)))
      (expand-file-name (or f default-directory))))

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
  ;; Copy name / path variants (transient menu, bound to "c")
  ;; -----------------------------------------------------------------------
  (defun my-dired-copy-file-path ()
    "Copy the full absolute path of the file at point."
    (interactive)
    (let ((file (my--dired-file-at-point)))
      (kill-new file)
      (message "Copied path: %s" file)))

  (defun my-dired-copy-file-name ()
    "Copy the name (with extension) of the file at point."
    (interactive)
    (let* ((file (my--dired-file-at-point))
           (name (file-name-nondirectory file)))
      (kill-new name)
      (message "Copied name: %s" name)))

  (defun my-dired-copy-file-name-no-ext ()
    "Copy the name (without extension) of the file at point."
    (interactive)
    (let* ((file (my--dired-file-at-point))
           (name (file-name-base file)))
      (kill-new name)
      (message "Copied name (no ext): %s" name)))

  (defun my-dired-copy-directory ()
    "Copy the directory (parent path) of the file at point."
    (interactive)
    (let* ((file (my--dired-file-at-point))
           (dir (file-name-directory file)))
      (kill-new dir)
      (message "Copied directory: %s" dir)))

  (transient-define-prefix my-dired-copy-transient ()
    "Copy file name/path variants menu."
    ["Copy"
     :if-derived 'dired-mode
     ("c" "Do Copy"            dired-do-copy)
     ("F" "Full path"          my-dired-copy-file-path)
     ("f" "File name"          my-dired-copy-file-name)
     ("n" "File name (no ext)" my-dired-copy-file-name-no-ext)
     ("d" "Directory"          my-dired-copy-directory)])

  ;; -----------------------------------------------------------------------
  ;; Numbered tabs (0-9)
  ;; -----------------------------------------------------------------------
  (defvar my-dired-tab-list (make-vector 10 nil)
    "Vector to store tab paths, indexed from 0-9.")
  (add-to-list 'savehist-additional-variables 'my-dired-tab-list)

  (defun my-dired-tab-bind (index)
    "Bind current directory to the given INDEX (1-10)."
    (let* ((actual-index (if (= index 0) 9 (1- index)))
           (current-dir default-directory))
      (aset my-dired-tab-list actual-index current-dir)
      (message "Tab %d bound to: %s" index (abbreviate-file-name current-dir))))

  (defun my-dired-tab-switch (index)
    "Switch to tab at INDEX (1-10).
If the bound directory no longer exists, unbind the tab and report it."
    (let* ((actual-index (if (= index 0) 9 (1- index)))
           (target-dir (aref my-dired-tab-list actual-index)))
      (cond
       ((null target-dir)
	(message "Tab %d is not bound to any path" index))
       ((not (file-directory-p target-dir))
	(aset my-dired-tab-list actual-index nil)
	(message "Tab %d unbound: directory no longer exists: %s"
		 index (abbreviate-file-name target-dir)))
       (t
	(find-alternate-file target-dir)
	(message "Switched to tab %d: %s" index (abbreviate-file-name target-dir))
	(when (bound-and-true-p dired-preview-global-mode)
          (dired-preview-trigger t))))))

  (defun my-dired-tab-list-show ()
    "Display all current tab bindings."
    (interactive)
    (let ((buf (get-buffer-create "*Dired Tab Bindings*")))
      (with-current-buffer buf
        (erase-buffer)
        (insert "Dired Tab Bindings:\n\n")
        (dotimes (i 10)
          (let ((display-num (if (= i 9) 0 (1+ i)))
                (path (aref my-dired-tab-list i)))
            (insert (format "%d. %s\n"
                            display-num
                            (if path (abbreviate-file-name path) "(not bound)"))))))
      (display-buffer buf)))

  (defun my-dired-tab-remove-current ()
    "Unbind current directory from tab list."
    (interactive)
    (let ((current-dir default-directory)
          (unbound nil))
      (dotimes (i 10)
        (when (equal (aref my-dired-tab-list i) current-dir)
          (aset my-dired-tab-list i nil)
          (setq unbound t)
          (message "Tab %d unbound." (if (= i 9) 0 (1+ i)))))
      (unless unbound
        (message "Current directory not found in tab bindings"))))

  ;; Generate the interactive bind/switch functions for keys 0-9.
  (dotimes (i 10)
    (let ((key (if (= i 9) 0 (1+ i))))
      (defalias (intern (format "my-dired-tab-bind-%d" key))
        (lambda () (interactive) (my-dired-tab-bind key)))
      (defalias (intern (format "my-dired-tab-switch-%d" key))
        (lambda () (interactive) (my-dired-tab-switch key)))))

  ;; -----------------------------------------------------------------------
  ;; Misc toggles menu
  ;; -----------------------------------------------------------------------
  (transient-define-prefix my-dired-toggle-transient ()
    [
     ["Toggle"
      :if-derived 'dired-mode
      ("T" "tab list"    my-dired-tab-list-show)
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
        ("r" . wdired-change-to-wdired-mode)

        ;; Copy name/path variants menu
        ("c" . my-dired-copy-transient)

        ;; Numbered tabs
        ("!"   . my-dired-tab-remove-current)
        ("C-1" . my-dired-tab-bind-1)
        ("C-2" . my-dired-tab-bind-2)
        ("C-3" . my-dired-tab-bind-3)
        ("C-4" . my-dired-tab-bind-4)
        ("C-5" . my-dired-tab-bind-5)
        ("C-6" . my-dired-tab-bind-6)
        ("C-7" . my-dired-tab-bind-7)
        ("C-8" . my-dired-tab-bind-8)
        ("C-9" . my-dired-tab-bind-9)
        ("C-0" . my-dired-tab-bind-0)
        ("1"   . my-dired-tab-switch-1)
        ("2"   . my-dired-tab-switch-2)
        ("3"   . my-dired-tab-switch-3)
        ("4"   . my-dired-tab-switch-4)
        ("5"   . my-dired-tab-switch-5)
        ("6"   . my-dired-tab-switch-6)
        ("7"   . my-dired-tab-switch-7)
        ("8"   . my-dired-tab-switch-8)
        ("9"   . my-dired-tab-switch-9)
        ("0"   . my-dired-tab-switch-0)))

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
