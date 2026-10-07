# E02.10 酷狗直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 29-1～29-8）记在 [record.md](record.md)；聊天由 D01.26 接上，PK 对方聊天的弹幕层在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md)（UPGRADES B-16）
- 旧编号：M4.29、M4.U.29、T02b.10
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；聊天 [D01.26](../../../D-弹幕/D01-平台弹幕协议/D01.26-酷狗直播弹幕/README.md)；PK 标签接到界面 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/README.md)（阶段“酷狗 PK”）；英文界面的公告 Z05.2；“优先 H.264”设置在 J01.1、A11.3；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/kugoulive/`（`kugoulive_api.dart` 952 行解析和链接，`kugoulive_site.dart` 372 行请求编排）；样本 `fixtures/kugoulive/`（ls 共 16 项：14 组接口录制，另有 `legacy_expected.dart` 补出 3.x 冻结输出和弹幕样本目录 `danmaku/`）；应用在 `apps/pure_live/lib/app/platforms.dart:181` 建 `KugouLiveSite(http, preferH264: preferH264)`

## 目标

把 3.x 的酷狗直播适配器（`lib/core/site/kugoulive/` 三个文件共 913 行）重构进 `live_core`。修掉 3.x 的 16 个问题：不存在的房间显示成叫“Kugou Live”的假房间、媒体请求从来没带平台请求头、在播却取不到流时整个房间打不开、`_known` 缓存没有上限、手机开播显示“未知”、搜索结果一律“0 在线”等。升级落地时还查明 3.x 当作“受访问范围限制”的 `limitType` 其实是公聊限制，那些房间能正常看。

## 平台接口要点

| 功能 | 接口（匿名，桌面 Chrome 140 UA、`Origin`、`Referer`（`KugouLiveApi.apiHeaders`），不跟随跳转，回答最多 4 MiB） | 位置 |
|---|---|---|
| 分类 | `fanxing.kugou.com/` 首页里带 `title` 的 `/pcindex/category/<id>` 链接，读一次后在适配器生命周期内保留；去掉关注、我看过的等四个个人页；读不到用内置的分区表 | `kugoulive_site.dart:117`、`:122`；`kugoulive_api.dart:221`、`:239`、`:453` |
| 推荐、分区 | `fx1.service.kugou.com/mfanxing-home/h5/cdn/room/index/list`（推荐和“推荐”分区 8000）、`…/list_v4` 加 `cid`（其他分区），查询参数与 3.x 逐字节相同；卡片的状态任何正数都是直播中（29-1） | `kugoulive_site.dart:138-156`；`kugoulive_api.dart:492`、`:523`、`:541` |
| 搜索 | `…/pt_search/pcsearch/v1/type_all.jsonp?keywords=&nums=200,0,0,0`（JSONP），第 1 页请求、第 2 页起 30 秒内用快照在本地切（最多存 8 个关键词）；只在直播中且人数大于 0 时算在线（29-3）；房间号或链接时查房间信息 | `kugoulive_site.dart:58`、`:164`、`:181`、`:208`；`kugoulive_api.dart:642`、`:654` |
| 详情 | `service2.fanxing.kugou.com/roomcen/room/web/cdn/getEnterRoomInfo?roomId=`；不存在（没有昵称且 `kugouId` 为 0）是 `NotFound`；详情不给标题（`publicMesg`、`privateMesg` 是公聊、私聊公告，放进 `notice`，29-2）；开播时间取 `liveSessionId`；关注刷新、开播状态 1 个请求，进房和录制在直播中时加一个取流请求并据此填受限类型 | `kugoulive_site.dart:232`、`:249`、`:266`、`:280-295`；`kugoulive_api.dart:374`、`:687`、`:709`、`:761` |
| 取流 | `…/video/pc/live/pull/mutiline/streamaddr?std_rid=`（3.x 的 10 个参数）：每条线路的 `streamProfiles` 按“协议:码率档:编码:布局”分组（`flv:4:1:2`，名称 `FLV 码率档 4`）；`codec` 2 是 HEVC（`KugouLiveApi.hevcCodec`，依据网站代码，29-8）；`txTime` 十六进制到期秒（约 12 小时），提前 5 分钟续期，不断开；`token` 不再校验格式（29-7）；`code` -1 要登录（`needsLogin`），没有流是 `unplayable` | `kugoulive_site.dart:314-364`；`kugoulive_api.dart:184-194`、`:770`、`:795`、`:863`、`:878`、`:902-926` |
| 优先 H.264 | `KugouLiveSite(preferH264:)`：开时 H.264 的档在前、HEVC 在后，每次取画质时读 | `kugoulive_site.dart:49`；`kugoulive_api.dart:937`；`app/platforms.dart:181` 传入 |
| 链接 | `fanxing.kugou.com/<号>`、`mfanxing.kugou.com/?roomId=`、手机分享页 `mfanxing.kugou.com/staticPub/rmobile/sharePage/…?roomId=`（任何路径上的 `roomId`，29-4）；房间号 3～11 位数字 | `kugoulive_site.dart:371`；`kugoulive_api.dart:243-289` |

聊天（D01.26）：按网页染色（B-15）；PK 时对方房间的聊天带 `LiveMessage.sourceRoomId`（B-16，E06.1 c4），“对方”标记还没接到聊天行。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/kugoulive/`） | 现在（`packages/live_core/lib/src/sites/kugoulive/`） | 说明 |
|---|---|---|---|
| 不存在的房间 | `kugou_live_api.dart:378` `_string(0)` 是 `'0'`，不存在当成存在，搜任何号码都得到假卡片 | `NotFound`，搜索没有结果 | 3.x 问题 1 |
| 媒体请求头 | 写了 `httpHeaders`，但播放层 `player/core/playback_header_resolver.dart` 只给已知平台发，没有酷狗分支 | 线路自带 UA、`Origin`、`Referer` | 3.x 问题 2 |
| “受限” | `kugou_live_api.dart:381` `limitType` 大于 0 显示“未知”、不能播 | 不再读（是公聊限制）；受限类型按取流回答 | 实测 5 个这样的房间都能拉流 |
| 列表状态 | 只认 1；手机开播（6）显示“未知” | 任何正数都是直播中 | 29-1 |
| 详情标题 | `kugou_live_api.dart:397` `publicMesg`（公聊公告），进房后标题变 | 详情不给标题（`mergeFrom` 保留卡片和关注的标题），公告放 `notice` | 29-2 |
| 搜索人数 | `kugou_live_api.dart:509` `viewerNum` 一律 0，显示“0 在线” | 只在直播中且大于 0 时算在线 | 29-3 |
| `token` 校验 | 必须以 `0-<房间号>-` 开头 | 不校验格式 | 29-7 |
| 编码 | 不标 | `codec` 2 标 `hevc`，“优先 H.264”排序 | 29-8 |
| 缓存 | `kugou_live_site.dart:29` `_known` 记下每个见过的房间，没有上限 | 去掉；详情只给房间信息里有的 | 3.x 问题 6 |
| 占位 | `kugou_live_api.dart:396-397`、`:505-506` 昵称、标题空时写 `Kugou Live` | 留空 | 统一原则 |
| 公告 | 开发说明式原文 | 看得懂的中文（`chatNotice`、`restrictedNotice`、`directoryScope`） | 29-6 |
| 聊天 | `EmptyDanmaku` | `packages/live_danmaku/lib/src/sites/kugoulive.dart`（D01.26） | 新增 |

