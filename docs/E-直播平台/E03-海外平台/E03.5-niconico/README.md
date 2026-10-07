# E03.5 niconico

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；升级落地（2026-09-29，[UPGRADES](../../../specs/UPGRADES.md) 17-1～17-6，另按统一原则填开播时间、受限类型和“按主播关注”）记在 [record.md](record.md)；评论由 D01.15 接上（17-3）
- 旧编号：M4.17、M4.U.17、T02c.5
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；评论 [D01.15](../../../D-弹幕/D01-平台弹幕协议/D01.15-niconico弹幕/README.md)（用 `NiconicoDanmakuArgs`）；会话型输入的播放和录制在 G01.1、H01.1、H02.1（`live_media` 的配方）；3.x 关注的身份迁移在 J02.1（规则）和 I01.1（启动时的 `IdentityMigration`）；决定 D-001、D-017、D-018（见 [DECISIONS.md](../../../DECISIONS.md)）
- 代码：`packages/live_core/lib/src/sites/niconico/`（`niconico_api.dart` 1195 行解析和观看页读取，`niconico_seat.dart` 296 行观看座位 WebSocket，`niconico_site.dart` 502 行请求编排）；应用里在 `apps/pure_live/lib/app/platforms.dart:168` 建 `NiconicoSite`，`:221` 接评论，`:265-271` 的 `identityResolver` 迁移旧关注；样本 `fixtures/niconico/`（13 组接口样本，3.x 冻结输出在 `legacy_expected.dart`；另有座位会话帧 `seat/S04-seat` 1 组，`danmaku/` 下 4 组评论样本归 D01.15）

## 目标

把 3.x 的 niconico 适配器（`lib/core/site/niconico/` 九个文件共 1241 行，画质目录还反向依赖录制层）重构进 `live_core`：最近节目、在播搜索、观看页详情、观看座位、画质探测、会话型取流都和 3.x 一样。niconico 的播放列表、分片、密钥各要自己路径上的 Cookie（由座位下发），所以取流照 3.x 给“配方”而不是线路。修掉 3.x 的 13 个问题；升级落地后关注改为按主播（`user/<id>`、`ch<号>`），不再是某一场。

## 平台接口要点

| 功能 | 接口（`live.nicovideo.jp`；请求头 `Referer`、UA `Mozilla/5.0`；以 `niconico` 的名义发出，走代理） | 位置 |
|---|---|---|
| 分类和推荐 | 最近节目 `front/api/pages/recent/v1/programs?tab=&offset=<页码-1>&sortOrder=recentDesc`，每页 70 条；目录说明键 `niconico_directory_scope` | `niconico_site.dart:105`、`:149-191`、`:163` |
| 搜索 | `front/api/pages/search/v1/programs?keyword=&status=onair&…`（关键词最多 500 个字符） | `:199-219` |
| 详情 | 观看页 `watch/<身份>`（`<script id="embedded-data">` 的 `data-props`，用私有的 script 标签读取器）；`watch/user/<id>`、`watch/ch<号>` 给这位主播最新一场；`ON_AIR` 直播中，`RELEASED`、`ENDED` 未开播；进房时把座位引导地址保留 60 秒给第一次画质探测（17-6，实测有效期 24 小时） | `:241`、`:253`、`:270-281` |
| 身份 | `NiconicoSite.resolveRoomId('lv…')`：读观看页把节目号换成 `user/<id>` 或 `ch<号>`（给 3.x 关注的迁移用） | `:289` |
| 观看座位 | `NiconicoSeat`：`wss://a.live2.nicovideo.jp/…`，发 `startWatching`，收 `seat`、`stream`（按路径的 13 个 Cookie）、`messageServer`；经 `live_net` 的 `SocketConnector` 按 `niconico` 的代理路由连接 | `niconico_seat.dart:26`、`:162`；`:304-326` |
| 画质探测 | 读观看页 → 开座位 → 用主列表路径的 Cookie 读主列表（5 秒，不跟随跳转）→ 列出画质（`800×450 · 1080800 bps`，id `800x450@1080800`）→ 关座位；最多 30 秒；关座位慢不算失败 | `:346`、`:362-380` |
| 取流 | `LivePlayUrlResolution.owned(NiconicoInputRecipe(节目号, 分辨率, 码率))`，不发请求；播放和录制按配方各自开座位（`live_media`） | `:422-459` |
| 链接 | `live.nicovideo.jp/watch/lv…`（要读一次观看页换成主播）、`http://`、旧手机站 `sp.live.nicovideo.jp`、`nico.ms/lv…`、主播主页、频道页 | `:474-487` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/niconico/`） | 现在 | 说明 |
|---|---|---|---|
| 分层 | `niconico_quality_catalog.dart:7` 从录制服务引入座位工厂和主列表读取器 | 座位和主列表读取都在平台层 | 3.x 问题 1 |
| 房间身份 | 节目号 `lv…`，每场都变，主播下次开播就对不上 | `user/<id>`、`ch<号>` | 17-1；3.x 的 `lv` 关注用 `resolveRoomId` 迁移（record.md“房间身份迁移规则”） |
| 链接 | `niconico_link.dart:7` 只认 `https://live.nicovideo.jp/watch/lv…` | 加 `nico.ms`、旧手机站、主页、频道页 | 17-2 |
| 列表坏行 | `niconico_directory.dart:60-90` 整页失败 | 只跳过这一行 | 17-4 |
| 简介 | 没有 | `program.description` 的纯文本 | 17-5 |
| 观看页请求 | 进房读一次，画质探测又读一次 | 进房的引导地址给第一次探测用 | 17-6 |
| 座位错误 | `niconico_session.dart:204-205` 丢掉错误码 | 按错误码分类（连接太多可重试、没有权限） | 3.x 问题 6 |
| 关座位 | `niconico_quality_catalog.dart:131-137` 关闭握手超过 2 秒整个探测失败 | 不再算失败 | 3.x 问题 9 |
| 频道卡片头像 | `niconico_directory.dart:91-100` 空字符串不退回 | 有头像 | 3.x 问题 7 |
| 受限 | 地区、登录限制在播时显示直播中，取流时报错 | 同 3.x，另填受限类型（付费频道的免费开头是 `none` + `NiconicoRoomData.paid`） | 统一原则 |
| 评论 | `EmptyDanmaku`，公告“弹幕暂未接入” | `live_danmaku/lib/src/sites/niconico.dart`（D01.15，NDGR protobuf 长轮询） | 17-3 |

