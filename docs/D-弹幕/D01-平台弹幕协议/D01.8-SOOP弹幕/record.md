# D01.8 弹幕：SOOP

- 日期：2026-09-29
- 目标：
  - `packages/live_danmaku/lib/src/sites/soop.dart`：`SoopDanmakuProtocol` 编解码、`SoopDanmakuConnection` 连接；
  - `packages/live_danmaku/lib/src/sites/soop/chat_socket.dart`：保留请求头大小写的 WebSocket 连接器 `connectSoopChatSocket`（`SoopChatSocket`），包内私有，不导出（见“做法”最后一条）。
- 参数：`live_core` 的 `SoopDanmakuArgs`（E03.1）：TLS 地址 `url`（`CHPT + 1`）、明文地址 `plainUrl`（`CHPT`）、`CHATNO`、握手请求头（v3 的 API 请求头换上 `Origin: https://play.sooplive.co.kr`，存了 Cookie 时带上；键是小写）。聊天主机取 `CHDOMAIN`，没有时由 `CHIP` 拼成 `chat-<十六进制>.sooplive.com`（7-6，E03.1 已改）。回答里没有 `CHATNO` 或聊天主机的房间（-6、-8、-14 等）没有弹幕参数，同 v3。
- 样本：
  - `fixtures/soop/danmaku/S07-live`：真实录制（2026-09-27，主播 `khm11903`，约 20 s，3589 帧：3 帧发出、3586 帧收到），来自归档。收到的包：服务 1（登录应答）、2（加入应答）各 1 个，5（聊天）144 个，4（观众名单）2045 个，127（观众标记）1386 个，12、19、21、54、90、94、110 共 9 个。`meta.json` 记着两次握手：先 TLS 端口 9001，后明文端口 9000，录到的是明文端口上的会话；
  - `fixtures/soop/danmaku/S08-synthetic`：本模块补的合成帧（`cases.json`，22 组），编号接在 S07 之后：移植 v3 的 3 个用例，以及切包的各种停止条件（前缀、服务号、长度、负长度、截断、残余字节）、宽松的数字读法、不检查的保留字节、字段数、空文字和空昵称、`-1` 与 `1`、含 `|` 的文字、去空白、坏 UTF-8、韩文和表情、其他服务、录制那样的空名单包夹着聊天；
  - 两个目录的 `expected.json` 都由 `fixtures/soop/danmaku/legacy_expected.dart` 生成：它把 v3 `SoopDanmaku` 的包字符串、`joinRoom`、`_calculateByteSize`、`heartbeat`、`decodeMessage`、`_decodeChatPacket` 和 `ListUtil.splitList` 原样搬进独立程序，只把日志换成标准错误输出、`onMessage` 换成列表、`WebScoketUtils` 换成记下发送内容的桩，模型删到只剩字段。运行：`dart run fixtures/soop/danmaku/legacy_expected.dart`（仓库根目录）。
- 脱敏核对：归档的录制工具已把聊天发送者的 id 换成同形同长的假名（保留 `(2)` 这种后缀）、昵称换成 `观众N` 或同形的假名，名单、标记等不解码的服务只留包头、清空包体（`meta.json` 的 `scrubbed`）。这次逐个看了 144 个聊天包的 16 个字段：其余字段是标志位（`589856|163840`）、订阅月数、昵称颜色（`C25111`，多人共用）和 `-1`，不含个人标识；登录和加入应答只有公开的房间号 `4172` 和主播 id。没有要补换的值，`frames.jsonl` 和 `meta.json` 没有改动，门禁的 `fixture privacy` 通过。
- 参考：
  - v3：`legacy/lib/core/danmaku/soop_danmaku.dart`；`core/utils/yy/yy_web_socket_channel.dart`（`connectCaseSensitiveWebSocket`、`YyWebSocketChannel`、`buildYyWebSocketHandshake`、`validateYyWebSocketHandshake`）；`core/common/web_socket_util.dart`；`core/site/soop/soop_site.dart`（`getHeaders`、`buildDanmakuWebSocketUrl`）；`core/common/utils/list_util.dart`；测试 `test/soop_danmaku_test.dart`（3 个用例）和 `test/yy_web_socket_channel_test.dart`（4 个，其中 1 个是 SOOP 的握手）；
  - 归档 v4（`archive/v4`，6ba709135）的 `packages/live_danmaku/lib/src/sites/soop.dart`、`runtime/exact_websocket.dart`，规格 `spec/sites/soop.md` 第 7 节、回归条目 REG-SOOP-001、002，录制工具的 SOOP 脱敏规则 `tools/live_cli/lib/src/danmaku/scrub_soop.dart`；
  - pure_live_TV `e1cca224` 的 `lib/platforms/soop/soop_danmaku.dart`（见“上游核对”）；
  - 2026-09-29 在本机（WSL，直连）对聊天服务器的实测，见问题 1、2。

