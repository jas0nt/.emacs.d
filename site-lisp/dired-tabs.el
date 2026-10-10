;;; dired-tabs.el --- Yazi-style numbered tabs for Dired -*- lexical-binding: t -*-

;;; Commentary:

;; A tiny tab system for Dired, inspired by Yazi's tabs but with explicit
;; tab numbers:
;;
;;   0..9     jump to tab N; if tab N does not exist it is created at the
;;            current directory (numbers need not be contiguous).  Tab 0
;;            is the external tab, see below.
;;   t        new tab at the current directory, numbered with the next free
;;            number after the current tab (else the smallest free number)
;;   [ / ]    previous / next existing tab, in number order (wraps around)
;;   { / }    swap the current tab's number with its left / right neighbour
;;   C-c C-c  close the current tab (the last tab cannot be closed)
;;   (toggle) `dired-tabs-toggle': leave Dired (tabs stay intact), or come
;;            back to the current tab from any other buffer
;;
;; Model: a tab is a number, a directory, and the file the cursor was on
;; when you left it.  Tab numbers are identities: you can have tabs 1, 3
;; and 7 and nothing else, and the tab bar shows them in number order.
;; There is a single window; switching tabs visits the target directory
;; with `dired' (existing Dired buffers are reused, and they are never
;; killed, so regular Dired marks survive a tab switch).  Because a tab
;; only remembers a directory, it does not matter how you navigate inside
;; it (`^', RET, `find-alternate-file', ...).
;;
;; Navigating inside Dired (RET on a directory, `^', or calling `dired'
;; while already in a Dired buffer) makes the current tab follow you, like
;; `cd' in Yazi.  Entering Dired from a NON-Dired buffer (`dired-jump',
;; `project-dired', `M-x dired' from a file buffer, ...) never overwrites
;; your numbered tabs.  Instead:
;;   - if some tab already shows that directory, that tab is activated
;;     (so jumping back to where you came from lands in the same tab);
;;   - otherwise the directory is shown in the external tab, tab 0
;;     (`dired-tabs-external-tab'), which is created on demand and simply
;;     overwritten by the next outside entry.
;; Tab 0 is reachable with the `0' key like any other tab, but it is
;; pinned: it cannot be swapped with `{' / `}' and `t' never picks it.
;; Set `dired-tabs-external-tab' to nil to turn all of this off.  Only the
;; `dired' command is covered; `dired-other-window' leaves the current
;; window's tab alone anyway, and `find-file' on a directory is not
;; intercepted.
;;
;; The tab bar is shown in the header line of Dired buffers while there
;; are two or more tabs, and hidden again when only one tab is left.
;;
;; Persistence: when Emacs exits, the tabs (number, directory, cursor
;; file, and which tab was current) are written to `dired-tabs-save-file'.
;; The file is read lazily, the first time a tab command runs or `dired'
;; is called, so there is no load-order issue and no dependency on
;; `savehist'.  Set `dired-tabs-save-file' to nil to disable.
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
;;         ("0" . dired-tabs-goto)
;;         ("1" . dired-tabs-goto) ("2" . dired-tabs-goto) ("3" . dired-tabs-goto)
;;         ("4" . dired-tabs-goto) ("5" . dired-tabs-goto) ("6" . dired-tabs-goto)
;;         ("7" . dired-tabs-goto) ("8" . dired-tabs-goto) ("9" . dired-tabs-goto)
;;         ("[" . dired-tabs-prev)
;;         ("]" . dired-tabs-next)
;;         ("{" . dired-tabs-move-left)
;;         ("}" . dired-tabs-move-right)
;;         ("C-c C-c" . dired-tabs-close)
;;         ("q" . dired-tabs-toggle))
;;
;;   ;; Global key to come back to Dired (C-u gives the old `dired-jump'):
;;   (global-set-key (kbd "C-x C-j") #'dired-tabs-toggle)

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

(defcustom dired-tabs-external-tab 0
  "Number of the tab used when Dired is entered from a non-Dired buffer.
Entering Dired from elsewhere (`dired-jump', `project-dired', ...) first
looks for a tab already showing that directory and activates it;
otherwise the directory is shown in this tab, which is created if needed
and overwritten by the next outside entry.  This tab is also pinned: it
is skipped when numbering new tabs and cannot be swapped.
If nil, entering Dired from elsewhere overwrites the current tab.
Navigating from within Dired always makes the current tab follow."
  :type '(choice (const :tag "Disabled" nil)
                 (integer :tag "Tab number"))
  :group 'dired-tabs)

