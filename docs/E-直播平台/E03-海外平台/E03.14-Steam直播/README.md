# E03.14 Steam 直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 27-1～27-7，其中 27-3 受阻）记在 [record.md](record.md)；聊天由 D01.24 接上
- 旧编号：M4.27、M4.U.27、T02c.14
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（封禁、仅订阅者、回放、占位不覆盖）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)（自定义地址经 `LinkParser` 的 `needsResolving`/`resolveUrl`）；聊天 [D01.24](../../../D-弹幕/D01-平台弹幕协议/D01.24-Steam直播弹幕/README.md)（用 `SteamBroadcastDanmakuArgs`）；按档播放在 G 组；3.x 占位值的清理 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md)；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/steambroadcast/`（`steambroadcast_api.dart` 1264 行解析、链接、画质档位，`steambroadcast_site.dart` 527 行请求编排）；应用里在 `apps/pure_live/lib/app/platforms.dart:179` 建适配器、`:231` 建聊天连接；样本 `fixtures/steambroadcast/`（19 组，另有聊天帧 `danmaku/` 和生成 3.x 冻结输出的 `legacy_expected.dart`）

## 目标

把 3.x 的 Steam 直播（Steam 社区 Broadcasts）适配器（`lib/core/site/steambroadcast/` 三个文件共 799 行，用 `package:html` 解析网页、平台层调界面翻译）重构进 `live_core`：热门社区直播目录、目录内筛选的搜索、直播页和 `getbroadcastmpd` 详情、HLS 主列表校验、取流、恢复、链接都和 3.x 一样，匿名、不带 Cookie。修掉 3.x 的媒体问题连带整个房间失败（`hls_url` 主机不在白名单、主列表取不到时连关注刷新都失败）、目录头像全部丢失等问题。升级落地后显示主播真头像、标题和分区改读 `getbroadcastinfo`（游戏名、截图）、认个人资料页和自定义地址、下播后不沿用人数、按主列表列出档位；核实 `user_restricted` 的真实含义是“主播账号被限制直播”，改为封禁。

## 平台接口要点

| 功能 | 接口（`steamcommunity.com`；Chrome UA、`Accept-Language: en-US`、`Referer`，JSON 接口另带 `X-Requested-With`；不跟随跳转、不带 Cookie；一次调用共用 25 秒总时限；以 `steambroadcast` 的名义发出，走代理） | 位置 |
|---|---|---|
| 分类 | 不请求：一个分类 `Steam Broadcasts`，一个分区“热门社区直播”（`community`/`trending`）；目录说明键 `steambroadcast_directory_scope` | `steambroadcast_api.dart:395-405`、`:602`；`steambroadcast_site.dart:170` |
| 目录、推荐 | `apps/allcontenthome?…&browsefilter=trend&appHubSubSection=13&forceanon=1&p=<页>&broadcastsoffset=<(页-1)×10>&numperpage=10`，HTML 片段，每页 10 张 `Broadcast_Card`，用 `HtmlElement` 解析；页尾隐藏表单判断有无下一页；同一主播只留第一张；读不了的卡片只跳过自己 | `steambroadcast_api.dart:563`、`:620`；`steambroadcast_site.dart:177` |
| 卡片 | 标题和分区是游戏名（内容类型去掉 `: Broadcast`），`N viewers` 作在线人数；头像改用同一张图的 `_full.jpg`，Steam 默认头像（hash `fef49e7f…`）算没有（27-1） | `steambroadcast_api.dart:689`、`:1149-1151` |
| 搜索 | Steam id、直播页、个人资料页链接：查这个账号（刷新的两个请求）；自定义地址 `/id/<名字>`：先读 `/id/<名字>/?xml=1` 的 `<steamID64>`；其他关键词只筛请求的那一页目录（10 个，按 id、主播名、标题、游戏） | `steambroadcast_site.dart:222-250`、`:254`；`steambroadcast_api.dart:699`、`:871` |
| 主播名和头像 | 迷你资料 `miniprofile/<账号 id>/json`（账号 id = Steam id − 76561197960265728），失败时退回 3.x 的直播页 `broadcast/watch/<id>`（`og:title`） | `steambroadcast_site.dart:272`；`steambroadcast_api.dart:593`、`:720`、`:752` |
| 关注刷新、开播状态 | 迷你资料 + `broadcast/getbroadcastinfo?steamid&broadcastid=0&location=5`（标题、游戏、截图、`viewer_count`、`is_online`、`is_replay`），失败时退回 `getbroadcastmpd`；两个请求 | `steambroadcast_site.dart:340-371`、`:393`、`:403`；`steambroadcast_api.dart:586`、`:770` |
| 进房、录制详情 | 迷你资料 + `broadcast/getbroadcastmpd?broadcastid=0&steamid&viewertoken=0`（`ready` 直播，`missing_subscription` 仅订阅者，`user_restricted` 封禁，`waiting*` 和不认识的值未知）+ `getbroadcastinfo` + HLS 主列表（变体和音轨要在同一主机、本账号路径、带 `broadcast_origin`，1～16 个）；在播四个请求 | `steambroadcast_site.dart:313`、`:386`；`steambroadcast_api.dart:577`、`:814`、`:835-837`、`:887` |
| 画质 | “自适应 HLS”（`auto`，排第一、默认）；主列表有多个变体时每档一个（`1080p60`、`720p`……，帧率高于 30 才加），档位放在画质的 `data`（`SteamBroadcastVariant`）（27-7） | `steambroadcast_api.dart:435-440`、`:923`、`:937`、`:49-82` |
| 取流 | 线路是进房时校验过的主列表：HLS、编码取自 `CODECS`、线路编号 `steamcontent`、请求头为空、没有租期；不发请求；媒体地址只认 `*.steamcontent.com`；恢复只取 `getbroadcastmpd` 和主列表（两个请求），新主列表没有这一档时改播自适应 | `steambroadcast_site.dart:454-495`；`steambroadcast_api.dart:1029`、`:1048` |
| 聊天参数 | `SteamBroadcastDanmakuArgs(steamId, broadcastId)`，只在进房时给（`getchatinfo` 必须用真实的直播 id） | `steambroadcast_api.dart:354` |
| 链接 | 纯 Steam id、`steamcommunity.com/broadcast/watch/<id>`、`/profiles/<id>` 不发请求；`/id/<名字>` 要一次请求；`www.`、`steam.tv` 不认 | `steambroadcast_api.dart:542`、`:555`；`steambroadcast_site.dart:503-525` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/steambroadcast/`） | 现在 | 说明 |
|---|---|---|---|
| 头像 | `steam_broadcast_api.dart:439-450` 只收 `avatars.akamai.steamstatic.com`，Steam 已换到 fastly，全部丢失；`steam_broadcast_site.dart:87` 用封面顶替 | 主播真头像（184 px） | 3.x 问题 1；27-1 |
| 媒体问题 | `steam_broadcast_api.dart:312-318` 解析时就按取流规则校验 `hls_url`，`:222-230` 预取主列表失败直接抛出：整个房间和关注刷新都失败 | 房间照常，原因记在 `SteamBroadcastRoomData`，取流时报出 | 3.x 问题 2、3 |
| 标题、分区、封面 | `steam_broadcast_api.dart:319-330` 直接进房是占位 `Steam Broadcast`、`Steam Community`，没有封面；关注刷新还会盖掉卡片存下的游戏名 | 读 `getbroadcastinfo` 的游戏名和截图；占位一律留空 | 27-2、统一原则；3.x 的三个占位保留为常量给 J02.1 |
| `user_restricted` | `steam_broadcast_api.dart:308` 当作“受限”，显示状态未知 | 封禁（主播账号被限制直播），关注分组在未开播 | 读 Steam 网页脚本 `broadcast_watch.js` 核实；`missing_subscription` 才是仅订阅者 |
| 下播后的人数 | `steam_broadcast_api.dart:66` 用记住的卡片补人数，不看状态 | 只在直播中且自己没有人数时补 | 27-5 |
| 记住的主播 | `steam_broadcast_site.dart:28` 的 `Map` 只增不删 | 最多 1000 个 | 3.x 问题 9 |
| 链接 | `steam_broadcast_link.dart:30` 只认直播页 | 加个人资料页、自定义地址 | 27-4 |
| 画质 | `steam_broadcast_site.dart:223` 只有 `auto` | `auto` 后跟主列表的各档 | 27-7；按档播放见“留下的问题” |
| 恢复 | 重新进房（直播页、`getbroadcastmpd`、主列表，三个请求） | `getbroadcastmpd`、主列表两个请求 | 恢复不需要主播名 |
| 请求头 | 房间写 `httpHeaders`（`steam_broadcast_site.dart:98`），但播放器、录制器没有 Steam 分支，从未用到 | 线路请求头为空（实测不带也 200） | 3.x 问题 8 |
| 未开播取画质 | `steam_broadcast_site.dart:221` 返回空列表 | `StreamUnavailable` | 3.x 问题 5 |
| 聊天 | `steam_broadcast_site.dart:40` `EmptyDanmaku` | `live_danmaku/lib/src/sites/steambroadcast.dart`（D01.24，日志时钟轮询） | 27-6 |

