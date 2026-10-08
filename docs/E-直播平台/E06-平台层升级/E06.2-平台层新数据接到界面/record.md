# E06.2 平台层新数据接到界面：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区，分支 `worktree-agent-af018d13b17ed503a`（从 master `b9f0e9308` 开始，按任务书从头做）；`472cbc025` 阶段 1、`939759b8f` 阶段 2～3（两个阶段改同一处聊天行，一个提交）、`2e372be42` 阶段 4、`c43d0aec6` 阶段 5、`c51017473` 阶段 6，最后一个提交是本记录和登记表。没有推送，没有合并
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)（G1、G2 的定稿写在 README“定稿”一节）

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 定稿 G1、G2 | 做了 | 按 D-003 取建议 A（维护者授权执行者选），写进 README：G1 是“播放轮播”按钮；G2 照 A08.1，“对方”和“本地”同一个小块，徽章 16 像素 |
| c1 哔哩哔哩轮播 | 做了 | `PictureAction.playCarousel`；`LiveRoomController.playCarousel()` 走 `_startStream`（进房一样先显示“正在进入直播间…”）；直播间和多画面的 `_plan` 都传 `start: resolution.start`；`onDemand` 照旧是 `_room.isRecord`（假）；`isPlayableNow` 没改。**多加了两处**：① 放轮播时 60 秒刷新发现主播开播，就载入直播（不加的话会一直放轮播）；② 多画面除了 `multiview_controller.dart` 还改了 `cell_view.dart`、`multiview_page.dart`（任务书“可以改”里没列，但验收 2 要求“多画面格子同样”，格子上得有按钮）。只对 `carouselPlatforms`（哔哩哔哩）给按钮：YouTube、TikTok 也会报轮播状态，但平台层取不到它们的轮播视频 |
| c2 名字颜色和徽章 | 做了 | 紧凑行名字用 `nameColor ?? color`；卡片行平台给了 `nameColor` 时名字用它，没给照旧（没头像时名字是正文色、圆点是消息色）。徽章用新组件 `ChatBadge`（走应用的图片缓存和请求头，和飞行弹幕的表情同一种取法），加载中、失败都是零大小。`compact_danmaku.dart` **不用改**：D03.3 c2（`2af8aa0ce`）已经把整条消息原样转给小窗，任务书说的 `:109-117` 重建消息那段已经不在了；加了一个测试守住 |
| c3 酷狗 PK | 做了 | `isFromOtherRoom` 的行（紧凑和卡片都有）名字前一个“对方”小块，键 `live-play-chat-other-room`。为了“和本地标签同样的小块”，把 `local_chat_line.dart` 私有的 `_Chip` 改成公开的 `ChatChip` 两处共用（文件不在任务书列表里，改动只是改名和加样式方法） |
| c4 Twitch | 做了 | 直播间 `start()` 对 `LiveSiteCookieRefusals` 订阅，`dispose` 时随其他订阅一起取消；多画面按平台只订阅一次（四个格子只提示一次）。`codecs` 传 `PlatformDeps.videoCodecs`，默认 `engineVideoCodecs = {avc, hevc, av1}` |
| c5 实际清晰度 | 做了 | 和 C01.4 同一规则：`_refreshPlan` 用 `resolveServedPlayQuality`，列表外的档顶替当前那一项，不提示（C01.4 只在进房和用户自己选档时提示）。下一次恢复请求的是现在显示的那一档（原来一直请求打开时那一档）。多画面同样 |
| c6 FC2 | 做了 | 半成品 `Fc2ControlPool` 整段用上（`recipes.dart` 从 `c695f45a1` 起 master 没改过，直接取旧工作区的文件），另加两处：控制连接在池里等的时候自己断了（授权过期、断线）就立刻移出；`of` 改成工厂构造（门禁的代码检查）。`platforms.dart` 用 `fc2LiveSite()`（`late final` 适配器，回调里 `Fc2ControlPool.of(site).adopt`）；应用退出时 `AppServices.close` 关掉池里剩下的 |
| 验收 8 | 做到 | `ui_baseline.json` 没动（`check_ui_structure.py` 通过） |

## 根因

