;;; init-session.el --- Session persistence configuration -*- lexical-binding: t -*-

;; -----------------------------------------------------------------------
;; Desktop
;; -----------------------------------------------------------------------

;; Desktop restore is off on purpose: the dashboard, recentf and save-place
;; already cover "pick up where I left off", and restoring window layouts
;; fights with dired-tabs / project buffers.  `desktop-dirname' is still
;; pointed into cache/ by `my-set-cache-files' (init-generic.el), so turning
;; it back on needs no other change.
(desktop-save-mode -1)

;; -----------------------------------------------------------------------
;; Minibuffer / search history
;; -----------------------------------------------------------------------
(use-package savehist
  :init
  (savehist-mode))

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
