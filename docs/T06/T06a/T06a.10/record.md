# T06a.10 弹幕（新增）：AcFun

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/acfun.dart`
  - `AcfunDanmakuConnection`：连接；
  - `AcfunDanmakuProtocol`：分帧、加解密、推送解码；
  - `AcfunDanmakuLink`：一条连接上的序号、会话密钥和要发的帧。
  - 后两者都不做 I/O。
- 参数：`live_core` 的 `AcfunDanmakuArgs`，T02b.3 已给出，T02.U 的 10-4 核对过。
  - 进房时 `AcfunSite.getRoomDetail` 把它放进 `LiveRoom.danmakuData`；
  - 其中的 `refresh` 是 `AcfunSite.danmakuArgs`：新访客会话加新的 `startPlay`。
  - 本模块没有改 `live_core`。
- 升级条目：10-4“接入 AcFun 弹幕”。v3 没有 AcFun 弹幕（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 样本：`fixtures/acfun/danmaku/S07-live`，归档 v4 的真实录制。
  - 2026-09-27，房间 41254970，5 分钟，784 行：开始时的 3 个 HTTP 请求和 781 个链路帧。
  - T02 从归档复制过来；本模块补做了一处脱敏（见“样本”），并加上归档 v4 解码的冻结输出 `expected.json`。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：
    - `packages/live_danmaku/lib/src/sites/acfun.dart`（`AcfunProtocol`、`AcfunLink`、`AcfunConnector`）和 `test/acfun_test.dart`；
    - `spec/sites/acfun.md` 第 7 节。协议出自 `live.acfun.cn` 播放页脚本（2026-09-27 下载），再用这份录制核对；
    - 回归条目 REG-ACFUN-001、007；
    - 录制工具的脱敏规则 `tools/live_cli/lib/src/danmaku/scrub_acfun.dart`。
  - pure_live_TV `e1cca224`：`lib/platforms/acfun/acfun_site.dart` 仍是 `EmptyDanmaku`，没有可参考的实现。
  - 2026-09-29 只读实测：匿名，直连，用本实现连推荐里人数最多的在播房间两次（70 s、280 s），见“实测”。

## 做法

- **建在 T06a.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`）。平台代码只写这几样：
  - `target`：地址和请求头；
  - `onOpen`：发注册包；
  - `onData`：解一帧；
  - `heartbeatFrame`：心跳；
  - 另外覆盖了 `onJoinTimeout`。
  - 换地址、退避、最多 8 次、无消息超时、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **开始时不发 HTTP 请求。**
  - 进房时 T02b.3 本来就要做访客登录和 `startPlay`（取流用），`AcfunDanmakuArgs` 已经带着访客会话、`liveId`、票据和 `enterRoomAttach`。
  - 归档 v4 每次开始都自己再登录、`startPlay`、取礼物表，共 3 个请求。
  - 只有参数不能用时才调用 `refresh`（2 个请求）：没有 `acSecurity`、它不是 16 字节的 AES 密钥、没有票据。
- **协议写成纯函数和一个小的状态对象。**
  - `AcfunDanmakuProtocol`：`frame`、`unframe`、`seal`、`open`、`ack`、`heartbeatInterval`、`push`；
  - `AcfunDanmakuLink`：一条连接的上行序号、`instanceId` 和会话密钥。它照录制写出注册、保活、进房、心跳和推送确认，读下行帧。
  - 每次打开新连接都新建一个 link。
- **protobuf 用 T06a.5 手写的读写器**（`src/sites/douyin/protobuf.dart`，只引用，没改）；AES 用 `live_core` 的 `Aes128Cbc`（解密）和 `AesCbc`（加密，T02b.6、T02c.11 加的）；gzip 用 `dart:io`。没有新增依赖。
- **只上报 v3 各平台上报的两类消息**：聊天（`CommonActionSignalComment`）和在线人数（`CommonStateSignalDisplayInfo.watchingCount`）。
  - 平台没有醒目留言或付费留言；
  - 礼物、香蕉、点赞、进场、关注、进房时的最近评论都不显示，见差异 2。
