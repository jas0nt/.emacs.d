;;; init-media.el --- Image / media viewing setup -*- lexical-binding: t; -*-

;;; Commentary:
;; Targets Emacs 30+.
;; - image-mode keybindings
;; - ready-player: debounced thumbnail regrab, parallel batch generation,
;;   persistent thumbnail cache

;;; Code:

(require 'cl-lib)

(defvar my-emacs-cache-dir)

;; Provided by ready-player / dired.
(declare-function ready-player-is-video-p "ready-player")
(declare-function ready-player--cached-thumbnail-path "ready-player")
(declare-function ready-player--refresh "ready-player")
(declare-function dired-get-filename "dired")
(declare-function dired-get-marked-files "dired")
(declare-function dired-current-directory "dired")
(defvar ready-player--thumbnail)

;; ---------------------------------------------------------------------------
;; image-mode
;; ---------------------------------------------------------------------------

(use-package image-mode
  :ensure nil
  :hook (image-mode . auto-revert-mode)
  :bind (:map image-mode-map
              ("=" . image-increase-size)
              ("-" . image-decrease-size)
              ("0" . image-transform-reset-to-initial)
              ("j" . scroll-up-command)
              ("k" . scroll-down-command)
              ("n" . image-next-file)
              ("p" . image-previous-file)
              ("r" . image-rotate)
              ("l" . (lambda () (interactive) (image-rotate -90)))
              ("g" . revert-buffer)
              ("q" . quit-window))
  :config
  (setq auto-revert-verbose nil
        auto-revert-avoid-polling t))

;; ---------------------------------------------------------------------------
;; ready-player: options
;; ---------------------------------------------------------------------------

(defgroup my-ready-player nil
  "Personal ready-player thumbnail tweaks."
  :group 'ready-player)

(defcustom my-ready-player-thumbnail-size 1000
  "Longest side (pixels) of thumbnails produced by ffmpegthumbnailer.
Keep this in line with `ready-player-thumbnail-max-pixel-height'."
  :type 'integer)

(defcustom my-ready-player-thumbnail-format "jpeg"
  "Output format for ffmpegthumbnailer's `-c' option.
If thumbnails fail to display, switch to \"png\"."
  :type '(choice (const "jpeg") (const "png")))

(defcustom my-ready-player-thumbnail-debounce-delay 0.3
  "Seconds to wait after the last percent adjustment before regenerating."
  :type 'number)

(defcustom my-ready-player-thumbnail-batch-max-processes
  (max 2 (min 8 (num-processors)))
  "Maximum concurrent `ffmpegthumbnailer' processes for batch generation."
  :type 'integer)

(defcustom my-ready-player-persistent-cache-dir
  (expand-file-name "ready-player/" my-emacs-cache-dir)
  "Persistent replacement for `ready-player's default /tmp cache dir."
  :type 'directory)

;; ---------------------------------------------------------------------------
;; ready-player: state and helpers
;; ---------------------------------------------------------------------------

(defvar my-ready-player-thumbnail-percent-table (make-hash-table :test 'equal)
  "Map of media-file -> target thumbnail seek percent (integer 0-95).")

(defvar my-ready-player--regrab-process-table (make-hash-table :test 'equal)
  "Map of media-file -> running regrab process.")

(defvar my-ready-player--debounce-timer-table (make-hash-table :test 'equal)
  "Map of media-file -> pending debounce timer.")

(defvar my-ready-player--log-buffer nil
  "Shared log buffer for thumbnailer processes.")

(defvar my-ready-player--batch-queue nil)
(defvar my-ready-player--batch-procs nil)
(defvar my-ready-player--batch-total 0)
(defvar my-ready-player--batch-done 0)
(defvar my-ready-player--batch-active 0)
(defvar my-ready-player--batch-gen 0
  "Incremented on every batch start/cancel; sentinels of stale jobs are ignored.")

(defun my-ready-player--log-buffer ()
  "Return the shared log buffer, creating it if needed."
  (unless (buffer-live-p my-ready-player--log-buffer)
    (setq my-ready-player--log-buffer
          (generate-new-buffer " *ready-player-thumbnails*" t))
    (with-current-buffer my-ready-player--log-buffer
      (buffer-disable-undo)))
  my-ready-player--log-buffer)

(defun my-ready-player--clear-log ()
  "Erase the log buffer unless thumbnailer jobs are running."
  (when (and (zerop my-ready-player--batch-active)
             (zerop (hash-table-count my-ready-player--regrab-process-table)))
    (with-current-buffer (my-ready-player--log-buffer)
      (erase-buffer))))

(defun my-ready-player--thumbnail-percent-for (media-file)
  "Return the target seek percent for MEDIA-FILE, defaulting to 10."
  (or (gethash media-file my-ready-player-thumbnail-percent-table) 10))

(defun my-ready-player--current-media-file ()
  "Return the media file from a `ready-player' buffer or the Dired line at point."
  (cond
   ((derived-mode-p 'ready-player-major-mode) (buffer-file-name))
   ((derived-mode-p 'dired-mode)
    (or (dired-get-filename nil t) (user-error "No file at point")))
   (t (user-error "Not in ready-player or dired"))))

(defun my-ready-player--spawn-thumbnailer (file percent thumb-path sentinel)
  "Start ffmpegthumbnailer for FILE at PERCENT and return the process.
Output goes to a unique temp file next to THUMB-PATH so concurrent jobs
never write to the same file."
  (let* ((temp-path (concat (make-temp-name (concat thumb-path ".")) ".tmp"))
         (proc (make-process
                :name "ready-player-thumbnail"
                :buffer (my-ready-player--log-buffer)
                :command (list "ffmpegthumbnailer" "-i" file
                               "-s" (number-to-string my-ready-player-thumbnail-size)
                               "-c" my-ready-player-thumbnail-format
                               "-t" (format "%d%%" percent)
                               "-o" temp-path)
                :connection-type 'pipe
                :noquery t
                :sentinel sentinel)))
    (process-put proc 'my-media-file file)
    (process-put proc 'my-thumb-path thumb-path)
    (process-put proc 'my-temp-path temp-path)
    (process-put proc 'my-percent percent)
    proc))

(defun my-ready-player--finalize-thumbnail (process)
  "Install PROCESS's output on success; always remove its temp file.
Return non-nil on success."
  (let ((temp (process-get process 'my-temp-path))
        (thumb (process-get process 'my-thumb-path)))
    (if (and (eq (process-exit-status process) 0) (file-exists-p temp))
        (progn (rename-file temp thumb t) t)
      (ignore-errors (delete-file temp))
      nil)))

;; ---------------------------------------------------------------------------
;; ready-player: single-file regrab (debounced)
;; ---------------------------------------------------------------------------

(defun my-ready-player--regrab-sentinel (process _event)
  "Sentinel for thumbnail regeneration PROCESS."
  (when (memq (process-status process) '(exit signal))
    (let* ((media-file (process-get process 'my-media-file))
           (thumb-path (process-get process 'my-thumb-path))
           (percent (process-get process 'my-percent))
           (current (eq (gethash media-file my-ready-player--regrab-process-table)
                        process)))
      (if (not current)
          ;; Superseded by a newer job: only clean up our temp file.
          (ignore-errors (delete-file (process-get process 'my-temp-path)))
        (remhash media-file my-ready-player--regrab-process-table)
        (if (my-ready-player--finalize-thumbnail process)
            (progn
              ;; Filter by filename so every package's cached pixel data
              ;; for this file is invalidated.
              (clear-image-cache thumb-path)
              (when-let* ((buf (get-file-buffer media-file))
                          ((buffer-live-p buf)))
                (with-current-buffer buf
                  (when (derived-mode-p 'ready-player-major-mode)
                    (setq ready-player--thumbnail thumb-path)
                    (ready-player--refresh))))
              (message "Thumbnail regenerated for %s at %d%%"
                       (file-name-nondirectory media-file) percent))
          (message "Failed to regenerate thumbnail (see %s)"
                   (buffer-name (my-ready-player--log-buffer))))))))

(defun my-ready-player--regrab-thumbnail-for-file (media-file percent)
  "Regenerate MEDIA-FILE's cached thumbnail at PERCENT (async).
Cancels any in-flight regrab for the same file first."
  (unless (executable-find "ffmpegthumbnailer")
    (user-error "ffmpegthumbnailer not found"))
  (when-let* ((old (gethash media-file my-ready-player--regrab-process-table))
              ((process-live-p old)))
    (delete-process old))
  (my-ready-player--clear-log)
  (message "Regenerating thumbnail for %s at %d%%..."
           (file-name-nondirectory media-file) percent)
  (puthash media-file
           (my-ready-player--spawn-thumbnailer
            media-file percent
            (ready-player--cached-thumbnail-path media-file)
            #'my-ready-player--regrab-sentinel)
           my-ready-player--regrab-process-table))

(defun my-ready-player--debounced-regrab (media-file percent)
  "Timer callback: regrab MEDIA-FILE's thumbnail at PERCENT."
  (remhash media-file my-ready-player--debounce-timer-table)
  (when (file-exists-p media-file)
    (my-ready-player--regrab-thumbnail-for-file media-file percent)))

(defun my-ready-player--adjust-thumbnail-percent (delta)
  "Bump the target percent by DELTA (clamped 0-95) and schedule a regrab.
Rapid calls are coalesced into one ffmpegthumbnailer run."
  (let* ((media-file (my-ready-player--current-media-file))
         (new-percent (max 0 (min 95 (+ (my-ready-player--thumbnail-percent-for media-file)
                                        delta)))))
    (puthash media-file new-percent my-ready-player-thumbnail-percent-table)
    (when-let* ((old-timer (gethash media-file my-ready-player--debounce-timer-table))
                ((timerp old-timer)))
      (cancel-timer old-timer))
    (puthash media-file
             (run-with-timer my-ready-player-thumbnail-debounce-delay nil
                             #'my-ready-player--debounced-regrab
                             media-file new-percent)
             my-ready-player--debounce-timer-table)
    (message "Thumbnail target for %s: %d%%"
             (file-name-nondirectory media-file) new-percent)))

;; ---------------------------------------------------------------------------
;; ready-player: batch generation
;; ---------------------------------------------------------------------------

(defun my-ready-player--batch-pump ()
  "Start workers until the concurrency limit is hit or the queue is empty.
Report completion once nothing is queued or running."
  (while (and my-ready-player--batch-queue
              (< my-ready-player--batch-active
                 my-ready-player-thumbnail-batch-max-processes))
    (let* ((file (pop my-ready-player--batch-queue))
           (thumb (ready-player--cached-thumbnail-path file)))
      (condition-case err
          (let ((proc (my-ready-player--spawn-thumbnailer
                       file (my-ready-player--thumbnail-percent-for file) thumb
                       #'my-ready-player--batch-sentinel)))
            (process-put proc 'my-batch-gen my-ready-player--batch-gen)
            (push proc my-ready-player--batch-procs)
            (cl-incf my-ready-player--batch-active))
        (error
         (cl-incf my-ready-player--batch-done)
         (message "Thumbnail spawn failed for %s: %s"
                  (file-name-nondirectory file) (error-message-string err))))))
  (when (and (null my-ready-player--batch-queue)
             (zerop my-ready-player--batch-active))
    (message "Thumbnail generation complete: %d/%d done"
             my-ready-player--batch-done my-ready-player--batch-total)))

(defun my-ready-player--batch-sentinel (process _event)
  "Sentinel for one batch PROCESS: finalize its file, then pump the queue."
  (when (memq (process-status process) '(exit signal))
    (my-ready-player--finalize-thumbnail process)
    (when (eq (process-get process 'my-batch-gen) my-ready-player--batch-gen)
      (setq my-ready-player--batch-procs
            (delq process my-ready-player--batch-procs))
      (cl-incf my-ready-player--batch-done)
      (cl-decf my-ready-player--batch-active)
      (message "Generating thumbnails: %d/%d"
               my-ready-player--batch-done my-ready-player--batch-total)
      (my-ready-player--batch-pump))))

(defun my-ready-player-batch-generate-thumbnails ()
  "Pre-generate ready-player thumbnails for videos in the Dired directory.
If any files are marked, only those are processed.  Files that already
have a cached thumbnail are skipped.  Runs up to
`my-ready-player-thumbnail-batch-max-processes' jobs in the background."
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
    (my-ready-player--clear-log)
    (cl-incf my-ready-player--batch-gen)
    (setq my-ready-player--batch-queue todo
          my-ready-player--batch-procs nil
          my-ready-player--batch-total (length todo)
          my-ready-player--batch-done 0
          my-ready-player--batch-active 0)
    (message "Generating thumbnails: 0/%d" my-ready-player--batch-total)
    (my-ready-player--batch-pump)))

(defun my-ready-player-batch-cancel-thumbnails ()
  "Cancel the running batch: drop the queue and kill running jobs."
  (interactive)
  (cl-incf my-ready-player--batch-gen)
  (setq my-ready-player--batch-queue nil)
  (dolist (proc my-ready-player--batch-procs)
    (when (process-live-p proc)
      (delete-process proc))
    (ignore-errors (delete-file (process-get proc 'my-temp-path))))
  (setq my-ready-player--batch-procs nil
        my-ready-player--batch-active 0)
  (message "Thumbnail batch cancelled (%d/%d done)"
           my-ready-player--batch-done my-ready-player--batch-total))

;; ---------------------------------------------------------------------------
;; ready-player: persistent cache and package setup
;; ---------------------------------------------------------------------------

(defun my-ready-player--cached-item-path-for (media-file suffix)
  "Like `ready-player--cached-item-path-for' but under a persistent directory.
The directory is created once in the `ready-player' :config block."
  (concat (file-name-as-directory my-ready-player-persistent-cache-dir)
          (md5 media-file) suffix))

(use-package ready-player
  :custom
  (ready-player-autoplay nil)
  (ready-player-ask-for-project-sustainability nil)
  (ready-player-thumbnail-max-pixel-height 1000)
  :config
  (make-directory my-ready-player-persistent-cache-dir t)
  (advice-add 'ready-player--cached-item-path-for :override
              #'my-ready-player--cached-item-path-for)
  (ready-player-mode 1))

(provide 'init-media)
;;; init-media.el ends here
