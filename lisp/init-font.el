;;; init-font.el --- Font configuration -*- lexical-binding: t -*-

(defun my-font-setup ()
  "Configure fonts for the current frame.
Called both at startup (if a frame already exists) and whenever a
new frame is created, so that daemon mode works correctly."
  ;; 1. Main English / code font.
  (set-face-attribute 'default nil :font "Maple Mono NF-22")
  ;; 2. Chinese font scaling relative to the main font (1.00 = no scaling).
  ;;    Adjust this value to fine-tune Chinese/Latin alignment.
  (add-to-list 'face-font-rescale-alist '("Maple Mono CN" . 1.00))
  ;; 3. Chinese (Han) characters.
  (set-fontset-font t 'han (font-spec :name "Maple Mono CN"))
  ;; 4. Symbols — covers most Nerd Font glyphs.
  (set-fontset-font t 'symbol (font-spec :family "Maple Mono NF"))
  ;; 5. Private Use Area (U+E000–U+F8FF) — catch-all for remaining Nerd Font icons.
  (set-fontset-font t '(#xe000 . #xf8ff) (font-spec :family "Maple Mono NF")))

;; 让中文字体的 underline 位置更准确
(setq x-use-underline-position-properties nil)

;; Apply immediately if a graphical frame already exists (normal startup),
;; and register for future frames (daemon / emacsclient).
(if (display-graphic-p)
    (my-font-setup)
  (add-hook 'after-make-frame-functions
            (lambda (frame)
              (when (display-graphic-p frame)
                (with-selected-frame frame
                  (my-font-setup))))))

(provide 'init-font)
;;; init-font.el ends here