- **恢复分两级：**
  - 票据失效先在同一连接上换下一张票据（网页的做法）；
  - 注册被拒、命令出错、直播状态变化、票据都失效时，刷新参数，用 `session.reopen` 换新连接（和哔哩哔哩刷新凭据一样，不提示）。
  - 刷新和票据的计数属于一次 `connect`（`DanmakuRun`）：被取代或关闭之后，晚到的刷新结果直接丢掉。

## 协议

帧（大端）：`[u16 0xABCD][u16 1][u32 头长度][u32 负载长度]`，接 `PacketHeader` 和负载，三段长度之和必须等于帧长。

| 部分 | 字段 | 说明 |
|---|---|---|
| `PacketHeader` | 1 `appId`（13）、2 `uid`（访客 id）、3 `instanceId`、7 `decodedPayloadLen`（明文长度）、8 `encryptionMode`、9 `tokenInfo {1: 1, 2: 服务令牌}`（只在注册包）、10 `seqId`、12 `kpn`（`ACFUN_APP`） | 服务端的头另有 5（录制里总是 1），不读 |
| 负载 | 16 字节 IV + AES-128-CBC（PKCS#7）密文 | 模式 1 的密钥是 `acSecurity`（Base64 解码），只用于注册和它的应答；模式 2 是注册应答给的会话密钥；模式 0 不加密（没见过，照 v4 支持） |
| 上行 `UpstreamPayload` | 1 `command`、2 `seqId`、3 `retryCount`（1）、4 `payloadData`、9 `subBiz`（`mainApp`） | `seqId` 每条连接从 1 起，每发一帧加一，推送确认除外 |
| 下行 `DownstreamPayload` | 1 `command`、2 `seqId`、3 `errorCode`、4 `payloadData`、5 `errorMsg` | |

| 帧 | 内容 |
|---|---|
| `Basic.Register`（发） | `{1 appInfo {1 "link-sdk", 4 "1.2.1"}, 2 deviceInfo {1 6（H5）, 3 "h5", 5 设备号}, 4 1, 5 1, 8 0, 11 ztCommonInfo {1 kpn, 2 "PC_WEB", 4 uid, 5 设备号}}`，模式 1 |
| `Basic.Register`（收） | `{2 会话密钥（16 字节）, 3 instanceId}`；`errorCode` 非 0 或密钥不是 16 字节算被拒 |
| `Basic.KeepAlive`（发） | `{1 1, 2 1}` |
| `Global.ZtLiveInteractive.CsCmd`（发） | `{1 类型, 2 内容, 3 票据, 4 liveId}`。进房 `ZtLiveCsEnterRoom {1 0, 2 reconnectCount, 4 enterRoomAttach, 5 "kwai-acfun-live-link"}`；心跳 `ZtLiveCsHeartbeat {1 本机毫秒时间, 2 序号（每条连接从 0 起）}` |
| `Global.ZtLiveInteractive.CsCmd`（收） | `ZtLiveCsCmdAck {1 类型, 2 错误码, 4 内容}`。进房应答的内容是 `{1 心跳间隔毫秒}`（录制和实测都是 10000） |
| `Push.*`（收） | 每个都回一帧确认：同一个 `command`、没有 `payloadData`，头里的 `seqId` 用推送自己的，上行序号不增加 |

`Push.ZtLiveInteractive.Message` 的内容是 `ZtLiveScMessage {1 类型, 2 压缩（2 为 gzip）, 3 内容, 4 liveId, 5 票据, 6 服务端时间}`：

