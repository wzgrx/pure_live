# Z02.1 搬目录：界面代码按 v3 模块分目录，门禁加“界面结构”检查

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：界面重构计划（旧编号 U.0）：逐个界面照 3.x 重做之前，先让 4.x 的界面代码按 3.x 的模块分目录，一个界面任务只动一个目录；同时用门禁防止目录之间再互相引用、防止功能代码直接写颜色和图标。
- 旧编号：U.0、T00b.1
- 相关：[specs/UI.md](../../../specs/UI.md) 第 5.2 节（界面结构）、[specs/ENGINEERING.md](../../../specs/ENGINEERING.md) 第 7 节（代码规则）；之后的界面任务（A 组）逐个把基线清小；Z03.1（界面清点，同一天）

## 目标

1. `apps/pure_live/lib/pages/*` 和 `lib/home` 搬到 `lib/features/<3.x 的模块名>/`，直播间照 3.x 的 `live_play` 拆成 `logic/`、`layout/`、`player/`、`danmaku/`、`buttons/`、`dialogs/`；测试跟着搬到 `test/features/<功能>/`。行为不变。
2. 门禁多一步“界面结构”：功能目录之间不能引用对方的内部文件；功能代码和电视外壳不直接写颜色和图标；`logic/` 不引 material。已有的违规记进基线，只能减少。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 搬之前（4.x，2026-10-01 上午） | 搬之后（`4e8e9998f`） | 现在 |
|---|---|---|---|---|
| 目录 | `lib/modules/<模块>/`（`live_play`、`favorite`、`settings`……），`lib/common/`、`lib/plugins/` | `lib/pages/<页面>/`、`lib/home/`，直播间平铺在一个目录 | `lib/features/<模块>/`，模块名照 3.x；直播间分 6 个子目录 | 25 个功能目录（`about`～`web_dav`）；`lib/shared/` 放共用部分 |
| 跨目录引用 | 随意（GetX 的 `Get.find` 到处拿） | 随意 | 门禁拦新的；已有 24 条进基线 | 17 条（多是 `home/home_menu.dart`、`home/menu_button.dart`、`version/` 的文件） |
| 直接写的颜色和图标 | 到处 `Colors.*`、`Icons.*`、`Remix.*` | 同左 | 门禁拦新的；已有 891 处、25 个区进基线 | 0（A08.5 的 `10bbcabe1` 清掉最后一个区） |
| `logic/` 引 material | — | — | 不允许（没有基线，当时就是 0） | 0 |

## 结果

- 提交：`4e8e9998f`（2026-10-01，“refactor(app): move pages into features named after v3's modules (U.0)”），188 个文件：144 个改名搬家、40 个修改（引用路径和文档）、4 个新加——`tools/gate/check_ui_structure.py`（86 行）、`tools/gate/tests/test_check_ui_structure.py`（5 个测试）、`tools/gate/ui_baseline.json`、一次性的搬家脚本 `tools/ui/u0_move.py`（127 行，`LIVE` 表写了直播间每个文件去哪个子目录，留作记录，不保证能重跑）。
- 门禁：`tools/gate/gate.sh` 第 115 行 `step "ui structure" python3 tools/gate/check_ui_structure.py`。
- 规则的细节和棘轮（多了报错、少了也报错要求改基线）见[子分类说明](../README.md)“现状”。
- 偏差：无（行为不变，测试只改了路径）。

## 验证

- 自动测试：应用全部 `flutter test` 照旧通过（只改了 `import` 路径）；`tools/gate/tests/test_check_ui_structure.py` 5 个（入口页可引、内部不可引；按区计数、注释不算；`logic/` 不能引 material；棘轮两个方向；干净的树通过）。
- 真机：不适用（工程任务，行为不变；PROCESS 第 2 节“工程”的证据是门禁通过和脚本输出）。

## 留下的问题

- 基线里还有 17 条跨功能引用：`home/home_menu.dart`、`home/menu_button.dart` 被 6 个功能目录引用（首页菜单应该挪进 `lib/shared/`），`version/app_version.dart`、`update_feed.dart`、`update_prompt.dart` 被 `about`、`home`、`remote_receiver` 引用，`areas/areas_common.dart`、`recorder/recorder_texts.dart`、`settings/settings_model.dart` 各被一个目录引用。没有专门的任务，跟着改到这些文件的界面任务顺手挪（A06 首页、A15.2 关于和版本）。
- 代码注释和测试名里还用 `U.0`、`U.2e` 这类旧编号（例如 `check_ui_structure.py:14` 的“when the rule arrived (U.0)”），查文档要先看 [MAPPING.md](../../../MAPPING.md)；Z06 的已知问题里统一记。
