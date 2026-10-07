# E02.10 酷狗直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 29-1～29-8）记在 [record.md](record.md)；聊天由 D01.26 接上，PK 对方聊天在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md)（UPGRADES B-16）
- 旧编号：M4.29、M4.U.29、T02b.10
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；聊天 D01.26；PK 标签接到界面 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/brief.md) 第 3 阶段；HEVC 档在 G 组；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/kugoulive/`（`kugoulive_api.dart` 952 行解析和链接，`kugoulive_site.dart` 372 行请求编排）；样本 `fixtures/kugoulive/`（16 组）

## 目标

把 3.x 的酷狗直播适配器（`lib/core/site/kugoulive/` 三个文件共 913 行）重构进 `live_core`。修掉 3.x 的 16 个问题：不存在的房间显示成叫“Kugou Live”的假房间、媒体请求从来没带平台请求头、在播却取不到流时整个房间打不开、`_known` 缓存没有上限、手机开播显示“未知”、搜索结果一律“0 在线”等。升级落地时还查明 3.x 当作“受访问范围限制”的 `limitType` 其实是公聊限制，那些房间能正常看。

## 平台接口要点

| 功能 | 接口（匿名，桌面 Chrome 140 UA、`Origin`、`Referer`） | 位置 |
|---|---|---|
| 分类 | `fanxing.kugou.com/` 首页里带 `title` 的 `/pcindex/category/<id>` 链接，读一次后在适配器生命周期内保留；去掉关注、我看过的等四个个人页 | `kugoulive_site.dart:117` |
| 推荐、分区 | `fx1.service.kugou.com/mfanxing-home/h5/cdn/room/index/list`（推荐和“推荐”分区 8000）、`…/list_v4` 加 `cid`（其他分区），查询参数与 3.x 逐字节相同 | `:138-156`；`kugoulive_api.dart:496` |
| 搜索 | `…/pt_search/pcsearch/v1/type_all.jsonp?keywords=&nums=200,0,0,0`（JSONP），第 1 页请求、第 2 页起 30 秒内用快照在本地切；房间号或链接时查房间信息 | `:164-181`；`kugoulive_api.dart:642` |
| 详情 | `service2.fanxing.kugou.com/roomcen/room/web/cdn/getEnterRoomInfo?roomId=`；不存在（没有昵称且 `kugouId` 为 0）是 `NotFound`；关注刷新、开播状态 1 个请求 | `:280-295`；`kugoulive_api.dart:688` |
| 取流 | `…/video/pc/live/pull/mutiline/streamaddr?std_rid=`（3.x 的 10 个参数）：每条线路的 `streamProfiles` 按“协议:码率档:编码:布局”分组（`flv:4:1:2`，名称 `FLV 码率档 4`）；`codec` 2 是 HEVC（依据网站代码）；`txTime` 十六进制到期秒（约 12 小时），提前 5 分钟续期，不断开 | `:314-364`；`kugoulive_api.dart:771` |
| 优先 H.264 | `KugouLiveSite(preferH264:)`：开时 H.264 的档在前、HEVC 在后 | `app/platforms.dart:181` 传入 |
| 链接 | `fanxing.kugou.com/<号>`、`mfanxing.kugou.com/?roomId=`、手机分享页 `mfanxing.kugou.com/staticPub/rmobile/sharePage/…?roomId=`（任何路径上的 `roomId`，29-4）；房间号 3～11 位数字 | `:371`；`kugoulive_api.dart:262` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/kugoulive/`） | 现在 | 说明 |
|---|---|---|---|
| 不存在的房间 | `kugou_live_api.dart:378` `_string(0)` 是 `'0'`，不存在当成存在，搜任何号码都得到假卡片 | `NotFound`，搜索没有结果 | 3.x 问题 1 |
| 媒体请求头 | 写了 `httpHeaders`，但播放层（`playback_header_resolver.dart:143-149`）只给已知平台发，酷狗从没带 | 线路自带 UA、`Origin`、`Referer` | 3.x 问题 2 |
| “受限” | `limitType` 大于 0 显示“未知”、不能播 | 不再读（是公聊限制）；受限类型按取流回答（`code` -1 要登录 → `needsLogin`，没有流 → `unplayable`） | 实测 5 个这样的房间都能拉流 |
| 列表状态 | 只认 1；手机开播（6）显示“未知” | 任何正数都是直播中 | 29-1 |
| 详情标题 | `publicMesg`（公聊公告），进房后标题变 | 详情不给标题（界面保留卡片标题），公告放 `notice` | 29-2 |
| 搜索人数 | `viewerNum` 一律 0，显示“0 在线” | 只在直播中且大于 0 时算在线 | 29-3 |
| `token` 校验 | 必须以 `0-<房间号>-` 开头 | 不校验格式 | 29-7 |
| 缓存 | `kugou_live_site.dart:29` `_known` 记下每个见过的房间，没有上限 | 去掉；详情只给房间信息里有的 | 3.x 问题 6 |
| 占位 | 昵称、标题空时写 `Kugou Live` | 留空 | 统一原则 |
| 聊天 | `EmptyDanmaku` | `live_danmaku/lib/src/sites/kugoulive.dart`（D01.26），E06.1 加了 PK 对方聊天（`LiveMessage.sourceRoomId`） | 新增 |

## 结果

- 首次重构（2026-09-28，提交 `f80083fe2`）：16 个 3.x 问题、12 条有意差异见 record.md；查询参数的顺序和编码与 3.x 的 `Uri.replace(queryParameters:)` 逐字节相同。
- 升级落地（2026-09-29，`53adeb466`）：29-1～29-4、29-6～29-8 完成（29-4 的 `fanxing2.kugou.com` 没录到，受阻），29-5 弹幕交给 D01.26；开播时间三处都有（房间信息的 `liveSessionId`、列表的 `livetime`、搜索）；“优先 H.264”；关键词搜索的快照。
- 测试：`packages/live_core/test/sites/kugoulive_api_test.dart` 44 个 `test(` 写法、`kugoulive_site_test.dart` 37 个；聊天 `packages/live_danmaku/test/sites/kugoulive_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（请求逐个对照）；不存在、`limitType` 不影响观看、手机开播、搜索人数、HEVC 档的顺序、分享页链接。
- 真实接口：2026-09-28 20:17～20:48 UTC 只读请求了推荐 1～4 页（约 200 个房间）的房间信息和取流回答、5 个带 `limitType` 的房间、网站 `RoomService.getInfo` 和房间页脚本。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）。PK 对方聊天的“对方”标签要等 E06.2 接到界面。

## 留下的问题

- `codec` 2 是 HEVC 来自网站代码，没录到这样的流（153 个房间全是 `codec` 1）。
- “要求登录”（`code` -1）只有合成回答。
- 关注里的标题是关注时卡片的 `label`（有些是推荐语，如“距离你附近1公里”），刷新不再更新；3.x 存下的标题是公聊公告，建议迁移时清空（J06.1 / J02.1）。
- PK 对方聊天的界面标签：[E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/brief.md)。
