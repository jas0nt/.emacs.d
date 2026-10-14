;;; init-common.el --- Common helper commands  -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared helper functions used by the keybindings and transient menus.

;;; Code:

;;;; Files and buffers

(defun cxc/find-file-in-clipboard ()
  "Open the file whose path is stored in the clipboard."
  (interactive)
  (let ((file (string-trim (current-kill 0))))
    (if (file-exists-p file)
        (find-file file)
      (message "Not a valid file: %s" file))))

(defun cxc/kill-current-buffer ()
  "Kill the current buffer, then close its window unless it is the last one."
  (interactive)
  (kill-current-buffer)
  (when (> (length (window-list)) 1)
    (delete-window)))

(defun cxc/prev-buffer ()
  "Switch to the most recently used other buffer."
  (interactive)
  (switch-to-buffer (other-buffer (current-buffer) 1)))

;;;; Toggle menu helpers

(defun cxc/toggle-desc-p (label on)
  "Return LABEL prefixed with an indicator; ON non-nil means enabled."
  (format "%s %s"
          (if on
              (propertize "●" 'face 'success)
            (propertize "○" 'face 'shadow))
          label))

(defun cxc/toggle-desc (label var)
  "Return LABEL prefixed with the on/off indicator of variable VAR."
  (cxc/toggle-desc-p label (and (boundp var) (symbol-value var))))

;;;; Toggle commands

(defconst cxc/transparency-alpha 75
  "Frame opacity (in percent) used when transparency is switched on.")

(defun cxc/transparent-p ()
  "Return non-nil if the selected frame is transparent."
  (< (or (frame-parameter nil 'alpha-background) 100) 100))

(defun cxc/toggle-transparency ()
  "Toggle the selected frame between `cxc/transparency-alpha' and 100% opacity.
Only the background becomes transparent; the text stays opaque."
  (interactive)
  (set-frame-parameter nil 'alpha-background
                       (if (cxc/transparent-p) 100 cxc/transparency-alpha)))

(defun cxc/toggle-relative-line-numbers ()
  "Toggle between relative and absolute line numbers in the current buffer."
  (interactive)
  (setq-local display-line-numbers-type
              (if (eq display-line-numbers 'relative) t 'relative))
  (display-line-numbers-mode 1))

(provide 'init-common)
;;; init-common.el ends here
