;;; dired-satchel.el --- Stash files in Dired, then copy/move/delete them, live or scripted -*- lexical-binding: t -*-

;;; Commentary:

;; `dired-satchel' lets you "pack" (stash) files from one or more Dired
;; buffers into a single satchel, then "deliver" them elsewhere with a
;; copy or move, or flag files for deletion -- either immediately, or
;; accumulated into a shell script (rsync for copy/move, rm for delete)
;; that you review and run later.
;;
;; Two modes, same keys:
;; - LIVE mode:   actions run immediately via built-in Dired primitives.
;; - SCRIPT mode: actions queue an operation (copy/move/delete) into
;;                `satchel--script-ops', a purely in-memory list.
;;
;; Script file lifecycle (deliberately simple):
;;
;; - The queue lives in memory only.  Packing, copying, moving,
;;   deleting and unmarking never touch the disk.
;; - `satchel-script-file' is written ONLY by `satchel-script-execute',
;;   right before it runs the script.
;; - Therefore, if the script file exists on disk, it is a LEFTOVER
;;   from an interrupted or failed run (reboot, crash, rsync error).
;;   It is never overwritten.
;; - A leftover script is removed in exactly two ways:
;;     1. it runs to completion successfully (automatic cleanup), or
;;     2. you call `satchel-script-clear' manually.
;; - `satchel-script-execute' with an empty queue runs the leftover
;;   script as-is.  With a non-empty queue and a leftover script on
;;   disk it refuses: run the leftover first (empty the queue), or
;;   clear it.
;; - The generated script is idempotent (rsync skips finished files,
;;   `--partial' resumes big files, rm -f ignores missing files), so
;;   re-running a leftover script is safe.
;;
;; Unmarking a queued file (the standard `u'/`U' Dired keys) removes
;; its command from the in-memory queue: a copy/move op loses the file
;; from its rsync source list (or is dropped if it becomes empty); a
;; delete op is dropped outright.
;;
;; Files that are packed or flagged for deletion get a persistent visual
;; mark that is redrawn automatically whenever a Dired buffer is
;; (re)read -- including after `find-alternate-file'.
;;
;; Use `satchel-script-progress' to see how many operations/files are
;; queued, or to jump to the live output of a running script.
;;
;; Suggested keybindings:
;;
;;   (:map dired-mode-map
;;         ("y" . satchel-pack)
;;         ("Y" . satchel-unpack)
;;         ("p" . satchel-action-copy-here)
;;         ("P" . satchel-action-move-here)
;;         ("d" . satchel-action-flag-deletion)
;;         ("x" . satchel-action-execute)
;;         ("v" . satchel-transient))
;;
;; Toggle LIVE vs SCRIPT mode with `satchel-toggle-script-mode'.

;;; Code:

(require 'dired)
(require 'transient)
(require 'cl-lib)
(require 'notifications)
(require 'compile)

(defgroup dired-satchel nil
  "Stash Dired files and copy/move/delete them, live or scripted."
  :group 'dired)

;; ---------------------------------------------------------------------
;; Customizable state
;; ---------------------------------------------------------------------

(defcustom satchel-script-file
  (expand-file-name "dired-satchel-commands.sh"
                    (if (boundp 'my-emacs-cache-dir)
                        my-emacs-cache-dir
                      user-emacs-directory))
  "Path to the generated rsync/rm script file."
  :type 'file
  :group 'dired-satchel)

(defcustom satchel-marker-char ?S
  "Marker character used to visually flag files packed into the satchel."
  :type 'character
  :group 'dired-satchel)

(defcustom satchel-notify-on-finish t
  "When non-nil, show a desktop notification via `notifications-notify'
\(D-Bus\) once the satchel script finishes running (success or failure)."
  :type 'boolean
  :group 'dired-satchel)

