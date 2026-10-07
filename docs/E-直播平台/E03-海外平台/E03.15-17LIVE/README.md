# E03.15 17LIVE

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 33-1～33-7，另按“统一原则”补了受限类型、拉流容错）记在 [record.md](record.md)；弹幕由 D01.30 接上，名字颜色和徽章（B-14）在弹幕层由 E06.1 c7 补上
- 旧编号：M4.33、M4.U.33、T02c.15
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（受限类型、开播时间）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕 [D01.30](../../../D-弹幕/D01-平台弹幕协议/D01.30-17LIVE弹幕/README.md)（Ably，频道名就是房间号）；聊天行显示名字颜色和徽章在 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/README.md) 阶段“名字颜色和徽章”；“优先 H.264”设置在 J01.1、A11.3，画质 id 对照给 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md)；FLV codec 12 的播放在 G 组；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/seventeenlive/`（`seventeenlive_api.dart` 870 行解析、链接、画质，`seventeenlive_site.dart` 309 行请求编排；平台 id 是 `17live`，Dart 文件名和类名不能以数字开头，所以叫 `seventeenlive`）；应用里在 `apps/pure_live/lib/app/platforms.dart:185` 建适配器（传入 `preferH264`）、`:237` 建弹幕连接；样本 `fixtures/17live/`（10 组，另有弹幕帧 `danmaku/` 和生成 3.x 冻结输出的 `legacy_expected.dart`）

## 目标

把 3.x 的 17LIVE（日本、台湾、香港）适配器（`lib/core/site/seventeenlive/` 三个文件共 721 行）重构进 `live_core`：日本区推荐的游标目录、当前直播搜索、`lives/<号>` 详情、四档 FLV 画质和多 CDN 线路、恢复、链接都和 3.x 一样，匿名、不带 Cookie。修掉 3.x 把 HTTP 520 `stream not found` 当“服务故障”（不存在的房间打不开、按房间号搜索整个失败，REG-17LIVE-004）、把 420 参数错误当“限流”、拉流数据一变连关注刷新也失败等问题。升级落地后加台湾、香港区，“标准”改名“原画”，默认播放 H.264 档（避开 FLV codec 12 只有声音或黑屏），拉流一律 https，带冒号的关键词能搜，认 `www.17.live`，显示开播时间，军团限定、付费直播标出受限类型。

## 平台接口要点

| 功能 | 接口（`api-dsa.17app.co`；桌面 Chrome UA、`Origin: https://17.live`；推荐和搜索用日文 `Accept-Language` 和站点根 `Referer`，房间用英文和房间页 `Referer`；不跟随跳转、不带 Cookie；以 `17live` 的名义发出，走代理） | 位置 |
|---|---|---|
| 请求头 | 目录和搜索 `catalogHeaders`，房间 `requestHeaders`，媒体 `mediaHeaders`（拉流主机检查 `Referer`，REG-17LIVE-003） | `seventeenlive_api.dart:283`、`:292`、`:303` |
| 分类 | 不请求：一个分类“地区”（`region`），三个分区日本 `JP`、台湾 `TW`、香港 `HK`（33-1）；目录说明键 `seventeen_directory_scope` | `seventeenlive_api.dart:216-242`；`seventeenlive_site.dart:96` |
| 目录、推荐 | `GET /api/v1/sections?count=20&typeTab=2&region=<区>&cursor=<游标>`；跳过 `TopBanner`、`ArchiveVideo`、`Vod` 区块，只收直播中的房间，一页内去重；按页码的第 N 页（1～20）从第 1 页重放 N 个请求；推荐仍是日本区 | `seventeenlive_site.dart:109-160`；`seventeenlive_api.dart:563`、`:580` |
| 搜索 | 房间号或 17LIVE 链接：`GET /api/v1/lives/<号>`；其他关键词：`GET /api/v1/liveStreams/search?query=`（只有当前直播，一页）；只有 `<scheme>://` 开头的才算网址，`Re:Zero` 照常搜，超过 100 字截断（33-5） | `seventeenlive_site.dart:182-205`；`seventeenlive_api.dart:611-636` |
| 详情 | `GET /api/v1/lives/<号>`：`status` 2 直播中、0 未开播、其他未知；`liveStreamID`、`userInfo.roomID` 要等于房间号；开播时间 `beginTime`（Unix 秒，只在直播中填，33-7）；受限 `premiumContent.premiumType`：1 付费 `paid`、2 军团限定 `subscribersOnly`、其他非 0 `unplayable`，`paymentInfo.paid` 为真是 `none` | `seventeenlive_site.dart:215-245`；`seventeenlive_api.dart:470`、`:485`、`:668`、`:678` |
| 错误 | HTTP 520 `{"errorMessage":"stream not found"}` 是 `NotFound`；420 是 `ApiChanged` | `seventeenlive_api.dart:318` |
| 画质 | `pullURLsInfo.rtmpURLs`（没有时 `rtmpUrls`），每项一个 CDN（腾讯、网宿，最多读 16 个）；四档：原画 `source`（500，3.x 叫“标准”）、增强高清 `enhanced`、高清 `hd`、H.264 `h264`；“优先 H.264”开（默认）时 H.264 排第一，关时原画排第一 | `seventeenlive_api.dart:174-210`、`:709-726`、`:823` |
| 取流 | 每个 CDN 的每个字段一条线路：FLV、线路编号 `tencent`/`wansu`、H.264 档标 `avc`、带媒体请求头、没有租期；地址必须是 `*.17app.co` 上含 `pull-rtmp` 的 `.flv`，http 一律升成 https（33-3）；进房带来的画质不再请求；3.x 的 `standard` 照样能取流 | `seventeenlive_api.dart:789`、`:810`；`seventeenlive_site.dart:266-300` |
| 弹幕参数 | `SeventeenLiveDanmakuArgs(roomId)`，进房和录制详情带，刷新和卡片不带 | `seventeenlive_api.dart:46` |
| 链接 | `17.live`、`www.17.live`（33-6）的 `/live/<号>`、`/<语言>/live/<号>`、`/profile/r/<号>`、`/<语言>/profile/r/<号>`；房间链接写 `https://17.live/en/live/<号>`；没有短链 | `seventeenlive_api.dart:280`、`:837`、`:846` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/seventeenlive/`） | 现在 | 说明 |
|---|---|---|---|
| 状态码 | `seventeenlive_api.dart:259-267` 非 200 丢掉正文，520 当 `service`，420 当限流 | 520 `stream not found` 是 `NotFound`，420 是 `ApiChanged` | 3.x 问题 1、2；REG-17LIVE-004 |
| 地区 | `seventeenlive_api.dart:184` 写死 `region=JP`，没有分类 | 日本、台湾、香港三个分区 | 33-1 |
| 画质名和顺序 | `seventeenlive_site.dart:185-190` 增强高清、高清、H.264、标准 | 原画、增强高清、高清、H.264，“优先 H.264”时 H.264 排第一 | 33-2；“标准”就是主播推的原始流 |
| 拉流协议 | 腾讯 CDN 用 http 照原样 | 一律 https | 33-3；实测两种都出流 |
| 带冒号的关键词 | `seventeenlive_site.dart:164` 用 `hasScheme` 判断，`Re:Zero` 直接返回空 | 只有 `<scheme>://` 才算网址 | 33-5 |
| `www.17.live` | `seventeenlive_link.dart:8-9` 主机必须正好是 `17.live` | 也认 `www.` | 33-6 |
| 开播时间 | 不读 | `beginTime` | 33-7 |
| 受限直播 | 不看 `premiumContent`，军团限定的直播照样播放 | 标受限类型，取流报原因，不绕过官网的锁 | 统一原则；实测香港区军团房间回答里也带地址 |
| 拉流数据异常 | 刷新、开播状态、按房间号搜索也解析拉流地址，跟着失败；直播中没有地址时房间打不开 | 刷新和搜索不读拉流地址；进房照常，取流时报原因；一个坏 CDN 只丢自己 | 3.x 问题 3、6；容错 |
| 未开播取画质 | `seventeenlive_site.dart:203` 返回空列表 | `StreamUnavailable` | 3.x 问题 4 |
| 媒体请求头 | 播放层 `player/core/playback_header_resolver.dart:177-178` 按平台补，房间带没人读的 `httpHeaders` | 线路自带请求头，值相同 | 3.x 问题 12 |
| 弹幕 | `seventeenlive_site.dart:38` `EmptyDanmaku` | `live_danmaku/lib/src/sites/seventeenlive.dart`（D01.30） | 33-4 |