- 轮播不能播：`room_controller.dart:491`（改之前）`!_room.isPlayableNow` 直接进未开播，画面状态 `room_status.dart:301-306` 只有“切换直播间”“刷新”，没有任何入口走 `_startStream`；`_plan`（`:637-641`）、多画面 `_plan`（`multiview_controller.dart:647-648`）不传 `start`，即使播了也从视频开头开始。
- 名字一个颜色、没有徽章：`chat_list.dart:737`（改之前）紧凑行名字只用 `message.color`，卡片行 `:768` 同样；`_tag()`（`:712`）只画本地标签，`nameColor`、`badges` 没人读。
- 分不出对方房间：同上，`isFromOtherRoom` 没人读。
- Cookie 失效没提示：`TwitchSite.cookieRefusals`（`packages/live_core/lib/src/sites/twitch/twitch_site.dart:196`）应用里没有订阅者；编码：`app/platforms.dart:159`（改之前）建 `TwitchSite` 没传 `codecs`。
- 恢复后显示旧档名：`room_controller.dart:668-670`（改之前）`_refreshPlan` 拿到 `resolution` 只做成计划，`appliedQuality` 被丢掉；多画面 `multiview_controller.dart:623` 同样。
- FC2 多开一次控制连接：`app/platforms.dart:185`（改之前）没传 `probeControl`，探测的连接被平台层关掉；而且即使传了，`recipes.dart:105`、`:117`（改之前）按“频道:画质”配对，探测连接是 `auto`，选了具体一档就配不上，打开时只用 `control.playlist`（`:124`）。打开器在 `app/recording.dart:34` 和 `bootstrap.dart:384` 各建一个（录制、播放），所以池按适配器挂（`Expando`），两边共用。

## 改了哪些文件

- `apps/pure_live/lib/shared/rooms/play_quality.dart`：`carouselPlatforms`、`carouselPlayable`。
- `apps/pure_live/lib/features/live_play/logic/room_status.dart`：`PictureAction.playCarousel`，轮播状态的按钮。
- `apps/pure_live/lib/features/live_play/player/player_status.dart`：“播放轮播”按钮。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`playCarousel`、`playingCarousel`、`_carousel`、刷新时轮播让位给直播、`_plan` 传 `start`；订阅 `cookieRefusals`；`_opens`、`_refreshPlan`、`_showServed`。
- `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart`：`playCarousel`、`_play`（从 `assign` 拆出）、`_plan` 传 `start`；按平台订阅 `cookieRefusals`；`_refreshPlan`。
- `apps/pure_live/lib/features/multiview/widgets/cell_view.dart`、`multiview_page.dart`：轮播格子的按钮。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：名字颜色、`ChatBadge`、`chatBadgeImage`、“对方”。
- `apps/pure_live/lib/features/live_play/local_interaction/local_chat_line.dart`：`_Chip` → `ChatChip`。
- `apps/pure_live/lib/app/platforms.dart`：`engineVideoCodecs`、`PlatformDeps.videoCodecs`、`TwitchSite(codecs:)`、`fc2LiveSite()`。
- `apps/pure_live/lib/app/services.dart`：`close()` 关 FC2 池。
- `packages/live_media/lib/src/inputs/recipes.dart`：`Fc2ControlPool`，`Fc2RecipeOpener` 用它。
- 翻译 `zh.json`、`en.json`；文档 `docs/specs/UPGRADES.md`（7 条的状态）、本文件夹 `README.md`、`record.md`，`docs/tasks.toml`。

## 新设置、翻译键、门禁基线

- 新翻译键 3 个（zh、en 都加，按键名排序）：`live_play_play_carousel`（播放轮播 / Play the rerun）、`danmaku_other_room`（对方 / Opponent）、`twitch_cookie_expired`（Twitch 的 Cookie 已失效，已改为匿名观看，请在账号页重新填写 / …）。
- 没有新设置；门禁基线没变。

## 测试

- 新增 25 个，改了 1 个：
  - `apps/pure_live/test/features/live_play/live_play_controller_test.dart`：`a carousel room plays its video from play_time (1-1)`（起点 37 秒、`onDemand` 假、关注里仍不能播、放完接下一段从 5 秒开始、开播后改放直播）；`only a carousel the app can play has the button; a reload is offline again (1-1)`；`B-7: a refused cookie is said once per refusal, and not after the room closed`；`a recovery that switched quality shows the quality now played (11-1)`。
  - `live_play_states_test.dart`：竖屏、横屏全屏各一个“播放轮播”布局测试；改了 `offline, banned, carousel and unknown…`（轮播的按钮变了，加了 YouTube 轮播照旧的断言）。
  - `test/features/live_play/chat_line_marks_test.dart`（新）：17LIVE `S06-live` 第一条评论的名字颜色压过消息色（两种样式）；浅色名字仍 ≥4.5:1、白色退回次要色；三个徽章按顺序、16 高、第二个失败时零大小；没徽章时没有；酷狗 `S09-pk-chat` 对方聊天两种样式都有“对方”。
  - `live_play_mini_window_test.dart`：小窗收到的消息带名字颜色、徽章、来源房间（改之前也通过，D03.3 已经做到，守住它）。
  - `test/features/multiview/multiview_controller_test.dart`：轮播格子、四个格子只提示一次 Cookie、恢复后显示新档 3 个；`multiview_page_test.dart`：轮播格子的按钮 1 个。
  - `test/platforms_test.dart`：Twitch 按应用给的编码请求 usher（默认 `av1,h265,h264`，只给 `avc` 时 `h264`）；FC2 探测连接进池、两个打开器共用、`AppServices.close` 关掉。
  - `packages/live_media/test/fc2_control_pool_test.dart`（新，7 个）：按频道接手、任何档用 `playlistFor`（50 → 51 号高延迟变体，auto → 0 号主列表）、没接手的走平台（请求 `memberApi.php`）、20 秒（注入的计时器）后关、同频道替换旧的、等待中断开的移出、`close` 全关、一个适配器一个池。控制连接是真的 `Fc2LiveControl`，假套接字回放 `fixtures/fc2live/control` 的录制。