## 做法

- **连接用 D01.1 的 WebSocket 运行时**，平台只写四样：
  - 地址：先 `url`（v3 连的 TLS 端口），失败后换 `plainUrl`（明文端口，差异 1）；子协议 `chat`；
  - 请求头：参数里的请求头，名字恢复成 v3 的写法（每个词首字母大写：`user-agent` → `User-Agent`，`sec-fetch-dest` → `Sec-Fetch-Dest`），顺序不变。于是握手里的请求头与 v3 逐字相同：`Accept`、`Origin`、`Referer`、`Sec-Fetch-Dest`、`Sec-Fetch-Mode`、`Sec-Fetch-Site`、`User-Agent`（Chrome 128）、`Cookie`。连明文端口时不带 `Cookie`（差异 2）；
  - 打开即就绪（v3 在 `onReady` 里先 `markConnected`、报 `onReady`，再 `joinRoom`），随后立即发登录包，200 ms 后发加入包（`run.delay`）；每次重连都重新发。200 ms 里换了连接时，旧连接的加入包不发，新连接自己会发（差异 4）；
  - 心跳：每 20 s 发一次；
  - 包都照 v3 用文本帧（字符串）发送；
  - 其余用 `DanmakuSocketPolicy` 的默认值，也就是 v3 `WebScoketUtils` 的默认值：无消息 90 s（max(3 × 20 s, 90 s)）换连接，握手超时 10 s，连续失败 8 次放弃。两个地址时失败后先换另一个，重连间隔依次是 1、2、2、3、3、4、4、5 s。没有加入计时器（v3 没有）；
  - 参数是 null（房间没有聊天服务器）时以 `DanmakuCloseReason.connectionFailed` 结束，不连接，对应 v3 的“服务器连接失败”（D01.1 对照表）；其他类型抛 `ArgumentError`。
- **协议照 v3 的 `SoopDanmaku`**，写成纯函数，不做 I/O：
  - 包：`ESC TAB`（`1B 09`）、4 位十进制服务号、6 位十进制包体字节数、`00`、包体；包体的字段以换页符（`0C`）分隔；
  - 登录包 `ESC TAB 0001 000006 00 \f\f\f16\f`；加入包 `ESC TAB 0002 <CHATNO 的 UTF-8 字节数 + 6> 00 \f<CHATNO>\f\f\f\f\f`；心跳 `ESC TAB 0000 000001 00 \f`；
  - 切包：从头按长度逐个切，遇到没有 `ESC TAB`、服务号或长度不是数字、长度为负、超出帧尾时停下，丢掉帧的其余部分；最后不足 14 字节的残余不管；长度后面的两个字节不检查。数字照 v3 用 `int.tryParse` 读，所以也接受空白、正号和 `0x`；
  - 只有服务 5 是聊天：字段少于 7 个的不要；文字取字段 1、昵称取字段 6，都去首尾空白；文字或昵称为空、文字是 `-1` 或 `1`、文字含 `|` 的丢掉；白色；没有用户 id、消息 id、时间和等级（v3 都没填）。其他服务（名单、标记、星气球等）不解码；
  - 文本帧忽略（v3 只写日志）。
