# 按钮与选择控件

目录的动作与选择控件都遵循同一份受控契约：值 prop 加变更回调，或经 `:bind` 传一个可写 ref；应用拥有值，组件只负责渲染并报告用户做了什么。按钮提交动作，checkbox 与 switch 拥有一个布尔量，radio 与 segmented 从固定列表里挑选，slider 与 range 报告一个由调用方保存的数字。本章定义这七个控件、它们的键盘行为以及共用的颜色 token。[UI 组件库总论](ui-overview.md)定义受控契约，[事件](events.md)定义一次按压如何到达回调，[焦点](focus.md)与[键盘](keyboard.md)定义控件继承的 Tab 与方向键行为，[组件样式与主题](component-styles-and-themes.md)定义 token 机制。

## 共用的选择契约

<!-- index: controlled control; tonal pill; selection state; bind -->

选择控件是*色调药丸*而不是带框输入框：选中控件绘制 secondary 按钮的浅色，未选中继承自己的表面，两者都没有描边。因为 secondary 浅色是对话框 token，选中控件在变暗 shell 之上的模态里依然清晰。几何不随选择变化——状态是绘制而不是布局——所以切换分段或勾选盒子永远不会移动邻项。

每个控件都经同一份契约读取输入。显式的 `:value` 或 `:checked` prop 与 `:on-change` 回调构成受控对；作为 `:bind` 传入的可写 ref 替代两者，其当前值提供显示状态。非 nil 的 bind 与显式的值或回调同时出现会被拒绝，冲突消息点名出问题的属性。ref 归调用方所有：被拒绝的发布保留此前的绑定目标，卸载时释放控件的处理器与订阅而不触碰 ref。

`DISABLED` 移除控件的回调与 Tab 停靠点，同时保留它的占位，所以切换可用性永不移动布局。受控接口之外还可以提供加性的 `:on-press` 观察者；它观察激活而不进入值路径。

## 按钮

<!-- index: etaf-button; button variant; failed publication; ghost -->

#### Component: etaf-button (&key label on-press disabled id ref class color bgcolor border padding font-size font-weight tab-index aria-label aria-selected help-echo hover-content hover-group pointer use variant)

渲染带提交回调的标准可按压按钮。

**参数。** LABEL 命名按钮，除非 default slot 取而代之。ON-PRESS 是零参回调。DISABLED 移除回调与默认 Tab 序号。VARIANT 是 `primary`（accent 填充、加粗；默认）、`secondary`（accent 浅色）或 `ghost`（继承表面、内边距更窄）；每个变体都是无边框的单行药丸，variant 名进入第二个类名。呈现类 prop COLOR、BGCOLOR、BORDER、PADDING、FONT-SIZE 与 FONT-WEIGHT 覆盖变体默认值。ID 到达渲染出的 Host，使基于锚点的表面能按身份引用该按钮；CLASS、REF、TAB-INDEX、ARIA-LABEL、ARIA-SELECTED、HELP-ECHO、HOVER-CONTENT、HOVER-GROUP、POINTER 与 USE 是普通 Host 能力。

**语义。** Runtime 把 ON-PRESS 与可见按钮一起发布，因此渲染失败时保留此前的回调及它捕获的值。按钮是一行的：它不会缩到标签以下，也不会拆开标签文字，因此空间不足的 Flex 行会整体移动按钮，而不是拆开它的文字。启用且未选中的按钮在指针悬停时画变体的 hover 填充；tab 与 segmented 这类 ARIA-SELECTED 控件保持选中表现，不叠加悬停高亮。default slot 用普通的非交互内容（比如标题与描述）取代可见标签；LABEL 或 ARIA-LABEL 仍命名单一的焦点与激活目标，按钮内部嵌套控件是不合适的。原生根属性 `:pointer`、`:help-echo`、`:hover-style` 与 `:hover-content` 请求 Ebox 的文本属性能力，显式 nil 阻断继承来的能力。

**返回。** 一个 View。

**错误。** 名字既不是已声明 prop 也不是受支持的 Host 属性时报 `error→ etaf-component-call-error`。

