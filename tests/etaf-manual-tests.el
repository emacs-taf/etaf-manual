;;; etaf-manual-tests.el --- Public behavior of the ETAF manual -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Scenarios exercise the book through the declared etaf-manual interfaces:
;; the parsed book, definition lookup and runnable examples.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'etaf)
(require 'etaf-manual)

(defun etaf-manual-tests--definitions (book)
  "Return (KIND NAME SIGNATURE) for every definition in BOOK."
  (cl-loop for chapter in (plist-get book :chapters)
           append (mapcar (lambda (definition)
                            (list (plist-get definition :kind)
                                  (plist-get definition :name)
                                  (plist-get definition :signature)))
                          (plist-get chapter :definitions))))

(defun etaf-manual-tests--warning-count ()
  "Return the number of lines in the warnings buffer."
  (if-let* ((buffer (get-buffer "*Warnings*")))
      (with-current-buffer buffer (count-lines (point-min) (point-max)))
    0))

(defconst etaf-manual-tests--generated-kinds
  '((token-table token)
    (style-quick-reference style)
    (host-and-property-quick-reference host property)
    (component-quick-reference component)
    (symbol-index function macro variable hook error component property style token))
  "Definition kinds each generated appendix and index promises to link.")

(ert-deftest etaf-manual-book-numbers-parts-and-chapters ()
  "Both languages list the same chapters in reading order with numbers."
  (dolist (language '("en" "zh-CN"))
    (let* ((book (etaf-manual-book language))
           (chapters (cl-remove-if-not (lambda (chapter)
                                         (eq (plist-get chapter :kind) 'chapter))
                                       (plist-get book :chapters)))
           (numbers (mapcar (lambda (chapter) (plist-get chapter :number)) chapters))
           (part-numbers (mapcar (lambda (part) (plist-get part :number))
                                 (plist-get book :parts))))
      (should (equal (plist-get book :language) language))
      (should (stringp (plist-get book :title)))
      (should (equal numbers (number-sequence 1 (length chapters))))
      (should (equal (seq-take '("I" "II" "III" "IV" "V" "VI" "VII" "VIII" "IX" "X"
                                 "XI" "XII" "XIII")
                               (length part-numbers))
                     part-numbers))
      (dolist (chapter chapters)
        (should (stringp (plist-get chapter :title)))
        (should (file-exists-p (plist-get chapter :file)))
        (should (memq (plist-get chapter :id)
                      (plist-get (cl-find (plist-get chapter :part)
                                          (plist-get book :parts)
                                          :key (lambda (part) (plist-get part :id)))
                                 :chapters)))))))

(ert-deftest etaf-manual-book-translations-share-entries ()
  "Every language has the same chapters and definition entries as English."
  (let* ((english (etaf-manual-book "en"))
         (chinese (etaf-manual-book "zh-CN"))
         (ids (lambda (book) (mapcar (lambda (chapter) (plist-get chapter :id))
                                     (plist-get book :chapters)))))
    (should (equal (funcall ids english) (funcall ids chinese)))
    (should (etaf-manual-tests--definitions english))
    (should (equal (etaf-manual-tests--definitions english)
                   (etaf-manual-tests--definitions chinese)))))

(ert-deftest etaf-manual-definition-finds-entries-by-name-and-kind ()
  "Definition lookup returns the entry's chapter, kind and anchor."
  (let ((definition (etaf-manual-definition 'etaf-ref)))
    (should (eq (plist-get definition :kind) 'function))
    (should (eq (plist-get definition :chapter) 'reactivity))
    (should (stringp (plist-get definition :anchor)))
    (should (integerp (plist-get definition :line))))
  (should (eq (plist-get (etaf-manual-definition 'etaf-ref 'function "zh-CN") :chapter)
              'reactivity))
  (should-not (etaf-manual-definition 'etaf-ref 'component))
  (should-not (etaf-manual-definition 'etaf-manual-tests-no-such-symbol)))

(ert-deftest etaf-manual-book-rejects-unknown-language ()
  "Requesting a language the book does not provide signals the manual error."
  (should (eq (car (should-error (etaf-manual-book "fr") :type 'etaf-manual-error))
              'etaf-manual-error)))

(ert-deftest etaf-manual-runnable-examples-mount ()
  "Every runnable example in every language mounts without warnings."
  (let ((warnings (etaf-manual-tests--warning-count))
        (count 0))
    (dolist (language '("en" "zh-CN"))
      (dolist (chapter (plist-get (etaf-manual-book language) :chapters))
        (dolist (example (plist-get chapter :examples))
          (let ((buffer (generate-new-buffer " *etaf-manual-example*")))
            (unwind-protect
                (let* ((view (etaf-manual-example-view example))
                       (runtime (progn (etaf-mount buffer view)
                                       (etaf-runtime-for-buffer buffer)))
                       (text (with-current-buffer buffer
                               (buffer-substring-no-properties (point-min) (point-max))))
                       (id (plist-get example :id)))
                  (should (stringp id))
                  (should (string-match-p "[^[:space:]]" text))
                  (etaf-unmount runtime)
                  (cl-incf count))
              (kill-buffer buffer))))))
    (should (> count 0))
    (should (= warnings (etaf-manual-tests--warning-count)))))

(ert-deftest etaf-manual-example-view-reports-failures ()
  "A failing example signals the manual error naming the example."
  (let ((error (should-error (etaf-manual-example-view
                              (list :id "broken-1" :code "(car 1)"))
                             :type 'etaf-manual-error)))
    (should (member "broken-1" error))))

(ert-deftest etaf-manual-generated-content-covers-the-book ()
  "Generated appendices carry content and link every interface they promise."
  (dolist (language '("en" "zh-CN"))
    (let* ((book (etaf-manual-book language))
           (chapters (plist-get book :chapters))
           (definitions (cl-loop for chapter in chapters
                                 append (plist-get chapter :definitions)))
           (generated (cl-remove-if-not (lambda (chapter)
                                          (plist-get chapter :generate))
                                        chapters)))
      (should (equal (mapcar (lambda (chapter) (plist-get chapter :generate)) generated)
                     '(token-table style-quick-reference
                       host-and-property-quick-reference component-quick-reference
                       concept-index symbol-index)))
      (dolist (chapter generated)
        (let ((content (plist-get chapter :content))
              (links (mapcar #'cdr (plist-get chapter :links)))
              (kinds (alist-get (plist-get chapter :generate)
                                etaf-manual-tests--generated-kinds)))
          (should (stringp content))
          (should (> (length content) 0))
          (should-not (plist-get chapter :file))
          (dolist (definition definitions)
            (when (memq (plist-get definition :kind) kinds)
              (should (member (format "%s.md#%s"
                                      (plist-get definition :chapter)
                                      (plist-get definition :anchor))
                              links)))))
        (when (eq (plist-get chapter :generate) 'concept-index)
          (dolist (other chapters)
            (dolist (record (plist-get other :index))
              (should (string-match-p (regexp-quote (plist-get record :term))
                                      (plist-get chapter :content))))))))))

;;; etaf-manual-tests.el ends here
