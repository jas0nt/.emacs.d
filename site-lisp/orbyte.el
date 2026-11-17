;;; orbyte.el --- Lightweight vim-style modal motion/selection -*- lexical-binding: t; -*-

;; Version: 0.3
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience

;;; Commentary:

;; A minimal modal editing package:
;;  - Normal state: vim-style single keys for motion, selection, search
;;    and jumping.
;;  - Insert state: plain native Emacs, with no extra bindings except
;;    <escape> to return to Normal.
;;  - Motion state: only the leader key, for buffers that take no text
;;    input (dired, help, magit, ...), so SPC works there too without
;;    taking over keys the buffer needs.
;; Editing commands (kill/copy/yank, etc.) keep using native Emacs keys
;; such as C-w / M-w / C-y / C-k / C-d, which also work in Normal state.
;;
;; `orbyte-global-mode' enables one `orbyte-mode' per buffer and picks the
;; starting state: Normal for `orbyte-modes', Motion for buffers where
;; letters do not insert text, and none for the rest (terminals, shells,
;; the minibuffer, ...).
;;
;; Deliberate differences from vim:
;;  - `v' selects whole lines and `V' selects characters, the reverse of
;;    vim.  See `orbyte-visual-line' and `orbyte-visual'.
;;  - There is no operator-pending state, so `dw' / `dd' / `cw' do not
;;    exist.  Select first (for example `v e'), then edit: `c' and `y'
;;    need a selection, and `d' kills the selection.  Without a
;;    selection `d' kills the character at point (like vim's `x').
;;  - Transient Mark mode is required; it is on by default.
;;
;; In Normal state SPC starts a keypad (like Meow keypad) that lets you
;; type key sequences without holding modifiers:
;;   SPC f       => C-c f      (leader: any unrecognised first key)
;;   SPC SPC     => C-c SPC
;;   SPC x f     => C-x C-f
;;   SPC x SPC b => C-x b      (SPC makes the next key literal)
;;   SPC m x     => M-x
;;   SPC g f     => C-M-f
;; See `orbyte-keypad' for the full rules.  Define the leader bindings on
;; C-c in your own config.  When `which-key-mode' is on, the keypad shows
;; the bindings of the prefix typed so far.
;;
;; To add your own Normal-state keys, use `orbyte-define-keys':
;;   (orbyte-define-keys (orbyte-normal-map "s" #'my-command))
;;
;; Usage:
;;   (require 'orbyte)
;;   (orbyte-global-mode 1)

;;; Code:

(require 'subr-x)

;; The state minor modes are defined further down; declare their variables
;; early so that the commands below can refer to the states.
(defvar orbyte-normal-mode)
(defvar orbyte-insert-mode)
(defvar orbyte-motion-mode)

;;;; Customization

(defgroup orbyte nil
  "Lightweight vim-style modal motion."
  :group 'convenience
  :prefix "orbyte-")

(defcustom orbyte-modes '(text-mode prog-mode conf-mode)
  "Major modes where `orbyte-global-mode' enables Normal state.
Matches the listed modes and any mode derived from them.  Other buffers
get Motion state when letters do not insert text, and no state at all
otherwise."
  :type '(repeat symbol))

(defconst orbyte--excluded-modes
  '(term-mode vterm-mode eat-mode eshell-mode)
  "Major modes that never get any state, so their keys reach the process.")

;;;; Motion commands

(defun orbyte-word-end (count)
  "Move onto the last character of the COUNT-th word (like vim's e)."
  (interactive "p")
  (dotimes (_ count)
    (ignore-errors (forward-char))
    (forward-word)
    (unless (bobp) (backward-char))))

(defun orbyte-WORD-end (count)
  "Move onto the last character of the COUNT-th WORD (like vim's E).
WORDs are separated by whitespace only."
  (interactive "p")
  (dotimes (_ count)
    (ignore-errors (forward-char))
    (skip-chars-forward " \t\n")
    (skip-chars-forward "^ \t\n")
    (unless (bobp) (backward-char))))

(defun orbyte-WORD-forward (count)
  "Move to the start of the COUNT-th whitespace-separated WORD (like vim's W)."
  (interactive "p")
  (dotimes (_ count)
    (skip-chars-forward "^ \t\n")
    (skip-chars-forward " \t\n")))

(defun orbyte-WORD-backward (count)
  "Move back to the start of the COUNT-th whitespace-separated WORD (like vim's B)."
  (interactive "p")
  (dotimes (_ count)
    (skip-chars-backward " \t\n")
    (skip-chars-backward "^ \t\n")))

(defun orbyte-window-top ()
  "Move to the first line of the window (vim's H)."
  (interactive)
  (move-to-window-line 0))

(defun orbyte-window-bottom ()
  "Move to the last line of the window (vim's L)."
  (interactive)
  (move-to-window-line -1))

(defun orbyte-window-middle ()
  "Move to the middle line of the window (vim's M)."
  (interactive)
  (move-to-window-line nil))

(defun orbyte-match-paren ()
  "Jump to the matching bracket (vim's %)."
  (interactive)
  (condition-case nil
      (cond ((looking-at-p "\\s(") (forward-sexp) (backward-char))
            ((looking-at-p "\\s)") (forward-char) (backward-sexp))
            (t (user-error "Not on a bracket")))
    (scan-error (user-error "Unbalanced brackets"))))

;;;; Selection

(defvar-local orbyte--linewise nil
  "Non-nil when the active region is a line-wise selection.")

(defvar-local orbyte--linewise-anchor nil
  "Marker at the beginning of the anchor line of a line-wise selection.")

(defun orbyte--linewise-clear ()
  "Forget the line-wise selection state."
  (setq orbyte--linewise nil)
  (when (markerp orbyte--linewise-anchor)
    (set-marker orbyte--linewise-anchor nil)
    (setq orbyte--linewise-anchor nil)))

(defun orbyte--linewise-pre-command ()
  "Drop stale line-wise state once the region has been deactivated."
  (when (and orbyte--linewise (not (region-active-p)))
    (orbyte--linewise-clear)))

(defun orbyte--linewise-refresh ()
  "Keep a line-wise selection aligned to whole lines.
Runs from `post-command-hook' so that every motion keeps extending the
selection by complete lines, the way vim's line-wise visual mode does."
  (when (and orbyte--linewise
             (markerp orbyte--linewise-anchor)
             (marker-position orbyte--linewise-anchor)
             (region-active-p))
    (let ((anchor (marker-position orbyte--linewise-anchor)))
      (if (>= (point) anchor)
          (progn
            (set-mark anchor)
            (goto-char (line-end-position)))
        (set-mark (save-excursion
                    (goto-char anchor)
                    (line-end-position)))
        (goto-char (line-beginning-position))))))

(defun orbyte--selection-bounds ()
  "Return the (BEG . END) of the active selection.
A line-wise selection is widened to whole lines, including the trailing
newline, so that `d' / `c' / `y' behave like vim.  An empty character-wise
selection counts as the character at point."
  (let ((b (region-beginning))
        (e (region-end)))
    (cond
     ((and orbyte--linewise (> e b))
      (cons (save-excursion (goto-char b) (line-beginning-position))
            (save-excursion (goto-char e)
                            (if (bolp) e (line-beginning-position 2)))))
     ((and orbyte--linewise (>= (point) b))
      ;; A line-wise selection of a single empty line.
      (cons (save-excursion (goto-char b) (line-beginning-position))
            (save-excursion (goto-char b) (line-beginning-position 2))))
     ((= b e)
      (cons (point) (min (1+ (point)) (point-max))))
     (t (cons b e)))))

(defun orbyte-visual ()
  "Toggle character-wise selection (character-wise visual mode).
This is vim's `v', but bound to `V' here; see `orbyte-visual-line'.
The character at point is selected and later motions extend the region."
  (interactive)
  (orbyte--linewise-clear)
  (if (region-active-p)
      (deactivate-mark)
    (push-mark (point) t t)
    (unless (eobp) (forward-char 1))))

(defun orbyte-visual-line ()
  "Toggle line-wise selection (line-wise visual mode).
This is vim's `V', but bound to `v' here; see `orbyte-visual'.
Selects the current line; later motions keep extending the selection by
whole lines, and `d' / `c' / `y' operate on complete lines including
the trailing newline."
  (interactive)
  (if (and orbyte--linewise (region-active-p))
      (progn
        (deactivate-mark)
        (orbyte--linewise-clear))
    (when (markerp orbyte--linewise-anchor)
      (set-marker orbyte--linewise-anchor nil))
    (setq orbyte--linewise t
          orbyte--linewise-anchor (copy-marker (line-beginning-position) t))
    (goto-char (line-beginning-position))
    (push-mark (point) t t)
    (goto-char (line-end-position))))

;;;; Editing commands

(defun orbyte-change ()
  "Kill the active selection and enter Insert state (vim's visual c)."
  (interactive "*")
  (unless (region-active-p)
    (user-error "No active selection"))
  (let ((bounds (orbyte--selection-bounds)))
    (kill-region (car bounds) (cdr bounds)))
  (orbyte--linewise-clear)
  (orbyte-insert-mode 1))

(defun orbyte-delete (&optional arg)
  "Kill the active selection, staying in Normal state (vim's visual d).
Without an active selection, kill ARG characters at point like `kill-region',
so that the text can be pasted back with `yank'."
  (interactive "*P")
  (if (region-active-p)
      (progn
        (let ((bounds (orbyte--selection-bounds)))
          (kill-region (car bounds) (cdr bounds)))
        (orbyte--linewise-clear))
    (let* ((n (prefix-numeric-value arg))
           (p (point))
           (q (save-excursion (forward-char n) (point))))
      (kill-region (min p q) (max p q)))))

(defun orbyte-copy ()
  "Copy the active selection to the kill ring (vim's visual y).
Point moves to the start of the selection and the selection is cleared."
  (interactive)
  (unless (region-active-p)
    (user-error "No active selection"))
  (let* ((bounds (orbyte--selection-bounds))
         (beg (car bounds)))
    (kill-ring-save beg (cdr bounds))
    (deactivate-mark)
    (orbyte--linewise-clear)
    (goto-char beg)))

(defun orbyte-paste (&optional arg)
  "Yank at point (vim's p).
With an active selection, replace the selection with the yanked text.
ARG is passed to `yank'."
  (interactive "*P")
  (when (region-active-p)
    (let ((bounds (orbyte--selection-bounds)))
      (delete-region (car bounds) (cdr bounds)))
    (orbyte--linewise-clear)
    (deactivate-mark))
  (yank arg))

(defun orbyte-o ()
  "With an active selection, swap point and mark (vim's visual o).
Otherwise open a new line below and enter Insert state (vim's o).
Note that the two meanings are exclusive: to open a line while a
selection is active, cancel the selection first."
  (interactive)
  (if (region-active-p)
      (exchange-point-and-mark)
    (orbyte-open-below)))

;;;; Entering / leaving Insert

(defun orbyte-normal ()
  "Return to Normal state.
Move back one character first when leaving Insert state, so that point
sits on the last typed character, the way vim leaves the cursor after
<escape>."
  (interactive)
  (when (and orbyte-insert-mode (not (bolp)))
    (backward-char))
  (orbyte--linewise-clear)
  (orbyte-normal-mode 1))

(defun orbyte-insert ()
  "Enter Insert state before point (vim's i)."
  (interactive)
  (orbyte-insert-mode 1))

(defun orbyte-append ()
  "Enter Insert state after point (vim's a)."
  (interactive)
  (unless (eolp) (forward-char))
  (orbyte-insert-mode 1))

(defun orbyte-insert-bol ()
  "Enter Insert state at the first non-blank character of the line (vim's I)."
  (interactive)
  (back-to-indentation)
  (orbyte-insert-mode 1))

(defun orbyte-append-eol ()
  "Enter Insert state at the end of the line (vim's A)."
  (interactive)
  (end-of-line)
  (orbyte-insert-mode 1))

(defun orbyte-open-below ()
  "Open a new line below and enter Insert state (vim's o)."
  (interactive)
  (end-of-line)
  (newline-and-indent)
  (orbyte-insert-mode 1))

(defun orbyte-open-above ()
  "Open a new line above and enter Insert state (vim's O)."
  (interactive)
  (beginning-of-line)
  (open-line 1)
  (indent-according-to-mode)
  (orbyte-insert-mode 1))

;;;; Search (reuses isearch state)

(defvar-local orbyte--last-match nil
  "Last match found by `orbyte--search', as (BEG . END).
Repeating the search skips over it, because a shorter match can start
inside the previous one (the `23' inside `123' for `[0-9]+').")

(defvar orbyte--search-fun-function nil
  "Search function of the last isearch.
`orbyte-search-next' and `orbyte-search-prev' rebuild the search through
`isearch-search-fun' with it, so custom engines (pcre2el, visual-regexp,
...) keep working after the isearch has ended.")

(defun orbyte--search (forward)
  "Search for the last isearch string in direction FORWARD, wrapping around.
Uses the same matching rules (regexp, word, symbol, case) as the last
isearch.  Point ends up on the start of the match."
  (when (string-empty-p isearch-string)
    (user-error "No previous search"))
  (let* ((case-fold-search isearch-case-fold-search)
         (isearch-forward forward)
         (isearch-search-fun-function
          (or orbyte--search-fun-function isearch-search-fun-function))
         (fn (isearch-search-fun))
         (origin (point)))
    ;; Point is on the start of the current match: continue after it.
    (when (and forward
               orbyte--last-match
               (= (point) (car orbyte--last-match)))
      (goto-char (min (cdr orbyte--last-match) (point-max))))
    (unless (funcall fn isearch-string nil t)
      (goto-char (if forward (point-min) (point-max)))
      (if (funcall fn isearch-string nil t)
          (message "Search wrapped")
        (goto-char origin)
        (user-error "Not found: %s" isearch-string)))
    (setq orbyte--last-match (cons (match-beginning 0) (match-end 0)))
    (goto-char (match-beginning 0))))

(defun orbyte-search-next ()
  "Find the next match in the last search direction (vim's n)."
  (interactive)
  (orbyte--search isearch-forward))

(defun orbyte-search-prev ()
  "Find the next match against the last search direction (vim's N)."
  (interactive)
  (orbyte--search (not isearch-forward)))

(defun orbyte--isearch-end ()
  "Remember the engine and match, then move to the match start.
This makes `/' behave like vim's search; Emacs leaves point at the end."
  (setq orbyte--search-fun-function isearch-search-fun-function)
  (setq orbyte--last-match
        (unless isearch-mode-end-hook-quit
          (when isearch-other-end
            (if isearch-forward
                (cons isearch-other-end (point))
              (cons (point) isearch-other-end)))))
  (when (and orbyte-normal-mode
             isearch-forward
             isearch-other-end
             (not isearch-mode-end-hook-quit))
    (goto-char isearch-other-end)))

;; Run before other end hooks: pcre2el restores `isearch-search-fun-function'
;; in its own end hook, and the value is needed for `n' / `N' afterwards.
(add-hook 'isearch-mode-end-hook #'orbyte--isearch-end -90)

;;;; Keypad (SPC): type key sequences without holding modifiers

(defun orbyte--keypad-event (seq ev mods)
  "Translate key EV, pressed after the keys in SEQ, into an event.
MODS is nil, `literal', or a list of modifiers such as (meta).
Without an explicit modifier, a letter or digit is taken as Control
when the resulting C-<key> is bound; other keys are always taken
literally, since Control versions of punctuation are often aliases of
unrelated keys (C-[ is ESC, for instance)."
  (cond ((eq mods 'literal) ev)
        ((consp mods)
         (or (ignore-errors (event-convert-list (append mods (list ev))))
             ev))
        (t
         (let ((ctrl (and (integerp ev)
                          (or (<= ?a ev ?z) (<= ?0 ev ?9))
                          (ignore-errors
                            (event-convert-list (list 'control ev))))))
           (if (and ctrl (key-binding (vconcat seq (vector ctrl))))
               ctrl
             ev)))))

(defun orbyte--keypad-prompt (seq mods)
  "Return the echo-area prompt for the keypad."
  (if (zerop (length seq))
      "Keypad: x=C-x h=C-h m=M- g=C-M- other=C-c"
    (format "Keypad: %s%s"
            (concat (key-description seq) " ")
            (cond ((eq mods 'literal) "(literal) ")
                  ((equal mods '(meta)) "M- ")
                  ((consp mods) "C-M- ")
                  (t "")))))

;; which-key has no public API for showing an arbitrary keymap, so these
;; two use its internal functions (as Meow's keypad does).  They are
;; guarded by `fboundp' and `ignore-errors': if which-key changes, the
;; popup silently disappears and the keypad still works.

(defun orbyte--keypad-which-key-show (seq)
  "Show which-key help for the prefix keymap bound to SEQ, if any."
  (when (and (> (length seq) 0)
             (bound-and-true-p which-key-mode)
             (fboundp 'which-key--create-buffer-and-show))
    (let ((km (key-binding seq)))
      (when (keymapp km)
        (ignore-errors
          (which-key--create-buffer-and-show
           nil km nil (concat "Keypad: " (key-description seq))))))))

(defun orbyte--keypad-which-key-hide ()
  "Hide the which-key popup, if which-key is active."
  (when (and (bound-and-true-p which-key-mode)
             (fboundp 'which-key--hide-popup))
    (ignore-errors (which-key--hide-popup))))

(defun orbyte-keypad ()
  "Read a key sequence without modifier keys, then run it.

The first key chooses the prefix:
  x / h       C-x / C-h
  m           M- on the next key        (m x    => M-x)
  g           C-M- on the next key      (g f    => C-M-f)
  other key   C-c plus that key, so SPC q runs C-c q,
              and SPC SPC runs C-c SPC.

Later keys use Control if C-<key> is bound after the keys so far,
otherwise the plain key (x f => C-x C-f, x s => C-x C-s).  Press SPC
before a key to force the plain key (x SPC b => C-x b), and m or g
for Meta or Control-Meta.  C-g or ESC cancels.

With `which-key-mode' on, the bindings under the prefix typed so far
are shown while reading the next key.

A numeric prefix typed before SPC is passed on to the command."
  (interactive)
  (let ((arg current-prefix-arg)
        (seq [])
        (mods nil)
        (done nil))
    (unwind-protect
        (progn
          (while (not done)
            (orbyte--keypad-which-key-show seq)
            (let ((ev (read-key (orbyte--keypad-prompt seq mods))))
              (cond
               ((memq ev '(?\C-g 27)) (keyboard-quit))
               ((and (null mods) (eql ev ?m))
                (setq mods '(meta)))
               ((and (null mods) (eql ev ?g))
                (setq mods '(control meta)))
               ((and (null mods) (> (length seq) 0) (eql ev ?\s))
                (setq mods 'literal))
               ((and (null mods) (zerop (length seq)))
                (setq seq (pcase ev
                            (?x (kbd "C-x"))
                            (?h (kbd "C-h"))
                            (_ (vconcat (kbd "C-c") (vector ev))))))
               (t
                (setq seq (vconcat seq (vector (orbyte--keypad-event seq ev mods)))
                      mods nil)))
              (when (and (null mods) (> (length seq) 0))
                (let ((binding (key-binding seq)))
                  (cond ((null binding)
                         (user-error "Keypad: %s is undefined"
                                     (key-description seq)))
                        ((keymapp binding))
                        (t (setq done t)))))))
          ;; Replay the translated keys through the normal command loop.
          (setq prefix-arg arg
                unread-command-events (append seq unread-command-events)))
      (orbyte--keypad-which-key-hide))))

;;;; Keymaps (qwerty order, lower and upper case side by side)

(defvar-keymap orbyte-g-map
  :doc "Prefix map for g in Normal state."
  "g" #'beginning-of-buffer)

(defvar-keymap orbyte-normal-map
  :doc "Normal state keymap.  Unbound plain characters are disabled
(they do not insert text)."
  :suppress 'nodigits
  ;; Number row: count prefix
  "1" #'digit-argument
  "2" #'digit-argument
  "3" #'digit-argument
  "4" #'digit-argument
  "5" #'digit-argument
  "6" #'digit-argument
  "7" #'digit-argument
  "8" #'digit-argument
  "9" #'digit-argument

  ;; q w e r t y u i o p
  "w" #'forward-to-word
  "W" #'orbyte-WORD-forward
  "e" #'orbyte-word-end
  "E" #'orbyte-WORD-end
  "r" #'query-replace
  "R" #'query-replace-regexp
  "t" #'rectangle-mark-mode
  "y" #'orbyte-copy
  "u" #'undo
  "U" #'undo-redo
  "i" #'orbyte-insert
  "I" #'orbyte-insert-bol
  "o" #'orbyte-o
  "O" #'orbyte-open-above
  "p" #'orbyte-paste

  ;; a s d f g h j k l
  "a" #'orbyte-append
  "A" #'orbyte-append-eol
  "d" #'orbyte-delete
  "g" orbyte-g-map
  "G" #'end-of-buffer
  "h" #'backward-char
  "H" #'orbyte-window-top
  "j" #'next-line
  "J" #'delete-indentation
  "k" #'previous-line
  "l" #'forward-char
  "L" #'orbyte-window-bottom

  ;; z x c v b n m
  "c" #'orbyte-change
  "v" #'orbyte-visual-line
  "V" #'orbyte-visual
  "b" #'backward-word
  "B" #'orbyte-WORD-backward
  "n" #'orbyte-search-next
  "N" #'orbyte-search-prev
  "m" #'evilmi-jump-items-native
  "M" #'orbyte-window-middle

  ;; Space bar: keypad / leader key (SPC q = C-c q, SPC x f = C-x C-f)
  "SPC" #'orbyte-keypad

  ;; Symbol keys
  "^" #'back-to-indentation
  "%" #'orbyte-match-paren
  "*" #'isearch-forward-symbol-at-point
  "[" #'backward-paragraph
  "]" #'forward-paragraph
  "{" #'backward-sentence
  "}" #'forward-sentence
  "." #'repeat
  "/" #'isearch-forward-regexp
  "?" #'isearch-backward-regexp
  "<escape>" #'keyboard-quit)

(defvar-keymap orbyte-insert-map
  :doc "Insert state has a single key: <escape> returns to Normal.
Everything else is native Emacs."
  "<escape>" #'orbyte-normal)

(defvar-keymap orbyte-motion-map
  :doc "Motion state keymap for buffers that take no text input.
It only holds the leader by default, so that the buffer's own keys keep
working; add more with `orbyte-define-keys'."
  "SPC" #'orbyte-keypad)

;;;; Extending the keymaps

(defmacro orbyte-define-keys (&rest groups)
  "Bind keys in the orbyte keymaps, one GROUP per keymap.
Each GROUP is a list of the form (MAP KEY DEF KEY DEF ...): the keymap
variable followed by any number of key/definition pairs.  For example:

  (orbyte-define-keys
    (orbyte-normal-map \"s\" #\\='my-command
                      \"f\" #\\='another-command)
    (orbyte-g-map      \"l\" #\\='yet-another-command))

KEY is anything `keymap-set' accepts, and DEF may be nil to unbind KEY."
  (declare (indent 0))
  (cons 'progn
        (let (forms)
          (dolist (group groups)
            (let ((map (car group))
                  (pairs (cdr group)))
              (while pairs
                (push `(keymap-set ,map ,(car pairs) ,(cadr pairs)) forms)
                (setq pairs (cddr pairs)))))
          (nreverse forms))))

;;;; States (three minor modes)

(defun orbyte--update-cursor ()
  "Use a bar cursor in Insert state and a box in the other states."
  (if (or orbyte-normal-mode orbyte-insert-mode orbyte-motion-mode)
      (setq-local cursor-type (if orbyte-insert-mode 'bar 'box))
    (kill-local-variable 'cursor-type)))

(define-minor-mode orbyte-normal-mode
  "Normal state: single-key motion/selection; native Emacs keys for editing."
  :lighter " <N>"
  :keymap orbyte-normal-map
  (if orbyte-normal-mode
      (progn
        ;; Keep line-wise selections aligned to whole lines.
        (add-hook 'pre-command-hook #'orbyte--linewise-pre-command nil t)
        (add-hook 'post-command-hook #'orbyte--linewise-refresh nil t)
        (orbyte-insert-mode -1)
        (orbyte-motion-mode -1))
    (remove-hook 'pre-command-hook #'orbyte--linewise-pre-command t)
    (remove-hook 'post-command-hook #'orbyte--linewise-refresh t)
    (orbyte--linewise-clear))
  (orbyte--update-cursor))

(define-minor-mode orbyte-motion-mode
  "Motion state: the leader in buffers that take no text input.
Used for buffers such as dired, help or magit, where letters do not
insert text.  Its keymap only holds the leader, so the buffer's own keys
keep working."
  :lighter " <M>"
  :keymap orbyte-motion-map
  (when orbyte-motion-mode
    (orbyte-normal-mode -1)
    (orbyte-insert-mode -1))
  (orbyte--update-cursor))

(define-minor-mode orbyte-insert-mode
  "Insert state: native Emacs."
  :lighter " <I>"
  :keymap orbyte-insert-map
  (when orbyte-insert-mode
    (orbyte-normal-mode -1)
    (orbyte-motion-mode -1))
  (orbyte--update-cursor))

;;;; The orbyte mode (one per buffer)

(defun orbyte--self-inserting-p ()
  "Return non-nil when plain letters insert text in the current buffer.
Remapped commands count as self-inserting, so terminals that remap
`self-insert-command' are recognised too."
  (let ((i ?a)
        (found nil))
    (while (and (<= i ?z) (not found))
      (let ((cmd (key-binding (vector i))))
        (when (and (symbolp cmd)
                   (string-match-p "self-insert" (symbol-name cmd)))
          (setq found t)))
      (setq i (1+ i)))
    found))

(defun orbyte--switch-state (state)
  "Enable STATE and disable the other states."
  (dolist (pair '((normal . orbyte-normal-mode)
                  (insert . orbyte-insert-mode)
                  (motion . orbyte-motion-mode)))
    (funcall (cdr pair) (if (eq (car pair) state) 1 -1))))

(define-minor-mode orbyte-mode
  "Modal editing for the current buffer.
This is the buffer-level switch used by `orbyte-global-mode'; the keys
come from `orbyte-normal-mode', `orbyte-insert-mode' or
`orbyte-motion-mode'.  The starting state is Normal for `orbyte-modes',
Motion for buffers where letters do not insert text (dired, help,
magit, ...), and none for everything else."
  :lighter nil
  (orbyte--switch-state
   (and orbyte-mode
        (cond
         ((apply #'derived-mode-p orbyte--excluded-modes) nil)
         ((apply #'derived-mode-p orbyte-modes) 'normal)
         ((orbyte--self-inserting-p) nil)
         (t 'motion)))))

;;;; Global mode

(defun orbyte--turn-on ()
  "Enable `orbyte-mode' unless this is the minibuffer."
  (unless (minibufferp)
    (orbyte-mode 1)))

;;;###autoload
(define-globalized-minor-mode orbyte-global-mode orbyte-mode
  orbyte--turn-on
  :group 'orbyte)

(provide 'orbyte)
;;; orbyte.el ends here
