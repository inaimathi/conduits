;;; -*- Mode: LISP; Base: 10; Syntax: Ansi-common-lisp; Package: (ORG.TFEB.CONDUIT-PACKAGES :use CL) -*-
;; File		     - conduit-packages.lisp
;; Description	     - Conduit packages, and package cloning
;; Author	     - Tim Bradshaw (tfb at lostwithiel)
;; Created On	     - Thu Sep 14 21:40:18 2000
;; Last Modified On  - Fri Jul  6 14:46:52 2012
;; Last Modified By  - Tim Bradshaw (tfb at kingston.local)
;; Update Count	     - 11
;; Status	     - Unknown
;; 
;; $Id: //depot/www-tfeb-org/main/www-tfeb-org/html/programs/lisp/conduit-packages.lisp#2 $
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; Conduit packages, and package cloning
;;;
;;; tfb 24-Jul-1998 00:41:02, tfb 3-Jul-2000 21:52:48
;;;
;;; Copyright 1998-2002 Tim Bradshaw.  This code may be used for any
;;; purpose whatsoever by anyone. It has no warranty whatsoever. I
;;; would appreciate acknowledgement if you use it in anger, and I
;;; would also very much appreciate any feedback or bug fixes.
;;;
;;; This generalises the stuff in VERIFY-FORM.LISP
;;;
;;; !!! TODO: more of the package operators probably need to be shadowed
;;;           Errors should be signalled as subtypes of PACKAGE-ERROR

