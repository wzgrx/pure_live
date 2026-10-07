# E05.4 平台层小问题合集

克拉克拉列表提前到底、LOOK 搜索能力、AcFun 付费直播仍连弹幕、百度签名过期后重连用旧地址、多画面里六间房没有弹幕、京东酷狗百度的 3.x 占位名、`getDanmaku` 死代码、斗鱼设置键注释。

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：2026-10-07 docs v2 核对。E 组：[E02 说明](../../E02-其他国内平台/README.md)“已知问题”（克拉克拉到底、LOOK 搜索说明、占位值）、[E02.6](../../E02-其他国内平台/E02.6-克拉克拉/README.md)、E 组报告（`getDanmaku` 死代码、斗鱼注释）；D 组：AcFun 付费直播（`connection_base.dart:55`）、百度签名（[D01.27](../../../D-弹幕/D01-平台弹幕协议/D01.27-百度直播弹幕/README.md)“留下的问题”）、六间房（[D01.28](../../../D-弹幕/D01-平台弹幕协议/D01.28-六间房弹幕/README.md)）；H、I 组更正：六间房录制不受影响（录制的弹幕走 `getRoomDetail`），受影响的是多画面
- 相关：E05.1、E05.2（模型和接口）；[E05.3](../E05.3-房间详情补齐时连封面一起补/README.md)（同一子分类的另一个小修）；[C01.6](../../../C-直播间/C01-进房和房间逻辑/C01.6-主播换场后弹幕参数变了要重连/README.md)（换场和弹幕结束后按进房详情取参数，和本任务的百度那条互补）；[J06.2](../../../J-设置和数据/J06-3.x数据迁移/J06.2-3.x迁移报告在正式版里看得到/README.md)（用本任务给的占位名常量清数据）；多画面 [N01](../../../N-多画面和投屏/N01-多画面/README.md)；决定 D-001、D-017、D-018、D-024
- 任务书：[brief.md](brief.md)

## 目标

八个各自很小、都在平台层（或紧挨着平台层）的问题，一次修掉：

1. **克拉克拉列表提前到底**：克拉克拉的时间线翻几页后会整页重复，适配器去重后返回空页并说“还有下一页”，列表却把空页当成到底，第 4 页以后的新主播看不到。
2. **LOOK 搜索说明不对**：搜索 LOOK 时写“只能用房间号或直播链接查找，不支持昵称搜索”，实际能按昵称在当前推荐里筛。
3. **AcFun 付费直播仍连弹幕**：付费直播没有弹幕参数，直播间照样去连，聊天区显示“弹幕连接失败”。
4. **百度签名过期后重连用旧地址**：百度的刷新不带弹幕参数，签名过期后用旧的过期地址重连，立刻又结束。
5. **多画面里六间房（以及 AcFun、克拉克拉）没有弹幕**：多画面用“录制详情”建格子，这几个平台的录制详情不带弹幕参数。
6. **京东、酷狗、百度的 3.x 占位名**：3.x 在不知道名字时写 `JD Live`、`Kugou Live`、`Baidu Live`，迁移过来的关注卡上一直显示它们；本任务在平台层给出这些值，清理在 J06.2 做。
7. **`getDanmaku` 死代码**：`LiveSite.getDanmaku()` 和 `LiveDanmaku`、`EmptyDanmaku` 是 3.x 的接口，4.x 的弹幕全在 `live_danmaku` 的注册表里，没有任何调用。
8. **斗鱼设置键注释写错**：注释写 `douyuForceRenewal`，实际设置键是 `douyuForceRenew`。

## 3.x 和现状

