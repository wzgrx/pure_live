# C01.6 主播换场后弹幕参数变了要重连；改“YouTube 显示全部聊天”立即生效：任务书

## 背景

- 来源：2026-10-07 docs v2 核对。D 组：SHOWROOM、克拉克拉、TwitCasting 换场后弹幕停在旧的一场（[D06](../../../D-弹幕/D06-弹幕功能余项/README.md) 余项表，[D01.16](../../../D-弹幕/D01-平台弹幕协议/D01.16-SHOWROOM弹幕/README.md)、[D01.14](../../../D-弹幕/D01-平台弹幕协议/D01.14-克拉克拉弹幕/README.md)）；百度签名过期后重连用旧地址（[D01.27](../../../D-弹幕/D01-平台弹幕协议/D01.27-百度直播弹幕/README.md)“留下的问题”）；“YouTube 显示全部聊天”要重新进房才生效。C、O 组复核属实（[C01 说明](../README.md)“已知问题”第 3、4 条）。
- 现象：
  1. 在 SHOWROOM（或 TwitCasting、克拉克拉）直播间一直开着，主播下播再开播，播放会话自己恢复了（没走 `load()`），聊天列表不再有新弹幕，状态行也没有“连接断开”；退出重进才有。
  2. 百度直播间开着超过分片签名的 7 天（或列表签名到期），连接结束后每 60 秒“重连”一次又立刻结束。
  3. YouTube 直播间里打开“YouTube 显示全部聊天”，聊天还是精选聊天。
- 为什么现在做：第二档；规模小（两个阶段各约 1 小时）。
- 已经做过的：B-24 刷新和“连接结束后重连”（C01.1）；登录变化后取新参数重连 `_onLoginChanged`（D02.1 / B06 c1）。

## 目标和验收

1. 刷新发现换场（平台给的开播时间 `startedAt` 变了；或者播放中某次刷新平台说未开播、之后又能播）时：按进房详情（`getRoomDetail`）取新的 `danmakuData`，强制重连；聊天列表出现“正在连接弹幕服务器”和“弹幕服务器连接正常”的状态行。
2. 弹幕连接已经结束、刷新要重连时：刷新回答没有 `danmakuData`（大多数平台的轻量刷新）→ 先按进房详情取新参数再连；有 → 直接用（`mergeFrom` 已换上）。
3. 取进房详情失败：只记日志，照旧用现有参数重连（和现在一样），不出错误提示。
4. YouTube 直播间里改“YouTube 显示全部聊天”：1 秒内重连，新连接按新值读（全部聊天 / 精选聊天）；别的平台的直播间改这个开关不重连。
5. 不换场时不多发请求：普通的 60 秒刷新照旧只请求轻量接口。
6. B-24 的现有用例（`live_play_controller_test.dart:178`）和登录变化的用例照样通过；新测试改之前失败。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：
  - `start()`（`:304-329`）：跟着设置重连只有 `enableDanmakuDisplay`、`enablePipDanmaku`（`:313-315` → `_syncDanmaku()`，不强制）。
  - `_onLoginChanged`（`:281-296`）：只管哔哩哔哩；`site.getRoomDetail` → `fetched.danmakuData` → `_room.copyWith(danmakuData:)` → `_syncDanmaku(force: true)`；取失败照样重连。
  - `refreshDetail`（`:758-787`）：先取轻量详情（`LiveSiteRoomRefresher.getRoomDetailForRefresh`，没有就 `getRoomDetail`，`:763-766`）；不在播变能播 → `load()`（`:775-777`）；在播、平台说不能播、会话出错 → `load()`（`:779-781`）；其余 `_room = _room.mergeFrom(fetched).withAudienceFallbackFrom(_room)`（`:783`），连接已结束才 `_syncDanmaku(force: true)`（`:785`）。
  - `_syncDanmaku`（`:809-846`）：`danmaku.connect(_room.danmakuData)`；`force` 为假时连接没结束就直接返回（`:824`）。
