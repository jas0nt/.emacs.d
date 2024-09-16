(defun load-font-setup()
  (cond ((eq window-system 'pgtk)
         (set-face-attribute 'default nil :height 140 :family "WenQuanYi Micro Hei Mono"))
        (t
         (let ((emacs-font-size 15)
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

(provide 'init-font)
