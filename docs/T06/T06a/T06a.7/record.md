# T06a.7 弹幕：YY 直播

- 日期：2026-09-29
- 目标：
  - `packages/live_danmaku/lib/src/sites/yy.dart`：`YyDanmakuProtocol`（地址、请求头、时长、正文规则）、`YyDanmakuSession`（匿名握手和解码，不做 I/O）、`YyDanmakuConnection`（连接）；
  - `packages/live_danmaku/lib/src/sites/yy/packet.dart`：`YyPacketReader`、`YyPacketWriter`（小端包的读写，不导出）；
  - 框架新增 `packages/live_danmaku/lib/src/exact_websocket.dart`：`ExactWebSocket`、`connectExactWebSocket`，**保留请求头大小写的 WebSocket 握手，YY 和 SOOP 共用**（见下面一节）。
- 参数：`live_core` 的 `YyDanmakuArgs`（T02b.1：频道号 `topSid`、子频道号 `subSid`，短号房间已换成规范频道）。T02.U 的 6-7 起，未开播的房间进房时也带这个参数。
- 样本：
  - `fixtures/yy/danmaku/S08-live`：真实录制（2026-09-27，频道 54880976，约 120 s，594 帧：31 帧发出、563 帧收到），来自归档。发出的是握手的 6 个包和 25 个 AP ping；收到的是匿名登录、AP 登录、加入频道的回答各 1 个，24 个 pong，536 个用户组消息：534 个是应用 103（礼物、进场之类，归档脱敏时已清空内容），2 个是应用 31 的聊天，正文都是 XML 包着的同一句投票通知。每帧一个包，没有多包帧；
  - `fixtures/yy/danmaku/S09-synthetic`：本模块补的合成帧（`cases.json`，38 组），覆盖录制里没有的：握手各步被拒、加入别的频道、乱序的回答、按 sid 推送和经路由转发的聊天、别的频道和应用、名字（没有、空白、前后空格）、附加项、表情代码、各种 XML 正文、坏包、截断、长度越界、失败之后的状态。编号接在 T02b.1 的 S08 之后；
  - 两个目录的 `expected.json` 都由 `fixtures/yy/danmaku/legacy_expected.dart` 生成：它把 v3 的 `yy_protocol.dart` 原样搬进独立程序（逐字核对过），再加上 v3 `YyDanmaku._decodeMessage` 里把聊天变成 `LiveMessage` 的部分，模型删到只剩字段。合成帧用 v3 的 `YyProtocolWriter` 按 v3 测试里的写法生成，结果里带上帧的字节，测试直接读这些字节。运行：`dart run fixtures/yy/danmaku/legacy_expected.dart`（仓库根目录）。
- 参考：
  - v3：`legacy/lib/core/danmaku/yy_danmaku.dart`、`core/utils/yy/yy_protocol.dart`、`core/utils/yy/yy_web_socket_channel.dart`、`core/common/web_socket_util.dart`、`core/site/yy/yy_site.dart`（`getDanmaku`），测试 `test/yy_protocol_test.dart`（7 个用例）、`test/yy_web_socket_channel_test.dart`（4 个用例）；
  - 归档 v4（`archive/v4`，6ba709135）的 `packages/live_danmaku/lib/src/sites/yy.dart`、`runtime/exact_websocket.dart` 和规格 `spec/sites/yy.md` 第 7 节、回归条目 REG-YY-001、002、009、010；
  - pure_live_TV `e1cca224` 的 `lib/platforms/yy/`（见“上游核对”）。

## 做法

