;;; init-all.el --- Main entry point: load all modules -*- lexical-binding: t -*-

;; Load font and accelerator settings before the startup optimization block,
;; so font rendering is correct from the first frame.
(require 'init-font)
(require 'init-accelerate)

;; -----------------------------------------------------------------------
;; Startup Performance Block
;; Temporarily raise GC threshold and suppress redisplay/messages to
;; speed up startup. Both are restored after the window is ready.
;; -----------------------------------------------------------------------
(let ((gc-cons-threshold most-positive-fixnum)
      (gc-cons-percentage 0.6)
      (file-name-handler-alist nil)) ; Avoid analysing remote file names during load

  ;; Suppress frame resizing and redisplay flicker during startup.
  (setq frame-inhibit-implied-resize t)
  (setq-default inhibit-redisplay t
                inhibit-message t)
  (add-hook 'window-setup-hook
            (lambda ()
              (setq-default inhibit-redisplay nil
                            inhibit-message nil)
              (redisplay)))

  ;; -----------------------------------------------------------------------
  ;; Core modules
  ;; -----------------------------------------------------------------------
  (require 'init-proxy)
  (require 'init-pkgs)
  (require 'init-theme)
  (require 'init-generic)
  (require 'init-buffer)
  (require 'init-common)
  (require 'init-keys)
  ;; (require 'init-evil)
  (require 'init-meow)
  (require 'init-completion)
  (require 'init-chinese)
  (require 'init-edit)
  (require 'init-dired)
  (require 'init-project)
  (require 'init-vc)
  (require 'init-dashboard)
  (require 'init-python)
  (require 'init-rust)
  (require 'init-lsp)
  (require 'init-other)

  ;; -----------------------------------------------------------------------
  ;; Post-startup: reset GC to a reasonable steady-state value
  ;; -----------------------------------------------------------------------
  (add-hook 'emacs-startup-hook
            (lambda ()
              (setq gc-cons-threshold (* 100 1024 1024) ; 100MB
                    gc-cons-percentage 0.1)))

  ;; -----------------------------------------------------------------------
  ;; Deferred modules: loaded after 1 second of idle time
  ;; -----------------------------------------------------------------------
  (run-with-idle-timer
   1 nil
   (lambda ()
     (require 'init-idle)
  (require 'init-session)
     (require 'init-music))))

(provide 'init-all)
;;; init-all.el ends here
