(use-package bing-dict)
(use-package fanyi)

(use-package pyim
   :init
   (pyim-default-scheme 'xiaohe-shuangpin)
   :config
   ;; 让 vertico 通过 orderless 支持拼音搜索候选项功能
   (defun my-orderless-regexp (orig_func component)
     (let ((result (funcall orig_func component)))
	(pyim-cregexp-build result)))
   (advice-add 'orderless-regexp :around #'my-orderless-regexp))


(use-package rime
  :config
  (custom-set-faces
   '(rime-default-face ((t (:background "#000000" :foreground "#bd93f9"))))
   '(rime-candidate-face ((t (:background "#282a36" :foreground "#bd93f9"))))
   '(rime-highlight-candidate-face ((t (:background "#ff79c6" :foreground "#f8f8f2"))))
   '(rime-code-face ((t (:foreground "#6272a4")))))

  (my/set-cache-files
   '(rime-user-data-dir "rime/"))

  (setq rime-share-data-dir "~/.local/share/fcitx5/rime")

  (setq default-input-method "rime"
	rime-show-candidate 'posframe))


(provide 'init-chinese)
