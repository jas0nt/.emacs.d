;;; dired-tabs.el --- Yazi-style numbered tabs for Dired -*- lexical-binding: t -*-

;;; Commentary:

;; A tiny tab system for Dired that mimics Yazi's tabs:
;;
;;   t        new tab (opens at the current directory, right after this tab)
;;   1..9     jump to tab N
;;   [ / ]    previous / next tab (wraps around)
;;   { / }    move the current tab left / right
;;   C-c C-c  close the current tab (the last tab cannot be closed)
;;
;; Model: a tab is just a directory plus the file the cursor was on when
;; you left it.  There is a single window; switching tabs visits the
;; target directory with `dired' (existing Dired buffers are reused, and
;; they are never killed, so regular Dired marks survive a tab switch).
;; Because a tab only remembers a directory, it does not matter how you
;; navigate inside it (`^', RET, `find-alternate-file', ...).
;;
;; The tab bar is shown in the header line of Dired buffers while there
;; are two or more tabs, and hidden again when only one tab is left.
;;
;; Works with `dired-satchel': packed/flagged marks are redrawn by its
;; `dired-after-readin-hook' whenever a Dired buffer gets (re)created.
;;
;; Suggested keybindings (these shadow some Dired defaults: `t' normally
;; toggles marks, and the digits are normally prefix arguments, which
;; `C-u N' / `M-N' still provide):
;;
;;   (:map dired-mode-map
;;         ("t" . dired-tabs-new)
;;         ("1" . dired-tabs-goto) ("2" . dired-tabs-goto) ("3" . dired-tabs-goto)
;;         ("4" . dired-tabs-goto) ("5" . dired-tabs-goto) ("6" . dired-tabs-goto)
;;         ("7" . dired-tabs-goto) ("8" . dired-tabs-goto) ("9" . dired-tabs-goto)
;;         ("[" . dired-tabs-prev)
;;         ("]" . dired-tabs-next)
;;         ("{" . dired-tabs-move-left)
;;         ("}" . dired-tabs-move-right)
;;         ("C-c C-c" . dired-tabs-close))

;;; Code:

