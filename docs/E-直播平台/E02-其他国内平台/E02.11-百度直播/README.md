# E02.11 百度直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 30-1～30-10）记在 [record.md](record.md)；聊天由 D01.27 接上
- 旧编号：M4.30、M4.U.30、T02b.11
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（用 `unknown` 表示受限的平台之一，已改）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；预告房间显示未开播（UPGRADES A-6）在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md) 确认；聊天 [D01.27](../../../D-弹幕/D01-平台弹幕协议/D01.27-百度直播弹幕/README.md)；回放点播在 G02.1、C01.1；“优先 H.264”设置在 J01.1、A11.3；画质 id 迁移在 J02.1；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/baidulive/`（`baidulive_api.dart` 1346 行解析和链接，`baidulive_site.dart` 403 行请求编排）；样本 `fixtures/baidulive/`（ls 共 14 项：12 组接口录制，另有 `legacy_expected.dart` 补出 3.x 冻结输出和弹幕样本目录 `danmaku/`）；应用在 `apps/pure_live/lib/app/platforms.dart:182` 建 `BaiduLiveSite(http, preferH264: preferH264)`

## 目标

把 3.x 的百度直播适配器（`lib/core/site/baidulive/` 三个文件共 995 行）重构进 `live_core`。3.x 最严重的问题是所有 FLV 画质都播不出来（`hls-live.bdstatic.com` 不带 `Referer` 回 403，3.x 写在房间 `httpHeaders` 里的请求头从没发出），而新闻频道默认选中的第一个画质就是 FLV。共修掉 14 个问题；升级落地后画质改成“原画 + 720p/480p”、H.265 单列、已结束的直播能看回放、付费和封禁的直播标直播中。

## 平台接口要点

| 功能 | 接口（匿名，桌面 Chrome 140 UA、`Origin`、`Referer`（`BaiduLiveApi.apiHeaders`），不跟随跳转，回答最多 4 MiB） | 位置 |
|---|---|---|
| 分类 | 不请求：一个分类“百度直播”，分区是频道；第一次读到推荐流第 1 页前用写死的 7 个频道（推荐 570、购物 574、财经 611、健康 612、教育 613、新闻 575、休闲 616），之后用回答里的 `tab` 块 | `baidulive_site.dart:198`、`:204`；`baidulive_api.dart:379`、`:685` |
| 推荐流 | `POST tiebac.baidu.com/livefeed/feed`（签名表单 `appname=pclive&…&timestamp=<秒>`），每个频道一个会话，第 1 页开新会话，之后只能请求下一页；推荐和“推荐”分区各用一个会话，同一会话再要它最后给出的那一页时重放上次的结果（30-6）；会话内去重 | `baidulive_site.dart:125`、`:227-279`、`:396`；`baidulive_api.dart:337`、`:497`、`:507`、`:656` |
| 搜索 | 房间号或房间链接查房间命令；其他关键词没有搜索（只能按房间号查） | `baidulive_site.dart:287`、`:295` |
| 详情 | 房间命令 `GET mbd.baidu.com/searchbox?cmd=371&…`（`data` 是 JSON，含房间号和每次新造的设备号）；`data.371` 为 null、`error_code` 1 或 4 是 `NotFound`；`status` 0 直播、3 已结束（回放）、-1 和 1 预告（另一种形状，显示未开播）；开播时间取 `create_time`（只在直播中）；简介 `video.description`（30-7）；`has_pay_service` 是 `paid`，`is_forbidden_url`、`ban_status` 是 `unplayable`（30-5）；见过的卡片和房间最多记 512 个，补后来回答里没有的字段 | `baidulive_site.dart:87`、`:157`、`:316-333`；`baidulive_api.dart:536`、`:640`、`:777`、`:907` |
| 画质和线路 | “原画”（源流，id `source`）和每个分辨率一档（720p、480p；有清晰度列表的另有 1080p、540p），同档的 FLV、HLS 和两个 CDN 按流名合成多条线路（v3 的主机在前，平台现在的 CDN `*.liveshow.lss-user.baidubce.com` 作备用）；`flv-live.bdstatic.com` 用 http（https 证书与主机名不符，30-9）；H.265 带“ · H.265”单列（id 加 `:hevc`，30-2）；线路带 UA、`Origin`、`Referer`，没有租期；回放取 `replay_list` 的录像（`*.bdstatic.com` 上这个房间的 m3u8），名字用平台的清晰度名，没有时叫“回放”（id `replay`） | `baidulive_site.dart:350-373`；`baidulive_api.dart:941-992`、`:1006`、`:1074`、`:1207`、`:1232`、`:1303`、`:1339` |
| 画质 id 换算 | `BaiduLiveApi.qualityIdFromLegacy`：`flv:0:avc`、`hls:0:avc` → `source`，`<flv|hls>:<高度>:avc` → `<高度>p`；取流也认旧 id | `baidulive_api.dart:960-979` |
| 优先 H.264 | `BaiduLiveSite(preferH264:)`：开时 H.264 的档在前、编码不明的其次、H.265 最后；关时按档位排 | `baidulive_site.dart:56`；`baidulive_api.dart:1290`；`app/platforms.dart:182` 传入 |
| 链接 | `live.baidu.com/m/media/pclive/pchome/live.html?room_id=`、`live.baidu.com/m/room/<号>` 等，http 和 https 都认（30-8） | `baidulive_site.dart:391`；`baidulive_api.dart:439-458` |

聊天（房间命令里 `liveshowstatic.baidu.com` 上的 HLS 消息列表，5 秒轮询）归 [D01.27](../../../D-弹幕/D01-平台弹幕协议/D01.27-百度直播弹幕/README.md)。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/baidulive/`） | 现在（`packages/live_core/lib/src/sites/baidulive/`） | 说明 |
|---|---|---|---|
| FLV 播放 | `baidu_live_site.dart:159`、`baidu_live_api.dart:153-157` 写了 `httpHeaders`，播放层 `player/core/playback_header_resolver.dart` 没有百度分支，不发，FLV 全部 403 | 线路自带请求头 | 3.x 问题 1 |
| 挑不出地址 | `baidu_live_api.dart:314-316` 在播房间整个打不开 | 照常进入，取流时说明原因；每档带平台现在的 CDN 作备用线路 | 3.x 问题 2 |
| 画质 | “协议 × 分辨率”（`HLS 720P · AVC`、`FLV 原始线路 · AVC`） | “原画”“720p”“480p” | 30-1 |
| H.265 | 只读 AVC；源流是 H.265 时“FLV 原始线路 · AVC”实际是 H.264 加 H.265 混在一档 | 单列“ · H.265” | 30-2 |
| 已结束 | 未开播，不能播 | 回放，播放录像；拿不到录像标 `unplayable` | 30-4 |
| 付费、封禁 | “未知”加限制说明 | 直播中，标 `paid` 或 `unplayable` | 30-5 |
| 预告 | 一律报“接口变了” | 未开播 | A-6 |
| 推荐会话 | 推荐和“推荐”分区共用会话；同一页再请求返回空并结束 | 各用一个；重放上次的结果 | 30-6 |
| 简介、http 链接 | 不显示；http 链接不认 | 显示 `video.description`；http 也认 | 30-7、30-8 |
| 已结束的人数 | `baidu_live_api.dart:94` 沿用之前卡片的在线人数 | 不沿用 | 3.x 问题 6 |
| 公告和占位 | “百度远端聊天尚待接入；目录 audience_count……”；昵称兜底 `Baidu Live` | 通俗说明（`chatNotice`、`restrictedNotice`、`directoryScope`）；昵称留空，界面显示平台名 | 30-10 |
| 聊天 | `EmptyDanmaku` | `packages/live_danmaku/lib/src/sites/baidulive.dart`（D01.27） | 新增 |

