;;; dired-satchel.el --- Stash files in Dired, then copy/move/delete them, live or scripted -*- lexical-binding: t -*-

;;; Commentary:

;; `dired-satchel' lets you "pack" (stash) files from one or more Dired
;; buffers into a single satchel, then "deliver" them elsewhere with a
;; copy or move, or flag files for deletion -- either immediately, or
;; accumulated into a shell script (rsync/mv for copy/move, rm or a
;; trash command for delete) that you review and run later.
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
;; - The marks of files belonging to a failed run are remembered, so a
;;   later successful re-run of the leftover script clears them too.
;; - The generated script is idempotent (rsync skips finished files,
;;   `--partial' resumes big files, rm -f ignores missing files, mv and
;;   trash commands are guarded by an existence check), so re-running a
;;   leftover script is safe.
;;
;; While the script is running, every command that changes the satchel
;; (pack, cut, unpack, paste, flag for deletion, LIVE-mode execute) is
;; refused, because the files it would touch may be in the middle of
;; being copied, moved or deleted.  Unmarking is still allowed.
;;
;; Script contents:
;;
;; - Moves within one filesystem use `mv' (a plain rename, instant at
;;   any size).  Moves across filesystems use rsync with
;;   `--remove-source-files', followed by a `find ... -empty -delete'
;;   pass that prunes the empty directory tree rsync leaves behind.
;; - Destinations on FAT/exFAT/NTFS get a different rsync flag set
;;   (`satchel-rsync-flags-nonposix') because they cannot store POSIX
;;   permissions/ownership.
;; - When `delete-by-moving-to-trash' is non-nil, deletions go through a
;;   trash command (`gio trash' / `trash-put', see `satchel-trash-command')
;;   instead of `rm -rf', exactly like LIVE mode does.
;; - Every `# ...' comment line in the script is flattened to a single
;;   line (control characters become `?'), so a hostile file name can
;;   never break out of a comment and become a shell command.
;;
;; Pasting is checked up front: two packed files with the same name,
;; a directory pasted into itself, a file/directory type mismatch with
;; an existing target, and moving a directory onto an existing
;; directory are all refused, so LIVE mode, `mv' and rsync behave alike.
;; `.' and `..' can never be packed or flagged, and a file that already
;; has a queued move or delete cannot be packed or flagged again.
;;
;; Unmarking a queued file (the standard `u'/`U'/`DEL'/`M-DEL' Dired
;; keys) removes it from the satchel and from the in-memory queue: a
;; copy/move op loses the file from its source list (or is dropped if it
;; becomes empty); a delete op is dropped outright.  This is done by
;; looking at which tracked files ended up unmarked after the command,
;; not by guessing which line the command acted on.
;;
;; Files that are packed or flagged for deletion get a persistent visual
;; mark that is redrawn automatically whenever a Dired buffer is
;; (re)read -- including after `find-alternate-file'.  Marks are applied
;; to every Dired buffer that lists the file, so a second buffer showing
;; the same directory never looks "unmarked" to the unmark sync.
;;
;; Use `satchel-script-progress' to see how many operations/files are
;; queued, or to jump to the live output of a running script.
;;
;; `satchel-script-open' (the transient's "s") shows the queue as an
;; interactive list rather than raw shell text: `j'/`k' move the cursor,
;; `J'/`K' reorder the operation at point, `d' removes it, `RET' shows
;; its files and generated command, `s' shows the full script, `x' runs
;; it and `C' clears it.  Reordering really changes the generated
;; script, since operations are executed in list order.  Removing an
;; operation never touches files on disk; a file that no other
;; operation references loses its mark, as if it had never been pasted.
;;
;; Satchel model (the keys mirror the Yazi task-queue plugin):
;;
;;   y  copy:  add the marked files (or the file at point) to the satchel
;;   x  cut:   same, but they will be moved instead of copied
;;   p  paste: deliver the satchel into this directory -- files packed with
;;      `y' are copied, files packed with `x' are moved -- then empty it.
;;   Y  empty the satchel
;;   d  flag the file at point for deletion
;;   v  menu: run script, preview, progress, clear, toggle mode ...
;;
;; The satchel accumulates: you can `x' in one directory, `y' in another
;; and `p' in the destination.  Packing a file again with the other key
;; simply switches its kind.  Only plain `*' marks are collected, so files
;; that are already packed or queued (marked `y'/`x') are never
;; re-packed by accident.
;; Packed files show `y' (copy) or `x' (move); deletions show the usual
;; `D'.  Pasting in SCRIPT mode keeps those files marked (they are not
;; done yet), but paints the mark with `satchel-queued-mark-face', so
;; "packed, not pasted" and "pasted, waiting for the script" are
;; different colors instead of different characters.  In LIVE mode a
;; paste finishes immediately, so its marks simply go away.
;;
;; Suggested keybindings:
;;
;;   (:map dired-mode-map
;;         ("y" . satchel-pack)
;;         ("x" . satchel-cut)
;;         ("Y" . satchel-unpack)
;;         ("p" . satchel-action-paste)
;;         ("d" . satchel-action-flag-deletion)
;;         ("v" . satchel-transient))
;;
;; Toggle LIVE vs SCRIPT mode with `satchel-toggle-script-mode' (also `t'
;; in the transient menu).  In LIVE mode copies and moves overwrite
;; existing files silently, and flagged deletions are executed with `x'
;; in the transient menu.

;;; Code:

(require 'dired)
(require 'dired-aux)
(require 'transient)
(require 'tabulated-list)
(require 'hl-line)
(require 'cl-lib)
(require 'seq)
(require 'pcase)
(require 'subr-x)
(require 'compile)
;; `notifications' needs D-Bus; builds without it (macOS, Windows) must
;; still be able to load this file.
(require 'notifications nil t)

(declare-function notifications-notify "notifications")
(declare-function evil-make-overriding-map "evil-core")

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

(defcustom satchel-copy-marker-char ?y
  "Marker character for files packed in the satchel to be copied.
A pasted file keeps this character; its queued state is shown with
`satchel-queued-mark-face' instead."
  :type 'character
  :group 'dired-satchel)

(defcustom satchel-cut-marker-char ?x
  "Marker character for files packed in the satchel to be moved.
A pasted file keeps this character; its queued state is shown with
`satchel-queued-mark-face' instead."
  :type 'character
  :group 'dired-satchel)

(defface satchel-queued-mark-face
  '((t :inherit font-lock-function-name-face :weight bold))
  "Face for the mark of a satchel operation waiting for the script.
Packed files that have not been pasted yet use `dired-mark-face'
instead; both states keep the same `y'/`x' character.
The foreground is inherited from `font-lock-function-name-face', so it
comes from the active theme and follows theme changes; the bold weight
keeps the mark distinguishable even without color.  To derive the color
from a different theme face, change the Inherit attribute with
`M-x customize-face RET satchel-queued-mark-face' (or use
`set-face-attribute' with `:inherit')."
  :group 'dired-satchel)

(defcustom satchel-rsync-flags "-avh --info=progress2 --partial"
  "rsync flags for copies and moves onto POSIX filesystems.
`--info=progress2' prints one overall progress line instead of one per
file (needs rsync 3.1+; use `--progress' for older versions)."
  :type 'string
  :group 'dired-satchel)

(defcustom satchel-rsync-flags-nonposix
  "-rltDvh --no-perms --no-owner --no-group --modify-window=1 --info=progress2 --partial"
  "rsync flags used when the destination is on a non-POSIX filesystem.
FAT/exFAT/NTFS cannot store permissions or ownership, so `-a' would make
rsync fail with exit code 23 and abort the script.  `--modify-window=1'
absorbs the 2-second timestamp granularity of FAT."
  :type 'string
  :group 'dired-satchel)

(defcustom satchel-nonposix-fs-types
  '("msdos" "vfat" "exfat" "ntfs" "ntfs3" "fuseblk")
  "Filesystem types (as printed by `stat -f -c %T') that get
`satchel-rsync-flags-nonposix'.  `fuseblk' is what ntfs-3g reports, but
it can also be another FUSE block filesystem; remove it if that bites."
  :type '(repeat string)
  :group 'dired-satchel)

(defcustom satchel-trash-command nil
  "Shell command prefix used to trash a file in generated scripts.
Only used when `delete-by-moving-to-trash' is non-nil.  The quoted file
name is appended.  If nil, `gio trash --' or `trash-put --' is used,
whichever is installed."
  :type '(choice (const :tag "Auto-detect" nil) string)
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
  "Alist of (FILE . KIND) for the files packed into the satchel.
FILE is an absolute file name; KIND is `copy' or `cut'.")

(defcustom satchel-script-mode t
  "When non-nil, satchel actions queue shell commands for
`satchel-script-file' instead of executing immediately.
This is a global toggle shared by all Dired buffers."
  :type 'boolean
  :group 'dired-satchel)

(defconst satchel--execute-buffer "*satchel-execute*"
  "Name of the compilation buffer the script runs in.")

;; ---------------------------------------------------------------------
;; Persistent marks (survive buffer recreation, e.g. tab switches)
;; ---------------------------------------------------------------------

(defvar satchel-persistent-marks (make-hash-table :test 'equal)
  "Map of absolute file name -> stored dired marker char.
This is the *stored* state (packed kind or deletion flag).  A pasted
file keeps the same character and gets a queued-mark overlay with
`satchel-queued-mark-face'; see `satchel--set-mark-overlay'.  Used to
redraw pack/delete marks after a Dired buffer is recreated, e.g. via
`find-alternate-file' when switching tabs.")

;; The script queue is defined further down, but painting a mark needs to
;; know which files are still waiting for the script.
(defvar satchel--script-ops)
(defvar satchel--script-pending-cleanup)

(defconst satchel--goto-threshold 40
  "Up to this many files, jump with `dired-goto-file'; above, scan once.")

(defun satchel--record-mark (file char)
  "Remember CHAR as the stored mark of FILE."
  (puthash (expand-file-name file) char satchel-persistent-marks))

(defun satchel--forget-mark (file)
  "Forget the stored mark of FILE."
  (remhash (expand-file-name file) satchel-persistent-marks))

(defun satchel--buffer-dirs ()
  "Return a hash set of the directories listed in this Dired buffer."
  (let ((h (make-hash-table :test 'equal)))
    (dolist (e dired-subdir-alist h)
      (puthash (car e) t h))))

(defun satchel--waiting-files ()
  "Return a hash set of files with queued-but-unfinished script work."
  (let ((set (make-hash-table :test 'equal)))
    (dolist (op satchel--script-ops)
      (dolist (f (satchel-op-files op))
        (puthash f t set)))
    (dolist (f satchel--script-pending-cleanup)
      (puthash f t set))
    set))

(defun satchel--queued-mark-p (file char waiting)
  "Return non-nil if FILE's mark CHAR denotes a queued operation.
A file is queued when it is waiting for the script and is no longer
packed in the satchel."
  (and (not (eq char ?\s))
       (not (eq char dired-del-marker))
       (gethash file waiting)
       (not (assoc file satchel-stash))))

(defvar-local satchel--mark-overlays nil
  "Hash of absolute file name -> overlay for queued marks in this buffer.")

(defun satchel--mark-overlay-table ()
  "Return this buffer's queued-mark overlay table, creating it if needed."
  (if (hash-table-p satchel--mark-overlays)
      satchel--mark-overlays
    (setq satchel--mark-overlays (make-hash-table :test 'equal))))

(defun satchel--remove-mark-overlay (file)
  "Delete the queued-mark overlay of FILE in this buffer, if any."
  (when (hash-table-p satchel--mark-overlays)
    (when-let* ((ov (gethash file satchel--mark-overlays)))
      (delete-overlay ov)
      (remhash file satchel--mark-overlays))))

(defun satchel--set-mark-overlay (file bol queued)
  "Show FILE's mark at BOL as queued with an overlay, or remove it.
Overlays are used instead of a text face because Dired's font-lock
would replace a text face on the next redisplay or after
`revert-buffer'; an overlay face takes precedence over font-lock."
  (if (not queued)
      (satchel--remove-mark-overlay file)
    (let* ((table (satchel--mark-overlay-table))
           (ov (gethash file table)))
      (unless (and ov (overlay-buffer ov))
        (setq ov (make-overlay bol (1+ bol)))
        (overlay-put ov 'satchel-mark t)
        (overlay-put ov 'evaporate t)
        (puthash file ov table))
      (move-overlay ov bol (1+ bol))
      (overlay-put ov 'face 'satchel-queued-mark-face))))

(defun satchel--remove-mark-overlays (files)
  "Delete queued-mark overlays for FILES in every buffer."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (hash-table-p satchel--mark-overlays)
        (dolist (f files)
          (satchel--remove-mark-overlay f))))))

(defun satchel--mark-line (file char waiting)
  "Mark the current Dired line for FILE with CHAR, then paint its state.
WAITING is the hash set returned by `satchel--waiting-files'."
  (let ((inhibit-read-only t)
        (bol (line-beginning-position))
        (queued (satchel--queued-mark-p file char waiting))
        (dired-marker-char char))
    (dired-mark 1)
    (satchel--set-mark-overlay file bol queued)))

(defun satchel--paint (table)
  "Apply TABLE (hash: absolute file -> stored marker char) to this buffer.
A char of SPC clears the mark.  Only files whose directory is listed in
this buffer are considered.  A few files are located with
`dired-goto-file'; many files are handled in a single scan.  This calls
`dired-mark' directly (with `dired-marker-char' bound) rather than
`dired-unmark', so it never triggers `satchel--sync-after-unmark'."
  (when (and (derived-mode-p 'dired-mode)
             (> (hash-table-count table) 0))
    (let ((dirs (satchel--buffer-dirs))
          (waiting (satchel--waiting-files))
          todo)
      (maphash (lambda (f c)
                 (when (gethash (file-name-directory f) dirs)
                   (push (cons f c) todo)))
               table)
      (when todo
        (save-excursion
          (if (<= (length todo) satchel--goto-threshold)
              (pcase-dolist (`(,f . ,c) todo)
                (when (dired-goto-file f)
                  (satchel--mark-line f c waiting)))
            (goto-char (point-min))
            (while (not (eobp))
              (let* ((f (dired-get-filename nil t))
                     (c (and f (gethash f table))))
                (if c
                    ;; `dired-mark' marks the current line and advances.
                    (satchel--mark-line f c waiting)
                  (forward-line 1))))))))))

(defun satchel--paint-in-all-buffers (table)
  "Apply TABLE (hash: absolute file -> stored marker char) to every buffer."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (satchel--paint table))))

(defun satchel--mark-in-all-buffers (files char)
  "Apply CHAR as the mark of every file in FILES in every Dired buffer."
  (when files
    (let ((table (make-hash-table :test 'equal :size (length files))))
      (dolist (f files) (puthash f char table))
      (satchel--paint-in-all-buffers table))))

(defun satchel-restore-persistent-marks ()
  "Redraw marks recorded in `satchel-persistent-marks' for the files
in the current Dired buffer.  Meant for `dired-after-readin-hook'."
  (satchel--paint satchel-persistent-marks))

(defun satchel-refresh-marks ()
  "Redraw every satchel mark in every Dired buffer.
Useful after external changes, or as a manual fallback if a Dired
buffer looks stale.  `revert-buffer' should not be needed for this."
  (interactive)
  (satchel--paint-in-all-buffers satchel-persistent-marks)
  (message "Satchel marks refreshed"))

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
  "Files whose persistent marks should be cleared once the script
finishes successfully.  Accumulates across runs: a failed run keeps its
files here so that re-running the leftover script cleans them up.")

(defvar satchel--script-start-time nil
  "Time (as returned by `current-time') at which the current script run
was launched.  Used to decide whether the finish notification is
persistent or short-lived.  Nil when no script is running.")

(defun satchel--script-running-p ()
  "Return non-nil if the satchel script's process is alive.
Computed from the process itself, so killing the buffer by hand can
never leave a stale \"running\" flag behind."
  (let ((proc (get-buffer-process satchel--execute-buffer)))
    (and proc (process-live-p proc))))

(defun satchel--ensure-idle ()
  "Signal a `user-error' if the satchel script is currently running.
Commands that change the stash, the queue or the marks call this first:
while the script runs, its source files are being copied, moved or
deleted, so packing, pasting or flagging them would race with it."
  (when (satchel--script-running-p)
    (user-error "Satchel script is running; wait for it to finish (`v v' to watch it)")))

(defun satchel--script-pending-files ()
  "Flat, de-duplicated list of every file referenced by any queued op.
Uses a hash table, so it is linear and never modifies the queue."
  (let ((seen (make-hash-table :test 'equal))
        out)
    (dolist (op satchel--script-ops)
      (dolist (f (satchel-op-files op))
        (unless (gethash f seen)
          (puthash f t seen)
          (push f out))))
    (nreverse out)))

(defun satchel--sanitize-comment (text)
  "Return TEXT with every control character replaced by `?'.
File names may legally contain newlines and other control characters.
Written verbatim into a `# ...' line of the script, a newline would end
the comment and turn the rest of the name into a live shell command, so
comments are always flattened to a single harmless line."
  (replace-regexp-in-string "[[:cntrl:]\177]" "?" text t t))

(defun satchel--op-comment (op)
  "Return a one-line, control-character-free comment describing OP,
for the generated script."
  (satchel--sanitize-comment
   (pcase (satchel-op-type op)
     ('copy (format "copy %d file(s) -> %s"
                    (length (satchel-op-files op)) (satchel-op-dest op)))
     ('move (format "move %d file(s) -> %s"
                    (length (satchel-op-files op)) (satchel-op-dest op)))
     ('delete (format "delete: %s" (car (satchel-op-files op)))))))

(defun satchel--trash-command ()
  "Return the trash command prefix if deletions should be trashed, else nil.
Non-nil only when `delete-by-moving-to-trash' is non-nil.  Signals a
`user-error' if trashing is wanted but no trash program can be found."
  (when delete-by-moving-to-trash
    (or satchel-trash-command
        (cond ((executable-find "gio") "gio trash --")
              ((executable-find "trash-put") "trash-put --"))
        (user-error "`delete-by-moving-to-trash' is set but neither gio nor trash-put was found; set `satchel-trash-command'"))))

(defvar satchel--probe-cache nil
  "Hash table bound only while the script is being rendered.
Memoizes external probes (PATH lookups, `stat' subprocesses).  Nil
outside rendering, in which case nothing is cached.")

(defun satchel--memo (key fn)
  "Return the value of calling FN, cached under KEY while rendering."
  (if (null satchel--probe-cache)
      (funcall fn)
    (let ((v (gethash key satchel--probe-cache 'none)))
      (if (eq v 'none)
          (puthash key (funcall fn) satchel--probe-cache)
        v))))

(defun satchel--op-command (op)
  "Return the shell command for OP.
Moves within one filesystem use `mv' (a plain rename, instant at any
size).  Files on a different filesystem from the destination still use
rsync, which gives progress output and resumable transfers; that path
also prunes the empty directories rsync leaves behind."
  (pcase (satchel-op-type op)
    ('copy (satchel--rsync-cmd 'copy (satchel-op-files op) (satchel-op-dest op)))
    ('move
     (let* ((files (satchel-op-files op))
            (dest  (satchel-op-dest op))
            ;; Stat the destination once, not once per file.
            (dev   (file-attribute-device-number
                    (file-attributes (expand-file-name dest))))
            fast slow)
       (dolist (f files)
         (if (and dev (equal dev (file-attribute-device-number
                                  (file-attributes (expand-file-name f)))))
             (push f fast)
           (push f slow)))
       (mapconcat #'identity
                  (delq nil
                        (list (and fast (satchel--mv-cmd (nreverse fast) dest))
                              (and slow (satchel--rsync-cmd 'move (nreverse slow) dest))))
                  "\n")))
    ('delete
     (let ((q (shell-quote-argument (car (satchel-op-files op))))
           (trash (satchel--memo 'trash #'satchel--trash-command)))
       (if trash
           (format "if [ -e %s ] || [ -L %s ]; then %s %s; fi" q q trash q)
         (format "rm -rf -- %s" q))))))

(defun satchel--render-script ()
  "Return the full script text rendered from `satchel--script-ops'."
  (let ((satchel--probe-cache (make-hash-table :test 'equal)))
    (with-temp-buffer
      (insert "#!/usr/bin/env bash\n"
              "set -xeuo pipefail\n\n")
      (dolist (op satchel--script-ops)
        (insert "# " (satchel--op-comment op) "\n"
                (satchel--op-command op) "\n\n"))
      (buffer-string))))

(defun satchel--script-write-file ()
  "Write the queue to `satchel-script-file'.
Signals an error if the file already exists: an existing script is
always a leftover and must be run or cleared first, never overwritten.
This is the only function that writes the script to disk."
  (when (file-exists-p satchel-script-file)
    (user-error "Leftover script exists at %s: run it with `v x' (empty the queue first) or delete it with `satchel-script-clear'"
                (abbreviate-file-name satchel-script-file)))
  (make-directory (file-name-directory satchel-script-file) t)
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file satchel-script-file
      (insert (satchel--render-script))))
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

(defun satchel--drop-files (files)
  "Forget FILES in the persistent marks, the stash and the queue.
In memory only.  A copy/move op loses just these files (and is dropped
entirely if that empties it); a delete op is dropped outright.  One
pass over the stash and the queue, however many FILES there are.
Return non-nil if the queue changed."
  (let ((set (make-hash-table :test 'equal))
        changed new-ops)
    (dolist (f files)
      (puthash f t set)
      (remhash f satchel-persistent-marks))
    (satchel--remove-mark-overlays files)
    (setq satchel-stash
          (cl-remove-if (lambda (e) (gethash (car e) set)) satchel-stash))
    (dolist (op satchel--script-ops)
      (let* ((old (satchel-op-files op))
             (kept (cl-remove-if (lambda (f) (gethash f set)) old)))
        (unless (= (length kept) (length old))
          (setq changed t))
        (when kept
          (setf (satchel-op-files op) kept)
          (push op new-ops))))
    (setq satchel--script-ops (nreverse new-ops))
    changed))

;; Keep the stash, the queue and the persistent marks in sync with the
;; built-in unmark commands.  Neither of these touches disk.
;;
;; Instead of guessing which line an unmark command acted on (`DEL' acts
;; on the previous line, `u' with a numeric prefix on several lines,
;; `U'/`M-DEL' on all of them), look at the result: any tracked file whose
;; line now has a blank mark column was unmarked.
(defun satchel--unmarked-tracked-files ()
  "Tracked files listed in this buffer whose mark column is now blank."
  (let ((dirs (satchel--buffer-dirs))
        here result)
    (maphash (lambda (f _)
               (when (gethash (file-name-directory f) dirs)
                 (push f here)))
             satchel-persistent-marks)
    (when here
      (save-excursion
        (if (<= (length here) satchel--goto-threshold)
            (dolist (f here)
              (when (and (dired-goto-file f)
                         (eq (char-after (line-beginning-position)) ?\s))
                (push f result)))
          (let ((set (make-hash-table :test 'equal)))
            (dolist (f here) (puthash f t set))
            (goto-char (point-min))
            (while (not (eobp))
              (when (eq (char-after (line-beginning-position)) ?\s)
                (let ((f (dired-get-filename nil t)))
                  (when (and f (gethash f set))
                    (push f result))))
              (forward-line 1))))))
    result))

(defun satchel--sync-after-unmark (&rest _)
  "Forget tracked files that are unmarked in the current Dired buffer.
Drops them from `satchel-persistent-marks', `satchel-stash' and the
script queue.  Meant as :after advice on the Dired unmark commands."
  (when (and (derived-mode-p 'dired-mode)
             (> (hash-table-count satchel-persistent-marks) 0))
    (when-let* ((dropped (satchel--unmarked-tracked-files)))
      (when (satchel--drop-files dropped)
        (satchel--preview-refresh-if-open)
        (message "Removed queued command(s) for %d unmarked file(s)"
                 (length dropped))))))

(dolist (cmd '(dired-unmark
               dired-unmark-backward
               dired-unmark-all-marks
               dired-unmark-all-files))
  (advice-add cmd :after #'satchel--sync-after-unmark))

;; ---------------------------------------------------------------------
;; Pack / cut / unpack (stash)
;; ---------------------------------------------------------------------

(defun satchel--kind-char (kind)
  "Return the marker character for satchel entries of KIND."
  (if (eq kind 'cut) satchel-cut-marker-char satchel-copy-marker-char))

(defun satchel--stash-files (kind)
  "Return the files in the satchel that are packed as KIND."
  (cl-loop for (file . k) in satchel-stash
           when (eq k kind) collect file))

(defun satchel--release-marks (files)
  "Forget the stored marks of FILES and clear them in every buffer."
  (dolist (f files)
    (satchel--forget-mark f))
  (satchel--mark-in-all-buffers files ?\s))

(defun satchel--release-unneeded-marks (files)
  "Clear the marks of FILES that are neither packed nor still queued.
Used after removing an operation from the queue: a file that another
operation still references, or that has been packed again, keeps its
mark."
  (let ((waiting (satchel--waiting-files))
        (stashed (make-hash-table :test 'equal)))
    (dolist (entry satchel-stash)
      (puthash (car entry) t stashed))
    (satchel--release-marks
     (cl-remove-if (lambda (f)
                     (or (gethash f waiting) (gethash f stashed)))
                   files))))

(defun satchel--star-marked-files ()
  "Return the absolute names of files carrying the plain `*' mark.
Files already marked `y'/`x' (packed or queued) or `D' (flagged) are
not included, so packing never picks up the satchel's own marks."
  (let ((case-fold-search nil)
        files)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^\\*" nil t)
        (when-let* ((f (dired-get-filename nil t)))
          (push f files))
        (forward-line 1)))
    (nreverse files)))

(defun satchel--check-not-queued (files)
  "Refuse FILES that a queued move or delete will take away."
  (when satchel--script-ops
    (let ((gone (make-hash-table :test 'equal)))
      (dolist (op satchel--script-ops)
        (when (memq (satchel-op-type op) '(move delete))
          (dolist (f (satchel-op-files op))
            (puthash f t gone))))
      (dolist (f files)
        (when (gethash f gone)
          (user-error "`%s' already has a queued move/delete; unmark it first (u)"
                      (file-name-nondirectory f)))))))

(defun satchel--check-eligible (files &optional dir)
  "Refuse `.', `..' and files with a queued move/delete.
When DIR (the directory of the Dired line the files came from) is
given, also refuse a name that resolves to DIR itself or to its parent,
in case `dired-get-filename' resolves the `.' and `..' lines that way."
  (let* ((cur (and dir (directory-file-name (expand-file-name dir))))
         (parent (and cur (directory-file-name (file-name-directory cur)))))
    (dolist (f files)
      (when (or (member (file-name-nondirectory f) '("." ".."))
                (and cur (member (directory-file-name f) (list cur parent))))
        (user-error "Cannot operate on `.' or `..'"))))
  (satchel--check-not-queued files))

(defun satchel--pack (kind)
  "Add the `*'-marked files (or the file at point) to the satchel as KIND.
The satchel accumulates across Dired buffers; a file that is already
in it just has its kind switched.  When acting on the file at point
\(no `*' marks), move to the next line afterwards, like `d' does.
Refused while the satchel script is running."
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (satchel--ensure-idle)
  (let* ((star-files (satchel--star-marked-files))
         (files (or star-files
                    (list (or (dired-get-filename nil t)
                              (user-error "No file at point")))))
         (char (satchel--kind-char kind))
         (index (make-hash-table :test 'equal))
         (added nil)
         (changed 0))
    (satchel--check-eligible files (dired-current-directory))
    (dolist (e satchel-stash) (puthash (car e) e index))
    (dolist (f files)
      (let ((entry (gethash f index)))
        (cond
         ((null entry)
          (cl-incf changed)
          (let ((new (cons f kind)))
            (puthash f new index)
            (push new added)))
         ((not (eq (cdr entry) kind))
          (cl-incf changed)
          (setcdr entry kind))))
      ;; Always redraw the mark: a `*' may have replaced an earlier one.
      (satchel--record-mark f char))
    (setq satchel-stash (nconc satchel-stash (nreverse added)))
    ;; Mark in every Dired buffer showing these files, not just this one,
    ;; so no buffer looks "unmarked" to `satchel--sync-after-unmark'.
    (satchel--mark-in-all-buffers files char)
    ;; Acting on the file at point: advance like `dired-flag-file-deletion'.
    (unless star-files
      (dired-next-line 1))
    (message "Packed %d file(s) to %s (satchel now has %d)"
             changed (if (eq kind 'cut) "move" "copy") (length satchel-stash))))

(defun satchel-pack ()
  "Pack the marked files (or the file at point) to be COPIED.
Bound to `y'.  See `satchel--pack'."
  (interactive)
  (satchel--pack 'copy))

(defun satchel-cut ()
  "Pack the marked files (or the file at point) to be MOVED.
Bound to `x'.  See `satchel--pack'."
  (interactive)
  (satchel--pack 'cut))

(defun satchel-unpack ()
  "Empty the satchel and clear its persistent marks.
Files that still have a queued operation keep their mark (it is the
\"queued\" indicator).  Use `dired-unmark' on a queued file, or
`satchel-script-clear' to drop everything queued.
Refused while the satchel script is running."
  (interactive)
  (satchel--ensure-idle)
  ;; Keep the marks of everything that is still waiting for the script,
  ;; whether it is in the queue or only in a failed run's cleanup list.
  (let ((pending (seq-union satchel--script-pending-cleanup
                            (satchel--script-pending-files))))
    (satchel--release-marks
     (cl-remove-if (lambda (f) (member f pending))
                   (mapcar #'car satchel-stash))))
  (setq satchel-stash nil)
  ;; A file packed again after it was pasted loses its packed mark here,
  ;; but it still has queued work, so redraw it with the queued mark.
  (satchel--paint-in-all-buffers satchel-persistent-marks)
  (message "Satchel emptied"))

;; ---------------------------------------------------------------------
;; Immediate copy / move helpers (LIVE mode)
;; ---------------------------------------------------------------------

(defun satchel--copy-file-list (files dest-dir)
  "Copy FILES into DEST-DIR using built-in `dired-copy-file'."
  ;; Directories are only copied when `dired-recursive-copies' allows it.
  (let ((dired-recursive-copies 'always))
    (dolist (from files)
      (let ((to (expand-file-name (file-name-nondirectory
                                   (directory-file-name from))
                                  dest-dir)))
        ;; OK-IF-ALREADY-EXISTS = t overwrites silently (an integer would ask).
        (dired-copy-file from to t))))
  (message "Copied %d file(s) to %s" (length files) dest-dir))

(defun satchel--move-file-list (files dest-dir)
  "Move/rename FILES into DEST-DIR using built-in `dired-rename-file'."
  (dolist (from files)
    (let ((to (expand-file-name (file-name-nondirectory
                                 (directory-file-name from))
                                dest-dir)))
      (dired-rename-file from to t)))
  (message "Moved %d file(s) to %s" (length files) dest-dir))

;; ---------------------------------------------------------------------
;; Command building (used when rendering the script)
;; ---------------------------------------------------------------------

(defun satchel--dest-nonposix-p (dir)
  "Return non-nil if DIR lives on a FAT/exFAT/NTFS-like filesystem.
Asks GNU `stat'.  Anything that goes wrong (BSD stat, missing
directory, remote path) counts as \"no\".  Memoized while rendering."
  (satchel--memo
   (list 'nonposix dir)
   (lambda ()
     (and (not (file-remote-p dir))
          (executable-find "stat")
          (let ((type (ignore-errors
                        (car (process-lines "stat" "-f" "-c" "%T"
                                            (expand-file-name dir))))))
            (and type (member type satchel-nonposix-fs-types) t))))))

(defun satchel--rsync-cmd (mode files dest-dir)
  "Build the shell command string that copies/moves FILES into DEST-DIR.
MODE is either `copy' or `move'.  `--partial' lets interrupted large
files resume when the script is re-run.

For `move', rsync's `--remove-source-files' deletes only files, never
directories, so a second line prunes the empty directory tree left
behind in the source.  `find -empty -delete' removes only directories
that are really empty, and `|| true' keeps a missing source (e.g. on a
re-run of a leftover script) from aborting the script under `set -e'."
  (let* ((dest (file-name-as-directory (expand-file-name dest-dir)))
         (base (if (satchel--dest-nonposix-p dest)
                   satchel-rsync-flags-nonposix
                 satchel-rsync-flags))
         (flags (if (eq mode 'move)
                    (concat base " --remove-source-files --ignore-missing-args")
                  base))
         (sources (mapconcat (lambda (f) (shell-quote-argument (expand-file-name f)))
                             files " "))
         (rsync (format "rsync %s -- %s %s" flags sources (shell-quote-argument dest))))
    (if (eq mode 'move)
        (concat rsync "\n"
                (format "find %s -depth -type d -empty -delete || true" sources))
      rsync)))

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
in this Dired buffer.  Only the flagged lines are visited."
  (let ((re (concat "^" (regexp-quote (char-to-string dired-del-marker))))
        (case-fold-search nil)
        files)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward re nil t)
        (when-let* ((f (dired-get-filename nil t)))
          (push f files))
        (forward-line 1)))
    (nreverse files)))

;; ---------------------------------------------------------------------
;; Interactive queue preview
;; ---------------------------------------------------------------------

(defconst satchel--preview-buffer "*satchel-preview*"
  "Name of the buffer that lists the queued satchel operations.")

(defconst satchel--operation-buffer "*satchel-operation*"
  "Name of the buffer that shows one queued operation in detail.")

(defconst satchel--script-text-buffer "*satchel-script*"
  "Name of the buffer that shows the full generated script.")

(defun satchel--preview-action (op)
  "Return OP's action word, propertized for the preview."
  (pcase (satchel-op-type op)
    ('copy   (propertize "copy"   'face 'success))
    ('move   (propertize "move"   'face 'warning))
    ('delete (propertize "delete" 'face 'error))))

(defun satchel--preview-file-names (op)
  "Return a short one-line summary of OP's files."
  (let* ((files (satchel-op-files op))
         (n (length files))
         (names (mapcar (lambda (f)
                          (file-name-nondirectory (directory-file-name f)))
                        files)))
    (if (= n 1)
        (car names)
      (format "%d files: %s%s"
              n
              (string-join (seq-take names 3) ", ")
              (if (> n 3) (format ", +%d" (- n 3)) "")))))

(defun satchel--preview-target (op)
  "Return a short description of where OP works, for the preview."
  (pcase (satchel-op-type op)
    ((or 'copy 'move)
     (concat (propertize "→ " 'face 'shadow)
             (abbreviate-file-name (satchel-op-dest op))))
    ('delete
     (concat (propertize "from " 'face 'shadow)
             (abbreviate-file-name
              (file-name-directory
               (directory-file-name (car (satchel-op-files op)))))))))

(defun satchel--preview-entries ()
  "Return `tabulated-list-entries' for the satchel queue."
  (let ((index 0))
    (mapcar
     (lambda (op)
       (cl-incf index)
       (list op
             (vector (propertize (number-to-string index) 'face 'shadow)
                     (satchel--preview-action op)
                     (satchel--preview-file-names op)
                     (satchel--preview-target op))))
     satchel--script-ops)))

(defun satchel--preview-update-summary ()
  "Update the mode-line summary of the queue preview."
  (let ((ops (length satchel--script-ops))
        (files (length (satchel--script-pending-files))))
    (setq mode-line-process
          (format " [%d op%s, %d file%s]"
                  ops (if (= ops 1) "" "s")
                  files (if (= files 1) "" "s")))))

(defun satchel--preview-refresh ()
  "Reprint the queue preview from `satchel--script-ops'."
  (satchel--preview-update-summary)
  (tabulated-list-print t)
  (when (null satchel--script-ops)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert "\n  " (propertize "No queued operations." 'face 'shadow) "\n")))
  (force-mode-line-update))

(defun satchel--preview-revert (&rest _)
  "`revert-buffer-function' for the interactive queue preview."
  (satchel--preview-refresh))

(define-derived-mode satchel-preview-mode tabulated-list-mode "Satchel-Preview"
  "Major mode for reviewing and editing the satchel script queue.

The queue is executed in order, so the order shown here is the order
the generated script will use.

\\{satchel-preview-mode-map}"
  (setq tabulated-list-format
        [("#" 4 nil :right-align t)
         ("Action" 7 nil)
         ("Files" 36 nil)
         ("Destination" 0 nil)])
  (setq tabulated-list-entries #'satchel--preview-entries)
  (setq tabulated-list-padding 1)
  (setq-local revert-buffer-function #'satchel--preview-revert)
  (hl-line-mode 1)
  (tabulated-list-init-header))

(define-key satchel-preview-mode-map (kbd "RET") #'satchel-preview-show-op)
(define-key satchel-preview-mode-map (kbd "j") #'next-line)
(define-key satchel-preview-mode-map (kbd "k") #'previous-line)
(define-key satchel-preview-mode-map (kbd "J") #'satchel-preview-move-op-down)
(define-key satchel-preview-mode-map (kbd "K") #'satchel-preview-move-op-up)
(define-key satchel-preview-mode-map (kbd "d") #'satchel-preview-delete-op)
(define-key satchel-preview-mode-map (kbd "M-<up>") #'satchel-preview-move-op-up)
(define-key satchel-preview-mode-map (kbd "C-<up>") #'satchel-preview-move-op-up)
(define-key satchel-preview-mode-map (kbd "M-<down>") #'satchel-preview-move-op-down)
(define-key satchel-preview-mode-map (kbd "C-<down>") #'satchel-preview-move-op-down)
(define-key satchel-preview-mode-map (kbd "s") #'satchel-preview-show-script)
(define-key satchel-preview-mode-map (kbd "x") #'satchel-preview-execute)
(define-key satchel-preview-mode-map (kbd "C") #'satchel-preview-clear)
(define-key satchel-preview-mode-map (kbd "?") #'ignore)

;; Evil's state keymaps are consulted before a mode's local map, so
;; without this `K' would run `evil-lookup' and `RET' would run
;; `evil-ret' in the preview.  Elevating the map lets its own keys win;
;; keys it does not bind still fall through to Evil.
(with-eval-after-load 'evil
  (when (fboundp 'evil-make-overriding-map)
    (evil-make-overriding-map satchel-preview-mode-map)))

(defun satchel--preview-current-op ()
  "Return the queued operation at point in the preview."
  (or (tabulated-list-get-id)
      (user-error "No satchel operation at point")))

(defun satchel--preview-goto-index (index)
  "Move to the INDEXth (0-based) operation in the preview."
  (goto-char (point-min))
  (unless tabulated-list-use-header-line
    (forward-line 1))
  (forward-line (max 0 index))
  (beginning-of-line))

(defun satchel-preview-open ()
  "Open (or refresh) the interactive satchel queue preview."
  (interactive)
  (let ((buf (get-buffer-create satchel--preview-buffer)))
    (with-current-buffer buf
      (unless (derived-mode-p 'satchel-preview-mode)
        (satchel-preview-mode))
      (satchel--preview-refresh))
    (pop-to-buffer buf)))

(defun satchel--preview-refresh-if-open ()
  "Refresh the queue preview buffer if it is currently live."
  (when-let* ((buf (get-buffer satchel--preview-buffer)))
    (with-current-buffer buf
      (when (derived-mode-p 'satchel-preview-mode)
        (satchel--preview-refresh)))))

(defun satchel-preview-delete-op ()
  "Remove the queued operation at point.
Only the operation is removed; files are not touched.  A file that no
operation references any more, and that is not packed in the satchel,
loses its mark."
  (interactive)
  (let* ((op (satchel--preview-current-op))
         (files (satchel-op-files op))
         (type (satchel-op-type op))
         (index (cl-position op satchel--script-ops :test #'eq)))
    (setq satchel--script-ops (delq op satchel--script-ops))
    (satchel--release-unneeded-marks files)
    (satchel--preview-refresh)
    (satchel--preview-goto-index
     (min index (1- (length satchel--script-ops))))
    (message "Removed %s operation on %d file(s) (files untouched)"
             type (length files))))

(defun satchel--preview-move-op (delta)
  "Move the operation at point DELTA positions in the queue."
  (let* ((op (satchel--preview-current-op))
         (index (cl-position op satchel--script-ops :test #'eq))
         (target (+ index delta)))
    (unless (and (>= target 0) (< target (length satchel--script-ops)))
      (user-error "Operation is already at the %s"
                  (if (< delta 0) "top" "bottom")))
    (let ((ops (copy-sequence satchel--script-ops))
          (a (nth index satchel--script-ops))
          (b (nth target satchel--script-ops)))
      (setcar (nthcdr index ops) b)
      (setcar (nthcdr target ops) a)
      (setq satchel--script-ops ops))
    (satchel--preview-refresh)
    (message "Moved operation %s" (if (< delta 0) "up" "down"))))

(defun satchel-preview-move-op-up ()
  "Move the queued operation at point one step earlier."
  (interactive)
  (satchel--preview-move-op -1))

(defun satchel-preview-move-op-down ()
  "Move the queued operation at point one step later."
  (interactive)
  (satchel--preview-move-op +1))

(defvar-local satchel--operation-op nil
  "Operation currently shown in the operation detail buffer.")

(defun satchel--operation-render ()
  "Insert the detail view of `satchel--operation-op' into the current buffer."
  (let ((op satchel--operation-op)
        (inhibit-read-only t))
    (erase-buffer)
    (if (null op)
        (insert "No operation selected.\n")
      (let ((type (satchel-op-type op))
            (files (satchel-op-files op)))
        (insert (propertize (format "%s operation (%d file%s)\n\n"
                                    (capitalize (symbol-name type))
                                    (length files)
                                    (if (= (length files) 1) "" "s"))
                            'face 'bold))
        (insert (propertize "Files\n" 'face 'bold))
        (dolist (f files)
          (insert "  " (propertize f 'face 'dired-filename) "\n"))
        (when-let* ((dest (satchel-op-dest op)))
          (insert "\n" (propertize "Destination\n" 'face 'bold))
          (insert "  " (abbreviate-file-name dest) "\n"))
        (insert "\n" (propertize "Command\n" 'face 'bold))
        (insert (satchel--op-command op) "\n")))))

(defun satchel--operation-revert (&rest _)
  "Revert the operation detail buffer."
  (satchel--operation-render))

(define-derived-mode satchel-operation-mode special-mode "Satchel-Operation"
  "Major mode for the detail view of one satchel operation.

\\{satchel-operation-mode-map}"
  (setq-local revert-buffer-function #'satchel--operation-revert))

(defun satchel-preview-show-op ()
  "Show the files and generated command of the operation at point."
  (interactive)
  (let* ((op (satchel--preview-current-op))
         (buf (get-buffer-create satchel--operation-buffer)))
    (with-current-buffer buf
      (unless (derived-mode-p 'satchel-operation-mode)
        (satchel-operation-mode))
      (setq satchel--operation-op op)
      (satchel--operation-render)
      (goto-char (point-min)))
    (display-buffer buf)))

(defun satchel-preview-show-script ()
  "Show the full script that the current queue would run."
  (interactive)
  (unless satchel--script-ops
    (user-error "Satchel queue is empty"))
  (let ((buf (get-buffer-create satchel--script-text-buffer)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (satchel--render-script)))
      (sh-mode)
      (goto-char (point-min))
      (view-mode 1))
    (pop-to-buffer buf)))

(defun satchel-preview-execute ()
  "Run the queued satchel script."
  (interactive)
  (let ((count (length satchel--script-ops)))
    (satchel-script-execute)
    (unless satchel--script-ops
      (message "Running %d satchel operation(s); watch %s"
               count satchel--execute-buffer))))

(defun satchel-preview-clear ()
  "Clear every queued satchel operation (asks for confirmation)."
  (interactive)
  (satchel-script-clear))

;; ---------------------------------------------------------------------
;; Script commands: preview, clear, execute
;; ---------------------------------------------------------------------

(defun satchel-script-open ()
  "Preview the satchel queue or the leftover script.
With a non-empty queue, open the interactive queue preview, where
operations can be inspected, deleted and reordered (nothing is written
to disk).  With an empty queue, open the leftover script on disk, if
there is one."
  (interactive)
  (cond
   (satchel--script-ops
    (satchel-preview-open))
   ((file-exists-p satchel-script-file)
    (find-file satchel-script-file))
   (t
    (user-error "Satchel queue is empty and there is no leftover script"))))

(defun satchel-script-clear ()
  "Drop every queued operation (in memory) and delete the script file.
This is the manual way to get rid of a leftover script.  Asks for
confirmation first, since it throws the whole queue away."
  (interactive)
  (when (satchel--script-running-p)
    (user-error "A satchel script is running; wait for it to finish"))
  (let ((files (seq-union satchel--script-pending-cleanup
                          (satchel--script-pending-files)))
        (script-exists (file-exists-p satchel-script-file)))
    (when (and (or files satchel--script-ops script-exists)
               (not (y-or-n-p
                     (format "Drop %d queued operation(s) / %d file(s)%s? "
                             (length satchel--script-ops)
                             (length files)
                             (if script-exists
                                 (format " and delete %s"
                                         (abbreviate-file-name satchel-script-file))
                               "")))))
      (user-error "Cancelled"))
    (let ((packed (make-hash-table :test 'equal)))
      (dolist (e satchel-stash) (puthash (car e) t packed))
      (satchel--release-marks
       (seq-remove (lambda (f) (gethash f packed)) files)))
    (setq satchel--script-ops nil
          satchel--script-pending-cleanup nil)
    (when script-exists
      (delete-file satchel-script-file))
    (satchel--preview-refresh-if-open)
    (message "Cleared satchel queue and script file: %s" satchel-script-file)))

(defun satchel--format-duration (seconds)
  "Format SECONDS as e.g. \"2m 14s\" or \"37s\"."
  (let ((secs (round seconds)))
    (if (>= secs 60)
        (format "%dm %ds" (/ secs 60) (% secs 60))
      (format "%ds" secs))))

(defun satchel--notify (success msg duration)
  "Show a desktop notification that the satchel script has finished.
SUCCESS is non-nil if it finished cleanly; MSG is the raw
compilation-finish status string (used for failure detail); DURATION
is the run's wall-clock length in seconds.

Runs of at least `satchel-notify-persistent-threshold' seconds get a
persistent notification (`:timeout 0' per the Desktop Notifications
spec; most daemons honor this as \"never expire\").  Shorter runs get
an auto-expiring one (`satchel-notify-short-timeout').  Never signals:
a missing notification daemon must not break the finish handler."
  (when (and satchel-notify-on-finish
             (fboundp 'notifications-notify))
    (condition-case err
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
                                :timeout (if persistent
                                             0
                                           satchel-notify-short-timeout)))
      (error (message "dired-satchel: notification failed: %s"
                      (error-message-string err))))))

(defun satchel--script-finish-cleanup (buf msg)
  "Compilation-finish handler for the satchel script.
Ignores every compilation except the satchel's own buffer BUF, so an
unrelated `M-x compile' finishing first cannot trigger the cleanup.
On success: delete the script file and clear pending marks.  On
failure: keep the script on disk (it is protected from overwriting and
can be re-run with `satchel-script-execute') and keep the list of marks
to clear.  Always show a desktop notification (last, and never
signalling) and reset the running state."
  (when (equal (buffer-name buf) satchel--execute-buffer)
    (remove-hook 'compilation-finish-functions #'satchel--script-finish-cleanup)
    (let ((success (string-match-p "\\`finished" msg))
          (duration (if satchel--script-start-time
                        (float-time (time-subtract (current-time)
                                                   satchel--script-start-time))
                      0)))
      (when success
        ;; The script file first: it is the part that must not be missed.
        ;; Demote a failure so the marks and the notification still happen.
        (when (file-exists-p satchel-script-file)
          (with-demoted-errors "dired-satchel: deleting the script failed: %S"
            (delete-file satchel-script-file)))
        (with-demoted-errors "dired-satchel: clearing marks failed: %S"
          ;; Keep the mark of files that are back in the satchel or were
          ;; queued again while the script was running.
          (let ((keep (make-hash-table :test 'equal)))
            (dolist (e satchel-stash) (puthash (car e) t keep))
            (dolist (f (satchel--script-pending-files)) (puthash f t keep))
            (satchel--release-marks
             (seq-remove (lambda (f) (gethash f keep))
                         satchel--script-pending-cleanup))))
        (setq satchel--script-pending-cleanup nil))
      (setq satchel--script-start-time nil)
      (satchel--notify success msg duration))))

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
  (when (satchel--script-running-p)
    (user-error "A satchel script is already running"))
  (let ((leftover (file-exists-p satchel-script-file)))
    (unless (or satchel--script-ops leftover)
      (user-error "Satchel queue is empty and there is no leftover script"))
    (when (and satchel--script-ops leftover)
      (user-error "Leftover script exists at %s: empty the queue and run it with `v x', or delete it with `satchel-script-clear'"
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
         (compilation-buffer-name-function
          (lambda (_mode) satchel--execute-buffer))
         ;; A file-moving script has nothing to do with unsaved buffers:
         ;; do not let `compile' ask to save them (or save them silently).
         (compilation-save-buffers-predicate #'ignore))
    ;; Marks to clear on success.  Accumulate: a failed earlier run keeps
    ;; its files here, so resuming the leftover script (empty queue) still
    ;; cleans their marks up.
    (setq satchel--script-pending-cleanup
          (seq-union satchel--script-pending-cleanup
                     (satchel--script-pending-files))
          satchel--script-ops nil
          satchel--script-start-time (current-time))
    (satchel--preview-refresh-if-open)
    (add-hook 'compilation-finish-functions #'satchel--script-finish-cleanup)
    (compile (format "bash %s" (shell-quote-argument satchel-script-file)))
    (with-current-buffer satchel--execute-buffer
      (setq-local compilation-scroll-output t))))

(defun satchel--kill-emacs-query ()
  "Ask before quitting Emacs while the satchel has unfinished work.
Meant for `kill-emacs-query-functions'."
  (cond
   ((satchel--script-running-p)
    (yes-or-no-p "A satchel script is still running and will be killed.  Quit anyway? "))
   (satchel--script-ops
    (yes-or-no-p (format "%d satchel operation(s) are queued but were never run.  Quit anyway? "
                         (length satchel--script-ops))))
   (t t)))

(add-hook 'kill-emacs-query-functions #'satchel--kill-emacs-query)

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
  (let ((queued (length satchel--script-ops))
        (pending (length (satchel--script-pending-files)))
        (buf (get-buffer satchel--execute-buffer)))
    (cond
     ((satchel--script-running-p)
      (message "Satchel script is running: %d operation(s) queued, %d file(s) pending -- jumping to live output"
               queued pending)
      (pop-to-buffer buf)
      (goto-char (point-max)))
     ((> queued 0)
      (message "%d operation(s) queued, %d file(s) pending (\"v x\" to run)"
               queued pending))
     ((file-exists-p satchel-script-file)
      (message "Queue is empty, but a leftover script exists at %s (\"v x\" to run it, \"v c\" to delete it)"
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

;; Drop a previous copy first: re-evaluating this file builds an `equal'
;; but not `eq' list, which would otherwise be added a second time.
(setq global-mode-string
      (append (remove satchel-mode-line-lighter global-mode-string)
              (list satchel-mode-line-lighter)))

;; ---------------------------------------------------------------------
;; Mode-aware copy / move / delete actions
;; ---------------------------------------------------------------------

(defun satchel--outside-dir (files dir)
  "Return the members of FILES that do not already live directly in DIR."
  (let ((dir (file-name-as-directory (expand-file-name dir))))
    (cl-remove-if
     (lambda (f)
       (equal (file-name-directory (directory-file-name (expand-file-name f)))
              dir))
     files)))

(defun satchel--base-name (file)
  "Return the last component of FILE, also for directories."
  (file-name-nondirectory (directory-file-name file)))

(defun satchel--real-directory-p (file)
  "Return non-nil if FILE is a directory and not a symlink to one."
  (and (file-directory-p file) (not (file-symlink-p file))))

(defun satchel--check-paste (copies cuts dest)
  "Signal a `user-error' if pasting COPIES and CUTS into DEST is unsafe.
Refuses: two files with the same name (the later would silently
overwrite the earlier), a directory pasted into itself, a file landing
on a directory or the other way round, and a directory moved onto an
existing directory (`mv' fails there while rsync would merge)."
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (f (append copies cuts))
      (let* ((name (satchel--base-name f))
             (target (expand-file-name name dest)))
        (when (gethash name seen)
          (user-error "Two packed files are both named `%s'" name))
        (puthash name t seen)
        (when (and (satchel--real-directory-p f)
                   (file-in-directory-p dest f))
          (user-error "Cannot paste directory `%s' into itself" name))
        (when (or (file-exists-p target) (file-symlink-p target))
          (let ((src-dir (satchel--real-directory-p f))
                (dst-dir (satchel--real-directory-p target)))
            (cond
             ((not (eq (and src-dir t) (and dst-dir t)))
              (user-error "`%s' already exists in the destination as a different kind of file"
                          name))
             ((and src-dir (member f cuts))
              (user-error "Directory `%s' already exists in the destination; moving onto it is not supported (copy it, or remove the target)"
                          name)))))))))

(defun satchel-action-paste ()
  "Deliver the satchel into the current directory, then empty it.
Files packed with `y' are copied, files packed with `x' are moved;
files that already live in this directory are skipped.

Immediate when `satchel-script-mode' is nil (existing files are
overwritten silently); otherwise queues a copy and/or a move operation
in memory.  In script mode each queued file keeps its mark until the
script actually runs.  Refused while the satchel script is running."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (satchel--ensure-idle)
  (unless satchel-stash
    (user-error "Satchel is empty"))
  (let* ((dest (dired-current-directory))
         (all (mapcar #'car satchel-stash))
         (copies (satchel--outside-dir (satchel--stash-files 'copy) dest))
         (cuts (satchel--outside-dir (satchel--stash-files 'cut) dest))
         (skipped (let ((used (make-hash-table :test 'equal)))
                    (dolist (f (append copies cuts))
                      (puthash f t used))
                    (cl-remove-if (lambda (f) (gethash f used)) all))))
    (unless (or copies cuts)
      (user-error "Everything in the satchel is already in this directory"))
    (satchel--check-eligible (append copies cuts))
    (satchel--check-paste copies cuts dest)
    (if satchel-script-mode
        (progn
          (when copies (satchel--script-queue-op 'copy copies dest))
          (when cuts (satchel--script-queue-op 'move cuts dest))
          (message "Queued copy of %d and move of %d file(s) to %s"
                   (length copies) (length cuts) dest)
          ;; Skipped files have nothing queued, so their mark goes away too.
          (satchel--release-marks skipped)
          (setq satchel-stash nil)
          ;; Repaint: the pasted files are no longer in the satchel, so
          ;; their mark now shows as queued instead of packed.
          (satchel--paint-in-all-buffers satchel-persistent-marks)
          (satchel--preview-refresh-if-open))
      ;; Even if one file fails half way, leave the stash and the marks
      ;; consistent: files already moved must not stay packed.
      (unwind-protect
          (progn
            (when copies (satchel--copy-file-list copies dest))
            (when cuts (satchel--move-file-list cuts dest)))
        (satchel--release-marks (append copies cuts skipped))
        (setq satchel-stash nil)
        (revert-buffer)))))

(defun satchel-action-flag-deletion ()
  "Flag the file at point for deletion.
In immediate mode this is just the standard `dired-flag-file-deletion'.
In script mode it also queues a delete operation for the file right
away (in memory), so flagging files across several Dired buffers is
all recorded, regardless of which buffer `satchel-action-execute' is
eventually run from.  Either way the flag is recorded so it survives
tab switches; in script mode it is cleared only once the script runs
\(or the file is unmarked).  Refused while the satchel script is running."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (satchel--ensure-idle)
  (let ((file (dired-get-filename nil t)))
    (unless file
      (user-error "No file at point"))
    (satchel--check-eligible (list file) (dired-current-directory))
    (when satchel-script-mode
      ;; Fail now, not when the script is rendered, if trashing is wanted
      ;; but impossible.
      (satchel--trash-command)
      (satchel--script-queue-op 'delete (list file))
      (message "Queued %s for %s"
               (if delete-by-moving-to-trash "TRASH" "DELETE")
               (file-name-nondirectory file))
      (satchel--preview-refresh-if-open))
    ;; Flag first: `dired-flag-file-deletion' rewrites the marker column,
    ;; so painting before it would lose the face of the `D'.
    (dired-flag-file-deletion 1)
    (satchel--record-mark file dired-del-marker)
    ;; Every buffer showing this file, so none looks "unmarked".
    (satchel--mark-in-all-buffers (list file) dired-del-marker)))

(defun satchel-action-execute ()
  "In immediate mode, delete files flagged for deletion.
In script mode, run the queued operations (or the leftover script when
the queue is empty) via `satchel-script-execute'."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (if satchel-script-mode
      (satchel-script-execute)
    (satchel--ensure-idle)
    (let ((flagged (satchel--flagged-for-deletion)))
      (dired-do-flagged-delete)
      ;; Only forget files that are really gone: if the deletion was
      ;; declined, the `D' flags are still there and must stay tracked.
      (dolist (f flagged)
        (unless (or (file-exists-p f) (file-symlink-p f))
          (satchel--forget-mark f))))))

;; ---------------------------------------------------------------------
;; Transient menu
;; ---------------------------------------------------------------------

(transient-define-prefix satchel-transient ()
  "Satchel (stash/rsync script) management menu."
  ["Satchel script"
   :if-derived 'dired-mode
   ("v" "Progress"                          satchel-script-progress)
   ("s" "Queue preview"                     satchel-script-open)
   ("x" "Execute"                           satchel-action-execute)
   ("c" "Clear queue and script file"       satchel-script-clear)
   ("t" "Toggle SCRIPT / LIVE mode"         satchel-toggle-script-mode)
   ("y" "Empty satchel"                     satchel-unpack)]
  ["Actions"
   ("q" "Quit" transient-quit-all)])

;; `dired-satchel' is often loaded lazily by the first satchel command,
;; when Dired buffers already exist.  Redraw marks that are already in
;; memory; the overlays also work in those buffers.
(satchel--paint-in-all-buffers satchel-persistent-marks)

(provide 'dired-satchel)
;;; dired-satchel.el ends here
