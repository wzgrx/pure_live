# E02.4 猫耳 FM

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 13-1～13-4）记在 [record.md](record.md)；弹幕由 D01.13 接上
- 旧编号：M4.13、M4.U.13、T02b.4
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)（分区身份带命名空间）、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕 [D01.13](../../../D-弹幕/D01-平台弹幕协议/D01.13-猫耳FM弹幕/README.md)（用这里的 `MissevanDanmakuArgs` 和游客会话地址）；画质 id 迁移在 J02.1；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/missevan/`（`missevan_api.dart` 634 行解析，`missevan_site.dart` 293 行请求编排）；样本 `fixtures/missevan/`（ls 共 16 项：14 组接口录制（含游客会话 `S05-user-info`），另有 `legacy_expected.dart` 补出 3.x 冻结输出和弹幕样本目录 `danmaku/`）；应用在 `apps/pure_live/lib/app/platforms.dart:164` 建 `MissevanSite(http)`；分区图标的拼图表在 `apps/pure_live/lib/features/areas/area_artwork.dart:9`

## 目标

把 3.x 的猫耳适配器（`lib/core/site/missevan/` 两个文件共 534 行，传输本来就可注入）重构进 `live_core`：分类、推荐和分区（原生目录分页）、可取消的搜索、详情（进房、刷新、录制是同一个请求，回答里就有拉流地址）、取流、续期都和 3.x 一样。修掉 3.x 的 10 个问题，最严重的是站点在分类里加了“团播”（`list` 类型），3.x 遇到就整个分类报错。

## 平台接口要点

| 功能 | 接口（全部是 `fm.missevan.com/api/v2/` 的匿名 GET，请求头 `Referer`、`Origin`、UA `Mozilla/5.0`，不跟随跳转，回答超过 1 MiB 是 `ApiChanged`） | 位置 |
|---|---|---|
| 分类 | `meta/data` 的标签页按命名空间分成三组：`catalog` → 分区（配音、音乐、情感、放松、古风）、`list` → 团播、`tag` → 标签（新星）；`areaType` 就是命名空间，`catalog:104` 和 `tag:104` 是两个分区；坏标签页只跳过那一项 | `missevan_site.dart:90`；`missevan_api.dart:112`、`:211` |
| 推荐、分区 | `chatroom/open/list?p=`（分别带 `catalog_id`、`tag_id`、`type`），服务端每页 20 条，回答必须回显页号和条数，超过 `maxpage` 的页必须为空；坏行只跳过这一行 | `missevan_site.dart:101`、`:111`、`:118`；`missevan_api.dart:248`、`:273` |
| 搜索 | `chatroom/search`（可取消），房间号或链接时精确查详情；关键词超过 100 个码点截断后再搜（13-4），含控制字符拒绝；只有 `scheme://主机` 形式才当链接 | `missevan_site.dart:130`、`:144`、`:178`、`:184-190`；`missevan_api.dart:300`、`:346` |
| 详情 | `live/<id>`，回答的房间号必须和请求的一样；同时带拉流地址（放进 `MissevanRoomData`，不存储）；进房时另把 `info.websocket[]` 的 `wss` 地址整理成 `MissevanDanmakuArgs`（只认猫耳自己的主机，没有就用 `wss://im.missevan.com/ws?room_id=`）；关注刷新、录制不带弹幕参数 | `missevan_site.dart:199`、`:215-230`；`missevan_api.dart:373`、`:421` |
| 画质和线路 | 一个“原画”（id `10000`，拉流地址里的 `qn=10000`），FLV 在前、HLS 在后两条线路；地址升级为 https；租期取 `expires`，提前 1 分钟续期；HLS 到期会断（`cutsConnection`），FLV 已建立的连接不断；一个地址不合规只少一条线路；恢复时重新读详情；旧 id `hls`、`flv` 也认 | `missevan_site.dart:240-285`；`missevan_api.dart:509`、`:521`、`:568` |
| 画质 id 换算 | `MissevanApi.qualityIdFromLegacy`：`hls`、`flv` → `10000`，可以重复套用 | `missevan_api.dart:143-146` |
| 游客会话（弹幕用） | `MissevanApi.guestSession` = `fm.missevan.com/api/user/info`，返回 `FM_SESS`（有效 3 天），由弹幕连接自己去取，不存进 CookieVault | `missevan_api.dart:151` |
| 链接 | `fm.missevan.com/live/<id>`；3.x 把 `Re:Zero` 这类带冒号的关键词当成别的平台的链接 | `missevan_site.dart:292`；`missevan_api.dart:587` |

