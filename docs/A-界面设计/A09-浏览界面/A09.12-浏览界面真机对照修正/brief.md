# A09.12 浏览界面真机对照修正：任务书

## 背景

- 来源：2026-10-08 真机对照（V03.4-01～04），截图在 `docs/V-需求和反馈/V03-审查和调研/V03.4-界面真机对照/shots/`。
- 为什么做：第二档；热门是首页常用的标签，首屏就能看到截断的标签和提前出现的按钮。
- 已经做过的：A09.2、A09.4、A09.7、A06.1 c4。

## 目标和验收

1. 热门停在第一个平台时，第三个标签不再被生硬截断，右端渐隐（和分区页一样）。
2. 列表没滚动时右下没有悬浮按钮，滚动后照现有阈值出现。
3. “全部平台”面板在竖屏打开时停在半屏，可以拉到全屏；说明文字一行。
4. 搜索的“全部”芯片和 A09.7 设计一致。
5. 宽屏和电脑不受影响。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/popular/popular_page.dart:152-160`（`_pickPlatform`、`showAdaptivePanel`）、`:170-200`（顶栏：`ScrollableTabBar` + ⌄）、`:225` `PlatformPicker`。
- `packages/live_ui/lib/src/widgets/scrollable_tab_bar.dart:7`（`ScrollableTabBar`，查有没有渐隐参数；分区页 `apps/pure_live/lib/features/areas/areas_page.dart` 怎么用的）。
- `packages/live_ui/lib/src/widgets/jump_buttons.dart:13`、`:39`、`:73-74`。
- `apps/pure_live/lib/features/search/search_scope.dart`（平台条和“全部”芯片）。

## 3.x 基线

- 3.x 悬浮按钮：`git show v3.2.11:lib/common/base/base_page_view_extension.dart:64-100`（滚动后出现）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）；`docs/specs/UI.md`。
2. 本文件夹的 `README.md`；A09.2、A09.4、A09.7 的 README 和 `v4-phone*.jpg`；V03.4 的 `record.md`。

## 范围

- 可以改：上面列的文件和它们的测试；翻译文件里“全部平台”说明那一条（zh、en）。
- 不能改：平台的顺序和显示设置；其他页面的悬浮按钮行为以外的东西。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1～c4 | 见“现状” | 验收 1～5；门禁 `--all` 通过 |

## 测试

- `apps/pure_live/test/features/popular/popular_test.dart`：393 宽时标签条有渐隐；面板初始高度约半屏。
- `packages/live_ui/test/` 的跳转按钮测试：未滚动不显示、滚动后显示。
- `apps/pure_live/test/features/search/search_test.dart`：“全部”芯片的图标。

## 真机验证（K90 或模拟器）

| 步骤 | 期望 |
|---|---|
| 1. 首页 → 热门（第一个平台） | 第三个标签渐隐，没有生硬截断；右下没有悬浮按钮 |
| 2. 往下滑一屏 | 出现回到顶部 / 底部 |
| 3. 点 ⌄ | 面板停在半屏，说明一行 |
| 4. 搜索页 | “全部”芯片是四宫格图标 |

## 风险和注意

- `ScrollJumpButtons` 是共用组件，改“滚动后才出现”会影响所有用到它的列表，逐个看一遍（热门、分区房间、关注、搜索、观看记录）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/A09.12` 或本机工作区；提交信息以 `[A09.12]` 开头（英文）；不推 master。
- 提交前：改过的包跑 format、analyze、测试；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条验收做到没有；改了哪些文件；测试数量；要在真机上看的。
