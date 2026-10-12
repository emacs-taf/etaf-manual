# 开发与发布规范

本手册中的各包以一组 colocated Jujutsu 仓库开发，每个仓库一条已发布分支。本章描述一个改动遵循的交付规则：工作怎样被跟踪、一个提交怎样写与检查、怎样到达远端、集成交付点怎样记录、历史怎样检查与恢复。本章不定义接口；它是让 `workspace.json` 里的修订号有意义的流程。

## 一个工作副本一个写者

<!-- index: colocated 仓库; 工作副本; 工作区 -->

每个仓库都是与 Git colocated 的 Jujutsu 仓库。Jujutsu 拥有工作副本：当前提交 `@` 就是工作副本，每条命令都会把文件快照进它，Git 处于分离 `HEAD` 属预期。用 `jj commit <paths> -m "…"` 封口一个提交，它把指名的路径放进一个已完成的 change 并开始一个空的 `@`；指名路径只会封住你自己的改动，所以提交永远不会顺手带走别人未完成的工作。一个工作副本只有一个写者：动手前先跑 `jj st`；当 `@` 里已有不是你做的改动时，只封自己的路径，若两边都改同一个文件先沟通。并行工作用独立的 `jj workspace add <dir>` 检出，绝不用 git worktree。已发布历史是必须尊重的一条例外：`immutable_heads()` 包含远端 bookmark，所以已发布的提交不会被无意重写。

## 提交

<!-- index: conventional commit; Validation 行; breaking change -->

一个提交是一个可解释、可独立评审与回退的改动——一个有内聚性的功能、修复、移动或文档更新，连同它的回归覆盖与文档——不是固定数量的文件。互不相关的改动要拆开，让每个提交都能用于二分。消息遵循 Conventional Commits：`type(scope): concrete imperative English summary`，type 取 `feat`、`fix`、`docs`、`refactor`、`perf`、`test`、`build`、`ci`、`chore` 或 `revert` 之一。标题最多 72 个字符，避免空泛措辞；空行之后，正文解释问题与由此产生的行为或改动原因。`Validation:` 行列出实际运行过的命令与结果，或者说明某项检查为什么没跑。破坏性改动在标题里带 `!`，并在 footer 写 `BREAKING CHANGE:` 说明影响与迁移。生成的 merge 或 revert 消息要改写以遵守同一契约；消息检查器验证的是格式，不是事实。

## 发布前检查

<!-- index: 提交消息检查; 封口树; 快进 -->

发布之前，发布范围里的每个提交都要检查，它产出的树也要检查。在要发布的仓库里，四条检查是：把每个提交的描述写到文件，用 `python3 scripts/check-commit-message.py` 检查；在仓库根运行 `python3 scripts/check-repository.py --staged`，校验 colocated Git 索引所镜像的封口树；运行 `jj log -r '(<range>) & (conflicts() | divergent() | description(exact:""))'`，它必须什么都不打印；确认 `@-..main@<remote>` 为空，于是发布是一次快进。次级 workspace 检出没有 Git 索引，那里的 `--staged` 只接受空的 `@`，改为检查那份封口的工作副本。工作区根的那份检查器默认根为工作区，所以命令要在被检查的子仓库里运行。

## 发布

<!-- index: 远端; bookmark; provider 先行 -->

每个仓库保留两个远端：`aliyun` 是交付远端，`laycat` 是第二个镜像；`origin` 留给将来，保持未配置。发布的分支是 `workspace.json` 记录的 `branch`，当前是 `main`。Jujutsu 不根据 tracking 推导推送远端，所以远端与 bookmark 永远显式指名：`jj bookmark set main -r @-`，然后 `jj git push --remote aliyun -b main`。发布只快进；当远端有本地没有的提交时，把未发布提交 rebase 到远端之上并重跑检查，而不是强推。provider 先提交并发布，再让依赖它接口的 consumer 提交，consumer 消息引用已发布的 provider 提交号而不是本地号。认证或连通性导致推不上去时，提交留在本地并如实报告交付失败；未推送的提交从不被说成已备份到远端。

## 集成交付点

<!-- index: 检查点; 记录的修订 -->

在集成交付点，每个子仓库已发布的 `main` 提交连同运行过的检查一起记录进 `workspace.json`，这正让一组修订号组合可复现。`python3 scripts/workspace.py status` 把仓库 bookmark 与这些记录的修订对比——不是与工作副本对比——所以记录的检查点永远指名已发布提交，绝不是未封口的 `@`。工作区的集成检查在安静的树上、编辑与提交都完成之后运行：测量期间源码变化会把这次运行标为未验证。

## 历史与恢复

<!-- index: 二分; 操作日志; 撤销 -->

两种恢复方式覆盖大多数需要。要找出回归在哪进入，`jj log -p <path>` 显示单个文件的历史，`jj file annotate <path>` 给一行定责，`jj bisect run --range <good>..<bad> -- <command>` 在提交范围上二分；二分会在工作副本上编辑，所以它在独立 workspace 里跑，退出码 125 表示跳过无法测试的修订，而不是标它为坏。要撤销失误，`jj undo` 反转上一次操作，`jj op log` 配合 `jj op restore <operation>` 把仓库恢复到更早的状态；`jj evolog -p -r <rev>` 显示单个 change 自身怎样被重写，这与文件的历史不同。

## 手册与变更记录随代码同行

<!-- index: 文档交付; 变更记录 -->

公共接口的变化连同它的文档一起交付：受影响的章节两种语言同步更新，book 门禁作为包检查的一部分运行，用户可见的变化按 Keep a Changelog 记进变更记录，归在某个发布标题或 `Unreleased` 下。当版本头变化时，手册中同时点名包与版本的段落要更新到一致，因为 book 门禁会把那段与入口文件对比。这条规则让手册始终描述当前代码，而不是某个更早版本的快照。
