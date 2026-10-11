# ETAF 参考手册

[English](README.md)

《ETAF 参考手册》记录 ETAF 核心包 ecss、ekp、ebox、etaf、etaf-ui 和 etaf-db 的全部公共接口。它仿照《Emacs Lisp 参考手册》，按子系统和对象组织，为每个公共函数、宏、变量、钩子、错误、组件、Host、属性、样式属性和主题 token 各写一个定义条目，并通过概念和公共接口讲清每个子系统怎样工作。手册有英文和简体中文两个版本。

本仓库包含全书源文件和 `etaf-manual` 包；这个包把全书作为数据读取，供 Emacs 工具和网站构建使用。全书与代码对照检查：签名与包的 Commentary 不符、正文点名了非公共符号、写出的版本号过期、译本与原文结构不一致，或者可运行示例挂载失败时，构建都会失败。

目前书中已有「引言」和「响应式系统」两章，其余各章正在编写。Emacs 内的交互式阅读器和 HTML 版尚未实现。

## 环境要求

Emacs 29.1 或更高版本、ETAF 0.2.1 和 etaf-ui 0.1.0。门禁还会读取 ecss、ekp、ebox、etaf、etaf-ui 和 etaf-db 的检出目录，它们应与本仓库相邻。

## 使用

把仓库根目录连同 ETAF 及其依赖加入 `load-path`，然后加载本包：

```elisp
(require 'etaf-manual)

(plist-get (etaf-manual-definition 'etaf-ref) :chapter)
     ⇒ reactivity
```

阅读某一章，直接打开 `book/en/` 或 `book/zh-CN/` 下的 Markdown 文件。受支持的 API 以 [`etaf-manual.el`](etaf-manual.el) 的 Commentary 为准。

## 文档

- [编写本手册](docs/manual.zh-CN.md)：全书格式、门禁和命令。
- [引言](book/zh-CN/introduction.md)：本书的范围和记法。

## 开发

克隆后运行 `make setup-hooks`。`make book-check` 运行门禁，`make coverage` 列出每个包已有条目的接口数，`make check` 另外运行结构检查、编译、[tests/acceptance.json](tests/acceptance.json) 中的公共场景、API 边界检查和门禁的工具测试。
