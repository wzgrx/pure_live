# A08.9 单击画面优先调出控制层：任务书

## 背景

- 来源：2026-10-08 K90 真机对照（V03.4-07）：弹幕多时单击画面几乎总打开长按弹幕面板，控制层很难调出来。
- 为什么做：第二档；天天用的直播间操作。
- 已经做过的：A08.4（点按、长按画面弹幕打开面板，`5ba728803` 之后）、B09 c1（单击立即响应、双击撤回第一次）。

## 目标和验收

1. 控制层隐藏时，单击画面任何位置（包括点中飞行弹幕）都只调出控制层。
2. 控制层显示时，单击点中弹幕打开长按弹幕面板（弹幕层停住）；没点中照旧隐藏控制层。
3. 长按照旧。双击全屏照旧（第一次单击被撤回）。
4. 暂停时（A07.10）单击只显示或隐藏控制层。
5. 设置里“点按弹幕”开关的说明更新（zh、en）。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/live_play/player/player_view.dart`：`_onTap` `:333-358`（`final undo = hit != null ? _tapMessage(hit) : _tapControls();`）、`_danmakuAt` `:416-440`（`danmakuTapAllowed` `:435`，控制条范围不算）、手势 `:653-665`。
- 设置：`enableDanmakuTapInteraction`（`apps/pure_live/lib/shared/danmaku/danmaku_settings_content.dart:197-213`）。

## 3.x 基线

- 3.x 同样默认开、单击先问弹幕（A08.4 README 的“3.x 的行为”）；本任务是有意改动，按 D-003 维护者选建议 A，已记为 D-038。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）；`docs/specs/UI.md`。
2. 本文件夹的 `README.md`；`docs/A-界面设计/A08-弹幕界面/A08.4-画面弹幕点按和长按/README.md`；`docs/A-界面设计/A07-直播间界面/A07.10-暂停状态/README.md`。

## 范围

- 可以改：`player_view.dart` 的单击处理；翻译文件里那一条说明；测试；本文件夹的文档。
- 不能改：弹幕层的命中算法（D03）；长按；设置键名和默认值（D-018）。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1～c3 | `player_view.dart`、`zh.json`、`en.json`、测试 | 验收 1～5；门禁 `--all` 通过 |

## 测试

- 在 A08.4 的画面点按测试旁边加：`tap on a danmaku with controls hidden shows the controls`、`tap on a danmaku with controls shown opens the panel`；双击全屏的已有测试不能坏。

## 真机验证（K90；先确认手机没被别的会话占用）

| 步骤 | 期望 |
|---|---|
| 1. 哔哩哔哩热门第一个房间（弹幕多），竖屏单击画面 5 次 | 每次都只显示或隐藏控制层 |
| 2. 控制层显示时点一条飞行弹幕 | 弹幕停住、打开面板 |
| 3. 横屏全屏重复 1、2 | 同上 |
| 4. 暂停后单击 | 只显示或隐藏控制层 |

## 风险和注意

- `_onTap` 里 `shownBefore` 在控制层渐隐过程中的值：控制层正在淡出时算“显示”还是“隐藏”，按用户看到的算（淡出开始就算隐藏）。
- 可能冲突：A07.14（双击飞行弹幕面板一闪）也改这一段，先做哪个后做哪个都要重跑对方的测试。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/A08.9` 或本机工作区；提交信息以 `[A08.9]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 format、analyze、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条验收做到没有；改了哪些文件；新决定编号；测试数量；要在真机上看的。
