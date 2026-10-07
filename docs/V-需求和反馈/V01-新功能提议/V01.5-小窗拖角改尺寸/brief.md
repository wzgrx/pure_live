# V01.5 小窗拖角改尺寸、小窗尺寸设置、画中画里的弹幕随窗口缩放：任务书

## 背景

- 来源：上游 pure_live `f9e03f446`（小窗拖角改尺寸）、`582e355f7`（Windows 画中画尺寸设置）、`b2cca41c7`（画中画弹幕随窗口放大成比例缩放），media_core 的画中画系列；W01.1（2026-10-03 上游对照）列为可借鉴的新功能，按 D-027 进 V01；旧任务清单 T05j.3。
- 现象：应用内小窗手机上固定 220 宽、不能改；Android 画中画两指拉大后弹幕还是小字（缩放上限 1.0）。
- 为什么是第三档：新功能（D-026），不影响现有使用；其中弹幕缩放（c4）是修正，可以提前单独做。
- 已经做过的：A07.8（小窗：三种小窗同一套按钮、应用内小窗尺寸、小窗弹幕不小于 10 号、桌面小窗拉边改大小）；本文件夹 `README.md` 的界面清点和评估初稿（c1～c6）。

## 目标和验收

本任务是**提议**（界面类），按登记的三个阶段：

1. 阶段 1 方案和对比页：
   - 出图（`src/v4-*.html` → `v4-*.jpg`）：手机竖屏首页上小窗的默认大小和拖大后的大小、右下角把手和拖动中的样子、平板上的小窗、设置里的“小窗大小”（三档或滑条两种）、画中画放大前后的弹幕（c4 前后对比）；3.x 还原图一张（`v3-mini.jpg`，照 `resolveAppFloatingSize`）。
   - `page.json`（说明、对比、3.x 的问题 P1～P3、改了什么 c1～c4、每个按钮怎么用、各客户端（手机、平板、电脑应用内；桌面小窗不变）、需要你选的 X1～X3、性能要点：拖动不重建播放器），生成并发布评审页；README 的“各版的经过”“确认的改动”按评审结果写；维护者改“待确认”。
   - 用户确认后：建议的 DECISIONS 条目；目标组任务（A07 界面 c1、c3；C02 逻辑 c1、c2；D03 弹幕 c4）。
2. 阶段 2 拖角改尺寸和尺寸设置：由目标组任务做（c1～c3）。
3. 阶段 3 弹幕缩放：由目标组任务做（c4）；如果维护者按 X3 先单独修了，这一阶段直接算完成。
4. 阶段 2、3 的目标组任务都完成后，本任务改“完成”。

## 现状（读代码得出，写文件:行）

- 应用内小窗：`apps/pure_live/lib/features/live_play/mini/floating_window.dart`（206 行：`FloatingRoomLayer` `:24`、`_FloatingWindow` `:104`，`:138` 用 `inAppMiniSize` 算大小，`:187` 常亮）；按钮层 `mini_player.dart:47` 的 `MiniPlayerSurface`（拖动 `onPanStart/Update/End` `:237-239`，左上回到直播间、右上关闭、中间播放）。
- 大小：`features/live_play/logic/mini_window.dart:98` 的 `inAppMiniBase`（短边 × 0.56，220～360）、`:104` 的 `inAppMiniSize`（横屏画面宽 = base；竖屏画面高 = base × 1.2、宽至少 120）；位置 `:137` 起（拖过的位置或右下角，始终在屏幕内）。
- 小窗弹幕：`mini_window.dart:191` 的 `CompactDanmakuMetrics.resolve`：`scale = (width / 350).clamp(0.65, 1.0)`（`:201`），自动时不小于 10 号（`:203`），行高 `clamp(18.0, 44.0)`（`:208`）；`features/live_play/mini/compact_danmaku.dart:156`、`:184` 读 `pipDanmakuAutoScale`。
- 测试：`apps/pure_live/test/features/live_play/live_play_mini_window_test.dart:284-289`（缩放用例，现在断言宽 360 时 12 号）。
- 桌面小窗：`apps/pure_live/lib/app/desktop/mini_window.dart`（`resolveMiniWindowBounds`，主窗口缩成小窗，能拉边改大小、记住位置；A07.8 c1）——本提议不改它。

## 3.x 基线

- `git show v3.2.11:lib/player/core/player_manager.dart` 的 `:4737` `resolveAppFloatingSize`、`:3010` 调用；`lib/common/utils/compact_danmaku_metrics.dart`（0.65～1.0）。
- 要保留：小窗的入口、按钮、手势（A07.8 确认的）；默认大小不变（“中”= 0.56）；小窗弹幕的设置键（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节界面设计、第 6 节新功能）。
2. `docs/specs/UI.md` 第 3 节；`docs/A-界面设计/A07-直播间界面/A07.8-小窗/README.md`（整份：清点、确认的改动 c1～c11、实现）。
3. 本文件夹 `README.md`；上游 `git show f9e03f446 582e355f7 b2cca41c7`（主仓库的远程 `upstream`）。
4. `tools/ui/mock/README.md`（出图）。

## 范围

- 可以改：本文件夹（README 的设计部分、`src/`、图、`page.json`、`page/`）。
- 不能改：代码；`docs/tasks.toml`、`docs/DECISIONS.md`；A07.8 的设计正文；其他组文档。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 方案和对比页 | 出图、写 `page.json`、发评审页；按回复写“确认的改动”；建议 DECISIONS 和目标组任务 | 本文件夹 | 评审页地址在 README；用户回复后“确认的改动”写好 |
| 2 拖角改尺寸和尺寸设置 | 目标组任务（A07 / C02）做 c1～c3 | — | 目标组任务完成 |
| 3 弹幕缩放 | 已拆出到 [D03.3](../../../D-弹幕/D03-飞行弹幕引擎/D03.3-小窗和画中画的弹幕/README.md)（2026-10-07 登记），本提议不再做 c4 | — | D03.3 完成 |

## 测试

- 本任务不写测试；README“实现和验证”写了实现任务要改和加的测试（`live_play_mini_window_test.dart` 的缩放用例要改；拖角、记住、旋转的用例要加）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 无（提议阶段不上机；实现任务各自写 verify.md） | — |

## 风险和注意

- 拖动改大小时不能重建播放器（R01.1 去掉了浮窗拖动时的透明，避免离屏绘制；改大小也要保持）。
- 拖角和拖动整个小窗的手势冲突：角上 24×24 留给改大小，其余地方拖动位置；触控区域至少 48（A04 的规则），评审时要画清。
- 平板和电脑上小窗最大值：不能盖住大半个首页（建议短边 × 0.9 封顶）。

## 环境和提交

- 出图：`python3 tools/ui/mock/render.py docs/V-需求和反馈/V01-新功能提议/V01.5-小窗拖角改尺寸/src/`；评审页 `python3 tools/ui/mock/page.py docs/V-需求和反馈/V01-新功能提议/V01.5-小窗拖角改尺寸/page.json`。
- 本机工作区或分支 `ai/V01.5`；提交信息以 `[V01.5]` 开头（英文）；不推 master。提交前 `python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：图和 `page.json` 先提交；README 末尾写“停在哪”（哪些图没出、评审页发了没有）。

## 报告（中文，简洁）

评审页地址；X1～X3 的建议；确认的改动（用户回复后）；建议的 DECISIONS 条目和目标组任务；c4 是否建议先单独修。
