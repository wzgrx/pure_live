# D01 平台弹幕协议

各直播平台的弹幕连接和解析：怎么连（地址、凭据、加入、心跳、重连）、怎么解（包格式、消息类型）、给出什么数据（聊天、醒目留言、人数、礼物、撤回、通知；昵称、颜色、粉丝牌、头像、表情图片），以及所有平台共用的连接框架。

## 范围

- 包括：
  - 纯 Dart 包 `packages/live_danmaku` 的连接框架（D01.1：`connection.dart`、`connection_base.dart`、`socket_connection.dart`、`registry.dart`、`binary.dart`、`codec/protobuf.dart`、`exact_websocket.dart`、`emoji.dart`、`sender.dart`）和 28 个平台的实现（`lib/src/sites/`，D01.2～D01.31，其中 LiveMe、TikTok 受阻没有实现文件）。
  - 应用里登记哪些平台有弹幕：`apps/pure_live/lib/app/platforms.dart:196` 的 `buildDanmakuRegistry`；连接状态和原因怎么变成聊天里的系统行（`features/live_play/logic/room_controller.dart` 的 `_syncDanmaku`、`_onDanmaku`，文字 `shared/rooms/room_texts.dart:171`、`:178`）。
  - 弹幕带来的数据：哔哩哔哩访客昵称提示、粉丝牌和头像（D01.32）；各平台的醒目留言、撤回、通知、礼物、在线人数的上报。
  - 样本和对照：`fixtures/<平台>/danmaku/`（28 个平台目录）和它们的冻结输出。
- 不包括（归哪里）：
  - 过滤规则（去重闸门、屏蔽、重复合并、相似度、打码昵称不能屏蔽）：代码在同一个包的 `lib/src/filters/`（D01.1 建的），之后的改动归 [D02](../D02-过滤和屏蔽/README.md)。
  - 弹幕连接要的参数（`*DanmakuArgs`：房间号、凭据、服务器地址）由平台适配器在取房间详情时给出 → [E 组](../../E-直播平台/README.md)各平台任务（E01～E03）；平台模型（`LiveMessage` 的字段）→ E05。
  - 消息进来以后怎么上屏：聊天列表的数据流和性能 → [D04](../D04-数据流和性能/README.md)；飞行弹幕怎么画 → [D03](../D03-飞行弹幕引擎/README.md)；弹幕设置生效 → [D05](../D05-弹幕设置生效/README.md)。
  - 聊天列表、醒目留言、提示条长什么样 → [A08](../../A-界面设计/A08-弹幕界面/README.md)（A08.1）；直播间什么时候连、断（进房、刷新、开播重连、小窗返回）→ [C01](../../C-直播间/C01-进房和房间逻辑/README.md)。
  - 录制时同时录弹幕 XML（`app/recording.dart:53` 也用这里的连接和过滤）→ H 组（H01.4 验证）。
  - 网络层：`LiveSocket`（重连、退避、心跳）→ Q01.1；Brotli 解码 → Q01.2；握手 User-Agent 去掉 Dart 前缀 → [Q03.1](../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)。

## 现状：做到哪、怎么工作的

- 用户看得到的：进直播间后聊天列表先写“开始连接弹幕服务器”，连上写“弹幕服务器连接正常”，之后弹幕同时进聊天列表和画面；断了写“与弹幕服务器断开连接，正在尝试重连”，重连 8 次失败写“弹幕服务器多次重连失败，已断开；刷新直播间可再次连接”，第一次尝试 30 秒没完成写“弹幕服务器连接超时，已自动释放并可重新连接”并给“重新连接”（`apps/pure_live/assets/translations/zh.json:274`、`:308`、`:309`、`:772-780`）。没登记弹幕的平台（网易 CC、映客、小红书、微博、LiveMe、TikTok）提示一次“该平台暂不支持弹幕”，聊天列表中间写“平台不提供弹幕”；IPTV 不连也不提示。哔哩哔哩未登录时列表顶上有“访客模式下哔哩哔哩会隐藏昵称 · 去登录”（D01.32）。
- 内部怎么工作：

