;;; dired-shortcuts.el --- Copy, jump and open shortcuts for Dired -*- lexical-binding: t; -*-

;;; Commentary:

;; Three small "one keystroke" conveniences for `dired-mode', each with
;; its own transient menu:
;;
;; 1. `dired-shortcuts-copy-transient': copy paths/names to the kill ring.
;;    Works on all marked files (or the file at point), in plain, shell-
;;    quoted and project-relative forms.
;;
;; 2. `dired-shortcuts-goto-transient': jump to frequently used
;;    directories, like Yazi's `g' menu.  The list is the customizable
;;    `dired-shortcuts-goto-locations'.  When
;;    `dired-kill-when-opening-new-dired-buffer' is set, jumping replaces
;;    the current Dired buffer instead of piling up a new one.
;;
;; 3. `dired-shortcuts-open-transient': open the file(s) at point with the
;;    default application, open a terminal here, or open the current
;;    directory in a graphical file manager.
;;
;; None of the features depends on another.

;;; Code:

(require 'transient)
(require 'dired)
(require 'project)
(require 'seq)
(require 'subr-x)

(defgroup dired-shortcuts nil
  "Copy, jump and open shortcuts for Dired."
  :group 'dired)

;;; -----------------------------------------------------------------------
;;; Shared helpers
;;; -----------------------------------------------------------------------

(defun dired-shortcuts--targets ()
  "Return the absolute paths the next command should act on.
That is every marked file, or the file at point if nothing is marked.
Falls back to `default-directory' if point is not on a file line."
  (mapcar #'expand-file-name
          (or (ignore-errors (dired-get-marked-files))
              (list default-directory))))

