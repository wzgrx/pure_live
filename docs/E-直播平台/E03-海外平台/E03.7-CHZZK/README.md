# E03.7 CHZZK

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 20-1～20-10）记在 [record.md](record.md)；弹幕由 D01.17 接上
- 旧编号：M4.20、M4.U.20、T02c.7
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕 [D01.17](../../../D-弹幕/D01-平台弹幕协议/D01.17-CHZZK弹幕/README.md)（用 `ChzzkDanmakuArgs`）；分类页 I03.1 直接显示平台的分区；卡片的受限标记 A09.1；英文界面的公告 Z05.2；决定 D-001、D-017
- 代码：`packages/live_core/lib/src/sites/chzzk/`（`chzzk_api.dart` 1112 行纯解析，`chzzk_site.dart` 392 行请求编排）；应用在 `apps/pure_live/lib/app/platforms.dart:171` 建适配器；主列表用共享的 `HlsMasterPlaylist`（E03.5 移植）；样本 `fixtures/chzzk/`（22 组接口录制，另有弹幕帧 `danmaku/` 和生成 3.x 冻结输出的 `legacy_expected.dart`）

## 目标

把 3.x 的 CHZZK 适配器（`lib/core/site/chzzk/` 三个文件共 779 行，自带流式读取的传输层，画质地址没有有效期）重构进 `live_core`：热门目录（游标翻页）、频道搜索、频道和直播详情、HLS 和 LLHLS 两个主列表合并的画质、链接都和 3.x 一样；修掉 3.x 的 15 个问题（游标翻页漏一场、一行坏数据整页失败、地区受限和成人直播取流只报“无媒体”、地址到期只能等断流等）。升级落地后用平台真实的分类和分区房间，进房只读两个接口，识别频道主页链接，公告改成看得懂的话。

## 平台接口要点