| 问题 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 1 克拉克拉空页 | 3.x 列表遇到连续两页没有新房间才结束 | 适配器 `packages/live_core/lib/src/sites/kilakila/kilakila_site.dart:146-190` `_timeline`：本页去重后为空时 `idle` 加一，连续 `maxPagesWithoutNew = 3`（`:59`）页才 `hasMore: false`；列表 `apps/pure_live/lib/shared/rooms/room_feed.dart:483` `hasMore = chunk.hasMore && chunk.rooms.isNotEmpty && unchanged < 2`：**空页直接到底**（`unchanged < 2` 本来就管“连续两页没有新房间”） | 空页不单独当到底：去掉 `chunk.rooms.isNotEmpty`，靠 `unchanged < 2` 和平台的 `hasMore` |
| 2 LOOK 搜索 | `lib/modules/search/search_capability.dart:111-115` 也写成 `roomLookup`（3.x 就错了） | `apps/pure_live/lib/features/search/search_capability.dart:139` `SiteIds.lookLive: roomLookup`；而 `looklive_site.dart:225-260` 的搜索是：房间号或链接精确找，其他关键词在两个推荐列表第一页里按号码、名字、标题筛 | 改 `showcaseSnapshot`（说明文字 `search_scope_showcase`：“输入号码或粘贴链接可精确查找；其他关键词只在平台当前推荐的直播里按昵称筛选，搜不到未开播的主播”） |
| 3 AcFun 付费 | 3.x 付费直播整个加载失败 | 付费直播 `_withBroadcast`（`acfun/acfun_site.dart:446-457`）`data == null` 时只带 `restriction: paid`，没有 `danmakuData`；直播间 `_danmakuStage`（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:807`）对“受限但在播”也连弹幕（U.2g c11）；`danmaku.connect(null)` → `packages/live_danmaku/lib/src/connection_base.dart:55` `ArgumentError` → 聊天区“弹幕连接失败” | 没有弹幕参数时不连：聊天区是“空闲”状态（和没开弹幕一样），不报错 |
| 4 百度签名 | 3.x 没有百度弹幕 | 刷新 `baidulive/baidulive_site.dart:319-321` 用同一个房间命令但不传 `withData`，`BaiduLiveApi.liveRoom`（`baidulive_api.dart:907-935`）`danmakuData: withData ? room.danmaku : null`（`:934`） | 刷新在直播中也带 `danmakuData`（同一个回答里本来就有，不多请求）；`data` 仍只在进房时带 |
| 5 多画面的弹幕参数 | 3.x 多画面不连弹幕的平台多 | 多画面 `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart:486-490` 对实现 `LiveSiteRecordRoomResolver` 的平台用 `getRoomDetailForRecording`；`:865` `room.danmakuData == null` 就不连。录制详情不带参数的：六间房 `sixroom/sixroom_site.dart:416`（`_detail(media: true)`，`danmaku` 默认 false）、AcFun `acfun_site.dart:470-471`（`danmaku: false`）、克拉克拉 `kilakila_site.dart:337`（`_entered` 默认 `withDanmaku: false`）。三家的参数都不用多发请求（`sixroom_site.dart:400`、`acfun_site.dart:453`、`kilakila_site.dart:320`）。录制自己连弹幕用 `getRoomDetail`（`apps/pure_live/lib/app/recording.dart:52`），不受影响 | 这三家的录制详情也带弹幕参数；其余 30 个平台逐个核对一遍（录制详情有没有 `danmakuData`），没带而且不用多请求的一起补 |
| 6 占位名 | `jd_live_api.dart:231-232`、`:261-262`（`JD Live`）；`kugou_live_api.dart:396-397`、`:505-506`（`Kugou Live`）；`baidu_live_api.dart:390`（`Baidu Live`）；合并时按“等于占位”换掉（`jd_live_api.dart:52-53`、`kugou_live_api.dart:92-93`、`baidu_live_api.dart:89-90`） | 4.x 适配器不再写占位（E02.9 的 28-2、UPGRADES X-2），`mergeFrom` 只在新值为空时保留旧值；3.x 存下的占位名迁移时没清（`packages/live_store/lib/src/legacy/legacy_rules.dart` 只清陈旧公告，`:11-14`、`:28`） | 平台层给一个“3.x 占位名”表（平台 id → 值），J06.2 用它清数据 |
| 7 `getDanmaku` | 3.x 的接口：`site.getDanmaku()` 返回连接，`EmptyDanmaku` 表示没有弹幕 | `packages/live_core/lib/src/live_site.dart:26-27` `LiveDanmaku getDanmaku() => EmptyDanmaku();`；`live_danmaku.dart`（64 行，`LiveDanmaku` `:9`、`EmptyDanmaku` `:50`），`live_core.dart:16` 导出；应用和其他包没有调用，只有 `packages/live_core/test` 下 37 个文件 47 处断言 `isA<EmptyDanmaku>()`；文档注释提到它的：`apps/pure_live/lib/app/services.dart:19`、`:57`、`:114`，`packages/live_danmaku/lib/src/registry.dart:42`，`missevan_site.dart:27`，`fc2live_site.dart:21` | 删掉接口、类、导出和断言；注释改成指向 `DanmakuRegistry` |
| 8 斗鱼注释 | — | `douyu/douyu_site.dart:73` 注释 `douyuForceRenewal`；设置是 `Settings.douyuForceRenew`（`packages/live_store/lib/src/settings/settings.dart:117`） | 改注释 |

## 方案

- c1 `room_feed.dart:483`：`hasMore = chunk.hasMore && unchanged < 2`；`_collect` 的文档注释（`:459-461`）写清“空页只算一次没有新房间”。核对 `popular_test.dart:163`（“an empty page ends the list”）的假平台第 3 页是 `hasMore: false`，不受影响；新增克拉克拉式的用例。
- c2 `search_capability.dart:139` → `SearchCoverage.showcaseSnapshot`；`search_test.dart` 里 LOOK 的说明文字断言跟着改。
- c3 `room_controller.dart:807`：`_danmakuStage` 加 `&& _room.danmakuData != null`（播放中但没有参数的情况一并处理）；聊天连接状态 `ChatConnection.idle`。多画面 `:865` 已经这样判断，不改。
- c4 `baidulive_site.dart:319-321`：刷新改成 `BaiduLiveApi.liveRoom(…, withChat: true)`（`liveRoom` 加参数 `withChat`，默认跟 `withData`）；`data` 照旧只在进房时带。`packages/live_core/test/sites/baidulive_site_test.dart` 加“刷新带聊天参数”。
- c5 三家的 `getRoomDetailForRecording` 带上弹幕参数：六间房 `_detail(roomId, media: true, danmaku: true)`；AcFun `_withBroadcast(…, danmaku: true)`；克拉克拉 `_entered(roomId, withDanmaku: true)`。再逐个看其他平台的录制详情（`grep -rn "getRoomDetailForRecording" packages/live_core/lib/src/sites`，34 个），把“进房带、录制不带、不用多请求”的列成表写进记录，一起补；要多请求的不补，写进“留下的问题”。
- c6 在 `packages/live_core` 加 `legacyPlaceholderNames`（例如 `lib/src/legacy_placeholders.dart`：`{SiteIds.jdLive: {'JD Live'}, SiteIds.kugouLive: {'Kugou Live'}, SiteIds.baiduLive: {'Baidu Live'}}`，加一句注释指向 3.x 的文件:行），从 `live_core.dart` 导出；J06.2 用。不改任何房间数据。
- c7 删 `LiveSite.getDanmaku`、`live_danmaku.dart`、`live_core.dart:16` 的导出；37 个测试文件里的断言删掉（断言的是“3.x 没有这个平台的弹幕”，现在由 `live_danmaku` 的注册表管，`apps/pure_live/test/platforms_test.dart` 已有注册表的覆盖）；改 6 处注释。
- c8 `douyu_site.dart:73` 注释改成 `douyuForceRenew`。

## 验证

- 自动测试：`apps/pure_live/test/features/popular/popular_test.dart`（空页不到底）、`search_test.dart`（LOOK 说明）、`live_play_controller_test.dart`（没有参数不连弹幕）、`packages/live_core/test/sites/baidulive_site_test.dart`、`sixroom_site_test.dart`、`acfun_site_test.dart`、`kilakila_site_test.dart`（刷新、录制详情带参数）、`apps/pure_live/test/features/multiview/`（六间房格子连弹幕）；删 `getDanmaku` 后 `packages/live_core` 全部测试通过。
- 真机：任务书“真机验证”（克拉克拉翻到第 5 页、LOOK 搜索说明、AcFun 付费直播间、多画面加六间房）；做之前“未开始”。

## 留下的问题

- 3.x 占位名的清理在 J06.2；`legacyPlaceholderNames` 只是数据。
- PandaTV 分区说明的旧文字（E 组报告，`zh.json` 的 PandaTV 目录说明）不在本任务，归 Z05 的文字整理。
- 换场后弹幕参数变了在 C01.6；本任务只让百度的刷新本身带参数。