**示例。**

```elisp
(etaf-button :label "Save" :variant 'primary :on-press #'save-buffer)
```

**参见。** `etaf-checkbox`、`:ui-button-primary-bg`。

## checkbox 与 switch

<!-- index: etaf-checkbox; etaf-switch; checkbox mark; switch state -->

#### Component: etaf-checkbox (&key checked label on-change disabled bind)

渲染受控 checkbox，下一个值发送给 ON-CHANGE。

**参数。** CHECKED 是显示的布尔量、ref 或 computed。ON-CHANGE 接收下一个布尔量。LABEL 是可见说明与可访问名。BIND 是一个已存在的可写 ref，替代 CHECKED 与 ON-CHANGE。

**语义。** 控件绘制加粗的 `[x]` 或 `[ ]` 标记，后接标签。不创建额外状态：对绑定 ref 的外部写入会更新控件，禁用控件不能写，加性的 `:on-press` 观察者只观察激活而不影响值路径。发布失败保留旧绑定目标，卸载释放控件的处理器与订阅而不拥有调用方的 ref。

**返回。** 一个 View。

**错误。** 非 nil 的 BIND 与显式 CHECKED 或 ON-CHANGE（包括 nil）同时出现时报 `error→ etaf-component-call-error`，点名冲突的属性；BIND 不是可写 ref 时同样报错。

**示例。**

```elisp
(etaf-checkbox :label "Auto-save" :checked t)
```

**参见。** `etaf-switch`、`:ui-checkbox-enabled-fg`。

#### Component: etaf-switch (&key checked label on-change disabled bind)

渲染受控的二元开关，所有权契约与 checkbox 相同。

**参数。** CHECKED 必须是布尔量、ref 或 computed；LABEL 默认为 `"Switch"`；BIND 与 `etaf-checkbox` 相同。

**语义。** 开关是单个 ghost 按钮，标题为 `"[x] LABEL"` 或 `"[ ] LABEL"`，打开时用选择色绘制。它的可访问名是 LABEL。

**返回。** 一个 View。

**错误。** 解析后的 CHECKED 不是布尔量、或 LABEL 不是字符串时报 `error→ etaf-component-call-error`。

**示例。** `(etaf-switch :checked nil :label "Aeroplane mode")`

## radio 与 segmented

<!-- index: etaf-radio; etaf-segmented; option alist; tab list -->

#### Component: etaf-radio (&key value options label on-change disabled bind)

从选项 alist 渲染受控的单选组。

**参数。** OPTIONS 是非空 alist，把唯一的标量值映射到唯一的非空字符串标签。VALUE 是 nil 或其中一个选项值。LABEL 命名分组，默认 `"Choice"`。ON-CHANGE 接收选中的值；BIND 与 `etaf-checkbox` 相同。

**语义。** 分组是带标签的 column，各选项属于同一个水平焦点组，方向键因此在选项间移动。每个选项是 ghost 按钮，选中时标题加前缀 `"(o) "`、未选中用 `"( ) "`，选中的那个绘制选择色。分组的 role 是 `radiogroup`，每个选项以自身标签作为可访问名。

**返回。** 一个 View。

**错误。** OPTIONS 为空或形式非法、值或标签重复、VALUE 不在 OPTIONS 中、或 LABEL 不是字符串时报 `error→ etaf-component-call-error`。

**示例。**

```elisp
(etaf-radio :value 'b :label "Mode"
            :options '((a . "Alpha") (b . "Beta")))
```

**参见。** `etaf-segmented`、`:ui-button-secondary-bg`。

#### Component: etaf-segmented (&key value options on-change disabled bind)

从选项 alist 渲染紧凑的互斥选择器。

**参数。** OPTIONS、VALUE、ON-CHANGE 与 BIND 与 `etaf-radio` 相同；没有说明标签。

**语义。** 各分段是同一水平焦点组里的按钮，间隔两列，带 `tablist` role。选择完全由按钮变体承载——选中的分段用 secondary、其余是 ghost——因此没有前缀改变标题宽度，选择移动时整行永不跳动。

