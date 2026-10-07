# E02.6 克拉克拉

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 15-1～15-8）记在 [record.md](record.md)；弹幕由 D01.14 接上
- 旧编号：M4.15、M4.U.15、T02b.6
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)（`audience.dart` 加了克拉克拉）、[E05.2](../../E05-平台框架和模型/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；弹幕 D01.14（用 `KilakilaDanmakuArgs`）；目录说明文字在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md) 第 6 条改写；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/kilakila/`（`kilakila_api.dart` 1093 行解析和分享链接解密，`kilakila_site.dart` 421 行请求编排）；样本 `fixtures/kilakila/`（19 组，含 29 个分享链接向量 `S09-share-vectors`）

## 目标

把 3.x 的克拉克拉适配器（`lib/core/site/kilakila/` 三个文件共 913 行，含 `package:html` 和 `pointycastle` 两个依赖）重构进 `live_core`。房间身份是主播 uid（每场直播的 `roomIdStr` 只在当场有效，REG-KILAKILA-001），官网的加密分享链接照 3.x 解开（REG-KILAKILA-002）。修掉 3.x 的 18 个问题（付费或非直播状态进房直接失败、签名地址没有续期时间、时间线循环翻不到底、带冒号的关键词搜不到等），去掉两个第三方依赖（搜索页用自带的小 HTML 读取器 `_Html`，`kilakila_api.dart:1008`；AES 用 `live_core` 的 `aes.dart`）。

## 平台接口要点

| 功能 | 接口（全部匿名 GET，请求头 `Referer: https://live.kilakila.cn/`、UA `Mozilla/5.0`，不跟随跳转） | 位置 |
|---|---|---|
| 分类 | 不请求：两个时间线 `0` 热门直播、`107` 萌星推荐 | `kilakila_site.dart:112` |
| 推荐、分区 | `live.kilakila.cn/pcLive/timeline?tag=0&type=<0 或 107>&genderType=0&pageNo=&pageSize=`；跨页去重，连续 3 页没有新主播、空页或第 100 页结束（REG-KILAKILA-005） | `:120-157` |
| 搜索 | 官网用户搜索页 `/aboutus/serach/kw/<关键词>[/p/<页>]`（HTML）；uid 或主播页链接查主页；直播页链接或分享链接先 `getRoomInfo` 再查主播；关键词超过 100 个 UTF-16 码元截断 | `:195-262` |
| 详情 | 主页 `live.hongrenshuo.com.cn/Tg/personalH5?uid=`（关注刷新、开播状态 1 个请求）；进房和录制另查当前直播 `live.kilakila.cn/LiveRoom/getRoomInfo?roomId=`；平台说 4 才是直播中，10（已结束）和没有当前直播是未开播 | `:102-105`、`:326-342` |
| 画质和线路 | 一个“原画”（id `original`），FLV、HLS 两条线路：`https://pull.live.hongrenshuo.com.cn/hrs/<直播 id>.flv|.m3u8`，恰好一个 `auth_key`（第一段是到期秒，签发后 30 天），提前 min(10 分钟, 寿命 / 4) 续期，HLS 到期会断；付费（`goldPrice` 大于 0）取流报 `NeedsLogin` | `:354-373` |
| 链接 | 主播页 `/zhubo/<uid>`、`/index/roomuser/uid/<uid 或密文>` 直接得 uid；直播页 `/room/<id 或密文>`、`/PcLive/index/detail?id=` 要请求一次 `getRoomInfo`；密文是 URL 安全 base64 + AES-128-CBC（两把公开密钥依次试）+ MD5 签名 | `:394-410`；`kilakila_api.dart:57-96` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/kilakila/`） | 现在 | 说明 |
|---|---|---|---|
| 状态 | `kilakila_site.dart:50-51`、`:178-191` 只有 4 是直播中，其余“未知” | 10 和没有当前直播是未开播 | 15-1 |
| 进房 | `:194` 用取流模式读详情，付费、非直播、缺地址直接进房失败 | 进房照常，取流时说明原因 | 3.x 问题 2 |
| 人数 | 不显示 | 主页 `onlineNumber` 作在线、`watchNumber` 作累计 | 15-2（REG-KILAKILA-003） |
| 时间线 | `kilakila_api.dart:420-427` 只按 `isLastPage`，热门到 55 页、萌星到 300 页仍有数据 | 去重 + 3 页无新主播或 100 页结束 | 15-3 |
| 搜索 | `:142` 带冒号的关键词当链接；超长关键词报错；直播链接搜不到 | 都能搜 | 3.x 问题 6；15-4、15-5 |
| 画质 | FLV、HLS 两个“画质” | 一个“原画”两条线路 | 15-6；旧 id 用 `KilakilaApi.qualityIdFromLegacy` |
| 进房封面 | `kilakila_api.dart:378-384` 换成 `getRoomInfo` 的默认背景动图 | 沿用主页卡片的 `backPic` | 15-7 |
| 租期 | 没有 `LivePlayLeaseMetadata`，录制拿不到续期时间 | 线路带 `PlayLease` | 3.x 问题 4 |
| 弹幕 | `EmptyDanmaku` | `live_danmaku/lib/src/sites/kilakila.dart`（D01.14，Socket.IO 游客房间） | 15-8 |

## 结果

- 首次重构（2026-09-28，提交 `c50732382`）：18 个 3.x 问题、11 条有意差异见 record.md；冻结输出把 3.x 代码原样复制到临时包里补出；29 个分享链接向量逐个对照。
- 升级落地（2026-09-29，`bfcbb3495`）：15-1～15-7 完成，15-8 平台层核对参数够用；开播时间取主页卡片的 `actualTime`；直播中 `goldPrice` 大于 0 标 `paid`；时间线、搜索页的坏行只跳过这一行；`audience.dart` 加了一行。
- 测试：`packages/live_core/test/sites/kilakila_api_test.dart` 56 个 `test(` 写法、`kilakila_site_test.dart` 38 个；弹幕 `packages/live_danmaku/test/sites/kilakila_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出，15-1、15-2、15-6、15-7 的变化用 `changed:` 列出；AES 标准向量；分享链接 29 个向量；时间线去重和结束规则；付费、已结束、缺地址能进房、取流说明原因。
- 真实接口：2026-09-28 17:40～18:10 UTC 只读请求（热门第 1 页 10 个主播的时间字段和人数、两条时间线翻到底、325 个在播主播的 `goldPrice` 和状态、100 字和 150 字关键词），并用新适配器走了一遍。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）。

## 留下的问题

- 付费直播没有样本（325 个在播主播 `goldPrice` 都是 0）；4、10 以外的状态值没见过，仍是“未知”。
- 时间线内容变化很大（同一天热门有时 42 页只有 100 个不同主播），去重后一页可能为空而 `hasMore` 仍为真，列表页要接着取下一页（I02、I03 的列表）。
- 人数：列表只有累计，“真实在线”模式下列表显示待定，设置页说明在界面层。
- 响应大小上限：3.x 边读边限制 1 MiB，`live_net` 没有逐请求的上限，现在下载完后判定。
