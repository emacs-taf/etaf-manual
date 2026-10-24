# 浮动面板

面板是一个子 frame，在你正在工作的窗口之上承载一个 ETAF Runtime：一个时钟、一个播放器、一个计时器、一份搜索结果。面板彼此独立——各自拥有 frame、Runtime 与输入，可以同时开好几个，而且面板从不改变当前 buffer。可聚焦的面板能拿到键盘；点面板任意位置会把它提到其他面板之上。本章讲面板本体；整套应用作为面板注册见[面板应用](posframe-applications.md)，面板提供给 View 的 Theme plist 见[组件样式与主题](component-styles-and-themes.md)，可聚焦面板收到的输入见[焦点](focus.md)与[键盘](keyboard.md)，面板落位的绝对坐标见[定位、层与浮层](positioning-layers-and-overlays.md)。

## 打开、刷新与关闭

<!-- index: etaf-posframe-show; etaf-posframe-hide; etaf-posframe-toggle; 面板选项; 面板标识 -->

#### Function: etaf-posframe-show (view &rest options)

把 VIEW 显示在一个浮动面板里并返回该面板。

**参数。** VIEW 是一个 View，或返回 View 的零参函数；每次开面板都重新挂载并拿到自己的 Runtime，面板跟随调用时的当前 buffer。OPTIONS 是 plist：`:at` 是落位，可以是 `frame-top-right`、`window-center`、`point` 这类锚点，`(ANCHOR ROWS COLS)` 按字符格偏移锚点（负的行向上、负的列向左），`(cells ROW COL)` 指当前窗口的某个字符格，`(pixels X . Y)` 指 frame 像素，也可以直接给 Posframe 的 poshandler，默认 `point`；`:stack` 让面板避开同锚点上已有面板，顶部与居中锚点向下叠、底部锚点向上叠；`:width` 是内容列数，默认 `etaf-posframe-default-width`，写 `(fraction 0.5)` 取父 frame 宽度的一半，并夹在父 frame 之内；`:height` 是行预算，默认 `etaf-posframe-default-max-height`，写 `(fraction 0.5)` 取父 frame 高度的一半，内容更高就裁剪；`:fill-height` 让 frame 保持行预算而不是收到内容高度；`:title` 是标题栏文字，不给就没有 header line 也不能拖动；`:draggable` 允许拖标题栏移动面板；`:focusable` 让面板拿键盘，它的 View 的 `:keys`、文本框与按钮才收得到输入；`:focus-on-open` 决定打开时是否选中面板，默认与 `:focusable` 相同；`:auto-hide` 为 nil 时面板一直留到关闭，为 t 时用户转到别处就隐藏，为数字时表示秒数；`:theme` 为 `auto` 跟随 Emacs 主题、`light` 或 `dark` 钉住调色板、也可以直接给 Theme plist；`:border` 是[外观与边框](#外观与边框)里说明的边框 plist；`:key` 是面板标识。

**语义。** 面板是一个 frame 加一份挂载好的 Runtime，所以里面的 View 与在 buffer 里完全一样：refs、组件、按键与保留更新都照旧，面板只额外提供 frame、标题栏与指针处理。用已经活着的 `:key` 再显示会替换那个面板；不同的 key 各自拥有 frame、Runtime 与位置，两个计时器才能并排放着。从外部改过大小的 frame 会成为面板新的宽或高，View 按新尺寸重排，而不是被弹回原尺寸。

**返回。** 一个面板值，对调用方不透明；交给下面几个函数使用。

**错误。** 选项未知、锚点非法、或 frame 不是图形 frame 时报 `etaf-posframe-error`。显示失败会先卸载 View、删掉 frame，再把错误抛出去。

**示例。**

```elisp
(etaf-posframe-show (etaf-view (text "25:00"))
                    :key 'timer :title "Timer" :width 24 :height 2
                    :at 'frame-top-right :stack t :draggable t)
```

#### Function: etaf-posframe-hide (&optional panel)

隐藏 PANEL，并释放它的 Runtime、计时器与 frame。

**语义。** PANEL 默认取当前 buffer 最新的面板，面板自己的按键就是这样调它的；其他面板不受影响。隐藏会释放这个面板持有的一切，所以隐藏之后到再显示之前不占任何开销。重复调用安全，只有真的隐藏了一个活面板才返回非 nil。

**返回。** 隐藏了活面板时返回非 nil。

**参见。** `etaf-posframe-show`、`etaf-posframe-toggle`、`etaf-posframe-app`。

#### Function: etaf-posframe-toggle (view &rest options)

隐藏同一个 `:key` 的面板，或按 OPTIONS 显示 VIEW。

**语义。** 没有 `:key` 时针对当前 buffer 最新的面板。这是「一个按键开关同一个面板、不碰其他面板」的入口，接受的选项与 `etaf-posframe-show` 相同。因为面板是重新挂载而不是复用，每次打开 View 都会读当时应用的状态。

**返回。** 新面板；隐藏了面板时返回 nil。

**参见。** `etaf-posframe-show`、`etaf-posframe-hide`。

#### Function: etaf-posframe-refresh (&optional panel)

安排 PANEL 按它的 frame 宽度重排，并把 frame 收到渲染内容的高度。

**语义。** PANEL 默认取当前 buffer 的面板。从外部改过大小的 frame 会成为面板宽度，View 因此重排、标题栏按新的列数重画；收高推迟到当前事件与渲染之后，所以从按钮、计时器或主题回调里调用都安全。宿主 frame 尺寸变化时面板本来也会自动收高，只有内容高度变了却没有 Runtime 更新时才需要手动调一次。收高带退避，反复改尺寸的条件不会把 CPU 跑满。

**返回。** PANEL 还活着时返回非 nil。

## 读取已打开的面板

<!-- index: etaf-posframe-panels; etaf-posframe-panel-frame; etaf-posframe-live-p -->

#### Function: etaf-posframe-panels ()

返回活着的面板，最新的在前。

**语义。** 返回的是副本，调用方可以边遍历边隐藏。顺序是最近使用顺序，`etaf-posframe-hide` 取默认面板、`etaf-posframe-cycle` 轮转都按它走。

**返回。** 面板值的列表。

#### Function: etaf-posframe-panel-frame (panel)

返回 PANEL 的子 frame；PANEL 不在了返回 nil。

**语义。** 要读或比较 frame 用它，而不是去翻内部结构，例如按某个面板的位置摆放另一个面板，或记下 window id 用于截图。

**返回。** 一个 frame 或 nil。

**参见。** `etaf-posframe-live-p`。

#### Function: etaf-posframe-live-p (panel)

PANEL 的 frame 还在、Runtime 还挂着时返回非 nil。

**语义。** 面板值比面板活得久：面板隐藏之后继续持有它是安全的，这个谓词回答还有没有东西可以对话。

**返回。** 布尔量。

## 落位

<!-- index: 面板锚点; 面板叠放; 字符格落位 -->

锚点名把面板放在父 frame 或当前窗口的相对位置，偏移锚点按字符格移动，面板就能贴着一行字而不是盖住它。字符格或像素对给出精确位置，跟随指针的面板、恢复记录位置的面板都靠它。`:stack` 读取同一锚点上的活面板并让新面板避开它们，所以同一个键连着开几个面板是叠起来而不是互相覆盖。面板是子 frame，按 frame 像素定位，不参与窗口布局。

## 标题栏与指针

<!-- index: 面板标题栏; 面板主题开关; 面板悬停边框; 面板拖动 -->

带 `:title` 的面板有一整行标题栏：一行高，底色是面板底向文字色微微抬起，下面一条发丝线，右侧在面板的 `:theme` 是某个模式时放着主题开关。标题栏会清掉主题自带的 `header-line` 脸，所以亮色主题不会在它周围画一圈深色描边。设了 `:draggable` 时拖标题栏移动面板，那是 Posframe 自己的拖动，应用不必写代码。

指针不会拿走键盘。面板不打开 buffer 级的 `track-mouse`，因为那样指针一动 Emacs 就会选中指针下的 frame，离开面板就等于把键盘带走了。悬停边框改由一个短计时器读指针：指针下的面板把边框画成强调色，只有点击才移动键盘。已经聚焦的面板保持聚焦边框、不叠悬停色，所以两种状态不会叠在一起。

标题栏里的主题开关就是[按钮与选择控件](ui-buttons-and-choice-controls.md)里的 `etaf-toggle-strip`，一排 `亮`、`随`、`暗`：选中格填主题强调色，其余格保持标题栏底色。点一下就让这块面板在余下的生命周期里用那个模式重画；`:theme` 仍然是调用方传的值，所以这个选择是会话设置，从不写配置。自带调色板的面板没有开关。

## 键盘

<!-- index: 面板按键; 面板焦点; 面板轮转 -->

只有用 `:focusable` 打开的面板才能聚焦，也只有那时它的 View 的按键、文本框与按钮才收得到输入；点面板任意位置把它提到其他面板之上，这一条与是否可聚焦无关。可聚焦面板拿着键盘时 `etaf-posframe-panel-keys` 始终生效，而且只在这三个绑定上压过 View 自己的按键，关闭面板因此不依赖应用记得去绑它。

#### Variable: etaf-posframe-panel-keys

可聚焦面板拿着焦点时始终生效的 keymap。

**语义。** 它在 `q`、`ESC` 与 `C-g` 上关闭面板，也只在这三个绑定上压过 View 自己的按键，其余按键应用可以随便用。View 想抢回这三个键是不可能的：正因如此，面板在任何状态下都能关掉，包括按键处理卡住的 View。

**参见。** `etaf-posframe-cycle`、`etaf-posframe-hide`。

#### Variable: etaf-posframe-hide-inactive

Emacs 不是当前活动应用时隐藏面板，默认 t。

**语义。** 子 frame 本身就是一个窗口，会列出窗口的窗口管理器因此会把它当成目标，点它会激活 Emacs 而不是它背后的应用。另一个应用活动时把面板藏起来，那份窗口列表就干净了；Emacs 重新活动时面板回来。

#### Variable: etaf-posframe-focus-follows-mouse

指针停在面板上时把输入焦点移过去，默认 nil。

**语义。** 只会聚焦可接受键盘的面板。默认把键盘留在用户放的地方，悬停边框因此不需要选项：指针下的面板画强调色边框但不动键盘，移动键盘的是点击。

**参见。** `etaf-posframe-show`、`etaf-posframe-panel-keys`。

## 外观与边框

<!-- index: 面板主题; 面板调色板; 面板边框; 边框强度 -->

面板给它的 View 提供一份 Theme，从父 frame 的默认脸推导，所以画在里面的应用跟随用户的调色板，而不是自带一套颜色。面板 frame 画的是面板底色，标题栏、边框与 View 读同一份调色板，深色 frame 里的亮色面板因此仍然亮着、仍然可读。

#### Function: etaf-posframe-theme (&optional frame mode)

返回从 FRAME 默认脸推导出的 ETAF UI Theme plist。

**参数。** FRAME 默认取选中的 frame。MODE 为 `light` 或 `dark` 时把调色板钉在该模式，nil 则跟随 FRAME。与 frame 自身底色一致的钉法保留那个底色，所以在跟随主题与钉住 frame 自己的模式之间切换时面板颜色不动；不一致的钉法推导出该极性的调色板。模式按 frame 实际底色判断，主题把 `background-mode` 留成旧值也照样读对。

**语义。** 结果带上这个包会用到的 ETAF UI token：`:ui-mode`、`:ui-bg`、`:ui-fg`、`:ui-panel-bg`、`:ui-panel-fg`、`:ui-muted-fg`、`:ui-panel-border`、`:ui-accent`、`:ui-accent-fg`，以及由它们派生的按钮与面板 token。`etaf-posframe-show` 打开的面板已经提供了它，所以这个函数是给自己搭边界的应用用的——第二个子 frame、面板里的一块区域——想要同一份调色板时调它。填充强调色上的文字按强调色的亮度取黑或白，深色主题配浅强调色、亮色主题配深强调色都能读。

**返回。** 一个 Theme plist。

**示例。**

```elisp
(let ((theme (etaf-posframe-theme nil 'dark)))
  (plist-get theme :ui-panel-bg))
```

#### Variable: etaf-posframe-border-width

`:border` 没有 `:width` 时用的 frame 边框宽度，单位像素，0 到 19。

**语义。** 一像素、主题边框色的边框把面板与背后 buffer 分开，让它读作一块浮起来的表面。面板的 `:border` 选项可以逐块覆盖。

#### Variable: etaf-posframe-border-focus-strength

聚焦边框里主题强调色占的比重，0 到 1，默认 0.6。

**语义。** 边框是面板底色向主题 `link` 色染过去的结果：0 就是底色，1 就是强调色本身。面板自己的 `:border` `:focus` 颜色会完全替代这个染色。用染色而不是直接画强调色，一像素描边在两套调色板里都不会读成一个饱和的框。

#### Variable: etaf-posframe-border-hover-strength

悬停边框里主题强调色占的比重，0 到 1，默认 0.3。

**语义。** 悬停的面板没有拿键盘，所以它只比聚焦更弱地暗示强调色。保持它低于 `etaf-posframe-border-focus-strength`，悬停提示、点击确认才能区分；面板自己的 `:border` `:hover` 颜色会完全替代这个染色。

## 尺寸与收高

<!-- index: 面板宽度; 面板高度; 面板等高 -->

#### Variable: etaf-posframe-default-width

没有 `:width` 时新面板的列数，默认 56。

**语义。** 这个值是内容的列数，不是 frame 的列数：边框、内边距与标题栏是加在它外面的。内容画在固定网格上的面板改传 `:width`，要占 frame 一定比例的面板传 `(fraction F)`。

**参见。** `etaf-posframe-show`、`etaf-posframe-default-max-height`。

#### Variable: etaf-posframe-default-max-height

没有 `:height` 时新面板的最大内容行数，默认 30。

**语义。** 面板在这个预算之内把 frame 收到渲染内容的高度，所以短的 View 得到矮面板。必须保持固定高度的面板，比如固定网格的游戏棋盘，传 `:height` 加 `:fill-height`，剩下的地方由底色填满。

**参见。** `etaf-posframe-show`、`etaf-posframe-default-width`。

## 错误与恢复

<!-- index: etaf-posframe-error -->

#### Error: etaf-posframe-error

表示面板输入非法、能力不可用。

**语义。** 这条条件报告选项未知、锚点非法、尺寸非正、`:border` plist 形状不对、或 frame 不是图形 frame。显示失败会先收拾干净再报：View 已卸载、frame 已删除，所以接住错误、换成合法选项重试的调用方是从干净状态开始，而不是漏掉一个 frame。

| 失败 | 结果 |
| --- | --- |
| 选项名未知 | 建 frame 之前就报 `etaf-posframe-error` |
| 锚点或尺寸非法 | 报 `etaf-posframe-error`，不留下打开的东西 |
| Emacs 没有图形 frame | 报 `etaf-posframe-error`；面板需要子 frame |

**参见。** `etaf-posframe-show`、[标准错误](standard-errors.md)。
