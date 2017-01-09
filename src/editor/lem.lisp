(in-package :lem)

(export '(*debug-p*
          after-init-hook
          pop-up-backtrace
          with-editor
          lem))

(defvar *debug-p* nil)
(defvar *running-p* nil)

(defun pop-up-backtrace (condition)
  (let ((buffer (get-buffer-create "*EDITOR ERROR*")))
    (display-buffer buffer)
    (erase-buffer)
    (with-open-stream (stream (make-buffer-output-stream (buffer-point buffer)))
      (princ condition stream)
      (fresh-line stream)
      (uiop/image:print-backtrace
       :stream stream
       :count 100))))

(defun bailout (condition)
  (throw 'toplevel
    (with-output-to-string (stream)
      (princ condition stream)
      (uiop/image:print-backtrace
       :stream stream
       :condition condition))))

(defmacro with-error-handler (() &body body)
  `(handler-case-bind (#'(lambda (condition)
                           (handler-bind ((error #'bailout))
                             (pop-up-backtrace condition)))
			 ,@body)
                      ((condition) (declare (ignore condition)))))

(defvar *syntax-scan-window-recursive-p* nil)

(defun syntax-scan-window (window)
  (check-type window window)
  (when (and (enable-syntax-highlight-p (window-buffer window))
             (null *syntax-scan-window-recursive-p*))
    (let ((*syntax-scan-window-recursive-p* t))
      (window-see window)
      (syntax-scan-range (line-start (copy-point (window-view-point window) :temporary))
                         (or (line-offset (copy-point (window-view-point window) :temporary)
                                          (window-height window))
                             (buffers-end (window-buffer window)))))))

(defun syntax-scan-buffer (buffer)
  (check-type buffer buffer)
  (when (enable-syntax-highlight-p buffer)
    (syntax-scan-range (buffers-start buffer) (buffers-end buffer))))

(defun syntax-scan-current-view ()
  (cond
    ((get-bvar 'already-visited)
     (syntax-scan-window (current-window)))
    (t
     (setf (get-bvar 'already-visited) t)
     (syntax-scan-buffer (current-buffer)))))

(defun ask-revert-buffer ()
  (if (prompt-for-y-or-n-p (format nil
                                "~A changed on disk; revert buffer?"
                                (buffer-filename)))
      (revert-buffer t)
      (update-changed-disk-date (current-buffer)))
  (redraw-display)
  (message nil))

(defmacro cockpit (&body body)
  `(cond (*debug-p*
          (handler-bind ((error #'bailout)
                         #+sbcl (sb-sys:interactive-interrupt #'bailout))
            ,@body))
         (t
          ,@body)))

(defun syntax-scan-point (point)
  (with-point ((start point)
               (end point))
    (syntax-scan-range (line-start start)
                       (line-end end))))

(defun setup ()
  (start-idle-timer "mainloop" 200 t
                    (lambda ()
                      (redraw-display)))
  (start-idle-timer "lazy-syntax-scan" 500 t
                    (lambda ()
                      (syntax-scan-current-view)
                      (redraw-display)))
  (pushnew #'(lambda (window)
               (declare (ignore window))
               (syntax-scan-current-view))
           *window-scroll-functions*)
  (pushnew #'(lambda (window)
               (declare (ignore window))
               (syntax-scan-current-view))
           *window-size-change-functions*)
  (pushnew #'(lambda (window)
               (syntax-scan-window window))
           *window-show-buffer-functions*)
  (pushnew 'syntax-scan-point (after-change-functions))
  (add-hook 'find-file-hook
            (lambda (buffer)
              (prepare-auto-mode buffer)
              (scan-file-property-list buffer)))
  (add-hook 'before-save-hook
            (lambda (buffer)
              (scan-file-property-list buffer))))

(defun lem-mainloop ()
  (do-commandloop (:toplevel t)
    (with-error-handler ()
      (cockpit
       (redraw-display)
       (start-idle-timers)
       (let ((cmd (read-key-command)))
         (stop-idle-timers)
         (if (changed-disk-p (current-buffer))
             (ask-revert-buffer)
             (progn
               (message nil)
               (handler-case
                   (handler-bind ((editor-condition
                                   (lambda (c)
                                     (declare (ignore c))
                                     (stop-record-key))))
                     (cmd-call cmd nil))
                 (editor-abort ()
                               (buffer-mark-cancel (current-buffer))
                               (message "Quit"))
                 (read-only-error ()
                                  (message "Read Only"))
                 (editor-error (c)
                               (message (editor-error-message c)))))))))
    #+(or)
    (buffer-test (current-buffer))))

(let ((passed nil))
  (defun call-with-editor (function)
    (unwind-protect
	 (catch 'toplevel
	   (let ((*running-p* t))
	     (unless passed
	       (setq passed t)
	       (let ((*debug-p* t))
		 (cockpit
		   (display-init)
		   (window-init)
		   (minibuf-init)
                   (setup)
		   (run-hooks 'after-init-hook))))
	     (funcall function)))
      (display-finalize))))

(defmacro with-editor (() &body body)
  `(call-with-editor (lambda () ,@body)))

(defun check-init ()
  (when *running-p*
    (error "Editor is already running")))

(defun lem (&rest args)
  (check-init)
  (let ((report (with-editor ()
                  (mapc 'find-file args)
                  (lem-mainloop))))
    (when report
      (format t "~&~a~%" report))))