- 改之前会失败：恢复后显示新档的 2 个（直播间、多画面）先把修复退掉跑过，都是“期望 1080p60，实际 720p60”；B-7 直播间那个改之前没有提示（失败）；其余新用例改之前编译不过（`playCarousel`、`ChatBadge`、`Fc2ControlPool`、`videoCodecs` 都是新接口）。小窗那个改之前也通过（见上）。
- 全部通过：`apps/pure_live` 的 `test/features/live_play`、`test/features/multiview`、`test/platforms_test.dart`、`packages/live_media`；`dart format`、`dart analyze --fatal-infos` 无问题；门禁见最后。
- 测试里的计时器：FC2 的 20 秒用注入的计时器，没有短于 1 秒的真计时器；不访问真实平台（Twitch、17LIVE、酷狗、FC2 都用仓库样本）。

## 和 C01.4 怎么分的

- C01.4（已完成）改的是 `_openQuality`（进房、用户选档），本任务改 `_refreshPlan`（恢复、续期）；两处用同一个 `resolveServedPlayQuality`。提示规则不变：恢复时不提示。

## 真机上要看的

K90（`192.168.1.2:5555`），测试包 `com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包。

1. 不登录哔哩哔哩，热门 → 哔哩哔哩，找一张标“轮播”的卡片进去（或关注里“未开播”组里标“轮播”的）：画面写“主播未开播，正在轮播往期视频”，按钮是“播放轮播”“切换直播间”。
2. 点“播放轮播”：先显示“正在进入直播间…”，几秒内出画面；画面不是视频开头（和网页上这个房间正在放的位置差不多）；清晰度按钮写“轮播”；弹幕照常连上。
3. 等这段放完（或拖到结尾附近）：日志里 `playback: recovering #1 live_source_completed`，接着放下一段，不报错。
4. 关注这个主播，回关注页：仍在“未开播”组（轮播不算开播，录制也照旧不录轮播）。
5. 横屏全屏（F 键或全屏按钮）时同一个房间：两个按钮一样，点了能播。
6. 多画面：选台选这个轮播房间，格子写轮播的说明，下面有“播放轮播”，点了播。
7. （有代理时）17LIVE 进一个聊天多的房间：名字有颜色（不刺眼，深浅主题都看得清），名字前有徽章图；离开成应用内小窗，小窗弹幕照常。
8. （碰上时）酷狗 PK 中的房间：对方房间的发言名字前有“对方”。
9. （有代理时）账号页填一个失效的 Twitch Cookie，进 Twitch 直播间：弹出一次“Twitch 的 Cookie 已失效，已改为匿名观看，请在账号页重新填写”，照常播放；再进别的 Twitch 房间不再提示。设置里关掉“优先 H.264”后进一个有 HEVC/AV1 的频道能播。
10. （有代理时）Picarto 主播中途换档（不好碰）：恢复后清晰度按钮显示新档名，没有“?”。
11. （有代理时）FC2 进房：起播比改之前快（`adb logcat -s flutter | grep playback-timing` 那一行的 `input` 比改之前短：不再另开一次控制连接）；切换清晰度能播；进房后 20 秒内退出，再进别的房间正常。

## 留下的问题

- 直播间上面开着多画面时（多画面暂停在下面），同一次 Cookie 被拒两边都会弹一次（两个订阅）；很少碰上，没处理。
- 电视直播间（`tv_room_overlays.dart`）的轮播状态没有“播放轮播”（电视按 OK 是刷新），这次只做 Android 手机，电视以后看要不要加。
- `engineVideoCodecs` 写死三种：Android 的 libmpv 里有 dav1d（查过 `libmpv.so` 的符号）和 HEVC 解码器，硬解不行时软解（`hwdec-software-fallback`）；Windows、Linux 的 libmpv 没查，那边如果缺 AV1 要在这里按平台给。传全集和不传（`null`）对 usher 的请求一样，这次接上主要是有了改的地方。
- 17LIVE 徽章的顺序按字段顺序，没和网页核对（E06.1 留下的）；`getRoundPlayVideo` 只用合成回答测过；登录后的轮播走 `getRoomPlayInfo` 能不能给地址没核实（E01.1）。
- 旧工作区 `agent-af6f5e80c4e19804f` 的半成品已经全部用上，可以删（我没删，留给维护者）。
