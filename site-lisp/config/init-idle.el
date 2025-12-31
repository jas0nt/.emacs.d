;;;; --- Core System & Memory ---

;; Use setq instead of custom-set-variables for cleaner init files.
;; Level 1 logs errors but suppresses noise. Level 0 makes debugging impossible.
(setq tramp-verbose 1)
(setq tramp-default-method "ssh")

(setq kill-ring-max 1024)        ; Undo/Cut history
(setq mark-ring-max 1024)
(setq global-mark-ring-max 1024)

;; Printing limits: Large, but not infinite (prevents freezing on circular data)
(setq eval-expression-print-length 10000)
(setq eval-expression-print-level 20)

;;;; --- Editor Behavior ---

(global-auto-revert-mode 1)
(global-hl-line-mode 1)          ; Highlight current line
(put 'narrow-to-region 'disabled nil)

;; Search & Minibuffer
(setq isearch-allow-scroll t)
(setq enable-recursive-minibuffers t)
(setq history-delete-duplicates t)
(setq minibuffer-message-timeout 1)

;; Parenthesis Matching
(show-paren-mode 1)
(setq show-paren-style 'parentheses) ; Highlight parens, don't jump cursor
(setq blink-matching-paren nil)      ; Don't flash the matching paren

;; Files & Encoding
(setq require-final-newline t) ; Recommended: t ensures POSIX compliance. Change back to nil only if specific need.

;;;; --- UI & Display ---

(setq message-log-max 5000)       ; Keep 5000 lines. 't' (infinite) can waste RAM over months.
(setq ediff-window-setup-function 'ediff-setup-windows-plain) ; No separate control frame
(setq x-stretch-cursor t)         ; Wide cursor on tabs
(setq void-text-area-pointer nil) ; Note: This changes pointer shape, doesn't hide it completely.
(setq print-escape-newlines t)    ; See \n as characters
(setq echo-keystrokes 0.1)        ; Fast feedback
(tooltip-mode -1)                 ; Use echo area instead of tooltips

;;;; --- Compilation ---

;; Cleaned up syntax using 'quote
(setq byte-compile-warnings
      '(free-vars
        unresolved
        callargs
        obsolete
        noruntime
        interactive-only
        make-local
        mapcar
        ;; Suppressed warnings
        (not redefine)
        (not cl-functions)))


(provide 'init-idle)
