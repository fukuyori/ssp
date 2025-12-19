;;;; load.lisp
;;;; SSP - Simple loader (ASDF不要版)
;;;;
;;;; Usage:
;;;;   (load "path/to/ssp/load.lisp")
;;;;   (ssexp:start)
;;;;   ; or
;;;;   (ssp:start)

(ql:quickload :ltk :silent t)

(let ((dir (make-pathname :directory (pathname-directory *load-truename*))))
  (labels ((load-file (name)
             (load (merge-pathnames name dir))))
    (load-file "package.lisp")
    (load-file "formula.lisp")
    (load-file "core.lisp")
    (load-file "ui.lisp")
    (load-file "main.lisp")))

(format t "~%SSP loaded. Start with (ssexp:start) or (ssp:start)~%")
