# E05.3 房间详情补齐时连封面一起补：任务书

## 背景

- 来源：2026-10-03 上游对照（[W01.1](../../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md) 第 20 行）。上游 pure_live `fa67c637f` 的提交说明原话：“修正垫底缺口：fillFromDetail 只补 nick/avatar/area，不含 cover——而封面恰是用户报告‘不显示’的字段”；pure_live_TV `5bc53016` 修了同一个问题。4.x 的 `LiveRoom.fillFromDetail` 照 3.x 搬过来，同样漏了封面。
- 现象（以抖音为例，其他平台见 README 的列表）：
  1. 关注里有一个没开播的抖音主播，卡片上有封面；
  2. 点进直播间（显示未开播），返回；或者进一个在播房间，详情没给封面；
  3. 观看记录里这一条没有封面（灰底），纯音频时画面上没有封面、后台播放通知没有大图、应用内小窗没画面时没有背景。
- 为什么现在做：第二档，规模小（一行代码加测试）；用户每天看观看记录。
- 已经做过的：E05.2（2026-09-29，`87bc61dfc`）让 `fillFromDetail` 也补标题（A-3，快手房间页没有标题）；`mergeFrom` 的空值保留（UPGRADES X-2）已经保证关注不丢封面。

## 目标和验收

1. `LiveRoom.fillFromDetail` 在自己的封面为空（去掉空白后）时用 `detail.cover`；自己有封面时不变；`detail` 为 `null` 时返回自己（`same`）。
2. 从带封面的卡片进一个详情不给封面的房间，开播成功后观看记录里那一条的封面等于卡片的封面。
3. 同样情况下直播间的 `_room.cover` 是卡片的封面（纯音频封面、小窗背景、通知大图都有图）。
4. 详情给了新封面时，用新封面（不被卡片的旧封面覆盖）。
5. `packages/live_core`、`apps/pure_live` 的测试全部通过；门禁通过。

## 现状（读代码得出，写文件:行）

- 根因：`packages/live_core/lib/src/live_room.dart:652-660`：

  ```dart
  LiveRoom fillFromDetail(LiveRoom? detail) {
    if (detail == null) return this;
    return copyWith(
      title: title.trim().isEmpty && detail.title.trim().isNotEmpty ? detail.title : title,
      area: (area ?? '').isEmpty ? detail.area : area,
      nick: nick.isEmpty ? detail.nick : nick,
      avatar: avatar.isEmpty ? detail.avatar : avatar,
    );
  }
  ```

  没有 `cover`。参数名 `detail` 实际是“进房前手里的那张卡”（调用方传 `requested`）。
- 调用：`apps/pure_live/lib/features/live_play/logic/room_controller.dart:384`（`_room = fetched.withAudienceFallbackFrom(requested).fillFromDetail(requested);`）、`apps/pure_live/lib/features/multiview/logic/multiview_controller.dart:499`。
- 观看记录写入：`room_controller.dart:438-441`（第一次开播成功后 `store.history.record(_room, now: _now())`）→ `packages/live_store/lib/src/rooms.dart:173-183`：`DELETE` 再 `INSERT`，整条用 `_room`，不合并，所以空封面直接写进去。之后的刷新 `HistoryStore.update`（`rooms.dart:204-214`）用 `mergeFrom`，只有刷新带回非空封面时才恢复。
- 用到 `_room.cover` 的地方：`features/live_play/player/player_status.dart:321`、`:351`（纯音频封面 `_DimmedCover`）、`features/live_play/mini/mini_player.dart:498-500`、`features/live_play/logic/background_playback.dart:342-348`（通知 `artUri`）、`shared/rooms/room_cards.dart:91`（观看记录和关注的卡片 `coverUrl`）。
- 详情不给封面的例子：`packages/live_core/lib/src/sites/douyin/douyin_api.dart:485`（没开播时 `''`）、`sites/jdlive/jdlive_api.dart:36-41`（播放回答没有封面）、`sites/kuaishou/kuaishou_api.dart:267`（`stream['poster']`）、`sites/missevan/missevan_api.dart:452`（默认图当作空）。
- 现有测试：`packages/live_core/test/live_room_test.dart:178-195`（“fillFromDetail fills only what is empty”、A-3 标题）；`packages/live_core/test/sites/kuaishou_api_test.dart:1025`、`:1038`；`apps/pure_live/test/features/live_play/live_play_controller_test.dart:58`（“a live room plays the preferred quality, records history and joins the danmaku”，`:72` 断言观看记录只有一条），假平台 `FakeSite` 在 `live_play_support.dart:9`。