```text
平台适配器 getRoomDetail → LiveRoom.danmakuData（*DanmakuArgs）
直播间页 live_play_page.dart:278  danmaku.connectionFor(site.id)、danmakuSupported: supports(site.id)
LiveRoomController._syncDanmaku（room_controller.dart:809）
   不在播 / 弹幕关 / IPTV → idle；不支持 → unsupported + 一次提示
   connect(danmakuData).timeout(30 s) → connecting → connected / timedOut / failed
DanmakuConnection.events（同步广播流）
   DanmakuReady → “弹幕服务器连接正常”
   DanmakuReceived → _onMessage（:868）：聊天先过 DanmakuMessageFilter（D02），再进 ChatFeed（D04）和 flying（D03）；
                     online → 人数；superChat → 醒目留言栏 + 列表一行；retraction → 撤下；notice → 一行；gift → 一行（可关）
   DanmakuReconnecting / DanmakuClosed → 系统行（room_texts.dart:171、:178）
```

  - 平台实现分两种：WebSocket 平台继承 `DanmakuSocketConnection`（23 个），只写 `target`、`onOpen`、`onData`、心跳帧，重连和退避由运行时做；HTTP 轮询或自己管理连接的平台直接继承 `DanmakuConnectionBase`（快手、YouTube、Steam、百度、niconico 5 个），用 `run.delay` 和 `run.ended` 做间隔和取消。
  - 每个连接对象只服务一个直播间；`connectionFor` 每次新建。`close` 返回后不会再有事件（基类保证），直播间换台、离开时直接关。
  - 消息统一成 `live_core` 的 `LiveMessage`（`packages/live_core/lib/src/live_message.dart:280`）：`type`（聊天、礼物、人数、醒目留言、撤回、通知）、昵称、文字、颜色、`messageId`、`sentAt`、`emotes`（平台给的表情图片）、`fansName`/`fansLevel`、`nameColor`、`badges`、`sourceRoomId`、`replayed`；每条都经过 `cleanDanmakuText` 去掉占位字符（`connection_base.dart:167`）。
- 完成度（和 3.x 对照）：
  - 3.x 有弹幕的 8 个平台（哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、SOOP、Twitch，`~/ref/v3ref/lib/core/danmaku/`）全部照 3.x 移植，用 3.x 解码器的冻结输出逐条比较（`legacy_expected.dart`），只有记录里写明的有意差异；同时修了 3.x 的问题（哔哩哔哩认证被拒后无限重连、Twitch 和 SOOP 再次连接不关旧连接、SOOP `connect` 不等等，见各平台记录）。
  - 3.x 没有弹幕的平台新接了 20 个（AcFun、Picarto、TwitCasting、猫耳 FM、克拉克拉、niconico、SHOWROOM、CHZZK、YouTube、BIGO LIVE、PandaTV、FC2 LIVE、Steam、京东、酷狗、百度、六间房、LOOK、17LIVE、Kick），样本对照网页或归档 v4 的输出（`web_expected.*`、`v4_expected.dart`）。3.x 这些平台的 `getDanmaku()` 都返回 `EmptyDanmaku`（例如 `core/site/acfun/acfun_site.dart:34`）。
  - 受阻 2 个：LiveMe（要登录 IM）、TikTok（要平台 SDK 现场签名），见 D01.18、D01.19；网易 CC 匿名加入没回应（附录 C-22，未排）。
  - 已批准升级（[specs/UPGRADES.md](../../specs/UPGRADES.md)）弹幕相关的 24 条和附录 B 的 26 条：弹幕层的部分都做完；要界面的余项在 E06.2（Twitch Cookie 提示、17LIVE 名字颜色和徽章、酷狗 PK“对方”标记）。

## 代码地图

框架（`packages/live_danmaku/lib/`，D01.1）：

