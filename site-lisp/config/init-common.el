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
  "toggle UI transparency"
  (interactive)
  (let ((alpha (frame-parameter nil 'alpha)))
    (set-frame-parameter
     nil 'alpha
     (if (eql (cond ((numberp alpha) alpha)
                    ((numberp (cdr alpha)) (cdr alpha))
                    ;; Also handle undocumented (<active> <inactive>) form.
                    ((numberp (cadr alpha)) (cadr alpha)))
              100)
         '(85 . 50) '(100 . 100)))))

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


(defun jst/mac-pbcopy ()
  "copy selected region to system clipboard"
  (interactive)
  (shell-command-on-region (point) (mark) "pbcopy"))

(defun jst/mac-reveal-in-finder ()
  "reveal current directory in finder"
  (interactive)
  (shell-command "open -R ."))


(provide 'init-common)