- **颜色**：固定白色，不涉及 E05.1 对数字颜色的修正。
- **握手用自带的连接器** `connectSoopChatSocket`，是 v3 `connectCaseSensitiveWebSocket`（`YyWebSocketChannel`）的移植，接口就是 `live_net` 的 `SocketConnector`：
  - 手写请求：`GET <路径> HTTP/1.1`、`Host`（非默认端口时带端口）、调用方的请求头（按原样的拼写和顺序，跳过连接器自己写的 7 个字段）、`Connection: Upgrade`、`Upgrade: websocket`、`Cache-Control: no-cache`、`Sec-WebSocket-Key`、`Sec-WebSocket-Version: 13`、`Sec-WebSocket-Protocol: chat`。与 v3 的 `buildYyWebSocketHandshake` 逐行相同；请求头里有换行时拒绝（v3 没有检查）；
  - 检查回答：状态 101、`Connection` 含 `upgrade`、`Upgrade: websocket`（不分大小写，SOOP 回的是 `WebSocket`）、`Sec-WebSocket-Accept`（用 `crypto` 的 sha1）、子协议必须是提供过的；这几个字段重复出现也算失败。响应头最多 32 KiB；
  - 帧：客户端帧加掩码；文本帧交出字符串、二进制帧交出字节；分片拼接；回应 ping；关闭时最多等 1 s 对方的关闭帧；RSV 位、未知操作码、错误的控制帧、超过 16 MiB 按协议错误关闭（1002），坏 UTF-8 的文本帧 1007。都照 v3；
  - `wss` 走 TLS，ALPN 只提供 `http/1.1`（v3）；不走代理，`route` 参数被忽略（v3，问题 5）；
  - 整个握手（TCP、TLS、升级）限制在 10 s 内（差异 5），超时或失败时关掉 socket。
- **与 D01.7（YY）的协调**：YY 在并行做共用的保留大小写连接器（`src/exact_websocket.dart`）。为了不冲突，本模块把连接器写成 SOOP 私有的文件，不新建共享文件。两边合并后由主会话改用 YY 的那份：把 `soop.dart` 里的 `connectSoopChatSocket` 换掉，删除 `src/sites/soop/chat_socket.dart` 和测试里“保留大小写的连接器”一组。换的时候要保证：请求头按调用方的拼写和顺序写出、子协议 `chat`、`Upgrade` 的值不分大小写、仍然直连（除非用户批准走代理）；不往明文端口发 Cookie 的包装在 `soop.dart` 里，与连接器无关，保留即可。

## 与 v3 的对照

对照方式：同一份帧分别给新代码和 v3 的解码代码（`legacy_expected.dart`），逐条比较消息的全部字段（类型、用户名、用户 id、文字、颜色、消息 id、发送时间、等级和粉丝牌字段、是否本地、`data`）。

| 样本 | 结果 |
|---|---|
| S07 发出的帧 | 登录包、加入包（`CHATNO` 4172）、心跳与 v3 逐字节相同，也与录下的 3 帧发出帧相同；另核对了 `CHATNO` 为 `1`、`123456789`、`채팅`（按 UTF-8 算长度）的加入包 |
| S07 收到的 3586 帧 | 144 条聊天，顺序、所在的帧和全部字段一致；每帧切出的包长加起来正好等于帧长，各服务的包数如上 |
| S08 移植 v3 的 3 个用例 | 一致 |
| S08 其余 19 组 | 一致 |
| 握手 | 地址与录制的两次握手逐字相同（`wss://chat-6e0a4c63.sooplive.com:9001/Websocket/khm11903`、`ws://…:9000/…`）；请求头的名字、顺序、取值与 v3 `getHeaders()` 加上 UA 和 `Origin` 后的结果相同（Cookie 为空时不带，E03.1 差异 13）；请求行和升级字段与 v3 的 `buildYyWebSocketHandshake` 相同 |

解码没有有意差异，测试要求完全相等。

## 审查发现的 v3 问题

