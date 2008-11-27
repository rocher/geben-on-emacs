;;==============================================================
;; session
;;==============================================================

(require 'cl)
(require 'xml)
(require 'dbgp)
(require 'geben-util)

;;--------------------------------------------------------------
;; constants
;;--------------------------------------------------------------

(defconst geben-process-buffer-name "*GEBEN<%s> process*"
  "Name for DBGp client process console buffer.")
(defconst geben-redirect-combine-buffer-name "*GEBEN<%s> output *"
  "Name for the debuggee script's STDOUT and STDERR redirection buffer.")
(defconst geben-redirect-stdout-buffer-name "*GEBEN<%s> stdout>*"
  "Name for the debuggee script's STDOUT redirection buffer.")
(defconst geben-redirect-stderr-buffer-name "*GEBEN<%s> stderr*"
  "Name for the debuggee script's STDERR redirection buffer.")
(defconst geben-backtrace-buffer-name "*GEBEN<%s> backtrace*"
  "Name for backtrace buffer.")
(defconst geben-breakpoint-list-buffer-name "*GEBEN<%s> breakpoint list*"
  "Name for breakpoint list buffer.")
(defconst geben-context-buffer-name "*GEBEN<%s> context*"
  "Name for context buffer.")

(defvar geben-sessions nil)
(defvar geben-current-session nil)

(defstruct (geben-session
	    (:constructor nil)
	    (:constructor geben-session-make))
  "Represent a DBGp protocol connection session."
  project
  process
  (tid 30000)
  (state :created)
  initmsg
  xdebug-p
  language
  (bp (geben-breakpoint-make))
  (cmd (make-hash-table :size 16))
  source
  (context (geben-dbgp-context-make))
  stack
  (cursor (list :overlay (make-overlay 0 0) :position nil))
  tempdir
  )
  
(defmacro geben-with-current-session (binding &rest body)
  (declare (indent 1))
  (cl-macroexpand-all
   `(let ((,binding geben-current-session))
      (when ,binding
	,@body))))

;; initialize

(defsubst geben-session-init (session init-msg)
  "Initialize a session of a process PROC."
  (pop-to-buffer (process-buffer (geben-session-process session)))
  (geben-session-tempdir-setup session)
  (setf (geben-session-initmsg session) init-msg)
  (setf (geben-session-xdebug-p session)
	(and (member "Xdebug" (geben-flatten init-msg))
	     t))
  (setf (geben-session-language session)
	(let ((lang (xml-get-attribute-or-nil init-msg 'language)))
	  (and lang
	       (intern (concat ":" (downcase lang)))))))
  
(defsubst geben-session-release (session init-msg)
  "Initialize a session of a process PROC."
  (setf (geben-session-project session) nil)
  (setf (geben-session-process session) nil)
  (setf (geben-session-cursor session) nil))
  
(defsubst geben-session-active-p (session)
  (let ((proc (geben-session-process session)))
    (and (processp proc)
	 (eq 'open (process-status proc)))))

;; tid

(defsubst geben-session-next-tid (session)
  "Get transaction id for next command."
  (prog1
      (geben-session-tid session)
    (incf (geben-session-tid session))))

;; source

(defsubst geben-session-source-get (session fileuri)
  (gethash fileuri (geben-session-source session)))

(defsubst geben-session-source-append (session fileuri local-path)
  (puthash fileuri (list :fileuri fileuri :local-path local-path)
	   (geben-session-source session)))

(defsubst geben-session-source-local-path (session fileuri)
  (plist-get (gethash fileuri (geben-session-source session))
	     :local-path))

(defsubst geben-session-source-fileuri (session local-path)
  (block geben-session-souce-fileuri
    (maphash (lambda (fileuri path)
	       (and (equal local-path path)
		    (return-from geben-session-souce-fileuri fileuri))))))

;; buffer

(defsubst geben-session-buffer-name (session format-string)
  (let* ((proc (geben-session-process session))
	 (idekey (plist-get (dbgp-proxy-get proc) :idekey)))
    (format format-string
	    (concat (if idekey
			(format "%s:" idekey)
		      "")
		    (format "%s:%s"
			    (dbgp-ip-get proc)
			    (dbgp-port-get (dbgp-listener-get proc)))))))

(defsubst geben-session-buffer-get (session format-string)
  (get-buffer-create (geben-session-buffer-name session format-string)))

;; temporary directory

(defcustom geben-temporary-file-directory temporary-file-directory
  "*Base directory path where GEBEN creates a temporary directory."
  :group 'geben
  :type 'directory)

(defun geben-session-tempdir-setup (session)
  "Setup temporary directory."
  (let* ((proc (geben-session-process session))
	 (topdir (file-truename geben-temporary-file-directory))
	 (leafdir (format "%d" (second (process-contact proc))))
	 (tempdir (expand-file-name leafdir
				    (expand-file-name "emacs-geben"
						      topdir))))
    ;;(make-directory tempdir t)
    ;;(set-file-modes tempdir 1023)
    (setf (geben-session-tempdir session) tempdir)))

(defun geben-session-tempdir-remove (session)
  "Remove temporary directory."
  (let ((tempdir (geben-session-tempdir session)))
    (when (file-directory-p tempdir)
      (geben-remove-directory-tree tempdir))))

(provide 'geben-session)