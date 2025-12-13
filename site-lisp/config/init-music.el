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
 "R" '(emms-shuffle :which-key "shuffle")
 "<SPC>" '(emms-mark-track :which-key "Mark Track")
 "mA" '(emms-playlist-limit-to-all :which-key "mode All")
 "ma" '(emms-playlist-limit-to-info-artist :which-key "mode artist")
 "mb" '(emms-playlist-limit-to-info-album :which-key "mode album"))


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
