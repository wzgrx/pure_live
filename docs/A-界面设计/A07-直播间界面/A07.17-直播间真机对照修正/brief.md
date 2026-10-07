# A07.17 直播间真机对照修正：任务书

## 背景

- 来源：2026-10-08 K90 真机对照（V03.4-06、09、12），截图在 `docs/V-需求和反馈/V03-审查和调研/V03.4-界面真机对照/shots/`。
- 为什么做：第二档；直播间是最常用的页面，这三处在真机上明显不好用。
- 已经做过的：A07.1、A07.2、A07.5、A08.1、A08.2。

## 目标和验收

1. 信息行在 393 宽（K90 竖屏）和右栏 300 宽里都只有一行，高度固定，和画质、线路按钮垂直居中对齐。
2. 手机横屏（869×400）不全屏时，按评审确认的设计排：弹幕列表能看到至少 5 行。
3. 竖屏流默认“中”高度，弹幕列表至少 5 行；本地弹幕输入框在竖屏流里收成按钮；画面上方没有黑边。
4. 平板和电脑的宽屏分栏（宽度 ≥ 840）不变。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/live_play/layout/room_info_bar.dart`：`RoomInfoBar` `:26`、`_TitleLine` `:90`、`AudienceStrip` `:193-240`（`Wrap`，spacing 14）。
- `apps/pure_live/lib/features/live_play/logic/room_layout.dart:58-70`：`roomWideMinWidth = 840`、`roomCompactMaxHeight = 480`、`roomPageLayout`。
- `apps/pure_live/lib/features/live_play/live_play_page.dart:1087-1110`（`_buildInline` 选布局）、`:913`（`_withSidePanel`）、`:947`（`_withPanelAtBottom`）。
- 竖屏流：`portraitPanelEligible`、`Settings.portraitLayoutMode`、`portraitFullscreenPolicy`（`live_play_page.dart:515-520`）；本地弹幕输入框 `features/live_play/local_interaction/local_composer.dart`（`localComposerCollapseWidth` 180 `:26`、`LocalComposerBelow` `:437`）。

## 3.x 基线

- 3.x 手机横屏不全屏时（`git show v3.2.11:lib/modules/live_play/live_play_page.dart`）怎么排，开工先截一张 3.x 的样子（模拟器装 3.2.11，不碰用户手机上的正式包）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节界面设计、第 5、8、14 节）；`docs/specs/UI.md`。
2. 本文件夹的 `README.md`；A07.1、A07.2、A07.5、A08.2 的 README；V03.4 的 `record.md`。

## 范围

- 可以改：`features/live_play/layout/`、`logic/room_layout.dart`、`live_play_page.dart` 的布局部分、`local_interaction/local_composer.dart` 的收起规则、测试、本任务的设计图和评审页。
- 不能改：宽屏分栏（≥ 840）；全屏的控制层；3.x 设置键（D-018）。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 出 c2 的效果图（手机横屏 869×400，建议 A 和 B 各一张）和 page.json、评审页；c1、c3 直接做 | 本文件夹 `v4-*.jpg`、`page.json`；`room_info_bar.dart`、竖屏流相关文件 | 评审页发出；验收 1、3 |
| 2 | 按评审结果做 c2 | `room_layout.dart`、`live_play_page.dart` | 验收 2、4 |

## 测试

- 布局测试三种尺寸（README“实现和验证”）；信息行用四个数的假房间（`audienceFigures` 返回 3 个 + 时长）。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（K90；先确认手机没被别的会话占用）

| 步骤 | 期望 |
|---|---|
| 1. 哔哩哔哩热门第一个房间 | 信息行一行 |
| 2. 手机横放（自动旋转开） | 按评审确认的排法，弹幕至少 5 行 |
| 3. 抖音竖屏直播 | 弹幕至少 5 行，画面上方没有黑边，输入框是按钮 |

## 风险和注意

- 和 O05.3（退出全屏回竖屏）、A08.9（单击）同在直播间，改到同一个文件时注意合并。
- 手机横屏的排法是新设计，必须先评审再开发（阶段 1）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/A07.17` 或本机工作区；提交信息以 `[A07.17]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 format、analyze、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条验收做到没有；评审结果；改了哪些文件；测试数量；要在真机上看的。
