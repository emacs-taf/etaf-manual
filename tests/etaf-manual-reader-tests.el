;;; etaf-manual-reader-tests.el --- Public API acceptance -*- lexical-binding: t; -*-

;;; Commentary:
;; Test the supported manual reader contract: session state, navigation,
;; language and theme switches, the navigation outline, the mounted
;; rendering and the in-place runnable examples.  Internal helpers are
;; outside this contract.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'etaf)
(require 'etaf-manual)

(defconst etaf-manual-reader-test--buffer " *etaf-manual-reader-test*"
  "Buffer name used by the mounted reader tests.")

(defmacro etaf-manual-reader-test--with-reader (session &rest body)
  "Mount SESSION in a test buffer, evaluate BODY, then release it."
  (declare (indent 1))
  `(let ((buffer (get-buffer-create etaf-manual-reader-test--buffer)))
     (unwind-protect
         (progn
           (setq buffer (etaf-mount buffer (etaf-manual-reader-view ,session)))
           (with-current-buffer buffer ,@body))
       (when-let* ((runtime (etaf-runtime-for-buffer etaf-manual-reader-test--buffer)))
         (etaf-unmount runtime))
       (when-let* ((live (get-buffer etaf-manual-reader-test--buffer)))
         (kill-buffer live)))))

(defun etaf-manual-reader-test--text ()
  "Return the plain text of the mounted reader buffer."
  (substring-no-properties (buffer-string)))

(ert-deftest etaf-manual-reader-create-reports-state ()
  "A new session reads the first chapter and exposes its outline."
  (let* ((session (etaf-manual-reader-create :language "zh-CN"))
         (state (etaf-manual-reader-state session)))
    (should (equal "zh-CN" (plist-get state :language)))
    (should (eq 'introduction (plist-get state :chapter)))
    (should (equal "引言" (plist-get state :chapter-title)))
    (should (zerop (plist-get state :position)))
    (should (> (plist-get state :chapters) 90))
    (should (member "范围" (plist-get state :nodes)))
    (should-not (plist-get state :can-back))))

(ert-deftest etaf-manual-reader-navigation-walks-sections-and-chapters ()
  "Next and previous move through sections and roll into other chapters."
  (let ((session (etaf-manual-reader-create :language "zh-CN")))
    (etaf-manual-reader-next session)
    (should (eql 0 (plist-get (etaf-manual-reader-state session) :node)))
    (etaf-manual-reader-next session)
    (should (eql 1 (plist-get (etaf-manual-reader-state session) :node)))
    (etaf-manual-reader-previous session)
    (should (eql 0 (plist-get (etaf-manual-reader-state session) :node)))
    ;; The first chapter has nothing before it.
    (should-error (etaf-manual-reader-previous session) :type 'user-error)
    ;; Walk to the end of the chapter, then roll into the next one.
    (let ((count (length (plist-get (etaf-manual-reader-state session) :nodes))))
      (dotimes (_ (1- count)) (etaf-manual-reader-next session))
      (let ((state (etaf-manual-reader-state session)))
        (should (eq 'introduction (plist-get state :chapter)))
        (should (eql (1- count) (plist-get state :node))))
      (etaf-manual-reader-next session)
      (let ((state (etaf-manual-reader-state session)))
        (should (eq 'ecosystem-and-layers (plist-get state :chapter)))
        (should (eql 0 (plist-get state :node))))
      ;; From the top of the second chapter, previous returns to the last
      ;; section of the first one.
      (etaf-manual-reader-previous session)
      (let ((state (etaf-manual-reader-state session)))
        (should (eq 'introduction (plist-get state :chapter)))
        (should (eql (1- count) (plist-get state :node)))))))

(ert-deftest etaf-manual-reader-up-follows-levels ()
  "Up moves a level-3 section to its level-2 parent and then to the top."
  (let ((session (etaf-manual-reader-create :language "zh-CN")))
    ;; "术语" is a level-3 section of the introduction.
    (let ((nodes (plist-get (etaf-manual-reader-state session) :nodes)))
      (etaf-manual-reader-goto
       session 'introduction
       (cl-position "术语" nodes :test #'equal)))
    (should (equal "术语" (plist-get (etaf-manual-reader-state session) :node-title)))
    (etaf-manual-reader-up session)
    (should (equal "记法约定" (plist-get (etaf-manual-reader-state session) :node-title)))
    (etaf-manual-reader-up session)
    (should-not (plist-get (etaf-manual-reader-state session) :node))))

(ert-deftest etaf-manual-reader-history-walks-both-ways ()
  "Back and forward move through the reading history."
  (let ((session (etaf-manual-reader-create :language "zh-CN")))
    (etaf-manual-reader-goto session 'introduction 0)
    (etaf-manual-reader-goto session 'ecosystem-and-layers 0)
    (should (eq 'ecosystem-and-layers (plist-get (etaf-manual-reader-state session) :chapter)))
    (etaf-manual-reader-back session)
    (should (eq 'introduction (plist-get (etaf-manual-reader-state session) :chapter)))
    (should (eql 0 (plist-get (etaf-manual-reader-state session) :node)))
    (etaf-manual-reader-forward session)
    (should (eq 'ecosystem-and-layers (plist-get (etaf-manual-reader-state session) :chapter)))
    (should (plist-get (etaf-manual-reader-state session) :can-back))))

(ert-deftest etaf-manual-reader-language-switch-keeps-position ()
  "Switching language keeps the chapter and reads the other translation."
  (let ((session (etaf-manual-reader-create :language "zh-CN")))
    (etaf-manual-reader-goto session 'components 0)
    (etaf-manual-reader-set-language session "en")
    (let ((state (etaf-manual-reader-state session)))
      (should (equal "en" (plist-get state :language)))
      (should (eq 'components (plist-get state :chapter)))
      (should (equal "Components" (plist-get state :chapter-title)))
      (should (eql 0 (plist-get state :node))))
    (etaf-manual-reader-set-language session "zh-CN")
    (should (equal "Component" (plist-get (etaf-manual-reader-state session) :chapter-title)))))

(ert-deftest etaf-manual-reader-toggle-theme-switches-palette ()
  "Toggling the theme flips between the dark and light palettes."
  (let ((session (etaf-manual-reader-create :language "zh-CN" :theme 'dark)))
    (should (eq (etaf-manual-reader-toggle-theme session) 'light))
    (should (eq 'light (plist-get (etaf-manual-reader-state session) :theme)))
    (should (eq (etaf-manual-reader-toggle-theme session) 'dark))))

(ert-deftest etaf-manual-reader-toc-marks-the-current-chapter ()
  "The outline names the parts, chapters and current sections."
  (let* ((session (etaf-manual-reader-create :language "zh-CN" :chapter 'components))
         (toc (etaf-manual-reader-toc session))
         (current (cl-find-if (lambda (chapter) (plist-get chapter :current))
                              (cl-loop for part in toc
                                       append (plist-get part :chapters)))))
    (should (> (length toc) 10))
    (should current)
    (should (eq 'components (plist-get current :id)))
    (should (listp (plist-get current :nodes)))
    (should (plist-get (car (plist-get current :nodes)) :anchor))))

(ert-deftest etaf-manual-reader-view-renders-chapter-and-example ()
  "The mounted reader shows the article, chrome and a runnable example."
  (let ((session (etaf-manual-reader-create :language "zh-CN" :chapter 'introduction)))
    (etaf-manual-reader-test--with-reader session
      (let ((text (etaf-manual-reader-test--text)))
        (should (string-match-p "手册" text))
        (should (string-match-p "引言" text))
        (should (string-match-p "范围" text))
        (should (string-match-p "可运行示例" text))
        (should (string-match-p "尚未运行" text))
        (should (string-match-p "索引" text))))))

(ert-deftest etaf-manual-reader-example-runs-and-stops-in-place ()
  "The run control renders the real View; stop clears it again."
  (let* ((session (etaf-manual-reader-create :language "zh-CN" :chapter 'introduction))
         (run-ref 'etaf-manual-example-run-introduction-1)
         (stop-ref 'etaf-manual-example-stop-introduction-1))
    (etaf-manual-reader-test--with-reader session
      (let ((runtime (etaf-runtime-for-buffer etaf-manual-reader-test--buffer)))
        (should (string-match-p "尚未运行" (etaf-manual-reader-test--text)))
        (etaf-dispatch-event runtime run-ref 'press)
        (etaf-runtime-flush runtime)
        (should-not (string-match-p "尚未运行" (etaf-manual-reader-test--text)))
        (should (string-match-p "Hello" (etaf-manual-reader-test--text)))
        (etaf-dispatch-event runtime stop-ref 'press)
        (etaf-runtime-flush runtime)
        (should (string-match-p "尚未运行" (etaf-manual-reader-test--text)))))))

(ert-deftest etaf-manual-reader-example-modes-switch ()
  "Source, preview and side-by-side modes switch per example."
  (let* ((session (etaf-manual-reader-create
                   :language "zh-CN" :chapter 'ui-buttons-and-choice-controls))
         (id "ui-buttons-and-choice-controls-1")
         (source-ref (intern (format "etaf-manual-example-source-%s" id)))
         (split-ref (intern (format "etaf-manual-example-split-%s" id))))
    (etaf-manual-reader-test--with-reader session
      (let ((runtime (etaf-runtime-for-buffer etaf-manual-reader-test--buffer)))
        ;; The default mode shows the preview surface only.
        (should (string-match-p "尚未运行" (etaf-manual-reader-test--text)))
        (etaf-dispatch-event runtime split-ref 'press)
        (etaf-runtime-flush runtime)
        (let ((text (etaf-manual-reader-test--text)))
          (should (string-match-p "源码" text))
          (should (string-match-p "预览" text))
          (should (string-match-p "etaf-view" text)))
        (etaf-dispatch-event runtime source-ref 'press)
        (etaf-runtime-flush runtime)
        (let ((text (etaf-manual-reader-test--text)))
          (should (string-match-p "etaf-view" text))
          (should-not (string-match-p "尚未运行" text)))))))

(ert-deftest etaf-manual-reader-shows-definition-cards ()
  "A chapter with definition entries renders their cards."
  (let ((session (etaf-manual-reader-create
                  :language "zh-CN" :chapter 'ui-buttons-and-choice-controls)))
    (etaf-manual-reader-test--with-reader session
      (let ((text (etaf-manual-reader-test--text)))
        (should (string-match-p "按钮与选择控件" text))
        (should (string-match-p "etaf-button" text))
        (should (string-match-p "Component" text))))))

(ert-deftest etaf-manual-reader-key-help-lists-reader-keys ()
  "The ETAF key help of the mounted reader lists the reader's own keys."
  (let ((session (etaf-manual-reader-create :language "zh-CN" :chapter 'introduction)))
    (etaf-manual-reader-test--with-reader session
      (let ((help (etaf-help)))
        (unwind-protect
            (with-current-buffer help
              (let ((text (buffer-string)))
                (should (string-match-p "下一节" text))
                (should (string-match-p "中英文切换" text))
                (should (string-match-p "手册阅读器" text))))
          (kill-buffer help))))))

(ert-deftest etaf-manual-reader-page-keys-drive-navigation ()
  "The page Host's `:keys' dispatch the reader keys in the runtime."
  (let ((buffer (etaf-manual-open 'introduction)))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (should-not (string-match-p "章 · " (substring-no-properties (buffer-string)))))
          (with-current-buffer buffer
            (execute-kbd-macro (kbd "n"))
            (etaf-runtime-flush (etaf-runtime-for-buffer buffer)))
          (with-current-buffer buffer
            (should (string-match-p "章 · " (substring-no-properties (buffer-string))))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (etaf-manual-close))))))

(ert-deftest etaf-manual-reader-examples-follow-run-blocks ()
  "Only `:run' blocks become viewers, including those inside definitions."
  (let ((session (etaf-manual-reader-create :language "zh-CN" :chapter 'introduction)))
    (etaf-manual-reader-test--with-reader session
      ;; The notation block before the first runnable example stays code.
      (should (string-match-p (regexp-quote "(etaf-value (etaf-ref 3))")
                              (etaf-manual-reader-test--text)))))
  (let ((session (etaf-manual-reader-create :language "zh-CN" :chapter 'components))
        (run-ref 'etaf-manual-example-run-components-1))
    (etaf-manual-reader-test--with-reader session
      (let ((runtime (etaf-runtime-for-buffer etaf-manual-reader-test--buffer))
            (idle (lambda ()
                    (let ((text (etaf-manual-reader-test--text)) (start 0) (count 0))
                      (while (string-match "尚未运行" text start)
                        (setq start (match-end 0) count (1+ count)))
                      count))))
        (let ((before (funcall idle)))
          (etaf-dispatch-event runtime run-ref 'press)
          (etaf-runtime-flush runtime)
          (should (= (funcall idle) (1- before))))))))

(ert-deftest etaf-manual-lookup-reaches-the-end-of-a-long-chapter ()
  "Looking up the last entry of a long chapter shows its card at once."
  (let ((etaf-manual-language "zh-CN")
        (buffer nil))
    (unwind-protect
        (progn
          (etaf-manual-lookup :outer 'style)
          (setq buffer (get-buffer "*ETAF 手册*"))
          (should buffer)
          (dotimes (_ 3) (accept-process-output nil 0.02))
          (with-current-buffer buffer
            (etaf-runtime-flush (etaf-runtime-for-buffer buffer))
            (let ((text (substring-no-properties (buffer-string))))
              (should (string-match-p "Style" text))
              (should (string-match-p ":outer" text)))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (etaf-manual-close))))))

(provide 'etaf-manual-reader-tests)
;;; etaf-manual-reader-tests.el ends here
