;;; export-site.el --- Export the book as Starlight content -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Dev tool for the site in `site/'.  It reads the parsed book with the same
;; reader the application uses, writes one Markdown page per chapter and
;; language, and emits the shared sidebar.  Chapter links are rewritten to
;; site routes; `elisp :run' and `elisp :figure' fences become plain code
;; fences with a short label, because a static site cannot mount a view.
;;
;;   emacs -Q --batch -L .. -L ../lisp -l scripts/export-site.el -- --site DIR

;;; Code:

(require 'cl-lib)
(require 'etaf-manual-book)

(defconst export-site--locales
  '(("en" . "en") ("zh-CN" . "zh-cn"))
  "Book language to site locale directory.")

(defconst export-site--ui
  '(("en" . (:runnable "Runnable example"
             :figure "Inline figure"
             :appendices "Appendices"
             :indices "Indices"))
    ("zh-CN" . (:runnable "可运行示例"
                :figure "插图"
                :appendices "附录"
                :indices "索引")))
  "Labels the exporter inserts around special content.")

(defun export-site--ui (language key)
  "Return LANGUAGE's label for KEY."
  (plist-get (cdr (assoc language export-site--ui)) key))

(defun export-site--routes (book)
  "Return BOOK's chapter ids and title anchors as an alist."
  (mapcar (lambda (chapter)
            (cons (symbol-name (plist-get chapter :id))
                  (etaf-manual--slug (or (plist-get chapter :title) ""))))
          (plist-get book :chapters)))

(defun export-site--rewrite-link (link locale routes)
  "Return LINK rewritten to a site route in LOCALE.
LINK is the inside of a Markdown link; ROUTES is the chapter alist.  An
anchor naming the target chapter's title is dropped: the title lives in
the page frontmatter and has no heading of its own."
  (if (string-match "\\`\\([a-z0-9][a-z0-9-]*\\)\\.md\\(#[^)]*\\)?\\'" link)
      (let* ((id (match-string 1 link))
             (anchor (or (match-string 2 link) ""))
             (title (cdr (assoc id routes))))
        (if title
            (format "/%s%s/%s" (if (equal locale "en") "" (concat locale "/"))
                    id (if (equal anchor (concat "#" title)) "" anchor))
          link))
    link))

(defun export-site--rewrite-links (line locale ids)
  "Rewrite chapter links in LINE for LOCALE; IDS are the chapter ids."
  (replace-regexp-in-string
   "\\](\\([a-z0-9][a-z0-9-]*\\.md\\(?:#[^)]*\\)?\\))"
   (lambda (match)
     (save-match-data
       (concat "](" (export-site--rewrite-link (substring match 2 -1) locale ids) ")")))
   line t t))

(defun export-site--fence-label (language info)
  "Return a label line for fence INFO, or nil for an ordinary fence."
  (cond
   ((string-match "\\`[ \t]*elisp[ \t]+:run\\_>" info)
    (format "*%s*" (export-site--ui language :runnable)))
   ((string-match "\\`[ \t]*elisp[ \t]+:figure\\_>\\(?:[ \t]+\\(.*\\)\\)?\\'" info)
    (let ((caption (match-string 1 info)))
      (format "*%s*%s" (export-site--ui language :figure)
              (if (and caption (not (string-empty-p caption)))
                  (format ": %s" caption)
                ""))))
   (t nil)))

(defun export-site--transform (text language locale ids)
  "Return TEXT as site Markdown for LANGUAGE and LOCALE.
The chapter title moves to frontmatter; special fences gain a label and
chapter links become site routes."
  (let ((lines (split-string text "\n"))
        (fence nil)
        (title-seen nil)
        out)
    (dolist (line lines)
      (cond
       ((and (null fence) (string-match "\\`[ ]\\{0,3\\}\\(```+\\|~~~+\\)\\(.*\\)\\'" line))
        (let* ((ticks (match-string 1 line))
               (info (match-string 2 line))
               (label (export-site--fence-label language info)))
          (when label (push label out))
          (push (if label (format "%selisp" ticks) line) out)
          (setq fence ticks)))
       ((and fence (string-match-p
                    (concat "\\`[ ]\\{0,3\\}" (regexp-quote fence) "[`~]*[ \t]*\\'") line))
        (push line out)
        (setq fence nil))
       (fence (push line out))
       ((and (not title-seen) (string-match-p "\\`# [^#]" line))
        (setq title-seen t))
       (t (push (export-site--rewrite-links line locale ids) out))))
    (let ((body (string-join (nreverse out) "\n")))
      (string-trim body))))

