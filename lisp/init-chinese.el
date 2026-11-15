;;; init-chinese.el --- Chinese input methods -*- lexical-binding: t -*-

(use-package bing-dict
  :defer t)

(use-package fanyi
  :defer t)

;; pyim builds its dict tables and pinyin regexps when it loads (~50ms).
;; Nothing needs it before the first input-method switch.
(use-package pyim
  :defer t
  :init
  (setq pyim-default-scheme 'xiaohe-shuangpin)
  :config
  ;; 让 vertico 通过 orderless 支持拼音搜索候选项功能
  (defun my-orderless-regexp (orig_func component)
    (let ((result (funcall orig_func component)))
      (pyim-cregexp-build result)))
  (advice-add 'orderless-regexp :around #'my-orderless-regexp))

;; rime loads a dynamic module; `default-input-method' only stores a symbol,
;; so setting it here does not need rime to be loaded.
(use-package rime
  :defer t
  :init
  (setq default-input-method "rime"
        rime-show-candidate 'posframe)
  :config
  (custom-set-faces
   '(rime-default-face ((t (:background "#000000" :foreground "#bd93f9"))))
   '(rime-candidate-face ((t (:background "#282a36" :foreground "#bd93f9"))))
   '(rime-highlight-candidate-face ((t (:background "#ff79c6" :foreground "#f8f8f2"))))
   '(rime-code-face ((t (:foreground "#6272a4")))))

  (my-set-cache-files
   '(rime-user-data-dir "rime/"))

  (setq rime-share-data-dir "~/.local/share/fcitx5/rime"))

(provide 'init-chinese)
;;; init-chinese.el ends here