- **连接用 T06a.1 的 WebSocket 运行时**，平台写的部分都照 v3：
  - 地址：`wss://h5-sinchl.yy.com/websocket?appid=yymwebh5&version=3.2.10&uuid=<UUID>`，只有这一个。UUID 是随机的第 4 版 UUID，每个连接对象生成一次，重连和换房间都不换（v3 每个 `YyDanmaku` 一个）；
  - 请求头：`User-Agent`（桌面 Chrome 151）、`Origin: https://www.yy.com`，按这个顺序和写法；
  - 握手用 `connectExactWebSocket`（REG-YY-001），**总是直连**：v3 的连接器把代理客户端关掉后直接拨号，这里的连接器不看路线；
  - 打开后先标为未连接，发匿名登录；协议报告加入频道成功时才就绪（`DanmakuReady`）。打开后 15 s 还没加入：报 `handshakeTimeout`，然后重连（`joinTimeout`，T06a.1 的运行时负责计时）；
  - 协议报告失败（某一步被拒、握手数据坏了）：报 `protocolError`，详情是失败文字，然后重连；
  - 心跳：每 5 s 发 AP ping（`794116`，包体一个 `u32 0`），从 AP 登录发出后到失败前才有，之前 `heartbeat()` 什么也不发；
  - 无消息 45 s 换连接（v3 自己的 `inactivityTimeout`）；断开提示的详情是最后一次失败，压成一行、最多 120 个字符（v3 `_compactFailure`）；
  - 其余用 `DanmakuSocketPolicy` 的默认值：握手 10 s，连续失败 8 次放弃，只有一个地址所以重连间隔依次是 2、3、4、5、6、6、6、6 s；
  - **连续 9 次打开了连接却没加入（被拒或超时）就结束**（`reconnectsExhausted`，详情是最后一次的失败），加入成功后重新计数。v3 这时会一直重连下去（审查问题 2）。
- **协议照 v3 的 `YyProtocolSession`**，写成不做 I/O 的状态机 `YyDanmakuSession`：
  - 包：小端，10 字节包头 `u32 总长（含包头）`、`u32 uri`、`u16 200`；字符串是 `u16 字节数` + 字节（Latin-1 或 UTF-8），UCS-2 字符串是 `u32 字节数` + UTF-16LE。一帧可以有多个包，按总长切开；
  - 每个新连接从头握手：匿名 UDB 登录（`778244` → `778500`，`realUri` 必须是 20078，信封和结果码是 0 或 200、uid 不为 0），AP 登录（`775684` → `775940`，结果码 200），然后一起发加入频道（路由包 `513035` 包着 `2048258`，服务名 `channelAuther`，带两个匿名频道属性，REG-YY-002）和应用订阅（`538456`：31、101、102、103、17）；路由回答 `512011` 里 `2048514` 的 `loginStatus` 为 4 且频道号、子频道号一致即加入，随后发两个用户组订阅（`537944`，6 组和 2 组）；
  - 回答不在它该来的阶段就忽略；握手阶段的坏包是失败，加入之后的坏包只记一条警告；
  - 聊天：应用 31 的 `3104600`，来自用户组消息 `533080`（也可能经路由 `512011` 转来）或按 sid 推送 `28760`。频道号或子频道号与房间不同就丢（REG-YY-010）。正文去掉首尾空白，为空就丢；名字是包末尾的 UTF-8 名字，去掉首尾空白，为空时是 `YY用户`。颜色、字号、发送者 uid、附加项都读过去但不用，消息一律白色，没有用户 id、消息 id 和发送时间；
  - **XML 正文取文字**（REG-YY-009，审查问题 1）：正文以 `<?xml` 或 `<msg` 开头时，取其中所有 `txt` 元素的 `data` 属性，依次连起来并解码 XML 实体（`&amp;`、`&lt;`、`&gt;`、`&quot;`、`&apos;`、数字引用；不是合法字符的引用原样保留）；没有 `txt` 的 XML 正文不算聊天。`/{tx`、`/{mg` 这样的表情代码原样保留。别的正文不动，哪怕后面出现了 `<txt …>`；
  - 失败和警告的文字用 pure_live_TV 翻译后的英文（v3 是中文），只作 `DanmakuReconnecting`、`DanmakuClosed` 的诊断详情，界面文字由 M13 按原因给出（T06a.1 差异 1）。
- **uid 用 `int`**：v3 用 `BigInt` 读写 64 位 uid。Dart 的 `int` 是 64 位，读写的比特相同，见到的匿名 uid 都在 2³³ 以内。

## 保留大小写的握手（YY、SOOP 共用）

YY 和 SOOP 的聊天服务器只认浏览器那样写的握手：`dart:io` 把 `Connection`、`Upgrade`、`Sec-WebSocket-*` 写成小写后，服务器不回答，握手一直挂到超时（v3 注释和归档规格 §7.1 的实测）。v3 为此写了 `yy_web_socket_channel.dart`（`connectCaseSensitiveWebSocket`，YY、SOOP 都用），这里移成框架里的共用文件 `src/exact_websocket.dart`，在 `live_danmaku.dart` 里导出：

