# E03.3 Picarto

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 11-1～11-9）记在 [record.md](record.md)；恢复时换档的实际画质在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md)（11-1 的 `appliedQuality`）；聊天由 D01.11 接上
- 旧编号：M4.11、M4.U.11、T02c.3
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)（频道名不分大小写）；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；聊天 D01.11；恢复后显示实际清晰度 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/brief.md) 第 5 阶段；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/picarto/`（`picarto_api.dart` 759 行解析和 HLS 主列表，`picarto_site.dart` 325 行请求编排）；样本 `fixtures/picarto/`（16 组）

## 目标

把 3.x 的 Picarto 适配器（`lib/core/site/picarto/` 三个文件共 578 行）重构进 `live_core`：分类、目录（不含成人内容）、搜索、详情、HLS 主列表解析、恢复、链接都和 3.x 一样（匿名，没有 Cookie）。修掉 3.x 的 15 个问题（不存在的频道报“schema”、接口请求不带 UA 而播放器带、站内页面 `/videos` 被当成频道、主播换档后恢复一直失败、一行坏数据整页失败等）。

## 平台接口要点

| 功能 | 接口（`ptvintern.picarto.tv`；请求头 `Referer`、`Origin` 为 `picarto.tv`，加 Chrome 140 UA） | 位置 |
|---|---|---|
| 分类 | `api/languages-categories`，一个分类“Picarto”，第一个分区是“公开直播（不含成人内容）”（就是推荐），后面是平台的分类 | `picarto_site.dart:62-64` |
| 目录 | `api/explore`（按观众数，`filter_params[adult]=false`），每页 30，坏行跳过 | `:72-98` |
| 搜索 | `api/search`（可取消），关键词取前 100 个字符；卡片标题用频道名、简介用 `bio` | `:137-154` |
| 详情 | 频道详情和多人同播列表 `getMultiStreams`；房间号是平台写法（请求 `thebaker` 得到 `TheBaker`），请求时的写法留在 `PicartoChannel.requestedId`；进房和录制在直播中时再取主列表（2 个请求），关注刷新只看频道本身（1 个，11-2）；私密频道照常显示、受限类型 `private`（11-9） | `:226-242` |
| 画质和线路 | 主列表每个视频档一个画质（id 由分辨率、帧率、编码、分组组成，不含码率和主机），名称 `720p 60fps`，整份主列表那一档叫“自动”；先按高度再按码率排（11-4）；线路带 3.x 播放层的请求头、格式、编码，没有租期 | `:252-274` |
| 恢复 | 重新进房；原档位不在新主列表里时改播第一档，`LivePlayUrlResolution.appliedQuality` 给出新档的名称和 id（11-1、E06.1） | `:274` |
| 弹幕参数 | `PicartoDanmakuArgs`：平台写法的频道名、频道 id | |
| 链接 | `picarto.tv/<频道>`；`videos`、`communities`、`subscriptions`、`following`、`shop` 等站内页面不算 | `:321` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/picarto/`） | 现在 | 说明 |
|---|---|---|---|
| 不存在 | `picarto_api.dart:343` `channel: null` 当格式错误 | `NotFound` | 3.x 问题 1 |
| 请求头 | `:31`、`:38` 接口和主列表不带 UA；播放层（`playback_header_resolver.dart:150-151`）却带 Chrome 140 | 都带同一组 | 3.x 问题 3、4 |
| 关注刷新 | `picarto_site.dart:84-85` 也校验取流字段，缺负载均衡节点时刷新失败 | 只看频道本身 | 11-2 |
| 恢复 | `:117-125` 只按 id 找原来的画质，主播换档后一直失败 | 改播最好的一档并报告实际画质 | 11-1 |
| 画质排序 | `picarto_hls.dart:81-91` 只按码率 | 先高度再码率，“HLS Auto”显示“自动” | 11-4 |
| 坏行 | `picarto_api.dart:286-300` 一行不合格整页失败，私密频道的行让整页报无权访问 | 坏行跳过 | 11-3 |
| 封面 | `:356` 自己那一路没有缩略图时清空；未开播没有封面 | 用频道的；未开播用最后一次直播的缩略图 | 3.x 问题 5；11-6 |
| 简介、关注数 | 不读 | 详情带 `descriptions` 和 `followers_count` | 3.x 问题 6 |
| 身份 | 按写法区分，链接的 `thebaker` 和关注的 `TheBaker` 对不上 | 比较不分大小写（`SiteIds.caseInsensitiveRoomIds`） | 11-8 |
| 弹幕 | `EmptyDanmaku` | `live_danmaku/lib/src/sites/picarto.dart`（D01.11，匿名 JWT + JSON WebSocket） | 11-7 |

## 结果

- 首次重构（2026-09-28，提交 `b8bcd1eb3`，当天 `664aaf5b6` 改回 3.x 的房间号写法）：15 个 3.x 问题、12 条有意差异见 record.md；严格校验照 3.x 保留（页码、每页条数、`total` 对不上不给残缺列表）。
- 升级落地（2026-09-29，`f12fb7262`）：11-1～11-9 完成（11-7 交给 D01.11，11-8 只核对）；开播时间只在进房时由公开接口 v1 的 `last_live` 给出（关注刷新要多一个请求，不做）；占位标题 `My Channel Title` 留空。
- 平台层余项（2026-10-02，`8d7da2dfc`，E06.1 c5）：`LivePlayUrlResolution.appliedQuality`，恢复和列表卡片取流换档时填。
- 测试：`packages/live_core/test/sites/picarto_api_test.dart` 52 个 `test(` 写法、`picarto_site_test.dart` 35 个；聊天 `packages/live_danmaku/test/picarto_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出；恢复换档、刷新不看取流字段、坏行跳过、排序、私密频道、站内页面链接。
- 真实接口：2026-09-28 17:10～17:25 UTC 只读请求了目录、详情、公开接口 v1、4 个在播频道的开播时间（和 HLS 分片名的时长对照）、全部 186 个在播频道的详情（找私密频道，没有）、7 个未开播频道的封面。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）；恢复后显示新档名称要等 E06.2 接到界面。

## 留下的问题

- 私密频道没有样本，按字段含义实现；不去试私密直播的主列表（等于绕过访问限制）。
- 开播时间只在进房时有。
- 多年没直播的频道，未开播封面地址打不开（平台仍给，适配器不猜）。
- 恢复后画质按钮显示新档名称：[E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/brief.md) 第 5 阶段。
