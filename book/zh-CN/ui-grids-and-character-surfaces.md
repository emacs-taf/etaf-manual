# 格子与字符表面

三个目录组件为应用提供固定几何的字符表面：格子网格把坐标回调投影到格子里，文本网格由独立保留的定宽文本行组成，扑克牌的内在尺寸永不被拉伸去填满视口。它们拥有布局与激活，从不拥有调用方的棋盘、棋盘状态、定时器或游戏规则，尺寸也始终保持调用方声明的值，即使窗口变化。[图片](images.md)定义格子使用的图像 Host，[UI 组件库总论](ui-overview.md)定义共同契约，[Grid 布局](grid-layout.md)定义底层轨道模型。

## 格子网格

<!-- index: etaf-tile-grid; coordinate callbacks; fixed cells; cell image -->

#### Component: etaf-tile-grid (&key rows columns cell-width cell-height cell-background cell-color cell-text cell-label cell-image cell-ref on-cell-press on-cell-focus)

渲染 ROWS 乘 COLUMNS 个带稳定坐标身份的固定格子。

**参数。** ROWS 与 COLUMNS 是正整数；CELL-WIDTH（字符列，默认 2）与 CELL-HEIGHT（文本行，默认 1）是正整数，视口变化时保持固定。回调接收从零开始的行与列：CELL-BACKGROUND 返回颜色或 nil；CELL-COLOR 提供前景（nil 继承）；两者都可以返回延迟 Theme token。CELL-TEXT 返回适配 CELL-WIDTH 的单行（默认一个空格）。CELL-IMAGE 返回本地文件路径、Emacs 图像描述符（包括生成的 SVG）或 nil——图像经 image Host 填满固定格子，nil 改用 CELL-TEXT，来源解码失败用 image Host 的占位。CELL-LABEL 返回可访问名与帮助文本（默认 `"Cell r,c"`）。CELL-REF 为每格返回不同的 Host 引用；省略时引用为实例本地。ON-CELL-PRESS 处理键盘与鼠标激活，没有它时格子只读；ON-CELL-FOCUS 在焦点进入格子时报告坐标。

**语义。** 网格拥有布局与激活，不拥有棋盘状态或定时器：它在回调里读取调用方的 ref，未变的格子因此保留内容，也从不维护第二份选择。有按压回调时每个格子都是 `grid` 焦点组里带 Tab 序号的 `button`；没有时格子是惰性的。格子裁剪隐藏溢出并居中内容，焦点描边标记聚焦的格子。

**返回。** 一个 View。

**错误。** ROWS、COLUMNS、CELL-WIDTH 或 CELL-HEIGHT 不是正整数、或某个坐标回调既不是函数也不是 nil 时报 `error→ etaf-component-call-error`。CELL-TEXT 或 CELL-LABEL 不是适配格宽的单独一行时也在渲染期报错。

**示例。**

```elisp
(etaf-tile-grid :rows 8 :columns 12 :cell-width 2 :cell-height 1
                :cell-text (lambda (_r _c) ".")
                :on-cell-press (lambda (row column) (select-cell row column)))
```

**参见。** `etaf-text-grid`、[图片](images.md)。

## 文本网格

<!-- index: etaf-text-grid; fixed-width rows; monospace surface -->

#### Component: etaf-text-grid (&key rows columns row-text row-ref label)

显示 ROWS 个固定文本行，每行 COLUMNS 个字符列宽。

**参数。** ROWS 与 COLUMNS 是正整数。ROW-TEXT 是必需回调，接收从零开始的行号；它返回显示宽度不超过 COLUMNS 的单行字符串，短行用空格补齐。ROW-REF 可选，为每行返回不同的 Text Host 引用以做保留内容更新——那些更新同样必须适配并补齐到 COLUMNS，且与回调状态保持同步。LABEL 命名这个只读表面（默认 `"Text grid"`）。

**语义。** 每行保留稳定身份与自己的保留边界，因此一行文本变化只重绘一行而不是整个表面。组件没有焦点目标、输入处理、定时器或终端转义解释；它是等宽展示，宽字符按 Emacs 显示宽度占位。拥有更细粒度身份的调用方用这种逐行保留来替代一个大文本宿主。

**返回。** 一个 View。

**错误。** ROWS 或 COLUMNS 不是正整数、ROW-TEXT 不是函数、ROW-REF 既不是函数也不是 nil、或 LABEL 不是字符串时报 `error→ etaf-component-call-error`。渲染期行内容不是字符串、含换行、回车或制表符、或宽于 COLUMNS 时报同一条件并点名 ROW-TEXT。

