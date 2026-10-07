# E03.8 LiveMe

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 21-1～21-9）记在 [record.md](record.md)；弹幕 21-9 由 D01.18 调查后受阻
- 旧编号：M4.21、M4.U.21、T02c.8
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)（新增的 `ShortLinkSession.send` 在这里）；弹幕 [D01.18](../../../D-弹幕/D01-平台弹幕协议/D01.18-LiveMe弹幕/README.md)（受阻：要登录）；卡片标“付费”“私密”A09.1，发现页默认隐藏 I02.1、A09.5；直播间说明受限原因 C01.1；画质 id 迁移 J02.1；决定 D-001、D-017
- 代码：`packages/live_core/lib/src/sites/liveme/`（`liveme_api.dart` 1080 行纯解析，含链接 `LiveMeLink` 和签名 `LiveMeSigner`；`liveme_site.dart` 406 行请求编排）；应用在 `apps/pure_live/lib/app/platforms.dart:173` 建适配器，弹幕表里没有登记（`:190-195` 的说明）；样本 `fixtures/liveme/`（12 组接口录制，另有生成 3.x 冻结输出的 `legacy_expected.dart`；没有弹幕样本）

## 目标

把 3.x 的 LiveMe 适配器（`lib/core/site/liveme/` 四个文件共 1068 行：接口、链接、签名、站点）重构进 `live_core`：精选目录、关键词搜索、按短号和各种链接找房间、进房、三档画质、签名的直播信息请求都和 3.x 一样；修掉 3.x 的 17 个问题（在播但地址不合规时进房失败、列表卡片取画质报错、签名时间戳第 10 次起变长、解不开的链接让搜索失败等）。升级落地后私密、付费直播显示为直播中并标受限类型，画质合成“原画”“流畅”两档，媒体地址不限主机，确认签名地址过期不断流、不续期。

## 平台接口要点

