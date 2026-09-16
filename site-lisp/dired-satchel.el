;;; dired-satchel.el --- Stash files in Dired, then copy/move/delete them, live or scripted -*- lexical-binding: t -*-

;;; Commentary:

;; `dired-satchel' lets you "pack" (stash) files from one or more Dired
;; buffers into a single satchel, then "deliver" them elsewhere with a
;; copy or move, or flag files for deletion — either immediately, or
;; accumulated into a shell script (rsync for copy/move, rm for delete)
;; that you review and run later.
;;
;; Two modes, same keys:
;; - LIVE mode:   actions run immediately via built-in Dired primitives.
;; - SCRIPT mode: actions queue an operation (copy/move/delete) into
;;                `satchel--script-ops', a purely in-memory list that
;;                is the single source of truth for the script.
;;
;; IMPORTANT — disk writes are manual: packing, copying, moving,
;; deleting, and unmarking only ever touch `satchel--script-ops' in
;; memory. Nothing is written to `satchel-script-file' until you do
;; one of the three things that write it out:
;;   - `satchel-script-write' (bound to "w" in `satchel-transient')
;;     just writes, without opening anything.
;;   - `satchel-script-open' writes, then opens the file for review.
;;   - `satchel-script-execute' writes, then runs it.
;; All three regenerate the file from scratch from the current queue,
;; so whichever one you use, what ends up on disk always matches
;; `satchel--script-ops' at that moment — never a stale snapshot.
;; This trades a small amount of crash-safety (an in-memory queue you
;; never wrote out via one of the above is gone if Emacs dies) for
;; zero disk I/O on the hot path of packing/marking/unmarking files,
;; which matters once the queue gets large.
;;
;; Because the script file is always *derived in full* from
;; `satchel--script-ops' rather than being append-only text, unmarking
;; a queued file (the standard `u'/`U' Dired keys) actually removes
;; its command from the queue — for a copy/move op this shrinks the
;; rsync command's file list (or drops the whole op if it becomes
;; empty); for a delete op it drops the op outright. The next write
;; (manual or at execute time) reflects that removal.
;;
;; CAVEAT: since the script file is just a rendering of
;; `satchel--script-ops', any commands you hand-add via
;; `satchel-script-open' will be silently discarded the next time
;; `satchel-script-write' or `satchel-script-execute' runs. Use
;; `satchel-script-open' for reviewing, not permanent hand-written
;; additions.
;;
;; Files that are packed or flagged for deletion get a persistent visual
;; mark that is redrawn automatically whenever a Dired buffer is
;; (re)read — including after `find-alternate-file', which many
;; tab/bookmark setups use to switch directories in place.
;;
;; Use `satchel-script-progress' to check how many operations/files are
;; still queued, or to jump straight to the live output of a script
;; that is currently running.
;;
;; Suggested keybindings (see accompanying init-dired.el snippet):
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
  "Path to the accumulated rsync/rm commands script file."
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
notification is shown persistently (stays until manually dismissed).
Runs shorter than this get a normal, auto-expiring notification
instead (see `satchel-notify-short-timeout')."
  :type 'number
  :group 'dired-satchel)

