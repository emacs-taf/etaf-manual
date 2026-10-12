;;; etaf-manual-reader-views.el --- Shell and navigation of the manual reader -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; The application shell of the manual reader: header with the brand,
;; breadcrumb, language switch and theme switch; the navigation column with
;; the three-level outline; the scrolling article column; and the key-hint
;; footer.  The shell composes the article layer of
;; `etaf-manual-reader-article' and the design system of
;; `etaf-manual-reader-style'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-manual-reader-style)
(require 'etaf-manual-reader-model)
(require 'etaf-manual-reader-article)

(defconst etaf-manual-reader--article-ref 'etaf-manual-article-column
  "Host reference of the scrolling article column.")

(defconst etaf-manual-reader--overview-ref 'etaf-manual-overview-column
  "Host reference of the narrow-screen overview column.")

(defconst etaf-manual-reader--nav-current-ref 'etaf-manual-nav-current
  "Host reference of the navigation row of the reading position.")

;;;; Environment and scrolling

(defun etaf-manual-reader--env (session &optional viewport rows)
  "Return the rendering environment of SESSION.
VIEWPORT, when known, is the frame width in character cells and ROWS the
frame height in lines."
  (let* ((theme (etaf-manual-reader--read session :theme))
         (palette (etaf-manual-reader-palette theme)))
    (list :palette palette
          :theme theme
          :viewport viewport
          :rows rows
          :reader session
          :open-link (lambda (url) (etaf-manual-reader-follow session url))
          :footnote-jump (lambda (label)
                           (etaf-manual-reader-message
                            session (format "脚注 %s" label))))))

(defun etaf-manual-reader--runtime (session)
  "Return SESSION's mounted runtime, or nil."
  (when-let* ((buffer (plist-get session :buffer)))
    (and (buffer-live-p buffer)
         (etaf-runtime-for-buffer buffer))))

(defun etaf-manual-reader--scroll-to-node (session)
  "Scroll SESSION's article so its current section starts at the top.
The navigation column follows by the least distance that shows the row of
the reading position."
  (when-let* ((runtime (etaf-manual-reader--runtime session)))
    (ignore-errors
      (etaf-scroll-into-view runtime etaf-manual-reader--nav-current-ref))
    (let ((node (etaf-manual-reader--read session :node)))
      (if node
          (let* ((anchor (plist-get (etaf-manual-reader--node-at session node)
                                    :anchor))
                 (ref (and anchor
                           (intern (format "etaf-manual-node-%s" anchor)))))
            (when ref
              (ignore-errors (etaf-scroll-into-view runtime ref 'start))))
        (ignore-errors (etaf-scroll-to runtime etaf-manual-reader--article-ref 0))))))

(defun etaf-manual-reader--after-navigation (session)
  "Scroll SESSION after the pending render settles."
  (run-at-time 0 nil #'etaf-manual-reader--scroll-to-node session))

(defun etaf-manual-reader--scroll-to-definition (session name)
  "Scroll SESSION's article to the definition card of NAME."
  (when-let* ((runtime (etaf-manual-reader--runtime session)))
    (let ((ref (intern (format "etaf-manual-definition-%s" name))))
      (ignore-errors (etaf-scroll-into-view runtime ref 'start)))))

(defun etaf-manual-reader-scroll-to-definition (session name)
  "Scroll SESSION's article to the definition card of NAME, after rendering."
  (run-at-time 0 nil #'etaf-manual-reader--scroll-to-definition session name))

;;;; Header

(defun etaf-manual-reader--language-options (&optional compact)
  "Return the language switch options, shortened when COMPACT."
  (if compact
      '(("zh-CN" . "中") ("en" . "EN"))
    '(("zh-CN" . "中文") ("en" . "EN"))))

(defun etaf-manual-reader--switch-language (session language)
  "Switch SESSION to LANGUAGE and report it."
  (condition-case error
      (progn
        (etaf-manual-reader-set-language session language)
        (etaf-manual-reader-message
         session (format "已切换到%s" (if (equal language "zh-CN") "中文" "英文"))))
    (error (etaf-manual-reader-message
            session (error-message-string error)))))

(defun etaf-manual-reader--theme-options ()
  "Return the theme switch options."
  '((light . "浅色") (dark . "深色")))

(defun etaf-manual-reader--breadcrumb (session env compact)
  "Return SESSION's reading trail in ENV: part, chapter and section.
COMPACT keeps only the chapter and section."
  (let* ((part (etaf-manual-reader--part session))
         (chapter (etaf-manual-reader--read session :chapter))
         (node (etaf-manual-reader--node-at
                session (etaf-manual-reader--read session :node)))
         (crumbs (delq nil
                       (list (and (not compact) part
                                  (cons (plist-get part :title) :muted))
                             (cons (etaf-manual-reader--chapter-title session chapter)
                                   (if node :muted :ink))
                             (and node (cons (plist-get node :title) :ink)))))
         (nodes nil))
    (dolist (crumb crumbs)
      (when nodes
        (push (etaf-manual-reader--icon env 'chevron-right :faint) nodes))
      (push (etaf-node 'text
                       (list :color (etaf-manual-reader--color env (cdr crumb)))
                       (list (car crumb)))
            nodes))
    (etaf-node 'row
               (list :item-gap '(ch 1) :cross-align 'center
                     :min-width '(px 0) :overflow 'hidden)
               (nreverse nodes))))

(defun etaf-manual-reader--header-view (session env)
  "Return the header View of SESSION in ENV."
  (let* ((language (etaf-manual-reader--read session :language))
         (theme (or (etaf-manual-reader--read session :theme)
                    (etaf-manual-reader-auto-theme)))
         (wide (etaf-manual-reader--wide-p env))
         (compact (etaf-manual-reader--compact-p env))
         (chrome (etaf-manual-reader--chrome
                  env
                  (list
                   (etaf-manual-reader--brand env (if compact "手册" "ETAF 手册"))
                   (etaf-manual-reader--breadcrumb session env compact)
                   (etaf-node 'box
                              (list :flex-grow 1 :flex-basis '(px 0)
                                    :min-width '(px 0))
                              nil)
                   (when (not wide)
                     (etaf-node 'etaf-button
                                (list :label (if (etaf-manual-reader--read session :toc)
                                                 "返回正文"
                                               "目录")
                                      :variant 'secondary
                                      :on-press (lambda ()
                                                  (etaf-set-value
                                                   (etaf-manual-reader--ref session :toc)
                                                   (not (etaf-manual-reader--read session :toc)))))
                                nil))
                   (etaf-node 'etaf-segmented
                              (list :value language
                                    :options (etaf-manual-reader--language-options compact)
                                    :on-change (lambda (code)
                                                 (etaf-manual-reader--switch-language session code)))
                              nil)
                   (unless compact
                     (etaf-node 'etaf-segmented
                                (list :value theme
                                      :options (etaf-manual-reader--theme-options)
                                      :on-change (lambda (value)
                                                   (etaf-manual-reader-set-theme
                                                    session value)))
                                nil))))))
    (etaf-node 'box
               (list :ref 'etaf-manual-header
                     :width 'stretch
                     :box-sizing 'border-box)
               (list chrome))))

;;;; Navigation column

(defun etaf-manual-reader--sidebar-row (session env row)
  "Return one clickable navigation ROW of SESSION in ENV.
ROW is a plist with `:number', `:label', `:chapter', `:node', `:level',
`:current' and `:current-node'.  The number sits in a fixed gutter and the
label wraps beside it, so a long title keeps its hanging indent; a
level-3 section widens the gutter and marks it with a dot."
  (let* ((label (plist-get row :label))
         (chapter (plist-get row :chapter))
         (node (plist-get row :node))
         (level (plist-get row :level))
         (current (plist-get row :current))
         (current-node (plist-get row :current-node))
         (chapter-row (eql level 0))
         (selected (if chapter-row
                       (and current (null (etaf-manual-reader--read session :node)))
                     current-node))
         (color (cond (selected (etaf-manual-reader--color env :accent))
                      ((and chapter-row current) (etaf-manual-reader--color env :heading))
                      (chapter-row (etaf-manual-reader--color env :ink))
                      (t (etaf-manual-reader--color env :muted)))))
    (etaf-node 'row
               (append
                (when selected (list :ref etaf-manual-reader--nav-current-ref))
                (list :width 'stretch
                     :box-sizing 'border-box
                     :padding '((lh 0) (ch 1))
                     :item-gap '(ch 1)
                     :background-color (cond (selected (etaf-manual-reader--color env :sidebar-current))
                                             ((and chapter-row current)
                                              (etaf-manual-reader--color env :panel))
                                             (t nil))
                     :border-left (list '(px 3) 'solid
                                        (if (and chapter-row current)
                                            (etaf-manual-reader--color env :accent)
                                          (etaf-manual-reader--color env :sidebar)))
                     :color color
                     :font-weight (if (or selected (and chapter-row current)) 'bold nil)
                     :pointer 'hand
                     :role 'button
                     :tab-index 0
                     :help-echo label
                     :on-press (lambda ()
                                 (etaf-manual-reader-goto session chapter node)
                                 (etaf-manual-reader--after-navigation session))))
               (list (etaf-node 'box
                                (list :width (if (eql level 3) '(ch 5) '(ch 3))
                                      :flex-shrink 0
                                      :text-align 'right
                                      :color (if (or selected (and chapter-row current))
                                                 (etaf-manual-reader--color env :accent)
                                               (etaf-manual-reader--color env :faint)))
                                (list (etaf-node 'text nil
                                                 (list (if (eql level 3)
                                                           "·"
                                                         (format "%s" (or (plist-get row :number) "")))))))
                     (etaf-node 'box
                                (list :flex-grow 1 :flex-basis '(px 0)
                                      :min-width '(px 0) :wrap-mode 'word)
                                (list (etaf-node 'text nil (list label))))))))

(defun etaf-manual-reader--sidebar-rows (session env)
  "Return the navigation rows of SESSION in ENV."
  (let ((rows nil) (first t))
    (dolist (part (etaf-manual-reader-toc session))
      (unless first
        (push (etaf-manual-reader--spacer) rows))
      (setq first nil)
      (push (etaf-node 'box
                       (list :width 'stretch
                             :box-sizing 'border-box
                             :padding '((lh 0) (ch 2))
                             :color (etaf-manual-reader--color env :faint))
                       (list (etaf-node 'text
                                        (list :font-weight 'bold)
                                        (list (format "%s  %s"
                                                      (plist-get part :number)
                                                      (plist-get part :title))))))
            rows)
      (dolist (chapter (plist-get part :chapters))
        (push (etaf-manual-reader--sidebar-row
               session env
               (list :number (plist-get chapter :number)
                     :label (plist-get chapter :title)
                     :chapter (plist-get chapter :id)
                     :node nil
                     :level 0
                     :current (plist-get chapter :current)))
              rows)
        (when (plist-get chapter :current)
          (dolist (node (plist-get chapter :nodes))
            (push (etaf-manual-reader--sidebar-row
                   session env
                   (list :label (plist-get node :title)
                         :chapter (plist-get chapter :id)
                         :node (plist-get node :index)
                         :level (plist-get node :level)
                         :current (plist-get chapter :current)
                         :current-node (plist-get node :current)))
                  rows)))))
    (nreverse rows)))

(defun etaf-manual-reader--sidebar (session env)
  "Return the navigation column View of SESSION in ENV."
  (etaf-node 'column
             (list :width (list 'ch etaf-manual-reader--sidebar-width)
                   :height 'stretch
                   :flex-shrink 0
                   :overflow 'scroll
                   :box-sizing 'border-box
                   :background-color (etaf-manual-reader--color env :sidebar)
                   :padding '((lh 1) (ch 1))
                   :item-gap '(lh 0)
                   :ref 'etaf-manual-nav-column)
             (etaf-manual-reader--sidebar-rows session env)))

(defun etaf-manual-reader--overview (session env)
  "Return the narrow-screen overview panel of SESSION in ENV."
  (etaf-node 'column
             (list :width 'stretch
                   :height 'stretch
                   :overflow 'scroll
                   :box-sizing 'border-box
                   :background-color (etaf-manual-reader--color env :bg)
                   :padding '((lh 1) (ch 2))
                   :item-gap '(lh 0)
                   :ref etaf-manual-reader--overview-ref)
             (etaf-manual-reader--sidebar-rows session env)))

;;;; Article column

(defun etaf-manual-reader--article-column (session env)
  "Return the scrolling article column View of SESSION in ENV."
  (etaf-node 'column
             (list :ref etaf-manual-reader--article-ref
                   :width 'stretch
                   :height 'stretch
                   :flex-grow 1
                   :flex-basis '(px 0)
                   :min-width '(px 0)
                   :overflow 'scroll
                   :cross-align 'center
                   :background-color (etaf-manual-reader--color env :bg))
             (list (etaf-manual-reader--article :session session :env env))))

;;;; Footer

(defun etaf-manual-reader--position-label (session)
  "Return the reading position label of SESSION."
  (let* ((state (etaf-manual-reader-state session))
         (node (plist-get state :node))
         (nodes (plist-get state :nodes)))
    (format "第 %s/%s 章%s" (1+ (plist-get state :position)) (plist-get state :chapters)
            (if node (format " · 第 %s/%s 节" (1+ node) (length nodes)) ""))))

(defun etaf-manual-reader--footer-hints (env)
  "Return the key hints the footer shows in ENV."
  (if (etaf-manual-reader--compact-p env)
      '(("n/p" . "节") ("i" . "索引") ("?" . "按键"))
    '(("n/p" . "上下节") ("[ ]" . "上下章") ("u" . "上级")
      ("i" . "索引") ("?" . "全部按键"))))

(defun etaf-manual-reader--footer (session env)
  "Return the footer View of SESSION in ENV: the reading position or the
latest message on the left, the most useful keys on the right."
  (let ((message (etaf-manual-reader--read session :message)))
    (etaf-node 'box
               (list :ref 'etaf-manual-footer
                     :width 'stretch :box-sizing 'border-box
                     :background-color (etaf-manual-reader--color env :panel))
               (list
                (etaf-manual-reader--chrome
                 env
                 (list
                  (if (and message (not (string-empty-p message)))
                      (etaf-manual-reader--state-line env message :accent)
                    (etaf-manual-reader--state-line
                     env (etaf-manual-reader--position-label session)))
                  (etaf-node 'box
                             (list :flex-grow 1 :flex-basis '(px 0) :min-width '(px 0))
                             nil)
                  (etaf-manual-reader--key-hints
                   env (etaf-manual-reader--footer-hints env))))))))

;;;; Shell

(defun etaf-manual-reader--shell (session env &optional keys)
  "Return the complete application View of SESSION in ENV.
KEYS is the page Host's `:keys' table, so `?' lists the reader's keys."
  (let* ((wide (etaf-manual-reader--wide-p env))
         (toc (and (not wide) (etaf-manual-reader--read session :toc)))
         (article (etaf-manual-reader--article-column session env))
         (body (if toc
                   (etaf-node 'column
                              (list :width 'stretch :height 'stretch
                                    :flex-grow 1 :flex-basis '(px 0)
                                    :min-width '(px 0))
                              (list (etaf-manual-reader--overview session env)))
                 (etaf-node 'flex
                            (list :width 'stretch :height 'stretch
                                  :flex-direction 'row
                                  :align-items 'stretch
                                  :min-height '(lh 0))
                            (append
                             (when wide
                               (list (etaf-manual-reader--sidebar session env)))
                             (list article))))))
    (etaf-manual-reader--page
     env
     (list (etaf-manual-reader--header-view session env)
           (etaf-node 'flex
                      (list :ref 'etaf-manual-body
                            :flex-direction 'row
                            :align-items 'stretch
                            :gap '((lh 0) (ch 0))
                            :width 'stretch
                            :flex-grow 1 :flex-basis '(px 0)
                            :min-height '(lh 0)
                            :overflow 'hidden)
                      (list body))
           (etaf-manual-reader--footer session env))
     ;; Reserve one row: a graphical frame may reserve its last text row for
     ;; window chrome while the runtime still counts it as available.  A
     ;; headless mount reports no height, so it renders the whole article
     ;; instead of a window-sized slice, which keeps batch tests complete.
     (list 'lh (if (plist-get env :rows)
                   (max 12 (1- (plist-get env :rows)))
                 500))
     keys)))

(provide 'etaf-manual-reader-views)
;;; etaf-manual-reader-views.el ends here
