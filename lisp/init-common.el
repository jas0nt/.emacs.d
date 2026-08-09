;;;###autoload
(defun jst/find-file-in-clipboard ()
  "open file in clipboard"
  (interactive)
  (when (file-exists-p (current-kill 0))
    (find-file (current-kill 0))))

;;;###autoload
(defun jst/toggle-ui-transparency ()
  "Toggle transparency using the modern Emacs 29+ alpha-background."
  (interactive)
  (let ((alpha (frame-parameter nil 'alpha-background)))
    (set-frame-parameter
     nil 'alpha-background
     (if (or (not alpha) (= alpha 100))
         75    ; Turn on transparency
       100)))) ; Turn off (100% opaque)

;;;###autoload
(defun jst/kill-current-buffer ()
  "kill current buffer but keep the last window"
  (interactive)
  (progn
    (kill-current-buffer)
    (when (> (length (window-list)) 1)
      (delete-window))))


(provide 'init-common)