(defcustom satchel-notify-short-timeout 3000
  "Timeout, in milliseconds, for the finish notification when the
script ran for less than `satchel-notify-persistent-threshold'
seconds. Passed straight to `notifications-notify's :timeout."
  :type 'integer
  :group 'dired-satchel)

(defvar satchel-stash nil
  "List of absolute file names currently packed into the satchel.")

(defvar satchel-script-mode t
  "When non-nil, satchel actions generate shell commands into
`satchel-script-file' instead of executing immediately.
This is a global toggle shared by all Dired buffers.")

;; ---------------------------------------------------------------------
;; Persistent marks (survive buffer recreation, e.g. tab switches)
;; ---------------------------------------------------------------------

(defvar satchel-persistent-marks (make-hash-table :test 'equal)
  "Map of absolute file name -> dired marker char.
Used to redraw pack/delete marks after a Dired buffer is recreated,
e.g. via `find-alternate-file' when switching numbered tabs.")

(defun satchel--record-mark (file char)
  (puthash (expand-file-name file) char satchel-persistent-marks))

(defun satchel--forget-mark (file)
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
  "Redraw any marks recorded in `satchel-persistent-marks' for the
files in the current Dired buffer. Meant for `dired-after-readin-hook'."
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
;; Script operation queue (purely in-memory; single source of truth)
;; ---------------------------------------------------------------------

(cl-defstruct (satchel-op (:constructor satchel-op-create))
  "One not-yet-run entry in the satchel script.
TYPE is `copy', `move', or `delete'. FILES is the list of absolute
file names involved (a single element for `delete'). DEST is the
destination directory for `copy'/`move', nil for `delete'."
  id type files dest)

(defvar satchel--script-ops nil
  "List of `satchel-op' structs describing every operation currently
queued, in memory only. Nothing here is written to
`satchel-script-file' automatically — see `satchel-script-write' and
`satchel-script-execute', the only two functions that touch disk.
This list is the single source of truth for the script's eventual
contents: when it does get written, the file is fully regenerated
from this list, never hand-appended to. That's what makes it possible
to remove a single already-queued file (e.g. via the standard Dired
`u'/`U' unmark keys) and have its command actually disappear, rather
than merely clearing a visual flag while the command still runs.")

(defvar satchel--op-id-counter 0
  "Monotonic counter used to give each `satchel-op' a unique id.")

(defun satchel--script-pending-files ()
  "Flat, de-duplicated list of every file referenced by any operation
in `satchel--script-ops'."
  (delete-dups (apply #'append (mapcar #'satchel-op-files satchel--script-ops))))

(defun satchel--op-comment (op)
  (pcase (satchel-op-type op)
    ('copy (format "copy %d file(s) -> %s"
                   (length (satchel-op-files op)) (satchel-op-dest op)))
    ('move (format "move %d file(s) -> %s"
                   (length (satchel-op-files op)) (satchel-op-dest op)))
    ('delete (format "delete: %s" (car (satchel-op-files op))))))

(defun satchel--op-command (op)
  (pcase (satchel-op-type op)
    ('copy (satchel--rsync-cmd 'copy (satchel-op-files op) (satchel-op-dest op)))
    ('move (satchel--rsync-cmd 'move (satchel-op-files op) (satchel-op-dest op)))
    ('delete (format "rm -rf -- %s" (shell-quote-argument (car (satchel-op-files op)))))))

(defun satchel--script-rewrite ()
  "Write `satchel-script-file' to disk from scratch, based on the
current `satchel--script-ops'. If there are no queued operations, any
existing file is deleted instead of being left around empty/stale.

This is the ONLY function that writes the script to disk; it is
called exclusively by `satchel-script-write' and
`satchel-script-execute'. Packing, copying, moving, deleting, and
unmarking never call this directly — they only mutate
`satchel--script-ops' in memory."
  (if (null satchel--script-ops)
      (when (file-exists-p satchel-script-file)
        (delete-file satchel-script-file))
    (make-directory (file-name-directory satchel-script-file) t)
    (with-temp-buffer
      (insert "#!/usr/bin/env bash\n")
      (insert "set -xeuo pipefail\n\n")
      (dolist (op satchel--script-ops)
        (insert "# " (satchel--op-comment op) "\n")
        (insert (satchel--op-command op) "\n\n"))
      (write-region (point-min) (point-max) satchel-script-file nil 'silent))
    (set-file-modes satchel-script-file #o755)))

(defun satchel-script-write ()
  "Write the current in-memory operation queue out to
`satchel-script-file', overwriting whatever was there before. This is
the only way (besides `satchel-script-execute') to get the queue onto
disk — pack/copy/move/delete/unmark are all purely in-memory until
you call this."
  (interactive)
  (satchel--script-rewrite)
  (if satchel--script-ops
      (message "Wrote %d queued operation(s) (%d file(s)) to %s"
               (length satchel--script-ops)
               (length (satchel--script-pending-files))
               satchel-script-file)
    (message "Queue is empty — no script file written (removed stale one, if any)")))

(defun satchel--script-queue-op (type files &optional dest)
  "Append a new TYPE ('copy/'move/'delete) operation on FILES (into
DEST, nil for delete) to `satchel--script-ops'. Purely in-memory; does
NOT write to disk. Call `satchel-script-write' (or press \"w\" in
`satchel-transient') when you want the file to reflect this."
  (cl-incf satchel--op-id-counter)
  (setq satchel--script-ops
        (append satchel--script-ops
                (list (satchel-op-create :id satchel--op-id-counter
                                          :type type
                                          :files (mapcar #'expand-file-name files)
                                          :dest dest)))))

(defun satchel--script-unqueue-file (file)
  "Remove FILE from every queued operation in `satchel--script-ops'.
Purely in-memory; does NOT write to disk. A copy/move operation loses
just this file from its source list (and is dropped entirely if that
empties it); a delete operation (always single-file) is dropped
outright. Returns non-nil if anything was actually removed.

This is what makes unmarking a file (`u'/`U') actually cancel its
queued command instead of just clearing the visual flag while the
stale command keeps running — the next `satchel-script-write' or
`satchel-script-execute' will reflect the removal."
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

;; Keep the operation queue and persistent-mark bookkeeping in sync
;; with the built-in u/U unmark keys. Neither of these touches disk.
(advice-add 'dired-unmark :before
            (lambda (&rest _)
              (when-let ((f (dired-get-filename nil t)))
                (satchel--forget-mark f)
                (setq satchel-stash (delete f satchel-stash))
                (when (satchel--script-unqueue-file f)
                  (message "Removed queued command for %s (not yet written to disk)"
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
satchel instead. Packed files are visually flagged with
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
Note: this only empties the *pack* (the files selected for the next
copy/move), not any operations already queued in `satchel--script-ops'
— use `dired-unmark' on a queued file, or `satchel-script-clear' to
drop everything queued, for that."
  (interactive)
  (dolist (f satchel-stash)
    (satchel--forget-mark f)
    (satchel--mark-in-all-buffers f ?\s))
  (setq satchel-stash nil)
  (message "Satchel emptied"))

;; ---------------------------------------------------------------------
;; Immediate copy / move helpers
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
;; Rsync command building (used only when (re)generating the script)
;; ---------------------------------------------------------------------

(defun satchel--rsync-cmd (mode files dest-dir)
  "Build an rsync command string that copies/moves FILES into DEST-DIR.
MODE is either `copy' or `move'."
  (let* ((dest (file-name-as-directory (expand-file-name dest-dir)))
         (flags (if (eq mode 'move)
                    "-avh --progress --remove-source-files --ignore-missing-args"
                  "-avh --progress"))
         (sources (mapconcat (lambda (f) (shell-quote-argument (expand-file-name f)))
                             files " ")))
    (format "rsync %s -- %s %s" flags sources (shell-quote-argument dest))))

(defun satchel--flagged-for-deletion ()
  "Return the list of absolute file names currently flagged for
deletion (marked with `d', dired-del-marker) in this Dired buffer."
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

(defun satchel-script-open ()
  "Regenerate the script file from the current queue and open it for
review/editing. Like `satchel-script-execute', this always writes
`satchel--script-ops' to disk first, so what you see is guaranteed to
match the current queue — not a stale snapshot from before some
pack/copy/move/delete/unmark you did since the last write."
  (interactive)
  (satchel--script-rewrite)
  (unless (file-exists-p satchel-script-file)
    (user-error "Satchel queue is empty — nothing to open"))
  (find-file satchel-script-file))

(defun satchel-script-clear ()
  "Drop every queued operation (in memory) and delete the script file
on disk, if one exists."
  (interactive)
  (dolist (f (satchel--script-pending-files))
    (satchel--forget-mark f)
    (satchel--mark-in-all-buffers f ?\s))
  (setq satchel--script-ops nil)
  (when (file-exists-p satchel-script-file)
    (delete-file satchel-script-file))
  (message "Cleared satchel queue and script file: %s" satchel-script-file))

(defvar satchel--script-pending-cleanup nil
  "Files whose persistent marks should be cleared once the in-flight
script run finishes successfully.")

(defvar satchel--script-running nil
  "Non-nil while the satchel script's compilation process is alive.
Kept in sync by `satchel-script-execute' and
`satchel--script-finish-cleanup', and refreshed on demand by
`satchel-script-progress'.")

(defvar satchel--script-start-time nil
  "Time (as returned by `current-time') at which the currently running
satchel script was launched by `satchel-script-execute'. Used by
`satchel--script-finish-cleanup' to decide whether the finish
notification should be persistent or short-lived. Nil when no script
is running.")

(defun satchel--notify (success msg duration)
  "Show a desktop notification that the satchel script has finished,
via `notifications-notify' (D-Bus). SUCCESS is non-nil if it finished
cleanly; MSG is the raw compilation-finish status string, used for
the failure detail; DURATION is the run's wall-clock length in
seconds.

Runs of at least `satchel-notify-persistent-threshold' seconds get a
persistent notification (`:timeout 0' per the Desktop Notifications
spec — most daemons, e.g. dunst/mako, honor this as \"never expire\";
a few ignore it and fall back to their own default), since those are
the ones you're likely to have wandered off from. Shorter runs get an
auto-expiring notification instead (`satchel-notify-short-timeout'),
so quick jobs don't leave a banner you have to go dismiss."
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
  "Format SECONDS as e.g. \"2m 14s\" or \"37s\" for notification bodies."
  (let ((secs (round seconds)))
    (if (>= secs 60)
        (format "%dm %ds" (/ secs 60) (% secs 60))
      (format "%ds" secs))))

(defun satchel--script-finish-cleanup (_buf msg)
  "Compilation-finish handler that clears pending marks once the
satchel script has finished running, shows a desktop notification
reporting whether it succeeded or failed (persistent or short-lived
depending on how long the run took — see `satchel--notify'), and —
on success — deletes the script file itself so the next queued action
starts fresh instead of leaving old, already-run commands lying
around on disk. The script is left in place on failure so it can be
inspected/retried."
  (setq satchel--script-running nil)
  (let ((success (string-match-p "^finished" msg))
        (duration (if satchel--script-start-time
                      (float-time (time-subtract (current-time)
                                                  satchel--script-start-time))
                    0)))
    (when success
      (when satchel--script-pending-cleanup
        (dolist (f satchel--script-pending-cleanup)
          (satchel--forget-mark f)
          (satchel--mark-in-all-buffers f ?\s)))
      (when (file-exists-p satchel-script-file)
        (delete-file satchel-script-file)))
    (satchel--notify success msg duration))
  (setq satchel--script-pending-cleanup nil)
  (setq satchel--script-start-time nil)
  (remove-hook 'compilation-finish-functions #'satchel--script-finish-cleanup))

(defun satchel-script-execute ()
  "Run the current queue asynchronously without blocking Emacs.
Regenerates `satchel-script-file' from `satchel--script-ops' right
before running (so it always executes the latest queue, whether or
not you called `satchel-script-write' yourself), prompts for
confirmation, and shows live progress in a compilation buffer. On
successful completion, clears persistent marks for every file that
was queued, and empties `satchel--script-ops'."
  (interactive)
  (unless satchel--script-ops
    (user-error "Satchel queue is empty — nothing to execute"))
  (satchel--script-rewrite)
  (unless (y-or-n-p
           (format "Run satchel script %s now? "
                   (abbreviate-file-name satchel-script-file)))
    (user-error "Execution cancelled"))
  (let* ((default-directory (file-name-directory satchel-script-file))
         (buf-name "*satchel-execute*")
         (compilation-buffer-name-function (lambda (_mode) buf-name)))
    (setq satchel--script-pending-cleanup (satchel--script-pending-files))
    (setq satchel--script-ops nil)
    (setq satchel--script-running t)
    (setq satchel--script-start-time (current-time))
    (add-hook 'compilation-finish-functions #'satchel--script-finish-cleanup)
    (compile (format "bash %s" (shell-quote-argument satchel-script-file)))
    (with-current-buffer buf-name
      (setq-local compilation-scroll-output t))))

;; ---------------------------------------------------------------------
;; Progress inspection
;; ---------------------------------------------------------------------

(defun satchel-script-progress ()
  "Show progress of the satchel queue/script.

Reports how many operations are queued in `satchel--script-ops' (in
memory — this is authoritative regardless of what's on disk) and how
many distinct files that covers. If the script's compilation process
is currently alive, jumps straight to the live output in the
`*satchel-execute*' buffer instead of just printing a summary, since
that's where the real progress (e.g. rsync's --progress output) is
visible."
  (interactive)
  (let* ((queued (length satchel--script-ops))
         (pending (length (satchel--script-pending-files)))
         (buf (get-buffer "*satchel-execute*"))
         (proc (and buf (get-buffer-process buf)))
         (running (and proc (process-live-p proc))))
    (setq satchel--script-running (and running t))
    (cond
     (running
      (message "Satchel script is running: %d operation(s) queued, %d file(s) pending — jumping to live output"
               queued pending)
      (pop-to-buffer buf)
      (goto-char (point-max)))
     ((> queued 0)
      (message "%d operation(s) queued in memory, %d file(s) pending (not yet written — \"w\" to write, \"x\" to run)"
               queued pending))
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
Immediate when `satchel-script-mode' is nil; queues a copy operation
into `satchel--script-ops' otherwise (purely in memory — no disk
write), keeping each file's persistent mark until the script actually
runs."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (unless satchel-stash
    (user-error "Satchel is empty"))
  (let ((dest (dired-current-directory)))
    (if satchel-script-mode
        (let ((n (length satchel-stash)))
          (satchel--script-queue-op 'copy satchel-stash dest)
          (message "Queued rsync COPY operation (%d file(s)) to %s (not yet written to disk)"
                   n dest))
      (satchel--copy-file-list satchel-stash dest)
      (revert-buffer))))

(defun satchel-action-move-here ()
  "Move packed files into the current directory.
Immediate when `satchel-script-mode' is nil; queues a move operation
into `satchel--script-ops' otherwise (purely in memory). In script
mode, the satchel is emptied so you don't re-queue the same files, but
each file's persistent mark is kept (as a \"queued\" indicator) until
the script actually runs."
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
          (message "Queued rsync MOVE operation (%d file(s)) to %s (not yet written to disk); satchel emptied"
                   n dest))
      (when (member dest (mapcar #'file-name-directory satchel-stash))
        (unless (y-or-n-p "Move into the same directory? (may overwrite)")
          (user-error "Move cancelled")))
      (satchel--move-file-list satchel-stash dest)
      (dolist (f satchel-stash)
        (satchel--forget-mark f)
        (satchel--mark-in-all-buffers f ?\s))
      (setq satchel-stash nil)
      (revert-buffer))))

(defun satchel-action-flag-deletion ()
  "Flag the file at point for deletion.
In immediate mode, this is just the standard `dired-flag-file-deletion'.
In script mode, it additionally queues a delete operation for this
file into `satchel--script-ops' immediately (purely in memory, so
flagging files across multiple Dired buffers all gets recorded,
regardless of which buffer `satchel-action-execute' is eventually run
from). Either way, the flag is recorded so it survives tab switches,
and in script mode it is only cleared once the script actually runs
(or the file is unmarked)."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (let ((file (dired-get-filename nil t)))
    (unless file
      (user-error "No file at point"))
    (when satchel-script-mode
      (satchel--script-queue-op 'delete (list file))
      (message "Queued DELETE operation for %s (not yet written to disk)"
               (file-name-nondirectory file)))
    (satchel--record-mark file dired-del-marker)
    (dired-flag-file-deletion 1)))

(defun satchel-action-execute ()
  "In immediate mode, delete files flagged for deletion (the standard
Dired `D' mark, set via `satchel-action-flag-deletion'). In script
mode, execute the entire accumulated queue (which already contains
any delete operations, plus any copy/move operations) via
`satchel-script-execute', which writes the script to disk first."
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
   ("v" "Script progress" satchel-script-progress)
   ("w" "Write script (queue -> disk)" satchel-script-write)
   ("s" "Open script"     satchel-script-open)
   ("c" "Clear script"    satchel-script-clear)
   ("x" "Execute script"  satchel-script-execute)
   ("y" "Empty satchel"   satchel-unpack)]
  ["Actions"
   ("q" "Quit" transient-quit-all)])

(provide 'dired-satchel)
;;; dired-satchel.el ends here
