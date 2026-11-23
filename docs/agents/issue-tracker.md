# Issue 记录方式：本地 Markdown

> **当前状态**：实际工作队列维护在 `docs/remaining-work.md`。`.scratch/` 流程尚未启用；
> 如需启用，先创建目录并按下面的约定开始记录。

本仓库的 issue 和规格说明以 markdown 文件形式存放在 `.scratch/` 目录。

本仓库是 `imacte/yumi` 的本地克隆：issue 只记在本仓库的 `.scratch/` 下，不要向上游 GitHub 仓库提交。

## 约定

- 一个功能一个目录：`.scratch/<feature-slug>/`
- 规格说明放在 `.scratch/<feature-slug>/spec.md`
- 实现类 issue 一个文件一条，放在 `.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号，禁止把所有 ticket 合并成一个文件
- 每条 issue 文件靠近顶部用一行 `Status:` 记录处理状态
- 评论和讨论历史追加到文件末尾 `## Comments` 标题下

## 当技能要求「发布到 issue 记录处」时

在 `.scratch/<feature-slug>/` 下新建文件（目录不存在就创建）。

## 当技能要求「获取相关 ticket」时

读取引用路径对应的文件。用户通常直接给出路径或 issue 编号。

## 寻路（Wayfinding）操作

供 `/wayfinder` 使用。**地图（map）** 是一个文件，每个 ticket 对应一个**子文件**。

- **地图**：`.scratch/<effort>/map.md`（存放 Notes / Decisions-so-far / Fog 正文）。
- **子 ticket**：`.scratch/<effort>/issues/NN-<slug>.md`，从 `01` 编号，正文写问题。用 `Type:` 行记录类型（`research`/`prototype`/`grilling`/`task`）；用 `Status:` 行记录 `claimed`/`resolved`。
- **阻塞**：文件靠近顶部写一行 `Blocked by: NN, NN`。当它列出的每个文件都是 `resolved` 时，该 ticket 解除阻塞。
- **前沿（Frontier）**：扫描 `.scratch/<effort>/issues/`，找出未关闭、未被阻塞、未被认领的文件；编号最小的优先。
- **认领**：开始工作前先把 `Status:` 设为 `claimed` 并保存。
- **解决**：在 `## Answer` 标题下追加答案，把 `Status:` 设为 `resolved`，再把上下文指针（要点 + 链接）追加到 `map.md` 的 Decisions-so-far 里。
