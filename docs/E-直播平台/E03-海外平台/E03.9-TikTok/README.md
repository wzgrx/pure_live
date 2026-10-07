# E03.9 TikTok

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 22-1～22-8）记在 [record.md](record.md)；评论弹幕 22-7 由 D01.19 调查后受阻
- 旧编号：M4.22、M4.U.22、T02c.9
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕 [D01.19](../../../D-弹幕/D01-平台弹幕协议/D01.19-TikTok弹幕/README.md)（受阻：要签名）；同档 FLV、HLS 两条线路互为备用 G01.1、G02.1；“优先 H.264”设置 J01.1、A11.3，硬解评估 G01.2；直播间说明受限原因 C01.1，录制 H02.1；画质 id 迁移 J02.1；决定 D-001、D-017
- 代码：`packages/live_core/lib/src/sites/tiktok/`（`tiktok_api.dart` 964 行纯解析和链接规则，`tiktok_site.dart` 352 行请求编排）；应用在 `apps/pure_live/lib/app/platforms.dart:174` 建适配器（传入 `preferH264`），弹幕表里没有登记（`:190-195` 的说明）；样本 `fixtures/tiktok/`（4 组接口录制，另有生成 3.x 冻结输出的 `legacy_expected.dart`；没有弹幕样本）

## 目标

把 3.x 的 TikTok 适配器（`lib/core/site/tiktok/` 三个文件共 803 行）重构进 `live_core`：TikTok 没有匿名目录和搜索，照 3.x 只做“按用户名或链接精确找房间”，进房时读 `streamData` 和 `hevcStreamData` 两个容器的流；修掉 3.x 的 18 个问题里能不改界面的那些（美区 CDN 的直播进不去、没有流时进房失败、`bytevc1` 让房间失败、`/t/` 短链不认等）。升级落地后受限直播显示为直播中并标受限类型，同档 FLV、HLS 合成一个画质的两条线路，默认优先 H.264，画质名用平台的叫法，搜索框里的短链能跟随跳转，用不到的字段放宽检查。

## 平台接口要点