| 文件 | 职责 |
|---|---|
| `live_danmaku.dart`（50 行） | 包的导出 |
| `src/connection.dart`（188） | `DanmakuStatus`（`:5`）、`DanmakuInterruption`（`:24`）、`DanmakuCloseReason`（`:37`）、事件 `DanmakuEvent`（`:52`）及四种子类、接口 `DanmakuConnection`（`:138`）、`DanmakuStartFailure`（`:176`） |
| `src/connection_base.dart`（219） | `DanmakuConnectionBase`（`:16`，按 run 失效的生命周期）、`DanmakuRun`（`:97`）、`cleanDanmakuText`（`:167`） |
| `src/socket_connection.dart`（416） | `DanmakuSocketPolicy`（`:15`）、`DanmakuHandshakeFailure`（`:59`）、`DanmakuSocketTarget`（`:88`）、`DanmakuSocketConnection`（`:122`）、`DanmakuSocketSession`（`:223`） |
| `src/exact_websocket.dart`（656） | 保留请求头大小写的 WebSocket 握手（`ExactWebSocket` `:57`），YY、SOOP 用（D01.7） |
| `src/registry.dart`（81） | `DanmakuRegistry`（`:45`）、`EmptyDanmakuConnection`（`:13`） |
| `src/binary.dart`（163）、`src/codec/protobuf.dart`（197） | 二进制读写、`ListUtil`（`:137`）；protobuf 读写（抖音、AcFun、niconico、YouTube、酷狗用） |
| `src/emoji.dart`（149） | 3.x 表情表的解析（`DanmakuEmoji` `:16`） |
| `src/sender.dart`（23） | `DanmakuSender`（头像，D01.32） |

各平台（`packages/live_danmaku/lib/src/sites/`）：

