;;; init-dired.el --- Dired configuration -*- lexical-binding: t -*-

;;; Commentary:

;; Helper functions, the transient menu and the zoxide/preview/thumbnail
;; glue live at top level (before the `use-package' forms), so they are
;; byte-compilable and `my-*' names exist before any key refers to them.
;;
;; `dired-tabs' and `dired-shortcuts' stay `:demand t' on purpose:
;; dired-tabs advises `dired' and must be active before the first call,
;; and dired-shortcuts commands are bound from the `dired' block below.
;; If startup time matters, measure with `use-package-compute-statistics'
;; before changing that.

;;; Code:

(require 'transient)

(defvar my-emacs-cache-dir)

;; Declared special so that `my-dired-do-open-current-only' below can bind it
;; dynamically (a plain `let' would create a lexical binding and the callee
;; would still see the default marker char).
(defvar dired-marker-char)

;; Defined in the user's own ready-player glue config.
;; (declare-function my-ready-player--adjust-thumbnail-percent "...")
;; (declare-function my-ready-player-batch-generate-thumbnails "...")
(declare-function ready-player--cached-thumbnail-path "ready-player")
(declare-function zoxide-open-with "zoxide")

;; -----------------------------------------------------------------------
;; Small commands
;; -----------------------------------------------------------------------

(defun my-dired-here ()
  "Open Dired in `default-directory'."
  (interactive)
  (dired default-directory))

(defun my-dired-do-open-current-only ()
  "Open the file at point using an external app, ignoring any marked files.
`dired-do-open' needs Emacs 29+.  A NUL marker char matches no line, so
`dired-get-marked-files' falls back to the file at point."
  (interactive)
  (let ((dired-marker-char ?\0))
    (dired-do-open)))

(defun my-dired-k ()
  "Run `dired-k' only inside a git repository.
Media directories have no VCS, so `dired-k' would shell out for nothing."
  (interactive)
  (if (locate-dominating-file default-directory ".git")
      (dired-k)
    (user-error "Not a git repository: %s" default-directory)))

(defun my-dired-jump-with-zoxide ()
  "Jump to a zoxide directory, replacing the current Dired buffer."
  (interactive)
  (require 'zoxide)
  (zoxide-open-with nil (lambda (file) (find-alternate-file file)) t))

;; Named commands for the thumbnail group of the menu below (easier to
;; debug than anonymous lambdas).
(defun my-dired-thumbnail-forward-5 ()
  (interactive) (my-ready-player--adjust-thumbnail-percent 5))
(defun my-dired-thumbnail-backward-5 ()
  (interactive) (my-ready-player--adjust-thumbnail-percent -5))
(defun my-dired-thumbnail-forward-1 ()
  (interactive) (my-ready-player--adjust-thumbnail-percent 1))
(defun my-dired-thumbnail-backward-1 ()
  (interactive) (my-ready-player--adjust-thumbnail-percent -1))

;; -----------------------------------------------------------------------
;; Misc toggles menu
;; -----------------------------------------------------------------------

(transient-define-prefix my-dired-toggle-transient ()
  [
   ["Toggle"
    :if-derived 'dired-mode
    ("t" "Tab new"     dired-tabs-new)
    ("c" "Tab close"   dired-tabs-close)
    ("T" "thumbnail"   media-thumbnail-dired-mode)
    ("d" "detail"      dired-hide-details-mode)
    ("u" "du"          dired-du-mode)
    ("g" "git"         my-dired-k)
    ("p" "preview"     dired-preview-global-mode)
    ("s" "script mode" satchel-toggle-script-mode)]
   ["Thumbnail"
    :if-derived 'dired-mode
    ("j" "Next Line"      dired-next-line :transient t)
    ("k" "Prev Line"      dired-previous-line :transient t)
    ("l" "Forward 5%"     my-dired-thumbnail-forward-5 :transient t)
    ("h" "Backward 5%"    my-dired-thumbnail-backward-5 :transient t)
    ("L" "Forward 1%"     my-dired-thumbnail-forward-1 :transient t)
    ("H" "Backward 1%"    my-dired-thumbnail-backward-1 :transient t)
    ("P" "batch generate" my-ready-player-batch-generate-thumbnails)]
   ["Actions"
    ("q" "Quit" transient-quit-all)]
   ])

;; -----------------------------------------------------------------------
;; Glue for media-thumbnail / dired-preview
;; -----------------------------------------------------------------------

(defun my-media-thumbnail-get-cache-path (file)
  "Reuse `ready-player's thumbnail cache path/naming, so both
packages share the exact same cached thumbnail file on disk."
  ;; Load ready-player lazily: its private function is only needed when a
  ;; thumbnail path is actually requested.
  (unless (fboundp 'ready-player--cached-thumbnail-path)
    (require 'ready-player))
  (ready-player--cached-thumbnail-path (expand-file-name file)))

(defun my-dired-preview-to-the-right ()
  "Display dired-preview window on the right side."
  `((display-buffer-in-side-window)
    (side . right)
    (slot . 0)
    (window-width . 0.45)
    (preserve-size . (t . nil))))

;; -----------------------------------------------------------------------
;; Packages
;; -----------------------------------------------------------------------

(use-package dired
  :ensure nil ; Built-in package
  :init
  ;; `--group-directories-first' needs GNU ls; macOS ships BSD ls.
  (when (and (eq system-type 'darwin) (executable-find "gls"))
    (setq insert-directory-program (executable-find "gls")))
  (setq dired-tabs-kill-old-buffer t)
  :custom
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-movement-style 'bounded-files)
  (dired-dwim-target t)
  (dired-listing-switches
   "-l --almost-all --human-readable --group-directories-first --no-group")
  (ls-lisp-use-insert-directory-program t)
  (dired-free-space nil)
  ;; Sensible defaults.
  (dired-auto-revert-buffer nil)
  (dired-recursive-copies 'always)
  (dired-recursive-deletes 'top)
  (dired-create-destination-dirs 'ask)
  ;; Also makes dired-satchel's script use a trash command, so SCRIPT and
  (delete-by-moving-to-trash nil)
  :hook (dired-mode . hl-line-mode)
  :bind
  ("C-x C-d" . my-dired-here)
  (:map dired-mode-map
        ("<SPC>" . evil-keypad-start)
        ("q"     . dired-tabs-toggle)
        ("<f5>"  . revert-buffer)
        ("C"     . dired-do-compress-to)
        ("t"     . my-dired-toggle-transient)

        ;; Navigation
        ("h" . dired-up-directory)
        ("j" . dired-next-line)
        ("J" . (lambda () (interactive) (dired-next-line 5)))
        ("k" . dired-previous-line)
        ("K" . (lambda () (interactive) (dired-previous-line 5)))
        ("l" . dired-find-file)
        ("]" . pixel-scroll-interpolate-down)
        ("[" . pixel-scroll-interpolate-up)
        ("'" . bookmark-jump)
        ("z" . my-dired-jump-with-zoxide)
        ("/" . consult-line)
        ("G" . avy-goto-line)
        ("f" . consult-fd)

        ;; Open
        ("<RET>"      . my-dired-do-open-current-only)
        ("C-<return>" . dired-do-open)
        ("`"          . dired-shortcuts-open-terminal)
        ("O"          . dired-do-shell-command)

        ;; Create
        ("a" . dired-create-empty-file)
        ("A" . dired-create-directory)

        ;; Edit mode
        ("r" . wdired-change-to-wdired-mode)))

(use-package dired-shortcuts
  :ensure nil
  :load-path "site-lisp"
  :demand t
  :after dired
  :bind
  (:map dired-mode-map
        ("c" . dired-shortcuts-copy-transient)
        ("n" . dired-shortcuts-goto-transient)
        ("o" . dired-shortcuts-open-transient)))

(use-package dired-tabs
  :ensure nil
  :load-path "site-lisp"
  :demand t
  :custom
  (dired-tabs-save-file (expand-file-name "dired-tabs" my-emacs-cache-dir))
  ;; Replace the old Dired buffer on tab switch, like RET/`^' do.
  (dired-tabs-kill-old-buffer t)
  :bind
  (:map dired-mode-map
        ("1" . dired-tabs-goto) ("2" . dired-tabs-goto) ("3" . dired-tabs-goto)
        ("4" . dired-tabs-goto) ("5" . dired-tabs-goto) ("6" . dired-tabs-goto)
        ("7" . dired-tabs-goto) ("8" . dired-tabs-goto) ("9" . dired-tabs-goto)
        ("0" . dired-tabs-goto) ("H" . dired-tabs-prev) ("L" . dired-tabs-next)
        ("{" . dired-tabs-move-left) ("}" . dired-tabs-move-right)))

(use-package dired-satchel
  :ensure nil
  :load-path "site-lisp"
  :after dired
  :commands (satchel-toggle-script-mode)
  :bind
  (:map dired-mode-map
        ("d" . satchel-action-flag-deletion)
        ("y" . satchel-pack)
        ("x" . satchel-cut)
        ("Y" . satchel-unpack)
        ("p" . satchel-action-paste)
        ("v" . satchel-transient)))

(use-package media-thumbnail
  :after dired
  :custom
  (media-thumbnail-max-processes 4)
  (media-thumbnail-cache-dir
   (expand-file-name "media-thumbnails/" my-emacs-cache-dir))
  :config
  ;; Bound the generated image the same way the ready-player pipeline does.
  ;; The default 0 means "original size", which for a 4K film writes a
  ;; full-resolution JPEG that dired then displays at 150px.
  (setq media-thumbnail-size my-ready-player-thumbnail-size)
  ;; `:config' already runs after the package is loaded.
  (advice-add 'media-thumbnail-get-cache-path :override
              #'my-media-thumbnail-get-cache-path))

(use-package dired-preview
  :after dired
  :custom
  (dired-preview-delay 0.3)
  ;; 50MB on purpose: every video here is several GB, and auto-previewing
  ;; them would spawn a decoder on every cursor move.  Videos are opened
  ;; with RET into ready-player instead, which uses the cached thumbnail.
  (dired-preview-max-size (* 50 1024 1024))
  (dired-preview-display-action-alist #'my-dired-preview-to-the-right)
  :config
  (dolist (cmd '(revert-buffer
                 satchel-action-flag-deletion
                 dired-tabs-goto
                 dired-tabs-prev
                 dired-tabs-next))
    (add-to-list 'dired-preview-trigger-commands cmd t))
  (dired-preview-global-mode 1))

(use-package dired-du
  :after dired
  :commands dired-du-mode
  :custom
  (dired-du-size-format t))

(use-package dired-quick-sort
  :after dired
  :config
  ;; The package's setup function installs its hooks; plain
  ;; `dired-quick-sort' is the sorting command itself.
  (dired-quick-sort-setup)
  :bind
  (:map dired-mode-map
        ("," . dired-quick-sort-transient)))

(use-package dired-k
  :commands dired-k
  :custom
  (dired-k-style 'git))

(use-package zoxide
  :defer t
  :commands zoxide-open-with)

(provide 'init-dired)
;;; init-dired.el ends here
