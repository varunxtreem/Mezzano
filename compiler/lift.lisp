;;;; Copyright (c) 2011-2015 Henry Harrington <henry.harrington@gmail.com>
;;;; This code is licensed under the MIT license.

;;; This is the compiler pass that performs lambda-lifting.

(in-package :sys.c)

(defun ll-form (form)
  (etypecase form
    (cons (ecase (first form)
	    ((block) (ll-block form))
	    ((go) (ll-go form))
	    ((return-from) (ll-return-from form))
	    ((tagbody) (ll-tagbody form))))
    (ast-function (ll-function form))
    (ast-if (ll-if form))
    (ast-let (ll-let form))
    (ast-multiple-value-bind (ll-multiple-value-bind form))
    (ast-multiple-value-call (ll-multiple-value-call form))
    (ast-multiple-value-prog1 (ll-multiple-value-prog1 form))
    (ast-progn (ll-progn form))
    (ast-quote (ll-quote form))
    (ast-setq (ll-setq form))
    (ast-the (ll-the form))
    (ast-unwind-protect (ll-unwind-protect form))
    (ast-call (ll-function-form form))
    (ast-jump-table (ll-jump-table form))
    (lexical-variable (ll-variable form))
    (lambda-information (ll-lambda form))))

(defun ll-implicit-progn (x)
  (do ((i x (cdr i)))
      ((endp i))
    (setf (car i) (ll-form (car i)))))

(defun ll-block (form)
  (unless (eql (lexical-variable-definition-point (second form)) *current-lambda*)
    (change-made)
    ;; Update the definition point.
    (setf (lexical-variable-definition-point (second form)) *current-lambda*))
  (ll-implicit-progn (cddr form))
  form)

(defun ll-function (form)
  form)

(defun ll-go (form)
  form)

(defun ll-if (form)
  (setf (test form) (ll-form (test form))
	(if-then form) (ll-form (if-then form))
	(if-else form) (ll-form (if-else form)))
  form)

(defun ll-let (form)
  ;; Patch up definition points after a lambda has been lifted.
  (dolist (binding (bindings form))
    (when (and (lexical-variable-p (first binding))
	       (not (eql (lexical-variable-definition-point (first binding)) *current-lambda*)))
      (change-made)
      (setf (lexical-variable-definition-point (first binding)) *current-lambda*))
    (setf (second binding) (ll-form (second binding))))
  (setf (body form) (ll-form (body form)))
  form)

(defun ll-multiple-value-bind (form)
  ;; Patch up definition points after a lambda has been lifted.
  (dolist (var (bindings form))
    (when (and (lexical-variable-p var)
	       (not (eql (lexical-variable-definition-point var) *current-lambda*)))
      (change-made)
      (setf (lexical-variable-definition-point var) *current-lambda*)))
  (setf (value-form form) (ll-form (value-form form))
        (body form) (ll-form (body form)))
  form)

