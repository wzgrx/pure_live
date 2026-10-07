# E03.12 PandaTV

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 25-1～25-12，另按“统一原则”补了受限类型、重播、占位、容错）记在 [record.md](record.md)；聊天由 D01.22 接上
- 旧编号：M4.25、M4.U.25、T02c.12
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（受限类型、开播时间、重播标回放、房间号不分大小写）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕 [D01.22](../../../D-弹幕/D01-平台弹幕协议/D01.22-PandaTV弹幕/README.md)（用 `PandaLiveDanmakuArgs`）；画质 id 对照和存储 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md)；英文界面里的公告和分区名 [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/pandalive/`（`pandalive_api.dart` 1193 行解析、链接和画质，`pandalive_site.dart` 401 行请求编排）；应用里在 `apps/pure_live/lib/app/platforms.dart:177` 建适配器、`:229` 建弹幕连接；样本 `fixtures/pandalive/`（12 组，另有弹幕帧 `danmaku/` 和生成 3.x 冻结输出的 `legacy_expected.dart`）

## 目标

把 3.x 的 PandaTV（팬더티비，韩国）适配器（`lib/core/site/pandalive/` 三个文件共 1078 行，平台层自己管 `HttpClient`、直接调界面翻译）重构进 `live_core`：固定目录、搜索、主播资料、进房、IVS 主列表画质、恢复、链接都和 3.x 一样，匿名、不带 Cookie。重点修掉 3.x 最大的毛病：PandaTV 把“主播不存在、已下播、成人房”放在 HTTP 400 的 JSON 里，3.x 把 400 一律当“格式错误”，处理这些情况的代码从来没有执行过（REG-PANDALIVE-001）。升级落地后加了“新人主播”分区、累计观看、开播时间（韩国时间换算）、分类名称、`/play/` 新地址、“原画”画质名，聊天参数交给弹幕层。

## 平台接口要点

| 功能 | 接口（`api.pandalive.co.kr`，表单 POST；桌面 Chrome UA、`Origin: https://www.pandalive.co.kr`、`Referer` 为请求所代表的页面；不跟随跳转、不带 Cookie；以 `pandalive` 的名义发出，走代理） | 位置 |
|---|---|---|
| 请求头 | API 请求头 `PandaLiveApi.headers`，媒体请求头 `mediaHeaders`（IVS 没有 `Origin` 一律 403，REG-PANDALIVE-003） | `pandalive_api.dart:149`、`:161` |
| 分类 | 不请求：一个分类 PandaTV，两个分区“公开直播”（`public`，3.x）和“新人主播”（`newbj`，25-1）；目录说明键 `pandalive_directory_scope` | `pandalive_api.dart:477`；`pandalive_site.dart:61`、`:109` |
| 目录、推荐 | `/v1/live/index`，表单 `offset=(页码-1)×30&limit=30&orderBy=hot`，新人主播多一个 `onlyNewBj=Y`；页码 1～1000 | `pandalive_api.dart:530`；`pandalive_site.dart:118-129` |
| 卡片 | 只收 `isLive` 为真的行；`playCnt` 作累计观看（25-3）；`startTime` 是韩国时间，换成 UTC 填开播时间（25-12）；分类代码换名称（`ind` 个人直播等，25-8）；`onAirType`/`liveType` 为 `rec` 是重播，标回放 | `pandalive_api.dart:598`、`:294`、`:218`、`:415` |
| 搜索 | 先 `/v1/live/bj_list`（主播，Referer `/search/bj?text=`），再 `/v1/live/index` 加 `orderBy=user&searchVal`（直播），一个接一个；每页直播 ⌈n/2⌉ 条、主播其余，各自最多 50；关键词 2～100 字；第 1 页的关键词是主播 id 时把这位主播挪到第一个，两个搜索都没列出才查 `member/bj`（25-11） | `pandalive_site.dart:171-258`；`pandalive_api.dart:627`、`:635` |
| 主播资料、关注刷新 | `/v1/member/bj`，表单 `userId&info=media`（25-9 去掉从不读的 `fanGrade`）；`media.isLive` 为假时是未开播（25-6） | `pandalive_site.dart:265-277`；`pandalive_api.dart:737`、`:914`、`:921` |
| 进房、录制详情 | `member/bj`；在播时 `/v1/live/play`（`action=watch&userId&password=&shareLinkType=`），能播时再 GET 它给的 IVS 主列表（只能读一次，REG-PANDALIVE-002）；拒绝（`castEnd`、`needAdult`、`needPassword`、`needLogin`）按代码和受限类型处理 | `pandalive_site.dart:290-328`；`pandalive_api.dart:741`、`:776`、`:939` |
| 画质 | 主列表每个视频变体一档：id `<高>p`（50 帧以上加 `60`，重复的加 `_<序号>`），源画质（`VIDEO="chunked"`）叫“原画”排第一（25-5）；纯音频变体跳过；v3 的 `1080p30` 由 `qualityIdFromLegacy` 换成新 id | `pandalive_api.dart:1021`、`:1072`、`:1139` |
| 取流 | 变体播放列表地址，线路编号 `ivs`，带媒体请求头和编码；`PlayLease` 30 分钟续期、`cutsConnection` 为真（REG-PANDALIVE-005）；进房带来的画质不再请求；恢复重新进房（3 个请求） | `pandalive_api.dart:1116`、`:1149`；`pandalive_site.dart:357-394` |
| 聊天参数 | `PandaLiveDanmakuArgs(userId, channel, token)`，`live/play` 接受且在播时放进 `danmakuData`；服务器 `wss://chat-ws.neolive.kr/connection/websocket`（协议见 D01.22） | `pandalive_api.dart:82`、`:242`、`:976` |
| 链接 | `pandalive.co.kr`、`www.`、`m.` 的 `/live/play/<id>`、`/play/<id>`、`/channel/<id>`、`/channel/<id>/home`；没有短链；房间链接写 `/play/<id>`（25-4） | `pandalive_api.dart:284`、`:1159`、`:1169` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/pandalive/`） | 现在 | 说明 |
|---|---|---|---|
| HTTP 400 | `pandalive_api.dart:197-200` 非 200 丢掉正文，当格式错误 | 照常解析 JSON：主播不存在 `NotFound`，已下播是未开播，成人、密码、粉丝专属显示直播中加公告 | 3.x 问题 1；用户以前看到的是加载失败 |
| 按 id 搜索 | `pandalive_site.dart:164-171` 先查 `member/bj`，存在就只返回它；`daisy` 这类不是现存主播的词整个搜索失败 | 先做两个原生搜索，再把这位主播挪到第一个 | 3.x 问题 2；25-11 |
| 新地址 | `pandalive_link.dart:18-27` 不认 `/play/<id>`，房间链接写 `/live/play/`（307 跳转） | 认 `/play/`，房间链接和 Referer 都用 `/play/` | 3.x 问题 17；25-4 |
| 分区 | `pandalive_site.dart:51` 只有 `public` | 加“新人主播” `newbj` | 25-1；3.x 存下的分区照常可用 |
| 累计观看 | `pandalive_site.dart:79` `totalViewers: null` | `playCnt` | 25-3；`audience.dart` 的 PandaTV 一行改为有累计 |
| `member/bj` 表单 | `pandalive_api.dart:379` `info=media fanGrade` | `info=media` | 25-9 |
| 主播在不在播 | `pandalive_api.dart:395-398` 有 `media` 就算直播中 | 看 `media.isLive` | 25-6；进房少一个请求 |
| 纯音频变体 | `pandalive_api.dart:518-520` 没有 `RESOLUTION` 整个房间打不开 | 跳过这一档 | 3.x 问题 6 |
| 画质名 | `pandalive_site.dart:264` `1080p30 · HLS` | “原画”、`720p`…… | 25-5；默认偏好“原画”能直接对上 |
| 有效期 | `pandalive_site.dart:271-281` 没有租期，看一个多小时画面停住 | 线路带 30 分钟的 `PlayLease` | 3.x 问题 13 |
| 请求头 | 播放层 `player/core/playback_header_resolver.dart:192-193` 按平台补；房间带没人读的 `httpHeaders`（`pandalive_site.dart:87`） | 线路自带请求头（值与 3.x 相同） | 3.x 问题 12 |
| 公告和分区名 | `pandalive_site.dart:52`、`:83-86`、`:111-114` 平台层调 `i18n` | 平台层给中文常量，改成看得懂的话（25-7）；英文界面 → Z05.2 | 3.x 问题 14 |
| 聊天 | `pandalive_site.dart:39` `EmptyDanmaku` | `live_danmaku/lib/src/sites/pandalive.dart`（D01.22，Centrifugo） | 25-2 |
| 重播 | 显示直播中 | 标回放，可以播放，关注分组在回放组 | 统一原则；实测目录 132 场里 9 场是 `rec` |

## 结果

- 首次重构（2026-09-28，提交 `c33ee7611`）：18 个 3.x 问题、10 条有意差异见 record.md；没有新增通用能力，主列表用本平台自己的解析（共享的 `HlsMasterPlaylist` 不接受 IVS 主列表里的 `TYPE=VIDEO`）。3.x 没有 PandaTV 的冻结输出，本任务用 `fixtures/pandalive/legacy_expected.dart` 把 3.x 三个文件原样搬进程序生成，连续运行两次逐字节相同。
- 升级落地（2026-09-29）：25-1～25-12 平台层都完成；按统一原则补了受限类型（`isAdult`、`isPw`、`type` → 成人、密码、粉丝专属）、重播标回放、昵称为空不再用 id 顶替、`PlayList` 和主列表里坏项只跳过自己。画质 id 对照和身份迁移规则写给 J02.1（房间身份不变，不用迁移）。
- 之后：聊天由 D01.22 接上；累计观看、开播时间、`/play/` 链接、受限标记在界面上的显示由 C01.1、I04.1、A07.7、A09.1 等完成（见 UPGRADES 25-x 的状态列）。
- 测试：`packages/live_core/test/sites/pandalive_api_test.dart` 60 个 `test(` 写法、`pandalive_site_test.dart` 45 个；聊天 `packages/live_danmaku/test/sites/pandalive_test.dart`。

## 验证

- 自动测试：12 组样本逐键对照 3.x 冻结输出（`changed:` 列出有意差异并写条目号，新字段由 `added` 逐个断言）；请求的方法、地址、表单字段和顺序、Referer、次数与 3.x 对照；400 的三种拒绝、密码房回 `needLogin` + `isPw`、主列表 403/404/看不懂/没有视频；画质命名、排序、旧 id；韩国时间换算；重播；链接（3.x 的 24 个向量）；REG-PANDALIVE-001～003、005。
- 真实接口：样本 2026-09-27 直连录制（匿名）；2026-09-28 19:20～20:05 UTC 直连、匿名实测人气目录翻到底（5 页 132 场）、新人主播、两种搜索、一个密码房的 `member/bj` 和 `live/play`、官网脚本和 `/v1/config/preset`（找分类名，没有找到），最后用新适配器走了一遍进房、取画质、用 v3 的画质 id 取地址并读到变体列表。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只写“完成”，是样本和探针测过）；国内要开代理。

## 留下的问题

- 英文界面里公告、目录说明、分区名（新人主播、个人直播等）仍是平台层给的中文：归 [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)（UPGRADES 25-7、25-8）。应用 `zh.json` 的 `pandalive_directory_scope` 还是旧说法，没有提到“新人主播”，也归 Z05.2 一并核对。
- `ind` 的名称“个人直播”是推断的（官网、脚本、配置接口都没有分类名）；以后找到官方名称改 `PandaLiveApi.areaNames` 一处：没有任务管。
- 粉丝专属（`type` 为 `fan`）没有录到样本，`subscribersOnly` 按归档规格的字段说明判断；重播只认小写 `rec`，含义按标题前缀“[녹]”推断：没有任务管。
- 变体地址的准确有效期（实测 34 分钟可用、87 分钟 403）没有平台说明，租期取 30 分钟：播放续期归 G 组。
- 匿名不能看成人、密码、粉丝专属房（本应用没有 PandaTV 登录）：同 3.x，不打算做。
- 接口会变：没有专门的巡检任务。