| 任务 | 平台 | 文件（行数） | 连接类（行）和基类 | 测试（用例数） | 样本 `fixtures/…/danmaku/` | 3.x |
|---|---|---|---|---|---|---|
| D01.2 | 哔哩哔哩 | `bilibili.dart`（895） | `BilibiliDanmakuConnection`（`:75`），WebSocket | `test/sites/bilibili_test.dart`（38） | S13 五份 | `core/danmaku/bilibili_danmaku.dart` |
| D01.3 | 斗鱼 | `douyu.dart`（395） | `:346`，WebSocket | `test/douyu_test.dart`（29） | S13～S16 | `douyu_danmaku.dart` |
| D01.4 | 虎牙 | `huya.dart`（439） | `:314`，WebSocket | `test/huya_test.dart`（36） | S11、S16～S20 | `huya_danmaku.dart` |
| D01.5 | 抖音 | `douyin.dart`（416） | `:251`，WebSocket | `test/sites/douyin_test.dart`（39） | S13 三份 | `douyin_danmaku.dart`、`xbogus.dart` |
| D01.6 | 快手 | `kuaishou.dart`（325） | `:213`，HTTP 轮询 | `test/kuaishou_test.dart`（19） | S16、S17 | `kuaishou_danmaku.dart` |
| D01.7 | YY 直播 | `yy.dart`（743）、`yy/packet.dart`（180） | `:654`，WebSocket（保留大小写） | `test/sites/yy_test.dart`（31） | S08～S10 | `yy_danmaku.dart` |
| D01.8 | SOOP | `soop.dart`（241） | `:158`，WebSocket（保留大小写） | `test/soop_test.dart`（30） | S07～S09 | `soop_danmaku.dart` |
| D01.9 | Twitch | `twitch.dart`（534） | `:407`，WebSocket（IRC） | `test/twitch_test.dart`（48） | S07～S10 | `twitch_danmaku.dart` |
| D01.10 | AcFun | `acfun.dart`（783） | `:36`，WebSocket | `test/sites/acfun_test.dart`（38） | S07 | 没有弹幕 |
| D01.11 | Picarto | `picarto.dart`（652） | `:461`，WebSocket | `test/picarto_test.dart`（40） | S07、S09～S15 | 没有弹幕 |
| D01.12 | TwitCasting | `twitcasting.dart`（280） | `:174`，WebSocket | `test/sites/twitcasting_test.dart`（24） | S08 | 没有弹幕 |
| D01.13 | 猫耳 FM | `missevan.dart`（905） | `:687`，WebSocket | `test/missevan_test.dart`（55） | S06～S09 | 没有弹幕 |
| D01.14 | 克拉克拉 | `kilakila.dart`（682） | `:549`，WebSocket（socket.io） | `test/sites/kilakila_test.dart`（28） | S07～S11 | 没有弹幕 |
| D01.15 | niconico | `niconico.dart`（1054） | `:718`，自管（座位 + 消息流） | `test/sites/niconico_test.dart`（49） | S07～S10 | 没有弹幕 |
| D01.16 | SHOWROOM | `showroom.dart`（200） | `:132`，WebSocket | `test/sites/showroom_test.dart`（17） | S06 | 没有弹幕 |
| D01.17 | CHZZK | `chzzk.dart`（916） | `:635`，WebSocket | `test/chzzk_test.dart`（58） | S09～S17 | 没有弹幕 |
| D01.18 | LiveMe | 没有（受阻） | — | — | 只有平台样本 `fixtures/liveme/` | 没有弹幕 |
| D01.19 | TikTok | 没有（受阻） | — | — | 只有平台样本 `fixtures/tiktok/` | 没有弹幕 |
| D01.20 | YouTube | `youtube.dart`（1027） | `:857`，HTTP 轮询 | `test/sites/youtube_test.dart`（69） | S06～S12 | 没有弹幕 |
| D01.21 | BIGO LIVE | `bigo.dart`（699） | `:446`，WebSocket | `test/sites/bigo_test.dart`（27） | S05～S07 | 没有弹幕 |
| D01.22 | PandaTV | `pandalive.dart`（594） | `:333`，WebSocket（Centrifugo） | `test/sites/pandalive_test.dart`（29） | S07 | 没有弹幕 |
| D01.23 | FC2 LIVE | `fc2live.dart`（667） | `:431`，WebSocket | `test/sites/fc2live_test.dart`（34） | S06 | 没有弹幕 |
| D01.24 | Steam 直播 | `steambroadcast.dart`（557） | `:360`，HTTP 轮询 | `test/sites/steambroadcast_test.dart`（24） | S07 | 没有弹幕 |
| D01.25 | 京东直播 | `jdlive.dart`（518） | `:384`，WebSocket | `test/sites/jdlive_test.dart`（32） | S06、S07 | 没有弹幕 |
| D01.26 | 酷狗直播 | `kugoulive.dart`（1167） | `:904`，WebSocket | `test/sites/kugoulive_test.dart`（36） | S07～S11 | 没有弹幕 |
| D01.27 | 百度直播 | `baidulive.dart`（641） | `:399`，HTTP 轮询 | `test/sites/baidulive_test.dart`（32） | S03～S07 | 没有弹幕 |
| D01.28 | 六间房 | `sixroom.dart`（610） | `:422`，WebSocket | `test/sites/sixroom_test.dart`（27） | S07 | 没有弹幕 |
| D01.29 | LOOK 直播 | `looklive.dart`（931） | `:667`，WebSocket（网易云信） | `test/sites/looklive_test.dart`（29） | S05 | 没有弹幕 |
| D01.30 | 17LIVE | `seventeenlive.dart`（1273） | `:878`，WebSocket（Ably） | `test/sites/seventeenlive_test.dart`（73） | S05～S10 | 没有弹幕 |
| D01.31 | Kick | `kick.dart`（434） | `:361`，WebSocket（Pusher） | `test/sites/kick_test.dart`（17） | S07、S08 | 3.x 没有这个平台 |
| D01.32 | 哔哩哔哩（昵称、粉丝牌、头像） | `bilibili.dart` 的 `_medal`（`:615`）、`_avatar`（`:635`）、`_userName`（`:706`） | — | 同 D01.2 | 同 D01.2 | — |

“3.x”一列的文件都在 `~/ref/v3ref/lib/core/danmaku/`；“没有弹幕”指 3.x 的 `core/site/<平台>/` 里 `getDanmaku()` 返回 `EmptyDanmaku`。

应用里（`apps/pure_live/lib/`）：

