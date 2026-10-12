;;; etaf-manual-reader-article.el --- Article and example rendering of the manual reader -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; The article layer of the manual reader.  It splits a chapter document into
;; section units, turns definition entries into cards and runnable examples
;; into interactive viewers, and renders everything else through the shared
;; `etaf-ui' markdown renderer.  The example viewer is the document's
;; self-explaining surface: source, live preview and side-by-side modes in one
;; card, with the preview being the real, interactive ETAF View the example
;; builds.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-manual-reader-style)
(require 'etaf-manual-reader-model)

(declare-function etaf-manual-example-view "etaf-manual" (example))
(declare-function etaf-ui-markdown-view-block "etaf-ui" (block env))
(declare-function etaf-ui-markdown-view-blocks "etaf-ui" (blocks env &optional tight))

(defconst etaf-manual-reader--definition-regexp
  "\\`\\([A-Za-z]+\\): \\([^ \t\n]+\\)\\(?:[ \t]+\\(.*?\\)\\)?[ \t]*\\'"
  "Match the text of a definition heading: KIND, NAME and SIGNATURE.")

(defconst etaf-manual-reader--definition-badges
  '(("Function" . info) ("Macro" . important) ("Variable" . neutral)
    ("Hook" . neutral) ("Error" . danger) ("Component" . success)
    ("Host" . neutral) ("Property" . neutral) ("Style" . neutral)
    ("Token" . warning) ("Syntax" . neutral))
  "Definition kind labels and the badge variant they paint.")

;;;; Sections