位置相对 `legacy/lib/`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 在本机的网络下 SOOP 弹幕连不上：9 次都失败后提示“服务器连接失败重连超过最大次数” | `core/danmaku/soop_danmaku.dart:77-79`；`core/site/soop/soop_site.dart:589-612` | v3 只连 `CHPT + 1` 的 TLS 端口。2026-09-29 实测：`chat-6e0a4c63.sooplive.com:9001` 在 ClientHello 之后直接断开（openssl、Python，TLS 1.2 和 1.3 都一样），明文端口 9000 对大小写正确的握手立即回 101。归档规格 2026-09-27 的实测相同，经代理也一样（REG-SOOP-002） | TLS 端口失败后换明文端口（E03.1 已给出 `plainUrl`）。同日用新代码连一个在播房间：约 1 s 时 TLS 失败、报一次重连，约 2.8 s 就绪，25 s 内收到 20 条聊天 |
| 2 | dart:io 的握手被挂起 | v3 已处理（`core/utils/yy/yy_web_socket_channel.dart`） | dart:io 把请求头名字写成小写，聊天服务器不回应（REG-SOOP-001）。实测再确认：同一个请求只把字段名改成小写，服务器 8 s 没有回应 | 保留：自带连接器。测试里用一个只认大小写正确的本地服务器：dart:io 的连接超时，新连接器升级成功 |
| 3 | 每条聊天的全部字段（含发送者 id 和昵称）写进调试日志；参数整段写进日志；文本帧整段按警告写日志 | `core/danmaku/soop_danmaku.dart:76、148、184` | 调试遗留 | 不移植 |
| 4 | 握手最长约 20 s | `core/utils/yy/yy_web_socket_channel.dart:120-147` | TCP 连接有 10 s 超时，发出请求后又单独等 10 s | 整个握手 10 s（差异 5） |
| 5 | 弹幕不走代理 | `core/utils/yy/yy_web_socket_channel.dart:21-38` | `connectCaseSensitiveWebSocket` 为 YY 写成始终直连（注释说“其他平台仍走代理”），SOOP 共用它后也不走代理了 | 按 v3 保留（D01.1 对照表），列为后续升级候选 |
| 6 | 文字是 `1`、`-1` 或含 `\|` 的聊天整条不显示 | `core/danmaku/soop_danmaku.dart:189` | 没有注释说明要挡什么（可能是某种系统包）；韩国直播间常见观众打“1”参与投票 | 按 v3 保留（没有样本说明这类包的来历），列为后续升级候选 |

另外两处属于框架，D01.1 已处理：v3 的 `start` 不等连接（`webScoketUtils?.connect()` 没有 await，D01.1 差异 4），再次 `start` 不关旧连接（D01.1 差异 3）。

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | TLS 端口失败后换明文端口，之后在两个端口间轮换 | 问题 1。能连 TLS 的网络上与 v3 相同（先连 TLS）。代价：TLS 不通的网络上，每次进房先出现一次“正在尝试重连”，1～2 s 后连上；以后断线也先试 TLS |
| 2 | 用户的 Cookie 只随 TLS 握手发送 | 明文端口会把登录 Cookie 明文发出去；读聊天不需要 Cookie（归档 v4 一直匿名连接，录制也是匿名的） |
| 3 | 请求头名字在这里恢复成 v3 的写法 | E03.1 的参数和其他平台一样用小写键；这个连接器按原样发出，所以由本模块恢复 v3 的拼写，线上看到的与 v3 相同 |
| 4 | 加入包只发给打开它的那次连接 | v3 等 200 ms 后发给“当前”的连接（`core/danmaku/soop_danmaku.dart:115-124`），这 200 ms 里若已重连，新连接会先收到旧的加入包、再收到自己的登录和加入包。重连至少等 1 s，线上看不出差别；这样写是为了不依赖这个时间关系 |
| 5 | 整个握手 10 s | 问题 4；与 `live_net` 的 `connectIoSocket` 一致 |
| 6 | 请求头里有换行时拒绝连接 | 手写 HTTP 请求要防止注入；E03.1 已去掉 Cookie 里的控制字符，正常数据不会遇到 |
| 7 | 回调换成事件；`connect(null)` 以 `connectionFailed` 结束，其他类型抛 `ArgumentError` | D01.1 的统一接口；v3 `start(null)` 报“服务器连接失败”，其他类型强制转换失败 |
| 8 | 不写调试日志 | 问题 3 |

保持 v3 行为、没有顺手改的地方：

- **打开即就绪**，不等登录应答（服务 1）或加入应答（服务 2）；固定等 200 ms 再加入。归档 v4 改成收到登录应答再加入、收到加入应答才算就绪，没有采用。
- **包用文本帧发送**。归档 v4 用二进制帧（它的实测说两种都被接受）。
- **聊天不带用户 id**（字段 2 有，归档 v4 用了它）、消息 id 和时间，所以 D01.1 的去重闸门按类型、昵称和文字在 2.5 s 内去重。
- **`1`、`-1`、含 `|` 的聊天丢掉**（问题 6）。
- **不显示星气球（可能是服务 18）、进场、名单**：v3 没有显示。
- **不走代理**（问题 5）。
- **数字按 `int.tryParse` 宽松读**，负长度才算坏包。
- **每次重连都报一次 `DanmakuReady`**，一轮失败只报一次重连（D01.1 的运行时，和 v3 一样）。

