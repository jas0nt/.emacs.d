;;; init-session.el --- Session persistence configuration -*- lexical-binding: t -*-

;; -----------------------------------------------------------------------
;; Desktop (restores buffers, window layout, and point positions)
;; -----------------------------------------------------------------------

;; `desktop-dirname' is set by `my-set-cache-files' in init-generic.el,
;; which must be loaded before this file.
(setq desktop-path (list desktop-dirname)
      desktop-base-file-name "emacs-desktop"
      desktop-save t
      desktop-load-locked-desktop t
      desktop-auto-save-timeout 30)

(desktop-save-mode 1)

;; -----------------------------------------------------------------------
;; Cursor position persistence (per file)
;; -----------------------------------------------------------------------

(save-place-mode 1)

;; -----------------------------------------------------------------------
;; Recent files
;; -----------------------------------------------------------------------

;; Required by `consult-recent-file' (used in init-keys.el).
(recentf-mode 1)
(setq recentf-max-saved-items 500
      recentf-max-menu-items 25)

(provide 'init-session)
;;; init-session.el ends here
