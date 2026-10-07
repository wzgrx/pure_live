# E01.1 哔哩哔哩

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001），E 组的第一个平台，后面 33 个平台都照这里的做法；之后又做了升级落地（2026-09-29）、国内平台完善（2026-10-01）和附录 C 落地，全部记在 [record.md](record.md)
- 旧编号：M4.01、M4.U.1、T02a.1
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；轮播播放 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md)、接到界面 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/brief.md)；弹幕 D01.2；巡检 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)；决定 D-001、D-013（打码昵称不还原）、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/bilibili/`（`bilibili_api.dart` 926 行纯解析，`bilibili_site.dart` 660 行请求编排）；样本 `fixtures/bilibili/`（35 组）

## 目标

把 3.x 的哔哩哔哩适配器（`lib/core/site/bilibili/bilibili_site.dart`，884 行）重构进 `live_core`：推荐、分类和分区、搜索房间和主播、房间详情、清晰度和线路、醒目留言、开播状态、扫码登录用的三个接口、链接解析都和 3.x 一样能用；行为以 3.x 的冻结输出（`fixtures/bilibili/*/expected.json`）为准，差异逐条说明。做完以后用户在推荐、分区、搜索、关注、直播间里看到的哔哩哔哩内容和 3.x 一致，另外修掉 3.x 的几个错误（搜索封面地址拼错、搜不到未开播主播、出错时显示别的房间）。

## 平台接口要点

| 功能 | 接口（`api.live.bilibili.com` 除非另写） | 位置 |
|---|---|---|
| 游客身份 | `api.bilibili.com/x/frontend/finger/spi` 取 buvid3、buvid4；Cookie 自带 `buvid3` 时不另取 | `bilibili_site.dart:92`、`:100` |
| WBI 签名 | `api.bilibili.com/x/web-interface/nav` 取 `img_key`、`sub_key`；分区的签名接口还要 `live.bilibili.com/lol` 页面里的 `w_webid`；-352 时续签重试一次，412 不重试 | `:118`、`:136`、`:184` |
| 分类 | `/room/v1/Area/getList`（12 类、462 个分区） | `:233` |
| 分区房间 | 先用不签名的 `/room/v1/area/getRoomList`（`sort_type=online`，`page_size` 限 1～30），失败时（限流除外）退回签名的 `/xlive/web-interface/v1/second/getList` | `:247`、`:251`、`:266` |
| 推荐 | `/room/v1/Area/getListByAreaID`，退回 `/xlive/web-interface/v1/webMain/getMoreRecList` | `:291` |
| 搜索 | `api.bilibili.com/x/web-interface/search/type`（`search_type=live`、`live_user`，`cover_type=user_cover`），每页条数按设置并限 1～50 | `:328`、`:337` |
| 详情 | `/xlive/web-room/v1/index/getInfoByRoom`；短号（如 6）保持为房间号，长号（7734200）放在 `BilibiliRoomData` 里只用于取流和弹幕 | `:362`、`:377` |
| 开播状态 | `/room/v1/Room/get_info`，轮播（`live_status=2`）为 false | `:400` |
| 醒目留言板 | `/av/v1/SuperChat/getMessageList` | `:406` |
| 清晰度和线路 | `/xlive/web-room/v2/index/getRoomPlayInfo`（只要 H.264，`codec=0`）；回答里的 `current_qn` 是实际给的画质（游客请求蓝光 400 实际给超清 250），线路带请求头和有效期（`LivePlayLine`、`PlayLease`） | `:418`、`:434`、`:468` |
| 轮播视频 | 游客拿不到轮播的地址时：`/live/getRoundPlayVideo` 取 `bvid`、`cid`、`play_time`，再经 `api.bilibili.com/x/player/playurl`（html5 MP4）给一条线路，从 `play_time` 秒开始 | `:452`；`bilibili_api.dart:384-423` |
| 弹幕凭据 | `/xlive/web-room/v1/index/getDanmuInfo`，最多 4 次，第 2、4 次刷新 WBI 密钥；进房只试一次，取不到也先开播 | `:498`、`:526` |
| 扫码登录、账号 | `passport.bilibili.com/x/passport-login/web/qrcode/generate`、`…/poll`，`api.bilibili.com/x/member/web/account` | `:545`、`:559`、`:582` |
| 链接 | `live.bilibili.com/<房间号>`、`www.bilibili.com` 的直播页；`b23.tv` 短链交给解析器逐跳跟随 | `:600`、`:620`、`:625` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/bilibili/bilibili_site.dart`） | 现在 | 说明 |
|---|---|---|---|
| 分类 | `getCategores` `:65` | `getCategories` `bilibili_site.dart:233` | 一致（`shortName` 由 null 改空字符串，3.x 读起来等价） |
| 分区房间 | `:96`，只用签名的 `second/getList` | `:247`，先 `getRoomList` | 3.x 的接口现在对游客每页都回 -352，分区页打不开；2026-10-01 换成不签名的接口（问题 1） |
| 推荐 | `:305` | `:291` | 房间、顺序、字段一致，多了 `totalViewers`（“N 人看过”） |
| 搜索房间 | `:722`，只读 `live_room` | `:328` | 第 1 页在直播间后面追加 `live_user` 里的未开播、轮播主播（3.x 永远搜不到）；封面用 `user_cover`，修掉 3.x 拼出的 `https:https://…` |
| 搜索主播 | `:767` | `:337` | 一致 |
| 详情 | `:632`、`_buildRoom` `:699` | `:377` | 简介去掉 HTML；公告取 `news_info.content`（3.x 写死为空）；出错抛类型化错误，不再返回“当前播放房间的快照” |
| 轮播 | `:699-711` 只认 `live_status == 1`，轮播当未开播 | `LiveStatus.carousel`；游客走轮播视频 | 状态在 2026-09-29 改，播放在 E06.1 做到平台层，界面入口在 E06.2 |
| 取流 | `getPlayQualites` `:132`、`getPlayUrls` `:138` | `:418`、`resolvePlayUrlsRaw` `:434` | 画质列表、线路、实际画质一致；同一组线路只保留一种编码（3.x 遇到 AVC 和 HEVC 同时返回会混在一起）；未开播时报 `StreamUnavailable` 而不是 `FormatException` |
| 开播状态、醒目留言 | `:800`、`:810` | `:400`、`:406` | 一致 |
| 弹幕 | `getDanmaku()` `:26` 直接 new `BiliBiliDanmaku` | `live_danmaku/lib/src/sites/bilibili.dart`，由 `app/platforms.dart` 的弹幕登记表连接 | `live_core` 不依赖弹幕包（D01.2） |
| 链接 | `lib/common/utils/live_url_tool.dart:134`、`:278`、`:305` | `LiveSiteLinks` 混入 `:600-640` | 规则随平台走（E04.1） |

## 结果

- 首次重构（2026-09-28，提交 `d5ed42a5d`）：解析写成纯函数（`BilibiliApi`），请求编排单独一层（`BilibiliSite`）；会话跟着登录 Cookie 走，Cookie 一变就重建；并发请求只取一次 buvid 和密钥。新增的通用能力：`LivePlayLine`（线路自带请求头、格式、编码、线路编号、有效期）、通用 JSON 读取、`normalizeImageUrl`，后面所有平台共用。有意差异 10 条，见 record.md“与 v3 的有意差异”。
- 升级落地（2026-09-29，`12d03ac89`）：轮播单独成状态（UPGRADES 1-1）；开播时间取 `room_info.live_start_time`，搜索的 `live_time` 按北京时间换算；`special_type` 为 1 的在播房间标受限类型 `paid`。
- 国内平台完善（2026-10-01，`81733c1e6`）：用真实接口跑了推荐、分类、分区、搜索、详情、取流、弹幕；修了分区页对游客全部 -352 和搜索卡片分区名带 `<em>` 两个问题；弹幕补了醒目留言撤下、撤回、警告和切断通知。附录 C 落地：在线人数取 `ONLINE_RANK_COUNT`，上舰等礼物上报（弹幕层，D01.2）。
- 平台层余项（2026-10-02，`8d7da2dfc`，E06.1）：游客看轮播走 `getRoundPlayVideo` → `x/player/playurl`，`LivePlayUrlResolution.start` 带上 `play_time`。
- 测试：`packages/live_core/test/sites/bilibili_api_test.dart` 32 个 `test(` 写法、`bilibili_site_test.dart` 30 个（样本逐个对照，部分循环生成）；record.md 最后一次统计本平台 102 个用例（含弹幕）全部通过。

## 验证

- 自动测试：上面两个文件，用 `fixtures/bilibili/` 的样本回放；`S06-*` 逐键对照 3.x 的 `toJson`，有意差异用 `changed:` 列出并写明原因；轮播、付费、开播时间、分区接口回退、b23 短链、扫码都有用例。
- 真实接口：2026-09-30 用本仓库的 `BilibiliSite` 跑过一遍（record.md“真实环境检查”表：推荐、分区、搜索、3 个在播和 1 个未开播房间的详情、6 条线路的开头字节、弹幕 120 秒）。
- 真机：播放和弹幕 K90 看过（2026-10-01，[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）；扫码登录、原画见 [S02 的 CHECKLIST.md](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 6～8 条。轮播播放要等 E06.2 接到界面后再看。

## 留下的问题

- 游客的清晰度列表里有拿不到的档（请求蓝光 400 实际给 250，线路上写明）：候选 D-4，等用户决定界面怎么标。
- 游客收到的礼物是 protobuf 的 `SEND_GIFT_V2`，现在只解析了 JSON 版和上舰：弹幕层候选，归 D01.2。
- 禁言通知（`ROOM_BLOCK_MSG`）没录到样本，附录 C 的 C-3 没做。
- 付费直播间（`special_type` 1）没有真实样本，只按接口含义和网页代码实现；登录后 `getRoomPlayInfo` 对轮播是否给地址没核实。
- 轮播在直播间里的入口和从中途开始播放：[E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/brief.md) 第 1 阶段。
- 接口会变：定期巡检归 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)。
