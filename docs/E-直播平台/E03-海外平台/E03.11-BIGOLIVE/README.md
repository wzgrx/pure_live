# E03.11 BIGO LIVE

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 24-1～24-7）记在 [record.md](record.md)；聊天由 D01.21 接上
- 旧编号：M4.24、M4.U.24、T02c.11
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（`SiteIds.caseInsensitiveRoomIds` 加了 `bigo`）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；聊天 [D01.21](../../../D-弹幕/D01-平台弹幕协议/D01.21-BIGOLIVE弹幕/README.md)（用 `BigoDanmakuArgs`）；按配方打开输入、分片解扰在 G 组（播放）和 H01.1（录制）；卡片标“加锁”A09.1，发现页默认隐藏 I02.1、A09.5，翻页共用列表 I02.1、I03.1；决定 D-001、D-017
- 代码：`packages/live_core/lib/src/sites/bigo/`（`bigo_api.dart` 950 行纯解析、网页令牌和分片解扰，`bigo_site.dart` 600 行请求编排）；通用的 `packages/live_core/lib/src/aes.dart` 加了 `AesCbc`（`:166`）；应用在 `apps/pure_live/lib/app/platforms.dart:176` 建适配器；样本 `fixtures/bigo/`（9 组接口录制，另有弹幕帧 `danmaku/` 和生成 3.x 冻结输出的 `legacy_expected.dart`）

## 目标

把 3.x 的 BIGO LIVE 适配器（`lib/core/site/bigo/` 六个文件共 927 行：接口、站点、链接、令牌、解扰、配方；分片解扰和中继写在录制层 `bigo_hls_input.dart`）重构进 `live_core`：公开推荐列表、本地分页和搜索、匿名网页令牌加直播间、会话型取流（配方，不给地址）都和 3.x 一样；修掉 3.x 的 16 个问题里不改界面的那些（http 头像让直播间全部打不开、解扰种子读不到导致根本播不了、刷新得到的房间取画质报错等）。升级落地后封面用直播截图，加锁和付费的直播标受限类型并显示为直播中，关注刷新复用网页令牌，翻页和搜索共用同一份列表，坏行只跳过，链接认子域和片段。

## 平台接口要点

