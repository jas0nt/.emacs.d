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
;; - SCRIPT mode: actions append rsync/rm commands to a script file
;;                instead of touching disk; you review and run the
;;                script yourself (`satchel-script-execute').
;;
;; Files that are packed or flagged for deletion get a persistent visual
;; mark that is redrawn automatically whenever a Dired buffer is
;; (re)read — including after `find-alternate-file', which many
;; tab/bookmark setups use to switch directories in place.
;;
;; Use `satchel-script-progress' to check how many commands/files are
;; still queued in the script, or to jump straight to the live output
;; of a script that is currently running.
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

(defvar satchel-stash nil
  "List of absolute file names currently packed into the satchel.")

(defvar satchel-script-mode t
  "When non-nil, satchel actions generate shell commands into
`satchel-script-file' instead of executing immediately.
This is a global toggle shared by all Dired buffers.")

(defvar satchel-script-pending-files nil
  "Files that have been queued into the satchel script (via copy, move,
or delete) but whose command hasn't run yet. Their persistent marks
are kept so you can see what's already queued vs. still untouched,
and are cleared once the script finishes running successfully.")

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

;; Keep persistent-mark bookkeeping in sync with the built-in u/U unmark keys.
(advice-add 'dired-unmark :before
            (lambda (&rest _)
              (when-let ((f (dired-get-filename nil t)))
                (satchel--forget-mark f)
                (setq satchel-stash (delete f satchel-stash))
                (setq satchel-script-pending-files
                      (delete f satchel-script-pending-files)))))

(advice-add 'dired-unmark-all-marks :before
            (lambda (&rest _)
              (when (derived-mode-p 'dired-mode)
                (save-excursion
                  (goto-char (point-min))
                  (while (not (eobp))
                    (when-let ((f (dired-get-filename nil t)))
                      (satchel--forget-mark f)
                      (setq satchel-stash (delete f satchel-stash))
                      (setq satchel-script-pending-files
                            (delete f satchel-script-pending-files)))
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
  "Empty the satchel and clear its persistent marks."
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
;; Rsync script accumulation (used by script mode)
;; ---------------------------------------------------------------------

(defun satchel--ensure-script ()
  "Create the script file with a shebang if it doesn't exist, and make
it executable."
  (unless (file-exists-p satchel-script-file)
    (make-directory (file-name-directory satchel-script-file) t)
    (with-temp-buffer
      (insert "#!/usr/bin/env bash\n")
      (insert "set -xeuo pipefail\n\n")
      (write-region (point-min) (point-max) satchel-script-file nil 'silent)))
  (set-file-modes satchel-script-file #o755))

(defun satchel--script-append (comment cmd)
  "Append a COMMENT line and a command CMD to the end of the script file."
  (satchel--ensure-script)
  (with-temp-buffer
    (insert "# " comment "\n")
    (insert cmd "\n\n")
    (write-region (point-min) (point-max) satchel-script-file t 'silent)))

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
  "Open the generated rsync/rm script for review/editing."
  (interactive)
  (satchel--ensure-script)
  (find-file satchel-script-file))

(defun satchel-script-clear ()
  "Delete the accumulated script file and clear its pending marks."
  (interactive)
  (when (file-exists-p satchel-script-file)
    (delete-file satchel-script-file))
  (dolist (f satchel-script-pending-files)
    (satchel--forget-mark f)
    (satchel--mark-in-all-buffers f ?\s))
  (setq satchel-script-pending-files nil)
  (message "Cleared satchel script: %s" satchel-script-file))

(defvar satchel--script-pending-cleanup nil
  "Files whose persistent marks should be cleared once the in-flight
script run finishes successfully.")

(defvar satchel--script-running nil
  "Non-nil while the satchel script's compilation process is alive.
Kept in sync by `satchel-script-execute' and
`satchel--script-finish-cleanup', and refreshed on demand by
`satchel-script-progress'.")

(defun satchel--script-finish-cleanup (_buf msg)
  "Compilation-finish handler that clears pending marks once the
satchel script has finished running."
  (setq satchel--script-running nil)
  (when (and satchel--script-pending-cleanup (string-match-p "^finished" msg))
    (dolist (f satchel--script-pending-cleanup)
      (satchel--forget-mark f)
      (satchel--mark-in-all-buffers f ?\s)))
  (setq satchel--script-pending-cleanup nil)
  (remove-hook 'compilation-finish-functions #'satchel--script-finish-cleanup))

(defun satchel-script-execute ()
  "Run the accumulated script asynchronously without blocking Emacs.
Prompts for confirmation first, and shows live progress in a
compilation buffer. On successful completion, clears persistent marks
for every file queued into the script (copy, move, or delete)."
  (interactive)
  (unless (file-exists-p satchel-script-file)
    (user-error "Satchel script does not exist: %s" satchel-script-file))
  (unless (y-or-n-p
           (format "Run satchel script %s now? "
                   (abbreviate-file-name satchel-script-file)))
    (user-error "Execution cancelled"))
  (let* ((default-directory (file-name-directory satchel-script-file))
         (buf-name "*satchel-execute*")
         (compilation-buffer-name-function (lambda (_mode) buf-name)))
    (setq satchel--script-pending-cleanup satchel-script-pending-files)
    (setq satchel-script-pending-files nil)
    (setq satchel--script-running t)
    (add-hook 'compilation-finish-functions #'satchel--script-finish-cleanup)
    (compile (format "bash %s" (shell-quote-argument satchel-script-file)))
    (with-current-buffer buf-name
      (setq-local compilation-scroll-output t))))

;; ---------------------------------------------------------------------
;; Progress inspection
;; ---------------------------------------------------------------------

(defun satchel--script-count-queued-commands ()
  "Count how many commands (copy/move/delete blocks) are queued in
`satchel-script-file', based on the `# ' comment line each block starts with."
  (if (file-exists-p satchel-script-file)
      (with-temp-buffer
        (insert-file-contents satchel-script-file)
        (how-many "^# " (point-min) (point-max)))
    0))

(defun satchel-script-progress ()
  "Show progress of the satchel script.

Reports how many commands are queued in the script and how many files
are still pending (queued but not yet run). If the script's
compilation process is currently alive, jumps straight to the live
output in the `*satchel-execute*' buffer instead of just printing a
summary, since that's where the real progress (e.g. rsync's
--progress output) is visible."
  (interactive)
  (let* ((queued (satchel--script-count-queued-commands))
         (pending (length satchel-script-pending-files))
         (buf (get-buffer "*satchel-execute*"))
         (proc (and buf (get-buffer-process buf)))
         (running (and proc (process-live-p proc))))
    (setq satchel--script-running (and running t))
    (cond
     (running
      (message "Satchel script is running: %d command(s) queued, %d file(s) pending — jumping to live output"
               queued pending)
      (pop-to-buffer buf)
      (goto-char (point-max)))
     ((file-exists-p satchel-script-file)
      (message "Satchel script is not running: %d command(s) queued, %d file(s) pending (script: %s)"
               queued pending (abbreviate-file-name satchel-script-file)))
     (t
      (message "No satchel script yet — nothing queued")))))

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
Immediate when `satchel-script-mode' is nil; appends an rsync
command to the script otherwise, keeping each file's persistent mark
until the script actually runs."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (unless satchel-stash
    (user-error "Satchel is empty"))
  (let ((dest (dired-current-directory)))
    (if satchel-script-mode
        (let* ((n (length satchel-stash))
               (cmd (satchel--rsync-cmd 'copy satchel-stash dest)))
          (satchel--script-append (format "copy %d file(s) -> %s" n dest) cmd)
          (dolist (f satchel-stash)
            (cl-pushnew f satchel-script-pending-files :test #'equal))
          (message "Appended rsync COPY command (%d file(s)) to %s"
                   n satchel-script-file))
      (satchel--copy-file-list satchel-stash dest)
      (revert-buffer))))

(defun satchel-action-move-here ()
  "Move packed files into the current directory.
Immediate when `satchel-script-mode' is nil; appends an rsync
command to the script otherwise. In script mode, the satchel is
emptied so you don't re-queue the same files, but each file's
persistent mark is kept (as a \"queued\" indicator) until the script
actually runs."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (unless satchel-stash
    (user-error "Satchel is empty"))
  (let ((dest (dired-current-directory)))
    (if satchel-script-mode
        (let* ((n (length satchel-stash))
               (cmd (satchel--rsync-cmd 'move satchel-stash dest)))
          (satchel--script-append (format "move %d file(s) -> %s" n dest) cmd)
          (dolist (f satchel-stash)
            (cl-pushnew f satchel-script-pending-files :test #'equal))
          (setq satchel-stash nil)
          (message "Appended rsync MOVE command (%d file(s)) to %s; satchel emptied (marks kept until run)"
                   n satchel-script-file))
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
In script mode, it additionally appends an rm command for this file
to the script immediately (so flagging files across multiple Dired
buffers all gets recorded, regardless of which buffer `satchel-action-execute'
is eventually run from). Either way, the flag is recorded so it
survives tab switches, and in script mode it is only cleared once the
script actually runs."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "Run this from a Dired buffer"))
  (let ((file (dired-get-filename nil t)))
    (unless file
      (user-error "No file at point"))
    (when satchel-script-mode
      (let ((cmd (format "rm -rf -- %s" (shell-quote-argument file))))
        (satchel--script-append (format "delete: %s" file) cmd)
        (cl-pushnew file satchel-script-pending-files :test #'equal)
        (message "Appended DELETE command for %s to %s"
                 (file-name-nondirectory file) satchel-script-file)))
    (satchel--record-mark file dired-del-marker)
    (dired-flag-file-deletion 1)))

(defun satchel-action-execute ()
  "In immediate mode, delete files flagged for deletion (the standard
Dired `D' mark, set via `satchel-action-flag-deletion'). In script
mode, execute the entire accumulated script (which already contains
any delete commands, plus any copy/move commands)."
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
   ("s" "Open script"     satchel-script-open)
   ("c" "Clear script"    satchel-script-clear)
   ("x" "Execute script"  satchel-script-execute)
   ("y" "Empty satchel"   satchel-unpack)]
  ["Actions"
   ("q" "Quit" transient-quit-all)])

(provide 'dired-satchel)
;;; dired-satchel.el ends here
