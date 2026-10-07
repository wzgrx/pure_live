# Z06 文档和登记表

`docs/` 这棵树本身：20 组、子分类、任务的结构，唯一的登记表 `docs/tasks.toml`，生成索引和检查文档的 `tools/docs/docs.py`，模板，文档的版本和标签。

## 范围

- 包括：
  - `docs/tasks.toml`（登记表：20 组、107 个子分类、283 个任务）和它的字段规则（PROCESS 第 3.1 节）。
  - `tools/docs/docs.py`：生成 `docs/STATUS.md`、`TASKS.md`、`MAPPING.md` 和每个组、子分类 README 的生成区；`--check` 检查登记表、文件夹名、生成文件、链接、代码里的文档路径（门禁“docs”一步，Z02.2）。
  - `docs/templates/`（10 个：`group.md`、`sub.md`、`design.md`、`feature.md`、`brief.md`、`verify.md`、`record.md`、`review.md`、`page.json`、`README.md`）。
  - 文档的版本：`docs/CHANGELOG.md`、git 标签 `docs-archive-2026-10-02`、`docs-v1`；`docs/README.md` 的目录和编号速查；PROCESS 第 13 节（文档规范）。
- 不包括（归哪里）：
  - 各组、各任务文档的内容 → 各组自己；本子分类只管结构、规则和工具。
  - `docs/specs/`（UI、ENGINEERING、UPGRADES）的内容 → 对应的组（A、Z01/Z02、E）；本子分类只管它们的链接和路径能打开。
  - `docs/inventory/` 的清单 → Z03。
  - 每周、每月、每季度要做的文档维护 → Z07（Z07.2、Z07.3）。

## 现状：做到哪、怎么工作的

- 三次结构变化：
  - **v0**（Z06.1，`c613b73f9`，北京时间 2026-10-03 00:13）：四套平行的文档（模块 M、界面 U、功能 F、4.0.x 的 B/P）合成一个登记表加生成的进度，20 组用 T00～T19 编号；旧文档全文存档在标签 `docs-archive-2026-10-02`。
  - **v1**（Z06.2，`9dfbb424d`，10-03 00:58，标签 `docs-v1`）：20 组改成按优先级排的字母 A～Z（跳过 B、F、M、P、T、U），文件夹“编号-中文名”，界面设计单独成 A 组排第一，新增 V、W、Z07；登记表加 `from`、`to`（D-025、D-028）。
  - **v2**（**正在进行，还没登记任务**）：2026-10-03 01:18 的骨架 `64046b98b` 把组和子分类 README 分成“手写说明 + 生成区”（`<!-- docs:生成开始 -->` 到 `<!-- docs:生成结束 -->`），模板改成 v2（每节写具体内容）；2026-10-07 起各组逐个重写组说明、子分类说明、每个任务的 README 和任务书（`7589916ce` 给 56 个没有文件夹的任务建了文件夹）。维护者合并完各组后会登记 Z06.3；`docs/tasks.toml:1` 和 `docs/README.md` 的版本还写“docs v1”，`CHANGELOG.md` 还没有 v2。
- 怎么工作（`tools/docs/docs.py`，571 行）：
  - `load`（`:98`）读 `tasks.toml`；`Project`（`:144` 起）校验登记表（`validate` `:155`：编号格式、组字母不用 B、F、M、P、T、U、状态和类型的取值、没完成的要写档位、完成和待真机要写日期、暂停要写 `next`、`done` 不超过阶段数、`to` 存在；组和子分类的文件夹名等于“编号-去掉空格括号的标题”；每个任务文件夹都登记了）。
  - 进度：没有阶段的按状态（`STATE_PROGRESS`，未开始 0、设计中 15、待确认 25、已确认 35、开发中 60、暂停 30、受阻 50、待真机 90、完成 100），有阶段的按 `90% × done / 阶段数`；组和全项目按规模加权（小 1、中 2、大 4），“不做”不算（`progress` `:103`、`weight` `:113`）。
  - 生成：`status_md`（`:260`）、`tasks_md`（`:345`）、`mapping_md`（`:369`，含旧文档去向 `OLD_DOCS` `:63`）、`group_md`（`:413`）、`sub_md`（`:438`）；`compose`（`:33`）只替换 README 里生成区之间的内容，上面的手写部分不动（没有手写部分时放一行“组说明还没写”的提示）。
  - 检查：`check_links`（`:508`）、`check_code_paths`（`:523`）；`main`（`:545`）。`--check` 不写文件，有问题退出 1。
