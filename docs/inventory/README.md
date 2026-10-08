# 清点

把 3.x 的界面、功能点、平台能力逐项列出来，并分到任务，保证不漏。

| 文件 | 内容 | 来源 |
|---|---|---|
| [V3_UI.md](V3_UI.md) | 3.x 的界面清单（按区域） | 手写 |
| [UI.md](UI.md) | 逐项界面：3.x 和 pure_live_TV 的页面、对话框、面板、菜单、覆盖层、提示条，按任务分组 | `tools/ui/inventory.py --items` 生成 |
| [UI_FILES.md](UI_FILES.md) | 每个任务对应的 3.x 和电视端界面文件 | `tools/ui/inventory.py --files` 生成 |
| [FEATURES.md](FEATURES.md) | 功能点 176 项（F-ROOM-01 这类编号）、Windows 专属 14 项、35 个来源的平台能力表、设置项核对 | 手写 |
| [OWNERS.toml](OWNERS.toml) | 归属表：代码文件（路径规则）、设置（按分节默认、个别指定）、35 个来源（播放和弹幕）、原生通道各归哪个子分类 | 手写 |
| [OWNERS.md](OWNERS.md) | 每个子分类管的路径、设置、来源、通道 | `tools/docs/owners.py` 生成 |

说明：

- UI.md 和 UI_FILES.md 由 `tools/ui/inventory.py --items` / `--files` 生成，直接输出新编号（从 `docs/tasks.toml` 的 `old` 字段对照，[Z03.3](../Z-工程文档和维护/Z03-清点和归属/README.md)），开头写着扫描的两个提交。现在的两份扫的是 pure_live_TV `b9d2f739`（X03.1 对照的版本）：`python3 tools/ui/inventory.py --items --tv-ref b9d2f739 > docs/inventory/UI.md`。条目编号（如 A11.3-11）按文件在磁盘上的顺序排，文档里大量引用；要在同一台机器的同一个盘上重新生成，换了机器先对比一遍编号。
- 功能点编号（`F-ROOM-01`）是功能点自己的编号，不是任务编号，保持不变。
- 全项目的归属清点（[Z03.2](../Z-工程文档和维护/Z03-清点和归属/README.md)）：`python3 tools/docs/owners.py` 按 OWNERS.toml 给 `apps/pure_live/lib/`、`packages/*/lib/` 的 Dart 文件、Android 的 Kotlin 文件、Windows 运行器、`tools/` 下的脚本，`Settings.all` 的每个设置，`SiteIds.supported` 的每个来源，每个 `pure_live/…` 通道找归属，并核对 FEATURES.md“依据”“备注”两列里的任务编号都在登记表里；没归属或对不上的逐条打印、退出 1，同时重新生成 OWNERS.md。门禁的 `owners` 一步跑 `--check`（只检查，OWNERS.md 不是最新的也报错）。
  - 加新目录（或者和所在目录归属不同的文件）、新设置分节、新平台、新通道时，在 OWNERS.toml 加一行再跑一次脚本；删文件时一并删掉只管它的规则（一条规则匹配不到文件也报错）。
  - 查归属：`python3 tools/docs/owners.py --who <路径|设置键|来源|通道>`；列一个子分类的全部文件：`--files <子分类>`。