**返回。** 一个 View。

**错误。** OPTIONS 为空或形式非法、值或标签重复、或 VALUE 不在 OPTIONS 中时报 `error→ etaf-component-call-error`。

**示例。**

```elisp
(etaf-segmented :value 'day
                :options '((day . "Day") (week . "Week") (month . "Month")))
```

## slider

<!-- index: etaf-slider; integer slider; native prompt; step alignment -->

#### Component: etaf-slider (&key value min max step label on-change disabled bind)

渲染受控的数值 slider。

**参数。** VALUE 必须是介于 MIN 与 MAX 之间、对齐 STEP 的整数。MIN 与 MAX 是满足 `min <= max` 的整数（默认 0 与 100）；STEP 是正整数（默认 1）。LABEL 默认为 `"Value"`。ON-CHANGE 接收下一个整数；BIND 与 `etaf-checkbox` 相同。

**语义。** slider 是带标签的 column：strong 说明与 muted 当前值，然后是一个显示 `"◀  N  ▶"` 的 secondary 按钮。按钮聚焦时，Left 与 Right 经方向通道报告移动一个 STEP 后的 VALUE，Home 与 End 不绑定；激活按钮会打开布局之外的原生 `read-number`，之后恢复焦点，并且只在结果通过同样的整数、范围与 STEP 对齐检查后才写入。取消提示保持值不变。

**返回。** 一个 View。

**错误。** MIN 或 MAX 不是整数、MAX 小于 MIN、STEP 不是正整数、LABEL 不是字符串、或 VALUE 不是边界内对齐的整数时报 `error→ etaf-component-call-error`。原生提示把不对齐或越界的输入报告为 `user-error` 且不写入。

**示例。**

```elisp
(etaf-slider :value 4 :min 0 :max 10 :step 2 :label "Level")
```

## range

<!-- index: etaf-range; retained fill; drag preview; commit callback; reactive bounds -->

#### Component: etaf-range (&key value min max step key-step on-change on-commit disabled color track-color bar-height label ref fill-ref)

在 MIN..MAX 内渲染受控的交互式 range（进度、拖动定位、音量）。

**参数。** VALUE 是 MIN..MAX 内的数字或响应式源，STEP 非 nil 时对齐 STEP。MIN 与 MAX 接受数字或响应式源。KEY-STEP 是方向键步长，默认 STEP，否则为跨度的二十分之一。ON-CHANGE 报告中间值，ON-COMMIT 报告释放值。BAR-HEIGHT 是绘制厚度占行的百分比（默认 40）。COLOR 与 TRACK-COLOR 覆盖填充与轨道 token。LABEL 是可访问名。REF 命名轨道 Host，FILL-REF 命名填充 Host。

**语义。** 进度条由普通流里承载规则字符串的轨道、以及绘制在其上方、宽度为百分比的绝对定位填充 Host 组成。指针点击把所指的值经 ON-CHANGE 与 ON-COMMIT 报告；拖拽把中间值经 ON-CHANGE、释放值经 ON-COMMIT 报告。按压或拖拽在调用方的值到达之前就通过保留 Host 几何重新分配两部分的比例，因此在后端回复未到时手势仍跟随指针。range 聚焦时，Left 与 Right 报告移动 KEY-STEP 后的值，Home 与 End 报告 MIN 与 MAX。调用方可以用 `etaf-runtime-update-host-geometries` 加 `:width` 百分比就地移动填充而不重新发布 View，播放位置就是这样推进的。经响应式源变化的边界在保留填充处读取，未就绪的 nil 边界画空跨度而不是失败。

**返回。** 一个 View。

**错误。** MIN 或 MAX 既不是数字也不是响应式源、静态 MAX 小于 MIN、STEP 或 KEY-STEP 不是正数、BAR-HEIGHT 不是 1 到 100 的整数百分比、ON-CHANGE 或 ON-COMMIT 既不是函数也不是 nil、或 DISABLED 不是布尔量时报 `error→ etaf-component-call-error`。解析出的响应式 MAX 小于 MIN 时，在保留填充读取它时报错。