## 结果

- 首次重构（2026-09-28，提交 `f80083fe2`）：16 个 3.x 问题、12 条有意差异见 record.md；查询参数的顺序和编码与 3.x 的 `Uri.replace(queryParameters:)` 逐字节相同。
- 升级落地（2026-09-29，`53adeb466`）：29-1～29-4、29-6～29-8 完成（29-4 的 `fanxing2.kugou.com` 没录到，受阻），29-5 弹幕交给 D01.26；开播时间三处都有（房间信息的 `liveSessionId`、列表的 `livetime`、搜索的 `lastLiveTime`）；“优先 H.264”；关键词搜索的快照；新样本 `S04-room-chatlimit`、`S05-stream-chatlimit` 等。画质 id、身份不变，不用迁移。
- E06.1（2026-10-02）：B-16 弹幕层完成（`LiveMessage.sourceRoomId`、`isFromOtherRoom`）。
- 测试：`packages/live_core/test/sites/kugoulive_api_test.dart` 44 个 `test(` 写法、`kugoulive_site_test.dart` 37 个（record.md 按实际用例统计 84 个：47 + 37）；聊天 `packages/live_danmaku/test/sites/kugoulive_test.dart` 36 个。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（请求逐个对照）；不存在、`limitType` 不影响观看、手机开播、搜索人数、HEVC 档的顺序、分享页链接（3.x 的 31 个链接向量）；把时钟往后推 30 天、1 年、5 年再跑也通过。
- 真实接口：2026-09-28 20:17～20:48 UTC 直连只读请求了推荐 1～4 页（约 200 个房间）的房间信息和取流回答、5 个带 `limitType` 的房间、网站 `RoomService.getInfo` 和房间页脚本。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节酷狗直播一行“播放：完成”“弹幕：新增”，备注“B-16 PK 对方聊天：弹幕层完成（E06.1），‘对方’标记 → E06.2”）。

## 留下的问题

- B-16（UPGRADES 附录 B，部分完成）：PK 时对方房间的聊天在聊天行加“对方”标记 → [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/README.md)（阶段“酷狗 PK”，E06.2 现在暂停）。
- 29-4（UPGRADES 状态“完成”，其中 `fanxing2.kugou.com` 受阻）：没有录到用这个主机的分享链接（只凭能打开房间页不算）；录到后加进 `KugouLiveApi._hosts`（`kugoulive_api.dart:245`）。没有任务管。
- 29-6（UPGRADES，部分完成）：中文界面完成；英文界面仍显示平台层给的中文公告 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
- `codec` 2 是 HEVC 来自网站代码，没录到这样的流（153 个房间全是 `codec` 1）；“要求登录”（`code` -1）只有合成回答。
- 关注里的标题是关注时卡片的 `label`（有些是推荐语，如“距离你附近1公里”），刷新不再更新；3.x 存下的标题是公聊公告，record.md 建议 J02.1 迁移时清空酷狗关注的 `title` 和占位昵称 `Kugou Live`，但 `packages/live_store/lib/src/legacy/` 里没有这条清理，覆盖安装时的核对在 J06.1，没有任务专门管。
- 推荐卡片的开播时间按 `livetime`（最近一次推流），断线重连过的房间比场次开始晚，进房或刷新后改为场次开始。
