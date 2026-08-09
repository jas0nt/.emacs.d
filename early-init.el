;;; early-init.el --- Early initialization before frame creation -*- lexical-binding: t -*-

;; GC: raise threshold during startup, restore after.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 100 1024 1024) ; 100MB
                  gc-cons-percentage 0.1)))

;; UI chrome: set frame parameters directly instead of calling
;; tool-bar-mode/menu-bar-mode/scroll-bar-mode, so the first frame
;; is created in its final state with no flash and no extra library loads.
(push '(menu-bar-lines . 0)   default-frame-alist)
(push '(tool-bar-lines . 0)   default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(push '(fullscreen . maximized) default-frame-alist)

(setq initial-frame-alist default-frame-alist)

;; (push '(alpha-background . 75) default-frame-alist) ; transparency, 0-100

(blink-cursor-mode -1)

;; Skip implied resizing and heavy default major mode.
(setq frame-inhibit-implied-resize t)
(setq initial-major-mode 'fundamental-mode)

;; Skip splash screen and startup echo message.
(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name)

;; Defer package.el initialization to init.el.
(setq package-enable-at-startup nil)

;; Silence native-comp async warnings/errors buffer popups.
(setq native-comp-async-report-warnings-errors 'silent)

;;; early-init.el ends here