(defcustom satchel-notify-persistent-threshold 60
  "Script runtime, in seconds, at or above which the finish
notification is persistent (stays until dismissed).  Shorter runs get
a normal, auto-expiring notification (see `satchel-notify-short-timeout')."
  :type 'number
  :group 'dired-satchel)

(defcustom satchel-notify-short-timeout 3000
  "Timeout, in milliseconds, for the finish notification when the
script ran for less than `satchel-notify-persistent-threshold' seconds.
Passed straight to `notifications-notify' as :timeout."
  :type 'integer
  :group 'dired-satchel)

(defvar satchel-stash nil
  "List of absolute file names currently packed into the satchel.")

(defvar satchel-script-mode t
  "When non-nil, satchel actions queue shell commands for
`satchel-script-file' instead of executing immediately.
This is a global toggle shared by all Dired buffers.")

;; ---------------------------------------------------------------------
;; Persistent marks (survive buffer recreation, e.g. tab switches)
;; ---------------------------------------------------------------------

(defvar satchel-persistent-marks (make-hash-table :test 'equal)
  "Map of absolute file name -> dired marker char.
Used to redraw pack/delete marks after a Dired buffer is recreated,
e.g. via `find-alternate-file' when switching tabs.")

(defun satchel--record-mark (file char)
  "Remember CHAR as the persistent mark of FILE."
  (puthash (expand-file-name file) char satchel-persistent-marks))

(defun satchel--forget-mark (file)
  "Forget the persistent mark of FILE."
  (remhash (expand-file-name file) satchel-persistent-marks))

(defun satchel--visually-mark-file (file char)
  "Set FILE's mark column to CHAR in the current Dired buffer, if present."
  (when (derived-mode-p 'dired-mode)
    (save-excursion
      (goto-char (point-min))
      (let (done)
        (while (and (not done) (not (eobp)))
          (if (equal (dired-get-filename nil t) file)
              (progn
                (if (eq char ?\s)
                    (dired-unmark 1)
                  (let ((dired-marker-char char))
                    (dired-mark 1)))
                (setq done t))
            (forward-line 1)))
        done))))

(defun satchel--mark-in-all-buffers (file char)
  "Apply CHAR as FILE's mark in every live Dired buffer showing it."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (satchel--visually-mark-file file char))))

(defun satchel-restore-persistent-marks ()
  "Redraw marks recorded in `satchel-persistent-marks' for the files
in the current Dired buffer.  Meant for `dired-after-readin-hook'."
  (when (derived-mode-p 'dired-mode)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (let* ((file (dired-get-filename nil t))
               (char (and file (gethash file satchel-persistent-marks))))
          (if char
              ;; `dired-mark' marks the current line and advances one line,
              ;; matching the (forward-line 1) fallback below.
              (let ((dired-marker-char char))
                (dired-mark 1))
            (forward-line 1)))))))

(add-hook 'dired-after-readin-hook #'satchel-restore-persistent-marks)

;; ---------------------------------------------------------------------
;; Script operation queue (purely in-memory)
;; ---------------------------------------------------------------------

