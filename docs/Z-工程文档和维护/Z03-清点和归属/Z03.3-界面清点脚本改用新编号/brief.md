# Z03.3 界面清点脚本改用新编号：任务书

## 背景

- 来源：docs v0（`c613b73f9`）和 v1（`9dfbb424d`）直接把 `docs/inventory/UI.md`、`UI_FILES.md` 里的 U 编号替换成了新编号，生成它们的 `tools/ui/inventory.py` 没改（登记时的旧编号 T00c.3）。
- 现象：`python3 tools/ui/inventory.py --items` 输出 `## U.2e`、`| U.2e-01 | …`；清单里任务的顺序是旧顺序（A08.1 在 A07.6 前面，R02.1 夹在 A 组里）；`docs/inventory/README.md` 只好写“在脚本改好之前不要重新生成，否则会变回旧编号”。同时 `~/ref/pure_live_TV` 已经从清点时的 `b9d2f739` 更新到 `37660afc`，现在重新生成会多 8 个电视视频页面文件。
- 为什么现在做：第二档、规模小；电视界面（A17）、以后的界面返工都要用这两份清单，不能重新生成就没法更新。
- 已经做过的：Z03.1（`2707a2869`、`62606ef5d`）写了脚本。

## 目标和验收

1. `inventory.py` 的三种输出（默认、`--files`、`--items`）里任务都是新编号，逐项编号是 `A07.13-08` 这种形式。
2. 任务按新编号排序（组字母、子分类、序号）。
3. 输出开头写明扫描的 3.x 提交和电视版提交；`--tv-ref <提交>` 能指定电视版的提交（不改 `~/ref/pure_live_TV` 的工作区）。
4. 用和现在一样的电视版提交重新生成的 UI.md、UI_FILES.md，和仓库里的文件相比只有顺序不同（diff 写进 `record.md`）。
5. 新测试 `tools/gate/tests/test_inventory.py` 通过；`docs/inventory/README.md` 去掉“不要重新生成”。
6. 电视版最新提交多出的文件列进 `record.md`，交给 A17.6 和维护者决定清单用哪个提交。

## 现状（读代码得出，写文件:行）

- `tools/ui/inventory.py`（241 行）：`V3` 规则表 `:28-78`、`ITEM_TASK` `:82-85`、`TV` `:87-94`，任务写的是 55 个 U 编号；`assign` `:97`；`scan` `:146`；`order` `:183`（正则 `U\.(\d+)([a-z]?)`，新编号会匹配失败抛异常）；`main` `:188`，`--items` 的锚点链接用 `task.lower().replace(".", "")`（`#a071` 这种，新编号同样适用）。
- 编号对照：`docs/tasks.toml` 的 `old` 字段，55 个 U 编号各对应一个任务：`U.1a` → A01.2、`U.1c` → A02.1、`U.1d` → A02.2、`U.2a`～`U.2k` → A07.1、A07.2、A07.4、A07.5、A08.1、A07.6、A07.7、R02.1（`U.2i`）、A07.8、A08.2，`U.3a`～`U.3d` → A06.1、A06.2、A06.4、A06.3，`U.4a`～`U.5c` → A09.1～A09.9，`U.6a`～`U.6e` → A11.1～A11.5，`U.7a`、`U.7b` → A10.1、A10.2，`U.8` → A13.2，`U.9` → A13.1，`U.10a`～`U.11c` → A12.1～A12.6，`U.12a`～`U.12d` → A15.1、A15.2、A09.10、A08.3，`U.13` → A16.1，`U.15a`～`U.15i` → A17.1～A17.9（同样可以在 [MAPPING.md](../../../MAPPING.md) 查到）。
- 默认路径：`--v3 ~/ref/v3ref`（`v3.2.11` 的只读工作区，提交 `f0d64772a`）、`--tv ~/ref/pure_live_TV`（现在 `37660afc`）。
- 2026-10-07 重跑（最新电视版）：357 个界面文件，比 UI_FILES.md 的 349 个多 8 个，例如 `tv:modules/video/pages/archive/video_detail_dialogs.dart`、`tv:modules/video/pages/discover/video_tag_search_page.dart`、`tv:modules/video/pages/playback/widgets/video_info_panel.dart`。
- 没有测试，不在门禁里。

