# 领域文档

工程类技能在探索本仓库代码时，应如何读取和使用这里的领域文档。

## 探索之前先读

- 仓库根目录的 **`GLOSSARY.md`**，或者
- 仓库根目录的 **`GLOSSARY-MAP.md`**（如果存在）：它指向每个上下文各自的 `GLOSSARY.md`；只读与当前主题相关的那些。
- **`docs/adr/`**：读与即将改动的区域有关的 ADR。多上下文仓库还要检查 `src/<context>/docs/adr/` 里该上下文自己的决策记录。

如果这些文件不存在，**直接继续，不要提**。不要指出它们缺失，也不要主动建议先创建。`/domain-modeling` 技能（通过 `/grill-with-docs` 和 `/improve-codebase-architecture` 进入）会在真正定下术语或决策时按需创建。

## 文件结构

单上下文仓库（大多数仓库）：

```
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

多上下文仓库（根目录存在 `GLOSSARY-MAP.md`）：

```
/
├── GLOSSARY-MAP.md
├── docs/adr/                          ← 系统级决策
└── src/
    ├── ordering/
    │   ├── GLOSSARY.md
    │   └── docs/adr/                  ← 该上下文的决策
    └── billing/
        ├── GLOSSARY.md
        └── docs/adr/
```

## 使用词表里的术语

输出里提到领域概念时（issue 标题、重构建议、假设、测试名），使用 `GLOSSARY.md` 里定义的说法，不要换成它明确避免的同义词。

如果需要的概念还不在词表里，这是一个信号：要么你在造项目不用的词（重新考虑），要么确实存在缺口（记下来交给 `/domain-modeling`）。

## 指出 ADR 冲突

如果你的输出与已有 ADR 矛盾，明确指出来，不要悄悄覆盖：

> _与 ADR-0007（事件溯源的订单）矛盾，但值得重新讨论，因为……_
