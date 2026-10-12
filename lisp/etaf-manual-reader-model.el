;;; etaf-manual-reader-model.el --- Session state of the manual reader -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; Session state and navigation of the manual reader.  A session is a plist
;; of reactive refs plus a document cache: it owns the language, the current
;; chapter and section, the history both ways and the theme, and it can exist
;; without any buffer, so scripts and tests drive the same model the mounted
;; application uses.
;;
;; All display values are read through `etaf-value' during render, so a
;; chapter change, a language switch or a theme switch repaints exactly the
;; regions that read the changed source.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'etaf)
(require 'etaf-manual-book)
(require 'etaf-manual-reader-theme)

(declare-function etaf-manual-book "etaf-manual" (&optional language))

(defconst etaf-manual-reader--history-limit 64
  "Maximum remembered positions per direction.")

(defun etaf-manual-reader--default-language ()
  "Return the default reader language."
  (if (boundp 'etaf-manual-reader-language)
      (symbol-value 'etaf-manual-reader-language)
    "zh-CN"))

;;;; Session

(cl-defun etaf-manual-reader-create (&key language theme chapter)
  "Create a headless manual reader session and return it.
LANGUAGE defaults to `etaf-manual-reader-language', THEME to the frame's own
background mode, and CHAPTER to the manual's first chapter.  The session owns
no buffer, so it is a complete headless reader for scripts and tests."
  (let* ((language (or language (etaf-manual-reader--default-language)))
         (book (etaf-manual-book language)))
    (list
     :language (etaf-ref language :name 'etaf-manual-reader-language)
     :theme (etaf-ref (or theme (etaf-manual-reader-auto-theme))
                      :name 'etaf-manual-reader-theme)
     :chapter (etaf-ref (or chapter
                            (etaf-manual-reader--book-default-chapter book))
                        :name 'etaf-manual-reader-chapter)
     :node (etaf-ref nil :name 'etaf-manual-reader-node)
     :back (etaf-ref nil :name 'etaf-manual-reader-back)
     :forward (etaf-ref nil :name 'etaf-manual-reader-forward)
     :toc (etaf-ref nil :name 'etaf-manual-reader-toc-visible)
     :message (etaf-ref nil :name 'etaf-manual-reader-message)
     :documents (make-hash-table :test #'equal)
     :buffer nil)))

(defun etaf-manual-reader--book-default-chapter (book)
  "Return BOOK's first reading-order chapter identifier."
  (let ((chapter (or (cl-find-if (lambda (entry) (eq (plist-get entry :kind) 'chapter))
                                 (plist-get book :chapters))
                     (car (plist-get book :chapters)))))
    (plist-get chapter :id)))

(defun etaf-manual-reader--ref (session key)
  "Return SESSION's reactive source named KEY."
  (plist-get session key))

(defun etaf-manual-reader--read (session key)
  "Return SESSION's current value for KEY."
  (etaf-value (etaf-manual-reader--ref session key)))

(defun etaf-manual-reader--write (session key value)
  "Publish VALUE as SESSION's new value for KEY and return VALUE."
  (let ((ref (etaf-manual-reader--ref session key)))
    (unless (equal (etaf-value ref) value)
      (etaf-set-value ref value))
    value))

;;;; Book access

(defun etaf-manual-reader--book (session)
  "Return SESSION's book in its current language."
  (etaf-manual-book (etaf-manual-reader--read session :language)))

(defun etaf-manual-reader--chapters (session)
  "Return SESSION's chapters in reading order."
  (plist-get (etaf-manual-reader--book session) :chapters))

(defun etaf-manual-reader--chapter (session &optional id)
  "Return SESSION's chapter for ID, defaulting to the current chapter."
  (let ((id (or id (etaf-manual-reader--read session :chapter))))
    (cl-find id (etaf-manual-reader--chapters session)
             :key (lambda (chapter) (plist-get chapter :id)))))

(defun etaf-manual-reader--chapter-title (session &optional id)
  "Return the display title of SESSION's chapter ID."
  (let ((chapter (etaf-manual-reader--chapter session id)))
    (when chapter
      (if-let* ((number (plist-get chapter :number)))
          (format "%s %s" number (plist-get chapter :title))
        (plist-get chapter :title)))))

(defun etaf-manual-reader--part (session &optional id)
  "Return the part of SESSION that owns chapter ID."
  (let ((id (or id (etaf-manual-reader--read session :chapter))))
    (cl-find-if (lambda (part) (memq id (plist-get part :chapters)))
                (plist-get (etaf-manual-reader--book session) :parts))))

(defun etaf-manual-reader--nodes (session &optional id)
  "Return SESSION's section nodes of chapter ID."
  (let ((chapter (etaf-manual-reader--chapter session id)))
    (plist-get chapter :nodes)))

(defun etaf-manual-reader--node-at (session index &optional id)
  "Return SESSION's node at INDEX of chapter ID, or nil for the chapter top."
  (when index
    (nth index (etaf-manual-reader--nodes session id))))

(defun etaf-manual-reader--position-title (session)
  "Return a breadcrumb title for SESSION's current position."
  (let* ((chapter (etaf-manual-reader--read session :chapter))
         (node (etaf-manual-reader--read session :node))
         (node-title (plist-get (etaf-manual-reader--node-at session node) :title)))
    (if node-title
        (format "%s › %s" (etaf-manual-reader--chapter-title session chapter)
                node-title)
      (etaf-manual-reader--chapter-title session chapter))))

;;;; Documents

(defun etaf-manual-reader--chapter-text (chapter)
  "Return CHAPTER's markdown text.
Generated chapters carry their text as `:content'; written chapters are read
from their `:file'."
  (or (plist-get chapter :content)
      (with-temp-buffer
        (insert-file-contents (plist-get chapter :file))
        (buffer-string))))

(defun etaf-manual-reader-document (session &optional id)
  "Return SESSION's parsed markdown document of chapter ID.
The document is cached per language and chapter; the cache is not reactive,
but callers read the chapter before asking, so a chapter change re-parses."
  (let* ((language (etaf-manual-reader--read session :language))
         (id (or id (etaf-manual-reader--read session :chapter)))
         (chapter (etaf-manual-reader--chapter session id))
         (key (cons language id))
         (cache (plist-get session :documents)))
    (when chapter
      (or (gethash key cache)
          (puthash key
                   (etaf-ui-markdown-parse
                    (etaf-manual-reader--chapter-text chapter))
                   cache)))))

(defun etaf-manual-reader--document-blocks (session &optional id)
  "Return the top-level blocks of SESSION's current document."
  (plist-get (etaf-manual-reader-document session id) :children))

(defun etaf-manual-reader--chapter-examples (session &optional id)
  "Return SESSION's runnable examples of chapter ID, in document order."
  (plist-get (etaf-manual-reader--chapter session id) :examples))

(defun etaf-manual-reader--chapter-definitions (session &optional id)
  "Return SESSION's definition entries of chapter ID, in document order."
  (plist-get (etaf-manual-reader--chapter session id) :definitions))

;;;; Navigation

(defun etaf-manual-reader--record (session)
  "Return SESSION's current position as (CHAPTER . NODE)."
  (cons (etaf-manual-reader--read session :chapter)
        (etaf-manual-reader--read session :node)))

(defun etaf-manual-reader--jump (session chapter &optional node)
  "Move SESSION to CHAPTER and NODE without recording history."
  (etaf-manual-reader--write session :chapter chapter)
  (etaf-manual-reader--write session :node node)
  session)

(defun etaf-manual-reader-goto (session chapter &optional node)
  "Move SESSION to CHAPTER and NODE, recording the previous position.
NODE is a zero-based index into the chapter's nodes, or nil for the chapter
top.  Return SESSION."
  (let ((target (cons chapter node)))
    (unless (equal (etaf-manual-reader--record session) target)
      (etaf-manual-reader--write
       session :back
       (cons (etaf-manual-reader--record session)
             (seq-take (etaf-manual-reader--read session :back)
                       (1- etaf-manual-reader--history-limit))))
      (etaf-manual-reader--write session :forward nil))
    (etaf-manual-reader--jump session chapter node)))

(defun etaf-manual-reader--chapter-index (session &optional id)
  "Return the reading-order index of chapter ID in SESSION's book."
  (cl-position (or id (etaf-manual-reader--read session :chapter))
               (etaf-manual-reader--chapters session)
               :key (lambda (chapter) (plist-get chapter :id))))

(defun etaf-manual-reader--chapter-at (session index)
  "Return the chapter identifier at reading-order INDEX, or nil.
INDEX outside the book returns nil, so the end-of-book checks never read a
neighbouring chapter through a negative index."
  (when (>= index 0)
    (plist-get (nth index (etaf-manual-reader--chapters session)) :id)))

(defun etaf-manual-reader--goto-anchor (session anchor)
  "Move SESSION to the section whose anchor is ANCHOR."
  (let ((index (cl-position anchor (etaf-manual-reader--nodes session)
                            :key (lambda (node) (plist-get node :anchor))
                            :test #'equal)))
    (if index
        (etaf-manual-reader-goto session
                                 (etaf-manual-reader--read session :chapter)
                                 index)
      (etaf-manual-reader-message session (format "找不到锚点 #%s" anchor)))))

(defun etaf-manual-reader-follow (session url)
  "Open URL from SESSION's document.
In-document anchors and links to another chapter stay inside the reader;
anything else goes to the browser."
  (cond
   ((string-prefix-p "#" url)
    (etaf-manual-reader--goto-anchor session (substring url 1)))
   ((string-match "\\`\\([^#]+\\)\\(?:#\\(.*\\)\\)?\\'" url)
    (let* ((file (match-string 1 url))
           (anchor (match-string 2 url))
           (id (intern (file-name-base file))))
      (cond
       ((etaf-manual-reader--chapter session id)
        (etaf-manual-reader-goto session id)
        (when (and anchor (not (string-empty-p anchor)))
          (etaf-manual-reader--goto-anchor session anchor)))
       ((string-match-p "\\`[a-zA-Z][a-zA-Z0-9+.-]*://" url)
        (browse-url url))
       (t (etaf-manual-reader-message session (format "找不到章节 %s" file))))))
   (t (browse-url url))))

(defun etaf-manual-reader-next (session)
  "Move SESSION to the next section, rolling into the next chapter."
  (let* ((chapter (etaf-manual-reader--read session :chapter))
         (nodes (etaf-manual-reader--nodes session))
         (node (etaf-manual-reader--read session :node)))
    (cond
     ((null node) (if nodes
                      (etaf-manual-reader-goto session chapter 0)
                    (etaf-manual-reader-next-chapter session)))
     ((< node (1- (length nodes)))
      (etaf-manual-reader-goto session chapter (1+ node)))
     (t (etaf-manual-reader-next-chapter session)))))

(defun etaf-manual-reader-previous (session)
  "Move SESSION to the previous section, rolling into the previous chapter."
  (let* ((chapter (etaf-manual-reader--read session :chapter))
         (node (etaf-manual-reader--read session :node)))
    (if (or (null node) (zerop node))
        (etaf-manual-reader-previous-chapter session)
      (etaf-manual-reader-goto session chapter (1- node)))))

(defun etaf-manual-reader-next-chapter (session)
  "Move SESSION to the first section of the next chapter."
  (let ((index (etaf-manual-reader--chapter-index session)))
    (if-let* ((id (etaf-manual-reader--chapter-at session (1+ index))))
        (etaf-manual-reader-goto session id
                                 (when (etaf-manual-reader--nodes session id) 0))
      (user-error "This is the last chapter"))))

(defun etaf-manual-reader-previous-chapter (session)
  "Move SESSION to the last section of the previous chapter."
  (let ((index (etaf-manual-reader--chapter-index session)))
    (if-let* ((id (etaf-manual-reader--chapter-at session (1- index))))
        (let ((nodes (etaf-manual-reader--nodes session id)))
          (etaf-manual-reader-goto session id (when nodes (1- (length nodes)))))
      (user-error "This is the first chapter"))))

(defun etaf-manual-reader-up (session)
  "Move SESSION one level up: level 3 to its section, a section to the top."
  (let* ((chapter (etaf-manual-reader--read session :chapter))
         (nodes (etaf-manual-reader--nodes session))
         (node (etaf-manual-reader--read session :node)))
    (cond
     ((null node) (user-error "Already at the chapter top"))
     ((= (plist-get (nth node nodes) :level) 2)
      (etaf-manual-reader-goto session chapter nil))
     (t (let ((parent (cl-loop for index from (1- node) downto 0
                               when (= (plist-get (nth index nodes) :level) 2)
                               return index)))
          (etaf-manual-reader-goto session chapter parent))))))

(defun etaf-manual-reader-back (session)
  "Return SESSION to the previous position in its history."
  (let ((back (etaf-manual-reader--read session :back)))
    (unless back
      (user-error "No earlier position"))
    (etaf-manual-reader--write session :forward
                               (cons (etaf-manual-reader--record session)
                                     (etaf-manual-reader--read session :forward)))
    (etaf-manual-reader--write session :back (cdr back))
    (etaf-manual-reader--jump session (car (car back)) (cdr (car back)))))

(defun etaf-manual-reader-forward (session)
  "Move SESSION to the next position in its history."
  (let ((forward (etaf-manual-reader--read session :forward)))
    (unless forward
      (user-error "No later position"))
    (etaf-manual-reader--write session :back
                               (cons (etaf-manual-reader--record session)
                                     (etaf-manual-reader--read session :back)))
    (etaf-manual-reader--write session :forward (cdr forward))
    (etaf-manual-reader--jump session (car (car forward)) (cdr (car forward)))))

(defun etaf-manual-reader-last-chapter-p (session)
  "Return non-nil when SESSION is at the last chapter."
  (= (etaf-manual-reader--chapter-index session)
     (1- (length (etaf-manual-reader--chapters session)))))

(defun etaf-manual-reader-first-chapter-p (session)
  "Return non-nil when SESSION is at the first chapter."
  (zerop (etaf-manual-reader--chapter-index session)))

;;;; Language, theme and messages

(defun etaf-manual-reader-set-language (session language)
  "Read SESSION in LANGUAGE, keeping the chapter and the nearest section."
  (etaf-manual-book language)
  (let ((node (etaf-manual-reader--read session :node)))
    (etaf-manual-reader--write session :language language)
    (let ((nodes (etaf-manual-reader--nodes session)))
      (etaf-manual-reader--write
       session :node
       (when (and node nodes)
         (min node (1- (length nodes)))))))
  session)

(defun etaf-manual-reader-set-theme (session theme)
  "Show SESSION with palette THEME."
  (etaf-manual-reader--write session :theme theme)
  session)

(defun etaf-manual-reader-toggle-theme (session)
  "Switch SESSION between the light and dark palettes and return the new one."
  (let ((theme (if (eq (etaf-manual-reader--read session :theme) 'dark)
                   'light
                 'dark)))
    (etaf-manual-reader-set-theme session theme)
    theme))

(defun etaf-manual-reader-message (session text)
  "Show TEXT in SESSION's status area."
  (etaf-manual-reader--write session :message text))

;;;; Outline and state

(defun etaf-manual-reader-toc (session)
  "Return SESSION's navigation outline as a list of part plists.
Each part has `:number', `:title' and `:chapters'; each chapter has `:id',
`:number', `:title', `:kind', `:current' and, for the current chapter,
`:nodes' with `:title', `:level', `:anchor' and `:current'."
  (let ((current (etaf-manual-reader--read session :chapter))
        (node (etaf-manual-reader--read session :node)))
    (cl-loop for part in (plist-get (etaf-manual-reader--book session) :parts)
             collect
             (list :number (plist-get part :number)
                   :title (plist-get part :title)
                   :chapters
                   (cl-loop for id in (plist-get part :chapters)
                            for chapter = (etaf-manual-reader--chapter session id)
                            for current-p = (eq id current)
                            collect
                            (list :id id
                                  :number (plist-get chapter :number)
                                  :title (plist-get chapter :title)
                                  :kind (plist-get chapter :kind)
                                  :current current-p
                                  :nodes
                                  (when current-p
                                    (cl-loop for entry in (plist-get chapter :nodes)
                                             for index from 0
                                             collect
                                             (list :title (plist-get entry :title)
                                                   :level (plist-get entry :level)
                                                   :anchor (plist-get entry :anchor)
                                                   :index index
                                                   :current (eql index node))))))))))

(defun etaf-manual-reader-state (session)
  "Return a detached snapshot of SESSION's reading state.
Keys are `:language', `:theme', `:chapter', `:chapter-title', `:part',
`:node', `:node-title', `:nodes' (titles in order), `:position' (zero-based
chapter index), `:chapters' (count), `:can-back' and `:can-forward'."
  (let ((chapter (etaf-manual-reader--chapter session))
        (node (etaf-manual-reader--read session :node)))
    (list :language (etaf-manual-reader--read session :language)
          :theme (etaf-manual-reader--read session :theme)
          :chapter (etaf-manual-reader--read session :chapter)
          :chapter-title (plist-get chapter :title)
          :part (plist-get (etaf-manual-reader--part session) :title)
          :node node
          :node-title (plist-get (etaf-manual-reader--node-at session node) :title)
          :nodes (mapcar (lambda (entry) (plist-get entry :title))
                         (plist-get chapter :nodes))
          :position (etaf-manual-reader--chapter-index session)
          :chapters (length (etaf-manual-reader--chapters session))
          :can-back (and (etaf-manual-reader--read session :back) t)
          :can-forward (and (etaf-manual-reader--read session :forward) t))))

(provide 'etaf-manual-reader-model)
;;; etaf-manual-reader-model.el ends here
