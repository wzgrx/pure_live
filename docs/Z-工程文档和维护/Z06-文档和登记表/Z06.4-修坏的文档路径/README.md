# Z06.4 修坏的文档路径，补上 docs.py 的检查漏洞和测试

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：docs v2 写作时发现（[Z06 子分类说明](../README.md)的“已知问题”，16 处坏路径的表也在那里）
- 相关：[Z06.1](../Z06.1-docs重写为20组/README.md)（`c613b73f9` 改路径时弄坏的）、[Z02.2](../../Z02-门禁/Z02.2-门禁加文档检查/README.md)（文档检查）、[E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)（`tools/live_cli`）、D-028

## 目标

代码注释里提到的文档都能按路径找到；以后再出现同类错误时门禁能拦住；`docs.py` 自己有测试。

## 3.x 和现状

| 方面 | 现在（文件:行） | 要做到 |
|---|---|---|
| 坏路径 | `c613b73f9` 把旧路径（`docs/4.0.x/`、`docs/ui/`、`docs/ui/compare/`、`docs/ui/tasks/`、`docs/features/records/`、`docs/modules/`）换成新路径时，注释里在 `/` 处换行的路径被换成了 `docs/README.md/` 或 `docs/TASKS.md/` + 下一行的旧文件名，共 16 处，例如 `apps/pure_live/lib/platform/display_mode.dart:140-141` | 每处改成指向新位置的完整路径（一行写完），对照表见 Z06 说明 |
| 检查漏洞 | `tools/docs/docs.py:502` 的 `PATH_RX = (?<![\w/.\-])docs/[\w.\-/、]*[\w\-]` 不跨行；末尾必须是字母数字或 `-`，正则回退掉 `docs/README.md/` 末尾的 `/`，剩下 `docs/README.md` 存在，于是通过（`check_code_paths` `:523-542`） | 路径后面紧跟 `/` 再换行时报“路径在注释里换行”；或先把注释续行拼起来再匹配 |
| 检查范围 | `CODE_DIRS = ['apps', 'packages', 'tools']`、`CODE_FILES` 5 个根文件（`:503-504`）；`fixtures/README.md` 不查，里面的 `docs/adr/0009-fixture-format.md`、`docs/modules/M4.*.md`、`spec/sites/<平台>.md`、`tools/live_cli/...` 都不存在（`fixtures/README.md:3`、`:17`、`:24`、`:32`、`:43`） | `fixtures/` 加进检查；`fixtures/README.md` 的悬空引用改掉（`tools/live_cli` 的部分等 E07.1 定） |
| 章节号 | `apps/pure_live/android/app/build.gradle.kts:9` 写“docs/specs/ENGINEERING.md §9”，ENGINEERING 只有 7 节（原文是 `PLAN.md §9`，讲签名） | 改成指向 Y01（签名和发布） |
| 测试 | `tools/gate/tests/` 只有 `test_check_deps.py`、`test_check_fixtures.py`、`test_check_ui_structure.py` | 加 `test_docs.py` |

## 方案

- c1：`docs.py` 的 `check_code_paths` 识别“路径在 `/` 处断行”：匹配后看原文 `m.end()` 处是不是 `/` 加换行，是就报问题。
- c2：`CODE_DIRS` 加 `fixtures`（只查 `.md`）。
- c3：`tools/gate/tests/test_docs.py`：用临时目录造文件，覆盖链接找不到、代码路径不存在、路径断行、生成区不是最新、文件夹名和登记表不一致。
- c4：改 16 处注释（逐处写成一行完整路径，指向 Z06 说明表里的新位置）和 `build.gradle.kts:9`。
- c5：`fixtures/README.md` 的 `docs/adr/`、`docs/modules/`、`spec/sites/` 引用改成现在的位置（平台说明在 E 组各平台任务、样本规则在 `docs/specs/ENGINEERING.md` 第 3 节）；`tools/live_cli` 的引用按 E07.1 的结论改。

## 验证

- 自动测试：`python3 -m unittest discover -s tools/gate/tests`（门禁 `--all` 的 “gate tests”）。
- c1 做完、c4 之前跑 `python3 tools/docs/docs.py --check` 应该正好报出 16 处；c4 之后 0 个问题。
- 不需要真机。

## 留下的问题

- 代码注释和测试名里大量旧编号（U、M、F、B、P、T 开头，约 2400 处）不在本任务：改到那个文件时顺手换（Z06 说明的已知问题）。
