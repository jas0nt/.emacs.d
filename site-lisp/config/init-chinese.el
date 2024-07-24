(use-package bing-dict)
(use-package fanyi)
(use-package ace-pinyin
  :config
  (ace-pinyin-global-mode +1))

(use-package pyim
   :init
   (pyim-default-scheme 'xiaohe-shuangpin)
   :config
   ;; 让 vertico 通过 orderless 支持拼音搜索候选项功能
   (defun my-orderless-regexp (orig_func component)
     (let ((result (funcall orig_func component)))
	(pyim-cregexp-build result)))
   (advice-add 'orderless-regexp :around #'my-orderless-regexp))


(provide 'init-chinese)
