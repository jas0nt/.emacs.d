;;; init-dired.el --- Dired and Dirvish configuration -*- lexical-binding: t -*-

(use-package dired
  :ensure nil  ; Built-in package
  :custom
  ;; REVERTED: Do not kill previous buffer automatically. 
  ;; This allows marks to persist in background buffers so you can move/copy between them.
  (dired-kill-when-opening-new-dired-buffer nil)
  
  ;; If two dired windows are open, copy/rename defaults to the other window.
  (dired-dwim-target t)
  ;; Standard listing switches
  (dired-listing-switches
   "-lt --almost-all --human-readable --group-directories-first --no-group")
  :config
  ;; Enable the 'a' command (dired-find-alternate-file) if you ever want to manually
  ;; kill the buffer while navigating.
  (put 'dired-find-alternate-file 'disabled nil))

(use-package dirvish
  :init
  (dirvish-override-dired-mode)
  ;; Evil integration
  (with-eval-after-load 'evil
    (evil-set-initial-state 'dired-mode 'emacs)
    (evil-set-initial-state 'dirvish-mode 'emacs))
  
  :custom
  (dirvish-default-layout nil)
  (dirvish-cache-dir (expand-file-name "dirvish/" my-emacs-cache-dir))
  (dirvish-quick-access-entries
   '(("h" "~/"                          "Home")
     ("d" "~/Downloads/"                "Downloads")
     ("m" "~/Music/"                    "Music")
     ("x" "/run/media/"                 "Drives")
     ("t" "~/.local/share/Trash/files/" "TrashCan")))
  (dirvish-mode-line-format
   '(:left (sort symlink) :right (omit yank index)))
  (dirvish-attributes
   '(vc-state subtree-state nerd-icons collapse git-msg file-time file-size))
  ;; Side window attributes (toggle with `dirvish-side`)
  (dirvish-side-attributes
   '(vc-state nerd-icons collapse file-size))

  :config
  (dirvish-peek-mode) ; Preview files in minibuffer

  (defun my-switch-to-last-non-file-manager ()
    "Switch to the last used buffer that is not dired-mode or dirvish-mode."
    (interactive)
    (let ((target-buffer
           (seq-find (lambda (buf)
                       (and 
			(not (eq buf (current-buffer)))
			(not (string-prefix-p " " (buffer-name buf)))
			(with-current-buffer buf
                          (not (derived-mode-p 'dired-mode 'dirvish-mode)))))
                     (buffer-list))))
      (if target-buffer
          (switch-to-buffer target-buffer)
	(message "No previous non-file-manager buffer found."))))

  ;; -----------------------------------------------------------------------
  ;; Custom Function: Open Kitty Cleanly
  ;; -----------------------------------------------------------------------
  (defun my-dirvish-open-kitty-here ()
    "Open a Kitty terminal in the current directory without blocking Emacs."
    (interactive)
    (let ((current-dir (dired-current-directory)))
      ;; Using start-process avoids the annoying *Async Shell Command* buffer
      (start-process "kitty" nil "kitty" "-d" current-dir)
      (message "Launched Kitty in: %s" current-dir)))

  ;; -----------------------------------------------------------------------
  ;; Custom Logic: Numbered Tabs (0-9)
  ;; -----------------------------------------------------------------------
  (add-to-list 'savehist-additional-variables 'my-dirvish-tab-list)
  (defvar my-dirvish-tab-list (make-vector 10 nil)
    "Vector to store tab paths, indexed from 0-9.")

  (defun my-dirvish-tab-bind (index)
    "Bind current directory to the given INDEX (1-10)."
    (let* ((actual-index (if (= index 0) 9 (1- index)))
           (current-dir default-directory))
      (aset my-dirvish-tab-list actual-index current-dir)
      (message "Tab %d bound to: %s" index (abbreviate-file-name current-dir))))

  (defun my-dirvish-tab-switch (index)
    "Switch to tab at INDEX (1-10)."
    (let* ((actual-index (if (= index 0) 9 (1- index)))
           (target-dir (aref my-dirvish-tab-list actual-index)))
      (if target-dir
          (progn
            (dirvish target-dir)
            (message "Switched to tab %d: %s" index (abbreviate-file-name target-dir)))
        (message "Tab %d is not bound to any path" index))))

  (defun my-dirvish-tab-list ()
    "Display all current tab bindings."
    (interactive)
    (let ((buf (get-buffer-create "*Dirvish Tab Bindings*")))
      (with-current-buffer buf
        (erase-buffer)
        (insert "Dirvish Tab Bindings:\n\n")
        (dotimes (i 10)
          (let ((display-num (if (= i 9) 0 (1+ i)))
                (path (aref my-dirvish-tab-list i)))
            (insert (format "%d. %s\n"
                            display-num
                            (if path (abbreviate-file-name path) "(not bound)"))))))
      (display-buffer buf)))

  (defun my-dirvish-tab-remove-current ()
    "Unbind current directory from tab list."
    (interactive)
    (let ((current-dir default-directory)
          (unbound nil))
      (dotimes (i 10)
        (when (equal (aref my-dirvish-tab-list i) current-dir)
          (aset my-dirvish-tab-list i nil)
          (setq unbound t)
          (message "Tab %d unbound." (if (= i 9) 0 (1+ i)))))
      (unless unbound
        (message "Current directory not found in tab bindings"))))

  ;; Generate the interactive functions for keybinding
  (dotimes (i 10)
    (let ((key (if (= i 9) 0 (1+ i))))
      ;; Bind function
      (defalias (intern (format "my-dirvish-tab-bind-%d" key))
        (lambda () (interactive) (my-dirvish-tab-bind key)))
      ;; Switch function
      (defalias (intern (format "my-dirvish-tab-switch-%d" key))
        (lambda () (interactive) (my-dirvish-tab-switch key)))))

  :bind
  (("C-x C-d" . dirvish)
   :map dirvish-mode-map
   ("Q"   . dirvish-quit)
   ("q"   . my-switch-to-last-non-file-manager)
   ("!" . my-dirvish-tab-remove-current)
   (","   . evil-switch-to-windows-last-buffer)
   (";"   . switch-to-buffer)
   
   ;; Tab Bindings
   ("C-1" . my-dirvish-tab-bind-1)
   ("C-2" . my-dirvish-tab-bind-2)
   ("C-3" . my-dirvish-tab-bind-3)
   ("C-4" . my-dirvish-tab-bind-4)
   ("C-5" . my-dirvish-tab-bind-5)
   ("C-6" . my-dirvish-tab-bind-6)
   ("C-7" . my-dirvish-tab-bind-7)
   ("C-8" . my-dirvish-tab-bind-8)
   ("C-9" . my-dirvish-tab-bind-9)
   ("C-0" . my-dirvish-tab-bind-0)
   
   ;; Tab Switching
   ("1"   . my-dirvish-tab-switch-1)
   ("2"   . my-dirvish-tab-switch-2)
   ("3"   . my-dirvish-tab-switch-3)
   ("4"   . my-dirvish-tab-switch-4)
   ("5"   . my-dirvish-tab-switch-5)
   ("6"   . my-dirvish-tab-switch-6)
   ("7"   . my-dirvish-tab-switch-7)
   ("8"   . my-dirvish-tab-switch-8)
   ("9"   . my-dirvish-tab-switch-9)
   ("0"   . my-dirvish-tab-switch-0)

   ;; Tools
   ("T"   . my-dirvish-open-kitty-here)
   ("`"   . dirvish-layout-toggle)
   ("TAB" . dirvish-subtree-toggle)
   
   ;; Navigation & Actions
   ("z"   . dired-jump-with-zoxide)
   ("h"   . dired-up-directory)
   ("l"   . dired-find-file)
   ("j"   . dired-next-line)
   ("k"   . dired-previous-line)
   ("C-d" . scroll-up-command)
   ("C-u" . scroll-down-command)
   ("/"   . consult-line)
   ("?"   . dirvish-dispatch)
   ("RET" . dired-do-open)
   ("a"   . dired-create-empty-file)
   ("A"   . dired-create-directory)
   ("c"   . dirvish-file-info-menu)
   ("o"   . dirvish-quick-access)
   ("n"   . dirvish-narrow)
   ("N"   . revert-buffer)
   ("s"   . dirvish-quicksort)
   ("r"   . dired-toggle-read-only)    ; Activates wdired (editable buffer)
   ("*"   . dirvish-mark-menu)
   ("y"   . dirvish-yank-menu)
   ("p"   . dirvish-yank)              ; Paste file
   ("P"   . dirvish-move)              ; Move file
   ("J"   . dirvish-history-jump)
   ("L"   . dirvish-history-go-forward)
   ("H"   . dirvish-history-go-backward)
   ("gg"  . beginning-of-buffer)
   ("G"   . end-of-buffer)
   ("gl"  . evil-avy-goto-line)
   ("g/"  . evil-avy-goto-char-timer)))

;; Additional syntax highlighting for dired
(use-package diredfl
  :hook
  ((dired-mode . diredfl-mode)
   (dirvish-directory-view-mode . diredfl-mode))
  :config
  (set-face-attribute 'diredfl-dir-name nil :bold t))

(use-package dired-k
  :config
  (setq dired-k-style 'git)
  :hook
  ((dired-mode . dired-k)))

(use-package zoxide
  :config
  (defun dired-jump-with-zoxide (&optional other-window)
    (interactive "P")
    (zoxide-open-with nil (lambda (file) (dired-jump other-window file)) t)))



(provide 'init-dired)