弹幕协议（Brotli 帧、30 秒心跳、`room/statistics` 的真实在线人数）归 [D01.13](../../../D-弹幕/D01-平台弹幕协议/D01.13-猫耳FM弹幕/README.md)；`packages/live_core/lib/src/audience.dart:271` 猫耳的在线人数已改成 `roomRealtime`（只在直播间里由弹幕更新）。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/missevan/`） | 现在（`packages/live_core/lib/src/sites/missevan/`） | 说明 |
|---|---|---|---|
| 分类 | `missevan_api.dart:168-170` 遇到 `catalog`、`tag` 以外的类型整个分类报错；`:197` 目录只认这两个命名空间；一个“猫耳 FM”组 | 支持团播，分三组 | 3.x 问题 1、2；13-3 |
| 画质 | `missevan_site.dart:109`：`HLS`、`FLV` 两个“画质”，HLS 在前 | 一个“原画”两条线路，FLV 在前 | 13-1 |
| 搜索 | `missevan_site.dart:65`、`:89` 带冒号的关键词当链接；超长关键词报“搜索失败” | 正常搜索；截断到 100 个字符 | 3.x 问题 3；13-4 |
| 未开播取流 | `missevan_site.dart:111` 返回空列表；`:120-135` 恢复时已下播报“画质不可用” | `StreamUnavailable` | 3.x 问题 4、5 |
| 错误 | `MissevanException`，5xx 和 `code` 不为 0 都是 `service` | 5xx 为 `NetworkFailure`，404 和 500030004 为 `NotFound`，其他 `ApiChanged` | 3.x 问题 7、10 |
| 列表的坏行 | 整页报错 | 只跳过这一行（全是坏行仍报错） | 统一原则“容错” |
| 封面 | 站点给没有封面的房间填默认图 `static.maoercdn.com/avatars/icon01.png`，3.x 照显示 | 留空（`MissevanApi.placeholderCover`），不覆盖关注里存下的封面 | 统一原则“占位信息” |
| 开播时间 | 不显示 | `status.open_time`（毫秒，只在在播时） | 统一原则 |
| 弹幕 | `missevan_site.dart:38` `getDanmaku()` 是 `EmptyDanmaku` | `packages/live_danmaku/lib/src/sites/missevan.dart`（D01.13） | 13-2 |

## 结果

- 首次重构（2026-09-28，提交 `8674cb62f`）：10 个 3.x 问题、7 条有意差异见 record.md；解析保持 3.x 的严格程度（回显页号、`status.open` 只能 0 或 1、回答超过 1 MiB 是 `ApiChanged`）。
- 升级落地（2026-09-29，`08da2f33c`）：13-1 一个“原画”两条线路；13-2 平台层给出弹幕参数（弹幕在 D01.13）；13-3 分类分三组；13-4 超长关键词截断；开播时间取 `status.open_time`；在播且地址可用的详情受限类型 `none`。请求数没有变化（测试里断言了）。
- 测试：`packages/live_core/test/sites/missevan_api_test.dart` 38 个 `test(` 写法、`missevan_site_test.dart` 27 个（record.md 按实际用例统计 71 个：44 + 27）；弹幕 `packages/live_danmaku/test/missevan_test.dart` 55 个。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（分类另附“去掉团播后”的 3.x 输出逐字段对照）；画质两条线路与 3.x 的地址和租期逐字节一致；旧画质 id 对照；关键词截断（中文、emoji）；REG-MISSEVAN-001～005 都有测试。
- 真实接口：2026-09-29 凌晨（北京时间）直连用新适配器实际请求（分类三组 5、1、1 个分区，推荐 22 个房间，团播 20 个，在播房间两条线路租期约 2 小时，进房带弹幕参数，160 个字符的关键词截断后 20 个结果）；同日读完推荐全部 22 页，发现第 1 页的 2 个推广位会在第 3、7 页再出现（适配器不去重）。超长关键词的实测没有录成样本。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节猫耳 FM 一行“播放：完成”“弹幕：新增”，指样本和探针测过）。

## 留下的问题

- 13-1～13-4（UPGRADES）都已完成，本平台没有“未排”或“受阻”的升级项。
- 推荐的推广位跨页重复：列表页按房间身份去重（I02.1、I03.1 的列表），适配器不另存状态。
- 流是 AAC 加 16×16 的 H.264 占位画面，平台层不标纯音频，播放器按实际轨道处理（G01.1）。
- 团播分区图标 `tuanbo.png` 是不是上下两态的拼图没核实，`area_artwork.dart:9` 的拼图表里没有它，现在按普通图片居中显示：没有任务管。
- 分类名“分区”“团播”“标签”（`MissevanApi.namespaceNames`）是平台层给的中文，英文界面仍显示中文 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
- 付费、私密、密码房：公开回答里没有这类状态，受限类型只填 `none`。
