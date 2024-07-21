(tool-bar-mode -1)                      ;禁用工具栏
(menu-bar-mode -1)                      ;禁用菜单栏
(scroll-bar-mode -1)                    ;禁用滚动条

; fullscreen
(setq initial-frame-alist (quote ((fullscreen . maximized))))

(provide 'init-ui)
