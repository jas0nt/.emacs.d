(defun load-font-setup()
  ;; 1. Set the main English/Code font
  (set-face-attribute 'default nil :font "Maple Mono NF-22")
  (add-to-list 'face-font-rescale-alist '("Maple Mono CN" . 1.00))

  ;; 2. Set the Chinese font
  (set-fontset-font
   t 'han
   (font-spec :name "Maple Mono CN"))

  ;; 3. Set the Nerd Font Icons
  ;; This tells Emacs to use Nerd Font for all "Symbol" characters
  (set-fontset-font
   t 'symbol
   (font-spec :family "Maple Mono NF"))

  ;; 4. Catch-all for the Private Use Area (where most Nerd Font icons live)
  (set-fontset-font
   t '(#xe000 . #xf8ff)
   (font-spec :family "Maple Mono NF"))
  )

(load-font-setup)


(provide 'init-font)
