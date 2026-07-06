;;; early-init.el --- Early initialization before frame creation -*- lexical-binding: t -*-

;; Disable UI chrome before the first frame is created, preventing
;; the brief flash of tool-bar/menu-bar/scroll-bar on startup.
(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(blink-cursor-mode -1)

;; Start maximized.
(setq initial-frame-alist '((fullscreen . maximized)))

;; Uncomment to enable background transparency (0-100, lower = more transparent).
;; (set-frame-parameter nil 'alpha-background 75)

;; Prevent frame resizing when fonts or other settings change during startup.
(setq frame-inhibit-implied-resize t)

;; Use fundamental-mode as the default major mode to avoid unnecessary
;; mode initialization on startup.
(setq initial-major-mode 'fundamental-mode)

;; Prevent package.el from auto-initializing at startup; package management
(setq package-enable-at-startup nil
      package--init-file-ensured t)


;;; early-init.el ends here
