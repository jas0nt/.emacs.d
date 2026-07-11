(use-package transient)
(use-package general)

(use-package which-key
  :config
  (setq which-key-idle-delay 0.5)
  (setq which-key-idle-secondary-delay 0.05)
  (which-key-mode)
  (which-key-enable-god-mode-support))


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
    ("W" "goto-symbol" avy-goto-symbol-1)
    ]

   ["goto-line"
    ("l" "goto-line" avy-goto-line)
    ]

   ["edit"
    ("k" "kill-region" avy-kill-region)
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
    ("f" "fd" consult-fd)
    ("z" "fzf" fzf)
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


(winner-mode 1)

(defun my-split-window-vertical ()
  "Split window right and move point to the new window."
  (interactive)
  (split-window-right)
  (windmove-right))

(defun my-split-window-horizontal ()
  "Split window below and move point to the new window."
  (interactive)
  (split-window-below)
  (windmove-down))

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
    ("/" "vertical" my-split-window-vertical)
    ("?" "horizontal" my-split-window-horizontal)
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
    (";" "switch" consult-buffer)
    ("u" "undo layout" winner-undo :transient t)
    ("U" "redo layout" winner-redo :transient t)
    ("q" "quit" transient-quit-all)
    ]
   ])


(defun my-prev-buffer ()
  (interactive)
  (switch-to-buffer (other-buffer (current-buffer) 1)))

(general-define-key
 "<f5>" 'revert-buffer
 "M-<up>" 'switch-to-prev-buffer
 "M-<down>" 'switch-to-next-buffer
 "M-<left>" '(lambda () (interactive) (other-window -1))
 "M-<right>" 'other-window
 "M-o" 'ace-window
 "M-y" 'consult-yank-pop

 "C-," 'my-prev-buffer
 "C-;" 'consult-buffer
 "C-'" 'avy-goto-char-2
 "C-s" 'consult-line
 "C-=" 'er/expand-region
 "C-x b" 'consult-buffer

 "C-c C-/" 'evilnc-comment-or-uncomment-lines
 "C-c C-k" 'kill-current-buffer
 "C-c T" 'ghostel
 "C-c f" 'my-transient-file
 "C-c j" 'my-transient-jump
 "C-c s" 'my-transient-search
 "C-c w" 'my-transient-window
 "C-c p" 'my-transient-music)


(provide 'init-keys)
