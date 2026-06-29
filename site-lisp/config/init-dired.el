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
  ;; Shared helper
  ;; -----------------------------------------------------------------------
  (defun my--dired-file-at-point-or-marked ()
    "Return an absolute path of the first marked file; else the file at
point; if neither, return `default-directory'. Non-nil and always existing."
    (let* ((files (or (dired-get-marked-files nil nil)
                       (let ((f (ignore-errors (dired-get-file-for-visit))))
                         (when f (list f)))))
           (p (or (car files) default-directory)))
      (expand-file-name p)))

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
     ("c" "Full path"          my-dired-copy-file-path)
     ("f" "File name"          my-dired-copy-file-name)
     ("n" "File name (no ext)" my-dired-copy-file-name-no-ext)
     ("d" "Directory"          my-dired-copy-directory)])

  ;; -----------------------------------------------------------------------
  ;; Stash (custom copy/paste/move)
  ;; -----------------------------------------------------------------------
  (defvar my-dired-stash nil
    "List of absolute file names stashed from a Dired buffer.")

  (defun my-dired-stash-marks ()
    "Stash the currently marked files from this Dired buffer.
If no files are marked, append the file at point to the existing
stash instead."
    (interactive)
    (unless (derived-mode-p 'dired-mode)
      (user-error "Run this from a Dired buffer"))
    (let ((files (dired-get-marked-files nil 'marked)))
      (if files
          (progn
            (setq my-dired-stash files)
            (message "Stashed %d file(s)" (length files)))
        (let ((f (dired-get-filename nil t)))
          (unless f
            (user-error "No file at point"))
          (if (member f my-dired-stash)
              (message "Already in stash: %s" (file-name-nondirectory f))
            (setq my-dired-stash (append my-dired-stash (list f)))
            (message "Appended %s (stash now has %d file(s))"
                     (file-name-nondirectory f)
                     (length my-dired-stash)))))))

  (defun my-dired-stash-clear ()
    "Clear the file stash."
    (interactive)
    (setq my-dired-stash nil)
    (message "Stash cleared"))

  (defun my--dired-copy-file-list (files dest-dir)
    "Copy FILES into DEST-DIR using built-in `dired-copy-file'."
    (dolist (from files)
      (let ((to (expand-file-name (file-name-nondirectory from) dest-dir)))
        (dired-copy-file from to 0)))
    (message "Copied %d file(s) to %s" (length files) dest-dir))

  (defun my--dired-move-file-list (files dest-dir)
    "Move/rename FILES into DEST-DIR using built-in `dired-rename-file'."
    (dolist (from files)
      (let ((to (expand-file-name (file-name-nondirectory from) dest-dir)))
        (dired-rename-file from to nil)))
    (message "Moved %d file(s) to %s" (length files) dest-dir))

  (defun my-dired-paste-copy-here ()
    "Copy stashed files into the current Dired directory."
    (interactive)
    (unless (derived-mode-p 'dired-mode)
      (user-error "Run this from a Dired buffer"))
    (unless my-dired-stash
      (user-error "Nothing stashed"))
    (let ((dest (dired-current-directory)))
      (my--dired-copy-file-list my-dired-stash dest)
      (revert-buffer)))

  (defun my-dired-paste-move-here ()
    "Move stashed files into the current Dired directory."
    (interactive)
    (unless (derived-mode-p 'dired-mode)
      (user-error "Run this from a Dired buffer"))
    (unless my-dired-stash
      (user-error "Nothing stashed"))
    (let ((dest (dired-current-directory)))
      (when (member dest (mapcar #'file-name-directory my-dired-stash))
        (unless (y-or-n-p "Move into the same directory? (may overwrite)")
          (user-error "Move cancelled")))
      (my--dired-move-file-list my-dired-stash dest)
      (setq my-dired-stash nil)
      (revert-buffer)))


  ;; -----------------------------------------------------------------------
  ;; Rsync command generation (stash first, run later; transient menu
  ;; bound to "v")
  ;; -----------------------------------------------------------------------
  (defvar my-dired-rsync-script-file
    (expand-file-name "dired-rsync-commands.sh"
                       (or (bound-and-true-p my-emacs-cache-dir)
                           user-emacs-directory))
    "Path to the accumulated rsync commands script file.")

  (defun my-dired--ensure-rsync-script ()
    "Create the script file with a shebang if it doesn't exist, and make
it executable."
    (unless (file-exists-p my-dired-rsync-script-file)
      (make-directory (file-name-directory my-dired-rsync-script-file) t)
      (with-temp-buffer
        (insert "#!/usr/bin/env bash\n")
        (insert "set -euo pipefail\n\n")
        (write-region (point-min) (point-max) my-dired-rsync-script-file nil 'silent)))
    (set-file-modes my-dired-rsync-script-file #o755))

  (defun my-dired--rsync-append (comment cmd)
    "Append a COMMENT line and a command CMD to the end of the script file."
    (my-dired--ensure-rsync-script)
    (with-temp-buffer
      (insert "# " comment "\n")
      (insert cmd "\n\n")
      (write-region (point-min) (point-max) my-dired-rsync-script-file t 'silent)))

  (defun my-dired--rsync-cmd (mode files dest-dir)
    "Build an rsync command string that copies/moves FILES into DEST-DIR.
MODE is either `copy' or `move'."
    (let* ((dest (file-name-as-directory (expand-file-name dest-dir)))
           (flags (if (eq mode 'move)
                      "-avh --progress --remove-source-files"
                    "-avh --progress"))
           (sources (mapconcat (lambda (f) (shell-quote-argument (expand-file-name f)))
                                files " ")))
      (format "rsync %s -- %s %s" flags sources (shell-quote-argument dest))))

  (defun my-dired--rsync-delete-cmd (files)
    "Build an rm command string that deletes FILES."
    (mapconcat (lambda (f) (shell-quote-argument (expand-file-name f)))
               files " "))

  (defun my-dired-rsync-copy-here ()
    "Generate an rsync COPY command for the stashed files into the
current directory and append it to the script file. Does not clear
the stash."
    (interactive)
    (unless (derived-mode-p 'dired-mode)
      (user-error "Run this from a Dired buffer"))
    (unless my-dired-stash
      (user-error "Nothing stashed"))
    (let* ((dest (dired-current-directory))
           (n (length my-dired-stash))
           (cmd (my-dired--rsync-cmd 'copy my-dired-stash dest)))
      (my-dired--rsync-append (format "copy %d file(s) -> %s" n dest) cmd)
      (message "Appended rsync COPY command (%d file(s)) to %s"
               n my-dired-rsync-script-file)))

  (defun my-dired-rsync-move-here ()
    "Generate an rsync MOVE command for the stashed files into the
current directory, append it to the script file, then clear the
stash."
    (interactive)
    (unless (derived-mode-p 'dired-mode)
      (user-error "Run this from a Dired buffer"))
    (unless my-dired-stash
      (user-error "Nothing stashed"))
    (let* ((dest (dired-current-directory))
           (n (length my-dired-stash))
           (cmd (my-dired--rsync-cmd 'move my-dired-stash dest)))
      (my-dired--rsync-append (format "move %d file(s) -> %s" n dest) cmd)
      (setq my-dired-stash nil)
      (message "Appended rsync MOVE command (%d file(s)) to %s; stash cleared"
               n my-dired-rsync-script-file)))

  (defun my-dired--flagged-for-deletion ()
    "Return the list of absolute file names currently flagged for
deletion (marked with `d', dired-del-marker) in this Dired buffer."
    (let (files)
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (let ((absname (dired-get-filename nil t)))
            (when (and absname
                       (eq (dired-file-marker absname) dired-del-marker))
              (push absname files)))
          (forward-line 1)))
      (nreverse files)))
  
  (defun my-dired-rsync-delete-here ()
    "Generate a delete command for the files currently flagged for
deletion (via `d', `dired-flag-file-deletion') in this buffer, and
append it to the script file. Does not touch the stash."
    (interactive)
    (unless (derived-mode-p 'dired-mode)
      (user-error "Run this from a Dired buffer"))
    (let ((files (my-dired--flagged-for-deletion)))
      (unless files
        (user-error "No files flagged for deletion (use `d' to flag)"))
      (let* ((n (length files))
             (targets (my-dired--rsync-delete-cmd files))
             (cmd (format "rm -rf -- %s" targets)))
        (my-dired--rsync-append (format "delete %d file(s)" n) cmd)
        ;; Unflag them now that the delete command has been recorded,
        ;; so the buffer no longer shows them as pending deletion.
        (dired-unmark-all-files dired-del-marker)
        (message "Appended DELETE command (%d file(s)) to %s"
                 n my-dired-rsync-script-file))))

  (defun my-dired-rsync-script-open ()
    "Open the generated rsync script for review/editing."
    (interactive)
    (my-dired--ensure-rsync-script)
    (find-file my-dired-rsync-script-file))

  (defun my-dired-rsync-script-clear ()
    "Delete the accumulated script file so the next command starts fresh."
    (interactive)
    (when (file-exists-p my-dired-rsync-script-file)
      (delete-file my-dired-rsync-script-file))
    (message "Cleared rsync script: %s" my-dired-rsync-script-file))

  (defun my-dired-rsync-script-execute ()
    "Run the rsync script asynchronously without blocking Emacs.
Prompts for confirmation first, and shows live progress in a
compilation buffer."
    (interactive)
    (unless (file-exists-p my-dired-rsync-script-file)
      (user-error "Rsync script does not exist: %s" my-dired-rsync-script-file))
    (unless (y-or-n-p
             (format "Run rsync script %s now? "
                     (abbreviate-file-name my-dired-rsync-script-file)))
      (user-error "Execution cancelled"))
    (let* ((default-directory (file-name-directory my-dired-rsync-script-file))
           (buf-name "*rsync-execute*")
           (compilation-buffer-name-function (lambda (_mode) buf-name)))
      (compile (format "bash %s" (shell-quote-argument my-dired-rsync-script-file)))
      (with-current-buffer buf-name
        (setq-local compilation-scroll-output t))))

  (transient-define-prefix my-dired-rsync-transient ()
    "Rsync script task menu."
    [["Rsync Copy/Move"
      :if-derived 'dired-mode
      ("p" "Copy here"     my-dired-rsync-copy-here)
      ("P" "Move here"     my-dired-rsync-move-here)
      ("d" "Delete"        my-dired-rsync-delete-here)]
     ["Rsync script"
      :if-derived 'dired-mode
      ("v" "Open script"    my-dired-rsync-script-open)
      ("c" "Clear script"   my-dired-rsync-script-clear)
      ("x" "Execute script" my-dired-rsync-script-execute)]
     ["Actions"
      ("q" "Quit" transient-quit-all)]])

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
    "Switch to tab at INDEX (1-10)."
    (let* ((actual-index (if (= index 0) 9 (1- index)))
           (target-dir (aref my-dired-tab-list actual-index)))
      (if target-dir
          (progn
            (dired target-dir)
            (message "Switched to tab %d: %s" index (abbreviate-file-name target-dir)))
        (message "Tab %d is not bound to any path" index))))

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
  
  (transient-define-prefix my-dired-toggle ()
    [["Toggle"
      :if-derived 'dired-mode
      ("t" "tumbnail"  media-thumbnail-dired-mode)
      ("d" "detail"    dired-hide-details-mode)
      ("u" "du"        dired-du-mode)
      ("g" "git"       dired-k)
      ]
     ["Actions"
      ("q" "Quit" transient-quit-all)]])

  :bind
  ("C-x C-d" . (lambda () (interactive) (dired default-directory)))
  (:map dired-mode-map
        ("<f5>" . revert-buffer)
        ("C"    . dired-do-compress-to)
	("t"    . my-dired-toggle)

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

        ;; Create
        ("a" . dired-create-empty-file)
        ("A" . dired-create-directory)

        ;; Edit mode
        ("r" . wdired-change-to-wdired-mode)

        ;; Copy name/path variants menu
        ("c" . my-dired-copy-transient)

        ;; Stash / copy / move
        ("y" . my-dired-stash-marks)
        ("Y" . my-dired-stash-clear)
        ("p" . my-dired-paste-copy-here)
        ("P" . my-dired-paste-move-here)

        ;; Rsync
        ("v" . my-dired-rsync-transient)

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

(use-package media-thumbnail
  :after dired
  :custom
  (media-thumbnail-max-processes 8)
  (media-thumbnail-cache-dir
   (expand-file-name "media-thumbnails/"
                     (or (bound-and-true-p my-emacs-cache-dir)
                         user-emacs-directory))))

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

;; Additional syntax highlighting for dired
(use-package diredfl
  :after dired
  :hook
  ((dired-mode . diredfl-mode)
   (dired-directory-view-mode . diredfl-mode))
  :config
  (set-face-attribute 'diredfl-dir-name nil :bold t))

(use-package dired-k
  :custom
  (dired-k-style 'git))

(use-package zoxide
  :after dired
  :config
  (defun dired-jump-with-zoxide (&optional other-window)
    (interactive "P")
    (zoxide-open-with nil (lambda (file) (dired-jump other-window file)) t)))

(use-package nerd-icons-dired
  :after dired
  :hook
  (dired-mode . nerd-icons-dired-mode))

(provide 'init-dired)
;;; init-dired.el ends here