| 文件 | 职责 |
|---|---|
| `app/platforms.dart`（196～256 行） | `buildDanmakuRegistry`（`:196`）：28 个平台的工厂（`:201-239`），传代理、HTTP、斗鱼的过滤设置、YouTube 的“显示全部聊天”；`plainDanmakuUserAgent`（`:245`，B-2，默认关）、`danmakuHandshake`（`:249`） |
| `app/services.dart` | `danmakuProvider`（`:116`） |
| `features/live_play/live_play_page.dart` | 进房时 `connectionFor`、`supports`（`:278-279`） |
| `features/live_play/logic/room_controller.dart` | `ChatConnection`（`:43`）、`ChatNameHint`（`:67`）、`_syncDanmaku`（`:809`，30 s 启动超时 `:100`）、`_onDanmaku`（`:848`）、`_onMessage`（`:868`）、`_onLoginChanged`（`:281`，D01.32） |
| `shared/rooms/room_texts.dart` | `interruptionText`（`:171`）、`closeText`（`:178`） |
| `tv/room/tv_live_play_page.dart`、`features/multiview/logic/multiview_controller.dart`、`app/recording.dart` | 电视直播间、多画面、录制弹幕 XML 也用同一个登记表 |

测试：`packages/live_danmaku/test/` 共约 1165 个 `test(`（有的在循环里展开，`dart test` 报的数更多，D01.32 合并时是 1594 个）；框架的见 [D01.1](D01.1-弹幕框架和过滤/README.md)，平台的见上表。应用侧：`apps/pure_live/test/features/live_play/live_play_controller_test.dart`（连接状态、超时、重连、访客提示）、`chat_names_test.dart`（D01.32）。

## 3.x 基线

- 接口：`git show v3.2.11:lib/core/interface/live_danmaku.dart:4`（`LiveDanmaku`，四个回调）；各平台 `lib/core/site/<平台>/*_site.dart` 的 `getDanmaku()`（例如 `bilibili_site.dart:26`、`douyu_site.dart:70`、`twitch_site.dart:523`）；没有弹幕的返回 `lib/core/danmaku/empty_danmaku.dart:9`。
- 运行时：`lib/core/common/web_socket_util.dart:73`（`WebScoketUtils`，连接超时 10 s `:170`、最多 8 次 `:124`、退避 1 s `:112`）。
- 会话：`lib/modules/live_play/controllers/danmaku_controller.dart`（`DanmakuController` `:19`，启动超时 20 s `:22`；`_installCallbacks` `:191`；IPTV 和 CC 不连 `:327`）。
- 8 个平台的实现：`lib/core/danmaku/`（`bilibili_danmaku.dart` 544 行、`douyu_danmaku.dart` 320、`huya_danmaku.dart` 474、`douyin_danmaku.dart` 335 + `xbogus.dart` 139、`kuaishou_danmaku.dart` 304、`yy_danmaku.dart` 214、`soop_danmaku.dart` 194、`twitch_danmaku.dart` 176）。
- 必须保留的：一轮连续失败只提示一次重连；每次重新加入都发就绪（提示 3 秒内去重）；最多重连 8 次；3.x 的提示文字（4.x 改成翻译键，意思不变）；斗鱼“疑似机器人”过滤设置的键名（`filterDouyuSuspectedAutomatedMessages`，D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| LiveMe 弹幕要登录账号的 IM 令牌，没有游客通道 | 没有实现文件；`app/platforms.dart:190-195` 不登记 | LiveMe 直播间没有弹幕，提示一次 | D01.18（受阻：支持 LiveMe 登录后再做） |
| TikTok 弹幕要平台安全 SDK 现场生成的签名，仓库里抖音的签名对不上 | 同上 | TikTok 直播间没有弹幕 | D01.19（受阻：有可用的签名办法后再做） |
| 网易 CC 匿名加入房间服务端不回应 | 不登记；3.x 也不连（`danmaku_controller.dart:327`） | CC 没有弹幕；4.x 会提示一次“该平台暂不支持弹幕”，3.x 不提示 | 附录 C-22，未排（要用户的登录 Cookie） |
| 哔哩哔哩访客收到的礼物是 `SEND_GIFT_V2`（protobuf），不解析；禁言通知没录到样本 | `bilibili.dart:484-497` | 访客只看到上舰，看不到普通礼物；没有禁言通知 | 礼物：没有任务（候选在 E01.1 记录“附录 C 落地”）；禁言：附录 C-3 受阻 |
| 斗鱼进房时补不上还在显示的超级弹幕（找不到列表接口） | E01.2 | 进房前发的醒目留言看不到 | 附录 C-5 受阻，未排 |
| 弹幕握手的 User-Agent 带 `Dart/… (dart:io)` 前缀 | `app/platforms.dart:245`（编译参数，默认关） | 只是外观；各平台都接受 | [Q03.1](../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)（在 K90 逐平台验证后默认打开） |
| Twitch Cookie 失效提示、17LIVE 名字颜色和徽章、酷狗 PK“对方”标记：弹幕层已上报，界面没接 | `LiveMessage.nameColor`、`badges`、`sourceRoomId` | 数据有了但看不到 | [E06.2](../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/README.md)（暂停） |
| 30 个平台弹幕任务登记为“完成”，但除哔哩哔哩外没有单独的 K90 记录；S02.2 冒烟只看了一个直播间的飞行弹幕，CHECKLIST 第 2 节第 1 条（五大平台连接和断网重连）还没填 | [CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 2 节 | 不符合 PROCESS 3.2“完成必须有真机结果”；海外平台还要代理 | 写进本单元报告；建议国内五大平台并入 S02.6，海外平台并入 S02.4（Twitch、Kick 已在里面） |
| 代码注释还用旧编号（M5、M5.17、M5.18、M5.34、B-x 的出处写成 M5.F 等） | `app/platforms.dart:190-195`、`:226`；`packages/live_danmaku/lib/live_danmaku.dart:1-5` | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换（和其他组一起） |
| 头像借用 `LiveMessage.data`（`DanmakuSender`） | `packages/live_danmaku/lib/src/sender.dart:8` | 以后读 `data` 的代码要认得它 | 需要维护者决定是否加正式字段（D01.32） |

## 相关决定和规范

- D-001：3.x 是基线，8 个老平台逐行移植、冻结输出对照。
- D-013：哔哩哔哩打码昵称不还原，做登录引导（D01.32）。
- D-017：测试里定时器至少 1 秒、不访问真实平台；用到样本时间的测试把“现在”固定成录制时间（各平台测试都这样）。
- D-018：3.x 的设置键名和含义不变（`filterDouyuSuspectedAutomatedMessages`）；新设置只加（`youtubeShowAllChat`，B-13）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：主表弹幕相关 24 条、附录 B（D01 各平台的后续升级候选，26 条）、附录 C（平台核对，C-1～C-5、C-18、C-22）。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md)：`live_danmaku` 是纯 Dart 包，只依赖 `live_core`、`live_net`；样本脱敏（门禁的样本隐私检查）。

