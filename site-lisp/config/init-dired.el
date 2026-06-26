;;; init-dired.el --- Dired configuration -*- lexical-binding: t -*-

(use-package dired
  :ensure nil  ; Built-in package
  :custom
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-dwim-target t)
  (dired-listing-switches
   "-l --almost-all --human-readable --group-directories-first --no-group")
  :hook (dired-mode . hl-line-mode)
  :config
  (put 'dired-find-alternate-file 'disabled nil)

  ;; -----------------------------------------------------------------------
  ;; Custom Function: Open Kitty Cleanly
  ;; -----------------------------------------------------------------------
  (defun my-dirvish-open-kitty-here ()
    "Open a Kitty terminal in the current directory without blocking Emacs."
    (interactive)
    (let ((current-dir (dired-current-directory)))
      ;; Using start-process avoids the annoying *Async Shell Command* buffer
      (start-process "kitty" nil "kitty" "-d" current-dir)
      (message "Launched Kitty in: %s" current-dir)))

  (defvar my-dired-favorites
    '(("Home" . "~/")
      ("Downloads" . "~/Downloads/")
      ("X" . "/run/media")
      ("Trash" . "~/.local/share/Trash/files/")))

  (defun my-dired-goto-favorite (&optional other-window)
    "Jump to a favorite directory in Dired"
    (interactive "P")
    (let* ((names (mapcar #'car my-dired-favorites))
	   (choice (completing-read "Favorite: " names nil t))
	   (dir (expand-file-name (cdr (assoc choice my-dired-favorites)))))
      (if other-window
	  (dired-other-window dir)
	(dired dir))))

  (defun my--dired-file-at-point-or-marked ()
    "Return an absolute path of the first marked file; else the file at point; if neither, return `default-directory'. Non-nil and always existing."
    (let* ((files (or (dired-get-marked-files nil nil nil 'distinguish-one-marked)
                      (let ((f (ignore-errors (dired-get-file-for-visit))))
			(when f (list f)))))
           (p (or (car files) default-directory)))
      (expand-file-name p)))

  (defun my-dired-do-open-current-only ()
    "Open the file at point using an external app, ignoring any marked files."
    (interactive)
    (let ((dired-marker-char ?\0))
      (dired-do-open)))


  ;; custom copy/paste/move
  (defvar my-dired-stash nil
    "List of absolute file names stashed from a Dired buffer.")

  (defun my-dired-stash-marks ()
    "Stash the currently marked files from this Dired buffer.
If no files are marked, append the file at point to the existing stash instead."
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
    (interactive)
    (setq my-dired-stash nil)
    (message "Stash cleared"))
  
  (defun my--dired-copy-file-list (files dest-dir)
    "Copy files into dest-dir using built-in `dired-coyp-file'."
    (dolist (from files)
      (let ((to (expand-file-name (file-name-nondirectory from) dest-dir)))
	(dired-copy-file from to 0)))
    (message "Copied %d file(s) to %s" (length files) dest-dir))

  (defun my--dired-move-file-list (files dest-dir)
    "Move/rename files into dest-dir using built-in `dired-rename-file'."
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
      ;; refresh destination listing
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
  ;; rsync 命令生成（先标记，后统一执行）
  ;; -----------------------------------------------------------------------
  (defvar my-dired-rsync-script-file
    (expand-file-name "dired-rsync-commands.sh"
                      (or (bound-and-true-p my-emacs-cache-dir)
                          user-emacs-directory))
    "累积生成的 rsync 命令的脚本文件路径。")

  (defun my-dired--ensure-rsync-script ()
    "若脚本文件不存在则创建，写入 shebang，并赋予可执行权限。"
    (unless (file-exists-p my-dired-rsync-script-file)
      (make-directory (file-name-directory my-dired-rsync-script-file) t)
      (with-temp-buffer
	(insert "#!/usr/bin/env bash\n")
	(insert "set -euo pipefail\n\n")
	(write-region (point-min) (point-max) my-dired-rsync-script-file nil 'silent)))
    (set-file-modes my-dired-rsync-script-file #o755))

  (defun my-dired--rsync-append (comment cmd)
    "把一条注释 COMMENT 和命令 CMD 追加写入脚本文件末尾。"
    (my-dired--ensure-rsync-script)
    (with-temp-buffer
      (insert "# " comment "\n")
      (insert cmd "\n\n")
      (write-region (point-min) (point-max) my-dired-rsync-script-file t 'silent)))

  (defun my-dired--rsync-cmd (mode files dest-dir)
    "构造把 FILES 复制/移动到 DEST-DIR 的 rsync 命令字符串。
MODE 为 `copy' 或 `move'。"
    (let* ((dest (file-name-as-directory (expand-file-name dest-dir)))
           (flags (if (eq mode 'move)
                      "-avh --progress --remove-source-files"
                    "-avh --progress"))
           (sources (mapconcat (lambda (f) (shell-quote-argument (expand-file-name f)))
                               files " ")))
      (format "rsync %s -- %s %s" flags sources (shell-quote-argument dest))))

  (defun my-dired-rsync-copy-here ()
    "为当前 stash 里的文件生成一条 rsync 复制命令（目标为当前目录），
追加写入脚本文件。不清空 stash。"
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
    "为当前 stash 里的文件生成一条 rsync 移动命令（目标为当前目录），
追加写入脚本文件，然后清空 stash。"
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

  (defun my-dired-rsync-script-open ()
    "打开生成的 rsync 脚本以供检查/编辑。"
    (interactive)
    (my-dired--ensure-rsync-script)
    (find-file my-dired-rsync-script-file))

  (defun my-dired-rsync-script-clear ()
    "删除已累积的脚本文件，让下一次命令重新开始。"
    (interactive)
    (when (file-exists-p my-dired-rsync-script-file)
      (delete-file my-dired-rsync-script-file))
    (message "Cleared rsync script: %s" my-dired-rsync-script-file))
  
  ;; -----------------------------------------------------------------------
  ;; Custom Logic: Numbered Tabs (0-9)
  ;; -----------------------------------------------------------------------
  (add-to-list 'savehist-additional-variables 'my-dired-tab-list)
  (defvar my-dired-tab-list (make-vector 10 nil)
    "Vector to store tab paths, indexed from 0-9.")

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

  (defun my-dired-tab-list ()
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

  ;; Generate the interactive functions for keybinding
  (dotimes (i 10)
    (let ((key (if (= i 9) 0 (1+ i))))
      ;; Bind function
      (defalias (intern (format "my-dired-tab-bind-%d" key))
        (lambda () (interactive) (my-dired-tab-bind key)))
      ;; Switch function
      (defalias (intern (format "my-dired-tab-switch-%d" key))
        (lambda () (interactive) (my-dired-tab-switch key)))))

  :bind
  ("C-x C-d" . (lambda () (interactive) (dired default-directory)))
  (
   :map dired-mode-map
   ("<f5>" . revert-buffer)
   ("!" . my-dired-tab-remove-current)
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

   ("1" . my-dired-tab-switch-1)
   ("2" . my-dired-tab-switch-2)
   ("3" . my-dired-tab-switch-3)
   ("4" . my-dired-tab-switch-4)
   ("5" . my-dired-tab-switch-5)
   ("6" . my-dired-tab-switch-6)
   ("7" . my-dired-tab-switch-7)
   ("8" . my-dired-tab-switch-8)
   ("9" . my-dired-tab-switch-9)
   ("0" . my-dired-tab-switch-0)

   ("T" . my-dirvish-open-kitty-here)
   ("'" . bookmark-jump)
   ("h" . dired-up-directory)
   ("j" . dired-next-line)
   ("k" . dired-previous-line)
   ("l" . dired-find-file)
   ("n" . my-dired-goto-favorite)
   ("/" . consult-line)
   ("<RET>" . my-dired-do-open-current-only)
   ("C-<return>" . dired-do-open)
   ("a" . dired-create-empty-file)
   ("A" . dired-create-directory)

   ("y" . my-dired-stash-marks)
   ("Y" . my-dired-stash-clear)
   ("p" . my-dired-paste-copy-here)
   ("P" . my-dired-paste-move-here)
   ("i" . my-dired-rsync-copy-here)
   ("I" . my-dired-rsync-move-here)
   ("v" . my-dired-rsync-script-open)
   ("V" . my-dired-rsync-script-clear)

   ("r" . wdired-change-to-wdired-mode)
   ("f" . consult-fd)
   ("z" . dired-jump-with-zoxide)))

(use-package media-thumbnail
  :after dired
  :custom
  (media-thumbnail-max-processes 8)
  (media-thumbnail-cache-dir
   (expand-file-name "media-thumbnails/"
                      (or (bound-and-true-p my-emacs-cache-dir)
                          user-emacs-directory)))
  :bind
  (:map dired-mode-map
        ("t" . media-thumbnail-dired-mode))
  :config
  ;; (add-hook 'dired-mode-hook 'media-thumbnail-dired-mode)
  )

;; Additional syntax highlighting for dired
(use-package diredfl
  :hook
  ((dired-mode . diredfl-mode)
   (dired-directory-view-mode . diredfl-mode))
  :config
  (set-face-attribute 'diredfl-dir-name nil :bold t))

(use-package dired-k
  :config
  (setq dired-k-style 'git)
  :hook
  ((dired-mode . dired-k)))

(use-package zoxide
  :config
  (defun dired-jump-with-zoxide (&optional other-window)
    (interactive "P")
    (zoxide-open-with nil (lambda (file) (dired-jump other-window file)) t)))

(use-package nerd-icons-dired
  :hook
  (dired-mode . nerd-icons-dired-mode))

(provide 'init-dired)
