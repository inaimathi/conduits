# Conduits

*Package-level extensions for Common Lisp*

This is a trivial copy of Tim Bradshaw's [Conduits](http://www.tfeb.org/lisp/hax.html#CONDUITS), with an added `asdf` definition. I'm packaging and posting it because, as the docs say,

> ... consider someone who wanted to have the basic arithmetic operators be generic functions so they could do the usual stupid thing of defining + on strings or something.
> ...
> What you want to be able to construct is a package which is 'just like' the `cl` package, but which has its own versions of the symbols of interest.
> ...
> This could be done "by hand" -- by looping over the exported symbols of the packages you are extending -- but the conduits system provides a version of defpackage which supports this directly

and I happen to be someone who wants to extend CL so that I can do the usual stupid things of defining `+` on things other than numeric primitives (not necessarily strings).

What follows is a markdown-formatted copy of the documentation found at that link.

* * *

The `conduits` system tries to generalize the CL package system to allow for more flexible construction of packages. In particular it lets you define packages which are 'like' other packages in the sense that they share some or many symbols with them, but they extend them in some way, perhaps by having some symbols from another package. These packages are `conduits` for the packages they extend.

### Example of conduits 1: variant Lisps

As an example, consider someone who wanted to have the basic arithmetic operators be generic functions so they could do the usual stupid thing of defining `+` on strings or something. They could start by defining a package which had its own versions of the operators:

    (defpackage :generic-maths-implementation
      (:use :cl)
      (:shadow #:+ #:- #:* #:/)
      (:export #:+ #:- #:* #:/))

This is quite easy. But to use the generic-maths-implementation package, you have to do something like this:

    (defpackage :gm-user
      (:use :cl)
      (:shadowing-import-from :generic-maths-implementation
                              #:+ #:- #:* #:/))

You can't do the apparently obvious thing:

    (defpackage :gm-user
      (:use :cl)
      (:use :generic-maths-implementation))

because you get symbol clashes.

What you want to be able to construct is a package which is 'just like' the `cl` package, but which has its own versions of the symbols of interest. It's possible to do this by understanding the distinction between using a package - which simply says to look for its external symbols when looking up a symbol -- and importing symbols from it - which makes them directly present in the current package, from which they can then be exported in turn.

So you can construct a package which imports all the symbols except the interesting ones from cl, and the interesting ones from generic-maths-implementation, and then reexports all these symbols. This package then looks just like the cl package, except it has different versions of the interesting symbols.

This could be done 'by hand' -- by looping over the exported symbols of the packages you are extending -- but the conduits system provides a version of `defpackage` which supports this directly:

    (defpackage :common-lisp/generic-maths
      (:nicknames :cl/gm)
      (:use)
      (:extends/excluding :cl #:+ #:- #:* #:/)
      (:extends :generic-maths-implementation))

    (defpackage :gm-user
      (:use :cl/gm))

The cl/gm package extends cl, except for a certain set of symbols, and extends generic-maths-implementation.

### Example of conduits 2: sub-common-lisps

Another thing that the conduit system can do is to allow you extend a package including only some symbols. This allows you to define subset dialects of the language in a fairly flexible way:

    (defpackage :tiny-lisp
      (:use)
      (:extends/including :cl #:lambda #:t #:nil #:if #:eq))

### Other things the package can do

Various features have accreted to conduits since the original implementation. These are much less well tested than the main functionality, which has now been used for a fairly large system. Most of the reason for these features being here is that I want to have just one `defpackage` macro. The documentation for these things is also even more sketchy than the conduit documentation proper.

###### Package cloning

You can 'clone' a package by creating a new package which has the same symbols, package use lists, imports, exports and so on. This is useful for taking a 'snapshot' of a package - things newly interned in the cloned package will not perturb the original package. Cloning is not compatible with extending.

    (defpackage :foo
      (:use :cl)
      (:export #:grun #:grob))

    (defpackage :foo-clone
      (:use)
      (:clones :foo))

    ;;; Now we could do things in FOO-CLONE such as intern new symbols &c
    ;;; which would not change FOO.  But FOO-CLONE:GRUN is EQ to FOO:GRUN

###### Per-package aliases

It is (arguably) nice to be able to have 'shorthands' for package names which are defined per-package: `if I'm in the ORG.TFEB.CLC-USER package, I want CL to refer to ORG.TFEB.CLC, so CL:DEFPACKAGE will mean ORG.TFEB.CLC:DEFPACKAGE'. The conduit system can now do this, in conjunction with the hierarchical packages hack.

    (defpackage :com.cley.cl-user
      (:nicknames :com.cley.user)
      (:use :org.tfeb.clc)
      (:aliases 
       ;; This means: if *PACKAGE* is COM.CLEY.CL-USER then CL:x means
       ;; ORG.TFEB.CLC:x.  Note the order is (alias real-name).
       (:cl :org.tfeb.clc)))

Because this trick depends on the hierarchical packages it will not work in all Lisps. Further, you need to have compiled and loaded the hierarchical packages code before compiling conduits to get this support, and you need to have the hierarchical packages fasl file in the same directory as the conduits fasl file at load time, if it is not already loaded, so it can be automatically dragged in.

### Notes on conduits

it's quite easy to define a 'static' conduit system, which allows you to define conduit packages as above. This is adequate for many purposes. However since Lisp is a dynamic language, it is desirable that the conduit packages have dynamic behavior: if a package which they extend changes the symbols it exports, they too should change the symbols they export. The current implementation tries to do this by defining its own versions of many of the package-manipulating functions. In particular the cl/conduits package -- nicknamed `clc` -- as well as defining a version of `defpackage`, defines versions of `export`, `unexport`, `delete-package` and `rename-package` which are 'conduits-aware'. The `clc` package is itself a conduit, of course.

Because of obscure implementation bugs in the handling of nested `eval-when` forms, the conduits package can not be compiled as one file in (at least) CLISP and old versions of CMUCL. You need to put the definition of the clc package in a separate file and compile it only after the main drag is loaded. Allegro CL, Genera, and recent versions of CMUCL can compile it successfully. I'd appreciate feedback on any other implementations.

There is no documented function-level interface to any of the conduits functionality. There should be.

The conduits system has been used in a fairly large application, and many smaller ones, and I'm fairly sure that the basic functionality works pretty well. The dynamic behaviour is less well-tested, and the per package alias code has had minimal testing. Please report any bugs!
