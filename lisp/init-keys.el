(use-package transient
  :custom
  (transient-show-menu -0.4))

(use-package general)

(use-package which-key
  :custom
  (which-key-idle-delay 0.5)
  (which-key-idle-secondary-delay 0.05)
  :config
  (which-key-mode))


(transient-define-prefix cxc/transient-file ()
  "transient-file"
  [
   ["find-file"
    ("f" "project file" consult-projectile-find-file)
    ("F" "project file" consult-projectile-find-file-other-window)
    ("d" "project dir" consult-projectile-find-dir)
    ("p" "project" consult-projectile-switch-project)
    ("r" "recentf" consult-recent-file)
    ("b" "bookmark" bookmark-jump)
    ("a" "find-file-at-point" find-file-at-point)
    ("c" "clipboard" cxc/find-file-in-clipboard)
    ]
   ["actions"
    ("S" "save-some-buffers" save-some-buffers)
    ("q" "quit" transient-quit-all)
    ]
   ]
  )

(transient-define-prefix cxc/transient-jump ()
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

(transient-define-prefix cxc/transient-search ()
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

(defun cxc/split-window-vertical ()
  "Split window right and move point to the new window."
  (interactive)
  (split-window-right)
  (windmove-right))

(defun cxc/split-window-horizontal ()
  "Split window below and move point to the new window."
  (interactive)
  (split-window-below)
  (windmove-down))

(transient-define-prefix cxc/transient-window ()
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
    ("/" "vertical" cxc/split-window-vertical)
    ("?" "horizontal" cxc/split-window-horizontal)
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
    ("D" "ace del" ace-delete-window)
    ("m" "maximum" delete-other-windows)
    (";" "switch" consult-buffer)
    ("u" "undo layout" winner-undo :transient t)
    ("U" "redo layout" winner-redo :transient t)
    ("q" "quit" transient-quit-all)
    ]
   ])


(transient-define-prefix cxc/transient-toggle ()
  "transient-toggle"
  [
   ["display"
    ("n" (lambda () (cxc/toggle-desc "line numbers" 'display-line-numbers-mode))
     display-line-numbers-mode :transient t)
    ("N" (lambda () (cxc/toggle-desc-p "relative numbers" (eq display-line-numbers 'relative)))
     cxc/toggle-relative-line-numbers :transient t)
    ("v" (lambda () (cxc/toggle-desc "visual-line" 'visual-line-mode))
     visual-line-mode :transient t)
    ("t" (lambda () (cxc/toggle-desc "truncate-lines" 'truncate-lines))
     toggle-truncate-lines :transient t)
    ("h" (lambda () (cxc/toggle-desc "hl-line" 'hl-line-mode))
     hl-line-mode :transient t)
    ("w" (lambda () (cxc/toggle-desc "whitespace" 'whitespace-mode))
     whitespace-mode :transient t)
    ("c" (lambda () (cxc/toggle-desc "fill-column" 'display-fill-column-indicator-mode))
     display-fill-column-indicator-mode :transient t)
    ]

   ["edit"
    ("o" (lambda () (cxc/toggle-desc "hideshow" 'hs-minor-mode))
     hs-minor-mode :transient t)
    ]

   ["frame"
    ("T" (lambda () (cxc/toggle-desc-p "transparency" (cxc/transparent-p)))
     cxc/toggle-transparency :transient t)
    ]

   ["actions"
    ("q" "quit" transient-quit-all)
    ]
   ])


(general-define-key
 "<f5>" 'revert-buffer
 "M-o" 'ace-window
 "M-y" 'consult-yank-pop
 "M-z" 'zap-to-char
 "M-Z" 'zap-up-to-char

 "C-," 'cxc/prev-buffer
 "C-;" 'consult-buffer
 "C-'" 'avy-goto-char-2
 "C-s" 'consult-line
 "C-=" 'er/expand-region

 "C-c C-/" 'evilnc-comment-or-uncomment-lines
 "C-c SPC" 'execute-extended-command
 "C-c q" 'cxc/kill-current-buffer
 "C-c w" 'delete-other-windows
 "C-c e" 'dired-tabs-toggle
 "C-c t" 'cxc/transient-toggle
 "C-c v" 'magit
 "C-c f" 'cxc/transient-file
 "C-c j" 'cxc/transient-jump
 "C-c s" 'cxc/transient-search
 "C-c W" 'cxc/transient-window
 "C-c p" 'cxc/transient-music)


(provide 'init-keys)