| 类型 / 信号 | 字段 | 本实现 | 归档 v4 |
|---|---|---|---|
| `ZtLiveScActionSignal` → `CommonActionSignalComment` | 1 文本、2 发送时间毫秒、3 用户 `{1 id, 2 昵称}` | 聊天：白色、没有消息 id；id 不大于 0 时为空；文本为空或没有用户时不报；时间不大于 0 或超出 `DateTime` 范围时为空 | 聊天 |
| `ZtLiveScActionSignal` → `CommonActionSignalGift`、`AcfunActionSignalThrowBanana` | 用户、礼物 id、数量… | 不报（差异 2） | 礼物，名字查礼物表 |
| `ZtLiveScActionSignal` → 点赞、进场、关注、富文本、加入粉丝团 | — | 不报 | 不报 |
| `ZtLiveScStateSignal` → `CommonStateSignalDisplayInfo` | 1 `watchingCount`（文字，可能带“万”）、2 点赞数、3 点赞增量 | 在线人数 `onlineViewers`，用 `parseChineseCount`；不是数字时不报 | 在线人数 |
| `ZtLiveScStateSignal` → 其他（香蕉总数、榜单、红包、宝箱、最近评论） | — | 不报 | 不报 |
| `ZtLiveScNotifySignal` | — | 不报 | 不报 |
| `ZtLiveScTicketInvalid` | 空 | 换下一张票据 | 重新开始 |
| `ZtLiveScStatusChanged` | 1 类型：1 下播、2 重新开播、3 换了播放地址、4 封禁 | 1、2、4 刷新参数；3 与弹幕无关，不管 | 1 重新开始，其余不管 |

在线人数的来源：列表和详情本来就给 `onlineCount`（`audience.dart` 里 AcFun 是 `roomList`），弹幕里的 `watchingCount` 是同一个数（录制结束时 70～71 对接口的 71，实测 60～61 对列表的 60）。接入后来源没有变，`audience.dart` 不用改。

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 依据 |
|---|---|---|---|
| 地址 | `wss://link.xiatou.com/` | 同 | 录制 |
| 握手请求头 | 参数里的 UA（Chrome 140）和 `Origin: https://live.acfun.cn`。默认的 `dart:io` 握手会把自己的 UA 加在前面（`Dart/3.13 (dart:io), Mozilla/…`），实测服务端照样接受 | UA 和 Origin | 规格 7.2；实测 |
| 开始前的请求 | 无；参数不能用时刷新一次 | 访客登录、`startPlay`、礼物表 | 差异 1 |
| 加入 | 打开后发注册；注册应答后发保活和进房；进房应答错误码为 0 时报 `DanmakuReady`（已加入时不再报）。进房前收到的聊天照常上报 | 同 | 录制：发注册到进房应答约 80 ms；实测 232～317 ms |
| 加入超时 | 10 s。第一次直接换连接，不单独提示（框架默认）；连续第二次同时刷新参数 | 10 s，超时重新开始（含 3 个请求） | 差异 6 |
| 心跳 | 10 s（策略固定），只在进房之后发；手动 `heartbeat()` 同样 | 按进房应答的间隔 | 录制和实测都是 10000 ms；差异 5 |
| 保活 | 注册应答后一次，之后每第 5 次心跳一次（50 s） | 心跳应答时距上次满 45 s 就发；录制里实际 60 s 一次 | 网页 `heartBeatInterval: 5e4`；差异 4 |
| 推送确认 | 每个推送都先确认，再上报其中的消息 | 同 | 录制 353 次 |
| 无消息超时 | 90 s（max(3 × 10 s, 90 s)，策略里不单独写）。状态信号约每 2 s 一条，心跳应答每 10 s 一条 | 框架默认 | — |
| 断线重连 | 框架默认：立刻换下一个地址（只有一个），每轮多等 1 s，最多 8 次，收到任何消息清零；一轮只提示一次。重连后重新注册、进房，`reconnectCount` 是本次 `connect` 之前开过的连接数 | 框架默认；`reconnectCount` 总是 0 | 差异 9 |
| 票据失效 | 进房或心跳应答的错误码 2、3、4、7，或 `ZtLiveScTicketInvalid`：标为未加入，在同一连接上用下一张票据再进房（之后的心跳也用它）；上次加入以来每张票据都失效过，就刷新参数 | 重新开始 | 网页 `handleAck`；差异 3 |
| 刷新参数 | 注册被拒、下行信封 `errorCode` 非 0（保活、命令）、其他应答错误码（1 下播、8 重新开播、未知）、状态变化 1、2、4、票据都失效、连续两次加入超时：停掉加入计时器、标为未加入、调用 `refresh`，拿到可用的参数后 `reopen`（关掉旧连接，失败计数重新开始，不提示）。刷新进行中再出错不另起刷新，旧连接照常收消息 | 重新开始 | — |
| 刷新的结果 | 抛 `StreamUnavailable`（关播、付费直播没有票据）：`DanmakuClosed(connectionFailed)`；抛其他错误、没有 `refresh`、新参数仍不能用：`DanmakuClosed(credentialsUnavailable)`；自上次加入以来已刷新 3 次，再出错时同样结束。详情里只写错误的种类（请求错误的文字可能带着地址里的访客令牌） | 关播是终态 `noRoom`，两次失败是终态 `credentials` | 差异 7 |
| 帧解不开 | 丢掉这一帧，不影响连接：长度不符、没有魔数、密钥不对、会话密钥还没到、未知加密模式、应答或推送解不开 | 同 | — |

