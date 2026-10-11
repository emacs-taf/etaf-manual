;;; etaf-manual.el --- The ETAF Reference Manual -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: ETAF contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf "0.2.1") (etaf-ui "0.1.0"))
;; URL: https://gitea.gklazycat.heiyu.space/emacs-taf/etaf-manual

;;; Commentary:

;; The ETAF Reference Manual documents the core ETAF packages (ecss, ekp,
;; ebox, etaf, etaf-ui and etaf-db) in English and Simplified Chinese.  The
;; chapters live below book/ as Markdown; this package reads them as data so
;; Emacs tools and the site build share one source.
;;
;; Public API
;;
;; Load this package with (require 'etaf-manual) after adding the repository
;; root to load-path.
;; Only the interfaces listed below are supported for use by other packages.
;; All unlisted symbols and implementation features are internal, including
;; names without a double hyphen. Do not require files below lisp/ from consumers.
;; This Commentary is the authoritative export list; docs/manual.md describes
;; the book format and how to build and check the manual.
;;
;; Variable: etaf-manual-language
;; Language code of the manual read by default: "en" or "zh-CN".
;;
;; Function: etaf-manual-book (&optional language)
;;;###autoload (autoload 'etaf-manual-book "etaf-manual" nil nil)
;; Return the manual in LANGUAGE (default `etaf-manual-language') as a plist.
;;
;; The plist has :language, :title, :parts and :chapters.  Each part is
;; (:id ID :number ROMAN :title STRING :chapters IDS).  :chapters lists every
;; chapter, appendix and index in reading order; each is a plist with :id
;; (a symbol), :kind (`chapter', `appendix' or `index'), :number (an integer
;; for chapters, a letter string for appendices, nil for indices), :title and
;; :definitions, :nodes and :examples lists.  Written chapters also have :part
;; and :file; generated appendices and indices have :generate naming their
;; content.  A node is (:level 2-or-3 :title STRING :anchor STRING :line N).
;; A definition is (:kind KIND :name SYMBOL :signature STRING :anchor STRING
;; :line N :chapter ID).  An example is (:id STRING :chapter ID :line N
;; :code STRING).  The result is cached until a source file changes; treat
;; it as read-only.  Signals `etaf-manual-error' when book/book.json or a
;; chapter is missing or malformed, or LANGUAGE is not provided.
;;
;; Function: etaf-manual-definition (name &optional kind language)
;;;###autoload (autoload 'etaf-manual-definition "etaf-manual" nil nil)
;; Return the definition entry of symbol NAME in LANGUAGE, or nil.
;; KIND restricts the match to one definition kind: `function', `macro',
;; `component' or `style' when NAME has several entries; otherwise the first
;; entry in reading order is returned.  The result has the definition shape
;; described for `etaf-manual-book'.
;;
;; Function: etaf-manual-example-view (example)
;;;###autoload (autoload 'etaf-manual-example-view "etaf-manual" nil nil)
;; Evaluate runnable EXAMPLE from `etaf-manual-book' and return its View.
;;
;; The code is read and evaluated form by form with lexical binding, with
;; etaf and etaf-ui loaded; the value of the last form is returned and must
;; be an ETAF View suitable for `etaf-mount'.  Component definitions in the
;; example may be evaluated again, so an example can be rerun after its
;; previous Runtime was unmounted.  Read and evaluation failures signal
;; `etaf-manual-error' with the example identifier and the original error.
;;
;; Error: etaf-manual-error
;; ETAF manual error
;; Signaled for malformed book sources and failing runnable examples.

;;; Code:

;;;###autoload
(eval-and-compile
  (add-to-list 'load-path
               (expand-file-name "lisp"
                                 (file-name-directory
                                  (or load-file-name
                                      (bound-and-true-p byte-compile-current-file)
                                      buffer-file-name)))))

(require 'cl-lib)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-manual-book)

(defgroup etaf-manual nil
  "The ETAF Reference Manual."
  :group 'etaf
  :prefix "etaf-manual-")

(defcustom etaf-manual-language "en"
  "Language code of the manual read by default."
  :type '(choice (const :tag "English" "en")
                 (const :tag "Simplified Chinese" "zh-CN"))
  :group 'etaf-manual)

(defun etaf-manual-book (&optional language)
  "Return the manual in LANGUAGE as a plist; see the package Commentary."
  (etaf-manual--read-book (expand-file-name "book" etaf-manual--root)
                          (or language etaf-manual-language)))

(defun etaf-manual-definition (name &optional kind language)
  "Return the definition of NAME, optionally of KIND, in LANGUAGE."
  (cl-loop for chapter in (plist-get (etaf-manual-book language) :chapters)
           thereis (cl-loop for definition in (plist-get chapter :definitions)
                            when (and (eq (plist-get definition :name) name)
                                      (or (null kind)
                                          (eq (plist-get definition :kind) kind)))
                            return definition)))

(defun etaf-manual-example-view (example)
  "Evaluate runnable EXAMPLE and return the View of its last form."
  (let ((id (plist-get example :id))
        (code (plist-get example :code)))
    (condition-case error
        (etaf-component-redefine-run
         (lambda ()
           (let ((position 0) (value nil) form)
             (while (setq form (condition-case nil
                                   (let ((read (read-from-string code position)))
                                     (setq position (cdr read))
                                     (list (car read)))
                                 (end-of-file nil)))
               (setq value (eval (car form) t)))
             value)))
      (error (signal 'etaf-manual-error (list "Runnable example failed" id error))))))

(provide 'etaf-manual)
;;; etaf-manual.el ends here
