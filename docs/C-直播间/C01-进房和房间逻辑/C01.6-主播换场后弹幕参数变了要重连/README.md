# C01.6 主播换场后弹幕参数变了要重连；改“YouTube 显示全部聊天”立即生效

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：2026-10-07 docs v2 D 组核对（[D06](../../../D-弹幕/D06-弹幕功能余项/README.md) 的余项表、[D01.16 SHOWROOM](../../../D-弹幕/D01-平台弹幕协议/D01.16-SHOWROOM弹幕/README.md)、[D01.14 克拉克拉](../../../D-弹幕/D01-平台弹幕协议/D01.14-克拉克拉弹幕/README.md)、[D01.27 百度直播](../../../D-弹幕/D01-平台弹幕协议/D01.27-百度直播弹幕/README.md)）和 C、O 组核对（[C01 说明](../README.md)“已知问题”第 3、4 条）
- 相关：刷新 B-24（[C01.1](../C01.1-直播间主要流程/README.md)）；平台层的百度刷新带弹幕参数在 [E05.4](../../../E-直播平台/E05-平台框架和模型/E05.4-平台层小问题合集/README.md)（互补）；YouTube 弹幕 [D01](../../../D-弹幕/D01-平台弹幕协议/README.md)（UPGRADES B-13）；同文件的任务 [C01.4](../C01.4-直播间清晰度显示实际档/README.md)、[C01.5](../C01.5-后台时未开播的房间开播后/README.md)；决定 D-001、D-017、D-018
- 任务书：[brief.md](brief.md)

## 目标

