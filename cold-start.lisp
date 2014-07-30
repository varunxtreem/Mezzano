(in-package :sys.int)

(declaim (inline null not))

(defun null (object)
  (if object
      'nil
      't))

(defun not (object)
  (if object
      'nil
      't))

(declaim (special *cold-toplevel-forms*
                  *package-system*
                  *additional-cold-toplevel-forms*
                  *initial-obarray*
                  *initial-keyword-obarray*
                  *initial-setf-obarray*
                  *initial-structure-obarray*
                  *kboot-tag-list*)
         (special *terminal-io*
                  *standard-output*
                  *standard-input*
                  *debug-io*
                  *cold-stream-screen*
                  *keyboard-shifted*))
(declaim (special *features* *macroexpand-hook*))

(defun write-char (character &optional stream)
  (cold-write-char character stream))

(defun start-line-p (stream)
  (cold-start-line-p stream))

(defun read-char (&optional stream (eof-error-p t) eof-value recursive-p)
  (cold-read-char stream))

(defun unread-char (character &optional stream)
  (cold-unread-char character stream))

(defun peek-char (&optional peek-type s (eof-error-p t) eof-value recursive-p)
  (cond ((eql peek-type nil)
         (let ((ch (cold-read-char s)))
           (cold-unread-char ch s)
           ch))
        ((eql peek-type t)
         (do ((ch (cold-read-char s)
                  (cold-read-char s)))
             ((not (whitespace[2]p ch))
              (cold-unread-char ch s)
              ch)))
        ((characterp peek-type)
         (error "TODO: character peek."))
        (t (error "Bad peek type ~S." peek-type))))

(defun read-line (&optional (input-stream *standard-input*) (eof-error-p t) eof-value recursive-p)
  (do ((result (make-array 16 :element-type 'character :adjustable t :fill-pointer 0))
       (c (read-char input-stream eof-error-p nil recursive-p)
          (read-char input-stream eof-error-p nil recursive-p)))
      ((or (null c)
           (eql c #\Newline))
       (if (and (null c) (eql (length result) 0))
           (values eof-value t)
           (values result (null c))))
    (vector-push-extend c result)))

(defun yes-or-no-p (&optional control &rest arguments)
  (declare (dynamic-extent arguments))
  (when control
    (write-char #\Newline)
    (apply 'format t control arguments)
    (write-char #\Space))
  (format t "(Yes or No) ")
  (loop
     (let ((line (read-line)))
       (when (string-equal line "yes")
         (return t))
       (when (string-equal line "no")
         (return nil)))
     (write-char #\Newline)
     (format t "Please respond with \"yes\" or \"no\". ")))

(defvar *cold-stream*)
(defun streamp (object)
  (eql object *cold-stream*))

(defun low-level-backtrace (&optional limit (resolve-names t))
  (do ((i 0 (1+ i))
       (fp (read-frame-pointer)
           (memref-unsigned-byte-64 fp 0)))
      ((or (and limit (> i limit))
           (= fp 0)))
    (write-char #\Newline *cold-stream*)
    (write-integer fp 16 *cold-stream*)
    (write-char #\Space *cold-stream*)
    (let* ((ret-addr (memref-unsigned-byte-64 fp 1))
           (fn (when resolve-names
                 (%%assemble-value (base-address-of-internal-pointer ret-addr) +tag-object+)))
           (name (when (functionp fn) (function-name fn))))
      (write-integer ret-addr 16 *cold-stream*)
      (when (and resolve-names name)
        (write-char #\Space *cold-stream*)
        (write name :stream *cold-stream*)))))
(setf (fdefinition 'backtrace) #'low-level-backtrace)

(defun error (datum &rest arguments)
  (write-char #\!)
  (write datum)
  (write-char #\Space)
  (write arguments)
  (low-level-backtrace)
  (loop (%hlt)))

(defun pathnamep (x) nil)
(defun pathnames-equal (x y) nil)

(defun equal (x y)
  (cond
    ((eql x y))
    ((stringp x)
     (and (stringp y)
          (string= x y)))
    ((bit-vector-p x)
     (and (bit-vector-p y)
          (eql (length x) (length y))
          (dotimes (i (length x) t)
            (when (not (eql (bit x i) (bit y i)))
              (return nil)))))
    ((consp x)
     (loop
        (when (not (consp y))
          (return nil))
        (when (not (equal (car x) (car y)))
          (return nil))
        (setf x (cdr x)
              y (cdr y))
        (when (not (consp x))
          (return (equal x y)))))
    ((and (pathnamep x) (pathnamep y))
     (pathnames-equal x y))))

(defun equalp (x y)
  (typecase x
    (character (and (characterp y)
                    (char-equal x y)))
    (number (and (numberp y)
                 (= x y)))
    (cons (and (consp y)
               (equalp (car x) (car y))
               (equalp (cdr x) (cdr y))))
    (vector (and (vectorp y)
                 (eql (length x) (length y))
                 (dotimes (i (length x) t)
                   (when (not (equalp (aref x i) (aref y i)))
                     (return nil)))))
    (array (and (arrayp y)
                (equalp (array-dimensions x) (array-dimensions y))
                (dotimes (i (array-total-size x) t)
                  (when (not (equalp (row-major-aref x i) (row-major-aref y i)))
                    (return nil)))))
    (structure-object
     (and (typep y 'structure-object)
          (eq (%struct-slot x 0) (%struct-slot y 0))
          (dotimes (slot (length (structure-slots (%struct-slot x 0)))
                    t)
            (when (not (equalp (%struct-slot x (1+ slot))
                               (%struct-slot y (1+ slot))))
              (return nil)))))
    ;; TODO: hash-tables.
    (t (eq x y))))

(defun %with-stream-editor (stream recursive-p function)
  (funcall function))

;; Needed for IN-PACKAGE before the package system is bootstrapped.
(defun find-package-or-die (name)
  t)

(defun %defmacro (name function &optional lambda-list)
  (setf (get name 'macro-lambda-list) lambda-list)
  (setf (macro-function name) function))

(defun sys.int::%compiler-defun (name source-lambda)
  (multiple-value-bind (sym mode-name form-name)
      (if (symbolp name)
          (values name 'inline-mode 'inline-form)
          (values (second name) 'setf-inline-mode 'setf-inline-form))
    (when (or (get sym mode-name)
              (get sym form-name))
      (setf (get sym form-name) source-lambda)))
  nil)

(defun %defun (name lambda)
  (setf (fdefinition name) lambda)
  name)

(defun symbol-macro-expansion (symbol env)
  (dolist (e env (values symbol nil))
    (when (eql (first e) :symbol-macros)
      (let ((x (assoc symbol (rest e))))
        (when x
          (return (values (second x) t)))))))

(defun macroexpand-1 (form &optional env)
  (cond ((symbolp form)
         (symbol-macro-expansion form env))
        ((consp form)
         (let ((fn (macro-function (first form) env)))
           (if fn
               (values (funcall *macroexpand-hook* fn form env) t)
               (values form nil))))
        (t (values form nil))))

(defun macroexpand (form &optional env)
  (let ((did-expand nil))
    (do () (nil)
       (multiple-value-bind (expansion expanded-p)
           (macroexpand-1 form env)
         (if expanded-p
             (setf form expansion
                   did-expand t)
             (return (values form did-expand)))))))

(defun %defstruct (structure-type)
  (setf (get (structure-name structure-type) 'structure-type) structure-type))

(defun make-function-reference (name &optional area)
  (let ((fref (%allocate-array-like +object-tag-function-reference+ 4 0 area)))
    (setf (%array-like-ref-t fref +fref-name+) name
          (function-reference-function fref) nil)
    fref))

(defun function-reference (name)
  "Convert a function name to a function reference."
  ;; FIXME: lock here.
  (cond ((symbolp name)
         (let ((fref (symbol-fref name)))
           (unless fref
             (setf fref (make-function-reference name)
                   (symbol-fref name) fref))
           fref))
	((and (consp name)
	      (= (list-length name) 2)
	      (eql (first name) 'setf)
	      (symbolp (second name)))
	 (let ((fref (get (second name) 'setf-fref)))
	   (unless fref
	     (setf fref (make-function-reference name)
		   (get (second name) 'setf-fref) fref))
           fref))
	(t (error "Invalid function name ~S." name))))

(defun function-reference-p (object)
  (and (eql (%tag-field object) +tag-object+)
       (eql (%object-tag object) +object-tag-function-reference+)))

(deftype function-reference ()
  '(satisfies function-reference-p))

(defun function-reference-name (fref)
  (check-type fref function-reference)
  (%array-like-ref-t fref +fref-name+))

(defun function-reference-function (fref)
  (check-type fref function-reference)
  (%array-like-ref-t fref +fref-function+))

(defun (setf function-reference-function) (value fref)
  "Update the function & entry-point fields of a function-reference.
VALUE may be nil to make the fref unbound."
  (check-type value (or function null))
  (check-type fref function-reference)
  ;; mhmm. This should really be a DCAS to avoid racing.
  ;; a lock would work, but writes are infrequent.
  (cond (value
         (setf (%array-like-ref-t fref +fref-function+) value
               (%array-like-ref-unsigned-byte-64 fref +fref-entry-point+) (%array-like-ref-unsigned-byte-64 value 0)))
        (t ;; making the fref unbound.
         (setf (%array-like-ref-t fref +fref-function+) nil
               (%array-like-ref-unsigned-byte-64 fref +fref-entry-point+) (%array-like-ref-unsigned-byte-64 sys.int::*undefined-function-thunk* 0))))
  value)

(defun fdefinition (name)
  (or (function-reference-function (function-reference name))
      (error 'undefined-function :name name)))

(defun (setf fdefinition) (value name)
  (check-type value function)
  (setf (function-reference-function (function-reference name)) value))

(defun fboundp (name)
  (not (null (function-reference-function (function-reference name)))))

(defun fmakunbound (name)
  (setf (function-reference-function (function-reference name)) nil)
  name)

(defun symbol-function (symbol)
  (check-type symbol symbol)
  (fdefinition symbol))

(defun (setf symbol-function) (value symbol)
  (check-type symbol symbol)
  (setf (fdefinition symbol) value))

(defun compiler-macro-function (name &optional environment)
  (multiple-value-bind (sym indicator)
      (if (symbolp name)
          (values name '%compiler-macro-function)
          (values (second name) '%setf-compiler-macro-function))
    (get sym indicator)))

(defun (setf compiler-macro-function) (value name &optional environment)
  (multiple-value-bind (sym indicator)
      (if (symbolp name)
          (values name '%compiler-macro-function)
          (values (second name) '%setf-compiler-macro-function))
    (setf (get sym indicator) value)))

(declaim (inline identity))
(defun identity (thing)
  thing)

(declaim (inline complement))
(defun complement (fn)
  #'(lambda (&rest args) (not (apply fn args))))

(declaim (special * ** ***))

(defun repl ()
  (let ((* nil) (** nil) (*** nil))
    (loop
       (fresh-line)
       (write-char #\>)
       (let ((form (read)))
         (fresh-line)
         (let ((result (multiple-value-list (eval form))))
           (setf *** **
                 ** *
                 * (first result))
           (when result
             (dolist (v result)
               (fresh-line)
               (write v))))))))

(defvar *early-initialize-hook* '())
(defvar *initialize-hook* '())

(defun add-hook (hook function)
  (unless (boundp hook)
    (setf (symbol-value hook) '()))
  (pushnew function (symbol-value hook)))

(defun set-gc-light ())
(defun clear-gc-light ())

(defun emergency-halt (message)
  (%cli)
  (mumble-string message)
  (low-level-backtrace nil nil)
  (loop (%hlt)))

(defun gc-trace (object direction prefix)
  (setf (io-port/8 #xE9) (char-code direction))
  (setf (io-port/8 #xE9) (logand (char-code prefix) #xFF))
  (let ((pointer (%pointer-field object))
        (tag (%tag-field object)))
    (dotimes (i 15)
      (setf (io-port/8 #xE9) (hexify (logand (ash pointer (* -4 (- 14 i))) #b1111))))
    (setf (io-port/8 #xE9) (hexify tag))
    (setf (io-port/8 #xE9) #x0A)))

(defun mumble (message &optional (nl t))
  (mumble-string message)
  (when nl
    (mumble-char #\Newline)))

;;; Used while the GC is copying, so no lookup tables.
(defun hexify (nibble)
  (cond ((<= 0 nibble 9)
         (+ nibble (char-code #\0)))
        (t (+ (- nibble 10) (char-code #\A)))))

(defun mumble-char (char &optional (position 0))
  (let ((code (logand (char-code char) #xFF)))
    (setf (io-port/8 #xE9) code)
    (when (eql code #x0A)
      (loop (when (logbitp 5 (io-port/8 (+ #x3F8 5))) (return)))
      (setf (io-port/8 #x3F8) #x0D))
    (loop (when (logbitp 5 (io-port/8 (+ #x3F8 5))) (return)))
    (setf (io-port/8 #x3F8) code)
    (setf (sys.int::memref-unsigned-byte-16 #x80000B8000 position)
          (logior code #x7000))))

(defun mumble-string (message)
  (dotimes (i (array-dimension message 0))
    (mumble-char (char message i) i)))
(defun mumble-hex (number &optional (message "") (nl nil))
  (mumble-string message)
  (dotimes (i 16)
    (mumble-char (code-char (hexify (logand (ash number (* -4 (- 15 i))) #b1111))) i))
  (when nl (mumble-char #\Newline)))

(defun make-case-correcting-stream (stream case)
  stream)

;;; Initial PRINT-OBJECT, replaced when CLOS is loaded.
(defun print-object (object stream)
  (print-unreadable-object (object stream :type t :identity t)))

(defun mini-vector-stream (vector)
  (cons vector 0))

(defun %read-byte (stream)
  (prog1 (aref (car stream) (cdr stream))
    (incf (cdr stream))))

(defun %read-sequence (seq stream)
  (replace seq (car stream)
           :start2 (cdr stream)
           :end2 (+ (cdr stream) (length seq)))
  (incf (cdr stream) (length seq)))

(defun %defconstant (name value &optional docstring)
  (proclaim `(special ,name))
  (setf (symbol-value name) value)
  (proclaim `(constant ,name))
  name)

(defun enter-debugger (condition)
  (write-char #\!)
  (write condition)
  (low-level-backtrace)
  (loop (%hlt)))

(defun invoke-debugger (condition)
  (write-char #\!)
  (write condition)
  (low-level-backtrace)
  (loop (%hlt)))

(defun round-up (n boundary)
  (if (zerop (rem n boundary))
      n
      (+ n boundary (- (rem n boundary)))))

(defun ub16ref/be (vector index)
  (logior (ash (aref vector index) 8)
	  (aref vector (1+ index))))
(defun (setf ub16ref/be) (value vector index)
  (setf (aref vector index) (ash value -8)
	(aref vector (1+ index)) (logand value #xFF))
  value)

(defun ub16ref/le (vector index)
  (logior (aref vector index)
	  (ash (aref vector (1+ index)) 8)))
(defun (setf ub16ref/le) (value vector index)
  (setf (aref vector index) (logand value #xFF)
	(aref vector (1+ index)) (ash value -8))
  value)

(defun ub32ref/be (vector index)
  (logior (ash (aref vector index) 24)
	  (ash (aref vector (+ index 1)) 16)
	  (ash (aref vector (+ index 2)) 8)
	  (aref vector (+ index 3))))
(defun (setf ub32ref/be) (value vector index)
  (setf (aref vector index) (ash value -24)
	(aref vector (+ index 1)) (logand (ash value -16) #xFF)
	(aref vector (+ index 2)) (logand (ash value -8) #xFF)
	(aref vector (+ index 3)) (logand value #xFF))
  value)

(defun ub32ref/le (vector index)
  (logior (aref vector index)
	  (ash (aref vector (+ index 1)) 8)
	  (ash (aref vector (+ index 2)) 16)
	  (ash (aref vector (+ index 3)) 24)))
(defun (setf ub32ref/le) (value vector index)
  (setf (aref vector index) (logand value #xFF)
	(aref vector (+ index 1)) (logand (ash value -8) #xFF)
	(aref vector (+ index 2)) (logand (ash value -16) #xFF)
	(aref vector (+ index 3)) (ash value -24))
  value)

(defun ub64ref/be (vector index)
  (logior (ash (aref vector index) 56)
	  (ash (aref vector (+ index 1)) 48)
	  (ash (aref vector (+ index 2)) 40)
	  (ash (aref vector (+ index 3)) 32)
	  (ash (aref vector (+ index 4)) 24)
	  (ash (aref vector (+ index 5)) 16)
	  (ash (aref vector (+ index 6)) 8)
	  (aref vector (+ index 7))))
(defun (setf ub64ref/be) (value vector index)
  (setf (aref vector index) (ldb (byte 8 56) value)
	(aref vector (+ index 1)) (ldb (byte 8 48) value)
	(aref vector (+ index 2)) (ldb (byte 8 40) value)
	(aref vector (+ index 3)) (ldb (byte 8 32) value)
	(aref vector (+ index 4)) (ldb (byte 8 24) value)
	(aref vector (+ index 5)) (ldb (byte 8 16) value)
	(aref vector (+ index 6)) (ldb (byte 8 8) value)
	(aref vector (+ index 7)) (ldb (byte 8 0) value))
  value)

(defun ub64ref/le (vector index)
  (logior (aref vector index)
	  (ash (aref vector (+ index 1)) 8)
	  (ash (aref vector (+ index 2)) 16)
	  (ash (aref vector (+ index 3)) 24)
	  (ash (aref vector (+ index 4)) 32)
	  (ash (aref vector (+ index 5)) 40)
	  (ash (aref vector (+ index 6)) 48)
	  (ash (aref vector (+ index 7)) 56)))
(defun (setf ub64ref/le) (value vector index)
  (setf (aref vector index) (ldb (byte 8 0) value)
	(aref vector (+ index 1)) (ldb (byte 8 8) value)
	(aref vector (+ index 2)) (ldb (byte 8 16) value)
	(aref vector (+ index 3)) (ldb (byte 8 24) value)
	(aref vector (+ index 4)) (ldb (byte 8 32) value)
	(aref vector (+ index 5)) (ldb (byte 8 40) value)
	(aref vector (+ index 6)) (ldb (byte 8 48) value)
	(aref vector (+ index 7)) (ldb (byte 8 56) value))
  value)

;;;; Simple EVAL for use in cold images.
(defun eval-cons (form)
  (case (first form)
    ((if) (if (eval (second form))
              (eval (third form))
              (eval (fourth form))))
    ((function) (if (and (consp (second form)) (eql (first (second form)) 'lambda))
                    (let ((lambda (second form)))
                      (when (second lambda)
                        (error "Not supported: Lambdas with arguments."))
                      (lambda ()
                        (eval `(progn ,@(cddr lambda)))))
                    (fdefinition (second form))))
    ((quote) (second form))
    ((progn) (do ((f (rest form) (cdr f)))
                 ((null (cdr f))
                  (eval (car f)))
               (eval (car f))))
    ((setq) (do ((f (rest form) (cddr f)))
                ((null (cddr f))
                 (setf (symbol-value (car f)) (eval (cadr f))))
              (setf (symbol-value (car f)) (eval (cadr f)))))
    (t (multiple-value-bind (expansion expanded-p)
           (macroexpand form)
         (if expanded-p
             (eval expansion)
             (apply (first form) (mapcar 'eval (rest form))))))))

(defun eval (form)
  (typecase form
    (cons (eval-cons form))
    (symbol (symbol-value form))
    (t form)))

;;;; Stuff needed to print the kboot tag list.
(defun format-uuid (stream argument &optional colon-p at-sign-p)
  (check-type argument (unsigned-byte 128))
  (format stream "~8,'0X-~4,'0X-~4,'0X-~4,'0X-~12,'0X"
          (ldb (byte 32 96) argument)
          (ldb (byte 16 80) argument)
          (ldb (byte 16 64) argument)
          (ldb (byte 16 48) argument)
          (ldb (byte 48 0) argument)))

(defun format-ipv4-address (stream argument &optional colon-p at-sign-p)
  (check-type argument (unsigned-byte 32))
  (format stream "~D.~D.~D.~D"
          (ldb (byte 8 24) argument)
          (ldb (byte 8 16) argument)
          (ldb (byte 8 8) argument)
          (ldb (byte 8 0) argument)))

(defun format-ipv6-address (stream argument &optional colon-p at-sign-p)
  (check-type argument (unsigned-byte 128))
  (dotimes (i 8)
    (unless (zerop i) (write-char #\: stream))
    (let ((group (ldb (byte 16 (* (- 7 i) 16)) argument)))
      (write group :base 16 :stream stream))))

(defun format-mac-address (stream argument &optional colon-p at-sign-p)
  (check-type argument (unsigned-byte 64))
  (dotimes (i 8)
    (unless (zerop i) (write-char #\: stream))
    (format stream "~2,'0X" (ldb (byte 8 (* (- 7 i) 8)) argument))))

(defun display-kboot-tag-list ()
  (when *kboot-tag-list*
    (labels ((p/8 (addr) (memref-unsigned-byte-8 (+ #x8000000000 addr) 0))
             (p/16 (addr) (memref-unsigned-byte-16 (+ #x8000000000 addr) 0))
             (p/32 (addr) (memref-unsigned-byte-32 (+ #x8000000000 addr) 0))
             (p/64 (addr) (memref-unsigned-byte-64 (+ #x8000000000 addr) 0))
             (p/uuid (addr)
               (let ((uuid (make-array 64 :element-type 'base-char)))
                 (dotimes (i 64)
                   (setf (aref uuid i) (code-char (p/8 (+ addr i)))))
                 (subseq uuid 0 (position (code-char 0) uuid))))
             (p/be (addr len)
               "Read a big-endian value from memory."
               (let ((value 0))
                 (dotimes (i len)
                   (setf value (logior (ash value 8)
                                       (p/8 (+ addr i)))))
                 value))
             (p/ipv4 (addr) (p/be addr 4))
             (p/ipv6 (addr) (p/be addr 16)))
      (format t "Loaded by KBoot. Tag list at #x~8,'0X~%" *kboot-tag-list*)
      (let ((addr *kboot-tag-list*)
            ;; For sanity checking.
            (max-addr (+ *kboot-tag-list* 1024))
            (last-type -1)
            (saw-memory nil)
            (saw-vmem nil)
            (saw-e820 nil))
        (loop (when (>= addr max-addr)
                (format t "Went past tag list max address.~%")
                (return))
           (let ((type (p/32 (+ addr 0)))
                 (size (p/32 (+ addr 4))))
             (unless (member type '(#.+kboot-tag-memory+ #.+kboot-tag-vmem+ #.+kboot-tag-e820+))
               (format t "Tag ~A (~D), ~:D bytes.~%"
                       (if (> type (length *kboot-tag-names*))
                           "Unknown"
                           (aref *kboot-tag-names* type))
                       type size))
             (when (and (eql addr *kboot-tag-list*)
                        (not (eql type +kboot-tag-core+)))
               (format t "CORE tag not first in the list?~%"))
             (case type
               (#.+kboot-tag-none+ (return))
               (#.+kboot-tag-core+
                (unless (eql addr *kboot-tag-list*)
                  (format t "CORE tag not first in the list?~%"))
                (format t "     tags_phys: ~8,'0X~%" (p/64 (+ addr 8)))
                (format t "     tags_size: ~:D bytes~%" (p/32 (+ addr 16)))
                (format t "   kernel_phys: ~8,'0X~%" (p/64 (+ addr 24)))
                (format t "    stack_base: ~8,'0X~%" (p/64 (+ addr 32)))
                (format t "    stack_phys: ~8,'0X~%" (p/64 (+ addr 40)))
                (format t "    stack_size: ~:D bytes~%" (p/32 (+ addr 48)))
                (setf max-addr (+ *kboot-tag-list* (p/32 (+ addr 16)))))
               #+nil(#.+kboot-tag-option+)
               (#.+kboot-tag-memory+
                (unless (eql last-type +kboot-tag-memory+)
                  (when saw-memory
                    (format t "MEMORY tags are non-contigious.~%"))
                  (setf saw-memory t)
                  (format t "MEMORY map:~%"))
                (let ((start (p/64 (+ addr 8)))
                      (length (p/64 (+ addr 16)))
                      (type (p/8 (+ addr 24))))
                  (format t "  ~16,'0X-~16,'0X  ~A~%"
                          start (+ start length)
                          (case type
                            (#.+kboot-memory-free+ "Free")
                            (#.+kboot-memory-allocated+ "Allocated")
                            (#.+kboot-memory-reclaimable+ "Reclaimable")
                            (t (format nil "Unknown (~D)" type))))))
               (#.+kboot-tag-vmem+
                (unless (eql last-type +kboot-tag-vmem+)
                  (when saw-vmem
                    (format t "VMEM tags are non-contigious.~%"))
                  (setf saw-vmem t)
                  (format t "VMEM map:~%"))
                (let ((start (p/64 (+ addr 8)))
                      (size (p/64 (+ addr 16)))
                      (phys (p/64 (+ addr 24))))
                  (format t "  ~16,'0X-~16,'0X -> ~8,'0X~%"
                          start (+ start size) phys)))
               (#.+kboot-tag-pagetables+
                (format t "          pml4: ~8,'0X~%" (p/64 (+ addr 8)))
                (format t "       mapping: ~8,'0X~%" (p/64 (+ addr 16))))
               (#.+kboot-tag-module+
                (format t "          addr: ~8,'0X~%" (p/64 (+ addr 8)))
                (format t "          size: ~:D bytes~%" (p/32 (+ addr 16))))
               (#.+kboot-tag-video+
                (case (p/32 (+ addr 8))
                  (#.+kboot-video-vga+
                   (format t "  VGA text mode.~%")
                   (format t "          cols: ~:D~%" (p/8 (+ addr 16)))
                   (format t "          rows: ~:D~%" (p/8 (+ addr 17)))
                   (format t "             x: ~:D~%" (p/8 (+ addr 18)))
                   (format t "             y: ~:D~%" (p/8 (+ addr 19)))
                   (format t "      mem_phys: ~8,'0X~%" (p/64 (+ addr 24)))
                   (format t "      mem_virt: ~8,'0X~%" (p/64 (+ addr 32)))
                   (format t "      mem_size: ~:D bytes~%" (p/32 (+ addr 40))))
                  (#.+kboot-video-lfb+
                   (let ((flags (p/32 (+ addr 16))))
                     (format t " LFB ~A mode.~%"
                             (cond
                               ((logtest flags +kboot-lfb-indexed+)
                                "indexed colour")
                               ((logtest flags +kboot-lfb-rgb+)
                                "direct colour")
                               (t "unknown")))
                     (format t "         flags: ~8,'0B" flags)
                     (when (logtest flags +kboot-lfb-rgb+)
                       (format t " KBOOT_LFB_RGB"))
                     (when (logtest flags +kboot-lfb-indexed+)
                       (format t " KBOOT_LFB_INDEXED"))
                     (format t "~%")
                     (format t "         width: ~:D~%" (p/32 (+ addr 20)))
                     (format t "        height: ~:D~%" (p/32 (+ addr 24)))
                     (format t "           bpp: ~:D~%" (p/8 (+ addr 28)))
                     (format t "         pitch: ~:D~%" (p/32 (+ addr 32)))
                     (format t "       fb_phys: ~8,'0X~%" (p/64 (+ addr 40)))
                     (format t "       fb_virt: ~8,'0X~%" (p/64 (+ addr 48)))
                     (format t "       fb_size: ~:D bytes~%" (p/32 (+ addr 56)))
                     (when (logtest flags +kboot-lfb-rgb+)
                       (format t "      red_size: ~:D bits~%" (p/8 (+ addr 60)))
                       (format t "       red_pos: ~:D~%" (p/8 (+ addr 61)))
                       (format t "    green_size: ~:D bits~%" (p/8 (+ addr 62)))
                       (format t "     green_pos: ~:D~%" (p/8 (+ addr 63)))
                       (format t "     blue_size: ~:D bits~%" (p/8 (+ addr 64)))
                       (format t "      blue_pos: ~:D~%" (p/8 (+ addr 65))))
                     (when (logtest flags +kboot-lfb-indexed+)
                       (format t "  palette_size: ~:D~%" (p/16 (+ addr 66))))))))
               (#.+kboot-tag-bootdev+
                (format t "        method: ~A~%"
                        (case (p/32 (+ addr 8))
                          (#.+kboot-bootdev-none+ "None")
                          (#.+kboot-bootdev-disk+ "Disk")
                          (#.+kboot-bootdev-network+ "Network")
                          (t (format nil "Unknown (~D)" (p/32 (+ addr 8))))))
                (case (p/32 (+ addr 8))
                  (#.+kboot-bootdev-disk+
                   (format t "         flags: ~8,'0B~%" (p/32 (+ addr 12)))
                   (format t "          uuid: ~S~%" (p/uuid (+ addr 16)))
                   (format t "        device: ~2,'0X~%" (p/8 (+ addr 80)))
                   (format t "     partition: ~2,'0X~%" (p/8 (+ addr 81)))
                   (format t " sub_partition: ~2,'0X~%" (p/8 (+ addr 82))))
                  (#.+kboot-bootdev-network+
                   (let ((flags (p/32 (+ addr 12))))
                     (format t "         flags: ~8,'0B" flags)
                     (when (logtest flags +kboot-net-ipv6+)
                       (format t " KBOOT_NET_IPv6"))
                     (format t "~%")
                     (if (logtest flags +kboot-net-ipv6+)
                         (format t "     server_ip: ~/sys.int::format-ipv6-address/~%"
                                 (p/ipv6 (+ addr 16)))
                         (format t "     server_ip: ~/sys.int::format-ipv4-address/~%"
                                 (p/ipv4 (+ addr 16))))
                     (format t "   server_port: ~D~%" (p/16 (+ addr 32)))
                     (if (logtest flags +kboot-net-ipv6+)
                         (format t "    gateway_ip: ~/sys.int::format-ipv6-address/~%"
                                 (p/ipv6 (+ addr 34)))
                         (format t "    gateway_ip: ~/sys.int::format-ipv4-address/~%"
                                 (p/ipv4 (+ addr 34))))
                     (if (logtest flags +kboot-net-ipv6+)
                         (format t "     client_ip: ~/sys.int::format-ipv6-address/~%"
                                 (p/ipv6 (+ addr 50)))
                         (format t "     client_ip: ~/sys.int::format-ipv4-address/~%"
                                 (p/ipv4 (+ addr 50))))
                     (format t "    client_mac: ~/sys.int::format-mac-address/~%"
                             (p/be (+ addr 66) 8))))))
               (#.+kboot-tag-e820+
                (unless (eql last-type +kboot-tag-e820+)
                  (when saw-e820
                    (format t "E820 tags are non-contigious.~%"))
                  (setf saw-e820 t)
                  (format t "E820 map:~%"))
                (let ((start (p/64 (+ addr 8)))
                      (size (p/64 (+ addr 16)))
                      (type (p/32 (+ addr 24)))
                      (attr (p/32 (+ addr 28))))
                  (format t "  ~16,'0X-~16,'0X ~D ~D~%"
                          start (+ start size) type attr))))
             (setf last-type type)
             (incf addr (round-up size 8))))))))

(defun load-modules ()
  (when *kboot-tag-list*
    (flet ((p/8 (addr) (memref-unsigned-byte-8 (+ #x8000000000 addr) 0))
           (p/16 (addr) (memref-unsigned-byte-16 (+ #x8000000000 addr) 0))
           (p/32 (addr) (memref-unsigned-byte-32 (+ #x8000000000 addr) 0))
           (p/64 (addr) (memref-unsigned-byte-64 (+ #x8000000000 addr) 0)))
      (let ((addr *kboot-tag-list*)
            ;; For sanity checking.
            (max-addr (+ *kboot-tag-list* 1024)))
      (loop (when (>= addr max-addr) (return))
         (let ((type (p/32 (+ addr 0)))
               (size (p/32 (+ addr 4))))
           (when (and (eql addr *kboot-tag-list*)
                      (not (eql type +kboot-tag-core+)))
             (format t "CORE tag not first in the list?~%")
             (return))
           (case type
             (#.+kboot-tag-none+ (return))
             (#.+kboot-tag-core+
              (unless (eql addr *kboot-tag-list*)
                (format t "CORE tag not first in the list?~%")
                (return))
              (setf max-addr (+ *kboot-tag-list* (p/32 (+ addr 16)))))
             (#.+kboot-tag-module+
              (let* ((address (p/64 (+ addr 8)))
                     (size (p/32 (+ addr 16)))
                     (array (make-array size
                                        :element-type '(unsigned-byte 8)
                                        :memory (+ #x8000000000 address)))
                     (stream (mini-vector-stream array)))
                (format t "Loading KBoot module at ~X~%" address)
                (mini-load-llf stream))))
           (incf addr (round-up size 8))))))))

(defvar *deferred-%defpackage-calls* '())

(defun %defpackage (&rest arguments)
  (push arguments *deferred-%defpackage-calls*))

;;; Until the process system is loaded.
(defun %maybe-preempt-from-interrupt-frame ()
  nil)

(defun %coerce-to-callable (thing)
  (if (functionp thing)
      thing
      (fdefinition thing)))

(defun initialize-lisp ()
  "A grab-bag of things that must be done before Lisp will work properly.
Cold-generator sets up just enough stuff for functions to be called, for
structures to exist, and for memory to be allocated, but not much beyond that."
  (setf *next-symbol-tls-slot* 256
        *array-types* #(t
                        fixnum
                        bit
                        (unsigned-byte 2)
                        (unsigned-byte 4)
                        (unsigned-byte 8)
                        (unsigned-byte 16)
                        (unsigned-byte 32)
                        (unsigned-byte 64)
                        (signed-byte 1)
                        (signed-byte 2)
                        (signed-byte 4)
                        (signed-byte 8)
                        (signed-byte 16)
                        (signed-byte 32)
                        (signed-byte 64)
                        single-float
                        double-float
                        short-float
                        long-float
                        (complex single-float)
                        (complex double-float)
                        (complex short-float)
                        (complex long-float)
                        xmm-vector)
        ;; Ugh! Set the small static area boundary tag.
        (memref-unsigned-byte-64 *small-static-area* 0) (- (* 1 1024 1024) 2)
        (memref-unsigned-byte-64 *small-static-area* 1) #b100
        *package* nil
        *cold-stream* (make-cold-stream)
        *terminal-io* *cold-stream*
        *standard-output* *cold-stream*
        *standard-input* *cold-stream*
        *debug-io* *cold-stream*
        *screen-offset* (cons 0 0)
        *cold-stream-screen* '(:serial #x3F8)
        *keyboard-shifted* nil
        *early-initialize-hook* '()
        *initialize-hook* '()
        * nil
        ** nil
        *** nil
        /// nil
        // nil
        / nil
        +++ nil
        ++ nil
        + nil
        *default-control-stack-size* 16384
        *default-binding-stack-size* 512)
  (setf *print-base* 10.
        *print-escape* t
        *print-readably* nil
        *print-safe* nil)
  (setf *features* '(:unicode :little-endian :x86-64 :mezzanine :ieee-floating-point :ansi-cl :common-lisp)
        *macroexpand-hook* 'funcall
        most-positive-fixnum #.(- (expt 2 (- 64 +n-fixnum-bits+ 1)) 1)
        most-negative-fixnum #.(- (expt 2 (- 64 +n-fixnum-bits+ 1))))
  ;; Initialize defstruct and patch up all the structure types.
  (bootstrap-defstruct)
  (dotimes (i (length *initial-structure-obarray*))
    (setf (%struct-slot (svref *initial-structure-obarray* i) 0) *structure-type-type*))
  (write-line "Cold image coming up...")
  ;; Hook FREFs up where required.
  (dotimes (i (length *initial-fref-obarray*))
    (let* ((fref (svref *initial-fref-obarray* i))
           (name (%array-like-ref-t fref 0)))
      (when (consp name)
        (setf (get (second name) 'setf-fref) fref))))
  ;; Run toplevel forms.
  (let ((*package* *package*))
    (dotimes (i (length *cold-toplevel-forms*))
      (eval (svref *cold-toplevel-forms* i))))
  ;; Constantify every keyword.
  (dotimes (i (length *initial-obarray*))
    (when (eql (symbol-package (aref *initial-obarray* i)) :keyword)
      (setf (symbol-mode (aref *initial-obarray* i)) :constant)))
  (dolist (sym '(nil t most-positive-fixnum most-negative-fixnum))
    (setf (symbol-mode sym) :constant))
  ;; Pull in the real package system.
  ;; If anything goes wrong before init-package-sys finishes then things
  ;; break in terrible ways.
  (dotimes (i (length *package-system*))
    (eval (svref *package-system* i)))
  (initialize-package-system)
  (dolist (args (reverse *deferred-%defpackage-calls*))
    (apply #'%defpackage args))
  (makunbound '*deferred-%defpackage-calls*)
  (let ((*package* *package*))
    (dotimes (i (length *additional-cold-toplevel-forms*))
      (eval (svref *additional-cold-toplevel-forms* i))))
  ;; Flush the bootstrap stuff.
  (makunbound '*initial-obarray*)
  (makunbound '*package-system*)
  (makunbound '*additional-cold-toplevel-forms*)
  (makunbound '*cold-toplevel-forms*)
  (makunbound '*initial-fref-obarray*)
  (makunbound '*initial-structure-obarray*)
  (setf (fdefinition 'initialize-lisp) #'reinitialize-lisp)
  (gc)
  (reinitialize-lisp))

(defun reinitialize-lisp ()
  (init-isa-pic)
  (cold-stream-init)
  (gc-init-system-memory)
  (setf *cold-stream-log* (make-array 10000 :element-type 'character :adjustable t :fill-pointer 0))
  (mapc 'funcall *early-initialize-hook*)
  (%sti)
  (pci-device-scan)
  (write-line "Hello, world.")
  (load-modules)
  (mapc 'funcall *initialize-hook*)
  (terpri)
  (write-char #\*)
  (write-char #\O)
  (write-char #\K)
  (terpri)
  (setf *bootlog* *cold-stream-log*)
  (makunbound '*cold-stream-log*)
  (repl)
  (loop (%hlt)))

(define-lap-function %%common-entry ()
  (:gc :no-frame)
  ;; This is the common entry code.
  ;; The KBoot & GRUB setup code both jump here.
  ;; The stack is not valid, the machine is in 64-bit mode with
  ;; our page tables, GDT & IDT loaded.
  ;; Calling this from Lisp is probably a bad idea.
  ;; Preset the initial stack group.
  (sys.lap-x86:mov64 :r8 (:constant *initial-stack-group*))
  (sys.lap-x86:mov64 :r8 (:r8 #.(+ (- sys.int::+tag-object+) 8 (* sys.c::+symbol-value+ 8))))
  (sys.lap-x86:mov64 :csp (:r8 #.(- (* (1+ +stack-group-offset-control-stack-base+) 8) +tag-object+)))
  (sys.lap-x86:add64 :csp (:r8 #.(- (* (1+ +stack-group-offset-control-stack-size+) 8) +tag-object+)))
  ;; Clear binding stack.
  (sys.lap-x86:mov64 :rdi (:r8 #.(- (* (1+ +stack-group-offset-binding-stack-base+) 8) +tag-object+)))
  (sys.lap-x86:mov64 :rcx (:r8 #.(- (* (1+ +stack-group-offset-binding-stack-size+) 8) +tag-object+)))
  (sys.lap-x86:sar64 :rcx 3)
  (sys.lap-x86:xor32 :eax :eax)
  (sys.lap-x86:rep)
  (sys.lap-x86:stos64)
  ;; Set the binding stack pointer.
  (sys.lap-x86:mov64 (:r8 #.(- (* (1+ +stack-group-offset-binding-stack-pointer+) 8)
                               +tag-object+))
                     :rdi)
  ;; Clear TLS binding slots.
  (sys.lap-x86:lea64 :rdi (:r8 #.(- (* (1+ +stack-group-offset-tls-slots+) 8)
                                    +tag-object+)))
  (sys.lap-x86:mov64 :rax :unbound-tls-slot)
  (sys.lap-x86:mov32 :ecx #.+stack-group-tls-slots-size+)
  (sys.lap-x86:rep)
  (sys.lap-x86:stos64)
  ;; Initialize GS.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:mov64 :rdx :r8)
  (sys.lap-x86:sar64 :rdx 32)
  (sys.lap-x86:mov64 :rcx #xC0000101)
  (sys.lap-x86:wrmsr)
  ;; Mark the SG as active.
  (sys.lap-x86:gs)
  (sys.lap-x86:and64 (#.(+ (- +tag-object+)
                           (ash (1+ +stack-group-offset-flags+)
                                +n-fixnum-bits+)))
                     #.(ash (lognot (1- (ash 1 +stack-group-state-size+)))
                            (+ +stack-group-state-position+
                               +n-fixnum-bits+)))
  ;; SSE init.
  ;; Set CR4.OSFXSR and CR4.OSXMMEXCPT.
  (sys.lap-x86:movcr :rax :cr4)
  (sys.lap-x86:or64 :rax #x00000600)
  (sys.lap-x86:movcr :cr4 :rax)
  ;; Clear CR0.EM and set CR0.MP.
  (sys.lap-x86:movcr :rax :cr0)
  (sys.lap-x86:and64 :rax -5)
  (sys.lap-x86:or64 :rax #x00000002)
  (sys.lap-x86:movcr :cr0 :rax)
  ;; Clear FPU/SSE state.
  (sys.lap-x86:push #x1F80)
  (sys.lap-x86:ldmxcsr (:rsp))
  (sys.lap-x86:add64 :rsp 8)
  (sys.lap-x86:fninit)
  ;; Clear frame pointer.
  (sys.lap-x86:mov64 :cfp 0)
  ;; Clear data registers.
  (sys.lap-x86:xor32 :r8d :r8d)
  (sys.lap-x86:xor32 :r9d :r9d)
  (sys.lap-x86:xor32 :r10d :r10d)
  (sys.lap-x86:xor32 :r11d :r11d)
  (sys.lap-x86:xor32 :r12d :r12d)
  (sys.lap-x86:xor32 :ebx :ebx)
  ;; Prepare for call.
  (sys.lap-x86:mov64 :r13 (:function initialize-lisp))
  (sys.lap-x86:xor32 :ecx :ecx)
  ;; Call the entry function.
  (sys.lap-x86:call (:r13 #.(+ (- sys.int::+tag-object+) 8 (* sys.int::+fref-entry-point+ 8))))
  ;; Crash if it returns.
  here
  (sys.lap-x86:ud2)
  (sys.lap-x86:jmp here))