- 登记表现状（2026-10-07）：283 个任务：完成 180、未开始 62、待真机 18、已确认 10、不做 6、暂停 3、开发中 2、受阻 2。

## 代码地图

| 文件 | 职责 |
|---|---|
| `docs/tasks.toml` | 唯一的进度来源：`[[group]]`（20）、`[[sub]]`（107，`scope`、`code`）、`[[task]]`（283） |
| `tools/docs/docs.py`（571 行） | 见上；常量 `STATUSES`、`TYPES`、`SIZES`、`TIERS`（`:43-46`）、`RESERVED`（`:80`）、`START`/`END`（`:29-30`）、`LINK_RX`（`:501`）、`PATH_RX`（`:502`）、`CODE_DIRS`、`CODE_FILES`、`CODE_EXT`（`:503-505`） |
| `docs/templates/*.md`、`page.json` | 各类文档的模板（v2，`64046b98b`） |
| `docs/README.md` | 文档入口、20 组的表、目录、编号速查、怎么改 |
| `docs/PROCESS.md` 第 1、3、13 节 | 编号和文件夹、登记表字段、文档规范和版本 |
| `docs/CHANGELOG.md` | 文档版本 v0、v1 |
| `docs/STATUS.md`、`TASKS.md`、`MAPPING.md`、各组和子分类 README 的生成区 | `docs.py` 生成，不手改 |

测试：没有（`tools/gate/tests/` 只有另外三个检查脚本的测试）。

## 3.x 基线