(cl-defstruct (satchel-op (:constructor satchel-op-create))
  "One not-yet-run entry in the satchel script.
TYPE is `copy', `move', or `delete'.  FILES is the list of absolute
file names involved (a single element for `delete').  DEST is the
destination directory for `copy'/`move', nil for `delete'."
  id type files dest)

(defvar satchel--script-ops nil
  "List of `satchel-op' structs describing every queued operation.
In memory only.  The script file is rendered from this list by
`satchel-script-execute' (and previewed by `satchel-script-open'),
never hand-appended to.")

(defvar satchel--op-id-counter 0
  "Monotonic counter used to give each `satchel-op' a unique id.")

(defvar satchel--script-pending-cleanup nil
  "Files whose persistent marks should be cleared once the in-flight
script run finishes successfully.")

(defvar satchel--script-running nil
  "Non-nil while the satchel script's compilation process is alive.")

(defvar satchel--script-start-time nil
  "Time (as returned by `current-time') at which the current script run
was launched.  Used to decide whether the finish notification is
persistent or short-lived.  Nil when no script is running.")

(defun satchel--script-pending-files ()
  "Flat, de-duplicated list of every file referenced by any queued op."
  (delete-dups (apply #'append (mapcar #'satchel-op-files satchel--script-ops))))

(defun satchel--op-comment (op)
  "Return a one-line comment describing OP, for the generated script."
  (pcase (satchel-op-type op)
    ('copy (format "copy %d file(s) -> %s"
                   (length (satchel-op-files op)) (satchel-op-dest op)))
    ('move (format "move %d file(s) -> %s"
                   (length (satchel-op-files op)) (satchel-op-dest op)))
    ('delete (format "delete: %s" (car (satchel-op-files op))))))

(defun satchel--op-command (op)
  "Return the shell command for OP.
Moves within one filesystem use `mv' (a plain rename, instant at any
size).  Files on a different filesystem from the destination still use
rsync, which gives progress output and resumable transfers."
  (pcase (satchel-op-type op)
    ('copy (satchel--rsync-cmd 'copy (satchel-op-files op) (satchel-op-dest op)))
    ('move
     (let* ((files (satchel-op-files op))
            (dest  (satchel-op-dest op))
            (fast  (cl-remove-if-not
                    (lambda (f) (satchel--same-filesystem-p f dest)) files))
            (slow  (cl-remove-if
                    (lambda (f) (satchel--same-filesystem-p f dest)) files))
            (cmds  (delq nil
                         (list (and fast (satchel--mv-cmd fast dest))
                               (and slow (satchel--rsync-cmd 'move slow dest))))))
       (mapconcat #'identity cmds "\n")))
    ('delete (format "rm -rf -- %s"
                     (shell-quote-argument (car (satchel-op-files op)))))))

(defun satchel--render-script ()
  "Return the full script text rendered from `satchel--script-ops'."
  (with-temp-buffer
    (insert "#!/usr/bin/env bash\n"
            "set -xeuo pipefail\n\n")
    (dolist (op satchel--script-ops)
      (insert "# " (satchel--op-comment op) "\n"
              (satchel--op-command op) "\n\n"))
    (buffer-string)))

(defun satchel--script-write-file ()
  "Write the queue to `satchel-script-file'.
Signals an error if the file already exists: an existing script is
always a leftover and must be run or cleared first, never overwritten.
This is the only function that writes the script to disk."
  (when (file-exists-p satchel-script-file)
    (user-error "Leftover script exists at %s: run it with `x' (empty the queue first) or delete it with `satchel-script-clear'"
                (abbreviate-file-name satchel-script-file)))
  (make-directory (file-name-directory satchel-script-file) t)
  (with-temp-file satchel-script-file
    (insert (satchel--render-script)))
  (set-file-modes satchel-script-file #o755))

(defun satchel--script-queue-op (type files &optional dest)
  "Append a new TYPE (`copy', `move' or `delete') operation on FILES
\(into DEST, nil for delete) to `satchel--script-ops'.  In-memory only."
  (cl-incf satchel--op-id-counter)
  (setq satchel--script-ops
        (append satchel--script-ops
                (list (satchel-op-create :id satchel--op-id-counter
                                         :type type
                                         :files (mapcar #'expand-file-name files)
                                         :dest dest)))))

(defun satchel--script-unqueue-file (file)
  "Remove FILE from every queued operation in `satchel--script-ops'.
In-memory only.  A copy/move op loses just this file (and is dropped
entirely if that empties it); a delete op is dropped outright.
Return non-nil if anything was removed."
  (let ((file (expand-file-name file))
        (changed nil)
        new-ops)
    (dolist (op satchel--script-ops)
      (if (member file (satchel-op-files op))
          (progn
            (setq changed t)
            (setf (satchel-op-files op) (delete file (satchel-op-files op)))
            (when (satchel-op-files op)
              (push op new-ops)))
        (push op new-ops)))
    (setq satchel--script-ops (nreverse new-ops))
    changed))

;; Keep the queue and persistent-mark bookkeeping in sync with the
;; built-in u/U unmark keys.  Neither of these touches disk.
(advice-add 'dired-unmark :before
            (lambda (&rest _)
              (when-let ((f (dired-get-filename nil t)))
                (satchel--forget-mark f)
                (setq satchel-stash (delete f satchel-stash))
                (when (satchel--script-unqueue-file f)
                  (message "Removed queued command for %s"
                           (file-name-nondirectory f))))))

(advice-add 'dired-unmark-all-marks :before
            (lambda (&rest _)
              (when (derived-mode-p 'dired-mode)
                (save-excursion
                  (goto-char (point-min))
                  (while (not (eobp))
                    (when-let ((f (dired-get-filename nil t)))
                      (satchel--forget-mark f)
                      (setq satchel-stash (delete f satchel-stash))
                      (satchel--script-unqueue-file f))
                    (forward-line 1))))))

;; ---------------------------------------------------------------------
;; Pack / unpack (stash)
;; ---------------------------------------------------------------------

(defun satchel-pack ()
  "Pack the currently marked files from this Dired buffer into the satchel.
If no files are marked, append the file at point to the existing
satchel instead.  Packed files are visually flagged with
`satchel-marker-char', and the flag survives tab switches."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (let ((files (dired-get-marked-files nil 'marked)))
    (if files
        (progn
          (setq satchel-stash files)
          (dolist (f files)
            (satchel--record-mark f satchel-marker-char)
            (satchel--visually-mark-file f satchel-marker-char))
          (message "Packed %d file(s)" (length files)))
      (let ((f (dired-get-filename nil t)))
        (unless f
          (user-error "No file at point"))
        (if (member f satchel-stash)
            (message "Already packed: %s" (file-name-nondirectory f))
          (setq satchel-stash (append satchel-stash (list f)))
          (satchel--record-mark f satchel-marker-char)
          (satchel--visually-mark-file f satchel-marker-char)
          (message "Appended %s (satchel now has %d file(s))"
                   (file-name-nondirectory f)
                   (length satchel-stash)))))))

(defun satchel-unpack ()
  "Empty the satchel and clear its persistent marks.
This only empties the pack (the files selected for the next
copy/move), not operations already queued in `satchel--script-ops'.
Use `dired-unmark' on a queued file, or `satchel-script-clear' to
drop everything queued."
  (interactive)
  (dolist (f satchel-stash)
    (satchel--forget-mark f)
    (satchel--mark-in-all-buffers f ?\s))
  (setq satchel-stash nil)
  (message "Satchel emptied"))

;; ---------------------------------------------------------------------
;; Immediate copy / move helpers (LIVE mode)
;; ---------------------------------------------------------------------

(defun satchel--copy-file-list (files dest-dir)
  "Copy FILES into DEST-DIR using built-in `dired-copy-file'."
  (dolist (from files)
    (let ((to (expand-file-name (file-name-nondirectory from) dest-dir)))
      (dired-copy-file from to 0)))
  (message "Copied %d file(s) to %s" (length files) dest-dir))

(defun satchel--move-file-list (files dest-dir)
  "Move/rename FILES into DEST-DIR using built-in `dired-rename-file'."
  (dolist (from files)
    (let ((to (expand-file-name (file-name-nondirectory from) dest-dir)))
      (dired-rename-file from to nil)))
  (message "Moved %d file(s) to %s" (length files) dest-dir))

;; ---------------------------------------------------------------------
;; Rsync command building (used when rendering the script)
;; ---------------------------------------------------------------------

(defun satchel--rsync-cmd (mode files dest-dir)
  "Build an rsync command string that copies/moves FILES into DEST-DIR.
MODE is either `copy' or `move'.  `--partial' lets interrupted large
files resume when the script is re-run."
  (let* ((dest (file-name-as-directory (expand-file-name dest-dir)))
         (flags (if (eq mode 'move)
                    "-avh --progress --partial --remove-source-files --ignore-missing-args"
                  "-avh --progress --partial"))
         (sources (mapconcat (lambda (f) (shell-quote-argument (expand-file-name f)))
                             files " ")))
    (format "rsync %s -- %s %s" flags sources (shell-quote-argument dest))))

(defun satchel--same-filesystem-p (file dest-dir)
  "Return non-nil if FILE and DEST-DIR are on the same filesystem.
Returns nil when either one does not exist, so callers fall back to
the rsync path (which has `--ignore-missing-args')."
  (let ((a (file-attribute-device-number
            (file-attributes (expand-file-name file))))
        (b (file-attribute-device-number
            (file-attributes (expand-file-name dest-dir)))))
    (and a b (equal a b))))

(defun satchel--mv-cmd (files dest-dir)
  "Build idempotent `mv' commands, one line per file in FILES.
Each line skips sources that no longer exist, so re-running a
leftover script after a partial run is safe under `set -e'."
  (let ((dest (shell-quote-argument
               (file-name-as-directory (expand-file-name dest-dir)))))
    (mapconcat
     (lambda (f)
       (let ((q (shell-quote-argument (expand-file-name f))))
         (format "if [ -e %s ] || [ -L %s ]; then mv -- %s %s; fi"
                 q q q dest)))
     files "\n")))

(defun satchel--flagged-for-deletion ()
  "Return the absolute file names flagged for deletion (dired-del-marker)
in this Dired buffer."
  (let (files)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (let ((absname (dired-get-filename nil t)))
          (when (and absname
                     (eq (dired-file-marker absname) dired-del-marker))
            (push absname files)))
        (forward-line 1)))
    (nreverse files)))

;; ---------------------------------------------------------------------
;; Script commands: preview, clear, execute
;; ---------------------------------------------------------------------

(defun satchel-script-open ()
  "Preview the script.
With a non-empty queue, show the script rendered from the queue in a
read-only buffer (nothing is written to disk).  With an empty queue,
open the leftover script on disk, if there is one."
  (interactive)
  (cond
   (satchel--script-ops
    (with-current-buffer (get-buffer-create "*satchel-preview*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (satchel--render-script)))
      (sh-mode)
      (goto-char (point-min))
      (view-mode 1)
      (pop-to-buffer (current-buffer))))
   ((file-exists-p satchel-script-file)
    (find-file satchel-script-file))
   (t
    (user-error "Satchel queue is empty and there is no leftover script"))))

(defun satchel-script-clear ()
  "Drop every queued operation (in memory) and delete the script file.
This is the manual way to get rid of a leftover script."
  (interactive)
  (when satchel--script-running
    (user-error "A satchel script is running; wait for it to finish"))
  (dolist (f (satchel--script-pending-files))
    (satchel--forget-mark f)
    (satchel--mark-in-all-buffers f ?\s))
  (setq satchel--script-ops nil)
  (when (file-exists-p satchel-script-file)
    (delete-file satchel-script-file))
  (message "Cleared satchel queue and script file: %s" satchel-script-file))

(defun satchel--notify (success msg duration)
  "Show a desktop notification that the satchel script has finished.
SUCCESS is non-nil if it finished cleanly; MSG is the raw
compilation-finish status string (used for failure detail); DURATION
is the run's wall-clock length in seconds.

Runs of at least `satchel-notify-persistent-threshold' seconds get a
persistent notification (`:timeout 0' per the Desktop Notifications
spec; most daemons honor this as \"never expire\").  Shorter runs get
an auto-expiring one (`satchel-notify-short-timeout')."
  (when satchel-notify-on-finish
    (let* ((title "Dired Satchel")
           (persistent (>= duration satchel-notify-persistent-threshold))
           (body (if success
                     (format "Script finished successfully (%s): %s"
                             (satchel--format-duration duration)
                             (abbreviate-file-name satchel-script-file))
                   (format "Script FAILED after %s (%s): %s"
                           (satchel--format-duration duration)
                           (string-trim msg)
                           (abbreviate-file-name satchel-script-file)))))
      (notifications-notify :title title :body body
                            :urgency (if success 'normal 'critical)
                            :timeout (if persistent 0 satchel-notify-short-timeout)))))

(defun satchel--format-duration (seconds)
  "Format SECONDS as e.g. \"2m 14s\" or \"37s\"."
  (let ((secs (round seconds)))
    (if (>= secs 60)
        (format "%dm %ds" (/ secs 60) (% secs 60))
      (format "%ds" secs))))

(defun satchel--script-finish-cleanup (_buf msg)
  "Compilation-finish handler for the satchel script.
On success: clear pending marks and delete the script file.  On
failure: keep the script on disk (it is protected from overwriting and
can be re-run with `satchel-script-execute').  Always show a desktop
notification and reset the running state."
  (setq satchel--script-running nil)
  (let ((success (string-match-p "^finished" msg))
        (duration (if satchel--script-start-time
                      (float-time (time-subtract (current-time)
                                                 satchel--script-start-time))
                    0)))
    (when success
      (dolist (f satchel--script-pending-cleanup)
        (satchel--forget-mark f)
        (satchel--mark-in-all-buffers f ?\s))
      (when (file-exists-p satchel-script-file)
        (delete-file satchel-script-file)))
    (satchel--notify success msg duration))
  (setq satchel--script-pending-cleanup nil)
  (setq satchel--script-start-time nil)
  (remove-hook 'compilation-finish-functions #'satchel--script-finish-cleanup))

(defun satchel-script-execute ()
  "Run the satchel script asynchronously, with live output.
With a non-empty queue: write the script to disk, then run it.  This
refuses if a leftover script already exists on disk.
With an empty queue: run the leftover script on disk as-is (e.g. after
a reboot or a failed run).

Asks for confirmation before anything is written or run.  On success,
clears the persistent marks of the queued files and deletes the script
file.  On failure the script stays on disk for a retry."
  (interactive)
  (when satchel--script-running
    (user-error "A satchel script is already running"))
  (let ((leftover (file-exists-p satchel-script-file)))
    (unless (or satchel--script-ops leftover)
      (user-error "Satchel queue is empty and there is no leftover script"))
    (when (and satchel--script-ops leftover)
      (user-error "Leftover script exists at %s: empty the queue and run it with `x', or delete it with `satchel-script-clear'"
                  (abbreviate-file-name satchel-script-file)))
    (unless (y-or-n-p
             (format (if leftover
                         "Run LEFTOVER satchel script %s now? "
                       "Run satchel script %s now? ")
                     (abbreviate-file-name satchel-script-file)))
      (user-error "Execution cancelled"))
    ;; Write only after confirmation, so cancelling never leaves a
    ;; stray script on disk.
    (when satchel--script-ops
      (satchel--script-write-file)))
  (let* ((default-directory (file-name-directory satchel-script-file))
         (buf-name "*satchel-execute*")
         (compilation-buffer-name-function (lambda (_mode) buf-name)))
    ;; Marks to clear on success (nil when resuming a leftover script).
    (setq satchel--script-pending-cleanup (satchel--script-pending-files)
          satchel--script-ops nil
          satchel--script-running t
          satchel--script-start-time (current-time))
    (add-hook 'compilation-finish-functions #'satchel--script-finish-cleanup)
    (compile (format "bash %s" (shell-quote-argument satchel-script-file)))
    (with-current-buffer buf-name
      (setq-local compilation-scroll-output t))))

;; ---------------------------------------------------------------------
;; Progress inspection
;; ---------------------------------------------------------------------

(defun satchel-script-progress ()
  "Show progress of the satchel queue/script.
Report how many operations and distinct files are queued in memory.
If the script is currently running, jump to the live output in the
`*satchel-execute*' buffer instead, since that is where the real
progress (e.g. rsync's --progress output) is visible."
  (interactive)
  (let* ((queued (length satchel--script-ops))
         (pending (length (satchel--script-pending-files)))
         (buf (get-buffer "*satchel-execute*"))
         (proc (and buf (get-buffer-process buf)))
         (running (and proc (process-live-p proc))))
    (setq satchel--script-running (and running t))
    (cond
     (running
      (message "Satchel script is running: %d operation(s) queued, %d file(s) pending -- jumping to live output"
               queued pending)
      (pop-to-buffer buf)
      (goto-char (point-max)))
     ((> queued 0)
      (message "%d operation(s) queued, %d file(s) pending (\"x\" to run)"
               queued pending))
     ((file-exists-p satchel-script-file)
      (message "Queue is empty, but a leftover script exists at %s (\"x\" to run it, \"c\" to delete it)"
               (abbreviate-file-name satchel-script-file)))
     (t
      (message "Satchel queue is empty")))))

;; ---------------------------------------------------------------------
;; Script mode toggle: same keys (y/p/P/d/x), immediate vs. scripted
;; ---------------------------------------------------------------------

(defun satchel-toggle-script-mode ()
  "Toggle between immediate satchel actions and scripted (rsync/rm) actions."
  (interactive)
  (setq satchel-script-mode (not satchel-script-mode))
  (message "Satchel script mode: %s"
           (if satchel-script-mode "ON (scripted)" "OFF (live)"))
  (force-mode-line-update t))

(defvar satchel-mode-line-lighter
  '(:eval
    (when (derived-mode-p 'dired-mode)
      (if satchel-script-mode
          (propertize " [SCRIPT]" 'face '(:foreground "orange" :weight bold))
        (propertize " [LIVE]" 'face '(:foreground "green" :weight bold)))))
  "Mode-line indicator for `satchel-script-mode'.")

(unless (memq satchel-mode-line-lighter global-mode-string)
  (setq global-mode-string
        (append global-mode-string (list satchel-mode-line-lighter))))

;; ---------------------------------------------------------------------
;; Mode-aware copy / move / delete actions
;; ---------------------------------------------------------------------

(defun satchel-action-copy-here ()
  "Copy packed files into the current directory.
Immediate when `satchel-script-mode' is nil; otherwise queues a copy
operation in memory.  In script mode each file keeps its persistent
mark until the script actually runs."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (unless satchel-stash
    (user-error "Satchel is empty"))
  (let ((dest (dired-current-directory)))
    (if satchel-script-mode
        (let ((n (length satchel-stash)))
          (satchel--script-queue-op 'copy satchel-stash dest)
          (message "Queued rsync COPY operation (%d file(s)) to %s" n dest))
      (satchel--copy-file-list satchel-stash dest)
      (revert-buffer))))

(defun satchel-action-move-here ()
  "Move packed files into the current directory.
Immediate when `satchel-script-mode' is nil; otherwise queues a move
operation in memory.  In script mode the satchel is emptied so you
don't re-queue the same files, but each file keeps its persistent mark
\(as a \"queued\" indicator) until the script actually runs."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (unless satchel-stash
    (user-error "Satchel is empty"))
  (let ((dest (dired-current-directory)))
    (if satchel-script-mode
        (let ((n (length satchel-stash)))
          (satchel--script-queue-op 'move satchel-stash dest)
          (setq satchel-stash nil)
          (message "Queued rsync MOVE operation (%d file(s)) to %s; satchel emptied"
                   n dest))
      (when (member dest (mapcar #'file-name-directory satchel-stash))
        (unless (y-or-n-p "Move into the same directory? (may overwrite) ")
          (user-error "Move cancelled")))
      (satchel--move-file-list satchel-stash dest)
      (dolist (f satchel-stash)
        (satchel--forget-mark f)
        (satchel--mark-in-all-buffers f ?\s))
      (setq satchel-stash nil)
      (revert-buffer))))

(defun satchel-action-flag-deletion ()
  "Flag the file at point for deletion.
In immediate mode this is just the standard `dired-flag-file-deletion'.
In script mode it also queues a delete operation for the file right
away (in memory), so flagging files across several Dired buffers is
all recorded, regardless of which buffer `satchel-action-execute' is
eventually run from.  Either way the flag is recorded so it survives
tab switches; in script mode it is cleared only once the script runs
\(or the file is unmarked)."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (let ((file (dired-get-filename nil t)))
    (unless file
      (user-error "No file at point"))
    (when satchel-script-mode
      (satchel--script-queue-op 'delete (list file))
      (message "Queued DELETE operation for %s"
               (file-name-nondirectory file)))
    (satchel--record-mark file dired-del-marker)
    (dired-flag-file-deletion 1)))

(defun satchel-action-execute ()
  "In immediate mode, delete files flagged for deletion.
In script mode, run the queued operations (or the leftover script when
the queue is empty) via `satchel-script-execute'."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (if satchel-script-mode
      (satchel-script-execute)
    (let ((flagged (satchel--flagged-for-deletion)))
      (dired-do-flagged-delete)
      (dolist (f flagged) (satchel--forget-mark f)))))

;; ---------------------------------------------------------------------
;; Transient menu
;; ---------------------------------------------------------------------

(transient-define-prefix satchel-transient ()
  "Satchel (stash/rsync script) management menu."
  ["Satchel script"
   :if-derived 'dired-mode
   ("v" "Progress"                          satchel-script-progress)
   ("s" "Preview / open script"             satchel-script-open)
   ("x" "Execute script (or leftover)"      satchel-script-execute)
   ("c" "Clear queue and script file"       satchel-script-clear)
   ("y" "Empty satchel"                     satchel-unpack)]
  ["Actions"
   ("q" "Quit" transient-quit-all)])

(provide 'dired-satchel)
;;; dired-satchel.el ends here
