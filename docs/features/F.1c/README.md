# F.1c 直播间小项：快手 App 跳转、切换直播间刷新、预测返回

- 状态：未开始
- 档位：应该；规模：小
- 功能点：F-RT-05、F-RT-07、F-AND-08（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`features/live_play/buttons/room_menu_button.dart`、`dialogs/room_switcher.dart`、`live_play_page.dart`；`packages/live_core` 快手（只添加 `liveStreamId`）
- 依赖：—
- 来源：M13.14“留给后续”第 6、7 项，M13.17 任务说明第 4、6、8 项
- 评审页：按授权直接开发
- 记录：[records/F.1c.md](../records/F.1c.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-RT-05 | 快手用 `kwai://liveaggregatesquare?liveStreamId=…` 跳 App（`modules/live_play/services/room_external_opener.dart:193`） | `externalRoomTarget`（`room_menu_button.dart:30`）没有快手，只开网页 | 有 `liveStreamId` 时先试 App，打不开用浏览器 |
| F-RT-07 | 切换直播间对话框右上角刷新，调用关注的全部刷新（`modules/live_play/dialogs/play_other.dart:119`） | `room_switcher.dart` 没有刷新 | 加刷新按钮，刷新中转圈，完成后列表更新 |
| F-AND-08 | 直播间接系统的预测返回，全屏和弹层时由应用处理返回（`modules/live_play/services/android_predictive_back_service.dart:7`） | 原生通道 `pure_live/predictive_back` 在（`android/.../MainActivity.kt:74`），Dart 侧没调用 | 照 v3 接上：有全屏、弹层时拦下返回，按返回链处理 |

## 改动清单

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | `live_core` 快手详情带 `liveStreamId`（只添加字段）；菜单加快手 App 跳转 | F-RT-05 |
| c2 | 补上 | 切换直播间加刷新按钮；关注的刷新在 `features/favorite/` 里，功能目录不能互相引用，经共享的 provider 调用（需要时放进 `shared/`） | F-RT-07 |
| c3 | 补上 | 直播间接 `pure_live/predictive_back` | F-AND-08 |

## 测试和验证

- 单元测试：快手跳转地址；刷新按钮调用刷新；返回链在全屏时先退全屏。
- K90：TASKS 第 5 节 5.1 第 5、14 条。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