| 功能 | 接口（`api.chzzk.naver.com`；请求头桌面 Chrome 140 UA、`Accept: application/json, text/plain, */*`、`Origin`、`Referer: https://chzzk.naver.com/`；不跟随跳转；匿名，不注入 Cookie；以 `chzzk` 的名义发出，走代理） | 位置 |
|---|---|---|
| 请求 | `_get`：401/403 `RiskControl`，404 `NotFound`，429 `RateLimited`，5xx 和跳转 `NetworkFailure`，400、`code` 不是 200、结构不符 `ApiChanged`；正文解析前按 2 MiB 查一次 | `chzzk_site.dart:77-81`；`chzzk_api.dart:214-236`、`:328-338` |
| 分类 | `service/v1/categories/live?size=50`，下一页把 `page.next` 原样作查询，最多 4 页（实测 4 页 200 个分区覆盖九成以上的直播）；一级分类按 `categoryType`：游戏、娱乐、体育、其他；重复的分区只留第一次 | `chzzk_site.dart:106-113`；`chzzk_api.dart:270-280`、`:438-495` |
| 推荐和热门 | `service/v1/lives?size=30`，之后按游标 `concurrentUserCount`、`liveId`（游标不含边界，只要 30 条）；游标对外是 JSON `{"v":人数,"l":liveId}` | `chzzk_site.dart:132-142`、`:196`；`chzzk_api.dart:539-595` |
| 分区房间 | `service/v2/categories/<类型>/<id>/lives?size=30`，翻页同热门；3.x 的“公开热门直播”（`directory/popular`）仍能打开，列出全站热门 | `chzzk_site.dart:202`；`chzzk_api.dart:289`、`:518-539` |
| 按页码取 | 从第 1 页逐页重放到第 N 页（N 最多 20），20 秒内完成，前几页出现过的频道不再出现 | `chzzk_site.dart:154-164`；`chzzk_api.dart:267` |
| 搜索 | `service/v1/search/channels?keyword=&offset=&size=20`：频道搜索，含未开播；关键词超过 100 个字符截断（不切开代理对） | `chzzk_site.dart:208-232`；`chzzk_api.dart:299-306`、`:682-696` |
| 卡片 | 标题 `liveTitle`；封面 `liveImageUrl` 把 `{type}` 换成 480，没有时 `defaultThumbnailImageUrl`；在线人数只在 `cvExposure` 为真时取；图片只收 `pstatic.net`、`akamaized.net` 的 https；开播时间 `openDate` 按韩国时间换成 UTC | `chzzk_api.dart:371-412`、`:645-668` |
| 详情 | `service/v1/channels/<id>`（主播名、头像、简介、粉丝数）和 `service/v3.1/channels/<id>/live-detail`（只用 v3.1，v2 对海外受限的直播报 500）；`OPEN` 直播中，`CLOSE`、`CLOSED` 未开播（以直播详情为准），其他值 `ApiChanged` | `chzzk_site.dart:243-289`；`chzzk_api.dart:741-796`、`:873` |
| 受限和公告 | 地区受限（`krOnlyViewing` 或 `blindType: ABROAD`）→ `regionBlocked`、取流 `RegionBlocked`；成人 → `adult`、取流 `NeedsLogin`；带付费商品 → `paid`；公告顺序地区 → 成人 → 可回看 | `chzzk_api.dart:248-260`、`:424-431`、`:910-924` |
| 画质 | 取画质时同时读 `livePlaybackJson` 里 `HLS`、`LLHLS` 两个主列表；视频变体按 `<高>p`（帧率 50 以上加 `60`）归档，名称 `1080p60 · HLS`，两个主列表的同名档合并成两条线路；纯音频变体跳过；一个主列表失败只少它的线路 | `chzzk_site.dart:295-375`；`chzzk_api.dart:812`、`:945-1011` |
| 取流和租期 | 线路带媒体请求头（UA、`Referer`）、编码（`avc1` → avc）、线路编号 `mediaId`；Akamai 令牌（`hdnts`、`hdntl`，实测约 17 小时）给出 `PlayLease`，提前 10 分钟续，`cutsConnection` 为真；恢复重新进房再读主列表 | `chzzk_site.dart:313-337`；`chzzk_api.dart:310`、`:1024-1075` |
| 弹幕参数 | 进房在播且有 `chatChannelId` 时给 `ChzzkDanmakuArgs(channelId, chatChannelId)` | `chzzk_site.dart:266`；`chzzk_api.dart:169` |
| 链接 | `chzzk.naver.com/live/<32 位十六进制>` 和频道主页 `chzzk.naver.com/<频道号>`（可带一个子页），大写转小写，不发请求 | `chzzk_site.dart:388-391`；`chzzk_api.dart:1090` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/chzzk/`） | 现在 | 说明 |
|---|---|---|---|
| 分类 | `chzzk_site.dart:100-102` 只有一个固定的“公开热门直播” | 平台真实的分类，约 200 个分区；旧分区仍能打开，不用迁移 | 20-1 |
| 游标翻页 | `chzzk_api.dart:204-211` 游标之后要 31 条去掉重复，截掉第 31 条时下一页漏一场 | 只要 30 条；截断时游标指向保留的最后一条 | 3.x 问题 1、20-6 |
| 列表坏行 | 一行不合预期整页目录或搜索失败 | 没有频道号或 `liveId` 的行跳过，其他字段留空 | 3.x 问题 2 |
| 搜索 | `chzzk_api.dart:230` 关键词超过 100 字报错，每页按调用方 | 截断后搜索，每页固定 20 条 | 20-5 |
| 不存在的频道 | 回 200 且 `channelId` 为 null，报 identity | `NotFound` | 3.x 问题 3 |
| 不在播的状态 | `chzzk_site.dart:236` 按频道的 `openLive`，刚下播时显示直播中 | 以 `live-detail` 为准 | 20-7 |
| 进房请求 | `chzzk_site.dart:237` 进房就读两个主列表（4 个请求），主列表失败进房失败 | 进房 2 个请求，取画质时再读主列表（合计仍是 4 个） | 20-9 |
| 取流的原因 | `chzzk_site.dart:270-274` 未开播空列表，地区受限、成人一律 `mediaUnavailable` | `StreamUnavailable`、`RegionBlocked`、`NeedsLogin` | 3.x 问题 5、7 |
| 地区受限 | `chzzk_api.dart:267` 只看 `krOnlyViewing`，列表卡片没有提示 | 也看 `blindType: ABROAD`，卡片带公告和受限类型 | 20-8 |
| 有效期 | 没有租期，只在断流后恢复 | `PlayLease`，令牌到期前 10 分钟续 | 3.x 问题 12 |
| 纯音频变体 | `chzzk_site.dart:205` 高度为 0 整个房间打不开 | 跳过 | 3.x 问题 8 |
| 公告文字 | 开发说明式（“实时 HLS 已启用；独立时光机回看会话纳入下一协议批次。”） | “这场直播在 CHZZK 网页上可以回看，本应用只播放实时画面。”；成人公告同样改写 | 20-10 |
| 链接 | `chzzk_link.dart:13` 只认 `/live/<id>` | 加频道主页 | 20-4 |
| 弹幕 | `chzzk_site.dart:58` `EmptyDanmaku` | 平台层给参数，连接在 `live_danmaku/lib/src/sites/chzzk.dart`（D01.17） | 20-2 |

## 结果

- 首次重构（2026-09-28，提交 `be431b915`）：15 个 3.x 问题、11 条有意差异见 record.md；4 条回归条目 REG-CHZZK-001～004 都有测试（004 当时按 3.x 保留固定目录）。
- 升级落地（2026-09-29）：20-1、20-2（平台层给参数，连接 D01.17）、20-4～20-10 完成；20-3 受阻。按统一原则补了开播时间（韩国时间换成 UTC）、受限类型、容错（一个主列表失败只少它的线路）、成人公告改写。分区身份是“平台 + `categoryId`”，存分区时要保留 `areaType`（J02.1 已知）。
- 测试：`packages/live_core/test/sites/chzzk_api_test.dart` 69 个 `test(` 写法、`chzzk_site_test.dart` 46 个（record.md 写的是 75 个和 46 个）；弹幕 `packages/live_danmaku/test/chzzk_test.dart` 归 D01.17。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（`fixtures/chzzk/legacy_expected.dart`）：热门两页、搜索、频道三个、`live-detail` 五种（在播、未开播、地区受限、成人、不存在）、两个主列表和合并后的画质；升级后另测分类 4 页（194 个分区、去重、坏行）、分区房间、30 条翻页、关键词截断、进房 2 个请求、主列表失败只少线路、租期和续期、频道主页链接。
- 真实接口：2026-09-28 18:40～19:15 UTC 直连、匿名、只读：全站热门 20 页（600 场）、分类翻到底（6 页 228 个分区）、十几个 `live-detail` 和 `live-status`；用新适配器实际走了一遍分类、进房、取画质和地址、地区受限和成人的房间。热门前 6 页 180 场里 10 场地区受限、3 场成人。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只记“完成”）；要用户开着代理。

## 留下的问题

- 20-3 累计观看数：受阻。平台在直播中所有公开接口的 `accumulateCount` 都是 0，下播后才给上一场的数（2026-09-29 实测 600 场）；平台以后给出非 0 值时填进 `totalViewers`、改人数能力表即可。没有任务管（登记在 UPGRADES 20-3）。
- 20-10 英文界面仍显示平台层给的中文公告：Z05.2。
- 付费直播没有见过在播的例子，`paidProduct` 等字段的判断只按字段名；`blindType` 除 `ABROAD` 以外的取值没见过。没有任务管。
- 游标翻页的跨页去重（人数变动把一场直播挤到下一页）留给列表页按房间身份去重（I02.1、I03.1）。
- 令牌到期后是否立即断流没有在真机上看过（线路按会断处理，提前续期）；归 G 组的播放验证，没有单独任务。