| 功能 | 接口（全部匿名，不注入 Cookie；请求头 UA、`Accept`、`Accept-Language`、`Origin`，`Referer` 是房间页或热门页；不跟随跳转；以 `liveme` 的名义发出，走代理） | 位置 |
|---|---|---|
| 请求 | `_send`/`_get`；访客参数 `guestQuery`；HTTP 和业务状态的映射 `checkStatus`（业务 500 “user not exist” 是 `NotFound`）；下载后查 8 MiB 上限 | `liveme_site.dart:70-99`；`liveme_api.dart:474-527` |
| 签名 | `LiveMeSigner`：表单加 `lm_s_id`、`lm_s_ts`（14 位，计数后缀 0～9 循环）、`lm_s_str`、`lm_s_ver`、`h5`，按键名排序拼“键+值”加网页密钥取 md5，作请求头 `lm-s-sign` | `liveme_api.dart:130-183` |
| 目录和推荐 | `lvapi.liveme.com/live/featurelist?countryCode=GLOBAL&page_index=&page_size=&pid=3&posid=3002&h5=1`，目录每页 20；没有分类；目录说明键 `liveme_directory_scope` | `liveme_site.dart:62`、`:163-178`；`liveme_api.dart:561` |
| 搜索 | `live.liveme.com/search/searchKeyword`（`type=1&page=&pageSize=&keyword=`，平台固定回 20 条）；5～12 位数字当短号直达房间；房间页、主页、分享页链接先换成短号 | `liveme_site.dart:194-245`；`liveme_api.dart:588-607` |
| 详情 | `liveme_ent/v1/user/uid_vid_by_short_id` 取 `uid`、`vid`，然后并行 `user/getinfo` 和（在播时）签名的 `live/queryinfosimple` POST；平台回显的短号、用户 id、直播 id 必须对得上 | `liveme_site.dart:101-149`、`:260-302`；`liveme_api.dart:630-722` |
| 状态和受限 | `online`=1、`status`=0、`roomstate`=0 是直播；`ispvt`=1 → `private`，`livebptype`=7 或付费标签（`hot_label_v2` 的 JSON 文本 `text` 是 “Paid broadcast”）→ `paid`，状态仍是直播中；开播时间 `vtime` | `liveme_api.dart:744-778` |
| 标题和图片 | 平台的 5 种默认标题（“Click for fun!”等）当作没有标题，用主播名；封面、头像取第一个能用的字段（空串也跳过）；在播简介用资料的签名 `usign` | `liveme_api.dart:458`、`:724`、`:795`、`:963-978` |
| 画质 | “原画”（`source`，FLV `videosource`/`videosourcemore` 在前、HLS `hlsvideosource` 在后）和“流畅”（`smooth`，`smallsource`/`smallsourcemore`）；旧 id `source-flv`、`hls`、`smooth-flv` 仍能取流 | `liveme_api.dart:427-451`、`:869-921` |
| 取流 | 线路编号 `flv`、`hls`，备用地址加 `#2`、`#3`；带 3.x 的媒体请求头；地址不限主机，3.x 认的三个 CDN 改 https；没有租期（`wsABStime` 跟着开播时间，过期也能播）；受限直播不读地址，取流报 `StreamUnavailable`（`(private)`/`(paid)`） | `liveme_site.dart:316-360`；`liveme_api.dart:484`、`:891`、`:944` |
| 链接 | `liveme.com`、`www.liveme.com`，可带地区段：`livehot/streaming/<短号>` 直接得到；`u/<uid>`、`v/<vid>`、`m/v/<vid>/index.html` 经 `ShortLinkSession` 请求一次（分享页要签名 POST，用 `session.send`） | `liveme_api.dart:32-112`；`liveme_site.dart:387-396` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/liveme/`） | 现在 | 说明 |
|---|---|---|---|
| 不能播的在播房间 | `liveme_site.dart:95-101` 地址不合规时进房失败 | 照常进房，取流时报 `StreamUnavailable` | 3.x 问题 2 |
| 取画质 | `liveme_site.dart:180` 未开播空列表；列表卡片报 `identity` | 未开播直接报原因；没有进房数据先查当前直播（2 个请求） | 3.x 问题 3、4 |
| 恢复 | `liveme_site.dart:193-195` 要求旧快照在播，整套进房（3 个请求） | 映射和直播信息 2 个请求，跟到新的一场 | 3.x 问题 5 |
| 签名时间戳 | `liveme_signer.dart:27` `% 10000`，第 10 次起变长 | 一位计数，固定 14 位 | 3.x 问题 8 |
| 付费标签 | `liveme_api.dart:474` 只按对象读，从来没生效 | 按 JSON 文本读 | 21-1 |
| 私密、付费 | `liveme_api.dart:276`、`liveme_site.dart:74` 显示“封禁”且不进目录 | 直播中，标 `private`、`paid`；发现页默认隐藏由界面做 | 21-1、21-5 |
| 图片兜底 | `liveme_api.dart:494-495` 用 `??`，空串时没有图 | 取第一个能用的字段 | 21-2 |
| 在播简介 | `liveme_api.dart:496` 用 `user_info.desc`（就是昵称） | 资料的签名 `usign` | 21-3 |
| 联合项目的搜索状态 | `liveme_api.dart:336` 只有 `liveme` 项目的 0 是未开播，其余“未知” | `is_live` 0 一律未开播，进房以详情为准 | 21-4 |
| 媒体地址 | 只收三个 CDN 主机并改 https | 不限主机；三个主机照旧改 https | 21-6 |
| 画质 | `liveme_site.dart:165-167` 三档：原始画质 · FLV、流畅画质 · FLV、HLS 自动 · HLS | “原画”（FLV、HLS 两条线路）、“流畅” | 21-7，旧 id 对照给 J02.1 |
| 租期 | 没有 | E03.8 加过租期，21-8 实测后去掉（不续期） | 21-8 |
| 列表坏行 | 整页 `ApiChanged` | 只跳过这一行，全坏仍报错 | 统一原则的容错 |
| 默认标题 | 照原样显示 | 5 种已知写法当作没有标题 | 统一原则的占位信息 |
| 公告 | `liveme_site.dart:82` “LiveMe 远端聊天尚待接入；……” | “这里暂时看不到 LiveMe 直播间的聊天。人数分别是热度、正在观看和累计观看。” | 统一原则的说明文字 |
| 弹幕 | `liveme_site.dart:38` `EmptyDanmaku` | 仍没有弹幕，弹幕表不登记，界面照 3.x 提示一次未接入 | D01.18 受阻 |

## 结果

- 首次重构（2026-09-28，提交 `6fe261aa8`）：17 个 3.x 问题、11 条有意差异见 record.md；新增通用能力 `ShortLinkSession.send`（`packages/live_core/lib/src/links.dart`），分享页链接要用签名的 POST 才能查到短号。
- 升级落地（2026-09-29）：21-1～21-8 完成（21-1、21-5 的发现页隐藏和受限说明由 A09.1、I02.1、A09.5、C01.1 接上；21-7 的画质 id 对照由 J02.1 迁移）；21-9 弹幕在 D01.18 受阻。按统一原则补了开播时间、受限类型、默认标题、容错、公告文字。
- 弹幕 21-9（D01.18，受阻）：平台层给出的只有本场直播 id `LiveMeRoomData.videoId`（`liveme_api.dart:358-377`，进房和录制的 `data` 里），它就是聊天室 id（直播信息的 `TCRoomId`，实测相等）。没有弹幕参数类，也没有 `live_danmaku/lib/src/sites/liveme.dart`：进聊天室还要账号的 uid、登录令牌和设备号（平台自有 IM，socket.io + protobuf，网页端只在登录后连），本项目没有 LiveMe 登录，也不绕过。
- 测试：`packages/live_core/test/sites/liveme_api_test.dart` 35 个 `test(` 写法、`liveme_site_test.dart` 27 个（record.md 写的是 38 个和 27 个）；`ShortLinkSession.send` 另在 `sites_links_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（`fixtures/liveme/legacy_expected.dart` 把 3.x 的四个文件原样搬进程序生成，POST 按 `videoid` 匹配）：精选两页、搜索三页、在播和未开播的房间、不存在的短号和主播、30 个链接向量；签名用录制样本和归档 v4 的独立向量核对。升级后另测付费标签、私密和付费的状态和取流说明、图片兜底、两档画质和旧 id、默认标题、坏行只跳过。
- 真实接口：2026-09-28 18:40～19:10 UTC 直连、匿名、只读：精选第 1～10 页 199 张卡片、22 个国家和地区的第 1 页；7 场在播直播走完三步请求；3 场 `wsABStime` 已过期 1.5～6.7 小时的直播，新建的 FLV 连接、HLS 主列表、子列表和分片都照常 200（21-8 的依据）。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只记“完成”，弹幕“受阻（要登录 IM）”）；要用户开着代理。

## 留下的问题

- 弹幕 21-9：受阻，要登录 LiveMe 才能进聊天室（D01.18）。以后支持 LiveMe 登录时，在平台层加弹幕参数类（直播 id 加账号的 uid、令牌、设备号），协议记录在 D01.18 的 record.md。没有任务管。
- 付费、私密直播没有真实样本：实测 199 张卡片和样本 40 张里都没有，判断规则来自官网网页端的脚本；付费直播的直播信息接口是否照样给地址没有试。没有任务管。
- `livebptype` 为 4 的直播按没有限制处理（网页端只把 7 当付费）；只收了 5 种默认标题，见到新的写法要加进 `LiveMeApi.defaultTitles`。没有任务管。
- 24 小时的 `game.live11` 地址过期以后能不能播没有等到；“原画”的 FLV 打不开时换 HLS 线路由播放器做（G01.1 同档两条线路互为备用）。
- 精选跨页会重复（10 页 199 张卡片只有 187 个主播），列表按 `identityKey` 去重（I02.1）。