## 回归条目的覆盖

- REG-SOOP-001（保留大小写的握手、`chat` 子协议）：握手文本逐行断言；只认大小写正确的本地服务器上，dart:io 的连接超时、新连接器升级；整段录制的端到端回放也走这个服务器，并核对服务器收到的每个请求头。
- REG-SOOP-002（TLS 端口不通时退回明文端口）：地址顺序与录制的两次握手相同；TLS 失败 1 s 后换明文端口，登录、加入照发，不带 Cookie；持续失败时两个端口轮换。

## 登记方式

应用（I01.1）建 `DanmakuRegistry` 时：

```dart
SiteIds.soop: SoopDanmakuConnection.new,
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `connector` | 否 | 只给测试替换握手；换成什么都不会把 Cookie 发到明文端口 |

不需要 HTTP 客户端、代理、Cookie 或设置：地址、`CHATNO`、请求头和用户的 Cookie 都在 `SoopDanmakuArgs` 里（E03.1 取房间时放入，Cookie 来自 `CookieVault`）；照 v3 直连，所以没有 `proxy` 参数。房间没有弹幕参数（null）时也照常调用 `connect(null)`，由它报 `connectionFailed`。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 连接状态的提示文字（TLS 不通的网络上，进房会先出现一次重连提示） | M13（D01.1 的原因表） |
| 房间没有弹幕参数时照 v3 调用 `connect(null)`，界面显示“服务器连接失败” | M13 |
| 合并 YY（D01.7）后改用共用的保留大小写连接器 | 主会话（合并时，见“做法”最后一条） |
| 平台表的登记 | I01.1 |

## 上游核对

pure_live_TV `e1cca224` 的 SOOP 弹幕与 v3 相同，只把提示文字换成了多语言键（`danmaku_connect_failed`、`danmaku_reconnecting`），仍然只连 TLS 端口、同样用 `connectCaseSensitiveWebSocket`。没有可采用的修复。

## 升级条目

- **7-6（只有 `CHIP` 时聊天服务器改用 `.sooplive.com`）**：E03.1 已在平台层改好 `SoopApi.danmakuArgs`；连接直接使用参数给的地址，不再自己拼主机。测试核对：只给 `CHIP` 110.10.76.99 时，连接依次连向 `wss://chat-6e0a4c63.sooplive.com:9001/Websocket/khm11903` 和 `ws://…:9000/…`，正是录制时 `CHDOMAIN` 给的主机和两次握手的地址。2026-09-29 实测一个在播房间，去掉 `CHDOMAIN` 后由 `CHIP` 拼出的主机与 `CHDOMAIN` 相同。`docs/specs/UPGRADES.md` 的状态改为完成。
- 表里 SOOP 的其他条目（7-1～7-5、7-7～7-9）不涉及弹幕。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 弹幕握手走应用的代理设置（归档 v4 的 `ExactWebSocket` 用 `CONNECT` 实现过）。**已做（D01 后续升级（原 M5.F））** | 始终直连 | 问题 5。本机直连明文端口可用，没有必须走代理的证据 |
| 2 | 显示文字是 `1`、`-1` 或含 `\|` 的聊天。**已做（D01 后续升级（原 M5.F））** | 丢掉 | 问题 6；先录到这类包再决定 |
| 3 | 聊天带上发送者 id（去掉 `(n)` 后缀）。**已做（D01 后续升级（原 M5.F））** | 没有 | 字段 2；去重闸门能区分同名的人 |

## 新增的通用能力、依赖

没有。连接器用的 `crypto` 在 D01.6 已是 `live_danmaku` 的依赖；只在 `live_danmaku.dart` 里加了一行导出，框架文件没有改。

## 测试

