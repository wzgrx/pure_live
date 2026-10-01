# F.2b 画面弹幕点按和长按

- 状态：未开始
- 档位：应该；规模：中
- 功能点：F-DM-13（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`；长按面板 `features/live_play/danmaku/chat_list.dart` 的 `showChatMessageActions`（多画面也要用，挪到 `shared/danmaku/`）
- 依赖：F.2a
- 来源：M13.14“留给后续”第 5 项、M13.17 任务说明第 3 项；`~/ref/notes/m13_notes.md`“tap/long-press on flying danmaku”
- 评审页：按授权直接开发（面板照 U.2f 已确认的“长按弹幕”）
- 记录：[records/F.2b.md](../records/F.2b.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-DM-13 | 按设置“点按 / 长按”命中画面上飞过的弹幕，打开复制、屏蔽此用户、屏蔽关键词（`video_controller.dart:132`、`:984`）；控制条范围内的点击不命中（UI_PLAN 附录 A 第 2 条） | 设置开关有（`enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction`）；弹幕层没有命中检测；弹幕列表的长按有 | 照 v3：开了哪个手势哪个生效，命中后打开和列表长按同一个面板 |

## 改动清单

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | 弹幕层记下每条弹幕当前位置，给出“这个点上是哪条” | F-DM-13 |
| c2 | 补上 | 直播间画面的点按、长按先问弹幕层；没命中时照原来（显示控制层、双击全屏）；控制条范围不问 | F-DM-13 |
| c3 | 保留 | 面板用 U.2f 的“长按弹幕”（`showChatMessageActions`），挪到 `shared/danmaku/` | F-DM-13 |

## 测试和验证

- 组件测试：开关关时不命中；命中后面板三项；控制条区域不命中；没命中时单击仍切换控制层。
- K90：TASKS 第 5 节 5.2 第 6 条。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
