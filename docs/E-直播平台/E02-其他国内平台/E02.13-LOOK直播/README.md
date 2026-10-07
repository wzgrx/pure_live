# E02.13 LOOK 直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 32-1～32-7）记在 [record.md](record.md)；聊天由 D01.29 接上
- 旧编号：M4.32、M4.U.32、T02b.13
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（-10 原以为是受限，核实后是禁播）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；聊天 [D01.29](../../../D-弹幕/D01-平台弹幕协议/D01.29-LOOK直播弹幕/README.md)（用 `LookLiveDanmakuArgs`）；卡片“仅限 App”标记在 A09.1；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/looklive/`（`looklive_api.dart` 1021 行解析和 weapi 加密，`looklive_site.dart` 377 行请求编排）；样本 `fixtures/looklive/`（ls 共 11 项：9 组接口录制，另有 `legacy_expected.dart` 补出 3.x 冻结输出和弹幕样本目录 `danmaku/`）；应用在 `apps/pure_live/lib/app/platforms.dart:184` 建 `LookLiveSite(http)`

## 目标

把 3.x 的网易 LOOK 直播适配器（`lib/core/site/looklive/` 三个文件共 730 行，加密依赖 PointyCastle）重构进 `live_core`：视频推荐、声音推荐、合并目录、搜索、房间、取流都和 3.x 一样（全部匿名，`weapi` 加密的 POST）。修掉 3.x 的 18 个问题，最严重的是推荐从第 2 页起必定失败（视频列表到头时平台回 `itemList: null`，3.x 当成格式错误）。升级落地时读官网脚本核实了 `liveStatus` -10 是禁播（FORBID），不是私密房。

## 平台接口要点

| 功能 | 接口（全部 `POST https://api.look.163.com/weapi/…`，`Origin: https://look.163.com`、`Referer`、UA `Mozilla/5.0`，不跟随跳转，每次调用 20 秒，回答最多 2 MiB） | 位置 |
|---|---|---|
| weapi 信封 | `params`：紧凑 JSON 先用网页 nonce、再用固定密钥做两次 AES-128-CBC（IV `0102030405060708`）再 Base64；`encSecKey` 是 RSA 加密的随机密钥（固定值）；AES 用 `live_core` 的 `aes.dart`，不再依赖 PointyCastle | `looklive_api.dart:474-508` |
| 分类 | 一个分类“LOOK 直播”，两个分区“视频直播”“语音直播”，不发请求 | `looklive_site.dart:186`；`looklive_api.dart:351-366`、`:553` |
| 推荐、分区 | 视频 `/weapi/livestream/homepage/recommend`、声音 `/weapi/livestream/listen/homepage/recommend/list`（载荷 `offset`、`limit`，每页 20）；分区用平台的 `hasMore`；推荐和不带分区的目录同时请求两个列表的同一页、视频在前、按房间号去重，记住到头的列表之后不再请求（32-1，第 1 页重来）；`itemList: null` 当作空的最后一页；读不了的条目只跳过这一条（32-6） | `looklive_site.dart:64`、`:141`、`:157`、`:192-214`；`looklive_api.dart:405-408`、`:511`、`:597`、`:628` |
| 搜索 | 只有第 1 页：房间号（2～18 位）或房间链接查房间；其他关键词在两个列表的第 1 页里按房间号、主播名、标题筛选 | `looklive_site.dart:222`、`:232`；`looklive_api.dart:575` |
| 详情 | `/weapi/livestream/room/get/v3`（每种深度 1 个请求）：`liveStatus` 1 直播、0、-1、-2 未开播、-10（FORBID）和 -4（违规整改）封禁（32-2）；卡片和房间的 `liveData.type`/`liveStreamType` 50 且没有地址是仅限 App（`appOnly`，32-4）；`feeInfo.fee` 为真且没有 `sessionKey` 是购票（`paid`）；开播时间 `roomInfo.startTime`（只在直播中）；同一场次的卡片补人数（只在直播中补，32-5）；见过的房间最多记 2000 个 | `looklive_site.dart:16`、`:129`、`:275`、`:282`、`:290-305`；`looklive_api.dart:411`、`:642`、`:678` |
| 画质和线路 | 每个地址一档：`HLS 原始线路`（`hls:source`）在前、`FLV 原始线路`（`flv:source`）在后；地址按 3.x 的白名单校验（`*.live.126.net` 上的 `/live/<32 位十六进制>`），不合规的只丢这一路（32-6），都不合规是 `unplayable`；线路带 `LookLiveApi.mediaHeaders`（32-3）；恢复时重新读房间 | `looklive_site.dart:322`、`:338-363`；`looklive_api.dart:393-402`、`:421-423`、`:752`、`:774`、`:786` |
| 聊天地址 | `/weapi/livestream/chat/address`（D01.29 用） | `looklive_api.dart:417`、`:531` |
| 链接 | `look.163.com/live?id=<房间号>` 等 | `looklive_site.dart:376`；`looklive_api.dart:435`、`:446` |