`soop_test.dart` 50 个用例，`live_danmaku` 共 384 个，连续跑 3 次全部通过。另做了变异检查：去掉“不是当前这次打开就不发加入包”的判断、去掉明文端口去 Cookie 的包装，对应用例都会失败。

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 5 | 登录、加入、心跳与 v3、录制逐字节相同（含 UTF-8 长度）；录制的每一帧切包完整、各服务的包数；地址与录制的两次握手相同；握手请求头与 v3 的拼写、顺序、取值相同，明文端口去掉 Cookie；聊天消息的全部字段 |
| 录制帧（S07）对照 v3 | 1 | 3586 帧逐条对照 144 条消息 |
| 合成帧（S08）对照 v3 | 23 | 22 组各一个用例，另有一个检查每组都有 v3 输出 |
| 保留大小写的连接器 | 7 | 握手文本逐行（控制字段由连接器写、带换行的请求头被拒）；回答的检查（RFC 6455 的 accept 例子、状态、升级字段、accept、重复字段、子协议）；与只认正确大小写的本地服务器往来：二进制和文本、分片、ping、7 万字节的帧、关闭握手；对方关闭帧的代码和原因；RSV 位的协议错误；dart:io 的小写握手超时而本连接器升级、代理路线被忽略；被拒、中途断开、无回应在超时内失败并关掉 socket，非 ws 地址 |
| 连接 | 14 | 地址、子协议、请求头、直连、打开即就绪、登录后 200 ms 加入；策略（20 s、90 s、无加入计时器、8 次）；20 s 心跳和手动心跳（文本帧）；回放整段录制得到 v3 的 144 条、文本帧忽略；TLS 失败 1 s 后换明文端口且不带 Cookie；只有 `CHIP` 时的主机（7-6）；断线重连后重新登录加入、再次就绪；换连接后旧的加入包不发；两个端口轮换、1、2、2、3、3、4、4、5 s 后放弃；`close` 之后没有加入、事件和心跳；换房间；没有聊天数据时 `connectionFailed`、参数类型；平台表登记；只认正确大小写的本地服务器端到端回放整段录制 |

## 改用共享连接器（2026-09-29）

D01.7 YY 合并后，SOOP 改用共享的 `connectExactWebSocket`（`src/exact_websocket.dart`），删除了私有的 `src/sites/soop/chat_socket.dart` 和它的 7 个测试。共享连接器同样按调用方的拼写和顺序写请求头、支持子协议 `chat`、`Upgrade` 的值不分大小写、总是直连。私有实现里“请求头带换行时拒绝连接”这一条已移到共享连接器（YY 也受益），测试一并移到 `exact_websocket_test.dart`。明文端口剥 Cookie 的包装仍在 `soop.dart`。

## 后续升级（D01 后续升级（原 M5.F），附录 B-6）

- 日期：2026-09-30～10-01
- 条目：B-6（本记录候选 1～3）：弹幕走应用的代理设置；显示文字为 `1`、`-1` 的聊天，含 `|` 的先核实不是分隔符；聊天带发送者 id。
- 依据：
  - 网页播放器脚本（2026-09-30 匿名下载；`play.sooplive.co.kr/<主播>` 现在跳到 `play.sooplive.com/<主播>`）`https://static.sooplive.com/asset/app/liveplayer/player/dist/LivePlayer.js?_=202609011100`：`readBody` 只按 `String.fromCharCode(12)`（换页符）切包体，跳过开头那一个，每段按 UTF-8 解开；`case l.SVC_CHATMESG` 取 `C = t.packet[0].replace(/\r/gi, "")` 作整段文字、`t.packet[1]` 作用户 id，`packet[3]` 为 1、2 时是工作人员、警察消息，其余都当普通聊天（`cmd: "msg"`），没有任何按 `1`、`-1` 或 `|` 过滤的地方；`|` 只在 `splitUserFlag`（标志位字段 `flag1|flag2`）和道具列表里拆分；`realID(t)` 用 `/(\w+)[\(0-9\)]*$/` 去掉 id 末尾的 `(n)`（另一处静态版本是 `/(\w+)(\(\d\))?/`，对真实 id 结果相同）。`LiveView.js` 显示聊天时只按用户的屏蔽名单过滤（`isShowChatMesg`）。
  - 新录的帧：2026-09-30 15:19～15:49 UTC（北京时间 23:19～23:49），匿名、只读、直连，主列表人数最多的 10 个直播间（`khm11903`、`rrvv17`、`galsa`、`ecvhao`、`wnnw`、`choi15778`、`b13246`、`townboy`、`xoals137`、`chanhaee`），只连明文端口，只发登录、加入和心跳，30 分钟。收到 39,209 个聊天包：每个都是 16 个字段；字段 7（标志位）全部是 `数字|数字`；另有一位观众的昵称以 `|` 结尾（字段 6，3 个包）；文字是 `1` 的 4 个（字段 5 都是 `-1`），文字是 `-1` 的 0 个，文字含 `|` 的 0 个；字段 2 带 `(n)` 的 8,270 个。用本实现解全部录制：39,208 条聊天（一个包的昵称为空），都有用户 id，4 条 `1`，没有异常。