(defun export-site--chapter-title (chapter)
  "Return CHAPTER's title for frontmatter."
  (let ((title (or (plist-get chapter :title) "")))
    (replace-regexp-in-string "\"" "\\\\\"" title t t)))

(defun export-site--chapter-text (chapter)
  "Return CHAPTER's Markdown source."
  (if-let* ((content (plist-get chapter :content)))
      content
    (with-temp-buffer
      (insert-file-contents (plist-get chapter :file))
      (buffer-string))))

(defun export-site--write (file text)
  "Write TEXT to FILE, creating its directory."
  (make-directory (file-name-directory file) t)
  (write-region text nil file nil 'silent))

(defun export-site--page (chapter language locale ids)
  "Return the page text of CHAPTER in LANGUAGE and LOCALE; IDS are chapter ids."
  (format "---\ntitle: \"%s\"\n---\n\n%s\n"
          (export-site--chapter-title chapter)
          (export-site--transform (export-site--chapter-text chapter)
                                  language locale ids)))

;;; Landing page (English): feature cards on their own grid, then an
;; application gallery and a game gallery.  Every picture links to the full
;; WebP and is opened in the lightbox by scripts/lightbox.js.
(defconst export-site--landing-en
  "---
title: ETAF
description: Build complete text applications in Emacs with a web-style model.
template: splash
hero:
  tagline: >-
    Build complete text applications in Emacs with a web-style model:
    declarative components, cascade styling and incremental updates.
  image:
    html: <img src='/etaf-icon.svg' alt='' class='etaf-hero-icon' width='512' height='512' />
  actions:
    - text: Read the manual
      link: /introduction/
      icon: open-book
      variant: primary
    - text: GitHub
      link: https://github.com/emacs-taf
      icon: github
---

import { Icon } from '@astrojs/starlight/components';

<div class='etaf-features'>
  <div class='etaf-feature'>
    <h3><Icon name='puzzle' class='etaf-feature-icon' /> Declarative components</h3>
    <p>Compose reusable Components with named bindings and reactive state; the runtime owns re-rendering, identity and lifecycle.</p>
  </div>
  <div class='etaf-feature'>
    <h3><Icon name='seti:css' class='etaf-feature-icon' /> Cascade and computed styles</h3>
    <p>Style subjects through selectors, specificity and cascade, and read the computed result back instead of setting faces by hand.</p>
  </div>
  <div class='etaf-feature'>
    <h3><Icon name='laptop' class='etaf-feature-icon' /> Box, Flex and Grid layout</h3>
    <p>Lay text out with the box model, normal flow, flex and grid, measured down to the pixel.</p>
  </div>
  <div class='etaf-feature'>
    <h3><Icon name='rocket' class='etaf-feature-icon' /> Incremental updates</h3>
    <p>Retained rendering publishes only what changed, so an update costs what it changed instead of a full redraw.</p>
  </div>
</div>

## Built with ETAF

### Applications

<div class='etaf-shots'>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-ncm.webp'><img src='/shots/etaf-ncm.webp' alt='NetEase Cloud Music player in Emacs' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-ncm'>etaf-ncm</a>: liked songs, lyrics and the queue</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-weread.webp'><img src='/shots/etaf-weread.webp' alt='WeChat Reading client in Emacs' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-weread'>etaf-weread</a>: shelf, notebook and reading statistics</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-md-preview.webp'><img src='/shots/etaf-md-preview.webp' alt='Markdown reading view beside its source in Emacs' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-md-preview'>etaf-md-preview</a>: the source beside the rendered view</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-pi.webp'><img src='/shots/etaf-pi.webp' alt='Pi agent client in Emacs' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-pi'>etaf-pi</a>: a resumed session with tool output</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-telega.webp'><img src='/shots/etaf-telega.webp' alt='Telegram client in Emacs' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-telega'>etaf-telega</a>: chats, groups and channels</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-desktop.webp'><img src='/shots/etaf-desktop.webp' alt='ETAF Desktop window manager' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-desktop'>etaf-desktop</a>: windows, workspaces and a launcher</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-algo-lab.webp'><img src='/shots/etaf-algo-lab.webp' alt='Algorithm lab in Emacs' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-algo-lab'>etaf-algo-lab</a>: watch, steer and compare algorithms</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-video-player.webp'><img src='/shots/etaf-video-player.webp' alt='Video player in Emacs' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-video-player'>etaf-video-player</a>: video as sharp image frames with sound</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-ascii-video.webp'><img src='/shots/etaf-ascii-video.webp' alt='ASCII video in Emacs' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-ascii-video'>etaf-ascii-video</a>: video rendered as characters</figcaption>
  </figure>
</div>

### Games

<div class='etaf-shots'>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-solitaire.webp'><img src='/shots/etaf-solitaire.webp' alt='Verdant solitaire in Emacs' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-solitaire'>etaf-solitaire</a>: Verdant, K+ Klondike solitaire</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-xiangqi.webp'><img src='/shots/etaf-xiangqi.webp' alt='Chu He xiangqi' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-xiangqi'>etaf-xiangqi</a>: Chinese chess on a native vector board</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-tanks.webp'><img src='/shots/etaf-tanks.webp' alt='Iron Tide tank battle' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-tanks'>etaf-tanks</a>: Iron Tide, real-time tank battle</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-salvage.webp'><img src='/shots/etaf-salvage.webp' alt='Salvage Station game' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-salvage'>etaf-salvage</a>: Salvage Station, real-time exploration</figcaption>
  </figure>
</div>

This manual documents every public interface of ecss, ekp, ebox, etaf, etaf-ui
and etaf-db, with the mechanisms behind them. Read the
[Introduction](/introduction/) first, or jump to
[Style Properties](/style-properties/), the [UI Overview](/ui-overview/), the
[Glossary](/glossary/) and the [Symbol Index](/symbol-index/).
"
  "English splash page for the site in `site/'.")

(defconst export-site--landing-zh
  "---
title: ETAF
description: 用 Web 的方式在 Emacs 里构建完整的文本应用。
template: splash
hero:
  tagline: >-
    在 Emacs 里构建完整的文本应用：声明式组件、级联样式与增量更新。
  image:
    html: <img src='/etaf-icon.svg' alt='' class='etaf-hero-icon' width='512' height='512' />
  actions:
    - text: 阅读手册
      link: /zh-cn/introduction/
      icon: open-book
      variant: primary
    - text: GitHub
      link: https://github.com/emacs-taf
      icon: github
---

import { Icon } from '@astrojs/starlight/components';

<div class='etaf-features'>
  <div class='etaf-feature'>
    <h3><Icon name='puzzle' class='etaf-feature-icon' /> 声明式组件</h3>
    <p>用命名绑定与响应式状态组合可复用组件，重渲染、身份和生命周期由运行时负责。</p>
  </div>
  <div class='etaf-feature'>
    <h3><Icon name='seti:css' class='etaf-feature-icon' /> 级联与计算样式</h3>
    <p>用选择器、优先级和级联给主体写样式，再读回计算样式，而不是手工设置 face。</p>
  </div>
  <div class='etaf-feature'>
    <h3><Icon name='laptop' class='etaf-feature-icon' /> Box、Flex 与 Grid 布局</h3>
    <p>用盒模型、常规流、Flex 与 Grid 排布文本，精确到像素。</p>
  </div>
  <div class='etaf-feature'>
    <h3><Icon name='rocket' class='etaf-feature-icon' /> 增量更新</h3>
    <p>保留式渲染只发布变化的部分，更新的代价取决于改动的大小，而不是整屏重绘。</p>
  </div>
</div>

## 用 ETAF 构建的应用

### 应用

<div class='etaf-shots'>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-ncm.webp'><img src='/shots/etaf-ncm.webp' alt='Emacs 里的网易云音乐播放器' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-ncm'>etaf-ncm</a>：我喜欢的音乐、歌词与播放队列</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-weread.webp'><img src='/shots/etaf-weread.webp' alt='Emacs 里的微信读书客户端' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-weread'>etaf-weread</a>：书架、笔记本与阅读统计</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-md-preview.webp'><img src='/shots/etaf-md-preview.webp' alt='Emacs 里并排显示 Markdown 原文与渲染' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-md-preview'>etaf-md-preview</a>：左边原文，右边渲染</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-pi.webp'><img src='/shots/etaf-pi.webp' alt='Emacs 里的 Pi 代理客户端' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-pi'>etaf-pi</a>：恢复的会话与工具输出</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-telega.webp'><img src='/shots/etaf-telega.webp' alt='Emacs 里的 Telegram 客户端' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-telega'>etaf-telega</a>：会话、群组与频道</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-desktop.webp'><img src='/shots/etaf-desktop.webp' alt='ETAF Desktop 窗口管理器' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-desktop'>etaf-desktop</a>：窗口、工作区与启动器</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-algo-lab.webp'><img src='/shots/etaf-algo-lab.webp' alt='Emacs 里的算法实验室' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-algo-lab'>etaf-algo-lab</a>：观看、操控并对比算法运行</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-video-player.webp'><img src='/shots/etaf-video-player.webp' alt='Emacs 里的视频播放器' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-video-player'>etaf-video-player</a>：清晰图像帧加声音播放视频</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-ascii-video.webp'><img src='/shots/etaf-ascii-video.webp' alt='Emacs 里的字符视频' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-ascii-video'>etaf-ascii-video</a>：把视频渲染成字符</figcaption>
  </figure>
</div>

### 游戏

<div class='etaf-shots'>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-solitaire.webp'><img src='/shots/etaf-solitaire.webp' alt='Emacs 里的纸牌接龙' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-solitaire'>etaf-solitaire</a>：Verdant，K+ Klondike 纸牌接龙</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-xiangqi.webp'><img src='/shots/etaf-xiangqi.webp' alt='楚河中国象棋' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-xiangqi'>etaf-xiangqi</a>：矢量棋盘上的中国象棋</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-tanks.webp'><img src='/shots/etaf-tanks.webp' alt='钢铁洪流坦克战' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-tanks'>etaf-tanks</a>：Iron Tide 实时坦克战</figcaption>
  </figure>
  <figure>
    <a class='etaf-shot-link' href='/shots/etaf-salvage.webp'><img src='/shots/etaf-salvage.webp' alt='Salvage Station 游戏' loading='lazy' class='etaf-shot' /></a>
    <figcaption><a href='https://github.com/emacs-taf/etaf-salvage'>etaf-salvage</a>：Salvage Station 实时探索与回收</figcaption>
  </figure>
</div>

这里收录 ecss、ekp、ebox、etaf、etaf-ui 与 etaf-db 的全部公共接口，以及它们背后的机制。先读[引言](/zh-cn/introduction/)，也可以直接跳到[样式属性参考](/zh-cn/style-properties/)、[UI 总论](/zh-cn/ui-overview/)、[术语表](/zh-cn/glossary/)与[符号索引](/zh-cn/symbol-index/)。
"
  "Chinese splash page for the site in `site/'.")

(defun export-site--landing (language)
  "Return the landing page text of LANGUAGE."
  (if (equal language "zh-CN")
      export-site--landing-zh
    export-site--landing-en))

(defun export-site--sidebar-item (chapter language)
  "Return CHAPTER's sidebar entry for LANGUAGE."
  (let* ((label (format "%s" (or (plist-get chapter :title) "")))
         (number (plist-get chapter :number)))
    (when number
      (setq label (format "%s %s" number label)))
    (list (intern (symbol-name (plist-get chapter :id))) label)))

(defun export-site--js (value)
  "Return VALUE as a double-quoted JavaScript string."
  (format "\"%s\"" (replace-regexp-in-string
                    "\"" "\\\\\"" (format "%s" value) t t)))

(defun export-site--sidebar (books)
  "Return the sidebar module text built from BOOKS (en . zh-CN)."
  (let* ((en (cdr (assoc "en" books)))
         (zh (cdr (assoc "zh-CN" books)))
         (en-chapters (plist-get en :chapters))
         (zh-chapters (plist-get zh :chapters)))
    (cl-labels
        ((groups
          (en-list zh-list en-label zh-label)
          (format
           "  { label: %s, translations: { 'zh-CN': %s }, items: [\n%s\n  ] }"
           (export-site--js en-label) (export-site--js zh-label)
           (mapconcat
            (lambda (pair)
              (let* ((title (export-site--item-title (car pair)))
                     (zh-title (export-site--item-title (cdr pair))))
                (format "    { label: %s, translations: { 'zh-CN': %s }, slug: '%s' },"
                        (export-site--js title) (export-site--js zh-title)
                        (symbol-name (plist-get (car pair) :id)))))
            (cl-mapcar #'cons en-list zh-list) "\n"))))
      (string-join
       (append
        (cl-loop for en-part in (plist-get en :parts)
                 for zh-part in (plist-get zh :parts)
                 collect
                 (groups (cl-loop for id in (plist-get en-part :chapters)
                                  collect (cl-find id en-chapters
                                                   :key (lambda (c) (plist-get c :id))))
                         (cl-loop for id in (plist-get zh-part :chapters)
                                  collect (cl-find id zh-chapters
                                                   :key (lambda (c) (plist-get c :id))))
                         (plist-get en-part :title)
                         (plist-get zh-part :title)))
        (let ((en-appendix (cl-remove-if-not
                            (lambda (c) (eq (plist-get c :kind) 'appendix)) en-chapters))
              (zh-appendix (cl-remove-if-not
                            (lambda (c) (eq (plist-get c :kind) 'appendix)) zh-chapters)))
          (list (groups en-appendix zh-appendix
                        (export-site--ui "en" :appendices)
                        (export-site--ui "zh-CN" :appendices))))
        (let ((en-index (cl-remove-if-not
                         (lambda (c) (eq (plist-get c :kind) 'index)) en-chapters))
              (zh-index (cl-remove-if-not
                         (lambda (c) (eq (plist-get c :kind) 'index)) zh-chapters)))
          (list (groups en-index zh-index
                        (export-site--ui "en" :indices)
                        (export-site--ui "zh-CN" :indices)))))
       ",\n"))))

(defun export-site--item-title (chapter)
  "Return CHAPTER's sidebar label with its number when it has one."
  (let ((title (format "%s" (or (plist-get chapter :title) "")))
        (number (plist-get chapter :number)))
    (if number (format "%s %s" number title) title)))

(defun export-site--export (site books)
  "Write BOOKS into SITE's Starlight content tree."
  (let ((docs (expand-file-name "src/content/docs" site)))
    (when (file-directory-p docs)
      (delete-directory docs t))
    (dolist (language (list "en" "zh-CN"))
      (let* ((book (cdr (assoc language books)))
             (locale (cdr (assoc language export-site--locales)))
             (ids (export-site--routes book))
             (directory (if (equal locale "en")
                            docs
                          (expand-file-name locale docs))))
        (dolist (chapter (plist-get book :chapters))
          (export-site--write
           (expand-file-name (format "%s.md" (plist-get chapter :id)) directory)
           (export-site--page chapter language locale ids)))
        (export-site--write
         (expand-file-name "index.mdx" directory)
         (export-site--landing language))))
    (export-site--write
     (expand-file-name "src/sidebar.mjs" site)
     (concat "// Generated by scripts/export-site.el; do not edit.\nexport default [\n"
             (export-site--sidebar books)
             "\n];\n"))))

(defun export-site--arguments ()
  "Parse command line arguments."
  (let ((site (expand-file-name "site" etaf-manual--root))
        (arguments command-line-args-left))
    (setq command-line-args-left nil)
    (while arguments
      (pcase (pop arguments)
        ("--" nil)
        ("--site" (setq site (expand-file-name (pop arguments))))
        (argument (error "Unknown argument: %s" argument))))
    site))

(defvar export-site--no-run nil
  "When non-nil, loading this file only defines functions.")

(unless export-site--no-run
  (let ((site (export-site--arguments)))
    (export-site--export
     site
     (mapcar (lambda (pair)
               (cons (car pair)
                     (etaf-manual--read-book
                      (expand-file-name "book" etaf-manual--root) (car pair))))
             export-site--locales))))

;;; export-site.el ends here
