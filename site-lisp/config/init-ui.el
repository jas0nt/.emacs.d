(tool-bar-mode -1)                      ;禁用工具栏
(menu-bar-mode -1)                      ;禁用菜单栏
(scroll-bar-mode -1)                    ;禁用滚动条
(setq-default cursor-type 'box)
(set-cursor-color "#50fa7b")
(blink-cursor-mode 0)

; fullscreen
(setq initial-frame-alist (quote ((fullscreen . maximized))))

(provide 'init-ui)