## 结果

- 首次重构（2026-09-28，提交 `9965e3c7f`）：14 个 3.x 问题、10 条有意差异见 record.md；没有新增通用能力和依赖（网页用 `live_core` 的 `HtmlElement`）。3.x 没有 Steam 的冻结输出，本任务用 `fixtures/steambroadcast/legacy_expected.dart` 把 3.x 三个文件原样搬进脚本，用临时包配置的 `package:html` 生成；补录了直播页、`getbroadcastmpd`、主列表 4 个样本。
- 升级落地（2026-09-29）：27-1、27-2、27-4、27-5 完成，27-6 平台层给参数（加 `broadcastId`），27-7 平台层列档；27-3（国内 CDN）受阻：本机出口在境外只拿到 `steamcontent.com`，测试机在中国大陆直连 Steam 社区接口 TCP 超时，录不到样本。新样本 8 组（迷你资料 3 个、1080p60 四档直播的 `getbroadcastinfo`/`getbroadcastmpd`/主列表、自定义地址和不存在的自定义地址）。画质 id 不需要迁移（`auto` 不变）。
- 请求数：关注刷新仍是 2 个（字节数从约 26 KB 降到约 0.6 KB），在播进房从 3 个变成 4 个，恢复从 3 个变成 2 个。
- 测试：`packages/live_core/test/sites/steambroadcast_api_test.dart` 39 个 `test(` 写法、`steambroadcast_site_test.dart` 27 个；聊天 `packages/live_danmaku/test/sites/steambroadcast_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（两页 20 张卡片、13 个关键词的搜索、26 个链接、`getbroadcastmpd` 的全部变体、8 种直播页、10 种主列表，`changed` 写原因）；迷你资料、`getbroadcastinfo` 的两种退回；封禁、仅订阅者、回放、状态未知的开播状态；只记 1000 个主播；媒体问题不影响房间；S09 选档、恢复保持档位；时间放后 30 天、1 年、5 年都通过。
- 真实接口：归档样本 2026-09-27；补录 2026-09-28 13:05（本机默认出口，不经代理）；升级样本 2026-09-28 20:00 UTC 直连；2026-09-29 在测试机的中国大陆网络下试 27-3，连不上 Steam 社区接口。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只写“完成”）；国内要开代理。

## 留下的问题

- 按档播放没有接上：平台层给的每一档线路都是整个主列表，档位只在画质的 `data`（`SteamBroadcastVariant.selectIn`）里，`live_player`、`live_media` 和应用都没有用它限定变体，选了 `720p` 实际仍按自适应播放、界面却显示 `720p`（record.md 原话“G 接上前不要把档位暴露给界面”）。UPGRADES 27-7 写的是“完成（G01.1）：各档是普通 HLS 线路，播放核心无需改动”，与代码不符：2026-10-07 已改成“部分完成”，按档播放 → [G01.4](../../../G-播放/G01-引擎/G01.4-Steam选清晰度实际仍是自适应/README.md)。录制按档同理（H 组，G01.4 记录里核对）。
- 27-3 国内 CDN 受阻：媒体地址只认 `*.steamcontent.com`，CSP 里的 `broadcast.st.dl.eccdnx.com`、`lv.queniujq.cn` 路径形状不明；从中国大陆 IP 直达 Steam 社区的用户会在取流时报 `ApiChanged`：等有样本再做，没有任务管。
- 回放（`is_replay`）、仅订阅者、主播账号被限制、变体重复或缺分辨率只有合成用例：没有任务管。
- 搜索只筛当前一页目录（Steam 没有匿名直播搜索），同 3.x，不打算改。
- 英文界面里的分区名、公告、目录说明仍是平台层给的中文：归 [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