- `packages/live_core/lib/src/live_room.dart:587-640` `mergeFrom`：`startedAt: incoming.startedAt ?? (sameBroadcast ? startedAt : null)`（`:614`）、`danmakuData: incoming.danmakuData ?? danmakuData`（`:619`）。
- 刷新不带参数的平台（举例）：SHOWROOM `showroom_site.dart:318-320`（`entry: false`，`:289` 注释“a refreshed room has neither”）；克拉克拉 `kilakila_site.dart:331-332`（`profileDetail`）；TwitCasting `twitcasting_site.dart:259-262`；百度 `baidulive_site.dart:319-321`（`BaiduLiveApi.liveRoom` 不传 `withData`，`baidulive_api.dart:933-934`）。
- YouTube：`apps/pure_live/lib/app/platforms.dart:226-227` 建连接时 `allChat: settings.get(Settings.youtubeShowAllChat)`；`packages/live_danmaku/lib/src/sites/youtube.dart:858-864` `YouTubeDanmakuConnection({required http, allChat = false, now})`，`start` 里 `_YouTubeChat(_http, run, allChat: _allChat, …)`（`:874`）；直播间的连接只建一次（`live_play_page.dart:278` `danmaku.connectionFor(site.id)`，控制器字段 `final DanmakuConnection danmaku`，`room_controller.dart:113`）。设置 `Settings.youtubeShowAllChat`（`packages/live_store/lib/src/settings/settings.dart:626`，默认关）在设置 → 弹幕 → 更多（`features/settings/danmaku_page.dart:102-103`）。
- 测试支持：`apps/pure_live/test/features/live_play/live_play_support.dart`：`FakeSite`（`:9`，`room` 可换、`detailCalls` 计数，没有实现 `LiveSiteRoomRefresher`）、`FakeDanmaku`（`:74`，`connects` 记每次的参数、`emit` 发事件）。

## 3.x 基线

- 3.x 没有定时刷新，也没有 TwitCasting、克拉克拉、SHOWROOM、百度、YouTube 的弹幕（都是 `EmptyDanmaku`），所以没有可对照的行为；4.x 的 B-24 是已批准升级。
- 要保留：60 秒刷新、刷新只用轻量接口（流量）；登录变化后重连的行为（B06 c1）；设置键名和默认值（`youtubeShowAllChat` 默认关，D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/DECISIONS.md` 的 D-017。
3. 本文件夹的 `README.md`；`docs/C-直播间/C01-进房和房间逻辑/README.md`（“现状”的刷新）；`docs/D-弹幕/D01-平台弹幕协议/D01.16-SHOWROOM弹幕/README.md`、`D01.27-百度直播弹幕/README.md`；`docs/E-直播平台/E05-平台框架和模型/E05.4-平台层小问题合集/brief.md`（百度那条，互补）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/logic/room_controller.dart`；`apps/pure_live/lib/app/platforms.dart`（只改 YouTube 那一行）；`packages/live_danmaku/lib/src/sites/youtube.dart`（只加可选参数）；测试 `live_play_controller_test.dart`、`live_play_support.dart`（`FakeSite` 加一个可选的轻量刷新）、`packages/live_danmaku/test/sites/youtube_test.dart`；本文件夹。
- 不能改：平台适配器（百度的刷新带参数在 E05.4）；`mergeFrom`；弹幕协议的连接逻辑；刷新间隔；`DanmakuConnection` 接口；设置键名和含义（D-018）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 换场和弹幕结束后按进房详情取新参数重连 | c1：从 `_onLoginChanged` 抽出 `Future<void> _renewDanmaku()`（用 `_epoch` 防晚到；失败照旧重连），`_onLoginChanged` 改用它。c2：`refreshDetail` 在合并前判断换场：`fetched.startedAt != null && _room.startedAt != null && fetched.startedAt != _room.startedAt`，或 `_sawOffline && fetched.isPlayableNow`（`_sawOffline` 在 `playing` 阶段收到 `!fetched.isPlayableNow` 时置真、换场处理后清掉）；是 → 合并后 `unawaited(_renewDanmaku())`。c3：`:785` 改成 `fetched.danmakuData == null ? _renewDanmaku() : _syncDanmaku(force: true)` | `room_controller.dart`、`live_play_support.dart`、`live_play_controller_test.dart` | 验收 1、2、3、5、6 |
| 2 YouTube 显示全部聊天改了就重连 | c4：`YouTubeDanmakuConnection` 加 `bool Function()? allChatOf`（`start` 时 `allChatOf?.call() ?? _allChat`）；`platforms.dart:227` 传 `allChatOf`；控制器 `start()` 里 `if (site.id == SiteIds.youtube)` 跟 `Settings.youtubeShowAllChat`，`skip(1)` 后 `_syncDanmaku(force: true)` | `youtube.dart`、`platforms.dart`、`room_controller.dart`、两个测试文件 | 验收 4 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 阶段 1（改之前会失败）：`live_play_controller_test.dart` 加
  - “a new broadcast found by the refresh reconnects the danmaku with fresh arguments (C01.6)”：`FakeSite` 加可选的 `refreshRoom`（实现 `LiveSiteRoomRefresher`，回答不带 `danmakuData`）；进房 `danmakuData: 'args-1'`、`startedAt` T1；之后 `site.room` 换成 `startedAt` T2、`danmakuData: 'args-2'`，刷新回答 `startedAt` T2 不带参数；`refreshDetail()` 后 `danmaku.connects == ['args-1', 'args-2']`，`site.detailCalls` 加一。
  - “a closed connection asks the room entry for arguments when the refresh has none”：`danmaku.emit(DanmakuClosed(credentialsUnavailable))`，进房详情换成 `'args-2'`，`refreshDetail()` 后最后一次连接用 `'args-2'`。
  - “no extra request without a new broadcast”：同一 `startedAt` 连刷三次，`detailCalls` 不变、`connects` 不变。
  - 取进房详情抛错：照旧用旧参数重连，不提示。
