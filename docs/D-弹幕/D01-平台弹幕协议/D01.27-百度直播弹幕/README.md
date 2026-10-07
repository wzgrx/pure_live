# D01.27 百度直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 30-3“百度弹幕（轮询消息列表）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x、归档 v4、pure_live_TV 都没有百度弹幕，这是新增功能，规格来自房间页脚本 `pchome.live.fcb2dc0e.js`（类 `Se`、`Te`）和归档规格 §7
- 旧编号：M5.26、T06a.27
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、房间命令和新加的 `BaiduLiveDanmakuArgs` [E02.11](../../../E-直播平台/E02-其他国内平台/E02.11-百度直播/README.md)（弹幕参数见它的 [record.md](../../../E-直播平台/E02-其他国内平台/E02.11-百度直播/record.md)）；礼物在聊天列表的显示 [C01.2](../../../C-直播间/C01-进房和房间逻辑/C01.2-直播间第二部分/README.md)（B-21）；连接结束后重连 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)（B-24）；附录 B-18～B-20（不做）；3.x 存下的旧公告由 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md) 导入时清掉；详细记录 [record.md](record.md)

## 目标

百度直播间能看到聊天、在线人数和礼物。百度网页优先用闭源的 IM SDK（`pim.baidu.com`），不支持时退回轮询房间命令给的消息列表；本实现只用后者（公开的签名地址，匿名可读），不跑平台的 SDK。直播结束（102）时弹幕连接跟着结束。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | 进房时房间命令 371 已有 `chat_msg_hls_url`、`reliable_msg_hls_url`、`host_msg_hls_url` 和 `msg_hls_pull_internal_in_second`，放进 `BaiduLiveDanmakuArgs`（`BaiduLiveApi.danmakuArgs`），不多发请求；地址只收 `liveshowstatic.baidu.com` 的 `.m3u8`（`messageList`），http 换成 https（网页同样） |
| 请求 | 以 `baidulive` 的名义走 `LiveHttp`；请求头是网页的 UA、`Origin`、房间页作 `Referer`；单个请求 10 s |
| 签名 | 列表地址带 `authorization=bce-auth-v1/…`，签 182.5 天（`signatureExpiry` 读出到期时间）；分片签 7 天，过期回 403 `RequestExpired`；开始时已过期（按连接的时钟）不发请求、以 `credentialsUnavailable`（`Chat list signature expired at …`）结束；运行中聊天列表回 403 且已过期同样结束 |
| 列表 | m3u8：第一行 `#EXTM3U`，每个分片一行 `/v1/liveshowstatic/<mcast_id>_<纳秒时间>.ts?authorization=…`，别的主机或协议的行跳过；列表总留最后 3 个分片（可能是几十小时前的）；`EXT-X-MEDIA-SEQUENCE` 恒为 0，按分片路径去重（每个列表记最近 256 个） |
| 节奏 | 第一次聊天列表回答即加入（404 也算，列表还没有消息），已列出的分片是历史不取；之后每隔 `pullInterval`（5 s，限 1～10 s）依次拉聊天列表、它的新分片、reliable 列表、它的新分片、host 列表；reliable、host 列表第一次回答同样是历史 |
| 分片 | gzip 的 JSON（看魔数 `1f 8b`，最多解两层；带不带 `Content-Encoding` 都行）：`list[].messages[]` 里 `type` 0 的外层消息，`content.text` 再解一层是载荷 |
| 消息 | 载荷 0 → 聊天（按 `message_type` 取文字：`0` 取 `content`、`3` 取链接标题，图片、卡片、语音没有文字不报；回复取自己的话；`name`、`uid`、外层 `msgid`、`create_time`；`room_id` 不同就丢），白色；101 → `onlineusercnt` 在线人数；107 且 `service_type` 10024 → 礼物（`BaiduLiveGift`：名字、数量、是否免费、图标，文字是“<礼物> ×<数量>”）；本房间的 102 → 先报这个分片的消息，再以 `connectionFailed`（`Broadcast ended`）结束；`mix_room_close`（说的是别的房间）和其他 107 不报 |
| 失败 | 加入合计 3 次（间隔 2 s），都失败以 `connectionFailed` 结束；之后聊天列表失败（没有回答、非 2xx 也不是 404、不是播放列表）第 1 次报重连，等 1、2、4、8、8… s，第 9 次 `reconnectsExhausted`，失败后再有回答重新报就绪；reliable、host 列表失败或 404 只跳过 1、2、4、8、12 轮（host 列表一直 404）；分片 4xx 或不是 JSON 对象跳过，没有回答或 5xx 在之后的轮里重试，共 3 次 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `BaiduLiveSite.getDanmaku() => EmptyDanmaku()`（`core/site/baidulive/baidu_live_site.dart:45`）；进房时弹幕区一条状态“此平台的远端弹幕尚未接入……”（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `BaiduLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/baidulive.dart:399`）：`start`（:409）查签名、加入重试；一个列表的状态 `_BaiduLiveList`（:436）；一次运行的 `_BaiduLiveChat`（:468）：`join`（:493）、`follow`（:499）轮询和退避、`_poll`（:536）reliable 和 host 列表、`_drain`（:575）取新分片、`_playlist`（:617）；应用登记在 `apps/pure_live/lib/app/platforms.dart:234`（只传 `LiveHttp`） | 有聊天、人数、礼物（已做） |
| 协议 | 无 | `BaiduLiveDanmakuProtocol`（:96）：请求 10 s、加入 3 次和间隔 2 s、失败上限 8、跳过上限 12 轮、分片 3 次、记 256 个分片、结束说明（:98～120）、`backoff`（:133）、`skippedPolls`（:137）、`playlist`（:147）、`inflate`（:174）、`segment`（:185）、`_chat`（:253）、`_online`（:283）、`_gift`（:293）；`BaiduLivePlaylist`（:52）、`BaiduLiveSegment`（:66）、`BaiduLiveGift`（:15） | 与网页脚本的读法逐个一致 |
| 平台层 | 无 | `live_core` 新加 `BaiduLiveDanmakuArgs`（`packages/live_core/lib/src/sites/baidulive/baidulive_api.dart:101`）、`BaiduLiveApi.messageList`（:844）、`signatureExpiry`（:855）、`danmakuArgs`（:880，直播中进房才给，:836） | — |
| 公告 | `baidulive_chat_notice`“百度远端聊天尚待接入；目录 audience_count 与房间 online_users 按当前观看人数展示……”（`baidu_live_site.dart:137`，`assets/translations/zh.json:1942`） | `BaiduLiveApi.chatNotice`（`baidulive_api.dart:401`）只说明人数，3.x 原文留成 `legacyChatNotice`（:404） | 3.x 存下的旧公告导入时清掉（J02.1） |
| 人数 | 卡片的 `audience_count` | `audience.dart:248` 仍是 `roomList`，弹幕的 101 是同一个数，收到就报 | — |