- `connectExactWebSocket` 是 `live_net` 的 `SocketConnector`，把它交给 `DanmakuSocketConnection` 的 `connector` 参数即可。YY 的连接默认就用它；SOOP（T06a.8）同样传它。
- `ExactWebSocket.handshake` 照 v3 写请求：`GET`、`Host`（默认端口不写），调用方的请求头按顺序和原样（它自己写的 `Host`、`Connection`、`Upgrade`、`Cache-Control`、`Sec-WebSocket-Key`、`Sec-WebSocket-Version`、`Sec-WebSocket-Protocol` 去掉），然后 `Connection: Upgrade`、`Upgrade: websocket`、`Cache-Control: no-cache`、`Sec-WebSocket-Key`、`Sec-WebSocket-Version: 13`，有子协议时 `Sec-WebSocket-Protocol`。
- `ExactWebSocket.verifyHandshake` 照 v3 检查回答：状态 101（HTTP/1.0 或 1.1）、`Connection` 含 `upgrade`、`Upgrade: websocket`、`Sec-WebSocket-Accept` 正确、选中的子协议必须是请求过的；这几个头重复出现也算错。
- 帧照 v3：文本帧给 `String`，二进制给 `List<int>`；分片合并；回 ping；保留位、未知操作码、没有开头的续帧、分片中又开新消息、过长或分片的控制帧、1 字节的关闭包都是协议错误（发 1002 关闭，流上报错）；文本不是合法 UTF-8 时发 1007。单条消息最多 16 MiB，回答头最多 32 KiB。客户端帧都加掩码。
- TCP（`wss` 时加 TLS，ALPN 只报 `http/1.1`）和升级回答各有 `connectTimeout`，和 v3 一样。
- **总是直连，不看代理路线**，和 v3 一样（v3 的 SOOP 也是这样）。归档 v4 的 `ExactWebSocket` 支持经 HTTP 代理 `CONNECT`，没有搬；SOOP 如果要走代理，是新的改动。
- Accept 值要 SHA-1。工作区里只有 `live_core` 依赖 `crypto`，为一处握手检查给本包加依赖不划算，文件里带了一个私有的 SHA-1（RFC 6455 的示例和跨分组边界的 7 个值与 Python `hashlib` 一致，另和 `dart:io` 的服务器互通）。

## 与 v3 的对照

对照方式：同一份帧分别给新代码和 v3 的协议代码（`legacy_expected.dart`），逐帧比较要发出的包（逐字节）、是否就绪、消息的全部字段（类型、用户名、用户 id、文字、颜色、消息 id、发送时间、等级和粉丝牌字段、是否本地、数据）、失败文字、警告、之后的阶段和心跳包。失败和警告的文字按 v3 中文 → 新英文的对照表换过再比。

| 样本 | 结果 |
|---|---|
| S08-live 发出的包 | 匿名登录、AP 登录、加入路由、应用订阅、两个用户组订阅、AP ping 与 v3 逐字节相同 |
| S08-live 与录制的发出帧 | 除加入路由里的 trace id 外逐字节相同：v3 和新代码是 `F<uid>_yymwebh5_<UUID 散列>_0`，录制工具（归档 v4）写的是 `F<uid>_yymwebh5_0`；其余段逐段相同，25 个 AP ping 都相同 |
| S08-live 收到的 563 帧 | 5 帧有结果，其余（pong、应用 103）都是空的，与 v3 一致。握手三步的发出包、就绪、阶段、心跳一致；2 条聊天除正文外一致（差异 1） |
| S09 移植 v3 的 5 个用例（握手顺序、加入别的频道、只在加入后读聊天和丢掉别的频道、一帧多包、截断的帧；另外 2 个是地址和包头，在协议测试里） | 一致 |
| S09 握手各步被拒、只有 32 位 uid、没有 uid、坏的匿名登录、乱序的回答、加入前的聊天、一帧里握手加聊天、别的应用和 uri、失败的路由、名字、附加项、表情代码、坏包、长度越界、短尾巴、失败之后 | 一致 |
| S09 的 4 组 XML 正文 | v3 把整段 XML 当正文；新代码是 `txt` 的文字（差异 1），没有 `txt` 的不算聊天 |

