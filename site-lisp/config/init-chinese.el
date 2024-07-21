(require 'bing-dict)
(require 'fanyi)

(require 'ace-pinyin)
(ace-pinyin-global-mode +1)

(require 'pyim)
(pyim-default-scheme 'xiaohe-shuangpin)

(defun my-orderless-regexp (orig_func component)
    (let ((result (funcall orig_func component)))
	(pyim-cregexp-build result)))
(advice-add 'orderless-regexp :around #'my-orderless-regexp)


(provide 'init-chinese)