;;; init.el --- Emacs entry point -*- lexical-binding: t -*-

;; -----------------------------------------------------------------------
;; Load Path Setup
;; -----------------------------------------------------------------------
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

(let ((site-lisp-dir (expand-file-name "site-lisp" user-emacs-directory)))
  (when (file-directory-p site-lisp-dir)
    (add-to-list 'load-path site-lisp-dir)
    (let ((default-directory site-lisp-dir))
      (normal-top-level-add-subdirs-to-load-path))))

;; -----------------------------------------------------------------------
;; Bootstrap
;; -----------------------------------------------------------------------
(require 'init-font)

;; -----------------------------------------------------------------------
;; Core modules
;; -----------------------------------------------------------------------
(require 'init-proxy)
(require 'init-pkgs)
(require 'init-theme)
(require 'init-generic)
(require 'init-session)
(require 'init-buffer)
(require 'init-common)
(require 'init-keys)
;; (require 'init-evil)
(require 'init-meow)
(require 'init-completion)
(require 'init-chinese)
(require 'init-edit)
(require 'init-media)
(require 'init-dired)
(require 'init-project)
(require 'init-vc)
(require 'init-dashboard)
(require 'init-python)
(require 'init-rust)
(require 'init-lsp)
(require 'init-other)

;; -----------------------------------------------------------------------
;; Deferred modules: loaded after 1 second of idle time
;; -----------------------------------------------------------------------
(run-with-idle-timer
 1 nil
 (lambda ()
   (require 'init-idle)
   (require 'init-term)
   (require 'init-system)
   (require 'init-music)))

;;; init.el ends here
