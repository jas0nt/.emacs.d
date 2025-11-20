(use-package emms
  :custom
  (emms-directory (expand-file-name "emms" my-emacs-cache-dir))
  :config
  (setq emms-source-file-default-directory "~/Music"
        emms-player-list '(emms-player-mpv)
        emms-repeat-playlist nil
        emms-playlist-buffer-name "*EMMS*")

  (defun my/emms-init ()
    (require 'emms-setup)
    (emms-standard)
    (emms-default-players)
    (emms-history-load))

  (my/emms-init))

(general-define-key
 :states 'normal
 :keymaps 'emms-playlist-mode-map
 "X" '(emms-stop :which-key "Music Quit")
 "x" '(emms-pause :which-key "Music Pause")
 "R" '(emms-shuffle :which-key "shuffle")
 "r" '(emms-random :which-key "random")
 "m" '(emms-mark-track :which-key "Mark Track")
 "d" '(emms-mark-kill-marked-tracks :which-key "Kill Track")
 "sm" '(emms-playlist-limit-to-info-album :which-key "mode album")
 "sa" '(emms-playlist-limit-to-info-artist :which-key "mode artist")
 )


(transient-define-prefix my-transient-music ()
  [
   ["Music"
    ("p" "Music" emms)
    ("X" "Quit" emms-stop)
    ("x" "play/pause" emms-pause)
    ("r" "random" emms-random)
    ("j" "next" emms-next)
    ("k" "prev" emms-previous)
    ]
   
   ["actions"
    ("q" "quit" transient-quit-all)
    ]
   ])


(provide 'init-music)
