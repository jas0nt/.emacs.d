(use-package markmacro
  :vc (:url "https://github.com/manateelazycat/markmacro" :rev "master")
  :bind
  ("C-c C-m w" . markmacro-mark-words)
  ("C-c C-m W" . markmacro-mark-symbols)
  ("C-c C-m l" . markmacro-mark-lines)
  ("C-c C-m ," . markmacro-apply-all)
  ("C-c C-m ." . markmacro-apply-all-except-first)
  ("C-c C-m m" . markmacro-rect-set)
  ("C-c C-m d" . markmacro-rect-delete)
  ("C-c C-m r" . markmacro-rect-replace)
  ("C-c C-m i" . markmacro-rect-insert)
  ("C-c C-m c" . markmacro-rect-mark-columns)
  ("C-c C-m s" . markmacro-rect-mark-symbols))

(use-package vundo
  :bind ("C-x u" . vundo)
  :config
  (setq vundo-glyph-alist vundo-unicode-symbols))

(use-package rainbow-delimiters
  :config
  (rainbow-delimiters-mode)
  (add-hook 'prog-mode-hook #'rainbow-delimiters-mode))

(use-package rainbow-mode
  :hook (prog-mode . rainbow-mode))

(use-package evil-nerd-commenter)

(use-package expand-region
  :demand t
  :init
  (transient-define-prefix cxc/transient-er-mark ()
    "Expand-region marks."
    [["Pairs / quotes"
      ("(" "inside pairs"   er/mark-inside-pairs)
      (")" "outside pairs"  er/mark-outside-pairs)
      ("i" "inside quotes"  er/mark-inside-quotes)
      ("o" "outside quotes" er/mark-outside-quotes)]
     ["Text"
      ("w" "word"       er/mark-word)
      ("W" "subword"    er/mark-subword)
      ("s" "symbol"     er/mark-symbol)
      ("S" "symbol+prefix" er/mark-symbol-with-prefix)
      ("n" "sentence"   er/mark-text-sentence)
      ("p" "paragraph"  er/mark-text-paragraph)]
     ["Code"
      ("d" "defun"       er/mark-defun)
      ("m" "method call" er/mark-method-call)
      ("a" "accessor"    er/mark-next-accessor)
      ("c" "comment"     er/mark-comment)
      ("t" "ts node"     er/mark-ts-node)]
     ["Markup / misc"
      ("<" "inner tag"  er/mark-inner-tag)
      (">" "outer tag"  er/mark-outer-tag)
      ("A" "html attr"  er/mark-html-attribute)
      ("u" "url"        er/mark-url)
      ("e" "email"      er/mark-email)]
     ["Python"
      ("y" "statement"       er/mark-python-statement)
      ("b" "block"           er/mark-python-block)
      ("B" "outer block"     er/mark-outer-python-block)
      ("D" "block+decorator" er/mark-python-block-and-decorator)
      ("'" "inside string"   er/mark-inside-python-string)
      ("\"" "outside string" er/mark-outside-python-string)]
     ["Step"
      ("=" "expand"   er/expand-region)
      ("-" "contract" er/contract-region)
      ("q" "quit"     transient-quit-one)]]))


(provide 'init-edit)