(require 'dired)
(require 'cl-lib)
(require 'seq)

(defgroup dired-tabs nil
  "Yazi-style numbered tabs for Dired."
  :group 'dired)

(defcustom dired-tabs-show-header-line t
  "When non-nil, show the tab bar in the header line of Dired buffers
while there are two or more tabs."
  :type 'boolean
  :group 'dired-tabs)

(defface dired-tabs-current
  '((t :inherit (highlight bold)))
  "Face for the current tab in the tab bar."
  :group 'dired-tabs)

(defface dired-tabs-inactive
  '((t :inherit header-line))
  "Face for inactive tabs in the tab bar."
  :group 'dired-tabs)

;; ---------------------------------------------------------------------
;; State
;; ---------------------------------------------------------------------

(cl-defstruct (dired-tabs-tab (:constructor dired-tabs--make)
                              (:copier dired-tabs--copy))
  "One tab: the directory it shows and the file the cursor was on."
  dir file)

(defvar dired-tabs--list nil
  "List of `dired-tabs-tab' structs, in display order.")

(defvar dired-tabs--current 0
  "Index (0-based) of the current tab in `dired-tabs--list'.")

(defun dired-tabs--ensure ()
  "Create the first tab from the current directory if there is none yet."
  (unless dired-tabs--list
    (setq dired-tabs--list
          (list (dired-tabs--make :dir (expand-file-name default-directory)))
          dired-tabs--current 0)))

(defun dired-tabs--save ()
  "Remember the directory and cursor file of the current tab.
Does nothing when the current buffer is not a Dired buffer."
  (when (derived-mode-p 'dired-mode)
    (let ((tab (nth dired-tabs--current dired-tabs--list)))
      (setf (dired-tabs-tab-dir tab) (expand-file-name default-directory)
            (dired-tabs-tab-file tab) (dired-get-filename nil t)))))

;; ---------------------------------------------------------------------
;; Tab bar (header line)
;; ---------------------------------------------------------------------

(defconst dired-tabs--header-spec '(:eval (dired-tabs--format))
  "Value of `header-line-format' while the tab bar is visible.")

(defun dired-tabs--label (dir)
  "Return the short, %-escaped label for DIR."
  (let ((name (file-name-nondirectory (directory-file-name dir))))
    (replace-regexp-in-string "%" "%%" (if (string-empty-p name) "/" name))))

(defun dired-tabs--format ()
  "Render the tab bar, or nil when there is only one tab."
  (when (cdr dired-tabs--list)
    (let ((i -1))
      (mapconcat
       (lambda (tab)
         (cl-incf i)
         (let* ((current (= i dired-tabs--current))
                ;; The current tab's saved dir is stale until we leave it.
                (dir (if current default-directory (dired-tabs-tab-dir tab))))
           (propertize (format " %d %s " (1+ i) (dired-tabs--label dir))
                       'face (if current 'dired-tabs-current 'dired-tabs-inactive))))
       dired-tabs--list " "))))

(defun dired-tabs--apply-header ()
  "Show or hide the tab bar in the current Dired buffer.
Only touches `header-line-format' when it is unset or already ours."
  (when (and dired-tabs-show-header-line
             (derived-mode-p 'dired-mode)
             (or (null header-line-format)
                 (equal header-line-format dired-tabs--header-spec)))
    (setq-local header-line-format
                (and (cdr dired-tabs--list) dired-tabs--header-spec))))

(defun dired-tabs--refresh ()
  "Update the tab bar in every Dired buffer."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (dired-tabs--apply-header)))
  (force-mode-line-update t))

(add-hook 'dired-mode-hook #'dired-tabs--apply-header)

;; ---------------------------------------------------------------------
;; Switching
;; ---------------------------------------------------------------------

(defun dired-tabs--visit (tab)
  "Show TAB's directory in the selected window and restore its cursor."
  (let ((dir (dired-tabs-tab-dir tab)))
    (unless (file-directory-p dir)
      (user-error "Directory no longer exists: %s" dir))
    (dired dir)
    (when-let ((file (dired-tabs-tab-file tab)))
      (dired-goto-file file))
    (dired-tabs--refresh)))

(defun dired-tabs--switch (index)
  "Leave the current tab (remembering its state) and activate tab INDEX."
  (dired-tabs--save)
  (setq dired-tabs--current index)
  (dired-tabs--visit (nth index dired-tabs--list)))

(defun dired-tabs--relative (delta)
  "Switch DELTA tabs away from the current one, wrapping around."
  (dired-tabs--ensure)
  (let ((n (length dired-tabs--list)))
    (if (< n 2)
        (message "Only one tab")
      (dired-tabs--switch (mod (+ dired-tabs--current delta) n)))))

;; ---------------------------------------------------------------------
;; Commands
;; ---------------------------------------------------------------------

(defun dired-tabs-new ()
  "Open a new tab at the current directory, right after the current tab."
  (interactive)
  (dired-tabs--ensure)
  (dired-tabs--save)
  (let* ((i (1+ dired-tabs--current))
         (new (dired-tabs--copy (nth dired-tabs--current dired-tabs--list))))
    (setq dired-tabs--list (append (seq-take dired-tabs--list i)
                                   (list new)
                                   (seq-drop dired-tabs--list i))
          dired-tabs--current i)
    (dired-tabs--refresh)
    (message "Tab %d/%d: %s" (1+ i) (length dired-tabs--list)
             (abbreviate-file-name (dired-tabs-tab-dir new)))))

(defun dired-tabs-close ()
  "Close the current tab and activate the previous one.
The last remaining tab cannot be closed."
  (interactive)
  (dired-tabs--ensure)
  (when (< (length dired-tabs--list) 2)
    (user-error "Cannot close the last tab"))
  (let ((i dired-tabs--current))
    (setq dired-tabs--list (append (seq-take dired-tabs--list i)
                                   (seq-drop dired-tabs--list (1+ i)))
          dired-tabs--current (max 0 (1- i)))
    (dired-tabs--visit (nth dired-tabs--current dired-tabs--list))))

(defun dired-tabs-goto (n)
  "Switch to tab N (1-based).
Interactively, N is the digit key that invoked the command (1-9),
or the prefix argument when called any other way."
  (interactive
   (list (if (and (characterp last-command-event)
                  (<= ?1 last-command-event ?9))
             (- last-command-event ?0)
           (prefix-numeric-value current-prefix-arg))))
  (dired-tabs--ensure)
  (let ((count (length dired-tabs--list)))
    (cond
     ((or (< n 1) (> n count))
      (user-error "Tab %d does not exist (%d open)" n count))
     ((= (1- n) dired-tabs--current)
      (message "Already on tab %d" n))
     (t
      (dired-tabs--switch (1- n))))))

(defun dired-tabs-next ()
  "Switch to the next tab (wraps around)."
  (interactive)
  (dired-tabs--relative 1))

(defun dired-tabs-prev ()
  "Switch to the previous tab (wraps around)."
  (interactive)
  (dired-tabs--relative -1))

(defun dired-tabs--swap (delta)
  "Swap the current tab with its neighbour DELTA positions away."
  (dired-tabs--ensure)
  (let ((i dired-tabs--current)
        (j (+ dired-tabs--current delta)))
    (if (or (< j 0) (>= j (length dired-tabs--list)))
        (message "Already at the %s end" (if (< j 0) "left" "right"))
      (dired-tabs--save)
      (cl-rotatef (nth i dired-tabs--list) (nth j dired-tabs--list))
      (setq dired-tabs--current j)
      (dired-tabs--refresh))))

(defun dired-tabs-move-left ()
  "Move the current tab one position to the left."
  (interactive)
  (dired-tabs--swap -1))

(defun dired-tabs-move-right ()
  "Move the current tab one position to the right."
  (interactive)
  (dired-tabs--swap 1))

(provide 'dired-tabs)
;;; dired-tabs.el ends here
