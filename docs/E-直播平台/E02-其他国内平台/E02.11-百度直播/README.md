# E02.11 百度直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 30-1～30-10）记在 [record.md](record.md)；聊天由 D01.27 接上
- 旧编号：M4.30、M4.U.30、T02b.11
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)（用 `unknown` 表示受限的平台之一，已改）；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；预告房间显示未开播（UPGRADES A-6）在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md) 确认；聊天 D01.27；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/baidulive/`（`baidulive_api.dart` 1346 行解析和链接，`baidulive_site.dart` 403 行请求编排）；样本 `fixtures/baidulive/`（14 组）

## 目标

把 3.x 的百度直播适配器（`lib/core/site/baidulive/` 三个文件共 995 行）重构进 `live_core`。3.x 最严重的问题是所有 FLV 画质都播不出来（`hls-live.bdstatic.com` 不带 `Referer` 回 403，3.x 写在房间 `httpHeaders` 里的请求头从没发出），而新闻频道默认选中的第一个画质就是 FLV。共修掉 14 个问题；升级落地后画质改成“原画 + 720p/480p”、H.265 单列、已结束的直播能看回放、付费和封禁的直播标直播中。

## 平台接口要点

| 功能 | 接口（匿名，桌面 Chrome 140 UA、`Origin`、`Referer`） | 位置 |
|---|---|---|
| 分类 | 不请求：一个分类“百度直播”，分区是频道；第一次读到推荐流第 1 页前用写死的 7 个频道（推荐 570、购物 574、财经 611、健康 612、教育 613、新闻 575、休闲 616），之后用回答里的 `tab` 块 | `baidulive_site.dart:198` |
| 推荐流 | `POST tiebac.baidu.com/livefeed/feed`（签名表单 `appname=pclive&…&timestamp=<秒>`），每个频道一个会话，第 1 页开新会话，之后只能请求下一页；推荐和“推荐”分区各用一个会话（30-6）；会话内去重 | `:227-279`；`baidulive_api.dart:337` |
| 搜索 | 房间号或房间链接查房间命令；其他关键词没有搜索（只能按房间号查） | `:287-295` |
| 详情 | 房间命令 `GET mbd.baidu.com/searchbox?cmd=371&…`（`data` 是 JSON，含房间号和每次新造的设备号）；`data.371` 为 null、`error_code` 1 或 4 是 `NotFound`；`status` 0 直播、3 已结束（回放）、-1 和 1 预告；预告房间是另一种形状（30-1 时实测） | `:316-333`；`:166` |
| 画质和线路 | “原画”（源流）和每个分辨率一档（720p、480p），同档的格式和 CDN 合成多条线路；`flv-live.bdstatic.com` 用 http（https 证书与主机名不符，30-9）；H.265 带“ · H.265”单列；线路带 UA、`Origin`、`Referer`，没有租期；回放取 `replay_list` 的录像（`p2.bdstatic.com`） | `:350-368` |
| 优先 H.264 | `BaiduLiveSite(preferH264:)` | `app/platforms.dart:182` 传入 |
| 链接 | `live.baidu.com/m/media/pclive/pchome/live.html?room_id=` 等，http 和 https 都认（30-8） | `:391`；`baidulive_api.dart:481` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/baidulive/`） | 现在 | 说明 |
|---|---|---|---|
| FLV 播放 | `baidu_live_site.dart:159`、`baidu_live_api.dart:153-157` 写了 `httpHeaders`，播放层（`playback_header_resolver.dart:143-148`）不发，FLV 全部 403 | 线路自带请求头 | 3.x 问题 1 |
| 挑不出地址 | `baidu_live_api.dart:314-316` 在播房间整个打不开 | 照常进入，取流时说明原因；另读平台现在的 CDN `*.liveshow.lss-user.baidubce.com` | 3.x 问题 2 |
| 画质 | “协议 × 分辨率”（`HLS 720P · AVC`、`FLV 原始线路 · AVC`） | “原画”“720p”“480p” | 30-1；旧 id 有对照（record.md“画质 id 对照”） |
| H.265 | 只读 AVC；源流是 H.265 时“FLV 原始线路 · AVC”实际是 H.264 加 H.265 混在一档 | 单列“ · H.265” | 30-2 |
| 已结束 | 未开播，不能播 | 回放，播放录像 | 30-4 |
| 付费、封禁 | “未知”加限制说明 | 直播中，标 `paid` 或 `unplayable` | 30-5 |
| 推荐会话 | 推荐和“推荐”分区共用会话；同一页再请求返回空并结束 | 各用一个；重放上次的结果 | 30-6 |
| 简介、http 链接 | 不显示；http 链接不认 | 显示 `video.description`；http 也认 | 30-7、30-8 |
| 已结束的人数 | `baidu_live_api.dart:94` 沿用之前卡片的在线人数 | 不沿用 | 3.x 问题 6 |
| 公告和占位 | “百度远端聊天尚待接入；目录 audience_count……”；昵称兜底 `Baidu Live` | 通俗说明；昵称留空 | 30-10 |
| 聊天 | `EmptyDanmaku` | `live_danmaku/lib/src/sites/baidulive.dart`（D01.27，HLS 轮询消息列表） | 新增 |

## 结果

- 首次重构（2026-09-28，提交 `4971f23cc`）：14 个 3.x 问题、10 条有意差异见 record.md；推荐流表单和房间命令的参数与 3.x 逐字相同。
- 升级落地（2026-09-29，`646cd5fd8`）：30-1、30-2、30-4～30-10 完成，30-3 弹幕交给 D01.27；开播时间取房间命令的 `create_time`（只在直播中）；“优先 H.264”。
- 测试：`packages/live_core/test/sites/baidulive_api_test.dart` 46 个 `test(` 写法、`baidulive_site_test.dart` 41 个；聊天 `packages/live_danmaku/test/sites/baidulive_test.dart`。E06.1 的 A-6 引用 `baidulive_site_test.dart` 的“an announced broadcast (S02-room-preview) opens as offline”。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出；线路请求头、http 的 `flv-live`、画质分档和 H.265、回放录像、付费和封禁、两个会话、预告房间。
- 真实接口：2026-09-28 20:55～21:20 UTC 只读请求了 7 个频道的推荐流（64 个房间）和它们的房间命令、60 个在播房间的 FLV 头（57 个 H.264、3 个 H.265）、一个 H.265 房间的全部地址（带和不带 `Referer`）、两场回放录像。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节：只能按房间号查）。

## 留下的问题

- 付费、封禁没有真实样本（64 个房间命令都是 0）；清晰度列表里的 `hevc_flv` 这次没见到，用合成数据测。
- `flv_avc_high`（1080p）没有用；`flv2`、`hls2` 本机解析不到，仍作备用线路。
- 下播后再开播时 `create_time` 会不会更新没见到。
- 默认画质：“优先 H.264”开时应只在 H.264 的档里按比例选（G 组，同映客、TikTok）。
