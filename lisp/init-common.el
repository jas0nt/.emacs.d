;;;###autoload
(defun jst/new-scratch-buffer ()
  "create a new scratch buffer to work in. (could be *scratch* - *scratchX*)"
  (interactive)
  (let ((n 0)
        bufname)
    (while (progn
             (setq bufname (concat "*scratch"
                                   (if (= n 0) "" (int-to-string n))
                                   "*"))
             (setq n (1+ n))
             (get-buffer bufname)))
    (switch-to-buffer (get-buffer-create bufname))
    (if (= n 1) (lisp-interaction-mode))))

;;;###autoload
(defun jst/find-config-file ()
  "open emacs config file"
  (interactive)
  (find-file jst/emacs-config-file))

;;;###autoload
(defun jst/reload-config-file ()
  "reload emacs config file"
  (interactive)
  (org-babel-load-file (expand-file-name jst/emacs-config-file)))

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

;;;###autoload
(defun jst/string-trim-final-newline (string)
  (let ((len (length string)))
    (cond
     ((and (> len 0) (eql (aref string (- len 1)) ?\n))
      (substring string 0 (- len 1)))
     (t string))))

;;;###autoload
(defun jst/shell-command-to-string-trim (command)
  (jst/string-trim-final-newline (shell-command-to-string command)))


(provide 'init-common)