## 登记方式

应用（T07a.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.acfun: () => AcfunDanmakuConnection(proxy: proxyPolicy),
  // …
});
```

- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `acfun` 选路由，和接口请求用同一份设置。
- 不需要 HTTP 客户端或 Cookie：`AcfunDanmakuArgs` 自带访客会话，`refresh` 绑定 `AcfunSite` 自己的 HTTP 客户端。AcFun 全程匿名，v3 也没有它的 Cookie 设置。
- `connector` 可选，默认 `dart:io` 的握手，不需要保留大小写的 `connectExactWebSocket`（实测，见下）。
- `policy`、`now`（心跳时间戳）、`random`（IV）只给测试用，应用不传。
- 参数来自 `getRoomDetail`。录制详情（`getRoomDetailForRecording`）和关注刷新不给弹幕参数，与 T02b.3 相同。付费直播进房时没有票据，也就没有弹幕参数（T02.U）。

## 与归档 v4 的对照

对照方式：

- 解码：`fixtures/acfun/danmaku/v4_expected.dart` 把归档 v4 的 `AcfunChatSession`～`AcfunLink` 和它的 protobuf、AES 实现原样搬进一个独立程序。只替换了它从别处引用的事件类型、`DecodeContext` 和几个 JSON 小函数。
- 它用录下的 HTTP 开始（访客登录、`startPlay`、礼物表）建会话，按顺序读每个收到的链路帧，写下命令、序号、错误码、命令应答的类型和错误码、进房应答的心跳间隔，以及推送解出的事件（投影）和票据、下播标记。
- 运行：在仓库根目录 `dart run fixtures/acfun/danmaku/v4_expected.dart`，结果在 `expected.json`，`generator` 字段写明来源。
- 测试用同一份录制跑新代码，逐帧比较。

| 对照 | 结果 |
|---|---|
| 390 个收到的帧 | 命令、序号、错误码全部一致：1 个注册应答（有会话密钥）、6 个保活应答、30 个命令应答（进房应答的心跳 10000 ms，29 个心跳应答，错误码都是 0）、353 个推送 |
| 推送解出的消息 | 一致：1 条聊天（用户 id、昵称、文本、发送时间）、151 次在线人数（70～76）；录制里没有礼物和香蕉，所以“不报礼物”这一差异在样本上看不出来；没有票据失效和状态变化 |
| 391 个发出的帧 | 本实现的 link 按录制的顺序写出同样的帧，头部逐字段相同、明文逐字节相同：注册 1、保活 6、进房 1、心跳 30（时间戳取录制的）、推送确认 353。IV 是随机的，所以只比明文 |
| 用连接重放录制 | 就绪 1 次；1 条聊天和 151 次人数；先发注册，注册应答后发保活和进房，之后每个推送都确认（353） |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 开始时不自己登录和 `startPlay`，用进房给的参数；参数不能用时才刷新一次 | 请求不比需要的多：进房为取流本来就要这两个请求。v4 每次开始 3 个请求，还和取流各用一个访客会话 |
| 2 | 不请求礼物表，不上报礼物和香蕉；REG-ACFUN-007（礼物只有编号）因此不适用 | v3 所有平台都不显示礼物（`LiveMessageType.gift` 注明“not shown yet”），T06a.2～T06a.9 也都不上报。以后要显示礼物时，礼物表用和 `startPlay` 相同的查询参数请求（T02b.3、v4 规格 7.1） |
| 3 | 票据失效先在同一连接上换下一张票据，都失效过才刷新 | 网页的做法（v4 规格 7.3 记下的 `handleAck`）；换票据不用请求，v4 直接重新开始（2～3 个请求） |
| 4 | 保活按心跳次数：每第 5 次心跳（50 s） | 网页是 50 s；v4 按时间判断，录制里实际成了 60 s 一次。实测 280 s 里连接一直正常 |
| 5 | 心跳间隔固定 10 s，不读进房应答 | 框架的心跳间隔属于每个平台固定的策略；录制和实测的进房应答都是 10000 ms。`AcfunDanmakuProtocol.heartbeatInterval` 可以读出这个值，测试核对它等于策略。以后见到别的值再改成按应答设置 |
| 6 | 第一次加入超时只换连接，连续第二次才刷新参数 | 连接卡住不必重新登录；注册应答解不开（密钥过期）或票据被默默忽略时，第二次就换参数。v4 每次超时都重新开始 |
| 7 | 结束原因用 T06a.1 的类型：v4 的 `noRoom` 是 `connectionFailed`，`credentials` 是 `credentialsUnavailable`；没有加入就连续刷新 3 次也结束 | T06a.1 没有“房间已下播”这种原因，界面文字由 M13 给出。次数上限防止被拒和刷新无限循环；每次加入成功都重新计数，所以长时间观看中偶尔换票据、换会话不受影响 |
| 8 | 推送里某个信号、某条评论解不开，只跳过它；整个信号列表或 gzip 解不开，这条推送不报消息（仍然确认） | v4 在任何一处出错时整帧丢掉 |
| 9 | 进房命令的 `reconnectCount` 是本次 `connect` 之前开过的连接数 | 网页照实报重连次数；v4 总是 0 |
| 10 | 注册应答的会话密钥必须是 16 字节 | 负载是 AES-128；v4 只要求非空，长度不对时之后每一帧都解不开 |
| 11 | 下行信封的 `errorCode` 非 0 时（保活、命令、未知命令）刷新参数；推送不看它 | v4 同样重新开始；这里统一走刷新 |

没有改的地方：

- 协议帧的写法与 v4 相同，服务端接受过：录制就是 v4 连的，逐字节核对过。
- 聊天和人数的解读与 v4 相同，时间用本地时区的 `DateTime`（同一时刻），和其他平台一样。

## 实测

2026-09-29 只读、匿名、直连，没有登录，没有发言，结果没有存成样本。

- 做法：`AcfunSite.getRecommendRooms` 取推荐（11 个在播），挑人数最多的房间（40740702，列表人数 60～61），`getRoomDetail` 进房拿到参数（带 `acSecurity`、4 张票据），用默认的 `dart:io` 握手连接。
- 70 s 那次：317 ms 就绪，一直保持连接，跨过了第一次定时保活（50 s）；收到 35 次在线人数（60～61），与列表一致。
- 280 s 那次：232 ms 就绪，全程保持连接，没有重连（跨过 5 次定时保活、约 28 次心跳）；收到 141 次在线人数（60）。两次都没有人发聊天。
- 结论：
  - 服务端接受 `dart:io` 的小写请求头和拼接后的 UA，不需要 `connectExactWebSocket`；
  - 进房时那一个访客会话和票据可以直接用于弹幕；
  - 10 s 心跳加 50 s 保活不会被断开。
- 实测时段在播的房间少、人也少，聊天稀疏，聊天的解码以录制为准。

## 样本

- **补做的脱敏：链路会话号 `instanceId`。**
  - 它是服务端给这条链路的会话号，出现在两处：注册应答（用样本里的假 `acSecurity` 加密）和之后每个帧的头部（明文 protobuf）。
  - 录制工具没有替换它，这次换成同样 20 位、varint 同样 10 字节的合成值 `11400714819323198485`：
    - 头部 780 处直接改；
    - 注册应答解密、改写、用原来的 IV 重新加密，长度不变，其余字节都没动（重新解码核对过）。
  - 已记进 `meta.json` 的脱敏记录。
- **逐字段检查了全部 781 个链路帧**（用样本里的假密钥解开，递归解 protobuf，推送再解 gzip），没有其他需要换的值：
  - 头部：访客 id、服务令牌是录制时换的合成值；`seqId` 是推送序号。
  - 注册：设备号、访客 id 是合成值。
  - 进房和心跳：票据、`enterRoomAttach` 是合成值；`liveId` 是公开的直播编号，时间戳。
  - 保活应答：接入点地址录制时已丢掉，只剩服务端时间。
  - 推送：发送者的 id 和昵称是合成值（`观众1`～`观众5`，英文名是同形的随机字母），头像等其他用户字段录制时已丢掉。没有解码的信号只留类型、内容为空；在线人数、点赞数、香蕉数是公开的房间数字；推送里的票据是合成值。
  - 找不到 IPv4 地址、URL、头像路径、Cookie。
- HTTP 部分（访客登录、`startPlay`、礼物表）：令牌、`acSecurity`、访客 id、设备号、票据、`enterRoomAttach`、服务器名在录制时已换掉，礼物表是公开数据。门禁的 `fixture privacy` 通过。
- `expected.json` 是新加的冻结输出，只含上面这些已脱敏的值。

## 回归条目的覆盖

- REG-ACFUN-001（AcFun 没有弹幕）：本模块。
- REG-ACFUN-007（礼物只有编号）：不适用，见差异 2。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | T07a.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（T06a.1 的原因表） |
| 付费直播进房没有弹幕参数时的提示 | M13：按 T06a.1，平台支持弹幕但房间没有参数时不连接 |
| 显示礼物（若以后要做） | M13 统一决定；本平台需要礼物表，见差异 2 |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | T06a 各平台完成后删除 |
| `connectIoSocket` 的 UA 拼接 | 框架（`live_net`）：`dart:io` 的 WebSocket 握手会把默认的 `Dart/… (dart:io)` 和传入的 UA 拼成一个值，所有用默认握手的平台都一样。AcFun 实测不受影响，本模块没有改框架 |

## 受阻

没有。

## 测试

`test/sites/acfun_test.dart` 38 个用例，`live_danmaku` 共 559 个，连续跑 3 次全部通过：

- 协议 11 个：
  - 分帧和各种坏帧；`acSecurity` 的几种不能用的形式；加解密和错误的密钥、长度；
  - 注册包的头部和字段；注册应答后的会话密钥、`instanceId`、序号、保活、进房、心跳序号；推送确认不占序号；
  - 读帧：会话密钥未到、未知加密模式、密钥不对、被拒的注册、长度不对的会话密钥、不加密的帧；命令应答和心跳间隔；
  - 推送：普通和 gzip 的评论、不报的信号、在线人数（含“万”和非数字）、票据失效和状态变化、坏的评论和信号只跳过自己、截断和坏 gzip、未知类型、边界的 id 和时间。
- 录制 4 个：
  - 录下的 HTTP 开始给出与 v4 相同的参数；
  - 390 个收到的帧与 v4 的冻结输出逐帧一致；
  - 391 个发出的帧与本实现写出的逐字段、逐字节一致；
  - 连接重放整份录制。
- 连接 23 个：
  - 默认时序和平台表登记；握手（地址、请求头、注册、保活和进房、只在进房应答后就绪、不重复就绪）；
  - 心跳只在进房后发、每第 5 次带保活、定时器按间隔发；推送先确认再上报、其他推送也确认；坏帧只丢自己；断线重连后重新注册、带上重连次数；
  - 票据：换下一张、推送里的票据失效、都失效后刷新并换连接；
  - 刷新：注册被拒、7 种触发和不触发的状态、关播结束为 `connectionFailed` 且之后没有事件、刷新失败或没有 `refresh` 或新参数不能用都是 `credentialsUnavailable` 且详情不带令牌、同时只刷新一次和 3 次上限及加入后重新计数、关闭后晚到的刷新不起作用；
  - 开始：不发请求、参数不能用时先刷新一次（3 种）、仍不能用或下播时不开连接（4 种）、开始途中关闭；
  - 加入超时两级；关闭后没有事件；真实的本地 WebSocket 服务器（默认的 `dart:io` 握手、请求头、注册、进房、聊天、心跳）。
