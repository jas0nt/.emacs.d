(require 'init-ui)
(require 'init-font)
(require 'init-accelerate)

(let (
      ;; 加载的时候临时增大`gc-cons-threshold'以加速启动速度。
      (gc-cons-threshold most-positive-fixnum)
      (gc-cons-percentage 0.6)
      ;; 清空避免加载远程文件的时候分析文件。
      (file-name-handler-alist nil))

  ;; 让窗口启动更平滑
  (setq frame-inhibit-implied-resize t)
  (setq-default inhibit-redisplay t
                inhibit-message t)
  (add-hook 'window-setup-hook
            (lambda ()
              (setq-default inhibit-redisplay nil
                            inhibit-message nil)
              (redisplay)))


  (with-temp-message ""              ;抹掉插件启动的输出
    (require 'init-pkgs)
    (require 'init-theme)
    (require 'init-generic)
    (require 'init-common)
    (require 'init-keys)
    (require 'init-evil)
    (require 'init-completion)
    (require 'init-chinese)
    (require 'init-edit)
    (require 'init-dired)
    (require 'init-project)
    (require 'init-vc)
    (require 'init-dashboard)
    (require 'init-python)
    (require 'init-rust)
    (require 'init-lsp)
    (require 'init-other)

    ;; HOOK: Reset GC after startup is complete
    (add-hook 'emacs-startup-hook
              (lambda ()
		(setq gc-cons-threshold (* 100 1024 1024) ; Reset to 100MB
                      gc-cons-percentage 0.1)))           ; Reset to default

    ;; 可以延后加载的
    (run-with-idle-timer
     1 nil
     #'(lambda ()
         (require 'init-idle)
	 (require 'init-music)
         ))
    ))

(provide 'init-all)
