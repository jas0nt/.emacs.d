(require 'package)
;;elpa
(setq package-archives '(("gnu"   . "http://elpa.emacs-china.org/gnu/")
			 ("melpa" . "http://elpa.emacs-china.org/melpa/")))
(package-initialize)

;;load path
(defun add-subdirs-to-load-path (dir)
    "Recursive add directories to `load-path'."
      (let ((default-directory (file-name-as-directory dir)))
	    (add-to-list 'load-path dir)
	        (normal-top-level-add-subdirs-to-load-path)))

(add-subdirs-to-load-path "~/.emacs.d/lisp")


;;custom file
(setq custom-file (expand-file-name "lisp/custom.el" user-emacs-directory))
(load-file custom-file)

(require 'init-config)
(require 'init-ui)
(require 'init-package)
(require 'init-key-binding)

;;packages
;;(require 'eaf)
