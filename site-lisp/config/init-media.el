(use-package image-mode
  :ensure nil
  :hook
  (image-mode . auto-revert-mode)
  :bind
  (:map image-mode-map
        ("=" . image-increase-size)
        ("-" . image-decrease-size)
        ("0" . image-transform-reset)
        ("j" . scroll-up-command)
        ("k" . scroll-down-command)
        ("n" . image-next-file)
        ("p" . image-previous-file)
        ("r" . image-rotate)
        ("l" . image-rotate)
        ("g" . revert-buffer)
        ("q" . quit-window))
  :config
  (setq auto-revert-verbose nil))

(use-package ready-player
  :custom
  (ready-player-autoplay nil)
  (ready-player-ask-for-project-sustainability nil)
  (ready-player-thumbnail-max-pixel-height 1000)
  :config
  (ready-player-mode 1)

  (defcustom my-ready-player-thumbnail-debounce-delay 0.3
    "Seconds to wait after the last percent adjustment before actually
regenerating the thumbnail.  Rapid key presses within this window are
coalesced into a single `ffmpegthumbnailer' call at the final percent."
    :type 'number
    :group 'ready-player)

  (defvar my-ready-player-thumbnail-percent-table (make-hash-table :test 'equal)
    "Map of media-file -> target thumbnail seek percent (integer 0-95).")

  (defvar my-ready-player-thumbnail-process-table (make-hash-table :test 'equal)
    "Map of media-file -> currently running regrab process (if any).")

  (defvar my-ready-player-thumbnail-debounce-timer-table (make-hash-table :test 'equal)
    "Map of media-file -> pending debounce timer for thumbnail regrab.")

  (defvar my-ready-player--regrab-log-buffer nil
    "Shared, reused log buffer for thumbnail regrabs.")

  (defun my-ready-player--thumbnail-percent-for (media-file)
    "Get current target seek percent for MEDIA-FILE, defaulting to 10."
    (or (gethash media-file my-ready-player-thumbnail-percent-table) 10))

  (defun my-ready-player--current-media-file ()
    "Resolve the media file at point/buffer, from `dired' or `ready-player'."
    (cond
     ((derived-mode-p 'ready-player-major-mode) (buffer-file-name))
     ((derived-mode-p 'dired-mode)
      (or (dired-get-filename nil t) (user-error "No file at point")))
     (t (user-error "Not in ready-player or dired"))))

  (defun my-ready-player--regrab-log-buffer ()
    "Return the shared log buffer, creating it if needed."
    (unless (buffer-live-p my-ready-player--regrab-log-buffer)
      (setq my-ready-player--regrab-log-buffer
            (generate-new-buffer "*ready-player-regrab*")))
    my-ready-player--regrab-log-buffer)

  (defun my-ready-player--regrab-thumbnail-for-file (media-file percent)
    "Regenerate ready-player's cached thumbnail for MEDIA-FILE at PERCENT (async).
PERCENT is an integer 0-99.  Cancels any in-flight regrab for the
same MEDIA-FILE first."
    (unless (executable-find "ffmpegthumbnailer")
      (user-error "ffmpegthumbnailer not found"))
    ;; Cancel any previous in-flight job for this file — no prompt, just kill it.
    (when-let ((old-proc (gethash media-file my-ready-player-thumbnail-process-table)))
      (when (process-live-p old-proc)
        (delete-process old-proc)))
    (let* ((thumb-path (ready-player--cached-thumbnail-path media-file))
           (temp-path (concat thumb-path ".regrab.tmp"))
           (log-buffer (my-ready-player--regrab-log-buffer))
           (proc
            (progn
              (with-current-buffer log-buffer (erase-buffer))
              (message "Regenerating thumbnail for %s at %d%%..."
                       (file-name-nondirectory media-file) percent)
              (make-process
               :name "ready-player-regrab-thumbnail"
               :buffer log-buffer
               :command (list "ffmpegthumbnailer" "-i" media-file "-s" "0"
                              "-t" (format "%d%%" percent) "-o" temp-path)
               :sentinel #'my-ready-player--regrab-sentinel))))
      (set-process-query-on-exit-flag proc nil)
      (process-put proc 'my-media-file media-file)
      (process-put proc 'my-thumb-path thumb-path)
      (process-put proc 'my-temp-path temp-path)
      (process-put proc 'my-percent percent)
      (puthash media-file proc my-ready-player-thumbnail-process-table)
      proc))

  (defun my-ready-player--regrab-sentinel (process _event)
    "Sentinel for thumbnail regeneration PROCESS."
    (when (memq (process-status process) '(exit signal))
      (let ((media-file (process-get process 'my-media-file))
            (thumb-path (process-get process 'my-thumb-path))
            (temp-path (process-get process 'my-temp-path))
            (percent (process-get process 'my-percent)))
        ;; Only act if this is still the tracked process for the file
        ;; (i.e. it wasn't superseded by a newer request).
        (when (eq (gethash media-file my-ready-player-thumbnail-process-table) process)
          (remhash media-file my-ready-player-thumbnail-process-table)
          (if (and (eq (process-exit-status process) 0)
                   (file-exists-p temp-path))
              (progn
                (rename-file temp-path thumb-path t)
                (image-flush (create-image thumb-path nil nil
                                           :max-height ready-player-thumbnail-max-pixel-height))
                (when-let* ((buf (get-file-buffer media-file))
                            (live (buffer-live-p buf)))
                  (with-current-buffer buf
                    (when (derived-mode-p 'ready-player-major-mode)
                      (setq ready-player--thumbnail thumb-path)
                      (ready-player--refresh))))
                (message "Thumbnail regenerated for %s at %d%%"
                         (file-name-nondirectory media-file) percent))
            (ignore-errors (delete-file temp-path))
            (message "Failed to regenerate thumbnail (see %s)"
                     (buffer-name (my-ready-player--regrab-log-buffer))))))))

  (defun my-ready-player--debounced-regrab (media-file percent)
    "Timer callback: actually regrab MEDIA-FILE's thumbnail at PERCENT."
    (remhash media-file my-ready-player-thumbnail-debounce-timer-table)
    (when (file-exists-p media-file)
      (my-ready-player--regrab-thumbnail-for-file media-file percent)))

  (defun my-ready-player--adjust-thumbnail-percent (delta)
    "Bump target percent by DELTA (clamped 0-95).
Debounces the actual regrab so rapid presses only trigger one
`ffmpegthumbnailer' call, at the final accumulated percent."
    (let* ((media-file (my-ready-player--current-media-file))
           (current (my-ready-player--thumbnail-percent-for media-file))
           (new-percent (max 0 (min 95 (+ current delta)))))
      (puthash media-file new-percent my-ready-player-thumbnail-percent-table)
      (when-let ((old-timer (gethash media-file my-ready-player-thumbnail-debounce-timer-table)))
        (when (timerp old-timer)
          (cancel-timer old-timer)))
      (puthash media-file
               (run-with-timer
                my-ready-player-thumbnail-debounce-delay nil
                #'my-ready-player--debounced-regrab media-file new-percent)
               my-ready-player-thumbnail-debounce-timer-table)
      (message "Thumbnail target for %s: %d%%"
               (file-name-nondirectory media-file) new-percent)))

  ;; -----------------------------------------------------------------------
  ;; Batch-generate thumbnails for all videos in a directory
  ;; -----------------------------------------------------------------------
  (require 'seq)

  (defcustom my-ready-player-thumbnail-batch-max-processes 4
    "Maximum number of concurrent `ffmpegthumbnailer' processes when
batch-generating thumbnails via `my-ready-player-batch-generate-thumbnails'."
    :type 'integer
    :group 'ready-player)

  (defvar my-ready-player--batch-queue nil
    "Remaining files to thumbnail in the current batch run.")
  (defvar my-ready-player--batch-total 0)
  (defvar my-ready-player--batch-done 0)
  (defvar my-ready-player--batch-active 0)
  (defvar my-ready-player--batch-log-buffer nil
    "Shared, reused log buffer for batch thumbnail generation.")

  (defun my-ready-player--batch-log-buffer ()
    (unless (buffer-live-p my-ready-player--batch-log-buffer)
      (setq my-ready-player--batch-log-buffer
            (generate-new-buffer "*ready-player-batch-thumbnails*")))
    my-ready-player--batch-log-buffer)

  (defun my-ready-player-batch-generate-thumbnails ()
    "Pre-generate ready-player thumbnails for every video file in the
current Dired directory, so previews don't have to generate them
lazily as you move point. If any files are marked, only those are
processed. Files that already have a cached thumbnail are skipped.
Runs up to `my-ready-player-thumbnail-batch-max-processes'
`ffmpegthumbnailer' jobs in parallel, in the background."
    (interactive)
    (unless (derived-mode-p 'dired-mode)
      (user-error "Run this from a Dired buffer"))
    (unless (executable-find "ffmpegthumbnailer")
      (user-error "ffmpegthumbnailer not found"))
    (when (> my-ready-player--batch-active 0)
      (user-error "A batch thumbnail generation is already running"))
    (let* ((marked (dired-get-marked-files nil 'marked))
           (files (or marked
                      (directory-files (dired-current-directory) t
                                       directory-files-no-dot-files-regexp)))
           (videos (seq-filter (lambda (f)
				 (and (file-regular-p f)
                                      (ready-player-is-video-p f)))
                               files))
           (todo (seq-remove
                  (lambda (f)
                    (file-exists-p (ready-player--cached-thumbnail-path f)))
                  videos)))
      (unless videos
	(user-error "No video files %s"
                    (if marked "among the marked files" "in this directory")))
      (unless todo
	(user-error "All %d video file(s) already have thumbnails"
                    (length videos)))
      (setq my-ready-player--batch-queue todo
            my-ready-player--batch-total (length todo)
            my-ready-player--batch-done 0
            my-ready-player--batch-active 0)
      (message "Generating thumbnails: 0/%d" my-ready-player--batch-total)
      (dotimes (_ (min my-ready-player-thumbnail-batch-max-processes (length todo)))
	(my-ready-player--batch-run-next))))

  (defun my-ready-player--batch-run-next ()
    "Pop the next file off the batch queue and start a thumbnailer process for it."
    (when my-ready-player--batch-queue
      (let* ((file (pop my-ready-player--batch-queue))
             (percent (my-ready-player--thumbnail-percent-for file))
             (thumb-path (ready-player--cached-thumbnail-path file))
             (temp-path (concat thumb-path ".batch.tmp"))
             (log-buffer (my-ready-player--batch-log-buffer)))
        (setq my-ready-player--batch-active (1+ my-ready-player--batch-active))
        (make-directory (file-name-directory thumb-path) t)
        (let ((proc (make-process
                     :name "ready-player-batch-thumbnail"
                     :buffer log-buffer
                     :command (list "ffmpegthumbnailer" "-i" file "-s" "0"
                                    "-t" (format "%d%%" percent) "-o" temp-path)
                     :sentinel #'my-ready-player--batch-sentinel)))
          (set-process-query-on-exit-flag proc nil)
          (process-put proc 'my-file file)
          (process-put proc 'my-thumb-path thumb-path)
          (process-put proc 'my-temp-path temp-path)))))

  (defun my-ready-player--batch-sentinel (process _event)
    "Sentinel for one batch-thumbnail PROCESS: finalize its file, then
either start the next queued file or, if the queue and all workers
are done, report completion."
    (when (memq (process-status process) '(exit signal))
      (let ((thumb-path (process-get process 'my-thumb-path))
            (temp-path (process-get process 'my-temp-path)))
        (if (and (eq (process-exit-status process) 0) (file-exists-p temp-path))
            (rename-file temp-path thumb-path t)
          (ignore-errors (delete-file temp-path))))
      (setq my-ready-player--batch-done (1+ my-ready-player--batch-done))
      (setq my-ready-player--batch-active (1- my-ready-player--batch-active))
      (message "Generating thumbnails: %d/%d"
               my-ready-player--batch-done my-ready-player--batch-total)
      (if my-ready-player--batch-queue
          (my-ready-player--batch-run-next)
        (when (= my-ready-player--batch-active 0)
          (message "Thumbnail generation complete: %d/%d done"
                   my-ready-player--batch-done my-ready-player--batch-total))))))


(provide 'init-media)
