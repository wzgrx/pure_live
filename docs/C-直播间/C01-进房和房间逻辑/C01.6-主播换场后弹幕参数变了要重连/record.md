# C01.6 主播换场后弹幕参数变了要重连；改“YouTube 显示全部聊天”立即生效：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区；两个阶段的代码、测试和本记录一个提交（`[C01.6]`），两个阶段都完整
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 取新参数并重连 | 做了 | `_renewDanmaku(why)` 从 `_onLoginChanged` 抽出，`_onLoginChanged` 改用它；用 `_epoch` 丢掉晚到的回答；取失败只记日志、照旧用现有参数重连；网络电视和不支持弹幕的平台不去取进房详情（直接按原来的方式重连） |
| c2 发现换场 | 做了 | 两条：开播时间都有而且相差**超过 2 分钟**；或者播放中某次刷新平台说不能播（`_sawOffline`）、这次又能播。只在 `playing`、这次刷新不 `load()` 时判断；`load()` 清掉 `_sawOffline`；一场只触发一次 |
| c3 结束后重连先拿新参数 | 做了 | 连接已结束：刷新回答没带 `danmakuData` → `_renewDanmaku`；带了 → 照旧 `_syncDanmaku(force: true)`（`mergeFrom` 已换上） |
| c4 YouTube 设置立即生效 | 做了 | `YouTubeDanmakuConnection` 加可选 `allChatOf`（每次 `start` 读，没给时用原来的 `allChat`）；`platforms.dart` 改传 `allChatOf`；控制器只在 `site.id == youtube` 时跟 `Settings.youtubeShowAllChat`，变了就强制重连 |

验收：

| 验收 | 结果 |
|---|---|
| 1. 换场（开播时间变了，或下播后又能播）→ 按进房详情取新参数、强制重连，聊天里有“开始连接弹幕服务器”“弹幕服务器连接正常” | 自动测试过（两种判断各一个） |
| 2. 连接结束后刷新：没带参数先取进房详情，带了直接用 | 自动测试过 |
| 3. 取进房详情失败：只记日志，用现有参数重连，没有提示 | 自动测试过 |
| 4. YouTube 直播间改开关立即重连，新连接按新值读；别的平台不重连 | 自动测试过（控制器两个、`youtube_test.dart` 一个：同一个连接两次 `connect`，第二次的请求是“全部聊天”的 continuation） |
| 5. 不换场不多发请求 | 自动测试过：同一场（开播时间差 40 秒）连刷三次，只有轻量刷新 |
| 6. B-24 原用例、登录变化的用例照样通过；新测试改之前失败 | 是 |

## 根因

- 换场停在旧的一场：`room_controller.dart` 的 `refreshDetail`（改前 `:807-837`）只在连接**已经结束**时重连（`:836`），而且用的是 `mergeFrom` 之后的参数；`LiveRoom.mergeFrom`（`packages/live_core/lib/src/live_room.dart:619`）`danmakuData: incoming.danmakuData ?? danmakuData`，SHOWROOM（`showroom_site.dart:318-320` `entry: false`）、克拉克拉（`kilakila_site.dart:331-332`）、TwitCasting（`twitcasting_site.dart:259-262`）、百度（`baidulive_site.dart:319-321`）的轻量刷新都不带参数，所以永远是进房时那一场的参数；这三个平台换场后旧连接也不一定结束，连“结束才重连”都等不到。
- 百度签名过期：连接以 `credentialsUnavailable` 结束后，`:836` 用同一组过期参数重连，立刻又结束。
- YouTube：`platforms.dart:227`（改前）建连接时读一次设置（`allChat: settings.get(...)`），直播间的连接只建一次（`live_play_page.dart` `danmaku.connectionFor(site.id)`），控制器只跟 `enableDanmakuDisplay`、`enablePipDanmaku`（改前 `:350-352`），改开关不会重连，重连了也还是旧值。
- 3.x 没有定时刷新，这几个平台也没有弹幕（`EmptyDanmaku`），没有可对照的行为；B-24 是 4.x 的已批准升级。

## 各平台的开播时间稳不稳

- 大多数平台给的是平台记的绝对时间（读代码：哔哩哔哩 `live_time` / `live_start_time`、斗鱼 `show_time`、虎牙 `startTime`、抖音 `start_time`、Twitch `createdAt`、YouTube `startTimestamp` 等），同一场每次一样；没有逐个平台抓包核对。
- 按“已播多久”倒推、每次刷新有秒级抖动：SOOP（`startedBefore(BTIME, now)`，`soop_api.dart:401`、`:429`）、酷狗（`listStart(livetime, answeredAt)`，`kugoulive_api.dart:582-586`）。所以判断换场时允许 2 分钟误差。
- 刷新不给开播时间的平台（或者给 null）只靠第二条（下播后又能播）。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`_renewDanmaku`、`_isNewBroadcast`、`_sawOffline`、`_startJitter`；`refreshDetail` 判断换场和结束后取参数；`start` 对 YouTube 跟 `youtubeShowAllChat`
- `apps/pure_live/lib/app/platforms.dart`：YouTube 那一行改传 `allChatOf`
- `packages/live_danmaku/lib/src/sites/youtube.dart`：`YouTubeDanmakuConnection` 加可选参数 `allChatOf`（只加不改；`_YouTubeChat` 运行中退回精选的逻辑没动）
- 测试：`apps/pure_live/test/features/live_play/live_play_support.dart`（`FakeSite.siteId`、`RefreshingFakeSite`）、`live_play_controller_test.dart`（6 个）、`packages/live_danmaku/test/sites/youtube_test.dart`（1 个）

## 新设置、翻译键、门禁基线

- 没有。`live_danmaku` 新加的参数：`YouTubeDanmakuConnection(allChatOf: bool Function()?)`。

## 测试

- 新增 7 个：控制器 6 个（开播时间变了、下播后又开播、结束后刷新不带参数先取进房详情 / 带了直接用、取失败照旧重连不提示、YouTube 改开关重连、别的平台不重连），`youtube_test.dart` 1 个。
- 改之前失败 5 个（控制器 4 个；`youtube_test.dart` 那个编译不过）；“取失败照旧重连”和“别的平台不重连”改之前也通过（守住原有行为）。
- `apps/pure_live` 全部 956 个、`packages/live_danmaku` 全部 1595 个通过；`dart analyze --fatal-infos` 无问题。

## 真机上要看的

- 任务书“真机验证”四步：SHOWROOM 或 TwitCasting 主播下播再开播，1～2 分钟内聊天出现重连状态行并有新弹幕；YouTube 改“显示全部聊天”立即重连、消息变多，关掉变回精选；哔哩哔哩里改同一个开关不重连；普通直播间开 5 分钟，每 60 秒只有一次轻量刷新。

## 可能冲突的文件

- `room_controller.dart`（C01.4、C01.5、E05.4 也改；并行的弹幕设置 / 画中画弹幕任务 A08.6、A08.7、D03.3 如果碰控制器的设置订阅，会在 `start()` 的同一段）；`platforms.dart` 的弹幕注册表（并行的平台适配器任务、Q03.1）；`live_play_support.dart`（测试支持，只加不改）。