**示例。**

```elisp
(etaf-range :value 30 :min 0 :max 100 :on-change #'preview-volume
            :on-commit #'set-volume :label "Volume")
```

**参见。** `:ui-range-fill`、`:ui-range-track`、[拖拽与手势](dragging-and-gestures.md)。

## 选择 token

<!-- index: ui-button-primary-fg; ui-button-secondary-fg; ui-checkbox-enabled-fg; ui-range-fill -->

#### Token: :ui-button-primary-fg

primary 按钮的前景。

**语义。** 画在 `:ui-button-primary-bg` 上，用于填充 accent 的按钮，配加粗文字。

#### Token: :ui-button-primary-bg

primary 按钮的填充。

#### Token: :ui-button-primary-hover-bg

primary 按钮的悬停填充。

**语义。** 指针悬停在启用的 primary 按钮上时，填充换成这个颜色；按钮不移动也不改变尺寸。

#### Token: :ui-button-secondary-fg

secondary 按钮与选中项的前景。

**语义。** checkbox 标记、radio 与 segmented 的选中项、switch 打开时的文字以及选择器行都用这个颜色画在 `:ui-button-secondary-bg` 上；因为它们是对话框 token，选中控件在变暗的 shell 之上依然清晰。

#### Token: :ui-button-secondary-bg

secondary 按钮与选中项的浅色。

#### Token: :ui-button-secondary-hover-bg

secondary 按钮的悬停浅色。

**语义。** 指针悬停在启用的 secondary 按钮上时，浅色换成这个颜色；选中项保持自己的选中颜色。

#### Token: :ui-button-ghost-fg

ghost 按钮的前景。

**语义。** ghost 按钮继承自己的表面、只画文字，因此未选中的分段或朴素的 tag 关闭控件读作内容而不是盒子。

#### Token: :ui-button-ghost-hover-bg

ghost 按钮的悬停表面。

**语义。** 指针悬停在启用的 ghost 按钮上时，它画上这个表面；指针离开后按钮依旧透明，露出周围的 panel。

#### Token: :ui-checkbox-enabled-fg

启用的 checkbox 的标签颜色。

#### Token: :ui-checkbox-disabled-fg

禁用的 checkbox 的标签颜色。

#### Token: :ui-range-fill

range 条填充的 accent 色。

**语义。** 绘制在轨道之上、表示已填充的部分；调用方可以用 range 的 `:color` prop 按实例覆盖。

#### Token: :ui-range-track

range 条未填充的轨道。

**语义。** 画成指针命中的那条规则字符串，因此它实测出的宽度决定指针位置如何映射成值；调用方可用 `:track-color` 覆盖。

## 错误与恢复

- `error→ etaf-component-call-error` 经 `etaf-check-prop` 报告每一条被拒绝的输入，消息点名组件、属性、收到的值与期望：bind 与显式值或回调同时出现、选项表为空或含重复、值不在选项中、slider 边界不是整数或值不对齐，以及 range 的边界、步长、厚度与回调契约。
- 发布失败保留最后一次已提交状态：按钮保留此前的回调与捕获值，绑定控件保留此前的绑定目标。组件永不回滚调用方的业务 ref。
- 禁用控件不是惰性标记：它移除自己的回调与 Tab 停靠点，因此激活无法到达它，而布局占位保持不变。
- slider 的原生提示是控件唯一离开布局的地方：取消提示不改变任何东西，不对齐的输入报告为 `user-error` 且不写入。

**参见。** [UI 组件库总论](ui-overview.md#错误与恢复)。

```elisp :run
(etaf-view
 (column :item-gap '(lh 1)
   (row :item-gap '(ch 1)
     (etaf-button :label "Save" :on-press #'ignore)
     (etaf-button :label "Cancel" :variant 'ghost :on-press #'ignore))
   (etaf-segmented :value 'week
                   :options '((day . "Day") (week . "Week")))
   (etaf-checkbox :label "Auto-save" :checked t)))
```
