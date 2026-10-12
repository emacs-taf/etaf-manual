;;; check-book.el --- Validate the ETAF Reference Manual sources -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Batch gate for book/.  It parses every language with the same book model
;; the reader uses and compares the result with the sibling provider
;; checkouts:
;;
;;   emacs -Q --batch -L . -L lisp -l scripts/check-book.el \
;;         [--book DIR] [--providers DIR] [--coverage]
;;
;; Problems are printed as FILE:LINE: MESSAGE on stderr and make Emacs exit
;; with status 1.  --coverage prints how many interfaces of each package and
;; vocabulary already have a definition entry.  The checks are listed in
;; docs/manual.md ("What the gate checks").

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'etaf-manual-book)

(defvar etaf-manual-check--problems nil
  "Problems found by the current run, newest first.")

(defvar etaf-manual-check--base nil
  "Directory that problem file names are reported relative to.")

(defun etaf-manual-check--problem (file line format-string &rest arguments)
  "Record a problem at FILE and LINE described by FORMAT-STRING and ARGUMENTS.
FILE is an absolute chapter file, nil for a book-wide problem, or a label
naming generated content."
  (push (format "%s:%s: %s"
                (cond ((null file) "book")
                      ((file-name-absolute-p file)
                       (file-relative-name file etaf-manual-check--base))
                      (t file))
                (or line 0)
                (apply #'format format-string arguments))
        etaf-manual-check--problems))

;;;; Provider sources

(defconst etaf-manual-check--record-regexp
  "^;; \\(Function\\|Macro\\|Variable\\|Hook\\|Error\\|Component\\): \\([^ \t\n()]+\\)\\(.*\\)$"
  "Commentary API record: KIND, NAME and the rest of the line.")

(defun etaf-manual-check--normalize (signature)
  "Return SIGNATURE with runs of whitespace collapsed and ends trimmed."
  (string-trim (replace-regexp-in-string "[ \t\n]+" " " (or signature ""))))

(defun etaf-manual-check--records (package directory)
  "Return the Commentary records of PACKAGE checked out in DIRECTORY.
Each record is (KIND NAME SIGNATURE PACKAGE) with KIND a definition kind."
  (let ((entry (expand-file-name (concat package ".el") directory)) records)
    (with-temp-buffer
      (insert-file-contents entry)
      (goto-char (point-min))
      (let ((start (and (re-search-forward "^;;; Commentary:" nil t) (point)))
            (end (and (re-search-forward "^;;; Code:" nil t) (point))))
        (when (and start end)
          (goto-char start)
          (while (re-search-forward etaf-manual-check--record-regexp end t)
            (let ((kind (intern (downcase (match-string 1))))
                  (name (intern (match-string 2)))
                  (rest (etaf-manual-check--normalize (match-string 3))))
              ;; Variable, Hook and Error records carry no signature.
              (push (list kind name (if (memq kind '(function macro component)) rest "")
                          package)
                    records))))))
    (nreverse records)))

(defun etaf-manual-check--source-files (directory package)
  "Return the Lisp sources of PACKAGE in DIRECTORY."
  (let ((entry (expand-file-name (concat package ".el") directory))
        (lisp (expand-file-name "lisp" directory)))
    (append (and (file-exists-p entry) (list entry))
            (and (file-directory-p lisp) (directory-files lisp t "\\.el\\'")))))

(defun etaf-manual-check--collect-constants (form constants)
  "Record in CONSTANTS the value of each top-level `defconst' in FORM."
  (pcase form
    (`(,(or 'progn 'eval-and-compile 'eval-when-compile) . ,body)
     (dolist (inner body) (etaf-manual-check--collect-constants inner constants)))
    (`(with-eval-after-load ,_ . ,body)
     (dolist (inner body) (etaf-manual-check--collect-constants inner constants)))
    (`(defconst ,(and name (pred symbolp)) ,value . ,_)
     (puthash name (if (eq (car-safe value) 'quote) (cadr value) value) constants))))

(defun etaf-manual-check--read-sources (files constants)
  "Read FILES, recording top-level constant values in CONSTANTS.
Return the concatenated source text for vocabulary scans."
  (with-temp-buffer
    (let ((texts nil))
      (dolist (file files)
        (erase-buffer)
        (insert-file-contents file)
        (push (buffer-string) texts)
        (goto-char (point-min))
        (condition-case nil
            (while t
              (etaf-manual-check--collect-constants (read (current-buffer)) constants))
          (end-of-file nil)
          (invalid-read-syntax
           (etaf-manual-check--problem file (line-number-at-pos)
                                       "cannot read provider source"))))
      (string-join (nreverse texts) "\n"))))

(defun etaf-manual-check--matches (regexp text group)
  "Return the distinct GROUP matches of REGEXP in TEXT as interned symbols."
  (let ((start 0) (found nil))
    (while (string-match regexp text start)
      (cl-pushnew (intern (match-string group text)) found)
      (setq start (match-end 0)))
    found))

(defun etaf-manual-check--providers (description providers)
  "Return the provider facts for book DESCRIPTION below PROVIDERS.
The result is a plist with the Commentary :records of every package and
reference, the :versions alist from package names to their entry's Version
header, and the :host, :property, :style and :token vocabularies."
  (let ((constants (make-hash-table :test #'eq))
        (texts (make-hash-table :test #'equal))
        (records nil)
        (versions nil))
    (dolist (package (append (plist-get description :packages)
                             (plist-get description :references)))
      (let ((directory (expand-file-name package providers)))
        (if (not (file-exists-p (expand-file-name (concat package ".el") directory)))
            (etaf-manual-check--problem nil nil "provider checkout missing: %s" directory)
          (with-temp-buffer
            (insert-file-contents (expand-file-name (concat package ".el") directory))
            (when (re-search-forward "^;; Version: *\\([^ \t\n]+\\)" nil t)
              (push (cons package (match-string 1)) versions)))
          (setq records (append records (etaf-manual-check--records package directory)))
          (puthash package (etaf-manual-check--read-sources
                            (etaf-manual-check--source-files directory package)
                            constants)
                   texts))))
    (list :records records :versions versions
          :host (let ((hosts (gethash 'etaf--host-names constants)))
                  (and (listp hosts) hosts))
          :property (delete-dups
                     (append (let ((props (gethash 'etaf--semantic-props constants)))
                               (and (listp props) props))
                             ;; Event props are Host props the ETAF Runtime reads.
                             (etaf-manual-check--matches "\\(:on-[a-z]+\\(?:-[a-z]+\\)*\\)\\_>"
                                                         (gethash "etaf" texts "") 1)
                             (list (intern ":aria-*"))))
          :style (etaf-manual-check--matches
                  "(:name \\(:[a-z0-9-]+\\) :id ebox/" (gethash "ebox" texts "") 1)
          :token (etaf-manual-check--matches "\\(:ui-[a-z0-9]+\\(?:-[a-z0-9]+\\)*\\)\\_>"
                                             (gethash "etaf-ui" texts "") 1))))

;;;; Book checks

(defconst etaf-manual-check--record-kinds
  '(function macro variable hook error component)
  "Definition kinds verified against Commentary records.")

(defconst etaf-manual-check--vocabulary-kinds '(host property style token)
  "Definition kinds verified against a provider vocabulary.")

(defconst etaf-manual-check--vocabulary-subjects
  '((host . "hosts") (property . "properties") (style . "styles") (token . "tokens"))
  "Coverage subject names of the vocabulary kinds.")

(defun etaf-manual-check--chapter-file (chapter)
  "Return CHAPTER's source file, or nil for generated content."
  (plist-get chapter :file))

(defun etaf-manual-check--label (chapter)
  "Return CHAPTER's report label: its file or its generated-content name."
  (or (etaf-manual-check--chapter-file chapter)
      (format "<generated:%s>" (or (plist-get chapter :generate) (plist-get chapter :id)))))

(defun etaf-manual-check--anchors (chapter)
  "Return the heading anchors CHAPTER defines."
  (append (list (etaf-manual--slug (plist-get chapter :title)))
          (mapcar (lambda (node) (plist-get node :anchor)) (plist-get chapter :nodes))
          (mapcar (lambda (definition) (plist-get definition :anchor))
                  (plist-get chapter :definitions))))

(defun etaf-manual-check--definitions (book facts)
  "Check BOOK's definition entries against provider FACTS.
Syntax entries name forms of View syntax and are not checked.
Return a hash table from (KIND . NAME) to the definition."
  (let ((seen (make-hash-table :test #'equal))
        (records (plist-get facts :records)))
    (dolist (chapter (plist-get book :chapters))
      (let ((file (etaf-manual-check--label chapter)))
        (dolist (definition (plist-get chapter :definitions))
          (let* ((kind (plist-get definition :kind))
                 (name (plist-get definition :name))
                 (line (plist-get definition :line))
                 (signature (etaf-manual-check--normalize (plist-get definition :signature)))
                 (key (cons kind name)))
            (if (gethash key seen)
                (etaf-manual-check--problem file line "duplicate %s entry for %s" kind name)
              (puthash key definition seen))
            (cond
             ((memq kind etaf-manual-check--record-kinds)
              (let ((record (cl-find-if (lambda (record)
                                          (and (eq (car record) kind) (eq (nth 1 record) name)))
                                        records)))
                (cond
                 ((null record)
                  (etaf-manual-check--problem file line "%s %s is not a Commentary record"
                                              kind name))
                 ((not (equal signature (nth 2 record)))
                  (etaf-manual-check--problem
                   file line "signature of %s differs from %s Commentary: %s"
                   name (nth 3 record) (nth 2 record))))))
             ((memq kind etaf-manual-check--vocabulary-kinds)
              (unless (memq name (plist-get facts (intern (format ":%s" kind))))
                (etaf-manual-check--problem file line "unknown %s %s" kind name))))))))
    seen))

(defun etaf-manual-check--coverage (book facts defined)
  "Return coverage rows for BOOK and report gaps in its declared coverage.
FACTS are the provider facts and DEFINED the definition table.  Each row is
\(SUBJECT DOCUMENTED TOTAL MISSING)."
  (let ((coverage (plist-get book :coverage)) rows)
    (dolist (package (plist-get book :packages))
      (let ((missing (cl-loop for record in (plist-get facts :records)
                              when (and (equal (nth 3 record) package)
                                        (not (gethash (cons (car record) (nth 1 record))
                                                      defined)))
                              collect (format "%s %s" (car record) (nth 1 record))))
            (total (cl-count package (plist-get facts :records)
                             :key (lambda (record) (nth 3 record)) :test #'equal)))
        (push (list package (- total (length missing)) total missing) rows)))
    (dolist (kind etaf-manual-check--vocabulary-kinds)
      (let* ((names (plist-get facts (intern (format ":%s" kind))))
             (missing (cl-loop for name in names
                               unless (gethash (cons kind name) defined)
                               collect (format "%s %s" kind name))))
        (push (list (alist-get kind etaf-manual-check--vocabulary-subjects)
                    (- (length names) (length missing))
                    (length names) missing)
              rows)))
    (setq rows (nreverse rows))
    (dolist (row rows)
      (when (member (car row) coverage)
        (dolist (missing (nth 3 row))
          (etaf-manual-check--problem nil nil "%s has no definition entry (coverage: %s)"
                                      missing (car row)))))
    rows))

(defun etaf-manual-check--references (book facts defined)
  "Check links and inline references in BOOK against FACTS and DEFINED.
A code span naming a symbol of a package must name a Commentary record:
the manual documents public interfaces only.
A code span naming a package and a version, such as `etaf 0.2.1', must
give the version in that package's entry header."
  (let ((chapters (make-hash-table :test #'eq))
        (prefixes (mapcar (lambda (package) (concat package "-"))
                          (plist-get book :packages)))
        (covered (plist-get book :coverage))
        (records (plist-get facts :records))
        (names (append (plist-get book :packages) (plist-get book :references))))
    (dolist (chapter (plist-get book :chapters))
      (puthash (plist-get chapter :id) chapter chapters))
    (dolist (chapter (plist-get book :chapters))
      (let ((file (etaf-manual-check--label chapter)))
        (pcase-dolist (`(,line . ,target) (plist-get chapter :links))
          (unless (string-match-p "\\`[a-z][a-z0-9+.-]*:" target)
            (let* ((hash (string-search "#" target))
                   (path (if hash (substring target 0 hash) target))
                   (anchor (and hash (substring target (1+ hash))))
                   (target-chapter
                    (cond
                     ((string-empty-p path) chapter)
                     ((string-match "\\`\\([a-z0-9]+\\(?:-[a-z0-9]+\\)*\\)\\.md\\'" path)
                      (gethash (intern (match-string 1 path)) chapters)))))
              (cond
               ((null target-chapter)
                (etaf-manual-check--problem file line "link to unknown chapter: %s" target))
               ((and anchor
                     (not (member anchor (etaf-manual-check--anchors target-chapter))))
                (etaf-manual-check--problem file line "link to unknown heading: %s"
                                            target))))))
        (pcase-dolist (`(,line . ,span) (plist-get chapter :code))
          (when (string-match "\\`\\([a-z][a-z0-9-]*\\) \\([0-9]+\\(?:\\.[0-9]+\\)+\\)\\'" span)
            (let ((version (cdr (assoc (match-string 1 span) (plist-get facts :versions)))))
              (when (and version (not (equal version (match-string 2 span))))
                (etaf-manual-check--problem file line "%s is version %s, not %s"
                                            (match-string 1 span) version
                                            (match-string 2 span)))))
          (when (and (string-match-p "\\`[a-z][a-z0-9-]*[a-z0-9]\\'" span)
                     (cl-some (lambda (prefix) (string-prefix-p prefix span)) prefixes))
            (let* ((name (intern span))
                   (record (cl-find name records :key #'cadr)))
              (cond
               ((and record (member (nth 3 record) covered)
                     (not (gethash (cons (car record) name) defined)))
                (etaf-manual-check--problem file line "`%s' has no definition entry" span))
               ((or record (member span names)))
               (t (etaf-manual-check--problem
                   file line "`%s' is not a public interface" span))))))))))

(defun etaf-manual-check--translations (books)
  "Check that every language in BOOKS has the structure of the first."
  (let ((reference (car books)))
    (dolist (book (cdr books))
      (cl-loop for chapter in (plist-get reference :chapters)
               for other in (plist-get book :chapters)
               for file = (etaf-manual-check--chapter-file other)
               do
               (unless (equal (mapcar (lambda (definition)
                                        (list (plist-get definition :kind)
                                              (plist-get definition :name)
                                              (plist-get definition :signature)))
                                      (plist-get chapter :definitions))
                              (mapcar (lambda (definition)
                                        (list (plist-get definition :kind)
                                              (plist-get definition :name)
                                              (plist-get definition :signature)))
                                      (plist-get other :definitions)))
                 (etaf-manual-check--problem file 1 "definition entries differ from %s"
                                             (plist-get reference :language)))
               (unless (equal (mapcar (lambda (node) (plist-get node :level))
                                      (plist-get chapter :nodes))
                              (mapcar (lambda (node) (plist-get node :level))
                                      (plist-get other :nodes)))
                 (etaf-manual-check--problem file 1 "section structure differs from %s"
                                             (plist-get reference :language)))
               (unless (= (length (plist-get chapter :examples))
                          (length (plist-get other :examples)))
                 (etaf-manual-check--problem file 1 "runnable examples differ from %s"
                                             (plist-get reference :language)))))))

(defconst etaf-manual-check--generated-kinds
  '((token-table token)
    (style-quick-reference style)
    (host-and-property-quick-reference host property)
    (component-quick-reference component)
    (symbol-index function macro variable hook error component property style token))
  "Definition kinds each generated appendix and index must link.")

(defun etaf-manual-check--generated (book)
  "Check that BOOK's generated content covers the interfaces and terms it promises."
  (let ((chapters (plist-get book :chapters)))
    (dolist (chapter chapters)
      (let ((name (plist-get chapter :generate))
            (links (mapcar #'cdr (plist-get chapter :links))))
        (when-let* ((kinds (alist-get name etaf-manual-check--generated-kinds)))
          (dolist (definition (cl-loop for other in chapters
                                       append (plist-get other :definitions)))
            (when (memq (plist-get definition :kind) kinds)
              (unless (member (format "%s.md#%s"
                                      (plist-get definition :chapter)
                                      (plist-get definition :anchor))
                              links)
                (etaf-manual-check--problem
                 nil nil "generated %s does not link %s %s"
                 name (plist-get definition :kind) (plist-get definition :name))))))
        (when (eq name 'concept-index)
          (dolist (other chapters)
            (dolist (record (plist-get other :index))
              (let ((target (format "%s.md#%s" (plist-get other :id)
                                    (or (plist-get record :anchor)
                                        (etaf-manual--slug (plist-get other :title))))))
                (unless (member target links)
                  (etaf-manual-check--problem
                   nil nil "generated concept index does not link %s" target)))
              (unless (string-match-p (regexp-quote (plist-get record :term))
                                      (or (plist-get chapter :content) ""))
                (etaf-manual-check--problem
                 nil nil "generated concept index does not list %s" (plist-get record :term))))))))))

(defun etaf-manual-check--orphans (book)
  "Report Markdown files in BOOK's language directory that no entry reads."
  (let* ((directory (expand-file-name (plist-get book :language)
                                      (plist-get book :directory)))
         (read (delq nil (mapcar #'etaf-manual-check--chapter-file
                                 (plist-get book :chapters)))))
    (dolist (file (and (file-directory-p directory)
                       (directory-files directory t "\\.md\\'")))
      (unless (member file read)
        (etaf-manual-check--problem file 1 "chapter is not listed in book.json")))))

(defun etaf-manual-check--line-breaks (book)
  "Report hard-wrapped paragraphs and list items in BOOK's chapters.
Each paragraph and list item is one source line, so every renderer and the
Emacs reader can fill it to the window; a line break inside a Chinese
paragraph would otherwise render as a space."
  (dolist (chapter (plist-get book :chapters))
    (let ((file (etaf-manual-check--chapter-file chapter)))
      (when (and file (file-exists-p file))
        (with-temp-buffer
          (insert-file-contents file)
          (let ((fence nil) (open nil) (line 0))
            (dolist (text (split-string (buffer-string) "\n"))
              (setq line (1+ line))
              (cond
               ((string-match-p "\\`[ \t]*```" text) (setq fence (not fence) open nil))
               (fence)
               ((string-match-p "\\`\\(?:[ \t]*\\'\\|#\\||\\|<!--\\)" text) (setq open nil))
               ((string-match-p "\\`[ \t]*\\(?:[-*+]\\|[0-9]+\\.\\) " text) (setq open t))
               (open (etaf-manual-check--problem
                      file line "hard-wrapped line: write each paragraph on one line"))
               (t (setq open t))))))))))

(defun etaf-manual-check-run (book-directory providers)
  "Check the book in BOOK-DIRECTORY against PROVIDERS; return coverage rows."
  (setq etaf-manual-check--problems nil
        etaf-manual-check--base (file-name-directory
                                 (directory-file-name (expand-file-name book-directory))))
  (let* ((description (etaf-manual--read-json
                       (expand-file-name "book.json" book-directory)))
         (facts (etaf-manual-check--providers description providers))
         (books nil) rows)
    (dolist (language (plist-get description :languages))
      (condition-case error
          (push (etaf-manual--read-book book-directory language) books)
        (etaf-manual-error
         (etaf-manual-check--problem (nth 2 error) (nth 3 error) "%s" (nth 1 error)))))
    (setq books (nreverse books))
    (dolist (book books)
      (let ((defined (etaf-manual-check--definitions book facts)))
        (etaf-manual-check--references book facts defined)
        (etaf-manual-check--generated book)
        (etaf-manual-check--orphans book)
        (etaf-manual-check--line-breaks book)
        (let ((book-rows (etaf-manual-check--coverage book facts defined)))
          (unless rows (setq rows book-rows)))))
    (when (= (length books) (length (plist-get description :languages)))
      (etaf-manual-check--translations books))
    (setq etaf-manual-check--problems
          (delete-dups (nreverse etaf-manual-check--problems)))
    rows))

(defun etaf-manual-check-main ()
  "Run the gate with the batch command-line arguments."
  (let ((book (expand-file-name "book" etaf-manual--root))
        (providers (file-name-directory (directory-file-name etaf-manual--root)))
        (coverage nil)
        (arguments command-line-args-left))
    (setq command-line-args-left nil)
    (while arguments
      (pcase (pop arguments)
        ("--book" (setq book (expand-file-name (pop arguments))))
        ("--providers" (setq providers (expand-file-name (pop arguments))))
        ("--coverage" (setq coverage t))
        (argument (error "Unknown argument: %s" argument))))
    (let ((rows (etaf-manual-check-run book providers)))
      (when coverage
        (dolist (row rows)
          (princ (format "%-10s %4d / %4d\n" (car row) (nth 1 row) (nth 2 row))))))
    (dolist (problem etaf-manual-check--problems)
      (message "%s" problem))
    (kill-emacs (if etaf-manual-check--problems 1 0))))

(when noninteractive
  (etaf-manual-check-main))

;;; check-book.el ends here
