# E05.3 房间详情补齐时连封面一起补（fillFromDetail 漏了封面，观看记录等处封面变空）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：上游对照 [W01.1](../../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)：pure_live `fa67c637f`（2026-10-01，“修正垫底缺口：fillFromDetail 只补 nick/avatar/area，不含 cover——而封面恰是用户报告‘不显示’的字段”）、pure_live_TV `5bc53016` 修了同一个问题；4.x 的 `fillFromDetail` 是照 3.x 搬的，同样漏了封面
- 旧编号：T02g.3
- 相关：模型 [E05.1](../E05.1-基础模型与接口/README.md)、[E05.2](../E05.2-模型扩展/README.md)（A-3 让 `fillFromDetail` 也补标题）；观看记录 I 组（I06）；关注刷新的合并 `mergeFrom`（UPGRADES X-2）；决定 D-001、D-017
- 任务书：[brief.md](brief.md)

## 目标

从一张卡片（热门、分区、搜索、关注、观看记录）进直播间时，卡片上已经有封面，而有的平台的房间详情不给封面（例如抖音没开播时、京东的播放回答、快手房间页没有 `poster` 时）。现在进房后 `_room` 的封面变成空字符串，随后：

- 观看记录写进去的是这个空封面（`HistoryStore.record` 整条覆盖，不合并），观看记录页那张卡从此没有封面，直到某次刷新带回封面；
- 直播间里用到封面的地方都是空的：纯音频时画面上的封面（`player_status.dart:321`、`:351`）、应用内小窗没画面时的背景（`mini/mini_player.dart:498`）、后台播放通知的大图（`logic/background_playback.dart:342`）。

做完以后：详情没给封面时用进房那张卡的封面补上（和标题、分区、昵称、头像同样的规则：详情有就用详情的，详情为空才用卡片的），以上各处都有封面；详情给了新封面时照旧用新的。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 补齐函数 | `common/models/live_room.dart:899-906` `fillFromDetail`：只补 `area`、`nick`、`avatar` | `packages/live_core/lib/src/live_room.dart:652-660` `fillFromDetail`：补 `title`（A-3，E05.2）、`area`、`nick`、`avatar`，**没有 `cover`** | 加上 `cover`：`cover.trim().isEmpty` 时用 `detail.cover` |
| 直播间进房 | `modules/live_play/controllers/live_play_controller.dart:699-702`：`fetchedRoom.withAudienceFallbackFrom(requestedRoom)` → `fillFromDetail(requestedRoom)` | `apps/pure_live/lib/features/live_play/logic/room_controller.dart:384`：同样的两步 | 不改调用，补齐函数改了就好 |
| 多画面格子 | `modules/multiview/multiview_controller.dart:729`（离线格子） | `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart:499` | 同上 |
| 写观看记录 | 3.x `upsertHistoryRoom` 整条写入 | `room_controller.dart:438-441` 第一次开播成功后 `store.history.record(_room)`；`packages/live_store/lib/src/rooms.dart:173-183` 先删后插，**不合并** | 记录里带上补齐的封面（补齐函数改了就好，不改 `record`） |
| 关注快照 | — | `room_controller.dart:386`、`:790` `follows.update([_room])` 用 `mergeFrom`（`live_room.dart:587`，空封面保留已存的，`rooms.dart:100-116`） | 不变（这里本来就不丢封面） |
| 上游的修法 | — | pure_live `fa67c637f` 在 8 个平台的 `getRoomDetailForRoom` 里各自补 `cover`；4.x 没有 `getRoomDetailForRoom`，所有进房都走 `fillFromDetail` | 在 `fillFromDetail` 一处补，不在各平台补 |

现在已知详情可能不给封面的平台（读代码得出）：抖音没开播时 `douyin_api.dart:485`（`cover: live ? … : ''`）；京东播放回答没有封面 `jdlive_api.dart:36-41`；快手房间页的封面取 `stream['poster']`（`kuaishou_api.dart:267`），没开播时没有；猫耳的默认灰猫图当作空（`missevan_api.dart:153-154`、`:452`）。另有几个平台在适配器里已经用“看到过的卡片”补封面（六间房 `sixroom_api.dart:157`、Steam `steambroadcast_api.dart:239`、百度 `baidulive_api.dart:255`、LOOK `looklive_api.dart:249`、京东 `jdlive_api.dart:126`），不受影响。

## 方案

- c1 `packages/live_core/lib/src/live_room.dart:652-660`：`fillFromDetail` 加一行 `cover: cover.trim().isEmpty ? detail.cover : cover`（和标题一样用 `trim()`，`nick`、`avatar` 现在没用 `trim()`，一起改成同样的判断，写进记录）；文档注释从“Area, name, avatar and title”改为包括封面。
- c2 测试：`packages/live_core/test/live_room_test.dart:178` 的“fillFromDetail fills only what is empty”加封面断言（详情空 → 用卡片的；详情有 → 用详情的；`null` 原样）；`apps/pure_live/test/features/live_play/` 加一个用例：卡片带封面、假平台的详情封面为空，进房后观看记录里那条有封面（改之前失败）。
- 不改：`mergeFrom`、`HistoryStore.record`、各平台适配器。

## 验证

- 自动测试：c2 的两个用例；`packages/live_core` 全部测试（`kuaishou_api_test.dart:1025` 的“进房保留卡片标题”不受影响）。
- 真机：从抖音一个没开播主播的关注卡进直播间，返回后看观看记录那张卡有封面（步骤见 [brief.md](brief.md)“真机验证”）。

## 留下的问题

- 已经被写成空封面的观看记录不会自己恢复，要等这个房间再被刷新（观看记录页下拉刷新，`features/history/history_refresh.dart`）或再进一次；不做数据修复。
- 卡片本身没有封面（例如从链接进房，`requested` 只有身份）时仍然没有封面，这是平台不给，不是这个问题。
