# A08.14 长按弹幕面板加“+1（本地）”：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-a4c68d33d49a63222`，提交 `[A08.14] …`；起点 master `1748290b9`（含 A08.13、D08.1）
- 任务书：[brief.md](brief.md)；设计和每条选择的理由：[README.md](README.md)“设计”c1～c4、“定稿的选择”s1～s8（维护者按 D-003 定）；来源：V03.6 第 4 节 E3、第 5.1 节做法 A

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 平台弹幕的面板在“复制”下面有“+1（本地）”和说明 | 做了 | 列表长按、右键，画面点按、长按都是同一个面板（`showRoomMessageActions`），所以都有 |
| 2 点了：面板关、列表多一条本地弹幕、提示“已发送本地弹幕”、开着时飞过 | 做了 | 还写进本地互动记录（D08.1，和输入框发出一样）；超过 40 字截成 40 字（s5） |
| 3 本地弹幕自己的面板里叫“再发一次” | 做了 | 用 D08.1 已有的键 `local_history_again` |
| 4 本地互动关着、没有会话、礼物、醒目留言、系统消息没有 | 做了 | 面板开着时关掉本地互动，这一行也立即消失（s8）；本地礼物也没有（s6） |
| 5 文字走翻译、图标在 `AppIcons` | 做了 | 新图标 `localSendAgain`（`plus_one_rounded`） |

## 根因

- 不是修问题，是新功能：`apps/pure_live/lib/features/live_play/danmaku/message_panel.dart` 的 `RoomMessagePanel._actions` 只有复制、屏蔽此用户、屏蔽关键词（3.x `danmaku_message_actions.dart` 同样）；本地弹幕只能从输入框发出（`LocalRoomSession.sendChat`，`logic/local_room_session.dart`）。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`：`localSendAgainText`（只给聊天行，截到 `LocalCatalog.danmakuLimit`）、`_SendAgainRow`（听 `LocalInteraction` 的开关，点了关面板 → `sendChat` → 提示）、`RoomMessagePanel.session`（找不到面板时弹出的底部面板由 `showRoomMessageActions` 先找好会话传进去）。
- `packages/live_ui/lib/src/icons/app_icons.dart`：`localSendAgain`。
- `apps/pure_live/assets/translations/zh.json`、`en.json`：`local_message_sent`、`local_plus_one`、`local_plus_one_desc`。
- 测试：新文件 `apps/pure_live/test/features/live_play/local_plus_one_test.dart`；`packages/live_ui/test/design_system_test.dart` 对照表加一行。
- 文档：本文件夹（README 的定稿选择、record、verify）；A08 子分类 README“现状”的长按弹幕一条；`docs/tasks.toml`（A08.14）。
- 没改：`logic/` 下的本地互动规则、`chat_list.dart`、面板其他行。

## 新图标、翻译键、门禁基线

- 新图标：`AppIcons.localSendAgain`（`Icons.plus_one_rounded`），用在面板这一行。
- 新翻译键（zh、en，按键名排序）：`local_message_sent`（“已发送本地弹幕”）、`local_plus_one`（“+1（本地）”）、`local_plus_one_desc`（“用你的本地身份和样式再发一次，只有你看得到”）。
- 设置键、默认值没有变。

## 测试

`apps/pure_live/test/features/live_play/local_plus_one_test.dart`（7 个）：

1. 平台弹幕（带 `[doge]`）长按：顺序是复制、+1（本地）、屏蔽此用户、屏蔽关键词；标题、说明、图标；点了面板关、画面上多飞一条、提示“已发送本地弹幕”、列表多一条本地弹幕（内容原样、名字“📺 舰队等级 · 听众 · Pure Live”、本地样式的字号字重位置描边色和本地颜色）、记录里多一条“弹幕”（带平台和房间号）。
2. 自己的本地弹幕：复制下面是“再发一次”（没有“+1（本地）”）；点了列表两条、记录两条。
3. 60 个字（中间一个 emoji）的平台弹幕：发出前 40 个字（emoji 算一个字），记录里也是这 40 个字。
4. 本地互动关着：没有这一行，复制和屏蔽照旧；开着时打开面板、再关掉本地互动：这一行消失。
5. 礼物、醒目留言、通知、只有空白的行、本地礼物：没有这一行。
6. 横屏全屏，用画面点按打开面板的同一个入口（`openMessage`）：右侧 360 的面板里有，点了飞过画面，仍在全屏。
7. 面板不在直播间页面里（多画面、电视的情况：路由在应用的导航器下，没有 `LocalRoomScope`）：没有这一行。

- 跑过：`apps/pure_live/test/features/live_play/` 全部（475 个）、`packages/live_ui/test/design_system_test.dart` 通过。

## 门禁

- 2026-10-09 本机 `bash tools/gate/gate.sh --all`（提交 `77e317e2c`，A08.14 和 D08.2 的全部提交）：`gate: passed (all, 14 members)`。

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包），逐条见 [verify.md](verify.md)，重点：

1. 竖屏长按一条平台弹幕：复制下面是“+1（本地）”和说明，点了面板关、列表最下面多一条自己的本地弹幕、画面上飞过、提示“已发送本地弹幕”。
2. 全屏横屏，控制层显示时点按一条飞行弹幕：右侧面板里也有这一行，点了以后仍在全屏、本地弹幕飞过。
3. 长按自己的本地弹幕：这一行叫“再发一次”。
4. 设置里关掉本地互动：面板没有这一行。
5. 带表情的弹幕 +1 后表情是不是照样显示；超过 40 字的弹幕 +1 后只有前 40 字。
