# 组合组件

目录里有两个组件存在的意义是组合既有契约而不是引入新契约。`etaf-date-picker` 是目录的原生文本字段加一条日期契约，`etaf-command-palette` 是裹着可选择列表的模态对话框。两者都受控且无状态：值或命令表归调用方所有，组件只负责渲染与报告。[文本输入控件](ui-text-input-controls.md)定义它们所基于的字段，[浮层](ui-overlays.md)定义对话框，[导航与集合](ui-navigation-and-collections.md)定义列表，[UI 组件库总论](ui-overview.md)定义共同契约。

## 日期选择器

<!-- index: etaf-date-picker; ISO date; draft value; submit validation -->

#### Component: etaf-date-picker (&key value label placeholder on-change disabled bind)

在目录的原生文本字段上渲染语义日期输入。

**参数。** VALUE 是受控值：ISO `YYYY-MM-DD` 字符串或 nil。LABEL 默认 `"Date"`。PLACEHOLDER（默认 `"YYYY-MM-DD"`）在字段为空时显示。ON-CHANGE 接收被接受的值：完整日期字符串，或字段被清空时的 nil。DISABLED 移除编辑，BIND 用可写 ref 替代 VALUE 与 ON-CHANGE，遵循 `etaf-text-input`。

**语义。** 编辑是原生、就地的，与文本字段所述完全一致。部分日期是草稿：尚未构成完整日期的击键不会被报告，上一个被接受的值保持不动。提交时会拒绝既不为空也不是完整日期的输入，报出点名标签的可读错误，而不是把它写进去。检查是形状检查——四位、两位、两位——所以形状合法但不存在的日期如 `2026-13-01` 也会被接受为值；强制日历合法性属于应用的业务规则。

**返回。** 一个 View。

**错误。** VALUE 既不是 nil 也不是 ISO `YYYY-MM-DD` 字符串时报 `error→ etaf-component-call-error`。提交非法草稿时报 `user-error`，消息含标签与期望形状，且值保持不变。

**示例。**

```elisp
(etaf-date-picker :value "2026-01-15" :label "Due"
                  :on-change (lambda (date) (setq due date)))
```

**参见。** `etaf-text-input`、`etaf-calendar`。

## 命令面板

<!-- index: etaf-command-palette; modal list; command registry -->

#### Component: etaf-command-palette (&key open title items on-select on-close)

组合模态对话框与列表，用于调用方拥有的命令选择。

**参数。** OPEN 是值、ref 或 computed。TITLE 默认 `"Command palette"`。ITEMS 遵循 `etaf-list`：带唯一 `:key`、非空字符串 `:title` 与可选 `:description` 的 item plist——命令的名字是它的 title，而不是菜单标签。ON-SELECT 接收选中的键，ON-CLOSE 必需。

**语义。** 打开时，面板是宽 `(ch 56)` 的居中模态对话框，正文是一个可选择列表，默认 footer 提供关闭按钮；Escape 与 header 的 `x` 与任何对话框一样请求 ON-CLOSE。面板不拥有命令表、过滤或执行：由应用提供条目、决定键的含义并关闭对话框。

**返回。** 一个 View。

**错误。** ON-CLOSE 不是函数时报 `error→ etaf-component-call-error`；ITEMS 遵循列表自己的 item 契约。

**示例。**

```elisp
(etaf-command-palette :open palette :on-close (lambda () (setf palette nil))
                      :items '((:key save :title "Save file")
                               (:key open :title "Open file"))
                      :on-select #'run-command)
```

**参见。** `etaf-list`、`etaf-dialog`。

## Markdown 正文渲染

<!-- index: markdown; 文档树; 调色板; 渲染回调 -->

Markdown 正文渲染把 Markdown 文本转换成普通 ETAF View，供 Markdown 预览器、手册阅读器与其他文档视图共用。它分两步：`etaf-ui-markdown-parse` 把文本解析成不带呈现事实的块树，渲染函数再把块树与一份环境 plist 变成 View。两步都是纯函数，不拥有缓冲区、运行时状态或文件，所以同一代码路径既服务离屏测试，也服务已挂载的 Component。

#### Function: etaf-ui-markdown-parse (text &optional flavor)

把 Markdown 文本解析为文档 plist。

**参数。** TEXT 是 Markdown 源文本。FLAVOR 选择方言：`etaf-ui-markdown-flavors` 中的名字（默认 `gfm`）、覆盖个别扩展标志的特性 plist，或 nil 以使用 `etaf-ui-markdown-flavor`。

**语义。** 解析覆盖 CommonMark 的块与内联结构以及 GitHub 扩展：管道表格、任务列表项、删除线、裸自动链接、脚注与告警块；YAML front matter 被剥离为文档元数据。块是 plist，`:type` 为 `heading`、`paragraph`、`code-block`、`blockquote`、`list`、`table`、`thematic-break`、`html-block` 或 `footnote-def`；内联的 `:type` 为 `text`、`code`、`emph`、`strong`、`strike`、`link`、`image`、`autolink`、`footnote-ref`、`html` 或 `break`。块树不携带呈现事实：样式与 ETAF 节点的选择属于渲染函数。标题获得稳定且唯一的锚点；链接引用定义与脚注定义在块读取时收集，再解析进内联节点。解析是纯 Elisp，不读缓冲区、文件或网络。

