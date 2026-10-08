# E05.4 平台层小问题合集：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区；阶段 1 `c0e306288`，阶段 2 `469081c60`，阶段 3 和本记录见登记表的 `commit`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 克拉克拉空页 | 做了 | 无 |
| c2 LOOK 搜索说明 | 做了 | 无 |
| c3 没有弹幕参数不连 | 做了 | SOOP 的弹幕连接对 `null` 参数会报“服务器连接失败”（3.x 的做法，`live_danmaku/lib/src/sites/soop.dart:200`）；现在直播间对没有参数的房间一律不连、聊天区空闲，SOOP 这种房间（直播中但站点回答没有聊天服务器）也一样，和多画面一致 |
| c4 百度刷新带参数 | 做了 | `liveRoom` 加 `withChat`（默认跟 `withData`），刷新传 `withChat: true` |
| c5 录制详情带弹幕参数 | 做了 | 除了任务书点名的三家，核对后另补 6 家（见下表）；B 站要多发请求，没补 |
| c6 3.x 占位名常量 | 做了 | `packages/live_core/lib/src/legacy_placeholders.dart`；3.x 的占位同时写进 `nick` 和 `title`，注释写明 |
| c7 删 `getDanmaku` | 做了 | 删掉的断言是 25 个测试文件里的 25 处（任务书写的 37 个文件、47 处含注释和 `EmptyDanmakuConnection`）；只剩“3.x 有 `EmptyDanmaku`”这类说明 3.x 的注释 |
| c8 斗鱼注释 | 做了 | 无 |

## 根因

- 1：`apps/pure_live/lib/shared/rooms/room_feed.dart:483`（改前）`hasMore = chunk.hasMore && chunk.rooms.isNotEmpty && unchanged < 2`：克拉克拉适配器去重后的空页（`hasMore: true`）被共用列表直接当成到底；“连续两页没有新房间才到底”（3.x）本来由 `unchanged < 2` 管，`chunk.rooms.isNotEmpty` 是 4.x 多加的。
- 2：`apps/pure_live/lib/features/search/search_capability.dart:139`（改前）LOOK 写成 `roomLookup`，照搬 3.x `lib/modules/search/search_capability.dart:111-115`（3.x 自己就和实现不一致）；实现（`looklive_site.dart:225-260`）在推荐里按号码、名字、标题筛。
- 3：`room_controller.dart:859`（改前）`_danmakuStage` 只看阶段，不看有没有参数；AcFun 付费直播 `_withBroadcast` 不带 `danmakuData`，`connect(null)` 在 `connection_base.dart:55` 抛 `ArgumentError`，落到“弹幕连接失败”。
- 4：`baidulive_site.dart:319-321`（改前）刷新调 `BaiduLiveApi.liveRoom` 不带参数，`liveRoom` 的 `danmakuData: withData ? … : null` 把同一个回答里的新聊天地址丢掉；`refreshDetail` 用 `mergeFrom` 合并，旧的过期地址留着，弹幕结束后每次刷新都用它重连。
- 5：多画面（`multiview_controller.dart:486-490`）对所有平台都用 `getRoomDetailForRecording` 建格子（34 个平台都实现了 `LiveSiteRecordRoomResolver`），`:876` 没有参数就不连；六间房、AcFun、克拉克拉等 9 家的录制详情特意不带参数（照 3.x 录制器“不需要弹幕”），于是多画面里没有弹幕。录制自己的弹幕走 `getRoomDetail`（`app/recording.dart:52`），不受影响；`live_record`、`live_store` 不存 `danmakuData`。
- 6：3.x 的占位见 `git show v3.2.11:lib/core/site/jdlive/jd_live_api.dart`（`:231-232`、`:261-262`）、`kugoulive/kugou_live_api.dart`（`:396-397`、`:505-506`）、`baidulive/baidu_live_api.dart`（`:390`）；4.x 没有给出这些值的地方。
- 7：`LiveSite.getDanmaku()`（`live_site.dart:28`）和 `live_danmaku.dart` 是 3.x 接口的残留，4.x 的连接全在 `DanmakuRegistry`。
- 8：`douyu_site.dart:73` 注释的键名写错。

## 录制详情逐平台核对（c5）

“进房”“录制”指改前 `getRoomDetail`、`getRoomDetailForRecording` 有没有 `danmakuData`；没有弹幕的平台（注册表里没有）不涉及。