- 阶段 2（改之前会失败）：`live_play_controller_test.dart` 加“changing YouTube's all-chat setting reconnects a YouTube room only”：`FakeSite` 的 `id` 可配（或加一个 `FakeYouTubeSite`），改 `Settings.youtubeShowAllChat` 后 `danmaku.connects` 多一次；哔哩哔哩房间不多。`youtube_test.dart` 加“allChatOf is read at every start”：同一个连接先后两次 `connect`，第一次假、第二次真，请求体分别是精选和全部聊天的 continuation（用现有的样本和假 HTTP）。
- 测试里的定时器至少 1 秒（D-017），不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 开着代理进一个在播的 SHOWROOM 直播间（或 TwitCasting），等聊天有新弹幕；等主播下播再开播（可以挑每天固定时段换场的主播），人不离开直播间 | 开播后 1～2 分钟内聊天区出现“正在连接弹幕服务器”“弹幕服务器连接正常”，之后有新弹幕 |
| 2. YouTube 在播直播间，设置 → 弹幕 → 更多 →“YouTube 显示全部聊天”开（或直播间弹幕设置标签里改） | 回到直播间 1 秒内聊天区出现重连状态行，消息明显变多（全部聊天）；关掉后变回精选 |
| 3. 哔哩哔哩直播间里改同一个开关 | 聊天不重连 |
| 4. 一个普通直播间开着 5 分钟，`adb logcat` 里看请求（或应用日志） | 每 60 秒只有一次轻量刷新，没有多余的进房详情请求 |

## 风险和注意

- `startedAt` 有的平台每次刷新给的值有秒级抖动（例如按“已播秒数”倒推）：比较时允许 60 秒误差，或者只在相差超过 2 分钟时算换场；写进记录哪几个平台是这样。
- `_renewDanmaku` 和 `load()` 交错：`load()` 会换 `_epoch`，`_renewDanmaku` 拿到回答后先 `_current(epoch)` 判断，过期就丢。
- YouTube 连接里的 `_YouTubeChat._allChat`（`youtube.dart:927`）在运行中会改（全部聊天拿不到时退回精选），`allChatOf` 只决定每次 `start` 的初值，不要改那段逻辑。
- 可能冲突的文件：`room_controller.dart`（C01.4、C01.5、E05.4 也改，先后做）；`platforms.dart`（Q03.1 改弹幕握手）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/C01.6` 或本机工作区；提交信息以 `[C01.6]` 开头（英文）；不推 master。
- 提交前：改过的包（`apps/pure_live`、阶段 2 还有 `packages/live_danmaku`）跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；换场的判断用了哪几条、各平台 `startedAt` 稳不稳；测试数量（改之前失败几个）；改了哪些文件；`live_danmaku` 新加的参数；要在真机上看的；可能冲突的文件。
