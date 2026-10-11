# Gallery 与验收面

目录附带三个可运行示例，它们同时是目录的验收面。它们用普通的调用方状态挂载真实组件：浮层示例演练菜单、popover 与对话框，gallery 把整个目录组合成一个工作区，窗口示例经原生手势路径驱动受控窗口。每个函数都挂载到 buffer 并返回它，因此测试或人可以不经菜单直接打开示例。[UI 组件库总论](ui-overview.md)定义组件遵循的契约，前面各章分别定义示例所组合的部件。

## 运行示例

<!-- index: runnable example; acceptance surface; independent mount -->

示例函数同时是交互式与非交互式的：交互调用显示它的 buffer，让用户立刻看到；Lisp 调用只挂载并返回 buffer，这正是批处理验收使用的路径。组件允许时，重开会重置示例自己的应用状态；调用方经卸载 Runtime 或杀死 buffer 释放示例。接受 buffer 名的函数允许同一示例的多个独立挂载，GUI 场景用它在同一次运行里并排开两个窗口。

示例是演示内容而不是框架行为：它们展示的数据只是示意，它们的局部辅助不是目录 API，也不为所组合的组件增加任何契约。它们的价值在于覆盖——每个目录组件族至少出现在其中一个示例里，因此对这三个示例做一遍 GUI 检查会同时触及布局、反馈、导航、输入、数据与浮层。

## 示例函数

<!-- index: etaf-ui-surfaces-open; etaf-ui-gallery-open; etaf-ui-window-resize-open -->

#### Function: etaf-ui-surfaces-open ()

把可运行的浮层组件示例挂载到 `*ETAF UI Surfaces*` 并返回它的 buffer。

**语义。** 交互调用会显示它。重开会重置它的应用状态；卸载 Runtime 或关闭 buffer 即释放。

**返回。** 示例 buffer。

**示例。** `(etaf-ui-surfaces-open)`

#### Function: etaf-ui-gallery-open (&optional buffer-or-name)

挂载整合的目录 Gallery 并返回它的 buffer。

**参数。** BUFFER-OR-NAME 默认 `*ETAF UI Gallery*`；显式名字允许独立挂载。

**语义。** Gallery 在一个组合工作区里演练布局、反馈、导航、输入、数据与浮层组件，其中的动作共享调用方状态与同一个 Theme。交互调用会显示它。卸载 Runtime 或杀死 buffer 即释放；重开重置它的演示状态。

**返回。** 示例 buffer。

**示例。** `(etaf-ui-gallery-open "*Gallery A*")`

#### Function: etaf-ui-window-resize-open (&optional buffer-or-name)

挂载带固定 body 与独立 peer 的受控目录窗口。

**参数。** BUFFER-OR-NAME 默认 `*ETAF Window Resize*`。

**语义。** 标题拖动移动窗口，八个原生手柄缩放它，Shift 锁定手势，再按一次确认，Escape 还原起始矩形；固定 body 裁剪而不是重排段落。交互调用显示 buffer，重开只替换既有的示例挂载。这个示例是 GUI 工作负载而不是性能认证：它在真实组件上演示手势路径，延迟预算用性能工具测量。

**返回。** 示例 buffer。

**示例。** `(etaf-ui-window-resize-open)`

## 错误与恢复

- 示例用普通组件挂载，因此示例里的缺陷表现为组件自己的错误；示例不添加自己的错误条件。
- 重开示例会替换它的挂载而不是在同一 buffer 上叠第二个 Runtime，交互式重试因此是幂等的。
- 释放是显式的：卸载 Runtime 或杀死 buffer。在那之前，示例保持已挂载状态与键绑定。

**参见。** [UI 组件库总论](ui-overview.md#错误与恢复)。