**返回。** 文档 plist：`:meta`（front matter alist）、`:title`、`:children`（带标题锚点的顶层块）、`:outline`（按文档顺序的 `(LEVEL TEXT ID)`）、`:footnotes`（含 `:label`、`:number` 与 `:children`）与 `:features`（解析出的扩展 plist）。

**错误。** 未知方言名报 `error→ etaf-ui-markdown-error`。

**示例。**

```elisp
(etaf-ui-markdown-parse "# 标题\n\n正文。\n")
```

**参见。** `etaf-ui-markdown-view-blocks`、`etaf-ui-markdown-flavors`。

#### Function: etaf-ui-markdown-view-block (block env)

把一个块渲染为一个 ETAF View，无可渲染内容时返回 nil。BLOCK 是 `etaf-ui-markdown-parse` 的一个顶层块，ENV 是 `etaf-ui-markdown-view-blocks` 描述的环境 plist。展开成多个 View 的块被包进一个 column，因此调用方每块拥有一个节点，可用于滚动、选中或逐块引用。

#### Function: etaf-ui-markdown-view-blocks (blocks env &optional tight)

按文档顺序返回 BLOCKS 的 View 列表，空输入返回 nil。相邻块之间隔一个空行，TIGHT 非 nil 时去掉。返回列表不带容器，调用方自行包裹；需要脚注定义时再渲染 `:footnotes` 的 View 并追加。环境 plist 的 `:palette` 必需，它是语义颜色键到颜色的 alist（`:ink`、`:muted`、`:faint`、`:heading`、`:accent`、`:accent-soft`、`:panel`、`:border`、`:quote-bg`、`:quote-bar`、`:table-header`、`:table-stripe`、`:ok`、`:ok-soft`、`:warn`、`:warn-soft`、`:danger`、`:danger-soft`、`:important` 与 `:important-soft`）；每个颜色都经它读取，因此换调色板不会漏出半更新的颜色，未知键报 `error→ etaf-ui-markdown-error`。其余可选项都是回调：`:open-link` 收到链接 URL；`:footnote-jump` 收到脚注标签；`:render-media (kind node env)` 返回媒体的 View，KIND 为 `image`、`video`、`inline-image` 或 `html-media`，没有它时媒体退化为 alt 文本或 URL；`:render-code-block (block env)` 可为代码块返回 View，返回 nil 保留默认围栏块；`:code-link (text)` 以每个 code span 的文本调用，可返回 URL 或 (URL . HELP) cons 把该 span 变成链接，它保留代码样式，激活时用 URL 调 `:open-link`，帮助回显为 HELP 或 URL；`:alert-labels` 按种类覆盖告警标签；`:features` 是文档解析出的扩展 plist，控制告警块是否渲染为 callout；`:line-grid` 非 nil 时每一行都保持标准行高，供与其他内容并排滚动的文档使用：标题与脚注引用沿用正文字号，一级标题改用强调色，二级标题加左侧强调条，滚动时显露的行不会改变高度。表格各列按最宽单元格的内容分配宽度，且不低于该列的 min-content，因此单词或短的 CJK 串不会被拆开；单元格在词边界换行。HTML 注释渲染为空。

#### Variable: etaf-ui-markdown-flavor

`etaf-ui-markdown-parse` 的默认方言。

**语义。** 显式的 FLAVOR 参数优先于它。`gfm` 启用 GitHub 扩展与 front matter，`commonmark` 只解析核心规范，特性 plist 可以逐项开关扩展。

**参见。** `etaf-ui-markdown-parse`、`etaf-ui-markdown-flavors`。

#### Variable: etaf-ui-markdown-flavors

具名方言与它们启用的扩展标志。

**语义。** `commonmark` 是 CommonMark 核心；`gfm` 加上渲染器也视为默认的 GitHub 扩展：表格、任务列表、删除线、裸自动链接、脚注与告警块，外加 front matter（它是文档约定而非 Markdown 扩展）。

**参见。** `etaf-ui-markdown-parse`。

#### Error: etaf-ui-markdown-error

Markdown 文档操作被拒绝时的条件。

**语义。** 未知方言名在解析时抛出；渲染时缺少 `:palette` 或点名调色板里没有的颜色键也在发布任何 View 之前抛出。数据是含描述字符串的列表。

**恢复。** 失败不产生半渲染的文档：解析失败没有块树，渲染失败没有 View 上屏。修正方言或补齐调色板键后重新调用。

**参见。** `etaf-ui-markdown-parse`、`etaf-ui-markdown-view-blocks`。

## 错误与恢复

- 日期选择器区分草稿与错误：尚不完整的日期文本只是不被报告，提交它报 `user-error` 且不写入值；取消会话恢复激活时的值。
- 面板组合列表的校验：形式非法的 item 列表在任何表面出现之前就以 `etaf-component-call-error` 失败，缺少关闭回调同样失败。
- 两个组件都无状态：被拒绝的输入让调用方的值与已挂载实例保持原样。

**参见。** [UI 组件库总论](ui-overview.md#错误与恢复)。

```elisp :run
(etaf-view
 (column :width '(ch 60) :height '(lh 18) :item-gap '(lh 1)
   (etaf-date-picker :value "2026-01-15" :label "Due")
   (etaf-command-palette :open t :on-close #'ignore :on-select #'ignore
                         :items '((:key save :title "Save file")))))
```