## 3.x 基线

- 不适用（工程任务）；扫描对象就是 `v3.2.11` 的 `lib/`。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 1 节编号、第 4.1 节界面任务的清点、第 13 节旧编号只出现在 MAPPING 和 `old` 里）。
2. 本文件夹的 `README.md`；`docs/Z-工程文档和维护/Z03-清点和归属/README.md`；`docs/inventory/README.md`；`tools/ui/inventory.py`；`tools/docs/docs.py` 的 `load`（读 `tasks.toml` 的写法）。

## 范围

- 可以改：`tools/ui/inventory.py`；新建 `tools/gate/tests/test_inventory.py`；重新生成 `docs/inventory/UI.md`、`UI_FILES.md`；`docs/inventory/README.md`；本文件夹的文档。
- 不能改：`docs/tasks.toml`；`~/ref/pure_live_TV`、`~/ref/v3ref` 的工作区（只读）；A 组任务 README 里的界面清点表（编号如果因为排序变了，列进报告，不要自己改）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 对照表（建议 A：读 `tasks.toml` 的 `old`）、c2 排序、c3 版本和 `--tv-ref`、c5 测试 | `tools/ui/inventory.py`、`tools/gate/tests/test_inventory.py` | 三种输出都是新编号、新顺序；测试通过 |
| 2 | c4 用 `b9d2f739`（如果本机副本里没有这个提交，用 UI_FILES.md 能对上的最近提交）重新生成，diff 只有顺序；再用最新提交生成一份放 scratchpad 比较 | `docs/inventory/UI.md`、`UI_FILES.md`、`docs/inventory/README.md`、`record.md` | 验收 4～6 |

两个阶段可以一次合并。

## 测试

- `tools/gate/tests/test_inventory.py`（`unittest`，不读 `~/ref`）：
  - 用一个临时的 `tasks.toml`（两个任务带 `old`）建对照表，`U.2e` → `A08.1`；
  - 规则表里有一个 `old` 里找不到的编号 → 抛出明确的错误；
  - `order` 对 `A07.6`、`A08.1`、`A17.10`、`R02.1` 排序正确（`A17.10` 在 `A17.9` 后面）；
  - `scan` 在一个临时的 `lib/` 上把文件分到正确的任务、没匹配的进 `missing`。
- 逐项编号的 diff 用脚本比，不手看。

## 真机验证

不适用（工程任务）。

## 风险和注意

- UI.md 的逐项编号（`A07.13-08`）被 A 组任务 README 的界面清点表引用；排序变了不影响逐项编号（编号是每个任务内部的序号），但如果某个任务内的条目顺序变了，编号会变——第 2 阶段的 diff 要专门看“同一任务内的条目顺序没变”。
- 读 `~/ref/pure_live_TV` 指定提交时用 `git -C ~/ref/pure_live_TV show <提交>:<路径>` 或 `git archive`，不要 checkout（那是共用的参考副本）。
- 可能冲突的文件：`docs/inventory/README.md`（Z03.2 第 3 阶段也改）。

## 环境和提交

- 只需要 Python 3.11+（`tomllib`）和本机的 `~/ref/v3ref`、`~/ref/pure_live_TV`。
- 分支 `ai/Z03.3` 或本机工作区；提交信息以 `[Z03.3]` 开头（英文）；不推 master。
- 提交前：`python3 -m unittest discover -s tools/gate/tests`；`python3 tools/ui/inventory.py`（退出码 0）；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

选了 A 还是 B；重新生成的 diff（是否只有顺序）；同一任务内条目顺序有没有变；电视版最新提交多出的文件清单；测试数量；需要维护者决定的（清单基线用哪个电视版提交）。
