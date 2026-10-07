# V01.3 按住弹幕让它停住，松手继续：任务书

## 背景

- 来源：上游 flame_barrage `3eddae8`（引擎的 `pauseItemAt`、`resumeAllPaused`）和 pure_live `2d2ad2039`（2026-10-02 “tap-to-hold 按住定住弹幕”），W01.1 列为可借鉴的新功能，按 D-027 进 V01；旧任务清单 T06c.5。
- 现象：飞得快的弹幕看不清；现在长按会打开面板并让全部弹幕停住，按下到面板出来之间那一条还在飞。
- 为什么是第三档：新功能（D-026），规模小，不影响现有功能。
- 已经做过的：A08.4（画面弹幕点按和长按：复制、屏蔽此用户、屏蔽关键词，面板开着全部停住）；本文件夹 `README.md` 的评估初稿（做法 A、B、C，建议 A）。

## 目标和验收

本任务是**提议**：做到“用户能拍板”为止。

1. 评估补完：核对 README 的文件:行；读上游 `2d2ad2039` 的 `video_controller.dart`、`video_controller_panel.dart` 改动（`git show 2d2ad2039`，主仓库的远程 `upstream`）和 flame_barrage 的 `lib/src/core/barrage_engine.dart:439-455`，写清 4.x 引擎里“单条停住”的实现思路（每条弹幕的时钟、同轨碰撞）。
2. 出图或短视频示意：按住时那一条停住、其他照飞；按到面板出来；做法 A、B、C 各一张对比；竖屏和横屏全屏。
3. 评审页：`page.json`（说明、现在和上游的对比、三种做法、需要你选的：做不做 / A、B、C），发布给用户；维护者改“待确认”。
4. 用户回复后：确认 → 建议的 DECISIONS 条目和目标组任务（D03 引擎 c1、A08 手势 c2；和 A07.14 的先后顺序）；否决 → V04 的说明。

## 现状（读代码得出，写文件:行）

- 手势：`apps/pure_live/lib/features/live_play/player/player_view.dart:416-438` 的 `_danmakuAt`（锁定时 `:417` 不响应；看 `Settings.enableDanmakuTapInteraction` 或 `enableDanmakuLongPressInteraction`；`danmakuTapAllowed`（`:830`）排除控制栏区域）；`:443-449` 的 `_openMessage`：`_danmakuHeld = true`，面板关掉才 `false`；`_danmakuHeld` 传给弹幕层的 `held`（`:485`）。
- 弹幕层：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`：`held`（`:200`，“everything stops until they close”）；`messageAt`（`:292`，从上往下找包含这个点的那一条，矩形放大 4 像素）；每条 `_Flying` 有自己的时钟（`_clockOf` `:299`：本地弹幕用 `_free`，平台弹幕用 `_media`）；暂停时（`running == false` 或 `held`）不进新弹幕（`:360`、`:383`）。
- 双击：A07.14（未开始）要修“在飞行弹幕上快速双击时面板一闪再关上”，改的也是 `player_view.dart` 的这段手势。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller.dart` 的 `:262`（`triggerItemAt`）；菜单开着时整个弹幕层暂停（`player_view.dart` 的注释写了“3.x paused the barrage until the sheet closed”）。
- 要保留：长按打开面板、面板开着全部停住（A08.4 确认过、照 3.x）——除非用户选 B 或 C。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节、第 6 节）。
2. `docs/A-界面设计/A08-弹幕界面/A08.4-画面弹幕点按和长按/README.md`（确认的改动和实现）；`docs/A-界面设计/A07-直播间界面/A07.14-双击飞行弹幕面板一闪/README.md`；`docs/D-弹幕/D03-飞行弹幕引擎/README.md`。
3. 本文件夹 `README.md`。

## 范围

- 可以改：本文件夹（README、`src/`、图、`page.json`、`page/`）。
- 不能改：代码；`docs/tasks.toml`、`docs/DECISIONS.md`；其他组文档。

## 方案和阶段

登记表没有阶段（规模小），按两步做：

| 步 | 做什么 | 怎么算做完 |
|---|---|---|
| 1 | 补完评估、出示意图、发评审页 | 评审页地址写进 README“经过”；报告给维护者改“待确认” |
| 2 | 用户回复后按 PROCESS 第 6 节第 3 步处理；实现任务完成后本任务改“完成” | 目标组任务登记好（或改“不做”） |

## 测试

- 本任务不写测试；README“验证”一节已写实现任务要加的测试（`apps/pure_live/test/shared/danmaku_overlay_test.dart` 的单条停住、`player_view` 的手势用例）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 无（提议阶段不上机） | — |

## 风险和注意

- 同轨碰撞：停住的那一条后面同一条轨道的弹幕会追上它，要么穿过（重叠）、要么也停（变成全停），评估里要选一种并在图里画出来。
- 和 A07.14 改同一段手势：先后顺序在报告里建议（建议先做 A07.14）。
- 读屏、键盘没有“按住”，不受影响。

## 环境和提交

- 出图：`tools/ui/mock/README.md`；`python3 tools/ui/mock/render.py docs/V-需求和反馈/V01-新功能提议/V01.3-按住弹幕让它停住/src/`。
- 本机工作区或分支 `ai/V01.3`；提交信息以 `[V01.3]` 开头（英文）；不推 master。提交前 `python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已写的先提交；README 末尾写“停在哪”。

## 报告（中文，简洁）

评估结论（建议的做法、同轨碰撞怎么处理、规模）；评审页地址；需要用户选的问题；建议的 DECISIONS 条目和目标组任务。
