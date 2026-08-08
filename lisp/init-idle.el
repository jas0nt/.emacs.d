;;; init-idle.el --- Settings loaded after 1 second of idle time -*- lexical-binding: t -*-

;; -----------------------------------------------------------------------
;; Core System & Memory
;; -----------------------------------------------------------------------

(setq tramp-verbose 1            ; Level 1: log errors, suppress noise
      tramp-default-method "ssh")

(setq kill-ring-max 1024         ; Max entries in the kill (clipboard) ring
      mark-ring-max 1024
      global-mark-ring-max 1024)

;; Large but finite: prevents freezing on circular data structures.
(setq eval-expression-print-length 10000
      eval-expression-print-level 20)

;; -----------------------------------------------------------------------
;; Editor Behavior
;; -----------------------------------------------------------------------

(global-auto-revert-mode 1)
(global-hl-line-mode 1)

(put 'narrow-to-region 'disabled nil)

;; Search & minibuffer.
(setq isearch-allow-scroll t
      enable-recursive-minibuffers t
      history-delete-duplicates t
      minibuffer-message-timeout 1)

;; Parenthesis matching.
(show-paren-mode 1)
(setq show-paren-style 'parentheses ; Highlight the parens themselves, not the region
      blink-matching-paren nil)      ; Don't flash the matching paren on screen

;; Files.
(setq require-final-newline t) ; Ensures POSIX compliance

;; -----------------------------------------------------------------------
;; UI & Display
;; -----------------------------------------------------------------------

(setq message-log-max 5000)    ; Finite limit; 't' (infinite) wastes RAM over time

(setq ediff-window-setup-function 'ediff-setup-windows-plain) ; No separate control frame
(setq x-stretch-cursor t)      ; Stretch cursor to cover wide characters (e.g. tabs)
(setq print-escape-newlines t) ; Display \n as a visible escape sequence
(setq echo-keystrokes 0.1)     ; Show keystrokes in echo area quickly

(tooltip-mode -1)              ; Show tooltips in the echo area instead

;; -----------------------------------------------------------------------
;; Compilation Warnings
;; -----------------------------------------------------------------------

;; Enable all standard warnings except `redefine' and `cl-functions',
;; which tend to produce noise from third-party packages.
(setq byte-compile-warnings '(not redefine cl-functions))

(provide 'init-idle)
;;; init-idle.el ends here
