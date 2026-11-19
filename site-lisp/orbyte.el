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
;; In Normal state `d' and `y' are bound to `kill-region' and
;; `kill-ring-save', so they behave exactly like C-w / M-w.
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
;;    exist.  Select first, then edit: `d' and `y' use the native
;;    region (`kill-region' / `kill-ring-save'), and `c' kills it and
;;    enters Insert.  The region is Emacs's half-open region, not an
;;    inclusive vim-style selection.
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
  :type '(repeat symbol)
  :group 'orbyte)

(defcustom orbyte-excluded-modes
  '(term-mode vterm-mode eat-mode eshell-mode)
  "Major modes that never get any state, so their keys reach the process.
`eshell-mode' also looks self-inserting, but it is listed explicitly so
that a change in keymap detection cannot give it Motion state."
  :type '(repeat symbol)
  :group 'orbyte)

(defcustom orbyte-normal-lighter (string #x20 #xF0018)
  "Mode line indicator for the Normal state.
Change it to another string if the default Nerd Font glyph is unavailable."
  :type 'string
  :group 'orbyte)

(defcustom orbyte-insert-lighter (string #x20 #xF4E9)
  "Mode line indicator for the Insert state.
Change it to another string if the default Nerd Font glyph is unavailable."
  :type 'string
  :group 'orbyte)

(defcustom orbyte-motion-lighter (string #x20 #xF0E7B)
  "Mode line indicator for the Motion state.
Change it to another string if the default Nerd Font glyph is unavailable."
  :type 'string
  :group 'orbyte)

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
    (set-marker orbyte--linewise-anchor nil))
  (setq orbyte--linewise-anchor nil))

(defun orbyte--selection-clear ()
  "Forget any orbyte selection state."
  (orbyte--linewise-clear))

(defun orbyte--selection-pre-command ()
  "Drop stale line-wise state once the region has been deactivated."
  (when (and orbyte--linewise (not (region-active-p)))
    (orbyte--selection-clear)))

(defun orbyte--line-eol (pos)
  "Return the end of the line at POS, ignoring fields."
  (save-excursion
    (goto-char pos)
    (pos-eol)))

(defun orbyte--linewise-refresh ()
  "Keep a line-wise selection aligned to whole lines.
Runs from `post-command-hook' so that every motion keeps extending the
selection by complete lines, the way vim's line-wise visual mode does."
  (when (and orbyte--linewise
             (markerp orbyte--linewise-anchor)
             (marker-position orbyte--linewise-anchor)
             (region-active-p)
             (not deactivate-mark))
    (let ((anchor (marker-position orbyte--linewise-anchor)))
      (if (>= (point) anchor)
          (progn
            (set-mark anchor)
            (goto-char (pos-eol)))
        (set-mark (orbyte--line-eol anchor))
        (goto-char (pos-bol))))))

(defun orbyte-visual ()
  "Toggle character-wise selection (character-wise visual mode).
This is vim's `v', but bound to `V' here; see `orbyte-visual-line'.
Starts an empty selection at point; later motions extend it.  The
selection is the ordinary Emacs region, so the position at the moving
end is exclusive, like `kill-region' and `kill-ring-save'."
  (interactive)
  (if (region-active-p)
      (progn
        (deactivate-mark)
        (orbyte--selection-clear))
    (orbyte--selection-clear)
    (set-mark (point))))

(defun orbyte-visual-line ()
  "Toggle line-wise selection (line-wise visual mode).
This is vim's `V', but bound to `v' here; see `orbyte-visual'.
Selects the current line; later motions keep extending the selection by
whole lines.  The region is the ordinary Emacs region, so it ends at the
line end and does not include the trailing newline."
  (interactive)
  (if (and orbyte--linewise (region-active-p))
      (progn
        (deactivate-mark)
        (orbyte--selection-clear))
    (orbyte--selection-clear)
    (setq orbyte--linewise t
          orbyte--linewise-anchor (copy-marker (pos-bol) t))
    (goto-char (pos-bol))
    (set-mark (point))
    (goto-char (pos-eol))))

;;;; Editing commands

(defun orbyte-change ()
  "Kill the active selection and enter Insert state (vim's visual c).
Killing uses the native region, like `kill-region'."
  (interactive "*")
  (unless (region-active-p)
    (user-error "No active selection"))
  (kill-region (mark t) (point) 'region)
  (orbyte--selection-clear)
  (orbyte-insert-mode 1))

(defun orbyte-paste (&optional arg)
  "Yank at point (vim's p).
With an active selection, replace the region with the yanked text.
ARG is passed to `yank'."
  (interactive "*P")
  (when (region-active-p)
    (delete-region (region-beginning) (region-end))
    (orbyte--selection-clear)
    (deactivate-mark))
  (yank arg))

(defun orbyte-o ()
  "With an active selection, swap point and mark (vim's visual o).
In a line-wise selection this swaps the anchor line, so the selection
does not collapse.  Otherwise, open a new line below and enter Insert
state (vim's o)."
  (interactive)
  (cond
   ((not (region-active-p))
    (orbyte-open-below))
   ((and orbyte--linewise
         (markerp orbyte--linewise-anchor)
         (marker-position orbyte--linewise-anchor))
    (let ((old (marker-position orbyte--linewise-anchor)))
      (set-marker orbyte--linewise-anchor (pos-bol))
      (goto-char old)))
   (t
    (exchange-point-and-mark))))

;;;; Entering / leaving Insert

(defun orbyte-normal ()
  "Return to Normal state.
Move back one character first when leaving Insert state, so that point
sits on the last typed character, the way vim leaves the cursor after
<escape>."
  (interactive)
  (when (and orbyte-insert-mode (not (bolp)))
    (backward-char))
  (orbyte--selection-clear)
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
  (goto-char (pos-eol))
  (orbyte-insert-mode 1))

(defun orbyte-open-below ()
  "Open a new line below and enter Insert state (vim's o)."
  (interactive)
  (goto-char (pos-eol))
  (newline-and-indent)
  (orbyte-insert-mode 1))

(defun orbyte-open-above ()
  "Open a new line above and enter Insert state (vim's O)."
  (interactive)
  (goto-char (pos-bol))
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

(defvar-local orbyte--hi-lock-lighter nil
  "Lighter of the hi-lock pattern left by orbyte's search, or nil.")

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

(defun orbyte-find-region-or-symbol ()
  "Search for the active region, or the symbol at point.
With no active region, if a search highlight is already shown, remove
it instead of searching again.  A region always starts a new search.
The region's text is searched literally.  The search finishes
immediately, so `n' and `N' can be used right away.  Unlike
`isearch-forward-symbol-at-point', this does not leave isearch active."
  (interactive)
  (cond
   ((and orbyte--hi-lock-lighter (not (use-region-p)))
    (orbyte-clear-search-highlight))
   ((use-region-p)
    (let ((string (buffer-substring-no-properties (region-beginning)
                                                  (region-end))))
      (when (string-empty-p string)
        (user-error "Empty region"))
      (deactivate-mark)
      (isearch-forward nil 1)
      (isearch-yank-string string)
      (isearch-done)))
   (t
    (isearch-forward-symbol-at-point)
    (isearch-done))))

(defun orbyte-clear-search-highlight ()
  "Remove the highlight left by the last orbyte search."
  (interactive)
  (when orbyte--hi-lock-lighter
    (require 'hi-lock nil t)
    (ignore-errors (unhighlight-regexp orbyte--hi-lock-lighter))
    (setq orbyte--hi-lock-lighter nil)))

(defun orbyte--search-regexp ()
  "Return the regexp matching the current isearch string."
  (cond
   ((functionp isearch-regexp-function)
    (funcall isearch-regexp-function isearch-string))
   (isearch-regexp-function
    (word-search-regexp isearch-string))
   ((and isearch-regexp
         (bound-and-true-p pcre-mode)
         (fboundp 'pcre-to-elisp/cached))
    (pcre-to-elisp/cached isearch-string))
   (isearch-regexp isearch-string)
   (t (regexp-quote isearch-string))))

(defun orbyte--highlight-search ()
  "Use hi-lock to keep the last isearch's matches visible."
  (when (and (or orbyte-normal-mode orbyte-insert-mode)
             (not (equal isearch-string "")))
    (require 'hi-lock nil t)
    (let ((regexp (orbyte--search-regexp)))
      (orbyte-clear-search-highlight)
      (let ((case-fold-search isearch-case-fold-search)
            (search-upper-case nil))
        (when (ignore-errors
                (highlight-regexp regexp 'lazy-highlight nil isearch-string)
                t)
          (setq orbyte--hi-lock-lighter isearch-string))))))

(defun orbyte--isearch-end ()
  "Remember the engine and match, then move to the match start.
This makes `/' behave like vim's search; Emacs leaves point at the end.
Only buffers in Normal or Insert state are affected, even though the
hook itself is global."
  (when (or orbyte-normal-mode orbyte-insert-mode)
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
      (goto-char isearch-other-end))
    (when (and (or orbyte-normal-mode orbyte-insert-mode)
               (not isearch-mode-end-hook-quit))
      (orbyte--highlight-search))))

;; Run before other end hooks: pcre2el restores `isearch-search-fun-function'
;; in its own end hook, and the value is needed for `n' / `N' afterwards.
(add-hook 'isearch-mode-end-hook #'orbyte--isearch-end -90)
;; A new search replaces the highlight left by the previous one.
(add-hook 'isearch-mode-hook #'orbyte-clear-search-highlight)

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
  "y" #'kill-ring-save
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
  "d" #'kill-region
  "f" #'orbyte-find-region-or-symbol
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
  "M" #'orbyte-window-middle

  ;; Space bar: keypad / leader key (SPC q = C-c q, SPC x f = C-x C-f)
  "SPC" #'orbyte-keypad

  ;; Symbol keys
  "^" #'back-to-indentation
  "%" #'orbyte-match-paren
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
                (unless (cdr pairs)
                  (error "orbyte-define-keys: %S has an odd number of arguments"
                         group))
                (push `(keymap-set ,map ,(car pairs) ,(cadr pairs)) forms)
                (setq pairs (cddr pairs)))))
          (nreverse forms))))

;;;; States (three minor modes)

(defvar-local orbyte-mode-line-tag nil
  "Mode line tag for the active orbyte state, or nil.
Updated by `orbyte--update-ui'.")

(defun orbyte--state-lighter (mode)
  "Return MODE's lighter, with surrounding whitespace removed.
MODE is one of the orbyte state minor modes.  This follows the
`:lighter' value, so customising it also changes the mode line tag."
  (let ((lighter (cadr (assq mode minor-mode-alist))))
    (when lighter
      (let ((tag (if (stringp lighter) lighter (eval lighter))))
        (when (stringp tag)
          (string-trim tag))))))

(defun orbyte--update-ui ()
  "Update cursor shape and mode line tag for the current state."
  (if (or orbyte-normal-mode orbyte-insert-mode orbyte-motion-mode)
      (progn
        (setq-local cursor-type (if orbyte-insert-mode 'bar 'box))
        (setq orbyte-mode-line-tag
              (orbyte--state-lighter
               (cond (orbyte-insert-mode 'orbyte-insert-mode)
                     (orbyte-normal-mode 'orbyte-normal-mode)
                     (orbyte-motion-mode 'orbyte-motion-mode)))))
    (kill-local-variable 'cursor-type)
    (kill-local-variable 'orbyte-mode-line-tag)))

(define-minor-mode orbyte-normal-mode
  "Normal state: single-key motion/selection; native Emacs keys for editing."
  :lighter orbyte-normal-lighter
  :keymap orbyte-normal-map
  (if orbyte-normal-mode
      (progn
        ;; Keep line-wise selections aligned to whole lines, and drop
        ;; stale state when the mark is deactivated.
        (add-hook 'pre-command-hook #'orbyte--selection-pre-command nil t)
        (add-hook 'post-command-hook #'orbyte--linewise-refresh nil t)
        (add-hook 'deactivate-mark-hook #'orbyte--selection-clear nil t)
        (orbyte-insert-mode -1)
        (orbyte-motion-mode -1))
    (remove-hook 'pre-command-hook #'orbyte--selection-pre-command t)
    (remove-hook 'post-command-hook #'orbyte--linewise-refresh t)
    (remove-hook 'deactivate-mark-hook #'orbyte--selection-clear t)
    (orbyte--selection-clear))
  (orbyte--update-ui))

(define-minor-mode orbyte-motion-mode
  "Motion state: the leader in buffers that take no text input.
Used for buffers such as dired, help or magit, where letters do not
insert text.  Its keymap only holds the leader, so the buffer's own keys
keep working."
  :lighter orbyte-motion-lighter
  :keymap orbyte-motion-map
  (when orbyte-motion-mode
    (orbyte-normal-mode -1)
    (orbyte-insert-mode -1))
  (orbyte--update-ui))

(define-minor-mode orbyte-insert-mode
  "Insert state: native Emacs."
  :lighter orbyte-insert-lighter
  :keymap orbyte-insert-map
  (when orbyte-insert-mode
    (orbyte-normal-mode -1)
    (orbyte-motion-mode -1))
  (orbyte--update-ui))

;;;; The orbyte mode (one per buffer)

(defun orbyte--self-inserting-p ()
  "Return non-nil when plain letters insert text in the current buffer.
Remapped commands count as self-inserting, so terminals that remap
`self-insert-command' are recognised too.  The orbyte state keymaps are
ignored while checking, so re-enabling `orbyte-mode' in a buffer that is
already in Normal state does not mistake the orbyte bindings for buffer
bindings."
  (let ((orbyte-normal-mode nil)
        (orbyte-insert-mode nil)
        (orbyte-motion-mode nil))
    (and (seq-some
          (lambda (i)
            (let ((cmd (key-binding (vector i))))
              (and (symbolp cmd)
                   (string-match-p "self-insert" (symbol-name cmd)))))
          (number-sequence ?a ?z))
         t)))

(defun orbyte--switch-state (state)
  "Enable STATE and disable the other states.
Each state's minor-mode body already disables the other two, so only
the target state needs to be enabled.  With STATE nil, disable all three."
  (pcase state
    ('normal (orbyte-normal-mode 1))
    ('insert (orbyte-insert-mode 1))
    ('motion (orbyte-motion-mode 1))
    (_
     (orbyte-normal-mode -1)
     (orbyte-insert-mode -1)
     (orbyte-motion-mode -1))))

(define-minor-mode orbyte-mode
  "Modal editing for the current buffer.
This is the buffer-level switch used by `orbyte-global-mode'; the keys
come from `orbyte-normal-mode', `orbyte-insert-mode' or
`orbyte-motion-mode'.  The starting state is Normal for `orbyte-modes',
Motion for buffers where letters do not insert text (dired, help,
magit, ...), and none for everything else.  Re-enabling the mode keeps
the current state instead of choosing it again."
  :lighter nil
  (unless (and orbyte-mode
               (or orbyte-normal-mode orbyte-insert-mode orbyte-motion-mode))
    (orbyte--switch-state
     (and orbyte-mode
          (cond
           ((apply #'derived-mode-p orbyte-excluded-modes) nil)
           ((apply #'derived-mode-p orbyte-modes) 'normal)
           ((orbyte--self-inserting-p) nil)
           (t 'motion))))))

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