## 结果

- 首次重构（2026-09-28，提交 `0141660c6`）：14 个 3.x 问题、10 条有意差异见 record.md；没有新增通用能力。3.x 没有 17LIVE 的冻结输出，本任务用 `fixtures/17live/legacy_expected.dart` 把 3.x 三个文件原样搬进程序生成。复制样本时发现归档的录制规则漏掉了搜索接口回答里主播的私人账户记录（访问令牌、密码散列、邮箱、电话、设备编号、出口 IP）和连麦区块的观众令牌，已换成同形的合成值；GitHub 上的归档分支 `archive/v4` 仍是原值，是否处理由用户决定。
- 升级落地（2026-09-29）：33-1～33-7 平台层都完成（33-4 只给弹幕参数）；新增设置“优先 H.264”（`preferH264`，默认开，与 8-8、14-5、22-3 共用）；新样本 `S02-sections-hk`（香港区，含军团限定直播）、`S04-live-army`。画质 id 对照：`standard` → `source`，其余不变（`qualityIdFromLegacy`）。
- 之后：D01.30 接上弹幕；E06.1 c7 在弹幕层给出 `LiveMessage.nameColor`、`badges`；设置页“优先 H.264”（J01.1、A11.3）、开播时间显示（C01.1、I04.1）已做。
- 测试：`packages/live_core/test/sites/seventeenlive_api_test.dart` 47 个 `test(` 写法、`seventeenlive_site_test.dart` 38 个；弹幕 `packages/live_danmaku/test/sites/seventeenlive_test.dart`。