## 3.x 基线

- `git show v3.2.11:lib/common/models/live_room.dart` 的 `:899-906`：`fillFromDetail` 只补 `area`、`nick`、`avatar`（用 `_getValueIfEmpty`），也没有封面——3.x 有同样的问题。调用在 `lib/modules/live_play/controllers/live_play_controller.dart:702`、`lib/modules/multiview/multiview_controller.dart:729`。
- 要保留的行为：只补空的、不覆盖详情给的值；`withAudienceFallbackFrom` 在前（人数照旧）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/E-直播平台/E05-平台框架和模型/E05.2-模型扩展/record.md`（A-3 标题补齐）；`packages/live_core/lib/src/live_room.dart:136-160` 的类注释（空值和占位的规则）。

## 范围

- 可以改：`packages/live_core/lib/src/live_room.dart`（只改 `fillFromDetail` 和它的注释）、`packages/live_core/test/live_room_test.dart`、`apps/pure_live/test/features/live_play/live_play_controller_test.dart`（或新建同目录的测试文件）、`live_play_support.dart`（假平台加一个“详情不给封面”的开关）；本文件夹的 `record.md`。
- 不能改：`mergeFrom`、`HistoryStore.record`/`update`、任何平台适配器、界面；`LiveRoom` 的 JSON 字段；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 先写两个改之前会失败的测试；`fillFromDetail` 加 `cover`（`cover.trim().isEmpty ? detail.cover : cover`）；`nick`、`avatar` 的判断统一成 `trim().isEmpty`（写进记录）；注释改成“title, area, name, avatar and cover” | `live_room.dart`、两个测试文件 | 新测试改之前失败、改之后通过；`packages/live_core` 和 `apps/pure_live` 全部测试通过 |

只有一个阶段（规模小）。

## 测试

- 改之前会失败：
  - `packages/live_core/test/live_room_test.dart`：新用例 `'fillFromDetail takes the card cover when the detail has none'`：`LiveRoom(platform: 'douyin', roomId: '1').fillFromDetail(card).cover == 'c'`；`cover: ' '` 时也取卡片的；`cover: 'd'` 时保持 `'d'`。
  - `apps/pure_live/test/features/live_play/live_play_controller_test.dart`：新用例 `'a detail without a cover keeps the card cover in the room and the history'`：卡片 `cover: 'https://img/c.jpg'`，假平台详情 `cover: ''`，进房开播后 `controller.room.cover` 和 `(await store.history.all()).single.cover` 都是卡片的。
- 已有的 `'fillFromDetail fills only what is empty'`（`:178`）补一行封面断言。
- 测试里的定时器至少 1 秒；不访问真实平台（D-017）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 关注一个现在没开播、卡片上有封面的抖音主播，点进去 | 显示未开播；返回 |
| 2. 我的 → 观看记录 | 这一条有封面（和关注卡上的一样） |
| 3. 进一个在播房间，上栏开纯音频 | 画面位置是这个房间的封面加暗色遮罩 |
| 4. 切到后台，下拉通知栏 | 后台播放通知有封面大图 |

## 风险和注意

- `fillFromDetail` 也被多画面用（`multiview_controller.dart:499`），格子没开播时的背景也会因此有封面，属于预期。
- 有的平台卡片封面是截图、详情封面是主播设置的封面；只在详情为空时才用卡片的，不改变“详情优先”。
- 可能冲突的文件：`live_room.dart`（E06.2 不改它）；`live_play_controller_test.dart`（C01.4、E06.2 也会加用例，按行合并即可）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/E05.3` 或本机工作区；提交信息以 `[E05.3]` 开头（英文）；不推 master。
- 提交前：`packages/live_core` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑 `flutter analyze`、全部 `flutter test`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

根因（文件:行）；改了哪些文件；测试数量（改之前失败几个）；`nick`、`avatar` 判断是否改成 `trim()`；要在真机上看的；可能冲突的文件。