**示例。**

```elisp
(etaf-text-grid :rows 24 :columns 80 :row-text (lambda (row) (buffer-line row)))
```

**参见。** `etaf-tile-grid`。

## 扑克牌

<!-- index: etaf-playing-card; card face; pile placeholder; intrinsic size -->

#### Component: etaf-playing-card (&key rank suit face-down empty selected disabled on-press label ref columns lines)

把受控的扑克牌或空牌堆占位呈现为单一激活目标。

**参数。** RANK 是最多三列的单行字符串；SUIT 是 `spades`、`hearts`、`clubs`、`diamonds` 或 nil。FACE-DOWN 隐藏点数与花色，包括生成的可访问名。EMPTY 呈现空牌堆占位。SELECTED 只改变绘制而不改变几何。COLUMNS 默认 9、最小 7，LINES 默认 5、最小 1；一行只露出叠牌中的牌角。这些内在尺寸从不拉伸填满视口。ON-PRESS 不收参数；省略或禁用的牌不可交互。LABEL 覆盖可访问名与帮助，因此调用方不得把隐藏信息写在那里。

**语义。** 牌是一个以格为单位定尺寸的居中按钮：左上角是点数与花色符号，中央是花色标记（背面时画 `◇`），超过三行高时右下角再出现一个角标。颜色来自扑克牌 token——默认底是暖象牙色，花色墨色黑或红，背面用蓝色，空堆用弱化占位色，选中用琥珀底色，悬停有反馈——因此游戏可以通过自己的 Theme 给整张牌桌换装。悬停保留全部文字并覆盖整张牌的绘制区域；牌背和空牌堆从自身底色派生轻微变化，不套用正面的悬停底色；选中的牌不再叠加悬停色。选择、叠放、移动与规则归调用方所有，也不需要任何游戏后端。

**返回。** 一个 View。

**错误。** RANK 既不是 nil 也不是最多三列的单行字符串、SUIT 不是四种花色之一或 nil、COLUMNS 小于 7、或 LINES 小于 1 时报 `error→ etaf-component-call-error`。

**示例。**

```elisp
(etaf-playing-card :rank "A" :suit 'hearts :on-press #'play-card)
```

## 扑克牌 token

<!-- index: ui-playing-card-bg; ui-playing-card-red; ui-playing-card-back-bg -->

#### Token: :ui-playing-card-bg

普通牌的牌面底色。

#### Token: :ui-playing-card-black

黑桃或梅花牌的墨色。

#### Token: :ui-playing-card-red

红桃或方块牌的墨色。

#### Token: :ui-playing-card-back-bg

背面牌的背景。

#### Token: :ui-playing-card-back-fg

背面牌的前景。

**语义。** 这一对绘制盖住的牌；背面牌绝不通过绘制、文本或可访问名泄漏点数与花色。

#### Token: :ui-playing-card-empty-bg

空牌堆占位的背景。

#### Token: :ui-playing-card-empty-fg

空牌堆占位符号的颜色。

#### Token: :ui-playing-card-selected-bg

选中牌的背景。

#### Token: :ui-playing-card-hover-bg

可交互牌的悬停浅色。

**语义。** 选中与悬停都只是绘制——牌的几何与牌堆的布局从不移动——没有提供 Theme 时每个 token 都回退到目录的内置调色板。

## 错误与恢复

- `error→ etaf-component-call-error` 经 `etaf-check-prop` 报告每一条被拒绝的输入：非正的尺寸、不是函数的回调、不是适配列宽的单独一行的行内容、过宽的点数、未知花色以及窄于七列的牌。
- 网格不拥有可回滚的状态：被拒绝的回调结果让渲染失败，此前发布的格子或行留在屏幕上。
- 无法解码的格子图像走 image Host 的占位路径而不是让网格失败；nil 图像直接回退到格子文本。
- 扑克牌是纯呈现：按压只报告给调用方，被忽略的按压让牌保持原样。

**参见。** [UI 组件库总论](ui-overview.md#错误与恢复)、[图片](images.md)。

```elisp :run
(etaf-view
 (column :item-gap '(lh 1)
   (etaf-tile-grid :rows 2 :columns 4 :cell-width 3 :cell-height 1
                   :cell-text (lambda (row column) (format "%d%d" row column))
                   :on-cell-press #'ignore)
   (etaf-playing-card :rank "A" :suit 'hearts :on-press #'ignore)))
```
