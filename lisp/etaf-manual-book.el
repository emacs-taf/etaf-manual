;;; etaf-manual-book.el --- Book model of the ETAF Reference Manual -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Internal reader for the book sources below book/.  The format is described
;; in docs/manual.md: book/book.json orders parts, chapters and appendices;
;; each chapter is one Markdown file per language.  This module turns those
;; files into plists: headings become nodes, `#### Kind: name signature'
;; headings become definition entries and `elisp :run' fences become
;; runnable examples.  The public shapes are documented in etaf-manual.el.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(define-error 'etaf-manual-error "ETAF manual error")

(defconst etaf-manual--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root directory of the etaf-manual checkout or installed package.")

(defconst etaf-manual--definition-kinds
  '(("Function" . function) ("Macro" . macro) ("Variable" . variable)
    ("Hook" . hook) ("Error" . error) ("Component" . component)
    ("Host" . host) ("Property" . property) ("Style" . style)
    ("Token" . token) ("Syntax" . syntax))
  "Definition heading labels and the kind symbols they denote.")

(defconst etaf-manual--definition-regexp
  (concat "\\`\\(" (regexp-opt (mapcar #'car etaf-manual--definition-kinds))
          "\\): \\([^ \t\n]+\\)\\(?:[ \t]+\\(.*?\\)\\)?[ \t]*\\'")
  "Match the text of a definition heading: KIND, NAME and SIGNATURE.")

(defvar etaf-manual--cache (make-hash-table :test #'equal)
  "Parsed books keyed by (DIRECTORY . LANGUAGE), validated by file times.")

;;;; Text helpers

(defun etaf-manual--slug (text)
  "Return the GitHub-compatible heading anchor of TEXT.
Inline links contribute their text; letters, numbers, marks, hyphens and
underscores are kept, spaces become hyphens and everything else is dropped."
  (let ((plain (replace-regexp-in-string
                "\\[\\([^]]*\\)\\]([^)]*)" "\\1" text)))
    (apply #'string
           (cl-loop for char across (downcase plain)
                    for category = (get-char-code-property char 'general-category)
                    if (eq char ?\s) collect ?-
                    else if (or (memq char '(?- ?_))
                                (memq (aref (symbol-name category) 0) '(?L ?N ?M)))
                    collect char))))

(defun etaf-manual--unique-anchor (slug seen)
  "Return SLUG made unique against hash table SEEN, recording it."
  (let ((count (gethash slug seen)))
    (puthash slug (1+ (or count -1)) seen)
    (if count (format "%s-%d" slug (1+ count)) slug)))

(defun etaf-manual--inline-code (line)
  "Return the contents of single-line inline code spans in LINE."
  (let ((start 0) spans)
    (while (string-match "\\(`+\\)\\(.+?\\)\\1" line start)
      (push (string-trim (match-string 2 line)) spans)
      (setq start (match-end 0)))
    (nreverse spans)))

(defun etaf-manual--links (line)
  "Return Markdown link targets in LINE outside inline code."
  (let ((text (replace-regexp-in-string "\\(`+\\).+?\\1" "" line))
        (start 0) targets)
    (while (string-match "\\](\\([^) \t]+\\)\\(?:[ \t]+\"[^\"]*\"\\)?)" text start)
      (push (match-string 1 text) targets)
      (setq start (match-end 0)))
    (nreverse targets)))

;;;; Chapters

(defun etaf-manual--parse-chapter (file id)
  "Parse chapter FILE with identifier ID into a partial chapter plist."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((seen (make-hash-table :test #'equal))
          (line-number 0) fence title nodes definitions examples links code
          index example-start example-lines)
      (dolist (line (split-string (buffer-string) "\n"))
        (cl-incf line-number)
        (cond
         ;; Inside a fence: collect example text until the closing fence.
         (fence
          (if (string-match-p (concat "\\`[ ]\\{0,3\\}" (regexp-quote fence) "[`~]*[ \t]*\\'") line)
              (progn
                (when example-start
                  (push (list :id (format "%s-%d" id (1+ (length examples)))
                              :chapter id :line example-start
                              :code (string-join (nreverse example-lines) "\n"))
                        examples))
                (setq fence nil example-start nil example-lines nil))
            (when example-start (push line example-lines))))
         ((string-match "\\`[ ]\\{0,3\\}\\(```+\\|~~~+\\)[ \t]*\\(.*\\)\\'" line)
          (setq fence (match-string 1 line))
          (when (string-match-p "\\`elisp[ \t]+:run\\b" (match-string 2 line))
            (setq example-start line-number)))
         ((string-match "\\`\\(#\\{1,6\\}\\)[ \t]+\\(.*?\\)[ \t]*#*[ \t]*\\'" line)
          (let* ((level (length (match-string 1 line)))
                 (text (match-string 2 line))
                 (anchor (etaf-manual--unique-anchor (etaf-manual--slug text) seen)))
            (cond
             ((= level 1)
              (if title
                  (signal 'etaf-manual-error (list "Chapter has several titles" file line-number))
                (setq title text)))
             ((= level 4)
              (if (string-match etaf-manual--definition-regexp text)
                  (push (list :kind (cdr (assoc (match-string 1 text)
                                                etaf-manual--definition-kinds))
                              :name (intern (match-string 2 text))
                              :signature (or (match-string 3 text) "")
                              :anchor anchor :line line-number :chapter id)
                        definitions)
                (signal 'etaf-manual-error
                        (list "Level-4 headings are definition entries" file line-number))))
             ((> level 4)
              (signal 'etaf-manual-error (list "Headings deeper than level 4" file line-number))))
            (when (memq level '(2 3))
              (push (list :level level :title text :anchor anchor :line line-number)
                    nodes))
            (dolist (target (etaf-manual--links text))
              (push (cons line-number target) links))))
         (t
          (when (string-match "\\`<!--[ \t]*index:[ \t]*\\(.*?\\)[ \t]*-->\\'" line)
            (dolist (term (split-string (match-string 1 line) ";" t "[ \t]+"))
              (push (list :term term :line line-number) index)))
          (dolist (target (etaf-manual--links line))
            (push (cons line-number target) links))
          (dolist (span (etaf-manual--inline-code line))
            (push (cons line-number span) code)))))
      (when fence
        (signal 'etaf-manual-error (list "Unclosed code fence" file)))
      (unless title
        (signal 'etaf-manual-error (list "Chapter needs a level-1 title" file)))
      (list :title title :file file :nodes (nreverse nodes)
            :definitions (nreverse definitions) :examples (nreverse examples)
            :links (nreverse links) :code (nreverse code) :index (nreverse index)))))

;;;; Books

(defun etaf-manual--roman (number)
  "Return NUMBER as an uppercase Roman numeral."
  (let ((result "") (rest number))
    (pcase-dolist (`(,value . ,glyph)
                   '((1000 . "M") (900 . "CM") (500 . "D") (400 . "CD")
                     (100 . "C") (90 . "XC") (50 . "L") (40 . "XL")
                     (10 . "X") (9 . "IX") (5 . "V") (4 . "IV") (1 . "I")))
      (while (>= rest value)
        (setq result (concat result glyph) rest (- rest value))))
    result))

(defun etaf-manual--read-json (file)
  "Read FILE as JSON with plist objects and list arrays."
  (condition-case error
      (json-parse-string
       (with-temp-buffer (insert-file-contents file) (buffer-string))
       :object-type 'plist :array-type 'list :null-object nil :false-object nil)
    (file-missing (signal 'etaf-manual-error (list "Missing book description" file)))
    (json-error (signal 'etaf-manual-error (list "Invalid book description" file error)))))

(defun etaf-manual--localized (value language)
  "Return LANGUAGE's string from title plist VALUE."
  (or (plist-get value (intern (concat ":" language)))
      (plist-get value :en)))

(defun etaf-manual--book-files (directory language description)
  "Return the chapter files DESCRIPTION reads in LANGUAGE below DIRECTORY."
  (let (files)
    (dolist (part (plist-get description :parts))
      (dolist (chapter (plist-get part :chapters))
        (push (expand-file-name (format "%s/%s.md" language chapter) directory) files)))
    (dolist (appendix (plist-get description :appendices))
      (unless (plist-get appendix :generate)
        (push (expand-file-name (format "%s/%s.md" language (plist-get appendix :id))
                                directory)
              files)))
    (nreverse files)))

(defun etaf-manual--stamp (files)
  "Return modification times of FILES, nil for missing files."
  (mapcar (lambda (file) (file-attribute-modification-time (file-attributes file)))
          files))

(defun etaf-manual--read-book (directory language)
  "Parse the book below DIRECTORY in LANGUAGE, reusing an unchanged result."
  (let* ((directory (file-name-as-directory (expand-file-name directory)))
         (description (etaf-manual--read-json (expand-file-name "book.json" directory)))
         (languages (plist-get description :languages)))
    (unless (member language languages)
      (signal 'etaf-manual-error (list "Unsupported manual language" language languages)))
    (let* ((files (cons (expand-file-name "book.json" directory)
                        (etaf-manual--book-files directory language description)))
           (key (cons directory language))
           (stamp (etaf-manual--stamp files))
           (cached (gethash key etaf-manual--cache)))
      (if (and cached (equal (car cached) stamp))
          (cdr cached)
        (let ((book (etaf-manual--build-book directory language description)))
          (puthash key (cons stamp book) etaf-manual--cache)
          book)))))

(defun etaf-manual--build-book (directory language description)
  "Build LANGUAGE's book plist from DESCRIPTION below DIRECTORY."
  (let ((chapter-number 0) (part-number 0) (appendix-number 0) parts chapters)
    (dolist (part (plist-get description :parts))
      (let ((part-id (intern (plist-get part :id))) ids)
        (dolist (slug (plist-get part :chapters))
          (let* ((id (intern slug))
                 (file (expand-file-name (format "%s/%s.md" language slug) directory)))
            (unless (file-exists-p file)
              (signal 'etaf-manual-error (list "Missing chapter" file)))
            (push id ids)
            (push (append (list :id id :kind 'chapter :number (cl-incf chapter-number)
                                :part part-id)
                          (etaf-manual--parse-chapter file id))
                  chapters)))
        (push (list :id part-id :number (etaf-manual--roman (cl-incf part-number))
                    :title (etaf-manual--localized (plist-get part :title) language)
                    :chapters (nreverse ids))
              parts)))
    (dolist (appendix (plist-get description :appendices))
      (let* ((id (intern (plist-get appendix :id)))
             (generate (plist-get appendix :generate))
             (number (string (+ ?A appendix-number))))
        (cl-incf appendix-number)
        (push (if generate
                  (list :id id :kind 'appendix :number number :generate (intern generate)
                        :title (etaf-manual--localized (plist-get appendix :title) language)
                        :nodes nil :definitions nil :examples nil)
                (append (list :id id :kind 'appendix :number number)
                        (etaf-manual--parse-chapter
                         (expand-file-name (format "%s/%s.md" language id) directory)
                         id)))
              chapters)))
    (dolist (index (plist-get description :indices))
      (push (list :id (intern (plist-get index :id)) :kind 'index
                  :generate (intern (plist-get index :generate))
                  :title (etaf-manual--localized (plist-get index :title) language)
                  :nodes nil :definitions nil :examples nil)
            chapters))
    (list :language language :directory directory
          :title (etaf-manual--localized (plist-get description :title) language)
          :packages (plist-get description :packages)
          :references (plist-get description :references)
          :coverage (plist-get description :coverage)
          :languages (plist-get description :languages)
          :parts (nreverse parts) :chapters (nreverse chapters))))

(provide 'etaf-manual-book)
;;; etaf-manual-book.el ends here
