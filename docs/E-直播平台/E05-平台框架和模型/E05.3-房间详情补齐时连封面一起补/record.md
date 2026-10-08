# E05.3 房间详情补齐时连封面一起补：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `820129343` 开始），提交 `[E05.3]`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | `fillFromDetail` 加 `cover`（`cover.trim().isEmpty ? detail.cover : cover`）；`nick`、`avatar` 的判断一起改成 `trim().isEmpty`；注释写明五个字段和封面的原因 |
| c2 | 做了 | `live_room_test.dart` 加 2 个、改 1 个；`live_play_controller_test.dart` 加 2 个 |
| 验收 1～4 | 做了 | 见“测试” |

## 根因

- `packages/live_core/lib/src/live_room.dart:652-660`（改之前）的 `fillFromDetail` 只补标题、分区、昵称、头像，没有封面。直播间进房 `room_controller.dart:384` 用它把进房那张卡补到详情上，详情不给封面（抖音没开播、京东、快手没有 `poster`、猫耳默认图）时 `_room.cover` 是空的，`store.history.record(_room)` 整条写进观看记录；纯音频封面、小窗背景、通知大图也都读 `_room.cover`。3.x（`common/models/live_room.dart:899-906`）同样漏了。

## 改了哪些文件

- `packages/live_core/lib/src/live_room.dart`：`fillFromDetail` 和注释。多画面（`multiview_controller.dart:499`）也走这里，没开播的格子背景因此有封面（预期）。
- 测试：`packages/live_core/test/live_room_test.dart`、`apps/pure_live/test/features/live_play/live_play_controller_test.dart`。假平台不用加开关：`liveRoom()` 的详情本来就没有封面。

## 新设置、翻译键、门禁基线

- 无。

## 测试

- 新增 4 个、改了 1 个；改之前失败 4 个（`fills only what is empty` 的封面断言、`takes the card cover when the detail has none`、`treats a blank name or avatar as missing`、应用的 `a detail without a cover keeps the card cover in the room and the history`）；`a detail with a new cover replaces the card cover` 改之前也通过（验收 4 的保护）。
- `packages/live_core` 全部 3645 个、`apps/pure_live` 全部 912 个通过；format、`dart analyze --fatal-infos` 无问题。

## 真机上要看的

- 见 brief“真机验证”：抖音没开播主播的关注卡进直播间、返回后观看记录那张卡有封面；纯音频时有封面加暗色遮罩；后台通知有封面大图。
- 已经被写成空封面的观看记录不会自己恢复（README“留下的问题”），真机上要换一个没进过的房间看，或先下拉刷新观看记录。
