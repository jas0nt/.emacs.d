;;; init-accelerate.el --- Early startup optimizations -*- lexical-binding: t -*-

;; Prevent frame resizing when fonts or other settings change during startup.
;; Also set in init-all.el's let block; kept here so it applies as early
;; as possible before that block runs.
(setq frame-inhibit-implied-resize t)

;; Use fundamental-mode as the default major mode to avoid unnecessary
;; mode initialization on startup.
(setq initial-major-mode 'fundamental-mode)

;; Prevent package.el from auto-initializing at startup; package management
;; is handled externally (Nix / explicit calls).
(setq package-enable-at-startup nil
      package--init-file-ensured t)

(provide 'init-accelerate)
;;; init-accelerate.el ends here
