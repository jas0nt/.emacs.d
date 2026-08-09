;;; dired-shortcuts.el --- Numbered tabs and copy-path shortcuts for Dired -*- lexical-binding: t; -*-

;; Two small, self-contained conveniences for `dired-mode':
;;
;; 1. Numbered tabs (0-9): bind the current directory to a digit and
;;    jump back to it instantly, like bookmarks with single-key recall.
;;
;; 2. Copy-path transient: a quick menu to copy the file at point's
;;    full path, name, name without extension, or parent directory.
;;
;; Neither feature depends on the other; they are bundled together
;; purely because both are "grab something with one keystroke" tools.

;;; Code:

(require 'transient)
(require 'dired)

;;; -----------------------------------------------------------------------
;;; Shared helper
;;; -----------------------------------------------------------------------

(defun dired-shortcuts--file-at-point ()
  "Return the absolute path of the file at point, ignoring any marks.
Falls back to `default-directory' if point is not on a file line."
  (let ((f (dired-get-filename nil t)))
    (expand-file-name (or f default-directory))))

;;; -----------------------------------------------------------------------
;;; Numbered tabs (0-9)
;;; -----------------------------------------------------------------------

(defvar dired-shortcuts-tab-list (make-vector 10 nil)
  "Vector to store tab paths, indexed from 0-9.")

(defun dired-shortcuts-tab-bind (index)
  "Bind current directory to the given INDEX (1-10).
INDEX 0 refers to slot 10 internally, matching the digit on your keyboard."
  (let* ((actual-index (if (= index 0) 9 (1- index)))
         (current-dir default-directory))
    (aset dired-shortcuts-tab-list actual-index current-dir)
    (message "Tab %d bound to: %s" index (abbreviate-file-name current-dir))))

(defun dired-shortcuts-tab-switch (index)
  "Switch to tab at INDEX (1-10).
If the bound directory no longer exists, unbind the tab and report it."
  (let* ((actual-index (if (= index 0) 9 (1- index)))
         (target-dir (aref dired-shortcuts-tab-list actual-index)))
    (cond
     ((null target-dir)
      (message "Tab %d is not bound to any path" index))
     ((not (file-directory-p target-dir))
      (aset dired-shortcuts-tab-list actual-index nil)
      (message "Tab %d unbound: directory no longer exists: %s"
               index (abbreviate-file-name target-dir)))
     (t
      (find-alternate-file target-dir)
      (message "Switched to tab %d: %s" index (abbreviate-file-name target-dir))
      (when (bound-and-true-p dired-preview-global-mode)
        (dired-preview-trigger t))))))

(defun dired-shortcuts-tab-list-show ()
  "Display all current tab bindings."
  (interactive)
  (let ((buf (get-buffer-create "*Dired Tab Bindings*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "Dired Tab Bindings:\n\n")
      (dotimes (i 10)
        (let ((display-num (if (= i 9) 0 (1+ i)))
              (path (aref dired-shortcuts-tab-list i)))
          (insert (format "%d. %s\n"
                          display-num
                          (if path (abbreviate-file-name path) "(not bound)"))))))
    (display-buffer buf)))

(defun dired-shortcuts-tab-remove-current ()
  "Unbind current directory from tab list."
  (interactive)
  (let ((current-dir default-directory)
        (unbound nil))
    (dotimes (i 10)
      (when (equal (aref dired-shortcuts-tab-list i) current-dir)
        (aset dired-shortcuts-tab-list i nil)
        (setq unbound t)
        (message "Tab %d unbound." (if (= i 9) 0 (1+ i)))))
    (unless unbound
      (message "Current directory not found in tab bindings"))))

;; Generate the interactive bind/switch functions for keys 0-9, e.g.
;; `dired-shortcuts-tab-bind-3', `dired-shortcuts-tab-switch-7'.
(dotimes (i 10)
  (let ((key (if (= i 9) 0 (1+ i))))
    (defalias (intern (format "dired-shortcuts-tab-bind-%d" key))
      (lambda () (interactive) (dired-shortcuts-tab-bind key))
      (format "Bind current directory to tab %d." key))
    (defalias (intern (format "dired-shortcuts-tab-switch-%d" key))
      (lambda () (interactive) (dired-shortcuts-tab-switch key))
      (format "Switch to tab %d." key))))

;;; -----------------------------------------------------------------------
;;; Copy name / path variants
;;; -----------------------------------------------------------------------

(defun dired-shortcuts-copy-file-path ()
  "Copy the full absolute path of the file at point."
  (interactive)
  (let ((file (dired-shortcuts--file-at-point)))
    (kill-new file)
    (message "Copied path: %s" file)))

(defun dired-shortcuts-copy-file-name ()
  "Copy the name (with extension) of the file at point."
  (interactive)
  (let* ((file (dired-shortcuts--file-at-point))
         (name (file-name-nondirectory file)))
    (kill-new name)
    (message "Copied name: %s" name)))

(defun dired-shortcuts-copy-file-name-no-ext ()
  "Copy the name (without extension) of the file at point."
  (interactive)
  (let* ((file (dired-shortcuts--file-at-point))
         (name (file-name-base file)))
    (kill-new name)
    (message "Copied name (no ext): %s" name)))

(defun dired-shortcuts-copy-directory ()
  "Copy the directory (parent path) of the file at point."
  (interactive)
  (let* ((file (dired-shortcuts--file-at-point))
         (dir (file-name-directory file)))
    (kill-new dir)
    (message "Copied directory: %s" dir)))

;;;###autoload (autoload 'dired-shortcuts-copy-transient "dired-shortcuts" nil t)
(transient-define-prefix dired-shortcuts-copy-transient ()
  "Copy file name/path variants menu."
  ["Copy"
   :if-derived 'dired-mode
   ("c" "Do Copy"            dired-do-copy)
   ("F" "Full path"          dired-shortcuts-copy-file-path)
   ("f" "File name"          dired-shortcuts-copy-file-name)
   ("n" "File name (no ext)" dired-shortcuts-copy-file-name-no-ext)
   ("d" "Directory"          dired-shortcuts-copy-directory)])

(provide 'dired-shortcuts)

;;; dired-shortcuts.el ends here