## 结果

- **提交**：cdb9504e3（2026-09-30，本任务的代码）。之后只有 docs v1 改编号时动过注释（c613b73f9、9dfbb424d），行为没有变。
- **期望值**：没有可对照的实现，`fixtures/baidulive/danmaku/web_expected.py` 按网页脚本的类 `Se`、`Te` 和归档规格 §7 用 Python 独立重写。S03-live-chat（教育直播 11548522172）17 条聊天、6 次人数；S04-live-online 105 次人数；S05-live-gift 3 条聊天、7 次人数、3 个礼物；S06-ended 的 `mix_room_close` 不报；S07-synthetic 43 个分片、8 个列表一致。
- **实测**（2026-09-30 匿名直连）：三场各 7 分钟，聊天 20 条（多是主播的欢迎机器人或 AI 机器人），人数 118 次；host 列表 293 次都是 404；没见到 102。本实现进教育直播 1.2 s 加入、90 s 4 条聊天，新闻直播 0.9 s 加入、28 次人数。
- **样本**：`fixtures/baidulive/S02-room-chat`（房间命令），`fixtures/baidulive/danmaku/` 的 S03～S07（观众、签名的密钥 id 和签名、响应头回显的出口地址都脱敏，签名时间和有效期保留用来测过期）。
- **测试**：`packages/live_danmaku/test/sites/baidulive_test.dart` 现在运行时 86 个（和做完时一样）：文件里 32 处 `test(`，其中第 445 行在 S03～S06 四份录制上各一个、第 500 行在 S07 的 43 个分片上各一个、第 507 行在 8 个列表上各一个、第 523 行在 S03～S05 三份录制上各一个。按分组：协议 5、录制对照 5、合成对照 53、虚拟时钟回放 3、连接 20。`live_core` 的百度测试 +9。