### 做法

- **代理**：共享的 `connectExactWebSocket` 不走代理（`route` 被忽略，D01.7 照 v3 为 YY 写的），所以在框架里做了添加（`src/exact_websocket.dart`，只加不改）：
  - `ExactWebSocket.connect` 多一个参数 `route`（默认 `DirectRoute`）。`HttpProxyRoute` 时 TCP 连到代理，发 `CONNECT <主机>:<端口> HTTP/1.1` 和同样的 `Host`（IPv6 加方括号，`ExactWebSocket.tunnelRequest`），代理回 `200` 后在同一条连接上发升级请求；`wss` 先在隧道里做 TLS（`SecureSocket.secure`，SNI 是聊天服务器的主机名，ALPN 只提供 `http/1.1`），和 `HttpClient` 的做法相同。
  - 代理回的不是 `200`：`WebSocketException('Proxy refused CONNECT: <状态行>')`；代理在 `200` 之后、TLS 之前就发来数据：`WebSocketException`；应答头超过 32 KiB 同升级回答。
  - 计时：连代理的 TCP 用 `connectTimeout`；之后代理的应答、TLS 和升级的回答共用一个 `connectTimeout`（直连仍是 TCP/TLS 一个、升级回答一个，不变）。
  - 新增 `connectExactWebSocketViaRoute`（按路由连的 `SocketConnector`）。`connectExactWebSocket` 不变，YY 仍然照 v3 直连。
  - 代理的用户名、密码：应用的代理设置只有主机和端口（`live_net` 的 `HttpProxyRoute`），所以不发 `Proxy-Authorization`。
- `SoopDanmakuConnection` 新增构造参数 `proxy`（`live_net` 的 `ProxyPolicy`，默认直连），每次握手按平台 id `soop` 取路由，默认握手改用 `connectExactWebSocketViaRoute`。明文端口仍然不带 Cookie（包装在 `soop.dart`，与路由无关）。没有新设置：用的就是应用已有的代理设置和按平台的路由。
- **`1`、`-1` 的聊天**：照网页显示，不再丢掉。
- **含 `|` 的聊天**：核实了 `|` 不是协议分隔符——网页只按换页符切字段，文字字段整段显示；录到的 39,353 个聊天包（S07 的 144 个加新录的）字段数都是 16，`|` 只出现在字段 7 的两个标志位之间和用户自己起的昵称里，都在换页符切出的字段内部。所以照网页显示。录制里没有文字含 `|` 的聊天，这一点只用合成帧测。
- **发送者 id**：字段 2 去首尾空白后照网页的 `realID` 取 id（`loo3672(2)` → `loo3672`，`abc_12(13)` → `abc_12`）；字段 2 为空时 id 为空。`(n)` 是同一账号的第几个会话，去掉后同一个人的几个会话是同一个 id。

### 用户看到的变化

- 开了代理（全局或给 SOOP 单独设置）时，SOOP 弹幕也经代理连接；以前总是直连。代理不允许 `CONNECT` 到 9000、9001 端口时会连不上（以前直连能连的网络上），这时要给 SOOP 单独设直连。
- 观众打的 `1`、`-1`（韩国直播间投票常见）和带 `|` 的聊天会显示。
- 去重闸门按 id 区分：两位同名观众 2.5 s 内发同一句话都会显示；同一账号的两个会话发同一句话只显示一次。以后的屏蔽、撤回也能按 id。

### 实测

- 2026-09-30 15:42 UTC（北京时间 23:42）用本实现经本机的 HTTP 代理（`127.0.0.1:7897`）连 `chanhaee`：TLS 端口经隧道后 TLS 仍被断开（和直连一样，问题 1），约 2.5 s 报一次重连；明文端口经 `CONNECT` 连上，4.4 s 就绪，30 s 收到 48 条聊天（32 个发送者，都有 id）。同一时间直连：2.7 s 就绪，30 s 57 条。
- 代理拒绝、不回答、TLS 在隧道里开始（ClientHello 带主机名）等情况用本地的假代理测。

### 样本

