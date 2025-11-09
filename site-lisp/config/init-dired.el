(use-package dirvish
  :init
  (dirvish-override-dired-mode)
  (evil-set-initial-state 'dired-mode 'emacs)
  (evil-set-initial-state 'dirvish-mode 'emacs)
  :custom
  (dirvish-cache-dir (expand-file-name "dirvish/" my-emacs-cache-dir))
  (dirvish-quick-access-entries ; It's a custom option, `setq' won't work
   '(("h" "~/"                          "Home")
     ("d" "~/Downloads/"                "Downloads")
     ("x" "/run/media/"                 "Drives")
     ("t" "~/.local/share/Trash/files/" "TrashCan")))
  :config
  (setq dired-listing-switches
        "-l --almost-all --human-readable --group-directories-first --no-group")
  (put 'dired-find-alternate-file 'disabled nil)
  (dirvish-peek-mode)                ; Preview files in minibuffer
  ;; (dirvish-side-follow-mode)      ; similar to `treemacs-follow-mode'
  (setq dirvish-mode-line-format
        '(:left (sort symlink) :right (omit yank index)))
  (setq dirvish-attributes           ; The order *MATTERS* for some attributes
        '(vc-state subtree-state nerd-icons collapse git-msg file-time file-size)
        dirvish-side-attributes
        '(vc-state nerd-icons collapse file-size))
  :bind
  (("C-x C-d" . dirvish)
   :map dirvish-mode-map               ; Dirvish inherits `dired-mode-map'
   ("q"   . dirvish-quit)
   ("T"   . dirvish-layout-toggle)
   ("h"   . dired-up-directory)
   ("l"   . dired-find-file)
   ("j"   . dired-next-line)
   ("k"   . dired-previous-line)
   ("/"   . consult-line)
   ("?"   . dirvish-dispatch)          ; [?] a helpful cheatsheet
   ("RET" . dired-do-open)
   ("a"   . dired-create-empty-file)
   ("A"   . dired-create-directory)
   ("c"   . dirvish-file-info-menu)    ; copy
   ("g"   . dirvish-quick-access)      ; go to `dirvish-quick-access-entries'
   ("n"   . dirvish-narrow)
   ("N"   . revert-buffer)
   ("s"   . dirvish-quicksort)         ; sort flie list
   ("r"   . dired-toggle-read-only)    ; batch rename
   ("*"   . dirvish-mark-menu)
   ("y"   . dirvish-yank-menu)
   ("TAB" . dirvish-subtree-toggle)
   ("J"   . dirvish-history-jump)      ; recent visited
   ("L"   . dirvish-history-go-forward)
   ("H"   . dirvish-history-go-backward)
   ))


(provide 'init-dired)