## 结果

- 首次重构（2026-09-28，提交 `4971f23cc`）：14 个 3.x 问题、10 条有意差异见 record.md；推荐流表单和房间命令的参数与 3.x 逐字相同。
- 升级落地（2026-09-29，`646cd5fd8`）：30-1、30-2、30-4～30-10 完成，30-3 弹幕交给 D01.27；开播时间取房间命令的 `create_time`（只在直播中）；“优先 H.264”；新样本（预告、H.265、清晰度列表、回放）。
- 测试：`packages/live_core/test/sites/baidulive_api_test.dart` 46 个 `test(` 写法、`baidulive_site_test.dart` 41 个（record.md 按实际用例统计 78 个）；聊天 `packages/live_danmaku/test/sites/baidulive_test.dart` 32 个。E06.1 的 A-6 引用 `baidulive_site_test.dart` 的“an announced broadcast (S02-room-preview) opens as offline”。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出；v3 的每个画质经 `qualityIdFromLegacy` 对上一档、那一档最前面的线路就是 v3 的地址；线路请求头、http 的 `flv-live`、画质分档和 H.265、回放录像、付费和封禁、两个会话、预告房间；v3 的 26 个链接向量、10 个媒体地址向量；`tools/timeshift/run.sh 30 1825` 通过。
- 真实接口：2026-09-28 20:55～21:20 UTC 直连只读请求了 7 个频道的推荐流（64 个房间）和它们的房间命令、60 个在播房间的 FLV 头（57 个 H.264、3 个 H.265）、一个 H.265 房间的全部地址（带和不带 `Referer`）、两场回放录像。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节百度直播一行：播放“完成”，弹幕“新增”，搜索“只能按房间号查”）。

## 留下的问题

- 30-10（UPGRADES，部分完成）：中文界面完成，名字为空时显示随界面语言的平台名；英文界面仍显示平台层给的中文公告 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
- 默认画质：record.md 给播放的注意“‘优先 H.264’开时应只在 H.264 的档里按比例选”没有落实：`apps/pure_live/lib/shared/rooms/play_quality.dart:7` 的 `defaultQualityIndex` 只按名字和比例选，不看编码；H.264 的档排在前面，所以偏好“原画”时能选到 H.264，但偏好靠后的档（如“流畅”）按比例可能落到 H.265 的档。没有任务管（可并入 G01.2）。
- 付费、封禁没有真实样本（70 张卡片、64 个房间命令都是 0）；清晰度列表里的 `hevc_flv` 这次没见到，用合成数据测。
- `flv_avc_high`（1080p）没有用；`flv2`、`hls2` 本机解析不到，仍作备用线路。
- 下播后再开播时 `create_time` 会不会更新没见到。
- 3.x 存下的 `Baidu Live` 占位昵称、标题不会自己清掉（record.md 给 J02.1 的可选清理没做，覆盖安装时的核对在 J06.1），没有任务专门管。
