(custom-set-variables '(tramp-verbose 0)) ;设置tramp的响应方式, 关闭后不弹出消息
(setq max-lisp-eval-depth 40000)          ;lisp最大执行深度
(setq max-specpdl-size 10000)             ;最大容量
(setq kill-ring-max 1024) ;用一个很大的 kill ring. 这样防止我不小心删掉重要的东西
(setq mark-ring-max 1024) ;设置的mark ring容量
(setq eval-expression-print-length nil) ;设置执行表达式的长度没有限制
(setq eval-expression-print-level nil)  ;设置执行表达式的深度没有限制
(auto-compression-mode 1)               ;打开压缩文件时自动解压缩
(setq read-quoted-char-radix 16)        ;设置 引用字符 的基数
(setq global-mark-ring-max 1024)        ;设置最大的全局标记容量
(global-hl-line-mode 1)                 ;高亮当前行
(setq isearch-allow-scroll t)           ;isearch搜索时是可以滚动屏幕的
(setq enable-recursive-minibuffers t)   ;minibuffer 递归调用命令
(setq history-delete-duplicates t)      ;删除minibuffer的重复历史
(setq minibuffer-message-timeout 1)     ;显示消息超时的时间
(setq auto-revert-mode 1)               ;自动更新buffer
(show-paren-mode t)                     ;显示括号匹配
(setq show-paren-style 'parentheses) ;括号匹配显示但不是烦人的跳到另一个括号。
(setq blink-matching-paren nil)      ;当插入右括号时不显示匹配的左括号
(setq message-log-max t)         ;设置message记录全部消息, 而不用截去
(setq require-final-newline nil) ;不自动添加换行符到末尾, 有些情况会出现错误
(setq ediff-window-setup-function (quote ediff-setup-windows-plain)) ;比较窗口设置在同一个frame里
(setq x-stretch-cursor t)         ;光标在 TAB 字符上会显示为一个大方块
(put 'narrow-to-region 'disabled nil)   ;开启变窄区域
(setq print-escape-newlines t)          ;显示字符窗中的换行符为 \n
(setq tramp-default-method "ssh")       ;设置传送文件默认的方法
(setq void-text-area-pointer nil)       ;禁止显示鼠标指针
(setq byte-compile-warnings
      (quote (
              ;; 显示的警告
              free-vars                 ;不在当前范围的引用变量
              unresolved                ;不知道的函数
              callargs                  ;函数调用的参数和定义的不匹配
              obsolete                  ;荒废的变量和函数
              noruntime                 ;函数没有定义在运行时期
              interactive-only          ;正常不被调用的命令
              make-local ;调用 `make-variable-buffer-local' 可能会不正确的
              mapcar     ;`mapcar' 调用
              ;;
              ;; 抑制的警告
              (not redefine)        ;重新定义的函数 (比如参数数量改变)
              (not cl-functions)    ;`CL' 包中的运行时调用的函数
              )))
(setq echo-keystrokes 0.1)              ;加快快捷键提示的速度
(tooltip-mode -1)                       ;不要显示任何 tooltips

(provide 'init-idle)
