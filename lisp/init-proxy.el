(setq url-proxy-services
   '(("no_proxy" . "^\\(localhost\\|127\\.0\\.0\\.1\\|10\\..*\\|192\\.168\\..*\\)")
     ("http"     . "127.0.0.1:7890")
     ("https"    . "127.0.0.1:7890")))


(provide 'init-proxy)