| 平台 | 进房带 | 录制带（改前） | 补不补 | 理由 |
|---|---|---|---|---|
| 六间房 | 带 | 不带 | 补 | 参数来自同一个 inroom 回答（`sixroom_site.dart:400`） |
| AcFun | 带 | 不带 | 补 | 同一个 `startPlay`（`acfun_site.dart:453`）；付费直播两处都没有 |
| 克拉克拉 | 带 | 不带 | 补 | 同一个 `getRoomInfo` 的场次号 |
| CHZZK | 带 | 不带 | 补 | 同一个 `live-detail` 的 `chatChannelId` |
| Kick | 带 | 不带 | 补 | 同一个频道回答的聊天室号 |
| 猫耳 | 带 | 不带 | 补 | 同一个 `live/{id}` 回答 |
| Picarto | 带 | 不带 | 补 | 频道详情里就有；开播时间那一个请求仍只在进房时发 |
| SOOP | 带 | 不带 | 补 | 播放器接口的同一个回答（`withDanmaku`）；站点信息那一个请求仍只在进房时发 |
| Steam | 带 | 不带 | 补 | 同一个广播信息 |
| 哔哩哔哩 | 带 | 不带 | 不补 | 进房另发 `getDanmuInfo`（`danmakuArgs`，带签名和重试），录制详情加它要多一个请求 → 留下的问题 |
| 抖音 | 带 | 带 | — | 同一个 `_detail(danmaku: true)` |
| 斗鱼、虎牙、快手、酷狗、京东、LOOK、PandaLive、17LIVE、SHOWROOM、TwitCasting、Twitch、YouTube、Bigo、FC2、百度 | 带 | 带 | — | 录制和进房调同一个函数、同样的参数 |
| niconico | 带 | 带 | — | `NiconicoApi.room` 都带；`keep` 只管座位引导 |
| YY | 带 | 带（直播中） | — | 直播中都走 `liveInfoDetail`；不在播时多画面本来不连 |
| CC、映客、LiveMe、TikTok、微博、小红书 | — | — | — | 没有弹幕 |

## 改了哪些文件

- 阶段 1：`apps/pure_live/lib/shared/rooms/room_feed.dart`、`apps/pure_live/lib/features/search/search_capability.dart`；测试 `popular_test.dart`、`search_test.dart`。
- 阶段 2：`apps/pure_live/lib/features/live_play/logic/room_controller.dart`（只改 `_danmakuStage`）；`packages/live_core/lib/src/sites/` 下 `baidulive/baidulive_api.dart`、`baidulive/baidulive_site.dart`、`sixroom`、`acfun`、`kilakila`、`chzzk`、`kick`、`missevan`、`picarto`、`soop`、`steambroadcast` 的 `*_site.dart`；测试 `live_play_controller_test.dart`、`live_play_support.dart`（`liveRoom` 加 `danmakuData` 参数）、`multiview_controller_test.dart` 和上面 10 个平台的 `*_site_test.dart`。
- 阶段 3：新文件 `packages/live_core/lib/src/legacy_placeholders.dart`、`packages/live_core/test/legacy_placeholders_test.dart`；`live_core.dart`（导出占位名，去掉 `live_danmaku.dart`）；删 `packages/live_core/lib/src/live_danmaku.dart`；`live_site.dart`；注释：`apps/pure_live/lib/app/services.dart`、`packages/live_danmaku/lib/src/registry.dart`、`missevan_site.dart`、`fc2live_site.dart`、`douyu_site.dart`；`packages/live_core/test` 下 25 个文件删断言；`packages/live_danmaku/test/connection_test.dart` 一处说明文字。

## 删掉的公开接口

- `LiveSite.getDanmaku()`、`LiveDanmaku`、`EmptyDanmaku`（`package:live_core`）。仓库里没有使用者；`EmptyDanmakuConnection`（`live_danmaku`）不动。

## 新设置、翻译键、门禁基线

- 都没有。LOOK 用的是已有的 `search_scope_showcase`、`search_scope_short_showcase`。

## 测试

- 新增 5 个：列表“空页 + 还有下一页不到底、连续两页才到底”、LOOK 说明、直播间“没有参数不连弹幕”、多画面“录制详情的参数被连上”、占位名表；改了 11 个平台测试的期望（百度刷新、9 家录制详情、Kick 新增录制用例）和 AcFun 付费直播录制详情没有参数的断言。
- 改之前失败的：列表、LOOK、直播间、百度、9 家录制详情、占位名（编译失败）共 14 个；多画面那条用假平台，改前也通过，守的是“多画面用录制详情建格子并连它的参数”这条路。
- 全部通过：`packages/live_core` 3659 个，`packages/live_danmaku` 1594 个，`apps/pure_live` 全部（见阶段 3 提交前的运行）。

## 真机上要看的

- 任务书“真机验证”1～5：克拉克拉推荐翻过第 3 页；LOOK 搜索说明；AcFun 付费直播间聊天区没有“弹幕连接失败”；多画面加六间房、AcFun、克拉克拉（以及 CHZZK、Kick、猫耳、Picarto、SOOP、Steam）点选后有弹幕；百度直播间 2 分钟弹幕正常。

## 留下的问题

- 多画面里哔哩哔哩没有弹幕：录制详情不带 `getDanmuInfo` 的凭据（要多一个请求）。要补得改多画面（选中格子时按需取参数）或者 B 站录制详情多发一个请求，归 N01 的后续。
- SOOP 直播中但回答里没有聊天服务器时，直播间以前报“服务器连接失败”（3.x），现在聊天区空闲。
- 3.x 占位名的清理在 J06.2。
- 可能冲突的文件：`room_controller.dart`（C01.6 正在改换场后弹幕参数）、`room_feed.dart`（I03.2）、`search_capability.dart`（I05）。
