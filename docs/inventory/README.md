# 清点

把 3.x 的界面、功能点、平台能力逐项列出来，并分到任务，保证不漏。

| 文件 | 内容 | 来源 |
|---|---|---|
| [V3_UI.md](V3_UI.md) | 3.x 的界面清单（按区域） | 手写 |
| [UI.md](UI.md) | 逐项界面：3.x 和 pure_live_TV 的页面、对话框、面板、菜单、覆盖层、提示条，按任务分组 | `tools/ui/inventory.py --items` 生成 |
| [UI_FILES.md](UI_FILES.md) | 每个任务对应的 3.x 和电视端界面文件 | `tools/ui/inventory.py --files` 生成 |
| [FEATURES.md](FEATURES.md) | 功能点 176 项（F-ROOM-01 这类编号）、Windows 专属 14 项、35 个来源的平台能力表、设置项核对 | 手写 |

说明：

- UI.md 和 UI_FILES.md 由 `tools/ui/inventory.py --items` / `--files` 生成，直接输出新编号（从 `docs/tasks.toml` 的 `old` 字段对照，[Z03.3](../Z-工程文档和维护/Z03-清点和归属/README.md)），开头写着扫描的两个提交。现在的两份扫的是 pure_live_TV `b9d2f739`（X03.1 对照的版本）：`python3 tools/ui/inventory.py --items --tv-ref b9d2f739 > docs/inventory/UI.md`。条目编号（如 A11.3-11）按文件在磁盘上的顺序排，文档里大量引用；要在同一台机器的同一个盘上重新生成，换了机器先对比一遍编号。
- 功能点编号（`F-ROOM-01`）是功能点自己的编号，不是任务编号，保持不变。
- 全项目的归属清点（代码文件、功能点、设置项、平台、原生插件都归到子分类）是 [Z03.2](../Z-工程文档和维护/Z03-清点和归属/README.md)。