## 测试和验证

- 自动测试：`cd packages/live_danmaku && dart test`。每个平台都有：协议单元测试、用真实样本的冻结输出对照（3.x 有的平台对照 3.x 解码器，新平台对照网页脚本或归档 v4）、连接时序（假连接器，记录计时器）、本地 WebSocket 服务器一遍。改样本要先读 `fixtures/README.md` 的脱敏规则。缺的：没有登录态的真实样本（哔哩哔哩全名、Twitch 账号）。
- 真实接口：各平台任务的记录里写了开发时用真实接口跑的结果（日期、房间、条数）；定期巡检归 E01.6。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 2 节第 1 条（五大平台连接、断网重连）、第 7 条（醒目留言、表情）；哔哩哔哩访客提示见 [D01.32 的 verify.md](D01.32-哔哩哔哩访客昵称和粉丝牌/verify.md)。S02.2 冒烟（2026-10-02，`288fec0ec`）看到飞行弹幕带表情图。

## 路线

1. D01.32 的真机验证（和 D02.1 同一轮，都要未登录的哔哩哔哩）。
2. 补真机结果：国内五大平台的连接、断网重连、醒目留言（并入 S02.6 第 1 阶段），海外平台（S02.4，要代理）。
3. Q03.1：握手 User-Agent 在 K90 上逐平台验证后默认去掉 Dart 前缀。
4. E06.2：把 17LIVE 名字颜色和徽章、酷狗 PK、Twitch Cookie 提示接到聊天列表。
5. 受阻的两个（D01.18、D01.19）和 CC 只在解除条件满足时再开工；新平台的弹幕随 E 组平台任务登记。新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [D 弹幕](../README.md)。

