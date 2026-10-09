# A08.14 长按弹幕面板加“+1（本地）”：用本地身份和样式再发一次

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：界面
- 来源：[V03.6](../../../V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md) 第 3.1 节“点按、长按”、第 4 节 E3、第 5.1 节（做法 A）；用户 2026-10-09“全面加强弹幕系统和本地互动体验”（D-040）
- 相关：长按弹幕面板 [A08.4](../A08.4-画面弹幕点按和长按/README.md)、[A08.8](../A08.8-长按弹幕面板显示等级/README.md)；本地互动 [A08.2](../A08.2-本地互动/README.md)、[D08](../../../D-弹幕/D08-本地互动/README.md)（`LocalRoomSession.sendChat`）；A08.13（V03.6 E2 的本地互动小修，另一个任务，同一个面板）；决定 D-003、D-038、D-040；任务书 [brief.md](brief.md)

## 目标

看到别人的一条弹幕想“跟一句”时，长按它（或在画面上点按、长按它），面板里点“+1（本地）”，就用自己的本地身份和样式把同样的内容发成一条本地弹幕（只有自己看得到），不用再打字。这是哔哩哔哩最常用的互动之一，也把“看弹幕”和“本地互动”连起来。

## 界面清点表

| 编号 | 界面 | 怎么打开 | 布局 |
|---|---|---|---|
| A08.14-01 | 长按弹幕面板的“+1（本地）”一行 | 列表长按 / 右键平台弹幕；画面上点按（控制层显示时，D-038）或长按飞行弹幕 | 竖屏画面下方、横屏和宽屏右侧 360；在“复制”下面 |
| A08.14-02 | 本地弹幕面板的“再发一次”一行 | 长按自己的本地弹幕 | 同上 |
| A08.14-03 | 发出后的提示 | 点了以后 | 短提示“已发送本地弹幕” |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 面板 | `v3.2.11:lib/modules/live_play/widgets/danmaku/danmaku_message_actions.dart`：复制、屏蔽此用户、屏蔽关键词 + `Lv.N` | `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`：第一张卡片、复制（`:181`）、屏蔽此用户（`:193`，本地弹幕没有）、屏蔽关键词（`:207`） | 复制下面加一行 |
| 发本地弹幕 | — | `LocalRoomSession.sendChat(text)`（`features/live_play/local_interaction/logic/local_room_session.dart`），经 `LocalRoomScope` 找到 | 面板调它 |

## 设计（V03.6 第 5.1 节，做法 A，D-003 维护者选 A）

- c1 面板在“复制”下面加一行：图标（`AppIcons` 里新加一个“再发一次 / 复读”的图标）、标题“+1（本地）”、说明“用你的本地身份和样式再发一次，只有你看得到”。点了：关面板 → `sendChat(这条的内容)` → 提示“已发送本地弹幕”（和输入框发出一样立即进列表、按设置飞过）。
- c2 本地互动总开关关着（`localInteractionAvailable` 为假）时没有这一行；直播间没有本地互动会话（多画面、电视）时也没有。
- c3 本地弹幕自己的面板里这一行叫“再发一次”。
- c4 礼物行、醒目留言、系统消息没有这一行（内容不是一句话）；内容只有表情时照样发（表情代码原样）。
- 不选 B（画面上双击弹幕直接 +1）：双击画面是全屏或暂停的手势，会冲突（A07.14 的教训）。

## 定稿的选择（D-003，维护者定，2026-10-09）

c1～c4 照上面的设计做；任务书没写死、开发时定下的几条：

| 编号 | 选择 | 理由 |
|---|---|---|
| s1 | 图标 `AppIcons.localSendAgain` = Material `plus_one_rounded`；“+1（本地）”和“再发一次”用同一个 | 同一个动作一个图标（UI.md 第 3 节第 6 条）；`localReplay`（进房放回）、`localSend`（纸飞机，发出输入框里的字）意思不同，不借用 |
| s2 | 两行用同一句说明“用你的本地身份和样式再发一次，只有你看得到”，标题分别是“+1（本地）”和已有的“再发一次”（`local_history_again`，和 D08.1 记录里的按钮同一个词） | 本地弹幕再发也是用现在的身份和样式（改过样式就是新样式） |
| s3 | 发出走 `LocalRoomSession.sendChat`：和输入框、D08.1 记录里的“再发一次”同一条路——立即进列表、按“本地弹幕在画面上飞过”飞、写一条 `local_events` 记录、画面弹幕关着时第一条照旧提示 | 不另开一条发送路径；逻辑（`logic/`）一行没改 |
| s4 | 提示条“已发送本地弹幕”（新键 `local_message_sent`），经会话的 `toast`（和记录里的“已再发一次”同一个出口） | 面板已经关了，要让人知道发出去了；全屏时提示条在画面中下部 |
| s5 | 超过 40 个字的平台弹幕截成前 40 个字（表情、emoji 各算一个字）再发 | 本地弹幕的上限是 40（A08.13 c3，`LocalCatalog.danmakuLimit`）；输入框粘贴时也是截掉多的，这里照做；不因为太长就不给这一行 |
| s6 | 只给聊天行：`type == chat`、不带礼物、去掉首尾空白后有字；“之前发的”（D08.1 放回的）也是本地弹幕，给“再发一次” | c4；本地礼物的一句话以名字开头（“Pure Live 送出 辣条 ×1”），不是能跟的一句话 |
| s7 | 会话从面板周围的 `LocalRoomScope` 找；没有直播间面板、弹成底部面板时（`showRoomMessageActions` 的退路）在打开的地方先找好传进去 | 多画面、电视没有 `LocalRoomScope`，自然没有这一行（c2） |
| s8 | 面板开着时在别处关掉本地互动，这一行立刻消失（听 `LocalInteraction`） | 和输入框一样跟着开关走 |

## 实现和验证

- 代码：`apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`（`localSendAgainText`、`_SendAgainRow`、`RoomMessagePanel.session`）；`packages/live_ui/lib/src/icons/app_icons.dart`（`localSendAgain`）；翻译 `local_message_sent`、`local_plus_one`、`local_plus_one_desc`。
- 测试：`apps/pure_live/test/features/live_play/local_plus_one_test.dart`（7 个）；`packages/live_ui/test/design_system_test.dart` 对照表。
- 记录：[record.md](record.md)；真机：[verify.md](verify.md)。