| 功能 | 接口（请求头 3.x 的 `Origin: https://www.bigo.tv`、`Referer`、`User-Agent: Mozilla/5.0`；不跟随跳转；不带 Cookie；一次列表或一次“令牌加直播间”共用 20 秒总时限；以 `bigo` 的名义发出，走代理） | 位置 |
|---|---|---|
| 请求 | `_send`、`_scoped`（20 秒总时限，超时 `NetworkFailure`）；401/403 `RiskControl`，404 `NotFound`，429 `RateLimited`，5xx 和跳转 `NetworkFailure`，结构不符 `ApiChanged`；解析前按 1 MiB 检查 | `bigo_site.dart:86`、`:138-169`；`bigo_api.dart:310-317` |
| 公开列表 | `ta.bigo.tv/official_website/OInterfaceWeb/vedioList/72?tabType=00&fetchNum=10&lang=en&countryCode=US`（实际约 20 个在播房间）；第 1 页（下拉刷新）总是重新请求，之后 30 秒内（`snapshotLifetime`）目录、搜索、推荐共用 | `bigo_site.dart:95`、`:193-243`；`bigo_api.dart:402-432` |
| 分类和目录 | 一个分类 `Bigo Live`，一个分区“公开推荐”（`public`/`72`）；原生目录每页 20 个；推荐和分区按 3.x 切片（条数超过 100 给空）；目录说明键 `bigo_directory_scope` | `bigo_site.dart:129`、`:275-306`；`bigo_api.dart:320-336`、`:386-392`、`:476-492` |
| 卡片 | 房间号是列表的 `bigo_id`；标题 `room_topic`（空时昵称）；封面和头像都是 `cover_m`；`user_count` 是在线人数；开播时间 `time_stamp`（实测是本场开播时间）；`is_locked` 为 1 标 `password` | `bigo_api.dart:432-470` |
| 搜索 | 网页搜索接口不给结果，照 3.x：房间链接和像号码的词查直播间；其余在列表里按昵称和标题筛选，纯字母的词筛不到就当号去查；不存在的号没有结果 | `bigo_site.dart:314-359`；`bigo_api.dart:500-520` |
| 网页令牌 | `sec.bigo.sg/v1/webjs/t` 取服务器时间 → `webjs/status?data=<加密请求>` 取令牌；请求数据是 OpenSSL 格式的 AES-256-CBC（EVP_BytesToKey，网站公开的口令），JSONP 回调名必须一致；刷新和开播状态复用最近用过的令牌 30 分钟（`tokenReuse`） | `bigo_site.dart:103`、`:385-415`；`bigo_api.dart:534-590` |
| 直播间 | `POST getInternalStudioInfo?siteId=<号>&verify=&token=<令牌>`（空正文）；房间号是平台写法的 `clientBigoId`；令牌只有第一次使用给播放列表 `hls_src` 和密码标志 `passRoom`；第一次回答“要求登录”时用同一令牌再问一次 | `bigo_site.dart:431-511`；`bigo_api.dart:618-662` |
| 房间和受限 | 标题 `roomTopic`，头像 `avatar`，封面直播截图 `snapshot`（没有时用头像），分区 `gameTitle`；`alive` 为 1 是直播中（加锁、付费、要求登录也是），受限类型 `password`、`paid`、`needsLogin`、`unplayable`；`BigoRoomData` 记访问权限、`ownerId`、`broadcastId`，不含地址和令牌 | `bigo_api.dart:20-70`、`:685` |
| 画质和配方 | 一档“直播自动”（id `live`），不发请求；取流返回 `LivePlayUrlResolution.owned(BigoInputRecipe(号))`，身份 `bigo:<号>:live`，没有地址也没有租期 | `bigo_site.dart:546-571`；`bigo_api.dart:279`、`:355-358` |
| 取流输入 | 播放和录制按配方各自调用 `resolveInput`：每次新令牌、读直播间，得到媒体列表（`<十六进制>.cubetecn.com:1451/list_…m3u8`）的线路，带 3.x 的请求头 | `bigo_site.dart:584`；`bigo_api.dart:728` |
| 分片解扰 | `BigoHlsProtection`：种子在 `#EXT-X-BIGO-WEB-PROTECTION:` 的属性列表里找 `SEED=`；每个分片前两个 188 字节 TS 包的前 16 字节按种子的 xorshift 流异或还原；不足 376 字节报错 | `bigo_api.dart:773-800` |
| 聊天参数 | 进房和录制的在播房间带 `BigoDanmakuArgs(siteId, ownerId, roomId)`，刷新不带 | `bigo_site.dart:478-480`；`bigo_api.dart:257`、`:713-722` |
| 链接 | `bigo.tv` 和任何子域，片段忽略；`/<号>` 或 `/<两个字母>/<号>`；7 个站点页面不是房间 | `bigo_api.dart:370`、`:739` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/bigo/`） | 现在 | 说明 |
|---|---|---|---|
| 头像 | `bigo_api.dart:448-456` 头像按媒体地址只收 https，录下的 http 头像让进房、刷新、录制、按号搜索全部失败 | 头像收 http(s)，不合规只丢头像 | 3.x 问题 1 |
| 解扰种子 | `bigo_hls_protection.dart:9` 要求 `:SEED=` 紧跟冒号，现在的 `VERSION=1,SEED=…` 读不到，分片原样转发，播不了 | 在属性列表里找 `SEED=` | 3.x 问题 2 |
| 取画质 | 未开播返回空列表；刷新得到的房间报 `mediaUnavailable` | 未开播报 `StreamUnavailable`；各种深度都带 `BigoRoomData`，都能取流 | 3.x 问题 3、9 |
| 封面 | `bigo_site.dart:161-162` 进房后封面和头像是同一张头像 | 直播截图 `snapshot` | 24-1 |
| 加锁、付费 | `bigo_api.dart:382` 解析了 `is_locked` 但没用，进房状态“未知” | 卡片标 `password`；在播的受限房间是直播中，取流说明原因 | 24-2 |
| 令牌 | `bigo_api.dart:252-260` 每次读直播间都重新取（3 个请求） | 刷新和开播状态复用 30 分钟（1 个请求）；进房、录制、取流输入仍取新令牌 | 24-4，实测见 record.md |
| 列表复用 | `bigo_site.dart:45` 带取消令牌就绕过缓存，每翻一页、每次搜索都重新下载 | 第 1 页刷新，之后 30 秒共用 | 24-5 |
| 列表坏行 | 一行不合格（含重复主播）整个列表失败 | 只跳过这一行，重复的只留第一行 | 24-6 |
| 链接 | `bigo_link.dart:14-21` 拒绝片段，只认 `bigo.tv`、`www.bigo.tv` | 任何子域，片段忽略 | 24-7 |
| 房间号大小写 | 区分 | 实测平台不分，`bigo` 加进 `SiteIds.caseInsensitiveRoomIds` | 统一原则的房间身份 |
| 不存在的号 | 当作结构错误，搜索一个列表里没有的词整次失败 | `NotFound`，搜索里算没有结果 | 统一原则的容错 |
| 公告 | “Bigo Live 远端聊天尚待接入；……”等三条开发说明 | 改成看得懂的话；D01.21 后 `chatNotice` 是“列表里的人数是正在观看的人数；进入直播间后，人数随弹幕更新。” | 统一原则的说明文字 |
| 传输和解扰位置 | 全局 HTTP 单例、自己的 1 MiB 流式读取；解扰和媒体请求头在录制层 | 注入 `LiveHttp`；`resolveInput`、`BigoHlsProtection` 由平台层提供，播放和录制共用 | 3.x 问题 5 |
| 聊天 | `bigo_site.dart:42` `EmptyDanmaku` | 平台层给参数，连接在 `live_danmaku/lib/src/sites/bigo.dart`（D01.21） | 24-3 |

## 结果

- 首次重构（2026-09-28，提交 `b336f2d27`）：16 个 3.x 问题、11 条有意差异见 record.md；新增通用能力 `AesCbc`（128/192/256 位 AES-CBC 加密，来自归档 v4），`live_core` 不必引入 PointyCastle；令牌数据与 3.x、OpenSSL 的输出逐字节相同。
- 升级落地（2026-09-29）：24-1～24-7 完成（24-2 的卡片标记和发现页隐藏由 A09.1、I02.1、A09.5 接上；24-3 聊天由 D01.21 完成；24-5 的界面部分由 I02.1、I03.1 接上）；新录 3 个样本（`S03-studio-reused`、`-offline`、`-unknown`）。实测发现 `BigoRoomData.broadcastId`（`roomId`）是主播固定的房间号，不是每场一个。
- 测试：`packages/live_core/test/sites/bigo_api_test.dart` 43 个 `test(` 写法、`bigo_site_test.dart` 40 个（record.md 写的是 60 个和 39 个）；`AesCbc` 另在 `test/aes_test.dart`；聊天 `packages/live_danmaku/test/sites/bigo_test.dart` 归 D01.21。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（`fixtures/bigo/legacy_expected.dart`，3.x 在 http 头像上全部失败，另记一份“头像改成 https”的输出作对照）：20 张卡片、10 种切片、12 个关键词的搜索、两个 JSONP、4 个令牌向量、直播间三种回答、种子和一个加扰包还原成 PAT、23 个链接。升级后另测加锁和付费、9 种坏行、令牌复用和“要求登录”的再问、列表 30 秒共用、子域和片段链接。通用条目 REG-LEASE-005、007、017（恢复重新取令牌、每个会话独立、不导出私有地址）都有测试。
- 真实接口：2026-09-28 19:20～20:25 UTC 经本机代理、匿名、只读：每 2 分钟取一次列表共 30 次（`time_stamp` 是本场开播时间的依据）；15 个国家和地区 × 3 种 `tabType` 共 900 行，`is_locked` 全是 0；同一令牌在 1～60 分钟后反复使用（只有第一次给播放列表）；房间号大小写；不存在的号；未开播的直播间。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只记“完成”）；要用户开着代理；能不能播取决于 G 组的本地中继解扰。

## 留下的问题

- 加锁、付费房间没有真实回答：列表 900 行里没有 `is_locked` 为 1，也没有找到 `passRoom` 为真或 `isPaidShow` 为 `"1"` 的直播间；这类房间在播时 `alive` 是否为 1 没有证据（`alive` 为 0 时照 3.x 显示“未知”）。没有任务管。
- “要求登录”至少有一部分是平台对匿名令牌的临时拒绝；`resolveInput` 遇到时报 `NeedsLogin`，播放器、录制器可以稍等后重试一次（平台层不自动重试），归 G 组和 H01.1，没有单独登记。
- 平台哪天开始校验旧令牌时，刷新会收到“要求登录”，适配器会作废保留的令牌（有测试），不用另做。
- 列表卡片的数字号（`bigo_id`）和进房后平台写法的号是两个身份，关注刷新要按请求时的身份绑定（关注页 I04.1，没有单独登记）。
- 关注刷新的回答没有开播时间和人数，只有列表卡片有；要显示时由界面把卡片的值合并进来，没有任务管。
