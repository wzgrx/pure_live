# 清点

把 3.x 的界面、功能点、平台能力逐项列出来，并分到任务，保证不漏。

| 文件 | 内容 | 来源 |
|---|---|---|
| [V3_UI.md](V3_UI.md) | 3.x 的界面清单（按区域） | 手写 |
| [UI.md](UI.md) | 逐项界面：3.x 和 pure_live_TV 的页面、对话框、面板、菜单、覆盖层、提示条，按任务分组 | `tools/ui/inventory.py --items` 生成 |
| [UI_FILES.md](UI_FILES.md) | 每个任务对应的 3.x 和电视端界面文件 | `tools/ui/inventory.py --files` 生成 |
| [FEATURES.md](FEATURES.md) | 功能点 176 项（F-ROOM-01 这类编号）、Windows 专属 14 项、35 个来源的平台能力表、设置项核对 | 手写 |

说明：

- UI.md 和 UI_FILES.md 是 2026-10-01 用 `tools/ui/inventory.py` 生成后换成新编号的；脚本本身还输出旧编号，改脚本是 [T00c.3](../T00/T00c/README.md)。在脚本改好之前不要重新生成，否则会变回旧编号。
- 功能点编号（`F-ROOM-01`）是功能点自己的编号，不是任务编号，保持不变。
- 全项目的归属清点（代码文件、功能点、设置项、平台、原生插件都归到子分类）是 [T00c.2](../T00/T00c/README.md)。