1. 人一直留在直播间里，主播下播又开了新的一场（或者平台换了这一场的聊天凭证），聊天列表能自动接到新的一场；现在 TwitCasting、克拉克拉、SHOWROOM 会停在旧的一场，一条新弹幕都没有，只能退出重进。
2. 百度直播的聊天列表签名过期、连接结束后，刷新时能拿到新签名重连；现在重连用的还是同一组过期地址，马上又结束。
3. 在直播间里改“YouTube 显示全部聊天”（设置 → 弹幕 → 更多，或直播间的弹幕设置），YouTube 直播间的聊天马上换成“全部聊天”或“精选聊天”；现在要退出重进才生效，用户以为开关没用。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| TwitCasting、克拉克拉、SHOWROOM 的弹幕 | 没有（3.x 这三个平台是 `EmptyDanmaku`） | 有（D01.12、D01.14、D01.16）；参数 `danmakuData` 只在进房详情里：SHOWROOM `_detail(entry: true)`（`packages/live_core/lib/src/sites/showroom/showroom_site.dart:290-311`，刷新 `:320` 用 `entry: false` 不带），克拉克拉 `getRoomDetail` → `_entered(withDanmaku: true)`（`kilakila/kilakila_site.dart:326`，刷新 `:331-332` 的 `profileDetail` 不带），TwitCasting 刷新只读 `streamserver.php`（`twitcasting/twitcasting_site.dart:259-262`） | 换场后用新参数重连 |
| 刷新时怎么处理弹幕 | 没有定时刷新 | `refreshDetail`（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:758-787`）：只在连接**已经结束**（`danmaku.status == DanmakuStatus.closed`）时 `_syncDanmaku(force: true)`（`:785`）；不比较这一场是不是换了；合并用 `LiveRoom.mergeFrom`，`danmakuData: incoming.danmakuData ?? danmakuData`（`packages/live_core/lib/src/live_room.dart:619`），刷新不带参数时保留旧的 | 发现换场（开播时间变了，或下播后又开播）时按进房详情取新参数、强制重连；连接结束后重连前，刷新没带参数就按进房详情取 |
| 旧连接会不会自己结束 | — | 这三个平台换场后旧连接不一定结束（SHOWROOM 只剩 `ACK`），所以“结束了才重连”等不到 | 不靠旧连接结束 |
| 百度签名过期 | 3.x 没有百度弹幕 | 列表签 182.5 天、分片签 7 天，过期时连接以 `credentialsUnavailable` 结束（D01.27）；刷新 `getRoomDetailForRefresh`（`baidulive/baidulive_site.dart:319-321`）不带参数（`baidulive_api.dart:934` `withData` 才带），`mergeFrom` 留着过期的 → 重连立刻再结束 | 重连前拿进房详情的新参数（本任务）；平台层让刷新本身带参数（E05.4，省一次请求） |
| “YouTube 显示全部聊天” | 3.x 没有 YouTube 弹幕（B-13 是 4.x 加的） | 只在建连接时读一次：`apps/pure_live/lib/app/platforms.dart:227` `YouTubeDanmakuConnection(http: http, allChat: settings.get(Settings.youtubeShowAllChat))`；直播间的连接在 `live_play_page.dart:278` 建一次；控制器只跟 `enableDanmakuDisplay`、`enablePipDanmaku` 两个设置重连（`room_controller.dart:313-315`） | 设置变了：YouTube 直播间重连，新连接按新值读 |
| 登录变化后的重连 | — | 已有同样的做法可以照抄：`_onLoginChanged`（`room_controller.dart:281-296`）重新 `getRoomDetail` 拿新 `danmakuData` 再 `_syncDanmaku(force: true)` | 抽成一个“取新参数并重连”的方法，三处共用 |

## 方案

- c1 **取新参数并重连**（`room_controller.dart`）：从 `_onLoginChanged` 抽出 `_renewDanmaku()`：在 `_danmakuStage && _wantsDanmaku` 时 `site.getRoomDetail(roomId:)`，拿到 `danmakuData` 就 `_room = _room.copyWith(danmakuData: data)`，然后 `_syncDanmaku(force: true)`；失败时只记日志，照旧用现有参数重连（和现在一样）。`_onLoginChanged` 改用它。
- c2 **发现换场**（`refreshDetail`）：在合并 `fetched` 之前比较：`fetched.startedAt` 和 `_room.startedAt` 都有而且不同；或者上一次刷新平台说未开播（记 `_sawOfflineWhilePlaying`，在 `playing` 阶段收到 `!fetched.isPlayableNow` 时置真）、这一次又能播。是换场 → 合并后 `unawaited(_renewDanmaku())`。
- c3 **结束后重连先拿新参数**：`:785` 的 `danmaku.status == DanmakuStatus.closed` 分支：`fetched.danmakuData == null`（刷新不带参数的平台）→ `_renewDanmaku()`；带了 → 照旧 `_syncDanmaku(force: true)`（`mergeFrom` 已经换上新参数）。这样百度过期后也能接上（E05.4 合并后百度的刷新本身就带参数，少一次请求）。
- c4 **YouTube 设置立即生效**：`packages/live_danmaku/lib/src/sites/youtube.dart:858-864` 的 `YouTubeDanmakuConnection` 加可选参数 `bool Function()? allChatOf`（每次 `start` 读；没给时用原来的 `allChat`，只加不改）；`platforms.dart:227` 改传 `allChatOf: () => settings.get(Settings.youtubeShowAllChat)`；控制器在 `site.id == SiteIds.youtube` 时多跟一个设置 `Settings.youtubeShowAllChat`（`:313-315` 的循环里加），变了就 `_syncDanmaku(force: true)`。多画面的 YouTube 格子按选中时建连接，自然读到新值，不改。
- 不改：刷新间隔、平台适配器（E05.4 改百度）、`mergeFrom` 的规则、弹幕协议。

## 验证

- 自动测试：`apps/pure_live/test/features/live_play/live_play_controller_test.dart` 加三个用例（换场后用新参数重连、连接结束且刷新不带参数时先取进房详情、YouTube 设置变了重连）；`packages/live_danmaku/test/sites/youtube_test.dart` 加一个（`allChatOf` 每次 `start` 都读）；`:178` 的 B-24 用例照样通过。
- 真机：任务书“真机验证”（SHOWROOM 或 TwitCasting 主播下播再开播、YouTube 改开关）；做之前“未开始”。

## 留下的问题

- 抖音、哔哩哔哩这类刷新本来就带参数、旧连接下播会自己结束的平台不受影响；其他平台换场时旧连接会不会结束没有逐个核对，c2 对所有平台生效，多一次进房详情请求（换场才发生，频率很低）。
- 多画面格子换场后的弹幕不在本任务（N01；多画面没有定时刷新）。