(defun dired-shortcuts--spawn (command &rest args)
  "Start COMMAND in the background, passing ARGS.
COMMAND is a string that may carry its own arguments (e.g. \"open -a
Terminal\").  The process runs asynchronously and its output is
discarded, so a terminal or viewer that stays open never blocks Emacs."
  (when (file-remote-p default-directory)
    (user-error "Not supported on remote (TRAMP) directories"))
  (let* ((parts (split-string-and-unquote command))
         (program (car parts)))
    (unless (and program (executable-find program))
      (user-error "Program not found: %s (see `dired-shortcuts' options)" program))
    (make-process :name (file-name-nondirectory program)
                  :command (append (list program) (cdr parts) args)
                  :buffer nil
                  :noquery t
                  :sentinel #'ignore)))

;;; -----------------------------------------------------------------------
;;; 1. Copy name / path variants
;;; -----------------------------------------------------------------------

(defcustom dired-shortcuts-copy-separator "\n"
  "String placed between entries when several files are copied at once.
Shell-quoted paths are always joined with a single space instead."
  :type 'string
  :group 'dired-shortcuts)

(defun dired-shortcuts--kill (label strings &optional separator)
  "Put STRINGS on the kill ring, joined by SEPARATOR, and report with LABEL."
  (let ((text (mapconcat #'identity strings
                         (or separator dired-shortcuts-copy-separator))))
    (kill-new text)
    (if (cdr strings)
        (message "Copied %s (%d items)" label (length strings))
      (message "Copied %s: %s" label text))))

(defun dired-shortcuts--project-relative (file)
  "Return FILE relative to its project root, or to `default-directory'."
  (let ((root (if-let* ((pr (project-current)))
                  (expand-file-name (project-root pr))
                default-directory)))
    (file-relative-name file root)))

(defun dired-shortcuts-copy-file-path ()
  "Copy the full absolute path of the marked files (or the file at point)."
  (interactive)
  (dired-shortcuts--kill "path" (dired-shortcuts--targets)))

(defun dired-shortcuts-copy-file-name ()
  "Copy the name (with extension) of the marked files (or the file at point)."
  (interactive)
  (dired-shortcuts--kill
   "name"
   (mapcar (lambda (f) (file-name-nondirectory (directory-file-name f)))
           (dired-shortcuts--targets))))

(defun dired-shortcuts-copy-file-name-no-ext ()
  "Copy the name (without extension) of the marked files (or the file at point)."
  (interactive)
  (dired-shortcuts--kill
   "name (no ext)"
   (mapcar (lambda (f) (file-name-base (directory-file-name f)))
           (dired-shortcuts--targets))))

(defun dired-shortcuts-copy-directory ()
  "Copy the parent directory of the marked files (or the file at point)."
  (interactive)
  (dired-shortcuts--kill
   "directory"
   (delete-dups (mapcar #'file-name-directory (dired-shortcuts--targets)))))

(defun dired-shortcuts-copy-shell-quoted-path ()
  "Copy shell-quoted absolute paths, space-separated, ready to paste in a shell."
  (interactive)
  (dired-shortcuts--kill
   "quoted path"
   (mapcar #'shell-quote-argument (dired-shortcuts--targets))
   " "))

(defun dired-shortcuts-copy-relative-path ()
  "Copy paths relative to the project root (or the current directory)."
  (interactive)
  (dired-shortcuts--kill
   "relative path"
   (mapcar #'dired-shortcuts--project-relative (dired-shortcuts--targets))))

;;;###autoload (autoload 'dired-shortcuts-copy-transient "dired-shortcuts" nil t)
(transient-define-prefix dired-shortcuts-copy-transient ()
  "Copy file name/path variants menu."
  ["Copy"
   :if-derived 'dired-mode
   ("c" "Do Copy"            dired-do-copy)
   ("F" "Full path"          dired-shortcuts-copy-file-path)
   ("q" "Full path (quoted)" dired-shortcuts-copy-shell-quoted-path)
   ("r" "Relative path"      dired-shortcuts-copy-relative-path)
   ("f" "File name"          dired-shortcuts-copy-file-name)
   ("n" "File name (no ext)" dired-shortcuts-copy-file-name-no-ext)
   ("d" "Directory"          dired-shortcuts-copy-directory)])

;;; -----------------------------------------------------------------------
;;; 2. Go to a frequently used directory
;;; -----------------------------------------------------------------------

(defun dired-shortcuts--removable-media-dir ()
  "Return the directory under which removable drives are mounted.
udisks mounts them at /run/media/USER (/media/USER on older Debian-like
systems); fall back to the parent directory if neither exists."
  (let ((user (user-login-name)))
    (or (seq-find #'file-directory-p
                  (list (format "/run/media/%s" user)
                        (format "/media/%s" user)))
        (seq-find #'file-directory-p '("/run/media" "/media"))
        "/run/media")))

(defcustom dired-shortcuts-goto-locations
  `(("h" "Home"      "~")
    ("d" "Downloads" "~/Downloads")
    ("D" "Documents" "~/Documents")
    ("c" "Config"    "~/.config")
    ("x" "drives"    ,(dired-shortcuts--removable-media-dir))
    ("t" "Trash"     "~/.local/share/Trash/files")
    ("e" "/etc"      "/etc")
    ("/" "Root"      "/"))
  "Directories offered by `dired-shortcuts-goto-transient'.
Each entry is (KEY LABEL DIRECTORY).  Keys must be unique.  The menu is
rebuilt every time it opens, so changes take effect immediately."
  :type '(repeat (list (string :tag "Key")
                       (string :tag "Label")
                       (directory :tag "Directory")))
  :group 'dired-shortcuts)

(defun dired-shortcuts-goto (dir)
  "Visit DIR in Dired.
From a Dired buffer with `dired-kill-when-opening-new-dired-buffer'
set, the current buffer is replaced (like RET and `^' do) instead of
leaving one more Dired buffer behind."
  (let ((target (expand-file-name dir)))
    (unless (file-directory-p target)
      (user-error "Directory does not exist: %s" (abbreviate-file-name target)))
    (if (and (derived-mode-p 'dired-mode)
             (bound-and-true-p dired-kill-when-opening-new-dired-buffer))
        (find-alternate-file target)
      (dired target))
    (when (and (bound-and-true-p dired-preview-global-mode)
               (fboundp 'dired-preview-trigger))
      (dired-preview-trigger t))
    (message "Went to %s" (abbreviate-file-name target))))

(defun dired-shortcuts--goto-children (_group)
  "Build the suffixes of `dired-shortcuts-goto-transient' from the location list."
  (transient-parse-suffixes
   'dired-shortcuts-goto-transient
   (mapcar
    (lambda (loc)
      (pcase-let ((`(,key ,label ,dir) loc))
        ;; One named command per entry: transient needs symbols, and the
        ;; closure remembers its directory.
        (let ((cmd (intern (format "dired-shortcuts-goto--%s" key))))
          (defalias cmd (lambda () (interactive) (dired-shortcuts-goto dir)))
          (list key label cmd))))
    dired-shortcuts-goto-locations)))

;;;###autoload (autoload 'dired-shortcuts-goto-transient "dired-shortcuts" nil t)
(transient-define-prefix dired-shortcuts-goto-transient ()
  "Jump to a frequently used directory."
  [:class transient-column
   :description "Go to"
   :if-derived 'dired-mode
   :setup-children dired-shortcuts--goto-children])

;;; -----------------------------------------------------------------------
;;; 3. Open externally
;;; -----------------------------------------------------------------------

(defcustom dired-shortcuts-open-command
  (if (eq system-type 'darwin) "open" "xdg-open")
  "Command used to open a file with its default application."
  :type 'string
  :group 'dired-shortcuts)

(defcustom dired-shortcuts-terminal-command nil
  "Command used to open a terminal in the current directory.
The terminal is started with the Dired directory as its working
directory, and the command may carry its own arguments.  If nil, the
command is detected each time it is needed: `open -a Terminal' on macOS,
else $TERMINAL, else the first installed of a list of common terminals.
\(Detection happens at use time, because an Emacs started from a desktop
launcher often has no $TERMINAL at load time.)"
  :type '(choice (const :tag "Auto-detect" nil) string)
  :group 'dired-shortcuts)

(defcustom dired-shortcuts-file-manager-command
  (if (eq system-type 'darwin) "open" "pcmanfm")
  "Command used to open the current directory in a graphical file manager."
  :type 'string
  :group 'dired-shortcuts)

(defcustom dired-shortcuts-open-confirm-threshold 5
  "Ask for confirmation when opening more than this many files at once."
  :type 'integer
  :group 'dired-shortcuts)

(defun dired-shortcuts--terminal-command ()
  "Return the terminal command to use, detecting it if necessary."
  (or dired-shortcuts-terminal-command
      (and (eq system-type 'darwin) "open -a Terminal")
      (let ((env (getenv "TERMINAL")))
        (and env (not (string-empty-p env)) env))
      (seq-find #'executable-find
                '("x-terminal-emulator" "kitty" "alacritty" "foot" "wezterm"
                  "gnome-terminal" "konsole" "xfce4-terminal" "xterm"))
      (user-error "No terminal found; set `dired-shortcuts-terminal-command'")))

(defun dired-shortcuts-open-external ()
  "Open the marked files (or the file at point) with the default application."
  (interactive)
  (let ((files (dired-shortcuts--targets)))
    (when (and (> (length files) dired-shortcuts-open-confirm-threshold)
               (not (y-or-n-p (format "Open %d files? " (length files)))))
      (user-error "Cancelled"))
    (dolist (f files)
      (dired-shortcuts--spawn dired-shortcuts-open-command f))
    (message "Opened %d file(s) with %s"
             (length files) dired-shortcuts-open-command)))

(defun dired-shortcuts-open-terminal ()
  "Open a terminal in the current Dired directory."
  (interactive)
  (let ((default-directory (dired-current-directory)))
    (dired-shortcuts--spawn (dired-shortcuts--terminal-command))
    (message "Terminal started in %s" (abbreviate-file-name default-directory))))

(defun dired-shortcuts-open-file-manager ()
  "Open the current Dired directory in the graphical file manager."
  (interactive)
  (let ((dir (dired-current-directory)))
    (dired-shortcuts--spawn dired-shortcuts-file-manager-command dir)
    (message "Opened %s in %s"
             (abbreviate-file-name dir) dired-shortcuts-file-manager-command)))

;;;###autoload (autoload 'dired-shortcuts-open-transient "dired-shortcuts" nil t)
(transient-define-prefix dired-shortcuts-open-transient ()
  "Open externally menu."
  ["Open"
   :if-derived 'dired-mode
   ("o" "Default application" dired-shortcuts-open-external)
   ("t" "Terminal here"       dired-shortcuts-open-terminal)
   ("m" "File manager"        dired-shortcuts-open-file-manager)])

(provide 'dired-shortcuts)

;;; dired-shortcuts.el ends here