- 3.x 的文档是根目录的几份政策（`git show v3.2.11:MAINTENANCE_POLICY.md`、`BUILD_POLICY.md`、`UPSTREAM_REVIEW_POLICY.md`、`RELEASE_NOTES.md`）和 `docs/` 下一次性的审计报告，没有登记表和进度；不作为基线。
- 4.x 自己的旧文档（2026-10-02 以前的 `docs/PLAN.md`、`docs/ui/`、`docs/features/`、`docs/4.0.x/`、`docs/modules/`）在标签 `docs-archive-2026-10-02`；它们和新文件的对照在 [MAPPING.md](../../MAPPING.md) 最后一节。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| **代码注释里 16 处文档路径是坏的**：`c613b73f9` 把旧路径（`docs/4.0.x/`、`docs/ui/`、`docs/ui/compare/`、`docs/ui/tasks/`、`docs/features/records/`、`docs/modules/`）换成新路径时，路径在注释里换了行的地方被换成了 `docs/README.md/`、`docs/TASKS.md/` + 下一行的旧文件名，例如 `apps/pure_live/lib/platform/display_mode.dart:140-141` 写成 `docs/README.md/` + `research-smoothness-2026-10-02.md 1.4`（原文 `docs/4.0.x/research-smoothness-2026-10-02.md`，现在应指向 `docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研`）。全部 16 处见下表 | 代码注释 | 按注释找不到文档 | 需要一个小任务改注释（建议登记 Z06.4），同时修下一行的检查漏洞 |
| **为什么检查没拦住**：`check_code_paths` 用 `PATH_RX = (?<![\w/.\-])docs/[\w.\-/、]*[\w\-]`（`docs.py:502`）逐段匹配，`[\w.\-/、]*` 不跨换行；`docs/README.md/` 后面就是行尾，最后一个字符必须是字母数字或 `-`，正则回退掉末尾的 `/`，得到 `docs/README.md`——这个文件存在，于是通过。凡是“路径在 `/` 处换行、前半截恰好是存在的文件或目录”的都会漏 | `tools/docs/docs.py:502`、`:523-542` | 检查形同虚设 | 修法建议：匹配到的路径如果后面紧跟 `/` 加换行，就报“路径在注释里换行”（要求路径写在一行里）；或者匹配前把注释续行拼起来。加 `tools/gate/tests/test_docs.py` |
| `fixtures/README.md` 不在检查范围（`CODE_DIRS` 只有 `apps`、`packages`、`tools`，根目录只查 5 个文件），里面的 `docs/adr/0009-fixture-format.md`、`docs/modules/M4.*.md`、`spec/sites/<平台>.md`、`test/fixtures_expected/`、`tools/live_cli/...` 都不存在 | `tools/docs/docs.py:503-504`；`fixtures/README.md:3`、`:17`、`:24`、`:32`、`:43` | 样本说明里的链接全部失效 | `docs.py` 把 `fixtures/` 加进检查；`fixtures/README.md` 的内容由 E07.1（取回 `tools/live_cli`）一起改 |
| `tools/live_cli` 不存在，但 `docs/specs/ENGINEERING.md:52`、`tools/gate/check_deps.py:34`、`:41`、`fixtures/README.md:17`、`:24` 当它存在 | 同左 | 文档和代码不符 | E07.1 已写取回和重写方案；不取回时删掉这些引用 |
| 代码里引用章节号不检查：`apps/pure_live/android/app/build.gradle.kts:9` 写“docs/specs/ENGINEERING.md §9”，ENGINEERING 只有 7 节 | 同左 | 找不到说明 | 和 Z06.4 一起改成指向 Y01；章节号是否要检查由维护者定 |
| `docs/specs/ENGINEERING.md:68` 说上游对照的结论写进“Z 的上游对照”，实际在 W01（例如 `docs/W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/`） | 同左 | 指错地方 | 维护者改 ENGINEERING（根目录 specs 不归各组改） |
| 链接检查也匹配反引号里的代码：在代码格式里写一个右方括号紧跟左圆括号，也会被当成链接去找 | `docs.py:501`、`:508` | 文档里不能用代码形式写这种字符 | 影响小，没有任务 |
| `docs.py` 没有测试 | `tools/gate/tests/` | 改脚本没有保护 | 和上面的检查漏洞一起加 |
| 代码注释和测试名里大量旧编号（U、M、F、B、P、T 开头，粗数约 2400 处，带 U/F/B 编号的文件 333 个） | 例如 `packages/live_store/lib/src/settings/settings.dart` 的 `U.2i`、`F.0a`、`M14.1` | 按注释找文档要先查 MAPPING | V03.3 记为“归 Z03.3、Z06 以后处理”；工作量大，建议只在改到那个文件时顺手换，不专门开任务（需要维护者决定） |
| docs v2 本身没有登记任务；`tasks.toml:1`、`docs/README.md` 还写 v1；`CHANGELOG.md` 没有 v2 | `docs/tasks.toml:1`、`docs/README.md:3`、`docs/CHANGELOG.md` | 版本记录落后 | 维护者合并后登记 Z06.3，写 CHANGELOG v2、打标签 `docs-v2`（D-028） |

16 处坏路径（下一行是旧文件名或旧编号，右列是应该指向的新位置）：

