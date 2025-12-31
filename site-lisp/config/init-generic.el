;;;; --- General UI & UX Settings ---

;; Use y/n for prompts, not yes/no
(fset 'yes-or-no-p 'y-or-n-p)

;; Disable distracting UI elements
(blink-cursor-mode -1)
;; (setq ring-bell-function 'ignore) ; Uncomment to disable all bells
(setq use-dialog-box nil)
(setq inhibit-startup-screen t)
(setq initial-scratch-message nil) ; nil is cleaner than "" for some session managers

;; Editor behavior
(global-subword-mode 1)         ; Treat CamelCase as multiple words
(setq-default comment-style 'indent)
(setq mouse-yank-at-point t)
(setq select-enable-clipboard t) ; Modern way to integrate with system clipboard
(setq split-width-threshold nil) ; Always split windows vertically
(setq word-wrap-by-category t)   ; Better word wrapping for CJK characters
(setq completion-auto-select nil)
(setq ad-redefinition-action 'accept) ; Suppress warnings when a function is redefined

;; Platform-specific tweaks
(setq frame-resize-pixelwise t) ; For pixel-perfect resizing, useful on macOS

;;;; --- Performance Optimizations ---

;; IO Performance
(setq process-adaptive-read-buffering nil)
(setq read-process-output-max (* 1024 1024)) ; 1MB

;; Font caching
(setq inhibit-compacting-font-caches t)

;; Large file performance improvements
(setq-default bidi-display-reordering nil)
(setq bidi-inhibit-bpa t)
(setq-default bidi-paragraph-direction 'left-to-right)
(setq large-file-warning-threshold 100000000) ; 100MB
(setq long-line-threshold 2000)

;; Smooth Scrolling
(setq scroll-step 1
      scroll-conservatively 10000
      scroll-preserve-screen-position t)

;;;; --- Encoding ---

;; Set UTF-8 as the default encoding everywhere. More concise for modern Emacs.
(set-language-environment "UTF-8")
(prefer-coding-system 'utf-8)


(defvar my-emacs-cache-dir (expand-file-name "cache/" user-emacs-directory)
  "Directory for Emacs plugin cache files.")

(unless (file-exists-p my-emacs-cache-dir)
  (make-directory my-emacs-cache-dir t))

(defun my/set-cache-files (&rest file-specs)
  "Set cache file paths in bulk, ensuring parent directories exist.
FILE-SPECS is a list of (variable filename) lists."
  (dolist (spec file-specs)
    (let* ((var (car spec))
           (file-path (expand-file-name (cadr spec) my-emacs-cache-dir))
           (dir-path (file-name-directory file-path)))
      (unless (file-exists-p dir-path)
        (make-directory dir-path t))
      (set var file-path))))

(my/set-cache-files
 '(custom-file "custom.el")
 '(recentf-save-file "recentf")
 '(bookmark-default-file "bookmarks")
 '(transient-levels-file "transient/levels.el")
 '(transient-values-file "transient/values.el")
 '(transient-history-file "transient/history.el")
 '(tramp-persistency-file-name "tramp")
 '(svg-lib-icons-dir "svg-lib/")
 '(url-configuration-directory "url/"))

;; Load customizations after setting the file path
(load custom-file :noerror)


(provide 'init-generic)
