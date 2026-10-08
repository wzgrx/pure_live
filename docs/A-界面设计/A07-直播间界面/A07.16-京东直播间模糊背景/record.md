# A07.16 京东直播间用平台给的模糊图作背景：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `bbd52a2a3` 开始，在 H05.4 之后）
- 设计或说明：[README.md](README.md)（第 1 版定稿，D-003）

## 根因（缺口）

- 平台层 28-3 以后京东房间的 `cover` 只有卡片的 `indexImage`，播放接口的模糊图放在 `JdLiveRoom.background`（`packages/live_core/lib/src/sites/jdlive/jdlive_api.dart:86-88`，`:480`），经 `getRoomDetail` 作为 `LiveRoom.data` 带进直播间（`:593`）。
- 应用里没有任何地方读它：沉浸背景 `apps/pure_live/lib/features/live_play/player/player_view.dart:540-543`（改前）`_cover` 只看 `room.cover`、`room.avatar`；暗封面 `player_status.dart:321`（改前，恢复中、未开播等）只看 `room.cover`，`:357`（改前，纯音频、语音直播）看封面再头像。京东播放接口不给头像，所以没见过卡片的京东房间（从关注进、重启后、粘贴链接）背景只剩渐变。

## 做了什么

- 设计先定稿（README 第 1 版）：c1～c3 按建议，X1、X2 选 A（D-003）；不出图，因为样子都是已确认的 A07.2 c12、C01.2，只换图的地址。
- `apps/pure_live/lib/features/live_play/logic/room_backdrop.dart`：`roomBackdropOf(room, {orAvatar = true})`：`room.data` 是 `JdLiveRoom` 且 `background` 不空时返回它；否则封面；封面空且 `orAvatar` 时头像。
- c1：`player_view.dart` 的 `_cover`（`AmbientBackdrop` 的图：竖屏全屏、横屏全屏两边、宽屏）改用 `roomBackdropOf`。
- c2：`player_status.dart` 的 `AudioOnlyCover`（纯音频、A07.20 的语音直播）用 `roomBackdropOf`；状态层的暗封面（恢复中、未开播、没有流、受限）用 `roomBackdropOf(room, orAvatar: false)`，其他平台和以前一样只用封面。
- c3：卡片、关注、观看历史的封面不动（只改了直播间里取图的地方）。
- 刷新：`LiveRoom.mergeFrom`（`packages/live_core/lib/src/live_room.dart:618`）是 `incoming.data ?? data`，刷新用的 `getRoomDetailForRefresh` 不带 `data` 时保留原来的，背景不会跳回封面（brief 的风险一条，已核对，没改 `room_controller.dart`）。
- 没改：小窗的纯音频封面（`mini/mini_player.dart` `_MiniAudioCover`，不在本任务范围）、换台预览（`room_swipe.dart`）。

## 测试

- 改之前失败、改之后通过（共 8 个新用例，5 个改前失败）：
  - `live_play_layouts_test.dart` 的 `A07.16 JD Live: ...` 组：竖屏全屏没有封面时背景是模糊图；有卡片封面也先用模糊图（宽屏，X2）；横屏全屏两边是模糊图；别的房间仍用封面（守卫）；样本本身有模糊图、没有卡片封面。
  - `live_play_room_test.dart` 的 `A07.16 JD Live: ...` 组：纯音频的封面是模糊图（不是卡片封面）；未开播时状态层的暗封面是模糊图，别的房间仍是封面；`roomBackdropOf` 的顺序（模糊图 → 封面 → 头像，`orAvatar: false` 时为空；卡片的 `JdLiveRoom` 没有模糊图；`data` 不是 `JdLiveRoom`）。
- `JdLiveRoom` 用 `fixtures/jdlive/S02-play-live` 的播放接口样本（`JdLiveApi.play`），不访问网络。图片用新的测试替身 `test/features/live_play/no_images.dart`（`NoImages`：每个地址都失败，不建磁盘缓存、不发请求），两个测试文件的 `_pump` 多了可选的 `images`。

## 真机

待 K90（brief“真机验证”）：

1. 关注一个正在直播的京东直播间，杀掉应用重开，从关注页直接进：竖屏全屏背景是模糊的直播画面（不是纯渐变）。
2. 双击进横屏全屏：两边是同样的模糊背景。
3. 菜单 → 纯音频：中间的暗封面是模糊画面。
4. 从推荐 → 京东进另一个直播间：同样是模糊画面；关注页、观看历史里这张卡片的封面仍是清楚的卡片封面。
5. 进一个哔哩哔哩竖屏直播间：背景和改之前一样（房间封面）。

## K90 复查（2026-10-08，master d34ad44d1）

- 从热门进京东直播间“真我福利直播间”（竖屏流）：画面正常；切纯音频，底色是压暗的紫色模糊图（这个房间背景是紫色），不是渐变 ✓。竖屏全屏、横屏全屏两边、从关注进没看。
- 顺带发现顶栏写“京东直播 · JD Live”，另开 A07.21 并修了。

## K90 复查（2026-10-08 晚，提交 `9e84b6f7b`）

- 第 2 步：热门 → 京东直播进“苏泊尔”（竖屏流），横屏全屏两边是模糊的画面图，不是渐变 ✓。
- 第 1 步：关注这个房间，杀掉应用重开，从关注页进，横屏全屏两边同样是模糊图 ✓（之后取消了关注）。
- 第 4 步：热门列表里的京东卡片封面是清楚的 ✓。
- 第 5 步：哔哩哔哩房间的背景仍是房间封面 ✓（A03.3 复查时的截图）。

结论：通过。
