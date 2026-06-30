;;; init.el --- Emacs entry point -*- lexical-binding: t -*-

;; -----------------------------------------------------------------------
;; Load Path Setup
;; -----------------------------------------------------------------------

(defun my-add-subdirs-to-load-path (search-dir)
  "Recursively add subdirectories of SEARCH-DIR to `load-path'.
Only directories containing at least one .el, .so, or .dll file are
added. Common non-Elisp directories (node_modules, .git, etc.) are
skipped to keep startup fast."
  (let ((dir (file-name-as-directory search-dir)))
    (dolist (subdir (directory-files dir))
      (unless (member subdir '("." ".."
                               "dist" "node_modules" "__pycache__"
                               "RCS" "CVS" "rcs" "cvs" ".git" ".github"))
        (let ((subdir-path (concat dir (file-name-as-directory subdir))))
          (when (and (file-directory-p subdir-path)
                     (seq-some (lambda (f)
                                 (and (file-regular-p (concat subdir-path f))
                                      (member (file-name-extension f)
                                              '("el" "so" "dll"))))
                               (directory-files subdir-path)))
            ;; Append rather than prepend, so parent directories take
            ;; precedence over subdirectories in load order.
            (add-to-list 'load-path subdir-path t))
          ;; Recurse into every subdirectory regardless of whether it
          ;; was added to load-path, since it may contain qualifying children.
          (my-add-subdirs-to-load-path subdir-path))))))

(my-add-subdirs-to-load-path "~/.emacs.d/site-lisp")

;; -----------------------------------------------------------------------
;; Bootstrap
;; -----------------------------------------------------------------------

(require 'init-all)

;;; init.el ends here
