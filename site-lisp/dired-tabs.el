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
;;   H / L    previous / next existing tab, in number order (wraps around)
;;   { / }    swap the current tab's number with its left / right neighbour
;;   C-c C-c  close the current tab (the last tab cannot be closed)
;;   (toggle) `dired-tabs-toggle': leave Dired (tabs stay intact), or come
;;            back to the current tab from any other buffer
;;
;; Model: a tab is a number, a directory, and the file the cursor was on
;; when you left it.  Tab numbers are identities: you can have tabs 1, 3
;; and 7 and nothing else, and the tab bar shows them in number order.
;; There is a single window; switching tabs visits the target directory.
;; If a live Dired buffer for it already exists it is simply switched to,
;; with no disk access at all; otherwise `dired' is called.  Because a tab
;; only remembers a directory, it does not matter how you navigate inside
;; it (`^', RET, `find-alternate-file', ...).
;;
;; Buffer lifetime is controlled by `dired-tabs-kill-old-buffer'.  When
;; nil, the Dired buffer you leave is always kept alive.  When non-nil --
;; the default follows `dired-kill-when-opening-new-dired-buffer' -- the
;; old Dired buffer is killed after a tab switch, EXCEPT when some tab
;; still shows its directory: those buffers stay alive so that switching
;; back to a tab is instant (important on slow external drives) and
;; regular Dired marks survive.  Only buffers no tab refers to are killed.
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
;; Slow media: switching to a tab whose directory is under one of
;; `dired-tabs-slow-dir-roots' first reads that directory in a background
;; process, so a spun-down USB disk or an unmounted automount point cannot
;; freeze Emacs: the minibuffer says that the disk is waking up, and the
;; tab is shown as soon as the disk answers.  A warm directory answers
;; within `dired-tabs-wake-grace' and is switched to normally.  Set
;; `dired-tabs-wake-slow-dirs' to nil to always switch synchronously.
;;
;; The tab bar is shown in the header line of Dired buffers while there
;; are two or more tabs, and hidden again when only one tab is left.  The
;; rendered bar is cached and only recomputed when the tabs, the window
;; width or the current directory change.
;;
;; Persistence: the tabs (number, directory, cursor file, and which tab
;; was current) are written to `dired-tabs-save-file' when Emacs exits,
;; and also a few seconds after the last structural change while Emacs is
;; idle, so a crash loses little.  The file is read lazily, the first time
;; a tab command runs or `dired' is called, so there is no load-order
;; issue and no dependency on `savehist'.  Restoring does NOT touch the
;; disk for the saved directories (important when external drives are
;; asleep or unmounted); a missing directory is reported when you switch
;; to that tab.  Set `dired-tabs-save-file' to nil to disable.
;;
;; Works with `dired-satchel': packed/flagged marks are redrawn by its
;; `dired-after-readin-hook' whenever a Dired buffer gets (re)created.
;;
;; Performance tips for slow / external drives (outside this package):
;;
;;   (setq dired-free-space nil)          ; Emacs 29+: no `df' per listing
;;   (setq dired-auto-revert-buffer nil)  ; no `stat' when revisiting
;;
;; Also consider turning off `global-auto-revert-non-file-buffers' for
;; Dired (it polls directories and wakes sleeping drives), and be wary of
;; packages that process every file after readin (icons, git info, ...).
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
;;         ("H" . dired-tabs-prev)
;;         ("L" . dired-tabs-next)
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
(require 'subr-x)

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
  "File in which the tabs are saved.
It is written when Emacs exits and shortly after structural changes
\(see `dired-tabs-save-delay').  The file is read lazily, the first time
a tab command runs or `dired' is called.  If nil, tabs are not
persisted."
  :type '(choice (const :tag "Do not persist" nil) file)
  :group 'dired-tabs)

(defcustom dired-tabs-save-delay 5
  "Seconds of idle time after a structural change before saving the tabs."
  :type 'number
  :group 'dired-tabs)

(defcustom dired-tabs-kill-old-buffer
  (bound-and-true-p dired-kill-when-opening-new-dired-buffer)
  "When non-nil, kill the old Dired buffer after switching tabs.
This avoids lingering buffers for directories you merely passed through.
A buffer is never killed if it is still visible in another window, or if
some tab still shows its directory (so going back to that tab is
instant).  Regular Dired marks (`*') in a killed buffer are lost;
`dired-satchel' marks are redrawn automatically."
  :type 'boolean
  :group 'dired-tabs)

(defcustom dired-tabs-wake-slow-dirs t
  "When non-nil, open tabs on slow media without freezing Emacs.
Switching to a tab whose directory is under one of
`dired-tabs-slow-dir-roots' first reads that directory in a background
process.  While a sleeping USB disk spins up (or an automount point is
mounted) the minibuffer says so and Emacs stays responsive; the
directory is shown as soon as the disk answers.  Switching to a live
Dired buffer never touches the disk and is unaffected."
  :type 'boolean
  :group 'dired-tabs)

(defcustom dired-tabs-slow-dir-roots '("/run/media/" "/media/" "/mnt/")
  "Directory prefixes whose tabs are woken asynchronously.
See `dired-tabs-wake-slow-dirs'.  Only the name is matched, nothing is
stat'ed, so a sleeping disk is not touched by the check itself.  TRAMP
names are never probed."
  :type '(repeat string)
  :group 'dired-tabs)

(defcustom dired-tabs-wake-grace 0.15
  "Seconds to wait for a slow directory before probing in the background.
If the directory answers within this delay -- a warm disk, or a page
cache hit -- the tab switch simply completes and nothing is shown.
Increase it for very large directories; 0 always probes in the
background."
  :type 'number
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

(defcustom dired-tabs-disambiguate t
  "When non-nil, tell apart tabs whose directories share a name.
Such tabs get parent components prepended, e.g. \"DiskA/Photos\" and
\"DiskB/Photos\", only as many as needed.  Truncation (see
`dired-tabs-label-width') cuts the end of a label, so the distinguishing
parent part stays visible."
  :type 'boolean
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

(defvar dired-tabs--version 0
  "Bumped whenever the tabs change structurally (invalidates the bar cache).")

(defvar dired-tabs--bar-cache nil
  "(VERSION WIDTH DIR . STRING) of the last rendered tab bar, or nil.")

(defvar dired-tabs--last-seen nil
  "(BUFFER DIR . POINT) at the last tracked command, or nil.
Lets `dired-tabs--track' return immediately when nothing has moved.")

(defvar dired-tabs--wake-process nil
  "Background process that is waking a slow directory, or nil.
Only one runs at a time; a new tab switch kills it.")

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
          dired-tabs--current 1)
    (cl-incf dired-tabs--version)))

(defun dired-tabs--save ()
  "Remember the directory and cursor file of the current tab.
Does nothing when the current buffer is not a Dired buffer, or when the
current tab number has no tab (which must never signal: this runs from
`post-command-hook')."
  (when (derived-mode-p 'dired-mode)
    (when-let* ((tab (dired-tabs--find dired-tabs--current)))
      (setf (dired-tabs-tab-dir tab) (expand-file-name default-directory)
            (dired-tabs-tab-file tab) (dired-get-filename nil t)))))

;; ---------------------------------------------------------------------
;; Persistence
;; ---------------------------------------------------------------------

;; Make sure the `let' in `dired-tabs--restore' binds it dynamically.
(defvar read-eval)

(defvar dired-tabs--restored nil
  "Non-nil once we have tried to read `dired-tabs-save-file' this session.")

(defvar dired-tabs--write-timer nil
  "Pending idle timer that will save the tabs, or nil.")

(defun dired-tabs--write ()
  "Write the tabs to `dired-tabs-save-file'.
Does nothing if there are no live tabs, so a session that never used
tabs does not overwrite the saved state."
  (when (and dired-tabs-save-file dired-tabs--list)
    (condition-case err
        (progn
          ;; Make sure the current tab is up to date if we are in Dired.
          (dired-tabs--save)
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

(defun dired-tabs--write-now ()
  "Timer function: clear the timer slot, then save."
  (setq dired-tabs--write-timer nil)
  (dired-tabs--write))

(defun dired-tabs--schedule-write ()
  "Save the tabs after `dired-tabs-save-delay' idle seconds (debounced)."
  (when dired-tabs-save-file
    (when (timerp dired-tabs--write-timer)
      (cancel-timer dired-tabs--write-timer))
    (setq dired-tabs--write-timer
          (run-with-idle-timer dired-tabs-save-delay nil
                               #'dired-tabs--write-now))))

(defun dired-tabs--restore ()
  "Load the tabs saved by a previous session, once.
Saved directories are NOT checked for existence here, so that sleeping or
unmounted external drives are never touched; `dired-tabs--visit' reports
a missing directory when you switch to that tab.  Nothing is displayed;
the next tab command or outside `dired' call picks the tabs up."
  (unless dired-tabs--restored
    (setq dired-tabs--restored t)
    (when (and dired-tabs-save-file
               (null dired-tabs--list)
               (file-readable-p dired-tabs-save-file))
      (condition-case err
          (let* ((data (with-temp-buffer
                         (insert-file-contents dired-tabs-save-file)
                         ;; Never evaluate anything found in the file.
                         (let ((read-eval nil))
                           (read (current-buffer)))))
                 (tabs (and (eq (plist-get data :version) 1)
                            (cl-loop for (num dir file) in (plist-get data :tabs)
                                     when (and (natnump num) (stringp dir))
                                     collect (dired-tabs--make
                                              :num num :dir dir
                                              :file (and (stringp file) file))))))
            (when tabs
              (setq dired-tabs--list tabs)
              (dired-tabs--sort)
              (cl-incf dired-tabs--version)
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

(defun dired-tabs--components (dir)
  "Return the path components of DIR, innermost first.
For a remote name the \"/ssh:host:\" part counts as one component."
  (nreverse (split-string (directory-file-name dir) "/" t)))

(defun dired-tabs--join (comps depth)
  "Join the DEPTH innermost components of COMPS (innermost first) with \"/\"."
  (if (null comps)
      "/"
    (mapconcat #'identity (reverse (seq-take comps depth)) "/")))

(defun dired-tabs--labels (dirs)
  "Return a display label for each directory in DIRS, in the same order.
A label is normally the last path component.  While several tabs would
get the same label but show different directories, the clashing labels
are extended with parent components (\"Photos\" becomes \"DiskB/Photos\")
until they differ or run out of components.  With
`dired-tabs-disambiguate' nil, only the last component is used."
  (let* ((comps (mapcar #'dired-tabs--components dirs))
         (depths (make-list (length dirs) 1))
         (labels (cl-mapcar #'dired-tabs--join comps depths)))
    (when dired-tabs-disambiguate
      (let ((changed t))
        (while changed
          (setq changed nil)
          (let ((i 0))
            (dolist (label labels)
              (when (and (> (cl-count label labels :test #'equal) 1)
                         (< (nth i depths) (length (nth i comps))))
                ;; Only grow entries that clash with a *different* path,
                ;; not tabs that show exactly the same directory.
                (when (cl-some (lambda (other-label other-dir)
                                 (and (equal other-label label)
                                      (not (equal other-dir (nth i dirs)))))
                               labels dirs)
                  (cl-incf (nth i depths))
                  (setq changed t)))
              (cl-incf i)))
          (setq labels (cl-mapcar #'dired-tabs--join comps depths)))))
    labels))

(defun dired-tabs--shorten (label max)
  "Truncate LABEL to at most MAX columns, ending with an ellipsis.
Uses display width, so double-width (CJK) characters are handled."
  (if (<= (string-width label) max)
      label
    (truncate-string-to-width label (max 2 max) nil nil "…")))

(defun dired-tabs--entries (cap cur-cap)
  "Return (NUM LABEL CURRENT) for every tab.
Labels are shortened to CAP columns, or CUR-CAP for the current tab."
  (let* ((dirs (mapcar
                (lambda (tab)
                  ;; The current tab's saved dir is stale until we leave it.
                  (if (= (dired-tabs-tab-num tab) dired-tabs--current)
                      default-directory
                    (dired-tabs-tab-dir tab)))
                dired-tabs--list))
         (labels (dired-tabs--labels dirs)))
    (cl-mapcar
     (lambda (tab label)
       (let* ((num (dired-tabs-tab-num tab))
              (current (= num dired-tabs--current)))
         (list num
               (dired-tabs--shorten label (if current cur-cap cap))
               current)))
     dired-tabs--list labels)))

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

(defun dired-tabs--render-bar ()
  "Render the tab bar to fit the window (uncached).
Labels are truncated; if that is not enough, the bar is squeezed down to
`dired-tabs-min-label-width', and finally tabs far from the current one
are hidden behind \"‹N\" / \"N›\" markers."
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
     " ")))

(defun dired-tabs--format ()
  "Return the tab bar for the header line, or nil when there is only one tab.
The result is cached in a single slot, keyed on the tab version, the
window width and the current directory (the current tab's label)."
  (when (cdr dired-tabs--list)
    (let ((c dired-tabs--bar-cache)
          (w (window-width)))
      (if (and c
               (eql (car c) dired-tabs--version)
               (eql (cadr c) w)
               (equal (nth 2 c) default-directory))
          (nthcdr 3 c)
        (let ((s (dired-tabs--render-bar)))
          (setq dired-tabs--bar-cache
                (cl-list* dired-tabs--version w default-directory s))
          s)))))

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
  "Update the tab bar in every Dired buffer and schedule a save.
Only buffers registered in `dired-buffers' are visited, not the whole
`buffer-list'."
  (cl-incf dired-tabs--version)
  (setq dired-tabs--last-seen nil)
  (dolist (entry dired-buffers)
    (when (buffer-live-p (cdr entry))
      (with-current-buffer (cdr entry)
        (dired-tabs--apply-header))))
  (force-mode-line-update t)
  (dired-tabs--schedule-write))

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

(defun dired-tabs--dir-in-use-p (buf)
  "Non-nil if some tab shows the directory of the Dired buffer BUF."
  (let ((d (file-name-as-directory
            (buffer-local-value 'default-directory buf))))
    (seq-some (lambda (tab)
                (equal (file-name-as-directory (dired-tabs-tab-dir tab)) d))
              dired-tabs--list)))

(defun dired-tabs--maybe-kill (old)
  "Kill the Dired buffer OLD we just left, if `dired-tabs-kill-old-buffer'.
Never kills a buffer that is still shown in some window, that some tab
still points at, nor the buffer we are in now, nor a non-Dired buffer."
  (when (and dired-tabs-kill-old-buffer
             (buffer-live-p old)
             (not (eq old (current-buffer)))
             (derived-mode-p 'dired-mode)
             (provided-mode-derived-p
              (buffer-local-value 'major-mode old) 'dired-mode)
             (not (get-buffer-window old t))
             (not (dired-tabs--dir-in-use-p old)))
    (kill-buffer old)))

(defun dired-tabs--slow-dir-p (dir)
  "Non-nil if DIR may live on media that is slow to wake up.
Nothing is stat'ed here: only the name is inspected, so asking the
question never touches a sleeping disk."
  (and dired-tabs-wake-slow-dirs
       (not (file-remote-p dir))
       (seq-some (lambda (root) (string-prefix-p root dir))
                 dired-tabs-slow-dir-roots)))

(defun dired-tabs--wake-program ()
  "Return the absolute name of the `ls' program, or nil if there is none.
The probe uses the same program Dired itself lists directories with."
  (executable-find (or insert-directory-program "ls")))

(defun dired-tabs--cancel-wake ()
  "Kill the pending wake-up process, if any.
The process is forgotten first, so that its sentinel does nothing."
  (when dired-tabs--wake-process
    (let ((proc dired-tabs--wake-process))
      (setq dired-tabs--wake-process nil)
      (when (process-live-p proc)
        (delete-process proc)))))

(defun dired-tabs--cancel-wake-on-command ()
  "Abandon a pending background switch when another command starts.
Runs from `pre-command-hook', so a directory that is still being woken
never replaces the buffer under the user's hands long after the switch
was asked for.  The tab remains the one that is on screen."
  (when dired-tabs--wake-process
    (dired-tabs--cancel-wake)))

(defun dired-tabs--wake (dir cont)
  "Read DIR in a background process, then call CONT.
Emacs stays responsive while a sleeping disk spins up or an automount
point gets mounted.  If DIR answers within `dired-tabs-wake-grace' the
switch stays synchronous; otherwise CONT runs from the process sentinel.
Nothing is committed before CONT runs, so a switch that cannot complete
\(the minibuffer is in use, the directory disappeared) leaves the tabs
untouched and can simply be repeated."
  (let ((proc (make-process
               :name "dired-tabs-wake"
               :command (list (dired-tabs--wake-program) "-A" dir)
               :connection-type 'pipe
               :noquery t
               :buffer nil
               :filter #'ignore)))
    ;; A warm directory answers at once: keep the switch synchronous then.
    (accept-process-output proc dired-tabs-wake-grace)
    (if (not (process-live-p proc))
        (progn
          (delete-process proc)
          (funcall cont))
      (setq dired-tabs--wake-process proc)
      (message "dired-tabs: waking %s…" (abbreviate-file-name dir))
      (set-process-sentinel
       proc
       (lambda (p _event)
         (when (eq p dired-tabs--wake-process)
           (setq dired-tabs--wake-process nil)
           (when (memq (process-status p) '(exit signal))
             (message "")
             (if (active-minibuffer-window)
                 ;; Do not switch buffers under a prompt; the tab stays
                 ;; current and pressing its digit again is now instant.
                 (message "dired-tabs: %s is ready" (abbreviate-file-name dir))
               (condition-case err
                   (funcall cont)
                 (error (message "dired-tabs: %s"
                                 (error-message-string err))))))))))))

(defun dired-tabs--show (tab old live)
  "Display TAB's directory in the selected window and restore its cursor.
OLD is the buffer the switch started from; LIVE, if non-nil, is an
existing Dired buffer for the directory, which is reused as is."
  (if live
      (switch-to-buffer live)
    (let ((dir (dired-tabs-tab-dir tab)))
      (unless (file-directory-p dir)
        (user-error "Directory no longer exists: %s" dir))
      (let ((dired-tabs--busy t))
        (dired dir))))
  ;; The switch only happens here, so the active tab always matches what
  ;; is on screen, even while a slow directory is still being woken.
  (setq dired-tabs--current (dired-tabs-tab-num tab))
  (dired-tabs--maybe-kill old)
  (when-let* ((file (dired-tabs-tab-file tab)))
    (unless (equal file (dired-get-filename nil t))
      (dired-goto-file file)))
  (dired-tabs--refresh))

(defun dired-tabs--visit (tab &optional then)
  "Show TAB's directory in the selected window and restore its cursor.
Call THEN, if non-nil, once the directory is displayed.
If a live Dired buffer for the directory exists (and
`dired-auto-revert-buffer' is off) it is switched to without any disk
access; otherwise `dired' is called.  A directory on slow media is first
read in a background process (see `dired-tabs-wake-slow-dirs'), in which
case this function returns before the switch is complete."
  (dired-tabs--cancel-wake)
  (let* ((dir (dired-tabs-tab-dir tab))
         (old (current-buffer))
         (live (and (not dired-auto-revert-buffer)
                    (dired-find-buffer-nocreate dir)))
         (cont (lambda ()
                 (dired-tabs--show tab old live)
                 (when then (funcall then)))))
    (if (or live
            (not (dired-tabs--slow-dir-p dir))
            (not (dired-tabs--wake-program)))
        (funcall cont)
      (dired-tabs--wake dir cont))))

(defun dired-tabs--switch (num)
  "Leave the current tab (remembering its state) and activate tab NUM.
The tab only becomes current once its directory is on screen, which may
be delayed for a slow disk (see `dired-tabs--wake')."
  (dired-tabs--save)
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
tabs, e.g. by opening a file.  A change of directory also schedules a
save.  When the buffer, its `default-directory' object and point are all
unchanged since the last call, return immediately.  Errors are demoted
to messages: an error in `post-command-hook' would make Emacs drop the
hook and tracking would silently stop."
  (when (and dired-tabs--list
             (derived-mode-p 'dired-mode)
             (eq (current-buffer) (window-buffer)))
    (let ((seen dired-tabs--last-seen))
      (unless (and seen
                   (eq (car seen) (current-buffer))
                   (eq (cadr seen) default-directory)
                   (eql (cddr seen) (point)))
        (with-demoted-errors "dired-tabs: %S"
          (let ((moved (not (and seen (eq (cadr seen) default-directory)))))
            (dired-tabs--save)
            (setq dired-tabs--last-seen
                  (cons (current-buffer) (cons default-directory (point))))
            (when moved
              (dired-tabs--schedule-write))))))))

(add-hook 'post-command-hook #'dired-tabs--track)

;; A switch that is still waiting for a slow disk is dropped as soon as
;; the user does something else; see `dired-tabs--cancel-wake-on-command'.
(add-hook 'pre-command-hook #'dired-tabs--cancel-wake-on-command)

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
keeps its directory and cursor.  (A window opened just for Dired, with
no history, is closed instead.)
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
      (dired-tabs--visit
       tab
       (lambda ()
         (when (and file
                    (equal (file-name-directory file)
                           (file-name-as-directory (dired-tabs-tab-dir tab))))
           (dired-goto-file file))))))))

(provide 'dired-tabs)
;;; dired-tabs.el ends here