- 代码：`packages/live_danmaku/lib/src/sites/`
- 进度：`███████████████████░` 97%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| D01.1 | 弹幕框架和过滤 | 平台 | 完成 | 2026-09-29 | 1251ad846 | [记录](D01.1-弹幕框架和过滤/record.md) |
| D01.2 | 哔哩哔哩 弹幕 | 平台 | 完成 | 2026-09-29 | 95adcea10 | [设计或说明](D01.2-哔哩哔哩弹幕/README.md)、[记录](D01.2-哔哩哔哩弹幕/record.md) |
| D01.3 | 斗鱼 弹幕 | 平台 | 完成 | 2026-09-29 | 04717fcf9 | [设计或说明](D01.3-斗鱼弹幕/README.md)、[记录](D01.3-斗鱼弹幕/record.md) |
| D01.4 | 虎牙 弹幕 | 平台 | 完成 | 2026-09-29 | 5051893e3 | [设计或说明](D01.4-虎牙弹幕/README.md)、[记录](D01.4-虎牙弹幕/record.md) |
| D01.5 | 抖音 弹幕 | 平台 | 完成 | 2026-09-29 | a4959ea90 | [设计或说明](D01.5-抖音弹幕/README.md)、[记录](D01.5-抖音弹幕/record.md) |
| D01.6 | 快手 弹幕 | 平台 | 完成 | 2026-09-29 | 60e8e0278 | [设计或说明](D01.6-快手弹幕/README.md)、[记录](D01.6-快手弹幕/record.md) |
| D01.7 | YY 直播 弹幕 | 平台 | 完成 | 2026-09-29 | 8122b9713 | [设计或说明](D01.7-YY直播弹幕/README.md)、[记录](D01.7-YY直播弹幕/record.md) |
| D01.8 | SOOP 弹幕 | 平台 | 完成 | 2026-09-29 | e97d20574 | [设计或说明](D01.8-SOOP弹幕/README.md)、[记录](D01.8-SOOP弹幕/record.md) |
| D01.9 | Twitch 弹幕 | 平台 | 完成 | 2026-09-29 | 9f1f3de1f | [设计或说明](D01.9-Twitch弹幕/README.md)、[记录](D01.9-Twitch弹幕/record.md) |
| D01.10 | AcFun 弹幕 | 平台 | 完成 | 2026-09-29 | 36285b104 | [设计或说明](D01.10-AcFun弹幕/README.md)、[记录](D01.10-AcFun弹幕/record.md) |
| D01.11 | Picarto 弹幕 | 平台 | 完成 | 2026-09-29 | 863bbf99c | [设计或说明](D01.11-Picarto弹幕/README.md)、[记录](D01.11-Picarto弹幕/record.md) |
| D01.12 | TwitCasting 弹幕 | 平台 | 完成 | 2026-09-29 | a4cb9a72e | [设计或说明](D01.12-TwitCasting弹幕/README.md)、[记录](D01.12-TwitCasting弹幕/record.md) |
| D01.13 | 猫耳 FM 弹幕 | 平台 | 完成 | 2026-09-29 | 700066213 | [设计或说明](D01.13-猫耳FM弹幕/README.md)、[记录](D01.13-猫耳FM弹幕/record.md) |
| D01.14 | 克拉克拉 弹幕 | 平台 | 完成 | 2026-09-29 | 644d18e6b | [设计或说明](D01.14-克拉克拉弹幕/README.md)、[记录](D01.14-克拉克拉弹幕/record.md) |
| D01.15 | niconico 弹幕 | 平台 | 完成 | 2026-09-29 | 67dba6d24 | [设计或说明](D01.15-niconico弹幕/README.md)、[记录](D01.15-niconico弹幕/record.md) |
| D01.16 | SHOWROOM 弹幕 | 平台 | 完成 | 2026-09-29 | a30d7aedd | [设计或说明](D01.16-SHOWROOM弹幕/README.md)、[记录](D01.16-SHOWROOM弹幕/record.md) |
| D01.17 | CHZZK 弹幕 | 平台 | 完成 | 2026-09-29 | 00da1b768 | [设计或说明](D01.17-CHZZK弹幕/README.md)、[记录](D01.17-CHZZK弹幕/record.md) |
| D01.18 | LiveMe 弹幕 | 平台 | 受阻 | 2026-09-29 | 2d1994160 | [设计或说明](D01.18-LiveMe弹幕/README.md)、[任务书](D01.18-LiveMe弹幕/brief.md)、[记录](D01.18-LiveMe弹幕/record.md) |
| D01.19 | TikTok 弹幕 | 平台 | 受阻 | 2026-09-29 | d1db5734e | [设计或说明](D01.19-TikTok弹幕/README.md)、[任务书](D01.19-TikTok弹幕/brief.md)、[记录](D01.19-TikTok弹幕/record.md) |
| D01.20 | YouTube 弹幕 | 平台 | 完成 | 2026-09-29 | da62d0146 | [设计或说明](D01.20-YouTube弹幕/README.md)、[记录](D01.20-YouTube弹幕/record.md) |
| D01.21 | BIGO LIVE 弹幕 | 平台 | 完成 | 2026-09-30 | 51ca7deda | [设计或说明](D01.21-BIGOLIVE弹幕/README.md)、[记录](D01.21-BIGOLIVE弹幕/record.md) |
| D01.22 | PandaTV 弹幕 | 平台 | 完成 | 2026-09-29 | 2a6b552b2 | [设计或说明](D01.22-PandaTV弹幕/README.md)、[记录](D01.22-PandaTV弹幕/record.md) |
| D01.23 | FC2 LIVE 弹幕 | 平台 | 完成 | 2026-09-30 | ecfea58fb | [设计或说明](D01.23-FC2LIVE弹幕/README.md)、[记录](D01.23-FC2LIVE弹幕/record.md) |
| D01.24 | Steam 直播 弹幕 | 平台 | 完成 | 2026-09-30 | 3a9914ad8 | [设计或说明](D01.24-Steam直播弹幕/README.md)、[记录](D01.24-Steam直播弹幕/record.md) |
| D01.25 | 京东直播 弹幕 | 平台 | 完成 | 2026-09-30 | 20deb4695 | [设计或说明](D01.25-京东直播弹幕/README.md)、[记录](D01.25-京东直播弹幕/record.md) |
| D01.26 | 酷狗直播 弹幕 | 平台 | 完成 | 2026-09-30 | 8fe5c32bb | [设计或说明](D01.26-酷狗直播弹幕/README.md)、[记录](D01.26-酷狗直播弹幕/record.md) |
| D01.27 | 百度直播 弹幕 | 平台 | 完成 | 2026-09-30 | cdb9504e3 | [设计或说明](D01.27-百度直播弹幕/README.md)、[记录](D01.27-百度直播弹幕/record.md) |
| D01.28 | 六间房 弹幕 | 平台 | 完成 | 2026-09-30 | 3a6825c91 | [设计或说明](D01.28-六间房弹幕/README.md)、[记录](D01.28-六间房弹幕/record.md) |
| D01.29 | LOOK 直播 弹幕 | 平台 | 完成 | 2026-09-30 | 3da78f071 | [设计或说明](D01.29-LOOK直播弹幕/README.md)、[记录](D01.29-LOOK直播弹幕/record.md) |
| D01.30 | 17LIVE 弹幕 | 平台 | 完成 | 2026-09-30 | 447e34074 | [设计或说明](D01.30-17LIVE弹幕/README.md)、[记录](D01.30-17LIVE弹幕/record.md) |
| D01.31 | Kick 弹幕 | 平台 | 完成 | 2026-10-01 | 6c68f0010 | [设计或说明](D01.31-Kick弹幕/README.md)、[记录](D01.31-Kick弹幕/record.md) |
| D01.32 | 哔哩哔哩访客昵称提示和登录引导、粉丝牌和头像 | 功能 | 待真机 | 2026-10-02 | 2eea8022a | [任务书](D01.32-哔哩哔哩访客昵称和粉丝牌/brief.md)、[记录](D01.32-哔哩哔哩访客昵称和粉丝牌/record.md) |

## 还没完成的

- **D01.18 LiveMe 弹幕**（受阻，—，规模 中）
  - 说明：要登录才能连弹幕，调查完成
- **D01.19 TikTok 弹幕**（受阻，—，规模 中）
  - 说明：要签名才能连弹幕，调查完成

<!-- docs:生成结束 -->
