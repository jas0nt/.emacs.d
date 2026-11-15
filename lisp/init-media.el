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
;; HDR-aware frame extraction
;; ---------------------------------------------------------------------------
;;
;; HDR sources (PQ / HLG) decoded without a colour conversion come out
;; washed out and desaturated: the 10-bit PQ signal is written straight to
;; an SDR JPEG.  ffmpegthumbnailer cannot tonemap, so HDR files go through
;; ffmpeg + zscale/tonemap instead.  With `-skip_frame nokey' plus scaling
;; before the colour pipeline that costs ~440ms on a 4K60 source, versus
;; ~380ms for ffmpegthumbnailer -- and it is the difference between a grey
;; smear and the actual frame.

(defcustom my-media-hdr-color-transfers '("smpte2084" "arib-std-b67")
  "ffprobe `color_transfer' values that mean HDR (PQ / HLG)."
  :type '(repeat string))

(defvar my-media--probe-cache (make-hash-table :test 'equal)
  "FILE -> (HDR . DURATION).  See `my-media-probe'.")

(defun my-media-probe (file)
  "Return (HDR . DURATION) for FILE, cached for the whole session.
HDR is non-nil for PQ/HLG sources, DURATION is in seconds (nil when
unknown).  One ffprobe run costs 20-190ms, hence the cache."
  (let ((cached (gethash file my-media--probe-cache 'miss)))
    (if (not (eq cached 'miss))
        cached
      (puthash file
               (condition-case nil
                   (let* ((json (with-temp-buffer
                                  (unless (zerop (call-process
                                                  "ffprobe" nil t nil
                                                  "-v" "error" "-select_streams" "v:0"
                                                  "-show_entries"
                                                  "format=duration:stream=color_transfer"
                                                  "-of" "json" file))
                                    (signal 'error nil))
                                  ;; `call-process' leaves point at eob.
                                  (goto-char (point-min))
                                  (json-parse-buffer :object-type 'alist)))
                          (stream (aref (alist-get 'streams json) 0))
                          (transfer (alist-get 'color_transfer stream))
                          (duration (alist-get 'duration (alist-get 'format json))))
                     (cons (and transfer
                                (member transfer my-media-hdr-color-transfers)
                                t)
                           (and duration (string-to-number duration))))
                 (error (cons nil nil)))
               my-media--probe-cache))))

(defun my-media-tonemap-filter (width)
  "Return an ffmpeg -vf chain scaling to WIDTH and tonemapping HDR to SDR.
Scaling first keeps the colour pipeline cheap on 4K sources."
  (concat (format "scale=%d:-2," width)
          "zscale=t=linear:npl=100,format=gbrpf32le,"
          "zscale=p=bt709,tonemap=hable:desat=0,"
          "zscale=t=bt709:m=bt709:r=tv,format=yuv420p"))

(defun my-media-frame-argv (file percent out-path)
  "Return the argv that writes a thumbnail of FILE at PERCENT into OUT-PATH."
  (if (car (my-media-probe file))
      (let* ((duration (or (cdr (my-media-probe file)) 600))
             (seek (max 0 (* duration (/ percent 100.0)))))
        (list "ffmpeg" "-v" "error" "-skip_frame" "nokey"
              "-ss" (format "%.3f" seek)
              "-i" file "-frames:v" "1"
              "-vf" (my-media-tonemap-filter my-ready-player-thumbnail-size)
              "-q:v" "3"
              ;; The job writes to a ".tmp" temp file, so the muxer cannot be
              ;; guessed from the extension.
              "-f" "mjpeg" "-y" out-path))
    (list "ffmpegthumbnailer" "-i" file
          "-s" (number-to-string my-ready-player-thumbnail-size)
          "-c" my-ready-player-thumbnail-format
          "-t" (format "%d%%" percent)
          "-o" out-path)))

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
  "Start a thumbnail job for FILE at PERCENT and return the process.
Uses `my-media-frame-argv', so HDR sources get tonemapped and everything
else keeps ffmpegthumbnailer.  Output goes to a unique temp file next to
THUMB-PATH so concurrent jobs never write to the same file."
  (let* ((temp-path (concat (make-temp-name (concat thumb-path ".")) ".tmp"))
         (proc (make-process
                :name "ready-player-thumbnail"
                :buffer (my-ready-player--log-buffer)
                :command (my-media-frame-argv file percent temp-path)
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

;; ---------------------------------------------------------------------------
;; Thumbnails: one bounded, HDR-correct JPEG per file, shared with media-thumbnail
;; ---------------------------------------------------------------------------
;;
;; ready-player asks ffmpegthumbnailer for `-s 0' (original size) and names
;; the result ".png", so every thumbnail was a full-resolution PNG (~800KB,
;; 1920x1080, ~8MB once decoded into Emacs) and `media-thumbnail' forced
;; image type `png' by extension even for the JPEGs we wrote ourselves.
;; Everything now lands in the same <md5>.jpg: bounded to
;; `my-ready-player-thumbnail-size' pixels and tonemapped when HDR.

(defun my-ready-player--cached-thumbnail-path (media-file)
  "Return the cache path for MEDIA-FILE's thumbnail, with a .jpg suffix.
The suffix is what makes ffmpeg write JPEG instead of the original-size
PNG, and what makes `media-thumbnail' decode it as jpeg."
  (ready-player--cached-item-path-for media-file ".jpg"))

(advice-add 'ready-player--cached-thumbnail-path :override
            #'my-ready-player--cached-thumbnail-path)

(defun my-ready-player-load-thumbnail (media-file &optional on-loaded _silent)
  "Replacement for ready-player's ffmpegthumbnailer loader.
Runs through `my-media-frame-argv', so the result is bounded in size and
colour-correct for HDR sources."
  (if (not (executable-find "ffmpegthumbnailer"))
      (when on-loaded (funcall on-loaded nil))
    (let ((thumb (ready-player--cached-thumbnail-path media-file)))
      (my-ready-player--spawn-thumbnailer
       media-file (my-ready-player--thumbnail-percent-for media-file) thumb
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (when on-loaded
             (funcall on-loaded (and (my-ready-player--finalize-thumbnail proc)
                                     thumb)))))))))

(with-eval-after-load 'ready-player
  (advice-add 'ready-player--load-file-thumbnail-via-ffmpegthumbnailer
              :override #'my-ready-player-load-thumbnail))

;; `media-thumbnail' builds its own ffmpeg command line; give it the same
;; HDR treatment.  Its cache path already comes from the advice above.
(with-eval-after-load 'media-thumbnail
  (define-advice media-thumbnail-ffmpeg-frame-cmd
      (:around (orig file cache-path &rest args) my-hdr)
    "Tonemap HDR sources instead of writing a washed-out frame."
    (if (not (car (my-media-probe file)))
        (apply orig file cache-path args)
      (let ((size (or (plist-get args :size) media-thumbnail-size)))
        (mapconcat
         #'identity
         (list media-thumbnail-ffmpeg-executable
               "-nostdin" "-y" "-loglevel" "error"
               "-skip_frame" "nokey"
               "-ss" (shell-quote-argument
                      (or (plist-get args :seek-time)
                          (car media-thumbnail-ffmpeg-seek-times)
                          "5"))
               "-i" (shell-quote-argument file)
               "-frames:v" "1" "-q:v" "2"
               "-vf" (shell-quote-argument
                      (my-media-tonemap-filter
                       (if (or (null size) (zerop size))
                           my-ready-player-thumbnail-size
                         size)))
               (shell-quote-argument cache-path))
         " ")))))

(provide 'init-media)
;;; init-media.el ends here