| 位置 | 现在写的 | 应该指向 |
|---|---|---|
| `apps/pure_live/lib/platform/display_mode.dart:140` | `docs/README.md/` + `research-smoothness-2026-10-02.md` | V03.2 流畅度、刷新率、分辨率调研 |
| `apps/pure_live/lib/features/iptv/iptv_import.dart:268` | `docs/TASKS.md/` + `U.9 c10` | A13.1 |
| `apps/pure_live/lib/features/account/account_widgets.dart:17` | `docs/README.md/` + `compare/U.10b c2` | A12.2 |
| `apps/pure_live/lib/features/account/bilibili_qr_login.dart:180` | `docs/TASKS.md/` + `U.10b c11-c13` | A12.2 |
| `apps/pure_live/lib/features/account/account_state.dart:178` | `docs/TASKS.md/` + `U.10b c2` | A12.2 |
| `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart:136` | `docs/TASKS.md/` + `U.2h` | D03.1 |
| `apps/pure_live/lib/app/desktop/shared_data.dart:8` | `docs/TASKS.md/` + `U.13 c14` | A16.1 |
| `apps/pure_live/lib/tv/widgets/tv_room_push_dialog.dart:19` | `docs/TASKS.md/` + `U.15a c15` | A17.1 |
| `apps/pure_live/lib/tv/widgets/tv_nav_item.dart:5` | `docs/TASKS.md/` + `U.15a, parts 3` | A17.1 |
| `apps/pure_live/lib/features/search/search_widgets.dart:18` | `docs/TASKS.md/` + `U.5a c12` | A09.7 |
| `apps/pure_live/lib/features/live_play/dialogs/player_dialogs.dart:44` | `docs/README.md/` + `compare/U.2n c5` | A07.12 |
| `apps/pure_live/test/features/live_play/chat_benchmark_test.dart:7` | `docs/TASKS.md/` + `B08.md` | D04.1 |
| `packages/live_ui/lib/src/widgets/status_banner.dart:22` | `docs/TASKS.md/` + `U.1c c8` | A02.1 |
| `packages/live_ui/lib/src/widgets/dialog_buttons_theme.dart:3` | `docs/README.md/` + `UI_PLAN.md §7` | `docs/specs/UI.md` 第 7 节 |
| `packages/live_ui/test/popups_test.dart:9` | `docs/README.md/` + `tasks/U02.md` | A02.2（同一行前面已经写了 A02.2 的路径，删掉后半截即可） |
| `packages/live_danmaku/lib/src/sites/jdlive.dart:47` | `docs/TASKS.md/` + `M5.24-jdlive.md` | D01.25 |

## 相关决定和规范

- D-014（不使用云端会话；文档改为 20 组，编号部分被 D-025 取代）、D-025（v1：字母编号和“编号-中文名”文件夹，界面设计排第一）、D-028（结构变化升版本并打标签）。
- [PROCESS.md](../../PROCESS.md) 第 1 节（编号和文件夹）、第 3 节（登记表、状态、进度）、第 13 节（只手改哪些、图片、链接、旧编号、决定、文档版本）。

## 测试和验证

- `python3 tools/docs/docs.py --check`（门禁“docs”一步）：有问题退出 1，问题逐行打印。
- `python3 tools/docs/docs.py` 重新生成；生成后 `git diff` 只应该出现在生成区和 STATUS、TASKS、MAPPING。
- 没有自动测试（见已知问题）。

## 路线

- 现在：docs v2 重写（各组分头写，维护者合并后统一运行 `docs.py`、登记 Z06.3、写 CHANGELOG v2、打 `docs-v2` 标签）。
- 之后建议登记（需要维护者决定）：修 16 处坏路径和 `§9`、`docs.py` 的换行漏洞和 `fixtures/` 检查、给 `docs.py` 加测试（一个小任务即可）。
- 季度复查（Z07.3）时核对 `docs/README.md`、PROCESS、CHANGELOG 和实际结构一致。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Z 工程文档和维护](../README.md)。

- 代码：`docs/`、`tools/docs/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Z06.1 | docs 重写为 20 组：登记表、总进度、生成脚本、模板 | 文档 | 完成 | 2026-10-02 | — | [设计或说明](Z06.1-docs重写为20组/README.md) |
| Z06.2 | docs v1：20 组按优先级重排（界面设计第一），字母加中文文件夹，新增需求和反馈、上游借鉴、定期维护 | 文档 | 完成 | 2026-10-03 | — | [设计或说明](Z06.2-docsv1/README.md) |

<!-- docs:生成结束 -->