测试里把 XML 的差异写成对 v3 输出的变换：先断言 v3 的正文确实是 XML，再断言新代码等于换了正文的结果，其余要求完全相等。

## 实测

2026-09-29 直连、匿名、只读，用新代码连真实服务器（结果没有存成样本）：

- 开播的频道：22490906、54880976 都在 0.4 s 左右就绪；推荐页热度最高的 8 个频道同时听 90 s，收到 41 条聊天（其中有 `/{mg` 这样的表情代码），没有看到 XML 正文。
- 未开播的频道（6-7）：T02b.1 的短号样本 35340121，和主播搜索样本里 9 个 `liveOn` 为 0 的频道，全部照常加入。房间页样本 S05-page-offline 的 85520900 每次都被拒（`loginStatus` 10，没有原因文字）；别的未开播频道都能进，所以不是未开播造成的，原因平台没有说明。v3 遇到它会每 2.5 s 重连一次、永不停止；新代码重连 8 次后结束（约 20 s）。
- AP 登录的回答（`775940`）在上下文字段后面回显客户端的公网地址和 NAT 端口：三次连接里地址相同、端口不同，与录制里的地址也相同（v3 的测试在同一位置写的是 `127.0.0.1:1234`）。见下面的样本脱敏。

## 审查发现的 v3 问题

位置相对 `legacy/lib/`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 部分弹幕显示成一整段 XML：`<?xml version="1.0"?><msg><txt data="发起了欢乐投票，…" /></msg>`（录制里的 2 条聊天都是这样） | `core/utils/yy/yy_protocol.dart:441` | 正文 UCS-2 字符串原样当作文字；YY 的一部分正文是 XML 包装，文字在 `txt` 的 `data` 属性里（REG-YY-009，归档 v4 已修） | `YyDanmakuProtocol.chatText` 取 `txt` 的文字并解码实体 |
| 2 | 频道拒绝加入（或加入一直没有回答）时永远重连，每轮两条重连提示 | `core/danmaku/yy_danmaku.dart:140-145、184-191`，`core/common/web_socket_util.dart:261-265` | `WebScoketUtils` 收到任何消息都把失败次数清零，而被拒之前服务器已经回答了匿名登录和 AP 登录，被拒的回答本身也是消息，所以“连续失败 8 次放弃”永远到不了 | 平台自己数连续没加入的次数，超过策略的 8 次重连就以 `reconnectsExhausted` 结束，详情是最后一次的失败；加入后重新计数 |
| 3 | 升级回答如果在请求 `flush` 完成前就到了，连接会在 10 s 后被自己的握手计时器以超时关掉 | `core/utils/yy/yy_web_socket_channel.dart:143-147` | 计时器在 `await socket.flush()` 之后才建，而回答处理只取消已有的计时器 | 已经升级就不建计时器（有测试守着“升级后计时器不再起作用”）。实际网络上回答很少早于 `flush`，影响小 |

另外，归档的录制脱敏漏了一处：AP 登录回答（第 3 帧，`775940`）里的客户端公网地址（录制者的出口 IP）。已换成文档地址 `203.0.113.7`（同为 4 字节，包长不变），记进 `meta.json` 的脱敏记录（`apLoginReply.address`）。这个地址在归档分支和 T02 复制样本的提交里已经进了 git 历史，按“不强推”的规则没有改历史。其余字段核对过：匿名会话（uid、用户名、密码、Cookie、UUID）、加入回答的 uid、聊天发送者（uid 换过、名字是 `观众1`、附加项去掉）归档都已换成合成值，应用 103 的内容已清空，pong 里只有时间；录制里没有头像、进场和榜单。

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | XML 正文显示 `txt` 的文字；没有 `txt` 的 XML 不显示 | 问题 1。多个 `txt` 依次连起来（只见过一个的，归档 v4 只取第一个；连起来不会丢字） |
| 2 | 连续 9 次没加入就结束，不再无限重连 | 问题 2。结束的原因和详情与 socket 自己放弃时一样（`reconnectsExhausted`），界面显示 T06a.1 的“重连超过最大次数”；握手超时结束时详情是 `YY danmaku handshake timed out` |
| 3 | 升级后握手计时器不再起作用 | 问题 3 |
| 4 | 失败和警告文字是英文，只作诊断详情 | T06a.1 差异 1；措辞取 pure_live_TV 的翻译 |
| 5 | 回调换成事件，`connect` 只接受 `YyDanmakuArgs`（其他类型抛 `ArgumentError`） | T06a.1 的统一接口；v3 强制转换失败时抛类型错误 |
| 6 | 连接器在升级完成后才返回，错误是 `dart:io` 的 `WebSocketException`；握手进行中 `close` 时，这次握手由运行时放弃，等它结束（最多两个 `connectTimeout`）再关掉 | `SocketConnector` 的接口（T03a.1）；v3 在 `close` 时立即断开未完成的握手。提示文字里的错误类型名因此不同 |

