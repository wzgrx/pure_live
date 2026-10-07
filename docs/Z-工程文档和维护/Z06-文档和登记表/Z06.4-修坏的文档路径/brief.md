# Z06.4 修坏的文档路径，补上 docs.py 的检查漏洞和测试：任务书

## 背景

- 来源：docs v2 写作时 X、Y、Z 组代理发现，写在 `docs/Z-工程文档和维护/Z06-文档和登记表/README.md` 的“已知问题”（含 16 处的对照表）。
- 现象：例如 `apps/pure_live/lib/platform/display_mode.dart:140-141` 的注释写 `docs/README.md/` 换行 `research-smoothness-2026-10-02.md 1.4`，按路径找不到文档（应指向 `docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/`）。门禁的“docs”一步没报。
- 为什么现在做：第二档；门禁检查形同虚设，以后改文档目录还会再坏；改动小。
- 已经做过的：`c613b73f9`（Z06.1、Z02.2）加了 `check_code_paths`，同一提交里批量换路径时弄坏了这 16 处。

## 目标和验收

1. `python3 tools/docs/docs.py --check` 能发现“路径在 `/` 处换行”的写法（先只做 c1 时，正好报出 16 处）。
2. 16 处注释和 `apps/pure_live/android/app/build.gradle.kts:9` 改好后，`--check` 0 个问题。
3. `fixtures/README.md` 在检查范围里，里面没有指向不存在文件的路径（`tools/live_cli` 按 E07.1 的结论处理，E07.1 没做时写“见 E07.1”而不是假路径）。
4. `tools/gate/tests/test_docs.py` 存在，`tools/gate/gate.sh --all` 的 “gate tests” 通过。
5. 只改注释、文档和 `tools/`，不改任何代码行为。

## 现状（读代码得出，写文件:行）

- `tools/docs/docs.py:501` `LINK_RX`、`:502` `PATH_RX`、`:503` `CODE_DIRS`、`:504` `CODE_FILES`、`:505` `CODE_EXT`；`check_links` `:508-520`；`check_code_paths` `:523-542`（`PATH_RX.finditer(text)` 对整个文件，`[\w.\-/、]*` 不含换行，末尾 `[\w\-]` 让正则回退掉 `/`）。
- 16 处的位置和该指向的新位置：见 Z06 说明的表（`display_mode.dart:140`、`iptv_import.dart:268`、`account_widgets.dart:17`、`bilibili_qr_login.dart:180`、`account_state.dart:178`、`danmaku_overlay.dart:136`、`shared_data.dart:8`、`tv_room_push_dialog.dart:19`、`tv_nav_item.dart:5`、`search_widgets.dart:18`、`player_dialogs.dart:44`、`chat_benchmark_test.dart:7`、`status_banner.dart:22`、`dialog_buttons_theme.dart:3`、`popups_test.dart:9`、`jdlive.dart:47`）。改之前用 `grep -rn 'docs/README.md/$\|docs/TASKS.md/$' apps packages` 重新确认。
- `fixtures/README.md:3`、`:17`、`:24`、`:32`、`:43`：`docs/adr/0009-fixture-format.md`、`docs/modules/M4.*.md`、`spec/sites/<平台>.md`、`test/fixtures_expected/`、`tools/live_cli/...`。
- `tools/gate/tests/`：已有三个测试文件可以照着写（`unittest`，临时目录）。

## 3.x 基线

- 不涉及（3.x 没有这套文档和检查）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 13 节）。
2. `docs/specs/ENGINEERING.md` 第 3 节（门禁）。
3. 本文件夹的 `README.md`；`docs/Z-工程文档和维护/Z06-文档和登记表/README.md`；`tools/docs/docs.py`；`tools/gate/tests/test_check_ui_structure.py`（测试写法）。

## 范围

- 可以改：`tools/docs/docs.py`、`tools/gate/tests/test_docs.py`（新建）、16 个文件里的那几行注释、`build.gradle.kts:9` 的注释、`fixtures/README.md`、本文件夹的文档和登记表。
- 不能改：任何代码行为（只动注释）；`docs/` 下生成的文件不手改（运行 docs.py）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

| 阶段 | 做什么（README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 检查和测试 | c1 断行检查、c2 `fixtures/` 进检查、c3 测试 | `tools/docs/docs.py`、`tools/gate/tests/test_docs.py` | 测试通过；`--check` 报出 16 处和 `fixtures/README.md` 的问题（这一阶段单独合并时门禁会失败，所以阶段 1 和 2 在同一个分支上做完再合并） |
| 2 改注释 | c4、c5 | 16 个文件的注释、`build.gradle.kts`、`fixtures/README.md` | `--check` 0 个问题；`gate.sh --all` 通过 |

## 测试

- `test_docs.py` 用例：`test_link_missing`、`test_code_path_missing`、`test_code_path_broken_at_slash`（`docs/README.md/` 加换行要报）、`test_code_path_ok_one_line`、`test_generated_block_stale`、`test_folder_name_mismatch`。docs.py 里的 `ROOT`、`DOCS` 要能注入临时目录（现在是模块常量，测试里 `mock.patch` 或改成参数）。
- 改注释不需要新测试；跑一次 `apps/pure_live` 和改到的包的 `dart format`、`dart analyze` 确认没碰坏。

## 真机验证

- 不需要。

## 风险和注意

- `PATH_RX` 改宽了可能误报 Markdown 里合法的写法（例如表格里写目录 `docs/` 结尾），测试里覆盖这些情况。
- `fixtures/README.md` 和 E07.1（取回或重写 `tools/live_cli`）有关，两边同时改时先合并先做完的那个。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/Z06.4` 或本机工作区；提交信息以 `[Z06.4]` 开头（英文）；不推 master。
- 提交前：`python3 -m unittest discover -s tools/gate/tests`；`python3 tools/docs/docs.py --check`；`tools/gate/gate.sh --all`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

检查改了什么、能拦住哪些写法；16 处各改成了什么；`fixtures/README.md` 怎么处理的；测试数量；需要维护者决定的（例如章节号要不要也检查）。