(defcustom dired-tabs-save-file (locate-user-emacs-file "dired-tabs")
  "File in which the tabs are saved when Emacs exits.
The file is read lazily, the first time a tab command runs or `dired'
is called.  If nil, tabs are not persisted."
  :type '(choice (const :tag "Do not persist" nil) file)
  :group 'dired-tabs)

(defcustom dired-tabs-label-width 14
  "Maximum width, in columns, of an inactive tab's label.
Longer directory names are truncated with an ellipsis."
  :type 'integer
  :group 'dired-tabs)

(defcustom dired-tabs-current-label-width 28
  "Maximum width, in columns, of the current tab's label.
The current tab is shortened last when the bar has to be squeezed."
  :type 'integer
  :group 'dired-tabs)

(defcustom dired-tabs-min-label-width 4
  "Smallest label width used when squeezing the bar to fit the window.
If the tabs still do not fit at this width, the ones farthest from the
current tab are hidden and summarized as \"‹N\" (left) and \"N›\" (right)."
  :type 'integer
  :group 'dired-tabs)

(defface dired-tabs-overflow
  '((t :inherit (shadow header-line)))
  "Face for the \"‹N\" / \"N›\" markers that stand for hidden tabs."
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
  "One tab: its number, the directory it shows, and the cursor file."
  num dir file)

(defvar dired-tabs--list nil
  "List of `dired-tabs-tab' structs, always sorted by tab number.")

(defvar dired-tabs--current 1
  "Number of the current tab.")

(defvar dired-tabs--busy nil
  "Non-nil while dired-tabs itself is calling `dired'.
Keeps `dired-tabs--dired-advice' from treating our own tab switches as
\"entering Dired from elsewhere\".")

(defun dired-tabs--sort ()
  "Keep `dired-tabs--list' sorted by tab number."
  (setq dired-tabs--list
        (sort dired-tabs--list
              (lambda (a b) (< (dired-tabs-tab-num a) (dired-tabs-tab-num b))))))

(defun dired-tabs--find (num)
  "Return the tab numbered NUM, or nil."
  (seq-find (lambda (tab) (= (dired-tabs-tab-num tab) num)) dired-tabs--list))

(defun dired-tabs--position ()
  "Return the index of the current tab in `dired-tabs--list'."
  (cl-position dired-tabs--current dired-tabs--list :key #'dired-tabs-tab-num))

(defun dired-tabs--ensure ()
  "Create tab 1 from the current directory if there are no tabs yet.
Tabs saved by a previous session are loaded first."
  (dired-tabs--restore)
  (unless dired-tabs--list
    (setq dired-tabs--list
          (list (dired-tabs--make :num 1 :dir (expand-file-name default-directory)))
          dired-tabs--current 1)))

(defun dired-tabs--save ()
  "Remember the directory and cursor file of the current tab.
Does nothing when the current buffer is not a Dired buffer."
  (when (derived-mode-p 'dired-mode)
    (let ((tab (dired-tabs--find dired-tabs--current)))
      (setf (dired-tabs-tab-dir tab) (expand-file-name default-directory)
            (dired-tabs-tab-file tab) (dired-get-filename nil t)))))

;; ---------------------------------------------------------------------
;; Persistence
;; ---------------------------------------------------------------------

(defvar dired-tabs--restored nil
  "Non-nil once we have tried to read `dired-tabs-save-file' this session.")

(defun dired-tabs--write ()
  "Write the tabs to `dired-tabs-save-file'.
Does nothing if there are no live tabs, so a session that never used
tabs does not overwrite the saved state."
  (when (and dired-tabs-save-file dired-tabs--list)
    (condition-case err
        (progn
          ;; Make sure the current tab is up to date if we are in Dired.
          (when (and (derived-mode-p 'dired-mode)
                     (dired-tabs--find dired-tabs--current))
            (dired-tabs--save))
          (with-temp-file dired-tabs-save-file
            (let ((print-length nil) (print-level nil))
              (prin1 (list :version 1
                           :current dired-tabs--current
                           :tabs (mapcar (lambda (tab)
                                           (list (dired-tabs-tab-num tab)
                                                 (dired-tabs-tab-dir tab)
                                                 (dired-tabs-tab-file tab)))
                                         dired-tabs--list))
                     (current-buffer)))))
      (error (message "dired-tabs: cannot save tabs: %s"
                      (error-message-string err))))))

(defun dired-tabs--restore ()
  "Load the tabs saved by a previous session, once.
Tabs whose directory has disappeared are dropped.  Nothing is displayed;
the next tab command or outside `dired' call picks the tabs up."
  (unless dired-tabs--restored
    (setq dired-tabs--restored t)
    (when (and dired-tabs-save-file
               (null dired-tabs--list)
               (file-readable-p dired-tabs-save-file))
      (condition-case err
          (let* ((data (with-temp-buffer
                         (insert-file-contents dired-tabs-save-file)
                         (read (current-buffer))))
                 (tabs (and (eq (plist-get data :version) 1)
                            (cl-loop for (num dir file) in (plist-get data :tabs)
                                     when (and (natnump num) (stringp dir)
                                               (or (file-remote-p dir)
                                                   (file-directory-p dir)))
                                     collect (dired-tabs--make
                                              :num num :dir dir
                                              :file (and (stringp file) file))))))
            (when tabs
              (setq dired-tabs--list tabs)
              (dired-tabs--sort)
              (let ((cur (plist-get data :current)))
                (setq dired-tabs--current
                      (if (and (natnump cur) (dired-tabs--find cur))
                          cur
                        (dired-tabs-tab-num (car dired-tabs--list)))))))
        (error (message "dired-tabs: cannot read %s: %s"
                        dired-tabs-save-file (error-message-string err)))))))

(add-hook 'kill-emacs-hook #'dired-tabs--write)

;; ---------------------------------------------------------------------
;; Tab bar (header line)
;; ---------------------------------------------------------------------

(defconst dired-tabs--header-spec '(:eval (dired-tabs--format))
  "Value of `header-line-format' while the tab bar is visible.")

(defun dired-tabs--name (dir)
  "Return the short display name of DIR: its last component, or \"/\"."
  (let ((name (file-name-nondirectory (directory-file-name dir))))
    (if (string-empty-p name) "/" name)))

(defun dired-tabs--shorten (label max)
  "Truncate LABEL to at most MAX columns, ending with an ellipsis.
Uses display width, so double-width (CJK) characters are handled."
  (if (<= (string-width label) max)
      label
    (truncate-string-to-width label (max 2 max) nil nil "…")))

(defun dired-tabs--entries (cap cur-cap)
  "Return (NUM LABEL CURRENT) for every tab.
Labels are shortened to CAP columns, or CUR-CAP for the current tab."
  (mapcar
   (lambda (tab)
     (let* ((num (dired-tabs-tab-num tab))
            (current (= num dired-tabs--current))
            ;; The current tab's saved dir is stale until we leave it.
            (dir (if current default-directory (dired-tabs-tab-dir tab))))
       (list num
             (dired-tabs--shorten (dired-tabs--name dir) (if current cur-cap cap))
             current)))
   dired-tabs--list))

(defun dired-tabs--entry-width (entry)
  "Return the display width of ENTRY as drawn: \" N label \"."
  (+ 3 (length (number-to-string (car entry))) (string-width (cadr entry))))

(defun dired-tabs--total (entries)
  "Return the total width of ENTRIES, including the separators."
  (+ (apply #'+ (mapcar #'dired-tabs--entry-width entries))
     (max 0 (1- (length entries)))))

(defun dired-tabs--window (entries avail)
  "Choose which of ENTRIES to show in AVAIL columns, centred on the current one.
Return (HIDDEN-LEFT VISIBLE HIDDEN-RIGHT), leaving room for the two
\"‹N\" / \"N›\" markers."
  (let* ((n (length entries))
         (lo (or (cl-position t entries :key #'caddr) 0))
         (hi lo))
    (cl-flet ((width (from to)
                (+ (dired-tabs--total (cl-subseq entries from (1+ to)))
                   (if (> from 0) (+ 3 (length (number-to-string from))) 0)
                   (if (< to (1- n)) (+ 3 (length (number-to-string (- n to 1)))) 0))))
      (let ((grew t))
        (while grew
          (setq grew nil)
          (when (and (> lo 0) (<= (width (1- lo) hi) avail))
            (cl-decf lo)
            (setq grew t))
          (when (and (< hi (1- n)) (<= (width lo (1+ hi)) avail))
            (cl-incf hi)
            (setq grew t)))))
    (list lo (cl-subseq entries lo (1+ hi)) (- n hi 1))))

(defun dired-tabs--render-entry (entry)
  "Return the propertized string for ENTRY."
  (pcase-let ((`(,num ,label ,current) entry))
    (propertize (format " %d %s " num (replace-regexp-in-string "%" "%%" label))
                'face (if current 'dired-tabs-current 'dired-tabs-inactive))))

(defun dired-tabs--format ()
  "Render the tab bar to fit the window, or nil when there is only one tab.
Labels are truncated; if that is not enough, the bar is squeezed down to
`dired-tabs-min-label-width', and finally tabs far from the current one
are hidden behind \"‹N\" / \"N›\" markers."
  (when (cdr dired-tabs--list)
    (let* ((avail (max 20 (- (window-width) 2)))
           (cap dired-tabs-label-width)
           (cur-cap (max cap dired-tabs-current-label-width))
           (entries (dired-tabs--entries cap cur-cap))
           (hidden-left 0)
           (hidden-right 0)
           (shrinking t))
      ;; 1. Shrink the labels (others first, the current tab last).
      (while (and shrinking (> (dired-tabs--total entries) avail))
        (cond ((> cap dired-tabs-min-label-width)
               (setq cap (1- cap)))
              ((> cur-cap dired-tabs-min-label-width)
               (setq cur-cap (1- cur-cap)))
              (t (setq shrinking nil)))
        (setq entries (dired-tabs--entries cap cur-cap)))
      ;; 2. Still too wide: hide the tabs farthest from the current one.
      (when (> (dired-tabs--total entries) avail)
        (pcase-let ((`(,lo ,visible ,hi) (dired-tabs--window entries avail)))
          (setq hidden-left lo
                hidden-right hi
                entries visible)))
      (mapconcat
       #'identity
       (append
        (when (> hidden-left 0)
          (list (propertize (format " ‹%d " hidden-left) 'face 'dired-tabs-overflow)))
        (mapcar #'dired-tabs--render-entry entries)
        (when (> hidden-right 0)
          (list (propertize (format " %d› " hidden-right) 'face 'dired-tabs-overflow))))
       " "))))

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

(defun dired-tabs--setup-buffer ()
  "Load saved tabs if needed, then show the tab bar in this Dired buffer.
Dired buffers can be created without going through the `dired' command
\(`find-file' on a directory, a directory given on the command line,
`dired-noselect', ...), so restoring only in the `dired' advice is not
enough: the first such buffer would get no header line."
  (dired-tabs--restore)
  (dired-tabs--apply-header))

(add-hook 'dired-mode-hook #'dired-tabs--setup-buffer)

;; ---------------------------------------------------------------------
;; Switching and creating
;; ---------------------------------------------------------------------

(defun dired-tabs--visit (tab)
  "Show TAB's directory in the selected window and restore its cursor."
  (let ((dir (dired-tabs-tab-dir tab)))
    (unless (file-directory-p dir)
      (user-error "Directory no longer exists: %s" dir))
    (let ((dired-tabs--busy t))
      (dired dir))
    (when-let ((file (dired-tabs-tab-file tab)))
      (dired-goto-file file))
    (dired-tabs--refresh)))

(defun dired-tabs--switch (num)
  "Leave the current tab (remembering its state) and activate tab NUM."
  (dired-tabs--save)
  (setq dired-tabs--current num)
  (dired-tabs--visit (dired-tabs--find num)))

(defun dired-tabs--create (num)
  "Create tab NUM as a copy of the current tab and make it current.
The new tab shows the same directory, so no buffer switch is needed."
  (dired-tabs--save)
  (let ((new (dired-tabs--copy (dired-tabs--find dired-tabs--current))))
    (setf (dired-tabs-tab-num new) num)
    (push new dired-tabs--list)
    (dired-tabs--sort)
    (setq dired-tabs--current num)
    (dired-tabs--refresh)
    (message "Created tab %d: %s" num
             (abbreviate-file-name (dired-tabs-tab-dir new)))))

(defun dired-tabs--next-free-number ()
  "Return the number for a new tab.
That is the smallest unused number (up to 9) greater than the current
tab's, else the smallest unused number overall.  The external tab's
number (`dired-tabs-external-tab') is never chosen."
  (let ((used (cons dired-tabs-external-tab
                    (mapcar #'dired-tabs-tab-num dired-tabs--list))))
    (or (cl-loop for n from (1+ dired-tabs--current) to 9
                 unless (memq n used) return n)
        (cl-loop for n from 1
                 unless (memq n used) return n))))

(defun dired-tabs--relative (delta)
  "Switch DELTA tabs away from the current one in number order, wrapping."
  (dired-tabs--ensure)
  (let ((count (length dired-tabs--list)))
    (if (< count 2)
        (message "Only one tab")
      (let ((i (mod (+ (dired-tabs--position) delta) count)))
        (dired-tabs--switch (dired-tabs-tab-num (nth i dired-tabs--list)))))))

;; ---------------------------------------------------------------------
;; Entering Dired from elsewhere
;; ---------------------------------------------------------------------

(defun dired-tabs--enter-external (dir)
  "Pick the tab that should show DIR, which is entered from outside Dired.
DIR must be an absolute directory name.  If a tab already shows DIR it
becomes current; otherwise the external tab (`dired-tabs-external-tab')
is created if needed, pointed at DIR and made current.  Nothing is
displayed here; the caller is about to show DIR itself."
  (let ((existing (seq-find
                   (lambda (tab)
                     (equal (file-name-as-directory (dired-tabs-tab-dir tab)) dir))
                   dired-tabs--list)))
    (if existing
        (setq dired-tabs--current (dired-tabs-tab-num existing))
      (let ((tab (dired-tabs--find dired-tabs-external-tab)))
        (if tab
            (setf (dired-tabs-tab-dir tab) dir
                  (dired-tabs-tab-file tab) nil)
          (push (dired-tabs--make :num dired-tabs-external-tab :dir dir)
                dired-tabs--list)
          (dired-tabs--sort))
        (setq dired-tabs--current dired-tabs-external-tab)))
    (dired-tabs--refresh)))

(defun dired-tabs--dired-advice (orig dirname &rest args)
  "Around advice for `dired'.
When called from a non-Dired buffer, route DIRNAME to the right tab (see
`dired-tabs-external-tab') before calling ORIG with DIRNAME and ARGS.
Tabs saved by a previous session are loaded first."
  (dired-tabs--restore)
  (when (and dired-tabs-external-tab
             dired-tabs--list
             (not dired-tabs--busy)
             (not (derived-mode-p 'dired-mode))
             (stringp dirname)
             (file-directory-p dirname))
    (dired-tabs--enter-external
     (file-name-as-directory (expand-file-name dirname))))
  (apply orig dirname args))

(advice-add 'dired :around #'dired-tabs--dired-advice)

(defun dired-tabs--track ()
  "Keep the current tab's saved directory and cursor file up to date.
This way the tab is correct even if you leave Dired without switching
tabs, e.g. by opening a file."
  (when (and dired-tabs--list
             (derived-mode-p 'dired-mode)
             (eq (current-buffer) (window-buffer)))
    (dired-tabs--save)))

(add-hook 'post-command-hook #'dired-tabs--track)

;; ---------------------------------------------------------------------
;; Commands
;; ---------------------------------------------------------------------

(defun dired-tabs-new ()
  "Open a new tab at the current directory.
It gets the next free number after the current tab, or the smallest free
number if there is none."
  (interactive)
  (dired-tabs--ensure)
  (dired-tabs--create (dired-tabs--next-free-number)))

(defun dired-tabs-goto (n)
  "Switch to tab N, creating it at the current directory if it does not exist.
Interactively, N is the digit key that invoked the command (0-9),
or the prefix argument when called any other way."
  (interactive
   (list (if (and (characterp last-command-event)
                  (<= ?0 last-command-event ?9))
             (- last-command-event ?0)
           (prefix-numeric-value current-prefix-arg))))
  (dired-tabs--ensure)
  (cond
   ((< n 0)
    (user-error "Tab number cannot be negative"))
   ((= n dired-tabs--current)
    (message "Already on tab %d" n))
   ((dired-tabs--find n)
    (dired-tabs--switch n))
   (t
    (dired-tabs--create n))))

(defun dired-tabs-next ()
  "Switch to the next tab in number order (wraps around)."
  (interactive)
  (dired-tabs--relative 1))

(defun dired-tabs-prev ()
  "Switch to the previous tab in number order (wraps around)."
  (interactive)
  (dired-tabs--relative -1))

(defun dired-tabs-close ()
  "Close the current tab and activate the previous one in number order.
The last remaining tab cannot be closed."
  (interactive)
  (dired-tabs--ensure)
  (when (< (length dired-tabs--list) 2)
    (user-error "Cannot close the last tab"))
  (let ((i (dired-tabs--position)))
    (setq dired-tabs--list (delq (nth i dired-tabs--list) dired-tabs--list)
          dired-tabs--current (dired-tabs-tab-num
                               (nth (max 0 (1- i)) dired-tabs--list)))
    (dired-tabs--visit (dired-tabs--find dired-tabs--current))))

(defun dired-tabs--swap (delta)
  "Exchange the current tab's number with its neighbour DELTA places away."
  (dired-tabs--ensure)
  (let* ((i (dired-tabs--position))
         (j (+ i delta)))
    (cond
     ((or (< j 0) (>= j (length dired-tabs--list)))
      (message "Already at the %s end" (if (< j 0) "left" "right")))
     ((or (eql dired-tabs--current dired-tabs-external-tab)
          (eql (dired-tabs-tab-num (nth j dired-tabs--list))
               dired-tabs-external-tab))
      (message "Tab %d is the external tab and cannot be moved"
               dired-tabs-external-tab))
     (t
      (dired-tabs--save)
      (let ((a (nth i dired-tabs--list))
            (b (nth j dired-tabs--list)))
        (cl-rotatef (dired-tabs-tab-num a) (dired-tabs-tab-num b))
        (setq dired-tabs--current (dired-tabs-tab-num a)))
      (dired-tabs--sort)
      (dired-tabs--refresh)))))

(defun dired-tabs-move-left ()
  "Swap the current tab's number with the tab to its left."
  (interactive)
  (dired-tabs--swap -1))

(defun dired-tabs-move-right ()
  "Swap the current tab's number with the tab to its right."
  (interactive)
  (dired-tabs--swap 1))

(defun dired-tabs--non-dired-buffer ()
  "Return the most recently used live non-Dired buffer, or nil.
This window's buffer history is searched first, then all buffers.
Internal buffers (names starting with a space) are skipped."
  (let ((ok (lambda (buf)
              (and (buffer-live-p buf)
                   (not (eq buf (current-buffer)))
                   (not (string-prefix-p " " (buffer-name buf)))
                   (not (provided-mode-derived-p
                         (buffer-local-value 'major-mode buf) 'dired-mode))))))
    (or (seq-some (lambda (entry) (and (funcall ok (car entry)) (car entry)))
                  (window-prev-buffers))
        (seq-find ok (buffer-list)))))

(defun dired-tabs-toggle (&optional jump)
  "Leave Dired without touching any tab, or come back to the current tab.
In a Dired buffer, switch this window to the most recent NON-Dired
buffer, skipping any Dired buffers you navigated through: every tab
keeps its directory and cursor, and the Dired buffers stay alive.
\(A window opened just for Dired, with no history, is closed instead.)
In any other buffer, return to the current tab's Dired; if the file you
are visiting lives in that directory, the cursor lands on it.
With a prefix argument (JUMP), or when no tab exists yet, call
`dired-jump' instead, which shows the directory of the current file
\(routed through the external tab, see `dired-tabs-external-tab').
Tabs saved by a previous session count as existing tabs."
  (interactive "P")
  (dired-tabs--restore)
  (cond
   ((derived-mode-p 'dired-mode)
    (dired-tabs--save)
    (let ((target (dired-tabs--non-dired-buffer)))
      (if (and target
               ;; A fresh window made for Dired has no history: close it.
               (or (window-prev-buffers) (one-window-p)))
          (switch-to-buffer target)
        (quit-window))))
   ((or jump (null dired-tabs--list))
    (dired-jump))
   (t
    (let ((file buffer-file-name)
          (tab (dired-tabs--find dired-tabs--current)))
      (dired-tabs--visit tab)
      (when (and file
                 (equal (file-name-directory file)
                        (file-name-as-directory (dired-tabs-tab-dir tab))))
        (dired-goto-file file))))))

(provide 'dired-tabs)
;;; dired-tabs.el ends here
