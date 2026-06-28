;;; init-music.el --- EMMS music player configuration -*- lexical-binding: t -*-

;; -----------------------------------------------------------------------
;; EMMS
;; -----------------------------------------------------------------------
(use-package emms
  :commands
  (emms emms-play-directory emms-smart-browse emms-play-file
        emms-pause emms-stop emms-previous emms-next emms-shuffle
        emms-seek-forward emms-seek-backward
        emms-volume-raise emms-volume-lower)
  :custom
  (emms-directory (expand-file-name "emms" my-emacs-cache-dir))
  :config
  (require 'emms-setup)
  (emms-all)

  ;; Define a custom volume function for PipeWire (using wpctl).
  (defun my-emms-volume-pipewire (amount)
    "Change volume using wpctl (WirePlumber). AMOUNT is the percentage to change."
    (let ((msg (if (> amount 0)
                   (format "%d%%+" amount)
                 (format "%d%%-" (abs amount)))))
      (start-process "emms-volume-pipewire" nil
                     "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" msg)))
  (setq emms-volume-change-function 'my-emms-volume-pipewire)

  (require 'emms-player-mpv)
  (setq emms-player-list '(emms-player-mpv))

  ;; Enable metadata (ID3 tags).
  (require 'emms-info-native)
  (setq emms-info-functions '(emms-info-native))

  ;; General settings.
  (setq emms-source-file-default-directory "~/Music"
        emms-repeat-playlist t            ; Loop playlist by default
        emms-playlist-buffer-name "*Music*"
        emms-show-format " %i %t ")       ; Display format in playlist

  ;; Auto-load the music library whenever EMMS is opened.
  (defun my-emms-load-music-library ()
    "Clear the current playlist and reload all tracks from
`emms-source-file-default-directory'."
    (interactive)
    (emms-playlist-current-clear)
    (emms-add-directory-tree emms-source-file-default-directory))

  (advice-add 'emms :before #'my-emms-load-music-library)

  ;; Mode line & persistence.
  (emms-mode-line-mode 1)
  (emms-playing-time-mode 1)
  (emms-history-load)

  :bind
  (:map emms-playlist-mode-map
        ("q"     . emms-stop)
        ("<SPC>" . emms-pause)
        ("."     . emms-playlist-mode-center-current)
        ("j"     . next-line)
        ("k"     . previous-line)
        ("h"     . emms-previous)
        ("l"     . emms-next)
        ("r"     . emms-random)
        ("R"     . emms-shuffle)
        (">"     . emms-seek-forward)
        ("<"     . emms-seek-backward)))

;; -----------------------------------------------------------------------
;; Transient Music Controller
;; -----------------------------------------------------------------------
(transient-define-prefix my-transient-music ()
  "Music Controller (EMMS)."
  [["Playback"
    ("<SPC>" "Play/Pause"      emms-pause)
    ("Q"     "Stop"            emms-stop)
    ("j"     "Next"            emms-next)
    ("k"     "Prev"            emms-previous)
    ("r"     "Random/Shuffle"  emms-random)]

   ["Seek & Volume"
    (">" "Seek +10s" emms-seek-forward  :transient t)
    ("<" "Seek -10s" emms-seek-backward :transient t)
    ("=" "Vol Up"    emms-volume-raise  :transient t)
    ("-" "Vol Down"  emms-volume-lower  :transient t)]

   ["Open"
    ("p" "Show Playlist" emms)
    ("d" "Directory"     emms-play-directory)
    ("f" "File"          emms-play-file)
    ("b" "Browser"       emms-smart-browse)]

   ["Actions"
    ("q" "Quit Menu" transient-quit-all)]])

(provide 'init-music)
;;; init-music.el ends here
