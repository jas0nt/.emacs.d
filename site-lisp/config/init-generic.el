;; 增加IO性能
(setq process-adaptive-read-buffering nil)
(setq read-process-output-max (* 1024 1024))

(fset 'yes-or-no-p 'y-or-n-p)           ;以 y/n代表 yes/no
(blink-cursor-mode -1)                  ;指针不闪动
(transient-mark-mode 1)                 ;标记高亮
(global-subword-mode 1)                 ;Word移动支持 FooBar 的格式
(setq use-dialog-box nil)               ;never pop dialog
(setq inhibit-startup-screen t)         ;inhibit start screen
(setq initial-scratch-message "")       ;关闭启动空白buffer, 这个buffer会干扰session恢复
(setq-default comment-style 'indent)    ;设定自动缩进的注释风格
;(setq ring-bell-function 'ignore)       ;关闭烦人的出错时的提示声
(setq default-major-mode 'text-mode)    ;设置默认地主模式为TEXT模式
(setq mouse-yank-at-point t)            ;粘贴于光标处,而不是鼠标指针处
(setq x-select-enable-clipboard t)      ;支持emacs和外部程序的粘贴
(setq split-width-threshold nil)        ;分屏的时候使用上下分屏
(setq inhibit-compacting-font-caches t) ;使用字体缓存，避免卡顿
(setq confirm-kill-processes nil)       ;退出自动杀掉进程
(setq async-bytecomp-allowed-packages nil) ;避免magit报错
(setq word-wrap-by-category t)             ;按照中文折行
(add-hook 'find-file-hook 'rainbow-mode t) ;增强的括号高亮

(setq completion-auto-select nil)       ;避免默认自动选择

(setq ad-redefinition-action 'accept)   ;不要烦人的 redefine warning
(setq frame-resize-pixelwise t) ;设置缩放的模式,避免Mac平台最大化窗口以后右边和下边有空隙

(recentf-mode 1)
(setq recentf-max-menu-items 25)

;; 对大文件或超长行提供性能优化
(setq-default bidi-display-reordering nil)
(setq-default bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t
      long-line-threshold 1000
      large-hscroll-threshold 1000
      syntax-wholeline-max 1000)

;; 平滑地进行半屏滚动，避免滚动后recenter操作
(setq scroll-step 1
      scroll-conservatively 10000)


(prefer-coding-system 'utf-8)
(setq locale-coding-system 'utf-8)
(set-language-environment 'utf-8)
(set-default-coding-systems 'utf-8)
(set-buffer-file-coding-system 'utf-8)
(set-clipboard-coding-system 'utf-8)
(set-file-name-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-selection-coding-system 'utf-8)
(modify-coding-system-alist 'process "*" 'utf-8)


(defvar my-emacs-cache-dir (expand-file-name "cache/" user-emacs-directory)
  "存放 Emacs 插件缓存文件的目录。")

(unless (file-exists-p my-emacs-cache-dir)
  (make-directory my-emacs-cache-dir t))

(defun my/set-cache-files (&rest file-specs)
  "批量设置缓存文件路径，自动确保所在目录存在。
FILE-SPECS 是 (变量 文件名) 形式的列表。"
  (dolist (spec file-specs)
    (let* ((var (car spec))
           (file-path (expand-file-name (cadr spec) my-emacs-cache-dir))
           (dir-path (file-name-directory file-path)))
      ;; 自动创建目录（如果不存在）
      (unless (file-exists-p dir-path)
        (make-directory dir-path t))
      ;; 设置变量
      (set var file-path))))

(my/set-cache-files
 '(custom-file "custom.el")
 '(bookmark-default-file "bookmarks")
 '(transient-levels-file "transient/levels.el")
 '(transient-values-file "transient/values.el")
 '(transient-history-file "transient/history.el")
 '(url-configuration-directory "url/"))


(load custom-file :noerror)


(provide 'init-generic)