- **S09-live-ones-and-bars**（新）：上面那次录制里的 4 条 `1` 和一条昵称带 `|` 的聊天，每个包单独成帧（原来的帧里还有别的包，都去掉了），`t` 是离第一帧的毫秒数。脱敏：字段 2 的 id 换成同形的合成 id（保留 `(n)`），昵称换成 `观众N`（保留昵称里的 `|`）；标志位、颜色、订阅月数等不是个人标识，保留。`meta.json` 记了来源房间、每个原始录制文件的 SHA-256 和长度、脱敏位置。门禁的 `fixture privacy` 通过。
- `legacy_expected.dart` 同时写出 S09 的 3.x 输出（3.x 把 4 条 `1` 都丢了，只剩那条昵称带 `|` 的）；S07、S08 的 `expected.json` 重新生成后没有变化。
- 录制和脱敏的脚本没有进仓库（`meta.json` 的 `tool` 写明了做法）。

### 与决定的差异

没有。没能实测的：文字是 `-1` 或含 `|` 的聊天（30 分钟、3.9 万条里一条也没有），只用合成帧测；代理的用户名、密码不支持（应用没有这项设置）。

### 测试

`soop_test.dart` 51 个（原 43 个，新增 8 个）；框架的 `exact_websocket_test.dart` 35 个（原 28 个，新增 7 个）；`live_danmaku` 共 1337 个，连续跑 3 次全部通过；这两个文件在时钟 +30 天、+1 年、+5 年下直接运行都通过，进程正常退出。

| 分组 | 用例 | 内容 |
|---|---|---|
| B-6 聊天 | 6 | S09：3.x 的输出（丢掉 4 条 `1`）和现在的（5 条，id、昵称），3.x 显示过的那一条只多了 id；S07 的 144 个聊天包字段都是 16 个、`|` 只在字段 7；`1`、`-1`、`\|`、` 1\|2\|3 `、`ㅋㅋ \| ㅋㅋ` 都是普通聊天；`realID` 的各种写法（后缀、两位数后缀、空白、空、非 ASCII、连字符）；去重闸门区分同名的两位观众、同一账号的第二个会话算同一人；S08 每条 B-6 改动都对应一组 |
| B-6 代理 | 2 | 按平台 `soop` 取路由（别的平台的设置、没给 `proxy` 时直连）；经本地假代理端到端：TLS 端口的 `CONNECT` 被拒后换明文端口，`CONNECT` 的请求行和 `Host`，升级请求的 `Host`、`Origin`，没有 Cookie，登录和加入，回放整段 S07 |
| 框架（隧道） | 7 | `CONNECT` 请求（端口、默认端口、IPv6）；`dart:io` 服务器经隧道：先 `CONNECT`、再照写的升级请求、收发帧、关闭码；`connectExactWebSocket` 仍不走代理；代理拒绝（407、坏状态行）；代理关闭、不回答、应答头超过 32 KiB；超时覆盖代理应答和升级；`wss` 在隧道里开始 TLS 且带主机名，`200` 之后 TLS 之前来数据时拒绝 |

另外把 `exact_websocket_test.dart` 里本地假服务器读客户端数据的等待从 5 s 放宽到 20 s（只影响失败时多等多久）：一次门禁（负载 24）里原有的“sends the request as written…”失败过一次，日志没留下原因，负载 41 下并行跑 84 次都没重现；直连的握手流程只是拆成了几个函数，逻辑没变。

改了原有测试的期望（测试里都注明了 B-6）：解码聊天的用例多了用户 id；S07 对照 3.x 时先断言 3.x 没有 id、其余字段相同，再断言带 id 的结果；S08 的 5 组（`-1` 与 `1`、含 `|`、坏 UTF-8、韩文和表情、名单包夹着聊天）先断言 3.x 的输出，再断言现在的；两个回放用例比较 3.x 的消息加上 id。

### 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 平台表的登记改为 `SiteIds.soop: () => SoopDanmakuConnection(proxy: proxyPolicy)`（和虎牙、克拉克拉等一样传应用的 `ProxyPolicy`） | I01.1 |
| 代理连不上 SOOP 弹幕时的提示（现在是普通的重连、失败提示） | M13（没有新的原因类型） |

框架的添加（`ExactWebSocket` 的 `CONNECT` 隧道、`connectExactWebSocketViaRoute`）写在上面“做法”里；YY 不受影响。
