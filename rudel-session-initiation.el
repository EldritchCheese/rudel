;;; rudel-session-initiation.el --- Session discovery and advertising functions
;;
;; Copyright (C) 2009 Jan Moringen
;;
;; Author: Jan Moringen <scymtym@users.sourceforge.net>
;; Keywords: Rudel, session, initiation, service, discovery, advertising
;; X-RCS: $Id:$
;;
;; This file is part of Rudel.
;;
;; Rudel is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; Rudel is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Rudel. If not, see <http://www.gnu.org/licenses>.


;;; Commentary:
;;
;; Interfaces for session initiation and discovery.
;;
;; The central interface is
;; `rudel-session-initiation-backend'. Backends implementing this
;; interface can provide methods to discover sessions, to advertise
;; sessions, or both.
;;
;; The client programming interface consists of a priority which is
;; one of:
;;
;; + `primary'
;; + `fallback'
;;
;; and the following functions:
;;
;; + `rudel-session-initiation-discover'
;; + `rudel-session-initiation-advertise'
;; + `rudel-session-initiation-withdraw'


;;; History:
;;
;; 0.1 - Initial revision


;;; Code:
;;

(eval-when-compile
  (require 'cl))

(require 'eieio)

(require 'rudel-backend)


;;; Customization options
;;

(defcustom rudel-configured-sessions nil
  "List of configured sessions.

Each session is a plist (a list of keys and values). Keys are
specified using keywords and look like this :username. Values are
mostly strings, but numbers are possible as well.

The following keys are required for any session
* :name    (string)
* :backend (string or symbol)

The values of the :name property have to be distinct for all
configured sessions."
  :group 'rudel
  :type  '(repeat :tag "Connections"
		  (plist :tag "Connection"
			 :options ((:name     string)
				   (:backend  symbol)
				   (:username string)
				   (:color    color))))
  )


;;; Variables and constants
;;

(defvar rudel-session-discovered-hook nil
  "This hook is run when collaboration sessions are discovered.")

(defvar rudel-session-vanished-hook nil
  "This hook is run when previously discovered collaboration
session disappear.")


;;; Class rudel-session-initiation-backend
;;

(defclass rudel-session-initiation-backend (rudel-backend)
  ((priority :initarg  :priority
	     :type     symbol
	     :accessor rudel-priority
	     :documentation
	     "Priority of the session initiation method
implemented by this backend. Has to be either 'primary or
'fallback"))
  "Interface implemented by session initiation backends."
  :abstract t)

(defgeneric rudel-discover ((this rudel-session-initiation-backend))
  "Return a list of discovered sessions.
Each list element is a connect info property list. See
`rudel-join-session' for a description of the format of this
list.

The presence of an implementation of this generic function should
be indicated by the presence of the 'discover' capability.")

(defgeneric rudel-advertise ((this rudel-session-initiation-backend) info)
  "Advertise session described by INFO.
INFO is a connect info property list. See `rudel-host-session'
for a description of the format of this list.

The presence of an implementation of this generic function should
be indicated by the presence of the 'advertise' capability.")


;;; Client programming interface functions.
;;

(defun rudel-session-initiation-suitable-backends (capability)
  "Return primary and fallback backends that have CAPABILITY.
The returned list is of the form (PRIMARY FALLBACK), where
PRIMARY and FALLBACK are lists of backends of the respective
priority."
  (let* (;; Select all backends, which can discover sessions
	 (suitable-backends (rudel-backend-suitable-backends
			     'session-initiation
			     (lambda (backend)
			       (rudel-capable-of-p backend capability))))
	 ;; Select primary backends
	 (primary-backends  (remove*
			     'fallback suitable-backends
			     :key (lambda (backend)
				    (rudel-priority (cdr backend)))))
	 ;; Select fallback backends
	 (fallback-backends (remove*
			     'primary suitable-backends
			     :key (lambda (backend)
				    (rudel-priority (cdr backend))))))
    (list primary-backends fallback-backends))
  )

(defun rudel-session-initiation-discover (&optional backend-name)
  "Return a list of session using BACKEND-NAME when non-nil.
BACKEND-NAME is a symbol. When it is non-nil, only the specified
backend is used to discover session.

The returned list is of the form (INFO-1 ... INFO-N FALLBACK-1
... FALLBACK-M) where INFO-I are connect info property lists (see
`rudel-join-session') and FALLBACK-I are conses of the form (NAME
. CLASS-OR-OBJECT) that specify fallback backends."
  (multiple-value-bind (primary-backends fallback-backends)
      (rudel-session-initiation-suitable-backends 'discover)
    ;; Retrieve session list from primary backend and fall back to
    ;; fallback backends if the list is empty.
    (if backend-name
	(let ((backend (find backend-name fallback-backends :key #'car)))
	  (rudel-discover (cdr backend)))
      (let ((primary-results
	     (remove-if #'null
			(apply #'append
			       (mapcar #'rudel-discover
				       (mapcar #'cdr primary-backends))))))
	(append primary-results fallback-backends))))
  )

(defun rudel-session-initiation-advertise (info)
  "Advertise the session described by INFO.
INFO is a connect info property list. See `rudel-host-session'
for a description of the format of this list.

Primary backends are tried first. If none succeeds, fallback
backends are tried.

The result is non-nil if at least one backend was able to
advertise the session."
  (multiple-value-bind (primary-backends fallback-backends)
      (rudel-session-initiation-suitable-backends 'advertise)
    (or ;; Try to advertise the session using primary backends.
        (some (mapcar (lambda (backend)
			(rudel-advertise backend info))
		      (mapcar #'cdr primary-backends)))
	;; When the primary backends fail, try to advertise the
	;; session using fallback backends
	(some (mapcar (lambda (backend)
			(rudel-advertise backend info))
		      (mapcar #'cdr fallback-backends)))))
  )


;;; Class rudel-ask-protocol-backend
;;

(defconst rudel-ask-protocol-version '(0 1)
  "Version of the ask-protocol backend for Rudel.")

;;;###autoload
(defclass rudel-ask-protocol-backend (rudel-session-initiation-backend)
  ((capabilities :initform (discover))
   (priority     :initform fallback))
  "This fallback backend can \"discover\" sessions by letting the
user select a suitable backend and asking for connect information
required by the chosen backend.")

(defmethod initialize-instance ((this rudel-ask-protocol-backend)
				&rest slots)
  "Set backend version."
  (when (next-method-p)
    (call-next-method))

  (oset this :version rudel-ask-protocol-version))

(defmethod rudel-discover ((this rudel-ask-protocol-backend))
  "\"Discover\" sessions by asking the user about the backend to use and the connect info."
  (let ((backend (rudel-backend-choose
		  'protocol
		  (lambda (backend)
		    (rudel-capable-of-p backend 'join)))))
    (list (append (list :name    "asked"
			:backend backend)
		  (rudel-ask-connect-info (cdr backend)))))
  )

;;;###autoload
(rudel-add-backend (rudel-backend-get-factory 'session-initiation)
		   'ask-protocol 'rudel-ask-protocol-backend)


;;; Class rudel-configured-sessions-backend
;;

(defconst rudel-configured-sessions-version '(0 1)
  "Version of the configured-sessions backend for Rudel.")

;;;###autoload
(defclass rudel-configured-sessions-backend
  (rudel-session-initiation-backend)
  ((capabilities :initform (discover))
   (priority     :initform primary))
  "This fallback backend can \"discover\" sessions the user has
configured using customization.")

(defmethod initialize-instance ((this rudel-configured-sessions-backend)
				&rest slots)
  "Set backend version."
  (when (next-method-p)
    (call-next-method))

  (oset this :version rudel-configured-sessions-version))

(defmethod rudel-discover ((this rudel-configured-sessions-backend))
  "\"Discover\" sessions the has configured."
  ;; Iterate over all configured sessions in order to make
  ;; adjustments.
  (mapcar #'rudel-session-initiation-adjust-info
	  rudel-configured-sessions))

;;;###autoload
(rudel-add-backend (rudel-backend-get-factory 'session-initiation)
		   'configured-sessions 'rudel-configured-sessions-backend)


;;; Miscellaneous functions
;;

(defun rudel-session-initiation-adjust-info (info)
  "Resolve arguments that need resolving in INFO."
  ;; Start with a new, empty property list.
  (let ((adjusted-info)
	(key   (car  info))
	(value (cadr info))
	(rest  info))
    ;; Iterate over all properties in INFO.
    (while rest
      (setq rest (cddr rest))
      (cond
       ;; Resolve backend arguments.
       ((eq key :backend)
	(let ((backend (rudel-backend-get 'protocol
					  (if (stringp value)
					      (intern value)
					    value))))
	  (push backend adjusted-info)
	  (push key     adjusted-info)))
       ;; Keep other arguments unmodified.
       (t
	(push value adjusted-info)
	(push key   adjusted-info)))
      ;; Advance to next key value pair.
      (setq key   (car  rest)
	    value (cadr rest)))
    ;; Return the transformed session information.
    adjusted-info)
  )

(provide 'rudel-session-initiation)
;;; rudel-session-initiation.el ends here