;; Reduce (multiple-value-call #'(lambda (&optional ... &rest unused) ...) value-form)
;; back down to (multiple-value-bind (vars...) value-form body...).
(defun ll-multiple-value-call (form)
  (let ((fn (function-form form)))
    (cond ((and (lambda-information-p fn)
                (null (lambda-information-required-args fn))
                (lambda-information-rest-arg fn)
                (not (lambda-information-enable-keys fn))
                (not (lambda-information-environment-arg fn))
                (every (lambda (x)
                         (and (typep (second x) 'ast-quote)
                              (eql (value (second x)) 'nil) ; An init-form of NIL.
                              (eql (third x) nil)))    ; No suppliedp arg.
                       (lambda-information-optional-args (function-form form)))
                (lexical-variable-p (lambda-information-rest-arg fn))
                (zerop (lexical-variable-use-count (lambda-information-rest-arg fn))))
           (change-made)
           ;; Variable definition points will be fixed up by LL-MULTIPLE-VALUE-BIND.
           (ll-form (make-instance 'ast-multiple-value-bind
                                   :bindings (mapcar 'first (lambda-information-optional-args fn))
                                   :value-form (value-form form)
                                   :body (lambda-information-body fn))))
          (t (setf (function-form form) (ll-form (function-form form))
                   (value-form form) (ll-form (value-form form)))
             form))))

(defun ll-multiple-value-prog1 (form)
  (setf (value-form form) (ll-form (value-form form))
        (body form) (ll-form (body form)))
  form)

(defun ll-progn (form)
  (ll-implicit-progn (forms form))
  form)

(defun ll-quote (form)
  form)

(defun ll-return-from (form)
  (setf (third form) (ll-form (third form)))
  (setf (fourth form) (ll-form (fourth form)))
  form)

(defun ll-setq (form)
  (setf (value form) (ll-form (value form)))
  form)

(defun ll-tagbody (form)
  (unless (eq (lexical-variable-definition-point (second form)) *current-lambda*)
    (change-made)
    (setf (lexical-variable-definition-point (second form)) *current-lambda*))
  (do ((i (cddr form) (cdr i)))
      ((endp i))
    (unless (go-tag-p (car i))
      (setf (car i) (ll-form (car i)))))
  form)

(defun ll-the (form)
  (setf (value form) (ll-form (value form)))
  form)

(defun ll-unwind-protect (form)
  (setf (protected-form form) (ll-form (protected-form form))
        (cleanup-function form) (ll-form (cleanup-function form)))
  form)

(defun ll-jump-table (form)
  (setf (value form) (ll-form (value form)))
  (ll-implicit-progn (targets form))
  form)

;; Doesn't support fuzzy allow-other-keys matching.
(defun arguments-match-lambda-list (lambda arg-list)
  (let ((arg-count (length arg-list))
        (req-count (length (lambda-information-required-args lambda)))
        (opt-count (length (lambda-information-optional-args lambda))))
    (when (and (lambda-information-rest-arg lambda)
               (not (symbolp (lambda-information-rest-arg lambda)))
               (lexical-variable-dynamic-extent (lambda-information-rest-arg lambda)))
      (return-from arguments-match-lambda-list nil))
    (cond ((lambda-information-enable-keys lambda)
           (let ((keywords (mapcar 'caar (lambda-information-key-args lambda))))
             (when (and (>= arg-count req-count)
                        (evenp (- arg-count (+ req-count opt-count))))
               (do ((i (nthcdr (+ req-count opt-count) arg-list) (cddr i)))
                   ((null i)
                    t)
                 (unless (and (typep (car i) 'ast-quote)
                              (member (value (car i)) keywords))
                   (return nil))))))
          ((lambda-information-rest-arg lambda)
           (<= req-count arg-count))
          (t (<= req-count arg-count (+ req-count opt-count))))))

(defun lift-lambda (lambda arg-list)
  (let ((name (or (lambda-information-name lambda) 'lambda))
	(required-args (lambda-information-required-args lambda))
	(optional-args (lambda-information-optional-args lambda))
	(rest-arg (lambda-information-rest-arg lambda))
        (key-args (lambda-information-key-args lambda)))
    (when (lambda-information-environment-arg lambda)
      (warn 'sys.int::simple-style-warning
            :format-control "Not inlining ~S, has environment arg."
            :format-arguments (list name))
      (return-from lift-lambda))
    ;; Attempt to match the argument list with the function's lambda list.
    (unless (arguments-match-lambda-list lambda arg-list)
      ;; Bail out.
      (warn 'simple-warning
	    :format-control "Not inlining ~S, arguments do not match."
	    :format-arguments (list name))
      (return-from lift-lambda))
    (change-made)
    ;; Fix argument definition points.
    (dolist (arg required-args)
      (when (lexical-variable-p arg)
	(setf (lexical-variable-definition-point arg) *current-lambda*)))
    (dolist (arg optional-args)
      (when (lexical-variable-p (first arg))
	(setf (lexical-variable-definition-point (first arg)) *current-lambda*))
      (when (lexical-variable-p (third arg))
	(setf (lexical-variable-definition-point (third arg)) *current-lambda*)))
    (when (lexical-variable-p rest-arg)
      (setf (lexical-variable-definition-point rest-arg) *current-lambda*))
    (dolist (arg key-args)
      (when (lexical-variable-p (second (first arg)))
	(setf (lexical-variable-definition-point (second (first arg))) *current-lambda*))
      (when (lexical-variable-p (third arg))
	(setf (lexical-variable-definition-point (third arg)) *current-lambda*)))
    (let* ((argument-vars (mapcar (lambda (x)
                                    (declare (ignore x))
                                    (make-instance 'lexical-variable
                                                   :name (gensym)
                                                   :definition-point *current-lambda*
                                                   :ignore :maybe))
                                  arg-list))
           (key-pairs (nthcdr (length required-args) argument-vars)))
      (labels ((build-required-bindings (req-args arg-vars)
                 (cond (req-args
                        (make-instance 'ast-let
                                       :bindings (list (list (first req-args) (first arg-vars)))
                                       :body (build-required-bindings (rest req-args) (rest arg-vars))))
                       (t (build-optional-bindings optional-args arg-vars))))
               (build-optional-bindings (opt-args arg-vars)
                 (cond ((and opt-args arg-vars)
                        (destructuring-bind (var init-form suppliedp)
                            (first opt-args)
                          (declare (ignore init-form))
                          (make-instance 'ast-let
                                         :bindings (if suppliedp
                                                       `((,var ,(first arg-vars))
                                                         (,suppliedp ,(make-instance 'ast-quote :value 't)))
                                                       `((,var ,(first arg-vars))))
                                         :body (build-optional-bindings (rest opt-args) (rest arg-vars)))))
                       (opt-args
                        (destructuring-bind (var init-form suppliedp)
                            (first opt-args)
                          (make-instance 'ast-let
                                         :bindings (if suppliedp
                                                       `((,var ,init-form)
                                                         (,suppliedp ,(make-instance 'ast-quote :value 'nil)))
                                                       `((,var ,init-form)))
                                         :body (build-optional-bindings (rest opt-args) '()))))
                       (t (build-rest-binding arg-vars))))
               (build-rest-binding (arg-vars)
                 (if rest-arg
                     (make-instance 'ast-let
                                    :bindings (list (list rest-arg (make-instance 'ast-call
                                                                                  :name 'list
                                                                                  :arguments arg-vars)))
                                    :body (build-key-bindings key-args))
                     (build-key-bindings key-args)))
               (build-key-bindings (keys)
                 (cond (keys
                        (destructuring-bind ((keyword var) init-form suppliedp)
                            (first keys)
                          (do ((p 0 (+ p 2))
                               (i (nthcdr (+ (length required-args)
                                             (length optional-args))
                                          arg-list)
                                  (cddr i)))
                              ((null i)
                               ;; Not provided, use the initform.
                               (make-instance 'ast-let
                                              :bindings (if suppliedp
                                                            `((,var ,init-form)
                                                              (,suppliedp ,(make-instance 'ast-quote :value 'nil)))
                                                            `((,var ,init-form)))
                                              :body (build-key-bindings (rest keys))))
                            (when (eql (value (car i)) keyword)
                              ;; Keywords match, use this argument.
                              (return (make-instance 'ast-let
                                                     :bindings (if suppliedp
                                                                   `((,var ,(nth (1+ p) key-pairs))
                                                                     (,suppliedp ,(make-instance 'ast-quote :value 't)))
                                                                   `((,var ,(nth (1+ p) key-pairs))))
                                                     :body (build-key-bindings (rest keys))))))))
                       (t (ll-form (lambda-information-body lambda))))))
        ;; Evaluate arguments.
        (make-instance 'ast-let
                       :bindings (mapcar #'list argument-vars arg-list)
                       :body (build-required-bindings required-args argument-vars))))))

(defun ll-function-form (form)
  (ll-implicit-progn (arguments form))
  (if *should-inline-functions*
      (or (and (eql (name form) 'funcall)
               (lambda-information-p (first (arguments form)))
               (lift-lambda (first (arguments form)) (rest (arguments form))))
          ;; Couldn't lift.
          form)
      form))

(defun ll-variable (form)
  form)

(defun ll-lambda (form)
  (let ((*current-lambda* form))
    (dolist (arg (lambda-information-optional-args form))
      (setf (second arg) (ll-form (second arg))))
    (dolist (arg (lambda-information-key-args form))
      (setf (second arg) (ll-form (second arg))))
    (setf (lambda-information-body form) (ll-form (lambda-information-body form))))
  form)
