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
  "Scroll SESSION's article so its current section starts at the top."
  (when-let* ((runtime (etaf-manual-reader--runtime session)))
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

(defun etaf-manual-reader--header-view (session env)
  "Return the header View of SESSION in ENV."
  (let* ((language (etaf-manual-reader--read session :language))
         (theme (etaf-manual-reader--read session :theme))
         (wide (etaf-manual-reader--wide-p env))
         (compact (etaf-manual-reader--compact-p env))
         (breadcrumb (etaf-manual-reader--position-title session))
         (chrome (etaf-manual-reader--chrome
                  env
                  (list
                   (etaf-manual-reader--brand env (if compact "手册" "ETAF 手册"))
                   (etaf-node 'text
                              (list :color (etaf-manual-reader--color env :muted))
                              (list "›"))
                   (etaf-node 'text
                              (list :color (etaf-manual-reader--color env :ink))
                              (list breadcrumb))
                   (etaf-node 'box
                              (list :flex-grow 1 :flex-basis '(px 0)
                                    :min-width '(px 0))
                              nil)
                   (when (not wide)
                     (etaf-node 'etaf-button
                                (list :label (if (etaf-manual-reader--read session :toc)
                                                 "▤ 收起"
                                               "▤ 目录")
                                      :variant 'ghost
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
                     (etaf-node 'etaf-switch
                                (list :checked (eq theme 'dark)
                                      :label "深色"
                                      :on-change (lambda (on)
                                                   (etaf-manual-reader-set-theme
                                                    session (if on 'dark 'light))))
                                nil))))))
    ;; A 1px border would push the page one pixel past the viewport and
    ;; clip the last chrome row, so chrome bars separate by surface color.
    (etaf-node 'box
               (list :ref 'etaf-manual-header
                     :width 'stretch
                     :box-sizing 'border-box)
               (list chrome))))

;;;; Navigation column

(defun etaf-manual-reader--sidebar-row (session env row)
  "Return one clickable navigation ROW of SESSION in ENV.
ROW is a plist with `:label', `:chapter', `:node', `:level', `:current' and
`:current-node'."
  (let ((label (plist-get row :label))
        (chapter (plist-get row :chapter))
        (node (plist-get row :node))
        (level (plist-get row :level))
        (current (plist-get row :current))
        (current-node (plist-get row :current-node)))
    (etaf-node 'box
               (list :width 'stretch
                     :box-sizing 'border-box
                     :padding (list '(lh 0)
                                    (list 'ch (pcase level
                                                (0 1)
                                                (3 4)
                                                (_ 2))))
                     :background-color (if current-node
                                           (etaf-manual-reader--color env :sidebar-current)
                                         nil)
                     :color (cond (current-node (etaf-manual-reader--color env :accent))
                                  (current (etaf-manual-reader--color env :accent))
                                  (t (etaf-manual-reader--color env :ink)))
                     :font-weight (if (or current current-node) 'bold nil)
                     :pointer 'hand
                     :role 'button
                     :tab-index 0
                     :help-echo label
                     :on-press (lambda ()
                                 (etaf-manual-reader-goto session chapter node)
                                 (etaf-manual-reader--after-navigation session)))
               (list (etaf-node 'text nil (list label))))))

(defun etaf-manual-reader--sidebar-rows (session env)
  "Return the navigation rows of SESSION in ENV."
  (let ((rows nil))
    (dolist (part (etaf-manual-reader-toc session))
      (push (etaf-node 'box
                       (list :width 'stretch
                             :box-sizing 'border-box
                             :padding '((lh 0) (ch 1))
                             :color (etaf-manual-reader--color env :muted))
                       (list (etaf-node 'text
                                        (list :font-weight 'bold)
                                        (list (format "%s · %s"
                                                      (plist-get part :number)
                                                      (plist-get part :title))))))
            rows)
      (dolist (chapter (plist-get part :chapters))
        (push (etaf-manual-reader--sidebar-row
               session env
               (list :label (format "%s  %s"
                                    (or (plist-get chapter :number) "·")
                                    (plist-get chapter :title))
                     :chapter (plist-get chapter :id)
                     :node nil
                     :level 0
                     :current (plist-get chapter :current)))
              rows)
        (when (plist-get chapter :current)
          (dolist (node (plist-get chapter :nodes))
            (push (etaf-manual-reader--sidebar-row
                   session env
                   (list :label (format "· %s" (plist-get node :title))
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
                   :border-right (etaf-manual-reader--border env)
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
    (format "%s/%s 章%s" (1+ (plist-get state :position)) (plist-get state :chapters)
            (if node (format " · %s/%s 节" (1+ node) (length nodes)) ""))))

(defun etaf-manual-reader--footer (session env)
  "Return the footer View of SESSION in ENV."
  (etaf-node 'box
             (list :ref 'etaf-manual-footer
                   :width 'stretch :box-sizing 'border-box
                   :background-color (etaf-manual-reader--color env :panel))
             (list
              (etaf-manual-reader--chrome
               env
               (list
                (etaf-manual-reader--kbd-hint env '("n" "p") "节")
                (etaf-manual-reader--kbd-hint env '("u") "上级")
                (unless (etaf-manual-reader--compact-p env)
                  (etaf-manual-reader--kbd-hint env '("l" "r") "历史"))
                (etaf-manual-reader--kbd-hint env '("i") "索引")
                (unless (etaf-manual-reader--compact-p env)
                  (etaf-manual-reader--kbd-hint env '("t") "主题"))
                (etaf-manual-reader--kbd-hint env '("q") "退出")
                (etaf-node 'box
                           (list :flex-grow 1 :flex-basis '(px 0) :min-width '(px 0))
                           nil)
                (let ((message (etaf-manual-reader--read session :message)))
                  (if (and message (not (string-empty-p message)))
                      (etaf-manual-reader--state-line env message)
                    (etaf-manual-reader--state-line
                     env (etaf-manual-reader--position-label session)))))))))

;;;; Shell

(defun etaf-manual-reader--shell (session env)
  "Return the complete application View of SESSION in ENV."
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
                 500)))))

(provide 'etaf-manual-reader-views)
;;; etaf-manual-reader-views.el ends here
