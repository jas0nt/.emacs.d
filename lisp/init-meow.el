(use-package meow
  :init
  (defun meow-setup ()
    (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)

    ;;; ============================================================
    ;;; MOTION state — for special/read-only buffers (dired, proced, etc.)
    ;;; ============================================================
    (meow-motion-overwrite-define-key
     '("j" . meow-next)
     '("k" . meow-prev)
     '("<escape>" . ignore))

    ;;; ============================================================
    ;;; LEADER — SPC-prefixed commands
    ;;; ============================================================
    (meow-leader-define-key
     '("<SPC>" . execute-extended-command)

     ;; --- SPC j/k pass through to run the original command in MOTION state ---
     '("j" . "H-j")
     '("k" . "H-k")

     ;; --- Digit arguments (SPC 1-0) ---
     '("1" . meow-digit-argument)
     '("2" . meow-digit-argument)
     '("3" . meow-digit-argument)
     '("4" . meow-digit-argument)
     '("5" . meow-digit-argument)
     '("6" . meow-digit-argument)
     '("7" . meow-digit-argument)
     '("8" . meow-digit-argument)
     '("9" . meow-digit-argument)
     '("0" . meow-digit-argument)

     ;; --- Help ---
     '("/" . meow-keypad-describe-key)
     '("?" . meow-cheatsheet))

    ;;; ============================================================
    ;;; NORMAL state — main command layer
    ;;; ============================================================
    (meow-normal-define-key

     ;; ---------- Movement ----------
     '("h" . meow-left)
     '("j" . meow-next)
     '("k" . meow-prev)
     '("l" . meow-right)
     '("[" . backward-paragraph)
     '("]" . forward-paragraph)
     '("w" . meow-next-word)
     '("W" . meow-next-symbol)
     '("b" . meow-back-word)
     '("B" . meow-back-symbol)
     '("f" . meow-find)
     '("t" . meow-till)
     '("Q" . meow-goto-line)
     '("V" . meow-goto-line)

     ;; ---------- Selection expand ----------
     '("H" . meow-left-expand)
     '("J" . meow-next-expand)
     '("K" . meow-prev-expand)
     '("L" . meow-right-expand)
     '("v" . meow-line)
     '("s" . meow-block)
     '("S" . meow-to-block)
     '("e" . meow-mark-word)
     '("E" . meow-mark-symbol)
     '("=" . er/expand-region)
     '("g" . meow-cancel-selection)
     '("z" . meow-pop-selection)
     '(";" . meow-reverse)

     ;; ---------- Thing (objects: brackets/quotes/paragraph, etc.) ----------
     '("," . meow-inner-of-thing)
     '("." . meow-bounds-of-thing)
     '("<" . meow-beginning-of-thing)
     '(">" . meow-end-of-thing)

     ;; ---------- Edit: insert ----------
     '("i" . meow-insert)
     '("a" . meow-append)
     '("o" . meow-open-below)
     '("O" . meow-open-above)
     '("c" . meow-change)
     '("r" . meow-replace)

     ;; ---------- Edit: delete ----------
     '("d" . meow-kill)
     '("x" . meow-delete)
     '("X" . meow-backward-delete)

     ;; ---------- Edit: copy/paste/grab ----------
     '("y" . meow-save)
     '("Y" . meow-sync-grab)
     '("p" . meow-yank)
     '("G" . meow-grab)
     '("R" . meow-swap-grab)

     ;; ---------- Undo / repeat ----------
     '("u" . meow-undo)
     '("U" . meow-undo-in-selection)
     '("'" . repeat)

     ;; ---------- Search / replace ----------
     '("n" . meow-search)
     '("/" . meow-visit)
     '("%" . meow-query-replace)

     ;; ---------- Digit arguments (NORMAL state) ----------
     '("0" . meow-expand-0)
     '("1" . meow-expand-1)
     '("2" . meow-expand-2)
     '("3" . meow-expand-3)
     '("4" . meow-expand-4)
     '("5" . meow-expand-5)
     '("6" . meow-expand-6)
     '("7" . meow-expand-7)
     '("8" . meow-expand-8)
     '("9" . meow-expand-9)
     '("-" . negative-argument)

     ;; ---------- Line / structure ----------
     '("m" . meow-join)

     ;; ---------- Macro ----------
     '("@" . meow-kmacro-lines)

     ;; ---------- Quit ----------
     '("q" . meow-quit)
     '("<escape>" . ignore)))

  :config
  ;;; ============================================================
  ;;; State assignment / thing registration
  ;;; ============================================================
  (add-to-list 'meow-mode-state-list '(blink-search-mode . insert))

  (meow-thing-register 'single-quote '(regexp "'" "'") '(regexp "'" "'"))
  (meow-thing-register 'angle '(regexp "<" ">") '(regexp "<" ">"))

  (setq meow-char-thing-table
        '((?\( . round)
          (?\) . round)
          (?{  . curly)
          (?}  . curly)
          (?\[ . square)
          (?\] . square)
          (?<  . angle)
          (?>  . angle)
          (?\" . string)
          (?'  . single-quote)
          (?b  . buffer)
          (?w  . window)
          (?.  . sentence)
          (?v  . line)
          (?f  . defun)
          (?p  . paragraph)
          (?s  . symbol)))

  (meow-setup)
  (meow-global-mode 1))

;;; ================================================================
;;; LEADER extra bindings — transient menu entry points
;;; Note: x, c, h, m, g are already used in NORMAL state, not reused here
;;; ================================================================
(meow-leader-define-key
 '("q" . delete-other-windows)
 '(";" . consult-buffer)
 '("," . my-prev-buffer)
 '("f" . my-transient-file)
 '("j" . my-transient-jump)
 '("s" . my-transient-search)
 '("w" . my-transient-window)
 '("p" . my-transient-music))

(provide 'init-meow)
