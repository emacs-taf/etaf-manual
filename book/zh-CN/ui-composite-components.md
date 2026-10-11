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
