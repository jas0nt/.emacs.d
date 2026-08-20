;;; -*- lexical-binding: t; -*-

;;;###autoload
(defun cxc/find-file-in-clipboard ()
  "Open the file whose path is stored in the clipboard."
  (interactive)
  (let ((file (string-trim (current-kill 0))))
    (if (file-exists-p file)
        (find-file file)
      (message "Not a valid file: %s" file))))

;;;###autoload
(defun cxc/toggle-ui-transparency ()
  "Toggle frame transparency using Emacs 29+ `alpha-background'."
  (interactive)
  (let ((alpha (frame-parameter nil 'alpha-background)))
    (set-frame-parameter
     nil 'alpha-background
     (if (and alpha (/= alpha 100)) 100 75))))

;;;###autoload
(defun cxc/kill-current-buffer ()
  "Kill the current buffer, then close its window unless it is the last one."
  (interactive)
  (kill-current-buffer)
  (when (> (length (window-list)) 1)
    (delete-window)))

(provide 'init-common)
