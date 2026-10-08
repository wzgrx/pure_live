# A08.14 长按弹幕面板加“+1（本地）”：任务书

## 背景

- 来源：V03.6（`docs/V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md`）第 4 节 E3（甲档）、第 5.1 节做法 A；用户 2026-10-09（D-040）。
- 现象：想跟着别人发同一句，只能自己打字。
- 为什么现在做：第二档（V03.6 甲档）；小改动、常用。
- 已经做过的：A08.4（画面弹幕点按和长按打开同一个面板）、A08.8（面板的等级）、D-038（控制层显示时才点中弹幕）。A08.13（V03.6 E2，本地弹幕长按去掉不起作用的“屏蔽关键词”）也改 `message_panel.dart`，**先确认它合并了没有，合并后在它的基础上改**。

## 目标和验收

1. 平台弹幕的长按面板（列表长按、右键，画面点按、长按）在“复制”下面有“+1（本地）”一行和说明“用你的本地身份和样式再发一次，只有你看得到”。
2. 点了：面板关掉，列表里多一条本地弹幕（内容和那条一样，用自己的本地身份和样式），提示“已发送本地弹幕”；“本地弹幕飞过画面”开着时也飞过。
3. 本地弹幕自己的面板里这一行叫“再发一次”。
4. 本地互动关着、或没有本地互动会话的地方（多画面、电视）没有这一行；礼物、醒目留言、系统消息没有这一行。
5. 文字走翻译（zh、en，按键名排序），图标在 `AppIcons`。

## 现状（读代码得出）

- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`：`RoomMessagePanel`（`:50`），复制 `:181-183`，屏蔽此用户 `:193`（`!message.isLocal` 才有），屏蔽关键词 `:207`，第二页 `_KeywordPage`（`:219`）。
- `features/live_play/local_interaction/local_interaction_scope.dart`：`localInteractionAvailable`（`:33`）、`LocalRoomScope`。
- `features/live_play/local_interaction/logic/local_room_session.dart`：`sendChat`（空文字或关着时返回 false）。
- 面板打开的地方：列表 `chat_list.dart:611-619`；画面 `player/player_view.dart` 的 `_openMessage`（`:452`）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/danmaku/danmaku_message_actions.dart`：复制、屏蔽此用户、屏蔽关键词。要保留：这三项和顺序；本地弹幕没有“屏蔽此用户”。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/UI.md` 第 3 节第 6 条（一个动作一个图标）。
3. 本文件夹 `README.md`；A08.4、A08.8、A08.2 的 README；`docs/D-弹幕/D08-本地互动/README.md`。

## 范围

- 可以改：`message_panel.dart`；`packages/live_ui/lib/src/icons/app_icons.dart`（新图标）；翻译文件；对应测试。
- 不能改：本地互动的规则（`logic/`，只调用 `sendChat`）；面板其他行；版本号。

## 方案和阶段

规模小，不分阶段：c1 面板行 → c2、c3、c4 条件 → 测试。

## 测试

- `apps/pure_live/test/features/live_play/`（`live_play_popups_test.dart` 或 `local_interaction_test.dart`）：平台弹幕的面板有这一行、位置在复制下面；点了列表多一条本地弹幕、内容一样、`isLocal`；本地弹幕的面板叫“再发一次”；本地互动关着没有；礼物行的面板没有；画面点按打开的面板也有。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 长按列表里一条平台弹幕，点“+1（本地）” | 面板关，列表多一条本地弹幕，提示“已发送本地弹幕” |
| 2. 全屏横屏，点按飞行弹幕（控制层显示时） | 面板里也有，发出后飞过 |
| 3. 设置里关掉本地互动 | 面板没有这一行 |

## 风险和注意

- 和 A08.13 改同一个文件：先后做，后做的合并前跑一遍面板的全部测试。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`apps/pure_live` 全部 `flutter test`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/A08.14`；提交信息以 `[A08.14]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；新翻译键和图标；测试数量；改了哪些文件；真机上要看的。
