(require 'transient)
(use-package general)

(use-package which-key
  :config
  (setq which-key-idle-delay 0.5)
  (which-key-mode)
  (which-key-enable-god-mode-support))

(general-define-key
 "<f5>" 'revert-buffer
 "C-s" 'consult-line
 "M-y" 'yank-pop
 "C-x C-b" 'bufler
 "C-x C-d" 'dirvish)

(transient-define-prefix my-transient-file ()
  "transient-file"
  [
   ["find-file"
    ("f" "project file" consult-projectile-find-file)
    ("F" "project file" consult-projectile-find-file-other-window)
    ("d" "project dir" consult-projectile-find-dir)
    ("D" "dired" dired)
    ("p" "project" consult-projectile-switch-project)
    ("r" "recentf" consult-recent-file)
    ("b" "bookmark" bookmark-jump)
    ("a" "find-file-at-point" find-file-at-point)
    ]
   ["actions"
    ("s" "save-buffer" save-buffer)
    ("S" "save-some-buffers" save-some-buffers)
    ("q" "quit" transient-quit-all)
    ]
   ]
  )

(transient-define-prefix my-transient-jump ()
  [
   ["goto-char"
    ("j" "goto-char-timer" avy-goto-char-timer)
    ("1" "goto-char" avy-goto-char)
    ("2" "goto-char-2" avy-goto-char-2)
    ]

   ["goto-word"
    ("w" "goto-word" avy-goto-word-1)
    ]
 
   ["goto-line"
    ("l" "goto-line" avy-goto-line)
    ]

   ["actions"
    ("q" "quit" transient-quit-all)
    ]
   ])

(transient-define-prefix my-transient-search ()
  [
   ["content"
    ("i" "imenu" consult-imenu)
    ("r" "rg" consult-ripgrep)
    ("R" "rg+" deadgrep)
    ("m" "multi-buffer" consult-line-multi)
    ]
   
   ["file"
    ("b" "bookmark" consult-bookmark)
    ("L" "locate" consult-locate)
    ]

   ["lookup"
    ("g" "google" google-this)
    ("d" "dict" bing-dict-brief)
    ("D" "fanyi" fanyi-dwim2)
    ("l" "browse-url" browse-url)
    ]

   ["actions"
    ("q" "quit" transient-quit-all)
    ]
   ])

(transient-define-prefix my-transient-window ()
  [
   ["nav"
    ("h" "←" windmove-left :transient t)
    ("j" "↓" windmove-down :transient t)
    ("k" "↑" windmove-up :transient t)
    ("l" "→" windmove-right :transient t)
    ("g" "goto" ace-window :transient t)
    ]

   ["swap"
    ("H" "⮌" windmove-swap-states-left :transient t)
    ("J" "⮏" windmove-swap-states-down :transient t)
    ("K" "⮍" windmove-swap-states-up :transient t)
    ("L" "⮎" windmove-swap-states-right :transient t)
    ("s" "swap" ace-swap-window :transient t)
    ]

   ["split"
    ("/" "vertical" (lambda ()
            (interactive)
            (split-window-right)
            (windmove-right)))
    ("?" "horizontal" (lambda ()
              (interactive)
              (split-window-below)
              (windmove-down)))
    ]

   ["resize"
    ("0" "⊞ balance" balance-windows :transient t)
    ("=" "inc H" enlarge-window :transient t)
    ("-" "dec H" shrink-window :transient t)
    ("." "inc W" enlarge-window-horizontally :transient t)
    ("," "dec W" shrink-window-horizontally :transient t)
    ]

   ["actions"
    ("d" "del" delete-window :transient t)
    ("D" "del other" ace-delete-window)
    ("m" "maximum" delete-other-windows)
    (";" "switch" switch-to-buffer)
    ("q" "quit" transient-quit-all)
    ]
   ])


(provide 'init-keys)
