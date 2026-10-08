# Z03 清点和归属

保证“没有东西被漏掉”：3.x 和 pure_live_TV 的每个界面文件都分到一个界面任务（已做，`tools/ui/inventory.py`），以及 4.x 的每个代码文件、功能点、设置项、平台、原生插件都归到一个子分类（Z03.2，`tools/docs/owners.py`，在门禁里）。

## 范围

- 包括：
  - `tools/ui/inventory.py`：扫描 3.x（`~/ref/v3ref`，即 `v3.2.11`）和 pure_live_TV（`~/ref/pure_live_TV`）的 `lib/`，把界面文件按路径规则分到任务，生成 `docs/inventory/UI.md`（逐项界面）和 `UI_FILES.md`（每个任务的界面文件）。
  - 全项目的归属清点（Z03.2）：4.x 的代码文件、功能点（`docs/inventory/FEATURES.md` 的 176 项）、设置项（218 个）、平台（35 个来源）、原生插件（Android 7 个 Kotlin 文件、14 个方法通道）都归到子分类，没归的报错。
  - `docs/inventory/README.md` 里对这些清单的说明。
- 不包括（归哪里）：
  - `FEATURES.md`、`V3_UI.md` 的内容（手写的功能点和 3.x 界面清单）→ 维护它们的是审查任务（V03.3 核对过 FEATURES.md）；Z03 只管脚本和自动生成的部分。
  - `tools/ui/strings.py`（取 3.x 文件里的中文文字）、`tools/ui/mock/`（效果图）、`tools/ui/export_compare.py`（评审页导出）→ A 组的设计流程（PROCESS 第 4.1 节）。
  - 登记表 `tasks.toml` 本身 → Z06。

## 现状：做到哪、怎么工作的

- `inventory.py` 的工作方式（`tools/ui/inventory.py`，241 行）：
  - “界面文件”= 声明了 widget 类（`WIDGET` 正则，`:17`）或调用了对话框、底部面板、菜单（`DIALOG`、`SHEET`、`MENU`，`:18-20`）的 Dart 文件。
  - 规则表 `V3`（`:28-78`）和 `TV`（`:87-94`）是“路径前缀 → 任务”，第一条匹配的生效；`get/`、`gen/` 跳过；`ITEM_TASK`（`:82-85`）把共用文件里的单个弹窗（3.x `plugins/utils.dart` 的关闭询问）改派到别的任务。
  - 三种输出（`main` `:188`）：默认是每个任务的计数表；`--files` 生成 UI_FILES.md；`--items` 逐项列页面、对话框、底部面板、菜单、覆盖层，名称取附近第一个翻译键的中文（`title_near` `:113`），位置写“文件:行”。有没分到任务的文件时打印 `unassigned:` 并退出 1。
- **编号还是旧的**：规则表里的任务写的是 `U.1a`～`U.15i` 这类界面重构时的旧编号（55 个），排序按旧编号（`order` `:183`）。`docs/inventory/UI.md`、`UI_FILES.md` 是 2026-10-01 生成后，在 docs v0（`c613b73f9`）、v1（`9dfbb424d`）时把编号替换成新编号的，所以文件里的任务顺序还是旧顺序（例如 A08.1 排在 A07.6 前面、R02.1 夹在 A 组中间）。`docs/inventory/README.md` 写明“脚本改好之前不要重新生成”。55 个旧编号在 `tasks.toml` 的 `old` 里都能一对一找到新编号（`U.2i` → R02.1，其余都在 A 组）。
- 现在跑一遍（2026-10-07）：357 个界面文件、179 个页面、123 个对话框、9 个底部面板、12 个菜单，没有未分配的；但 UI_FILES.md 里只有 349 个文件——`~/ref/pure_live_TV` 已经更新到 `37660afc`（X03.1 用的是 `b9d2f739`），多出 8 个电视版的视频页面文件。
- 全项目的归属清点（Z03.2，2026-10-08）：归属表 `docs/inventory/OWNERS.toml`（路径规则 196 条，第一条匹配的生效；设置按 23 个分节给默认、69 个单独指定；35 个来源的播放和弹幕；14 个通道），`tools/docs/owners.py` 核对 667 个代码文件、219 个设置、35 个来源、14 个通道都有归属、FEATURES.md 里写的任务编号都存在，生成 `docs/inventory/OWNERS.md`；门禁的 `owners` 一步跑 `--check`。分法：界面归 A 组、逻辑和数据归功能子分类，先按目录、再按文件写例外。`tasks.toml` 的 `code` 字段还是文字，和归属表不一致的地方列在 [Z03.2 的记录](Z03.2-项目清点脚本/record.md)里，由维护者定。
- 完成度：Z03.1 完成（2026-10-01，`2707a2869` 第一次加脚本和清单，`62606ef5d` 加 `--items` 逐项清单）；Z03.2 完成（2026-10-08）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `tools/ui/inventory.py`（241 行） | 界面清点：`V3`、`TV` 规则表、`ITEM_TASK`、`scan`（`:146`）、`items_of`（`:127`）、三种输出 |
| `tools/ui/strings.py`（29 行） | 列出一个 3.x 文件里用到的翻译键和中文（设计时用，不属本子分类，列出备查） |
| `docs/inventory/UI.md`（692 行，生成后改过编号） | 52 个任务的逐项界面表，编号 `A07.13-08` 这类就是这里的行号 |
| `docs/inventory/UI_FILES.md`（518 行，同上） | 55 个任务各自的 3.x、电视版界面文件 |
| `docs/inventory/FEATURES.md`（413 行，手写） | 176 个功能点、Windows 专属 14 项、35 个来源的平台能力表、218 个设置项核对 |
| `docs/inventory/V3_UI.md`（233 行，手写） | 3.x 的界面清单（按区域） |
| `tools/docs/owners.py` | 归属清点：扫代码文件（`CODE`）、`parse_settings`、`parse_sites`、`find_channels`、`feature_ids`，`Owners.check` 逐条报问题，`markdown` 生成 OWNERS.md；`--check`、`--who`、`--files` |
| `docs/inventory/OWNERS.toml`（手写） | 归属表：`path`、`site`、`channel`、`setting`、`[setting_sections]`，写法见文件开头 |
| `docs/inventory/OWNERS.md`（生成） | 每个子分类管的路径规则、设置、来源、通道 |
| `docs/tasks.toml` 的 `[[sub]]` `code` 字段 | 各子分类管哪些代码（文字说明，和 OWNERS.toml 的差别见 Z03.2 记录） |

