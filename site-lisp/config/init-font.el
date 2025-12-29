(defun load-font-setup()
  ;; 1. Set the main English/Code font
  (set-face-attribute 'default nil :font "Recursive Mono Casual Static-20")

  ;; 2. Set the Chinese font
  (set-fontset-font
   t 'han
   (font-spec :name "Source Han Sans" :size 22))

  ;; 3. Set the Nerd Font Icons
  ;; This tells Emacs to use FiraCode Nerd Font for all "Symbol" characters
  (set-fontset-font
   t 'symbol
   (font-spec :family "FiraCode Nerd Font Mono Regular" :size 18))

  ;; 4. Catch-all for the Private Use Area (where most Nerd Font icons live)
  (set-fontset-font
   t '(#xe000 . #xf8ff)
   (font-spec :family "FiraCode Nerd Font Mono Regular" :size 18))
  )

(load-font-setup)


(provide 'init-font)