(defpackage :org.tfeb.conduit-packages
  (:size 50)					;why bother with this...
  (:use :cl)
  ;; redefined CL names
  (:shadow #:export #:unexport #:defpackage #:delete-package #:rename-package)
  (:export #:export #:unexport #:defpackage #:delete-package #:rename-package)
  ;; non-CL thing
  (:export #:recompute-conduits))

(in-package :org.tfeb.conduit-packages)

(provide :org.tfeb.conduit-packages)

;;;; Hack to make the HP stuff `work' even when they are not loaded.
;;;

;;; Load HP if we can find it
;;;

#+org.tfeb.hierarchical-packages
(eval-when (:load-toplevel :compile-toplevel :execute)
  (when (or *load-truename* *compile-file-truename*)
    ;; This is a post-read-time check to see if it is actually 
    ;; there already
    (unless (member ':org.tfeb.hierarchical-packages
                    *features*)
      (let ((f (compile-file-pathname
                (make-pathname :name "hierarchical-packages"
                               :version :newest
                               :defaults (or *load-truename*
                                             *compile-file-truename*)))))
        (if (probe-file f)
            (load f)
          (warn "Could not load ~A, which I need"
                f))))))
                             
(defun hp-alias-map (p)
  (declare (ignorable p))
  #+org.tfeb.hierarchical-packages
  (gethash p org.tfeb.hierarchical-packages:*per-package-alias-table*)
  '())
    
(defun (setf hp-alias-map) (new p)
  ;; This one should never be called if HP is not loaded.
  (declare (ignorable new p))
  #+org.tfeb.hierarchical-packages
  (setf 
   (gethash p org.tfeb.hierarchical-packages:*per-package-alias-table*)
   new)
  #-org.tfeb.hierarchical-packages
  (error "No hierarchical packages, so aliases will not work"))

(defun delete-hp-alias-map (p)
  (declare (ignorable p))
  #+org.tfeb.hierarchical-packages
  (remhash p  org.tfeb.hierarchical-packages:*per-package-alias-table*))

;;;; Conduit implementation
;;;

(defvar *conduit-package-descriptions* '())
(defvar *package-conduits* '())
(defvar *conduit-packages* '())

(defun canonicalise-package-name (package/name)
  ;; Return a keyword, being the canonical name of the package.
  ;; Second value is the package named, if it exists.
  ;; maybe this should not use KEYWORD but our own secret package.
  (etypecase package/name
    (package (values (intern (package-name package/name) 
			     (find-package :keyword))
		     package/name))
    ((or string symbol)
     (let ((found (find-package package/name)))
       (values (intern (if found
			   (package-name found)
			   (typecase package/name
			     (string package/name)
			     (symbol (symbol-name package/name))))
		       (find-package :keyword))
	       found)))))

(defun note-conduit (pack conduit)
  (let ((pack (canonicalise-package-name pack))
	(conduit (canonicalise-package-name conduit)))
    (let ((found (assoc pack *package-conduits*)))
      (if found 
	  (pushnew conduit (cdr found))
	  (push (list pack conduit) *package-conduits*)))
    (let ((found (assoc conduit *conduit-packages*)))
      (if found
	  (pushnew pack (cdr found))
	  (push (list conduit pack) *conduit-packages*)))))

(defun recompute-conduits-for (pack &optional (chain '()))
  (let ((pack (canonicalise-package-name pack)))
    (when (member pack chain)
      (error "Circular conduits: ~S occurs in ~S" pack chain))
    (dolist (conduit (cdr (assoc pack *package-conduits*)))
      (apply #'make-package-conduit-package
	     (assoc conduit *conduit-package-descriptions*))
      (recompute-conduits-for conduit (cons pack chain)))
    (find-package pack)))

(defun clean-package-alist (pa)
  ;; return a cleaned package alist: no nulls, no singletons, no nonexistent
  ;; packages.  Just blindly cons a new list here.
  (mapcan #'(lambda (pl)
	      (let ((ppl (mapcan #'(lambda (p)
				     (if (find-package p)
					 (list p)
					 nil))
				 pl)))
		(if (or (null ppl)
			(null (cdr ppl)))
		    nil
		    (list ppl))))
	  pa))

(defun recompute-conduits ()
  "Clean up the lists of conduits, and recompute all conduit packages
to make them consistent"
  (setf *package-conduits* (clean-package-alist *package-conduits*)
	*conduit-packages* (clean-package-alist *conduit-packages*))
  (dolist (pd *package-conduits* (values))
    (recompute-conduits-for (car pd))))

		       
(defun make-package-conduit-package (package/name &key 
						  extends
						  extends/including
						  extends/excluding)
  (flet ((ensure-package (p)
	   (let ((package (etypecase p
			    (package p)
			    ((or symbol string) (find-package p)))))
	     (unless package
	       ;; might want to be able to continue
	       (error "No package named ~S" p))
	     package))
	 (ensure-external-symbol (d p)
	   (multiple-value-bind (s state)
	       (find-symbol (etypecase d
			      (symbol (symbol-name d))
			      (string d))
			    p)
	     (ecase state
	       ((:external)
		s)
	       ((nil)
		(error "Symbol name ~S not found in ~S" d p))
	       ((:internal)
		(error "Symbol ~S internal in ~S" s p))
	       ((:inherited)
		(error "Symbol ~S not directly present in ~S" s p)))))
	 (import-symbol (s pack)
	   (cl:import (if (eq s 'nil) 
			  '(nil)
			  s)
		      pack))
	 (export-symbol (s pack)
	   (cl:export (if (eq s 'nil) 
			  '(nil)
			  s)
		      pack)))
    (let ((package (ensure-package package/name)))
      (dolist (ex extends)
	(note-conduit ex package)
	(do-external-symbols (s (ensure-package ex))
	  (import-symbol s package)
	  (export-symbol s package)))
      (dolist (ei extends/including)
	(let ((p (ensure-package (first ei))))
	  (note-conduit p package)
	  (dolist (s (mapcar #'(lambda (sd)
				 (ensure-external-symbol sd p))
			     (rest ei)))
	    (import-symbol s package)
	    (export-symbol s package))))
      (dolist (ee extends/excluding)
	(let* ((p (ensure-package (first ee)))
	       (es (mapcar #'(lambda (sd)
			       (ensure-external-symbol sd p))
			   (rest ee))))
	  (note-conduit p package)
	  (do-external-symbols (s p)
	    (unless (member s es)
	      (import-symbol s package)
	      (export-symbol s package)))))
      package)))

;;; Cloning.  Unlike conduits, cloning is a static operation: making a
;;; clone of a package says to copy its state at a given moment and
;;; then ignore any further changes.  Redefining a clone package will
;;; only pick up some of the changes - in particular symbols which
;;; have been unexported from the cloned packages will not get
;;; unexported and so on.
;;;
;;; It may or may not make sense to clone multiple packages, this
;;; function `supports' that because it's kind of implicit in the way
;;; DEFPACKAGE works that you might get multiple packages.
;;;
;;; It's not clear if any of this behaviour is right.
;;;

(defun clone-packages-to-package (froms to)
  (let ((to (typecase to
              (package to)
              (t (or (find-package to)
                     (make-package to :use '()))))))
    (when (null to)
      (error "No target package..."))
    (loop for f in froms
          for from = (typecase f
                       (package f)
                       (t (find-package f)))
          for used = (package-use-list from)
          for shadows = (package-shadowing-symbols from)
          for exports = (let ((exps '()))
                          (do-external-symbols (s from exps)
                            (push s exps)))
          for interned-symbols = (let ((ints '()))
                                   (do-symbols (s from ints)
                                     (when (eq (symbol-package s) from)
                                       (push s ints))))
          when interned-symbols
          do (import interned-symbols to)
          when shadows
          do (shadow shadows to)
          when exports 
          do(export exports to)
          when used
          do (use-package used to))
    (loop with aliases = '()
          for f in froms
          for from = (typecase f
                       (package f)
                       (t (find-package f)))
          do (loop for e in (hp-alias-map from)
                   when (assoc (first e) aliases
                               :test #'string=)
                   do
                   (error "Duplicate package alias when cloning ~A" (first e))
                   do (push e aliases))
          finally (when aliases
                    ;; Make sure we only call this if there were aliases
                    (setf (hp-alias-map to) (nreverse aliases))))
    to))

;;;; Define the basic package operations we need to take over.
;;; 
;;; !!! Others may need to be added here.  I think that UNINTERN is OK,
;;; but I'm not sure about others.

(defun export (symbol/s &optional (package *package*))
  (prog1
    (cl:export symbol/s package)
    (recompute-conduits-for package)))

(defun unexport (symbol/s &optional (package *package*))
  (prog1
    (cl:unexport symbol/s package)
    (recompute-conduits-for package)))

(defmacro defpackage (name &body clauses)	;+++export
  "Define a package.  See CL:DEFPACKAGE for tha basics.
In addition, this version of DEFPACKAGE can define a `conduit package':
that you can use as a conduit to extend existing packages.
This works by importing symbols from the existing packages and 
then reexporting them. The syntax is as DEFPACKAGE, with the addition
of three new clauses:
	(:EXTENDS package) takes package and reexports all its symbols;
	(:EXTENDS/INCLUDING package . syms/names) reexports only syms/names;
	(:EXTENDS/EXCLUDING package . syms/names) reexports all *but* syms/names.
When defining a conduit package you almost certainly will want to say (:USE) 
to prevent the CL package being used.

If hierarchical packages are loaded when conduits is built (yes, I know)
Then you can also say
        (:ALIASES (name realname) ...)
Which will cause name to be a shorthand for realname when the package
Being defined is the current package.  Aliases are not inherited from
conduits.

This version of DEFPACKAGE also support `cloning' packages: making another
package which is `just like' an existing package. This means that all the
internal, exported and shadowing symbols in the clone will be the same as
those in the cloned package, but any additional things defined by DEFPACKAGE
will also take effect.  This allows you to essentially make a copy of 
a package which you can then use to define new functionality without
interning a lot of things in the original package.  Cloning is a static
operation - packages do not know who their clones are, and no attempt is made
to keep clones up to date.  Cloning is done by the clause
        (:CLONES package)
Cloning is not compatible with extending (this is checked).
As with extending you probably want to specify (:USE) when cloning."
  (let ((dpcs '()) (excs '()) (eics ()) (eecs '()) (cpcs '())
        (package-aliases '()))
    (dolist (c clauses)
      (case (first c)
	((:extend :extends)
	 (dolist (e (rest c))
	   (push e excs)))
	((:extend/including :extends/including)
	 (push (rest c) eics))
	((:extend/excluding :extends/excluding)
	 (push (rest c) eecs))
        ((:clone :clones)
         (dolist (e (rest c))
           (push e cpcs)))
        ((:alias :aliases)
         (loop for e in (rest c)
               unless (and (consp e)
                           (typep (first e)
                                  '(or symbol string))
                           (typep (second e)
                                  '(or symbol string))
                           (null (cddr e)))
               do 
               (error 
                "Package aliases should be list of (STRING STRING)")
               when (assoc (string (first e)) package-aliases
                           :test #'string=)
               do
               (error "Duplicate package alias ~A" (first e))
               do (push (cons (string (first e)) (string (second e)))
                        package-aliases)))
	(otherwise
         (push c dpcs))))
    (when (and cpcs (or excs eics eecs))
      (error "Cloning is not compatible with extending"))
    (when (and cpcs package-aliases)
      (error "Cloning is not compatible with package aliases"))
    (cond ((or excs eics eecs package-aliases)
	   `(progn
	      (cl:defpackage ,name
	        ,@(nreverse dpcs))
	      ;; need always to do this because defpackage is always done.
	      (eval-when (:compile-toplevel :load-toplevel :execute)
	        (let* ((cn (canonicalise-package-name ',name))
		       (found (assoc cn *conduit-package-descriptions*))
		       (descr '(:extends ,(nreverse excs)
			        :extends/including ,(nreverse eics)
			        :extends/excluding ,(nreverse eecs))))
	          (if found
		      (setf (cdr found) descr)
		    (push (cons cn descr) *conduit-package-descriptions*))
	          (apply #'make-package-conduit-package cn descr))
                ,@(when package-aliases
                    `((setf (hp-alias-map (find-package ',name))
                            ',(nreverse package-aliases))))
	        (recompute-conduits-for ',name))))
          (cpcs
           `(progn
              (cl:defpackage ,name
                ,@(nreverse dpcs))
              (eval-when (:compile-toplevel :load-toplevel :execute)
                (clone-packages-to-package ',cpcs ',name))))
          (t
	   `(progn
	      (cl:defpackage ,name ,@(nreverse dpcs))
	      (recompute-conduits-for ',name))))))

(defun delete-package (pack/name)
  (let ((name (canonicalise-package-name pack/name)))
    (let ((conduits (cdr (assoc name *package-conduits*))))
      (when conduits
	(error "Trying to delete ~S, but it has conduits ~S" 
	       (find-package pack/name) (mapcar #'find-package conduits))))
    (prog1 
        (progn
          (delete-hp-alias-map (find-package pack/name))
          (cl:delete-package pack/name))
      ;; NAME can occur in *CONDUIT-PACKAGES* if it was a conduit.
      ;; NAME can occur in *PACKAGE-CONDUITS* if it had conduits
      ;; (there will not now be any)
      (setf *conduit-packages* (delete name *conduit-packages* :key #'car)
	    *package-conduits* (delete name *package-conduits* :key #'car)))))



(defun rename-package (pack/name new-name &optional (nicknames '()))
  (prog1 
    (cl:rename-package pack/name new-name nicknames)
    (let ((name (canonicalise-package-name pack/name))
	  (new-name (canonicalise-package-name new-name)))
      (dolist (c *conduit-packages*)
	(nsubstitute new-name name c))
      (dolist (p *package-conduits*)
      	(nsubstitute new-name name p)))))

;;;; Define the CL/CONDUITS package and a user package.
;;;
;;; I would like to be able to say simply (EVAL-WHEN (:LOAD-TOPLEVEL
;;; ...)  ...)  here, but that breaks, because that results in
;;; DEFPACKAGE being processed as a top-level form in not-compile-time
;;; mode, and *it* expands to (EVAL-WHEN (:COMPILE-TOPLEVEL ...) ...),
;;; so actually gets evaluated at compile-time, which fails.  (LET ()
;;; ...) is just enough to stop this: LOCALLY or PROGN is not.  This is
;;; broken.
;;;
;;; CLISP 2000-03-06 (March 2000)  can't hack this at all:  you need to
;;; extract the remainder of this file and put it into a different
;;; file, compiled and loaded after the main file is loaded.
;;;
;;; CMUCL 18b can't do this.  CMUCL 18c Sources 2000-09-27 does have
;;; bugs in EVAL-WHEN, but does this right.
;;;
(eval-when (:load-toplevel :execute)
  (let ()
    (defpackage :org.tfeb.cl/conduits
      (:use)
      (:nicknames :org.tfeb.clc)
      (:extends/excluding :cl #:export #:unexport #:defpackage 
			  #:delete-package #:rename-package)
      (:extends/excluding :org.tfeb.conduit-packages
       #:recompute-conduits))
    (defpackage :org.tfeb.cl-user/conduits
      (:nicknames :org.tfeb.clc-user)
      (:use :org.tfeb.clc)))
  #+Genera
  (pushnew (find-package :org.tfeb.cl/conduits) si:*reasonable-packages*))

#||
(defpackage :cl/magic-if
  (:extends/excluding :cl #:if)
  (:export #:if))
||#