测试：`tools/gate/tests/test_owners.py`（19 个，临时目录造的小仓库）；`inventory.py` 的测试见 Z03.3。

## 3.x 基线

- 3.x 没有清点脚本；`tool/` 下有一些一次性审计脚本，`docs/` 下有手写的审计报告（例如 `git show v3.2.11:docs/ISSUE_874_FAVORITES_PORTABLE_BACKUP_AUDIT_2026_09_23.md`）。
- 清点的对象就是 3.x 本身：`v3.2.11` 的 `lib/`（`~/ref/v3ref` 是这个标签的只读工作区）。电视版的基线是 pure_live_TV（AGPL-3.0），X03.1 对照的是 `b9d2f739`。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 脚本输出旧编号（`U.2e` 这类），排序按旧编号 | `tools/ui/inventory.py:28-94`、`:183` | 不能重新生成 UI.md、UI_FILES.md，否则编号变回旧的；现有文件的任务顺序是旧顺序 | Z03.3 |
| `~/ref/pure_live_TV` 比清点时新（`37660afc` 对 `b9d2f739`），重新生成会多 8 个电视视频页面文件 | `~/ref/pure_live_TV` | 重新生成后 A17.6 的清单会变 | Z03.3 里加 `--tv-commit` 或在输出里写明用的提交；新增的文件由 A17.6 确认 |
| `tasks.toml` 的 `code` 字段是文字，和 OWNERS.toml 有出入 | `docs/tasks.toml` 的 `[[sub]]` | 按 `code` 找代码会找到另一个子分类的文件 | 维护者定（Z03.2 记录列了冲突）；以后可以让 `docs.py` 的“代码：”一行从 OWNERS 取 |
| 脚本没有测试、不进门禁 | `tools/ui/inventory.py` | 规则表改坏了只能靠人看输出 | Z03.3 加最小测试；进门禁是 Z03.2 第 3 阶段 |
| 代码注释里的旧编号（`U.2i`、`F.0a`、`M14.1` 等）没有替换 | 例如 `packages/live_store/lib/src/settings/settings.dart` | 按注释找文档要查 MAPPING | V03.3 记为“归 Z03.3、Z06 以后处理”；Z06 已知问题统一记 |

## 相关决定和规范

- D-001（3.x 是基线：清点保证每个 3.x 界面都有任务）；D-025（新编号）；D-029（功能点改“完成”要有真机结果）。
- [PROCESS.md](../../PROCESS.md) 第 4.1 节第 1 步（界面任务先在 UI.md 找逐项界面、在 UI_FILES.md 找文件）；第 13 节（旧编号只出现在 MAPPING 和登记表的 `old` 里）。

## 测试和验证

- 现在：`python3 tools/ui/inventory.py`（默认计数）退出码 0、没有 `unassigned:`。
- Z03.3 之后：重新生成的 UI.md、UI_FILES.md 和现有文件除了顺序和新增的电视文件外没有差别（diff 核对）。
- Z03.2 之后：归属清点进门禁，没归属的代码文件、设置、平台、通道让门禁失败。

## 路线

1. Z03.3（第二档，小）：脚本改用新编号（从 `tasks.toml` 的 `old` 建对照表，或把规则表直接改成新编号）、按新编号排序、输出里写明扫描的 3.x 和电视版提交；重新生成两份清单。
2. Z03.2（第二档，中，三个阶段）：定规则和路径表 → 写脚本 → 接进门禁。可以复用 Z03.3 的“从登记表取编号”的代码。
3. 两者都做完后，`docs/inventory/README.md` 去掉“不要重新生成”的提示。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Z 工程文档和维护](../README.md)。

- 代码：`tools/ui/inventory.py`、`docs/inventory/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Z03.1 | 界面清点脚本：v3 和电视的每个界面文件都分到一个任务 | 工程 | 完成 | 2026-10-01 | 2707a2869 | [设计或说明](Z03.1-界面清点脚本/README.md) |
| Z03.2 | 项目清点脚本：代码文件、功能点、设置项、平台、原生插件都归到子分类，没归的报错 | 工程 | 完成 | 2026-10-08 | — | [设计或说明](Z03.2-项目清点脚本/README.md)、[任务书](Z03.2-项目清点脚本/brief.md)、[记录](Z03.2-项目清点脚本/record.md) |
| Z03.3 | 界面清点脚本改用新编号（现在输出 U 开头的旧编号） | 工程 | 完成 | 2026-10-08 | — | [设计或说明](Z03.3-界面清点脚本改用新编号/README.md)、[任务书](Z03.3-界面清点脚本改用新编号/brief.md)、[记录](Z03.3-界面清点脚本改用新编号/record.md) |

<!-- docs:生成结束 -->