| 功能 | 接口（两个匿名 GET；请求头 Chrome 140 UA、`Accept`、`Accept-Language: en-US`、`Origin`、`Referer`；不跟随跳转；20 秒期限；不带 Cookie；以 `tiktok` 的名义发出，走代理） | 位置 |
|---|---|---|
| 请求 | `_get`/`_head`；401/403 和空回答 `RiskControl`，404 和业务码 19881007 `NotFound`，420/429 `RateLimited`，5xx `NetworkFailure`，400、格式和未知业务码 `ApiChanged`；12 MiB 上限 | `tiktok_site.dart:78-93`；`tiktok_api.dart:256-259`、`:323`、`:801` |
| 用户的直播 | `www.tiktok.com/api-live/user/room/?aid=1988&sourceType=54&staleTime=600000&uniqueId=<用户名>`，`Referer: https://www.tiktok.com/@<用户名>/live`；房间号是小写用户名 | `tiktok_site.dart:116`；`tiktok_api.dart:313`、`:361-437` |
| 直播间号换主播 | `webcast.tiktok.com/webcast/room/info/?aid=1988&room_id=<直播间号>`（`share/live` 链接用） | `tiktok_site.dart:129`；`tiktok_api.dart:318-319`、`:474-480` |
| 目录和推荐 | 没有：匿名的目录接口都要签名或登录，目录永远为空，常驻目录说明 `tiktok_directory_scope`，不发请求 | `tiktok_site.dart:69`、`:141-150` |
| 搜索 | 只有第 1 页：用户名（带不带 `@`）、主页或直播页链接 1 个请求；`share/live` 链接 2 个请求；短链先读跳转（最多 3 次），再查找 | `tiktok_site.dart:155-201`；`tiktok_api.dart:294`、`:490` |
| 状态和受限 | `liveRoom.status`（没有时 `user.status`）2 直播、4 未开播、其他未知；受限另算：`user.secret` → `private`，`liveSubOnly` 为 1 → `subscribersOnly`，`paidEvent.paid_type` 大于 0 → `paid`，状态仍是直播中；开播时间 `liveRoom.startTime` | `tiktok_api.dart:451-465` |
| 卡片 | 昵称、标题（为空用昵称）、头像 `avatarLarger`（不合格时看下一个字段）、封面 `coverUrl`、简介、粉丝数；在线 `userCount`、累计进房 `enterCount`；分区固定“TikTok LIVE” | `tiktok_api.dart:262`、`:361-431` |
| 流 | 只在进房和录制、直播中且没有受限时读；`streamData` 和 `hevcStreamData` 的 `pull_data.stream_data`、`sdk_params` 都是字符串里的 JSON，两层解码；编码看 `VCodec`（`bytevc1` 算 H.265）；只有声音的 `ao` 不要；坏地址、坏档、坏容器只丢自己，记在 `TikTokRoomData.skipped` | `tiktok_api.dart:706-776`、`:826`、`:918-924` |
| 画质 | 按“编码 + 档位”分，id `h264:origin`；名字 `origin` 叫“原画”，否则用平台 `options.qualities[].name`（`720p`、`1080p60`），H.265 加“ · H.265”；“优先 H.264”开时 H.264 全部在前；旧 id `h264:origin:flv` 仍能取流 | `tiktok_site.dart:262-263`；`tiktok_api.dart:271-281`、`:543-632` |
| 取流 | 一个画质 FLV 线路在前、HLS 在后，线路编号 `flv`、`hls`；带 3.x 的媒体请求头；可信主机 `tiktokcdn.com`、`tiktokv.com`、`byteoversea.com`、`tiktokcdn-us.com`、`tiktokcdn-eu.com`；租期按地址的 `expire`（签发后约 14 天），提前 1 小时续，过期不断开已建立的连接 | `tiktok_site.dart:266-292`；`tiktok_api.dart:298`、`:333`、`:640-689` |
| 不能播时 | 受限、未开播、未知、直播中却没有流都报 `StreamUnavailable`（受限写明需要关注、订阅或付费）；流都坏了报 `ApiChanged`；已知不能播的卡片不发请求 | `tiktok_api.dart:515-526` |
| 链接 | 主页 `/@<用户名>`、直播页 `/@<用户名>/live`（`tiktok.com`、`www`、`m`）直接得到；`share/live/<15～25 位直播间号>` 经 `room/info`；短链 `vm.tiktok.com`、`vt.tiktok.com`、`www.tiktok.com/t/<码>` 读一次跳转 | `tiktok_api.dart:148-225`；`tiktok_site.dart:332` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/tiktok/`） | 现在 | 说明 |
|---|---|---|---|
| 美区 CDN | `tiktok_api.dart:496-497` 可信主机没有地区 CDN，样本 `@qvc` 进房、录制都报 `schema` | 加 `tiktokcdn-us.com`、`tiktokcdn-eu.com` | 3.x 问题 1 |
| 没有流的直播 | `tiktok_site.dart:89-95` 进房整个失败 | 进房照常，取流报 `StreamUnavailable`；录制详情照 3.x 报错 | 3.x 问题 2 |
| 取画质 | `tiktok_site.dart:168` 未开播、受限返回空列表；没有进房数据的房间报 `identity` | 报原因，不发请求；没有进房数据先进房一次 | 3.x 问题 3、4 |
| 受限直播 | `tiktok_api.dart:249-254`、`tiktok_site.dart:69` 显示“封禁”，进房提示“服务器错误,请稍后获取” | 直播中 + `private`/`subscribersOnly`/`paid`，取流说明谁能看 | 22-1 |
| 画质 | `tiktok_site.dart:155-162` 中文档位名加分辨率、编码、协议，FLV、HLS 各一个画质（样本 14 个） | 同档两条线路（样本 7 个），名字用平台的叫法 | 22-2、22-4 |
| 默认编码 | `tiktok_api.dart:374` 先比档位，最好的档是 H.265 时它是默认 | 设置“优先 H.264”（默认开），H.265 只供手动选 | 22-3 |
| 编码名 | `tiktok_api.dart:459-461` 只认 `avc`、`hevc`、`h264`、`h265` | `bytevc1` 算 H.265 | 3.x 问题 7 |
| 搜索框里的短链 | `tiktok_site.dart:129-131` 没有结果 | 跟随跳转后查找 | 22-5 |
| `/t/` 短链 | `tiktok_link.dart` 短链只认 `vm`、`vt` | 也认 `www.tiktok.com/t/<码>` | 3.x 问题 9 |
| 字段检查 | 用不到的字段（`verified`、`secUid`、`signature`、`streamId`）形状不对整个房间打不开，一处坏流整个 `ApiChanged` | 只影响名片的字段留空；身份、状态、受限字段仍严格；坏流只丢自己 | 22-6、统一原则的容错 |
| 公告 | `tiktok_site.dart:76` “TikTok LIVE 远端聊天尚待接入；……” | “TikTok 直播的评论暂时不能在这里显示。……” | 统一原则的说明文字 |
| 弹幕 | `tiktok_site.dart:38` `EmptyDanmaku` | 仍没有弹幕，弹幕表不登记，界面照 3.x 提示一次未接入 | D01.19 受阻 |

## 结果

- 首次重构（2026-09-28，提交 `1ea332247`）：18 个 3.x 问题、10 条有意差异见 record.md；3.x 不收美区 CDN，所以冻结输出另做了一份把主机写成 `tiktokcdn.com` 的 `trustedHosts` 对照。
- 升级落地（2026-09-29）：22-1～22-6 完成（22-1 的直播间说明由 C01.1、录制由 H02.1 接上；22-2 的换线由 G01.1、G02.1 接上；22-3 的设置由 J01.1、A11.3 接上，硬解评估余 G01.2）；22-7 弹幕在 D01.19 受阻；22-8 推荐和分区受阻。按统一原则补了开播时间、受限类型、公告文字。
- 弹幕 22-7（D01.19，受阻）：平台层给出的只有本场的直播间号 `TikTokRoomData.liveRoomId`（`tiktok_api.dart:106-108`，即 `user.roomId`，也是 IM 用的 `room_id`），在进房和录制的 `data` 里。没有弹幕参数类，也没有 `live_danmaku/lib/src/sites/tiktok.dart`：网页评论要先签名请求 `webcast/im/fetch/` 再连 WebSocket，签名由网页安全 SDK（webmssdk）现场生成，仓库里抖音的签名对不上（加上后与不签名一样被拒）；访客 Cookie `ttwid` 平台层也没有拿。
- 测试：`packages/live_core/test/sites/tiktok_api_test.dart` 39 个 `test(` 写法、`tiktok_site_test.dart` 32 个（record.md 写的是 43 个和 34 个）。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（`fixtures/tiktok/legacy_expected.dart`）：在播、未开播、不存在三种用户的刷新、进房、录制、开播状态，7 种搜索输入，21 种链接输入，`share/live` 换主播；升级后另测 7 个画质在“优先 H.264”开和关时的顺序、3.x 的 14 个 id 的对照、三种受限、15 种坏字段留空、12 种坏容器只丢自己、短链跳转（绝对和相对、最多 3 次、绕圈、跳到视频或别的网站）。受限直播、短链的真实跳转都只有合成回答。
- 真实接口：2026-09-29（北京时间）经代理只读请求了 `@qvc` 的 `user/room`，解析出 7 个画质，与样本相同；三条 FLV 线路都读到了 FLV 文件头。同日探查目录接口都要签名或登录（22-8 的依据）。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只记“完成（受限房间说明原因）”，弹幕“受阻（要签名）”）；要用户开着代理。

## 留下的问题

- 弹幕 22-7：受阻，要 TikTok 网页安全 SDK 的签名（D01.19）。有了签名以后再加弹幕参数类（直播间号加 `ttwid` 等）。不运行平台的混淆脚本、不用第三方签名服务，没有任务管。
- 22-8 推荐、分区：受阻。`webcast/feed` 空正文，`api/live/discover`、`webcast/room/recommend` 要签名，直播搜索要登录（2026-09-29 复测）。目录保持为空，没有任务管。
- 22-3 “优先 H.264”的默认值要在高通真机上评估 H.265 硬解后再定：G01.2。偏好不是“原画”时按比例选档可能落到后面的 H.265 档，应只在 H.264 的档里选（G 组）。
- 受限直播、短链的真实跳转没有样本；`liveRoom.status` 除 2、4 以外的取值按“未知”处理，没有见过。没有任务管。
- 应用的代理按平台分配：`share/live` 和短链经 `ShortLinkSession` 以链接的名义发出，要按主机把 `tiktok.com` 分给 TikTok 的代理（record.md 记给 J02.1、I01.1）。
