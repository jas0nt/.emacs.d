(use-package proced
  :custom
  ;; Auto-refresh every 2 seconds.
  (proced-auto-update-flag t)
  (proced-auto-update-interval 2)
  ;; Show all processes by default, not just the current user's.
  (proced-filter 'all)
  ;; Sort by CPU usage descending (most active processes first).
  (proced-sort 'pcpu)
  (proced-descend t)
  ;; Use the medium format: pid, user, cpu, mem, args — a good balance.
  (proced-format 'medium)
  ;; Emacs 29+: colour-code CPU and memory columns.
  (proced-enable-color-flag t)
  ;; Moving point does not auto-change the sort column.
  (proced-goal-attribute nil)

  :bind
  (("C-c P" . proced)
   :map proced-mode-map
   ("g" . revert-buffer)))


(provide 'init-system)