(defun etaf-manual-reader--sections (blocks)
  "Split BLOCKS into (HEAD . SECTIONS).
HEAD holds the blocks before the first level-2 or level-3 heading (the
chapter title among them).  SECTIONS is a list of (INDEX . BLOCKS) in
document order, where INDEX counts the chapter's section nodes."
  (let (head sections (current nil) (index -1))
    (dolist (block blocks)
      (if (and (eq (plist-get block :type) 'heading)
               (memq (plist-get block :level) '(2 3)))
          (progn
            (when current
              (push (cons index (nreverse current)) sections))
            (setq current (list block))
            (cl-incf index))
        (if current
            (push block current)
          (push block head))))
    (when current
      (push (cons index (nreverse current)) sections))
    (cons (nreverse head) (nreverse sections))))

(defun etaf-manual-reader--heading-text (block)
  "Return BLOCK's plain heading text."
  (string-trim
   (mapconcat (lambda (node)
                (or (plist-get node :text) ""))
              (plist-get block :children)
              "")))

;;;; Rendering environment

(defun etaf-manual-reader--doc-env (env)
  "Return ENV adapted for the shared markdown renderer."
  (list :palette (plist-get env :palette)
        :features (plist-get env :markdown-features)
        :open-link (plist-get env :open-link)
        :footnote-jump (plist-get env :footnote-jump)
        :render-code-block (plist-get env :render-code-block)
        :line-grid t))

(defun etaf-manual-reader--code-pane (env text &optional language)
  "Return the source pane for TEXT with optional LANGUAGE tag.
The tag sits on the pane's first line, right-aligned, so the pane needs no
caption row of its own."
  (etaf-node 'column
             (list :width 'stretch
                   :item-gap '(lh 0)
                   :background-color (etaf-manual-reader--color env :panel2)
                   :box-sizing 'border-box
                   :padding-top (if language '(lh 0) '(lh 1))
                   :padding-bottom '(lh 1)
                   :padding-left '(ch 2)
                   :padding-right '(ch 2))
             (append
              (when language
                (list (etaf-node 'flex
                                 (list :width 'stretch :justify-content 'flex-end)
                                 (list (etaf-manual-reader--label env language)))))
              (list (etaf-node 'box
                               (list :width 'stretch :wrap-mode 'char)
                               (list (etaf-node 'text
                                                (list :font-family (etaf-manual-reader--mono-family)
                                                      :color (etaf-manual-reader--color env :ink))
                                                (list text))))))))

;;;; Example viewer

(defun etaf-manual-reader--run-example (example result)
  "Evaluate EXAMPLE and publish its View or its error into RESULT."
  (condition-case error
      (etaf-set-value result (list :view (etaf-manual-example-view example)))
    (error (etaf-set-value result (list :error (error-message-string error))))))

(defun etaf-manual-reader--example-preview (example result)
  "Return the preview surface of EXAMPLE backed by RESULT."
  (let ((outcome (etaf-value result)))
    (cond
     ((plist-get outcome :view)
      (etaf-node 'box
                 (list :width 'stretch :box-sizing 'border-box
                       :min-height '(lh 4)
                       :padding '((lh 1) (ch 2)))
                 (list (plist-get outcome :view))))
     ((plist-get outcome :error)
      (etaf-node 'etaf-alert
                 (list :title "示例运行失败"
                       :message (plist-get outcome :error)
                       :variant 'danger)
                 nil))
     (t
      (etaf-node 'etaf-empty
                 (list :title "尚未运行"
                       :description "运行示例，这里会出现真实的 ETAF 界面。"
                       :action-label "▶ 运行"
                       :on-action (lambda ()
                                    (etaf-manual-reader--run-example example result)))
                 nil)))))

(etaf-define-component etaf-manual-reader--example
    (&key example env)
  "Render one runnable EXAMPLE with source, preview and split modes."
  :bindings ((mode (etaf-ref "preview" :name 'etaf-manual-example-mode))
             (result (etaf-ref nil :name 'etaf-manual-example-result)))
  :render
  (let* ((current (etaf-value mode))
         (id (plist-get example :id))
         (run-ref (intern (format "etaf-manual-example-run-%s" id)))
         (stop-ref (intern (format "etaf-manual-example-stop-%s" id)))
         (source (plist-get example :code))
         (language (or (plist-get example :language) "elisp"))
         (code (etaf-manual-reader--code-pane env source language))
         (preview (etaf-manual-reader--example-preview example result))
         (running (etaf-value result))
         (toolbar
          (etaf-node 'flex
                     (list :width 'stretch
                           :flex-direction 'row
                           :background-color (etaf-manual-reader--color env :panel2)
                           :border-bottom (etaf-manual-reader--border env)
                           :box-sizing 'border-box
                           :padding '((lh 0) (ch 1))
                           :column-gap '(ch 2)
                           :align-items 'center)
                     (list
                      (etaf-manual-reader--label
                       env (format "可运行示例 · %s" (plist-get example :id)))
                      (etaf-node 'etaf-tabs
                                 (list :items (list (list :key "source" :label "源码"
                                                          :ref (intern (format "etaf-manual-example-source-%s" id)))
                                                    (list :key "preview" :label "预览"
                                                          :ref (intern (format "etaf-manual-example-preview-%s" id)))
                                                    (list :key "split" :label "并排"
                                                          :ref (intern (format "etaf-manual-example-split-%s" id))))
                                       :active current
                                       :variant 'underline
                                       :width 'max-content
                                       :on-change (lambda (key) (etaf-set-value mode key)))
                                 nil)
                      (etaf-node 'box
                                 (list :flex-grow 1 :flex-basis '(px 0) :min-width '(px 0))
                                 nil)
                      (etaf-node 'etaf-button
                                 (list :ref run-ref
                                       :label (if running "重新运行" "▶ 运行")
                                       :variant 'primary
                                       :on-press (lambda ()
                                                   (etaf-manual-reader--run-example
                                                    example result)))
                                 nil)
                      (when running
                        (etaf-node 'etaf-button
                                   (list :ref stop-ref
                                         :label "■ 停止"
                                         :variant 'ghost
                                         :on-press (lambda () (etaf-set-value result nil)))
                                   nil)))))
         (content
          (pcase current
            ("source" (list code))
            ("preview" (list (etaf-node 'box
                                       (list :width 'stretch
                                             :box-sizing 'border-box
                                             :padding '((lh 1) (ch 2)))
                                       (list preview))))
            (_ (list
                (etaf-node 'flex
                           (list :width 'stretch
                                 :flex-wrap 'wrap
                                 :align-items 'flex-start
                                 :gap '((lh 1) (ch 2)))
                           (list
                            (etaf-node 'column
                                       (list :flex-grow 1 :flex-basis '(ch 40)
                                             :min-width '(ch 32)
                                             :item-gap '(lh 0))
                                       (list
                                        (etaf-manual-reader--label env "源码")
                                        code))
                            (etaf-node 'column
                                       (list :flex-grow 1 :flex-basis '(ch 40)
                                             :min-width '(ch 32)
                                             :item-gap '(lh 0))
                                       (list
                                        (etaf-manual-reader--label env "预览")
                                        preview)))))))))
    (etaf-node 'column
               (list :width 'stretch
                     :background-color (etaf-manual-reader--color env :panel)
                     :border (etaf-manual-reader--border env)
                     :box-sizing 'border-box
                     :item-gap '(lh 0))
               (append
                (list toolbar)
                (list (etaf-node 'column
                                 (list :width 'stretch :item-gap '(lh 0))
                                 content))))))

(defun etaf-manual-reader--example-viewer (example env)
  "Return the viewer View for EXAMPLE in ENV."
  (etaf-node 'etaf-manual-reader--example
             (list :example example :env env)
             nil))

;;;; Definition cards

(defun etaf-manual-reader--definition-parts (heading)
  "Return (KIND NAME SIGNATURE) from a level-4 definition HEADING, or nil."
  (let ((text (etaf-manual-reader--heading-text heading)))
    (when (string-match etaf-manual-reader--definition-regexp text)
      (list (match-string 1 text)
            (match-string 2 text)
            (or (match-string 3 text) "")))))

(defun etaf-manual-reader--definition-card (definition-heading blocks env)
  "Return the card View for a definition entry.
DEFINITION-HEADING is the level-4 heading block and BLOCKS its body blocks."
  (pcase-let* ((`(,kind ,name ,signature)
                (etaf-manual-reader--definition-parts definition-heading))
               (badge (or (cdr (assoc kind etaf-manual-reader--definition-badges))
                          'neutral))
               (ref (intern (format "etaf-manual-definition-%s" name))))
    (etaf-node 'box
               (list :ref ref
                     :width 'stretch
                     :background-color (etaf-manual-reader--color env :panel)
                     :border-left (list '(px 3) 'solid
                                        (etaf-manual-reader--color env :accent))
                     :box-sizing 'border-box
                     :padding etaf-manual-reader--card-pad)
               (append
                (list
                 (etaf-node 'row
                            (list :width 'stretch
                                  :item-gap '(ch 2)
                                  :cross-align 'center)
                            (list
                             (etaf-node 'etaf-badge
                                        (list :text kind :variant badge)
                                        nil)
                             (etaf-node 'text
                                        (list :font-weight 'bold
                                              :color (etaf-manual-reader--color env :heading))
                                        (list name)))))
                (when (and signature (not (string-empty-p signature)))
                  (list (etaf-node 'text
                                   (list :font-family (etaf-manual-reader--mono-family)
                                         :color (etaf-manual-reader--color env :muted))
                                   (list signature))))
                (when blocks
                  (list (etaf-manual-reader--spacer)))
                (etaf-ui-markdown-view-blocks
                 blocks
                 (etaf-manual-reader--doc-env env))))))

;;;; Article flow

(defun etaf-manual-reader--ordinary-view (block env examples state)
  "Return the View for an ordinary BLOCK, or an example viewer.
EXAMPLES and STATE track the chapter's runnable examples in document order."
  (if (and examples
           (eq (plist-get block :type) 'code-block)
           (equal (plist-get block :lang) "elisp")
           (< (car state) (length examples)))
      (let ((example (nth (car state) examples)))
        (setcar state (1+ (car state)))
        (etaf-manual-reader--example-viewer example env))
    (etaf-ui-markdown-view-block block (etaf-manual-reader--doc-env env))))

(defun etaf-manual-reader--render-blocks (blocks env &optional examples state)
  "Render BLOCKS in ENV with definition cards and example viewers.
EXAMPLES is the chapter's runnable example list; STATE is a mutable list
whose car counts consumed examples, so a chapter renders one continuous flow
across its sections."
  (let ((examples (or examples nil))
        (state (or state (list 0)))
        nodes)
    (while blocks
      (let ((block (pop blocks)))
        (if (and (eq (plist-get block :type) 'heading)
                 (= (plist-get block :level) 4)
                 (etaf-manual-reader--definition-parts block))
            (let (body)
              (while (and blocks
                          (not (eq (plist-get (car blocks) :type) 'heading)))
                (push (pop blocks) body))
              (push (etaf-manual-reader--definition-card
                     block (nreverse body) env)
                    nodes))
          (let ((view (etaf-manual-reader--ordinary-view
                       block env examples state)))
            (when view (push view nodes))))))
    (nreverse nodes)))

(defun etaf-manual-reader--section-view (blocks env examples state)
  "Return the section View for BLOCKS.
The View carries the scroll anchor of its first heading so navigation can
bring it to the top of the article scroller."
  (let* ((heading (car blocks))
         (anchor (plist-get heading :id))
         (ref (and anchor (intern (format "etaf-manual-node-%s" anchor)))))
    (etaf-node 'column
               (append (list :width 'stretch :item-gap '(lh 1))
                       (when ref (list :ref ref)))
               (etaf-manual-reader--render-blocks blocks env examples state))))

(defun etaf-manual-reader--chapter-head-view (blocks env number)
  "Render the chapter title and lead BLOCKS in ENV.
NUMBER is the chapter number shown before the title.  The lead blocks
follow as separate Views so the article's one-line rhythm spaces them."
  (let ((nodes nil) (title nil))
    (dolist (block blocks)
      (if (and (eq (plist-get block :type) 'heading)
               (= (plist-get block :level) 1))
          (setq title (etaf-manual-reader--heading-text block))
        (push block nodes)))
    (append
     (when title
       (list (etaf-manual-reader--chapter-heading env number title)))
     (delq nil (mapcar (lambda (block)
                         (etaf-ui-markdown-view-block
                          block (etaf-manual-reader--doc-env env)))
                       (nreverse nodes))))))

(cl-defun etaf-manual-reader--article (&key session env)
  "Return the article column View of SESSION's current chapter in ENV."
  (let* ((document (etaf-manual-reader-document session))
         (blocks (plist-get document :children))
         (examples (etaf-manual-reader--chapter-examples session))
         (state (list 0))
         (split (etaf-manual-reader--sections blocks))
         (head (car split))
         (sections (cdr split))
         (env (append env (list :markdown-features (plist-get document :features))))
         (part (etaf-manual-reader--part session))
         (number (plist-get (etaf-manual-reader--chapter session) :number))
         (lead (etaf-manual-reader--chapter-head-view head env number))
         (body nil))
    (dolist (section sections)
      (push (etaf-manual-reader--section-view
             (cdr section) env examples state)
            body))
    (when (null sections)
      (dolist (view (etaf-manual-reader--render-blocks
                     blocks env examples state))
        (push view body)))
    (etaf-node 'column
               (list :width 'stretch
                     :max-width (list 'ch (etaf-manual-reader--measure env))
                     :padding '((lh 1) (ch 3))
                     :item-gap '(lh 1)
                     :color (etaf-manual-reader--color env :ink))
               (append
                (when part
                  (list (etaf-manual-reader--label
                         env (format "%s · %s"
                                     (or (plist-get part :number) "")
                                     (or (plist-get part :title) "")))))
                lead
                (list (etaf-node 'column
                                 (list :width 'stretch :item-gap '(lh 2))
                                 (nreverse body)))))))

(provide 'etaf-manual-reader-article)
;;; etaf-manual-reader-article.el ends here
