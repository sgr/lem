(in-package :lem)

(setf *find-directory-function* 'lem.dired:dired-buffer)

(defun load-init-file ()
  (flet ((test (path)
               (when (cl-fad:file-exists-p path)
                 (lem.lisp-mode:lisp-load-file path)
                 (message "Load file: ~a" path)
                 t)))
    (or (test (merge-pathnames "lem.rc" (truename ".")))
        (test (merge-pathnames ".lemrc" (user-homedir-pathname))))))

(add-hook 'after-init-hook
          'load-init-file)

(add-hook 'find-file-hook
          (lambda ()
            (syntax-scan-buffer (current-buffer))))

;;; !!!
(progn
  (defvar *syntax-timer* nil)

  (add-hook 'post-command-hook
            (lambda ()
              (syntax-scan-lines (current-window)
                                 (current-linum)
                                 (1+ (current-linum)))))

  (add-hook 'pre-command-hook
            (lambda ()
              (when (timer-p *syntax-timer*)
                (stop-timer *syntax-timer*))
              (setq *syntax-timer*
                    (start-timer 500
                                 nil
                                 (lambda ()
                                   (unless (active-minibuffer-window)
                                     (syntax-scan-window (current-window))
                                     (redraw-display)))))))
  )

#+sbcl
(push #'(lambda (x)
          (if x
              (lem x)
              (lem))
          t)
      sb-ext:*ed-functions*)
