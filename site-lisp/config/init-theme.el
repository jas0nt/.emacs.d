(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(setq-default cursor-type 'box)
(set-cursor-color "#50fa7b")
(blink-cursor-mode 0)

(require 'all-the-icons)
(require 'doom-modeline)

(defun load-font-setup()
  (cond ((eq window-system 'pgtk)
         (set-face-attribute 'default nil :height 140 :family "WenQuanYi Micro Hei Mono"))
        (t
         (let ((emacs-font-size 10)
               (chinese-font-name  "Source Han Sans")
               english-font-name)
           (cond
            ((featurep 'cocoa)
             (setq english-font-name "FiraCode Nerd Font"))
            ((string-equal system-type "gnu/linux")
             (setq english-font-name "FiraCode Nerd Font")))
           (when (display-grayscale-p)
             (set-frame-font (format "%s-%s" (eval english-font-name) (eval emacs-font-size)))
             (set-fontset-font (frame-parameter nil 'font) 'unicode (eval english-font-name))

             (dolist (charset '(kana han symbol cjk-misc bopomofo))
               (set-fontset-font (frame-parameter nil 'font) charset (font-spec :family (eval chinese-font-name))))
             )))))

(load-font-setup)
(load-theme 'dracula t)
(doom-modeline-mode 1)

(defconst jst/modeline-bg (face-attribute 'mode-line :background))
(defun jst/flash-mode-line ()
  (let ((bell-color "#ff5555"))
    (set-face-background 'mode-line bell-color)
    (run-with-timer 0.1 nil #'set-face-background 'mode-line jst/modeline-bg)))


(provide 'init-theme)