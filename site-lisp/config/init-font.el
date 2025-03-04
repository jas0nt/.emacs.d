(defun load-font-setup()
  (set-face-attribute 'default nil :font "Recursive Mono Casual Static-18")
  (set-fontset-font
   t 'han
   (font-spec :name "Source Han Sans" :size 18))
  )

(load-font-setup)

(provide 'init-font)
