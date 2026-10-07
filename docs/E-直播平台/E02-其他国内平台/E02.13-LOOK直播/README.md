# E02.13 LOOK 直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 32-1～32-7）记在 [record.md](record.md)；聊天由 D01.29 接上
- 旧编号：M4.32、M4.U.32、T02b.13
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)（-10 原以为是受限，核实后是禁播）；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；聊天 D01.29；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/looklive/`（`looklive_api.dart` 1021 行解析和 weapi 加密，`looklive_site.dart` 377 行请求编排）；样本 `fixtures/looklive/`（11 组）

## 目标

把 3.x 的网易 LOOK 直播适配器（`lib/core/site/looklive/` 三个文件共 730 行，加密依赖 PointyCastle）重构进 `live_core`：视频推荐、声音推荐、合并目录、搜索、房间、取流都和 3.x 一样（全部匿名，`weapi` 加密的 POST）。修掉 3.x 的 18 个问题，最严重的是推荐从第 2 页起必定失败（视频列表到头时平台回 `itemList: null`，3.x 当成格式错误）。升级落地时读官网脚本核实了 `liveStatus` -10 是禁播（FORBID），不是私密房。

## 平台接口要点

| 功能 | 接口（全部 `POST https://api.look.163.com/weapi/…`，`Origin: https://look.163.com`、`Referer`，20 秒时限） | 位置 |
|---|---|---|
| weapi 信封 | `params`：紧凑 JSON 先用网页 nonce、再用固定密钥做两次 AES-128-CBC（IV `0102030405060708`）再 Base64；`encSecKey` 是 RSA 加密的随机密钥；AES 用 `live_core` 的 `aes.dart` | `looklive_api.dart` |
| 分类 | 一个分类“LOOK 直播”，两个分区“视频直播”“语音直播”，不发请求 | `looklive_site.dart:186` |
| 推荐、分区 | 视频 `/weapi/livestream/homepage/recommend`、声音 `/weapi/livestream/listen/homepage/recommend/list`（载荷 `offset`、`limit`）；分区用平台的 `hasMore`；推荐和不带分区的目录同时请求两个列表的同一页、视频在前、按房间号去重，记住到头的列表之后不再请求（32-1） | `:192-214`；`looklive_api.dart:405-408` |
| 搜索 | 只有第 1 页：房间号（2～18 位）或房间链接查房间；其他关键词在两个列表的第 1 页里按房间号、主播名、标题筛选 | `:222-232` |
| 详情 | `/weapi/livestream/room/get/v3`：`liveStatus` 1 直播、0 和 -1 未开播、-10（FORBID）和 -4（违规整改）封禁；`liveStreamType` 50 且没有地址是仅限 App；`feeInfo.fee` 为真且没有 `sessionKey` 是购票；同一场次的卡片补人数（只在直播中补）；见过的房间最多记 2000 个 | `:290-305`；`looklive_api.dart:411` |
| 画质和线路 | 每个地址一档：`HLS 原始线路`（`hls:source`）在前、`FLV 原始线路`（`flv:source`）在后；地址按 3.x 的白名单校验，不合规的只丢这一路；线路带 `LookLiveApi.mediaHeaders`（32-3） | `:338-358` |
| 聊天地址 | `/weapi/livestream/chat/address`（D01.29 用） | `looklive_api.dart:417` |
| 链接 | `look.163.com` 的直播间链接 | `:376` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/looklive/`） | 现在 | 说明 |
|---|---|---|---|
| 推荐翻页 | `look_live_site.dart:127-130`、`look_live_api.dart:253-257` 视频列表到头回 `itemList: null`，第 2 页起整页失败 | 当作空的最后一页；记住到头的列表 | 3.x 问题 1；32-1 |
| 房间号规则 | 列表接受 1～19 位、链接只认 2～18 位，不一致时抛无类型的 `FormatException` | 不合规的卡片跳过 | 3.x 问题 2 |
| -10 | 显示“未知”，公告“受私密房或账号访问条件限制” | 封禁（官网常量 `FORBID: -10`），-4 同样 | 32-2 |
| 仅限 App | 刷新时总带“请在 LOOK 客户端中观看”；列表认不出 | 按 `liveData.type` 在卡片上就能标出 | 3.x 问题 3、4；32-4 |
| 下播后人数 | 沿用同一场次卡片的热度和在线 | 只在直播中补 | 32-5 |
| 地址白名单 | 一个地址不合规整页或整个进房失败 | 只让那一档不可用 | 32-6 |
| 媒体请求头 | 房间带 `httpHeaders`，播放层没有 LOOK 分支，从不用 | 线路自带 | 32-3 |
| 错误 | 9 种 `LookLiveFailure`，`access` 同时表示 401/403、`code` 424/520、受限 | 类型化 | 3.x 问题 6、7 |
| 聊天 | `EmptyDanmaku` | `live_danmaku/lib/src/sites/looklive.dart`（D01.29，网易云信） | 32-7 |

## 结果

- 首次重构（2026-09-28，提交 `7761b780a`）：18 个 3.x 问题、8 条有意差异见 record.md；补录了视频推荐第 2 页（`itemList: null`）。
- 升级落地（2026-09-29，`fc65a5286`）：32-1～32-6 完成，32-7 由 D01.29 完成；开播时间取 `roomInfo.startTime`（毫秒，只在直播中）；受限类型 `appOnly`、`paid`、`unplayable`；公告改通俗。
- 测试：`packages/live_core/test/sites/looklive_api_test.dart` 37 个 `test(` 写法、`looklive_site_test.dart` 27 个；聊天 `packages/live_danmaku/test/sites/looklive_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出；weapi 信封；`itemList: null`；-10、-4 封禁；卡片的仅限 App；地址不合规只少一档。
- 真实接口：2026-09-28 补录 3 个样本；2026-09-29 读了 LOOK 官网脚本（`LIVE_STATUS_TYPE`、`LIVE_STREAM_TYPE` 常量和直播间页的判断）。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节：只能按房间号查）。

## 留下的问题

- -10、-4、-2、购票的真实房间都没找到（房间号很稀疏），按官网脚本和合成用例测。
- 类型 19（音乐节）、51、`liveType` 不是 1、2 的房间没有样本。
- 搜索只能筛两个推荐列表的第 1 页（平台没有匿名搜索接口）。
