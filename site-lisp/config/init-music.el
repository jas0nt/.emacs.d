(use-package emms
  :commands (emms emms-play-directory emms-smart-browse emms-play-file
		  emms-pause emms-stop emms-previous emms-next emms-shuffle
		  emms-seek-forward emms-seek-backward
		  emms-volume-raise emms-volume-lower)
  :custom
  (emms-directory (expand-file-name "emms" my-emacs-cache-dir))
  :config
  (require 'emms-setup)
  (emms-all) 

  ;; Define a custom volume function for PipeWire (using wpctl)
  (defun my/emms-volume-pipewire (amount)
    "Change volume using wpctl (WirePlumber). AMOUNT is the percentage to change."
    (let ((msg (if (> amount 0)
                   (format "%d%%+" amount)
		 (format "%d%%-" (abs amount)))))
      (start-process "emms-volume-pipewire" nil 
                     "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" msg)))

  (setq emms-volume-change-function 'my/emms-volume-pipewire)
  
  (require 'emms-player-mpv)
  (setq emms-player-list '(emms-player-mpv))
  
  ;; Enable Metadata (ID3 Tags)
  (require 'emms-info-native)
  (setq emms-info-functions '(emms-info-native))

  ;; General Settings
  (setq emms-source-file-default-directory "~/Music"
        emms-repeat-playlist t         ; Loop playlist by default
        emms-playlist-buffer-name "*Music*"
        emms-show-format " %i %t ")    ; Display format in playlist

  ;; Mode Line & Persistence
  (emms-mode-line-mode 1)
  (emms-playing-time-mode 1)
  (emms-history-load))

;;;; --- Evil Keybindings for Playlist Buffer ---

(general-define-key
 :states 'normal
 :keymaps 'emms-playlist-mode-map
 "q" 'kill-this-buffer
 "R" '(emms-shuffle :which-key "Shuffle")
 "<SPC>" '(emms-mark-track :which-key "Mark Track")
 "D" '(emms-playlist-mode-kill-track :which-key "Remove track")
 
 ;; Sorting/Filtering
 "s a" '(emms-playlist-sort-by-natural-order :which-key "Sort default")
 "m A" '(emms-playlist-limit-to-all :which-key "Show All")
 "m a" '(emms-playlist-limit-to-info-artist :which-key "Filter Artist")
 "m b" '(emms-playlist-limit-to-info-album :which-key "Filter Album"))

;;;; --- Transient Music Controller ---

(transient-define-prefix my-transient-music ()
  "Music Controller (EMMS)"
  [
   ["Playback"
    ("x" "Play/Pause" emms-pause)
    ("s" "Stop" emms-stop)
    ("n" "Next" emms-next)
    ("p" "Prev" emms-previous)
    ("r" "Random/Shuffle" emms-shuffle)
    ]
   
   ["Seek & Volume"
    ("l" "Seek +10s" emms-seek-forward :transient t)
    ("h" "Seek -10s" emms-seek-backward :transient t)
    ("=" "Vol Up" emms-volume-raise :transient t)
    ("-" "Vol Down" emms-volume-lower :transient t)
    ]

   ["Open"
    ("e" "Show Playlist" emms)
    ("d" "Directory" emms-play-directory)
    ("f" "File" emms-play-file)
    ("b" "Browser" emms-smart-browse)
    ]

   ["Actions"
    ("q" "Quit Menu" transient-quit-all)
    ]
   ])


(provide 'init-music)
