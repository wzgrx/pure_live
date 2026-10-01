# F.2b 画面弹幕点按和长按

- 状态：开发中（2026-10-02，和 U.2h 的 c9 一起做）
- 档位：应该；规模：中
- 功能点：F-DM-13（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`；`features/live_play/player/player_view.dart`；面板 `features/live_play/danmaku/chat_list.dart` 的 `showChatMessageActions`
- 依赖：F.2a
- 来源：M13.14“留给后续”第 5 项、M13.17 任务说明第 3 项；`~/ref/notes/m13_notes.md`“tap/long-press on flying danmaku”
- 评审页：按授权直接开发（面板照 U.2f 已确认的“长按弹幕”，行为照 [U.2h](../../ui/compare/U.2h/README.md) 的 c9）
- 记录：[records/F.2b.md](../records/F.2b.md)（开发后）

## v3 的行为（`~/ref/v3ref`，v3.2.11）

| 行为 | 位置 |
|---|---|
| 每条弹幕按设置带上点按、长按回调（开关关着就没有） | `modules/live_play/widgets/video_player/video_controller.dart:217-220` |
| 画面手势层先挡掉上下控制条范围内的点（控制条显示时），再把点的位置转给弹幕层；命中就不再显示 / 隐藏控制层 | `video_controller_panel.dart:69-84`、`:196-245`；`video_controller.dart:258-263`、`:984-995` |
| 命中后弹幕层暂停，打开“长按弹幕”面板（复制、屏蔽此用户、屏蔽关键词），面板关了继续；长按后 1 秒内的点按不再开第二次 | `video_controller.dart:132-149` |

## v4 现在

- 设置开关有（`enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction`，默认开，同 v3），只有设置面板读（`shared/danmaku/danmaku_settings_content.dart:197-213`）。
- 弹幕层整层 `IgnorePointer`，不记位置（`danmaku_overlay.dart:370`）；画面的点按只切换控制层（`player_view.dart:240-251`、`:389-393`）。
- 弹幕列表的长按面板已有（`features/live_play/danmaku/chat_list.dart:173-195`、`:521`）。

## 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 点、长按画面弹幕没反应 | 弹幕层换成自己的画法（M12.2）时没做命中检测，画面手势层也不问弹幕层 |
| P2 | 面板打开时弹幕照飞 | 弹幕层没有“暂停”（U.2h V9、V10） |

## 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | 弹幕层给出“这个点上是哪条”（按这一帧的位置，照 U.2h 的 c9） | P1 |
| c2 | 补上 | 画面的点按、长按：控制条显示时上下控制条范围不问（照 v3）；开了哪个手势哪个才问弹幕层；没命中照原来（显示 / 隐藏控制层、双击全屏） | P1 |
| c3 | 保留 | 面板用 U.2f 的“长按弹幕”（`showChatMessageActions`），复制、屏蔽此用户、屏蔽关键词和列表长按同一套 | P1 |
| c4 | 补上 | 面板打开期间弹幕层暂停，关了继续（照 U.2h 的 c9） | P2 |

面板留在 `chat_list.dart`，直播间的画面和列表共用一个入口；多画面不在本任务的目录（`features/multiview/`），以后要用时再挪到 `shared/danmaku/`。

## 需要选的

无。

## 测试和验证

- 组件测试：弹幕层按位置命中；开关关时点弹幕只切换控制层；命中后出面板三项、弹幕层暂停、关了继续；控制条范围不命中。
- K90：TASKS 第 5 节 5.2 第 6 条。

## 风险和性能

- 命中检测只在点按时算一次（遍历屏上最多 48 条），平时没有开销。
- 长按手势只在长按开关开着时挂上，免得影响画面的拖动。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比，和 U.2h 一起开发 |