## 验证

- 自动测试：`baidulive_test.dart` 覆盖时序常量和请求头、分片去重、播放列表的各种行、gzip 两层和不带头的 gzip、聊天各种 `message_type` 和回复、人数、礼物；四份录制和 51 个合成样本对照网页读法；虚拟时钟上按录制回放（加入、跳过历史、新分片只报一次）；连接的 404 加入、加入失败 3 次、签名过期（开始时和运行中 403）、退避和第 9 次结束、reliable 和 host 列表跳过、分片 4xx/5xx、102 结束、换房间、关闭时取消、本地 HTTP 服务器端到端。
- 真实接口：2026-09-30 跑过（见上面的实测）。没验证到的：102 直播停止（按网页脚本，合成帧测）、回复、图片、语音消息、长时间运行（实测最长 7 分钟）。
- 真机：没有单独的真机记录；S02.2、S02.3 的记录里没有百度，E02.11 也写“没有在 K90 上专门看过”。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列国内五大平台，没有百度弹幕的条目。真机上要看：进一个在播的百度直播间，聊天延迟几秒出现、人数随之变化，有礼物时聊天列表里出现礼物行。

## 留下的问题

- 延迟最多一个间隔（5 s）加分片生成的时间；接百度 IM 能更快：不做（附录 B-18：要运行平台不公开的 SDK）。
- 进场、点赞、升级通知不显示：不做（B-19）；在线人数不改用 `real_onlineusercnt_str`：不做（B-20，和房间页、卡片的人数对不上）。
- 102 没有实测到：没有任务。如果平台其实不发 102，下播后连接只是每 5 s 拉一次没有新分片的列表，不打转、不报错，界面按房间状态处理。
- 签名过期（`credentialsUnavailable`）后要拿新的房间详情再连：2026-10-07 登记，平台层让刷新带参数 → [E05.4](../../../E-直播平台/E05-平台框架和模型/E05.4-平台层小问题合集/README.md)，直播间在连接结束后先按进房详情取参数 → [C01.6](../../../C-直播间/C01-进房和房间逻辑/C01.6-主播换场后弹幕参数变了要重连/README.md)。C01.1 的 B-24 在弹幕连接结束后，直播间每 60 秒刷新详情时重连（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:785`），但刷新用的 `getRoomDetailForRefresh`（`packages/live_core/lib/src/sites/baidulive/baidulive_site.dart:321`）不带弹幕参数，`LiveRoom.mergeFrom` 保留旧的（`packages/live_core/lib/src/live_room.dart:619`），所以重连用的还是同一组过期地址，会立刻再次结束。列表签半年，实际很少遇到；要做时让百度的刷新在直播中也带参数，或过期时直播间按进房详情重取。
- 3.x 存下的旧公告：已由 J02.1 处理，真机核对在 [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)。
- 没有真机结果：没有任务；真机清单没有本平台弹幕的条目（见“验证”）。