保持 v3 行为、没有顺手改的地方：

- **就绪要等加入成功**，每次重连都从匿名登录开始，都报一次 `DanmakuReady`。握手超时和协议失败都会连着出现两条重连提示（自己的一条，socket 的一条“Reconnect requested”），T06a.1 已记录。
- **每个连接对象一个 UUID**，重连、换房间都不换；归档 v4 在失败后换 UUID，没有搬。trace id 仍用 v3 的公式（含 UUID 的字符串散列）。
- **被拒后立即按退避重连**，不区分会不会好转的拒绝（比如 85520900 的 10），只是加了次数上限。
- **聊天一律白色**，不读颜色字段（归档规格：实测多为 0，其余值看不出含义），没有用户 id、消息 id、发送时间，名字为空时 `YY用户`；附加项 100、101 不用。
- **应用 103（礼物、进场之类）不解码**，v3 没有。
- **不走代理**，见上一节。
- 未开播的房间和开播一样连接；什么时候连（比如只在直播间里连）由 M13 决定。

## 回归条目的覆盖

归档规格里 T02b.1 留给 T06a 的四条都有测试：

- REG-YY-001（小写握手没有回答）：`ExactWebSocket` 的请求逐行断言（YY 和 SOOP 两种），原始 TCP 服务器收到的请求与 `handshake` 逐字节相同，本地 `dart:io` 服务器端到端；YY 连接不传 `connector` 时用的就是它（代码，测试里换成了假连接器），真实服务器上的效果见上面的实测；
- REG-YY-002（加入包缺两个匿名频道属性）：加入路由与 v3 逐字节相同、与录制逐段相同；
- REG-YY-009（XML 正文）：录制的 2 条和 S09 的 4 组 XML 用例，`chatText` 的单独用例；
- REG-YY-010（别的频道的聊天）：S09 的频道、子频道用例，连接测试里别的频道和换房间后的旧频道。

## 升级条目

- **6-7 未开播的房间也给弹幕连接参数**：T02b.1 已让进房的未开播房间（含短号）带 `YyDanmakuArgs`。本模块照 v3 的协议连接它们，不看开播状态：测试用样本 S05-page-offline 经 `YyApi.roomPage`、`YyApi.offlineRoom` 得到参数，连接后加入路由请求的是频道 85520900，加入后照常收聊天；实测见上（10 个未开播频道都能进）。一直被拒的频道不再无限重连（问题 2）。`docs/specs/UPGRADES.md` 的状态改为“完成（T02.U、T06a.7）”。
- 表里 YY 的其他条目都不涉及 T06a。

## 登记方式

应用（T07a.1）建 `DanmakuRegistry` 时：