聊天（网易云信聊天室，匿名游客）归 [D01.29](../../../D-弹幕/D01-平台弹幕协议/D01.29-LOOK直播弹幕/README.md)：进房在直播中时给 `LookLiveDanmakuArgs`。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/looklive/`） | 现在（`packages/live_core/lib/src/sites/looklive/`） | 说明 |
|---|---|---|---|
| 推荐翻页 | `look_live_site.dart:127-130` 合并目录同时请求两个列表，`look_live_api.dart:253-257` 视频列表到头回 `itemList: null` 就报格式错误，第 2 页起整页失败 | 当作空的最后一页；记住到头的列表，不再请求 | 3.x 问题 1；32-1 |
| 房间号规则 | 列表接受 1～19 位、链接只认 2～18 位，不一致时抛无类型的 `FormatException` | 不合规的卡片跳过 | 3.x 问题 2 |
| -10 | `look_live_api.dart:285` 当作受限，显示“未知”，公告“受私密房或账号访问条件限制” | 封禁（官网常量 `FORBID: -10`），-4 同样；-2 未开播 | 32-2 |
| 仅限 App | 刷新时总带“请在 LOOK 客户端中观看”；列表认不出 | 按 `liveData.type` 在卡片上就能标出；有没有地址每种深度都看 | 3.x 问题 3、4；32-4 |
| 下播后人数 | 沿用同一场次卡片的热度和在线 | 只在直播中补 | 32-5 |
| 地址白名单 | 一个地址不合规整页或整个进房失败 | 只让那一档不可用 | 32-6 |
| 媒体请求头 | 房间带 `httpHeaders`，播放层没有 LOOK 分支，从不用 | 线路自带 | 32-3 |
| 错误 | 9 种 `LookLiveFailure`，`access` 同时表示 401/403、`code` 424/520、受限 | 类型化 | 3.x 问题 6、7 |
| 公告 | 开发说明式原文 | `chatNotice`、`bannedNotice`、`appOnlyNotice`、`paidNotice` | 统一原则“说明文字” |
| 聊天 | `look_live_site.dart:40` `getDanmaku()` 是 `EmptyDanmaku` | `packages/live_danmaku/lib/src/sites/looklive.dart`（D01.29） | 32-7 |

## 结果

- 首次重构（2026-09-28，提交 `7761b780a`）：18 个 3.x 问题、8 条有意差异见 record.md；补录了视频推荐第 2 页（`itemList: null`）。
- 升级落地（2026-09-29，`fc65a5286`）：32-1～32-6 完成，32-7 由 D01.29 完成（匿名游客进云信聊天室）；开播时间取 `roomInfo.startTime`（毫秒，只在直播中）；受限类型 `appOnly`、`paid`、`unplayable`；公告改通俗。画质 id、身份不变，3.x 存下的 -10 房间刷新后变为封禁，不用迁移。
- 界面接上：卡片“仅限 App”标记在全部列表都有（A09.1 c7，`cardOf` → `roomMark`）。
- 测试：`packages/live_core/test/sites/looklive_api_test.dart` 37 个 `test(` 写法、`looklive_site_test.dart` 27 个（合计与 record.md 统计的 64 个用例相同）；聊天 `packages/live_danmaku/test/sites/looklive_test.dart` 29 个。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（列表 85 种、房间 39 种修改逐一对照）；weapi 信封；`itemList: null`；-10、-4 封禁、-2 未开播；卡片的仅限 App；地址不合规只少一档；线路请求头；`tools/timeshift/run.sh 30 1825` 的 `live_core` 通过。
- 真实接口：2026-09-28 直连补录 3 个样本；2026-09-29 读了 LOOK 官网脚本（`LIVE_STATUS_TYPE`、`LIVE_STREAM_TYPE` 常量和直播间页的判断），并用 32-3 的请求头取 S01 那场的 HLS 列表和 FLV（都是 200）。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节 LOOK 直播一行：播放“完成”，弹幕“新增”，搜索“只能按房间号查”）。

## 留下的问题

- 搜索说明和适配器不符：适配器对非房间号的关键词会在两个推荐列表的第 1 页里按主播名、标题筛选，但应用的搜索能力表把 LOOK 记为 `roomLookup`（`apps/pure_live/lib/features/search/search_capability.dart:139`，提示“只能用房间号或直播链接查找”），FEATURES.md 第 14 节也写“只能按房间号查”；应改为 `showcaseSnapshot`（“只在平台当前推荐的直播里按昵称筛选”）。没有任务管。
- -10、-4、-2、购票的真实房间都没找到（房间号很稀疏），按官网脚本和合成用例测；`code` 424、555（私密房密码框）的回答形状没录到。
- 类型 19（音乐节）、51、`liveType` 不是 1、2 的房间没有样本；`liveType` 不是 1、2 的房间接口仍照 3.x 报 `ApiChanged`。
- 搜索只能筛两个推荐列表的第 1 页（平台没有匿名搜索接口）。
- 32-1～32-7（UPGRADES）都已完成，本平台没有“未排”或“受阻”的升级项；公告、分区名、画质名是平台层给的中文，英文界面仍显示中文 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