## 结果

- 首次重构（2026-09-28，提交 `5442c7303`）：13 个 3.x 问题、10 条有意差异见 record.md；座位 Cookie 的过期时间只认 RFC 1123（不依赖 `dart:io`）。
- 升级落地（2026-09-29，`3088ad3e2`）：17-1～17-6 完成（17-3 平台层给参数）；开播时间三处都有（列表 `beginAt`、搜索 `beginTime`、观看页 `program.beginTime`）；身份迁移规则写给 J02.1。
- 测试：`packages/live_core/test/sites/niconico_api_test.dart` 76 个 `test(` 写法、`niconico_site_test.dart` 64 个（样本对照是循环生成的）；评论测试 `packages/live_danmaku/test/sites/niconico_test.dart` 49 个 `test(` 写法，归 D01.15。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（`legacy_expected.dart`）；座位会话帧回放；画质探测的 Cookie 和超时；主播身份、`resolveRoomId`、“a 3.x follow is merged only once migrated”；坏行跳过；简介的纯文本；链接。
- 真实接口：2026-09-28 17:58～18:32 UTC 经本机代理、匿名读了 7 个分区 1～3 页（534 行）、两个关键词搜索（33 行）、6 个观看页（用户、频道、官方节目和它的频道），录了 4 个新样本；同一个座位引导地址在 0～1800 秒内反复开座位都成功（17-6 的依据）。没有做过国内五大平台那样的“真实环境检查”。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节 niconico 一行各列是“完成”“新增”，关注状态“完成（按主播）”，没有“K90 看过”）；要用户开着代理。旧关注换成主播身份的真机核对是 [S02 的 CHECKLIST.md](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 10 条（F-FAV-08，还没填结果）。

## 留下的问题

- 3.x 的 `lv` 关注换成主播身份（17-1）：UPGRADES 写“完成（J02.1 迁移；I01.1 启动时 `IdentityMigration`；关注页 I04.1）”，应用启动时由 `platforms.dart:265-271` 的 `identityResolver` 调 `resolveRoomId` 逐个换（节目已删除的保留原值）；没有在真机上核对（见“验证”）。
- 官方节目没有主播页，仍按节目号 `lv…` 关注，下一场对不上：平台的限制，没有任务管。
- 匿名不能看的节目（私密、付费且没有免费开头、仅关注者）没有样本，按字段名 `isPrivate`、`payment`、`isFollowerOnly` 判断。没有任务管。
- `nico.ms`、旧手机站链接没有实际请求过；同一个用户同时两场在播时 `watch/user/<id>` 给哪一场没核实；自定义名字的频道页 `ch.nicovideo.jp/<名字>` 要多一次请求，没有认。没有任务管。
- 最近节目按开播时间倒序，翻页之间新开播的节目会把行挤到下一页：跨页去重已由列表页做了（`apps/pure_live/lib/shared/rooms/room_feed.dart:479` 按 `identityKey` 去重），平台层不用改。
- UPGRADES 里本平台的 17-1～17-6、附录 B 的 B-11 都已完成，没有“未排”的余项。
- 海外平台在国内要代理，接口改版没有定期巡检任务，没有任务管。