## 验证

- 自动测试：8 组样本逐键对照 3.x 冻结输出（画质按对照逐档比较，地址是 3.x 的地址换成 https）；列表行的 12 种跳过规则；`premiumContent` 的 12 种形状；拉流容错；“优先 H.264”开关两种顺序；28 个链接向量；REG-17LIVE-001～004（H.264 档标 `avc`、线路按 CDN 顺序、每条线路带 `Referer`、520 是不存在）。
- 真实接口：归档样本 2026-09-27 直连录制；2026-09-28 20:50～21:01 UTC 经本机代理（出口不在中国大陆）实测三个区的 `sections`、腾讯 CDN 的 https 拉流（原画和 H.264 都读到 FLV 文件头；网宿那时不出流，同 REG-17LIVE-002）、`Re:Zero` 和 150 字的搜索、官网脚本里 `premiumType` 的枚举、香港区军团房间。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只写“完成”）；国内要开代理。

## 留下的问题

- 弹幕的名字颜色和徽章：弹幕层已有（`LiveMessage.nameColor`、`badges`），聊天行还没显示：归 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/README.md) 阶段“名字颜色和徽章”（UPGRADES B-14）。
- 默认画质：3.x 的全局偏好按名字匹配，四个名字都带“ · FLV”对不上；“优先 H.264”开时偏好“蓝光8M”“超清”“流畅”的用户按比例会落到可能是 codec 12 的档，应只在标了 `avc` 的档里选；codec 12 的播放和“优先 H.264”默认值等高通硬解评估：归 G 组（[G01.2](../../../G-播放/G01-引擎/G01.2-高通硬解评估/README.md)）。
- 录制按 `sort` 选档会默认录原画（3.x 录增强高清），原画可能是 codec 12；受限直播录制时取流报 `StreamUnavailable`，要停下而不是反复重试：归 H 组。
- 付费 Premium Live（`premiumType 1`）、`NEW_USER`（3）的直播没有样本，只有合成用例：没有任务管。
- 第 2 页可能出现第 1 页已有的房间（连麦区块），跨页去重留给列表页。
- 归档分支 `archive/v4` 的 17LIVE 样本里仍有主播私人账户记录的原值：等用户决定，没有任务管。