```dart
SiteIds.yy: YyDanmakuConnection.new,
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `connector` | 否 | 默认 `connectExactWebSocket`；只给测试替换握手 |
| `random` | 否 | 生成 UUID 的随机数，只给测试 |

不需要代理、HTTP 客户端、Cookie、账号或设置：弹幕是匿名的 H5 协议，v3 也不带 Cookie，握手总是直连。每个直播间 `connectionFor` 一次，得到新的 UUID，和 v3 每个直播间 `getDanmaku()` 一次一样。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| SOOP 改用共用的 `connectExactWebSocket`（T06a.8 并行开发时先用了私有实现） | 合并后由主会话统一 |
| 连接状态的提示文字（含 `handshakeTimeout`、`protocolError` 的文字）、弹幕列表 | M13（T06a.1 的原因表） |
| 名字为空时的 `YY用户` 做多语言（pure_live_TV 用的键是 `danmaku_anonymous_user`） | M13 |
| 未开播房间什么时候连弹幕、等开播时的提示 | M13 |
| YY 的表情代码（`/{tx`、`/{mg`）显示成图片：v3 没有 YY 的表情表，列为升级候选 | T01a.1 |
| 平台表的登记 | T07a.1 |
| T06a.1 记录里对照表把 SOOP 标成 T06a.7、YY 标成 T06a.9，实际编号是 YY T06a.7；没有改那份记录 | — |

## 上游核对

pure_live_TV `e1cca224` 的 `yy_protocol.dart`、`yy_web_socket_channel.dart` 与 v3 相同，只把失败和警告文字译成英文（本模块采用了这些措辞）、名字为空时的 `YY用户` 换成多语言键；`yy_danmaku.dart` 只有提示文字换成多语言键。没有行为上的修复可采用，问题 1～3 在上游也都在。

## 测试

`live_danmaku` 共 357 个用例，连续跑 3 次全部通过。本模块新增 93 个：

`test/sites/yy_test.dart` 66 个：

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 8 | v3 的地址（移植 v3 的用例）、请求头顺序、时长；UUID 的格式和随机性；包头和读写（移植 v3 的用例），越界抛错、读失败不移动位置；发出的包与 v3 逐字节相同；与录制相同（加入路由逐段比较、只有 trace id 不同）；录制里回显的地址已换成文档地址；XML 正文规则（实体、多个 `txt`、单引号、属性顺序、非法引用原样）；失败详情的压缩 |
| 录制帧（S08）对照 v3 | 3 | 563 帧逐帧对照（有结果的 5 帧和其余的空帧）；聊天的全部字段；别的频道的会话读不到聊天、加入失败 |
| 合成帧（S09）对照 v3 | 39 | 38 组各一个用例（4 组按 XML 差异变换），另有一个检查每组都有 v3 输出 |
| 连接 | 16 | 地址、请求头原样、直连、先发匿名登录、未就绪；策略（5 s、45 s、15 s、8 次）和每个对象一个 UUID；回放录制的握手后就绪、聊天去掉 XML、文本帧和别的频道；5 s 的 AP ping、AP 登录前没有；被拒一次后 2 s 重连、重新握手、同一 UUID；连续被拒 8 次重连后结束；加入后重新计数；15 s 握手超时的提示、重连、8 次后结束；断线的提示带压缩过的失败、重新加入；退避 2、3、4、5、6、6、6、6 s 后放弃；`close` 之后没有事件和心跳；换房间关掉旧连接、同一 UUID 加入新频道；未开播的房间（6-7）；参数类型；平台表登记；本地 WebSocket 服务器经 `connectExactWebSocket` 端到端回放录制 |

`test/exact_websocket_test.dart` 27 个：

| 分组 | 用例 | 内容 |
|---|---|---|
| 握手 | 4 | YY 的请求逐字（移植 v3 的用例）；端口、子协议、调用方写的受控头被去掉（移植 v3 SOOP 的用例）；Accept 值（RFC 6455 和 7 个跨分组边界的值）；回答的检查（移植 v3 的用例，另加 9 种拒绝） |
| 连接 | 16 | 原始 TCP 服务器：请求与 `handshake` 逐字节相同、随回答一起到的帧；文本、分片、带掩码的服务端帧、16 位和 64 位长度、回 pong；客户端帧加掩码和三种长度、非法数据；服务器关闭时回送并保留代码和原因；`close` 发代码、等回答；没有回答 1 s 后结束；8 种协议错误各自的关闭代码；超长帧；升级后握手计时器不再起作用 |
| 握手失败 | 6 | 非 101、错的 Accept、握手中断开、回答头超过 32 KiB、超时、不支持的协议和拒绝连接 |
| 互通 | 1 | `dart:io` 服务器：子协议、回显文本和二进制、关闭代码；给了代理路线也直连 |
