# T06a.9 弹幕：Twitch

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/twitch.dart`（`TwitchDanmakuProtocol` 编解码、`TwitchDanmakuFrame` 解码结果、`TwitchDanmakuConnection` 连接）
- 参数：`live_core` 的 `TwitchDanmakuArgs`（T02c.2）：频道登录名 `channel`（小写），和同一份 Cookie 里的聊天登录 `chat`（`login` 与 `auth-token` 都有时，由 `TwitchApi.chatLogin` 读出；否则为 null，匿名加入）。这正是 v3 的 `joinRoom` 自己去设置里读的东西。Twitch 的每个房间都有弹幕参数。
- 样本：
  - `fixtures/twitch/danmaku/S07-live`：真实录制（2026-09-27，频道 `zarbex`，约 37 s，26 帧：4 帧发出、22 帧收到，都是文本帧），来自归档。收到的帧：`CAP * ACK` 1 帧，欢迎（001～004、375、372、376）1 帧 7 行，自己的 `JOIN` 和 `ROOMSTATE` 1 帧，`353`/`366` 1 帧，聊天 18 帧、每帧一行 `PRIVMSG`。发出的 4 帧是录制工具（归档 v4 的连接器）写的：`CAP REQ` 在前、不要 membership，其后 `PASS SCHMOOPIIE`、`NICK justinfan39976`、`JOIN #zarbex`；握手带了 `Origin`，经代理；
  - `fixtures/twitch/danmaku/S08-synthetic`：本模块补的合成帧（`cases.json`，24 组），编号接在 S07 之后：移植 v3 的 2 个用例，以及显示名的各种缺省、没有标签的行、各种颜色、标签转义、缺失和读不出的 id 与时间、超出范围的时间、`/me`、没有文字部分和空文字、首尾空白、其他命令、文字里含 ` PRIVMSG ` 的其他命令、二进制帧和坏 UTF-8、只用 LF 分行、服务器 `PING` 的几种位置、登录被拒、韩文中文和表情、回复；
  - 两个目录的 `expected.json` 都由 `fixtures/twitch/danmaku/legacy_expected.dart` 生成：它把 v3 `TwitchDanmaku` 的 `heartbeat`、`joinRoom`、`_parseCookie`、`decodeMessage`、`parseMessages`、`_decodeTag` 和 `start` 里把二进制帧转成文字的那一句原样搬进独立程序，只把日志换成标准错误输出、`onMessage` 换成列表、`WebScoketUtils` 换成记下发送内容的桩、设置换成存着 Cookie 的桩、`Random.secure().nextInt` 换成固定返回 38976（于是匿名昵称正是录制的 `justinfan39976`），模型删到只剩字段（颜色用 v3 的 `numberToColor`）。运行：`dart run fixtures/twitch/danmaku/legacy_expected.dart`（仓库根目录）。
- 脱敏核对：归档的录制工具已把聊天发送者的显示名、登录名（前缀和回复标签里的）、用户 id（`user-id`、`reply-parent-user-id`、`reply-thread-parent-user-id`）换成同形同长的假值，`client-nonce` 换成同形的随机串，聊天文字里提到的名字也一并换掉，`USERNOTICE` 行和删空的帧已删除（`meta.json` 的 `scrubbed`）。这次逐个看了 18 行聊天的全部标签：其余是徽章、颜色、表情位置、各种标志、消息 id（UUID，只标识这条消息）、`room-id`（公开的频道 id）和时间；非聊天的行只有匿名昵称和频道状态。回复里的 `reply-parent-*` 与被回复那条的假名一致。没有要补换的值，`frames.jsonl` 和 `meta.json` 没有改动，门禁的 `fixture privacy` 通过。
- 参考：
  - v3：`legacy/lib/core/danmaku/twitch_danmaku.dart`、`core/common/web_socket_util.dart`、`core/site/twitch/twitch_site.dart`（`getDanmaku`、`danmakuData`）、`common/models/live_message.dart`（`numberToColor`），测试 `test/twitch_danmaku_protocol_test.dart`（2 个用例）；
  - 归档 v4（`archive/v4`，6ba709135）的 `packages/live_danmaku/lib/src/sites/twitch.dart`、规格 `spec/sites/twitch.md` 第 7 节，录制工具的 Twitch 脱敏规则 `tools/live_cli/lib/src/danmaku/scrub_twitch.dart`；
  - pure_live_TV `e1cca224` 的 `lib/platforms/twitch/twitch_danmaku.dart`（见“上游核对”）；
  - 2026-09-29 在本机（WSL，直连）对 `irc-ws.chat.twitch.tv` 的实测：用 v3 的顺序匿名加入 8 个频道；用编造的令牌登录；匿名收 18 个热门频道 90 s 的聊天（967 行）做统计。见问题 1～5。

## 做法

- **连接用 T06a.1 的 WebSocket 运行时**，平台只写四样，都照 v3：
  - 地址：只有 `wss://irc-ws.chat.twitch.tv` 一个（v3 不写端口），不带请求头和子协议。录制工具握手时带了 `Origin`，v3 没带，照 v3；
  - 打开后依次发 `PASS`、`NICK`、`CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership`、`JOIN #<频道>`，每行单独一个文本帧、不加 CRLF，然后就算加入（v3 在 `onReady` 里 `markConnected`、`joinRoom`、`onReady`），不等服务器的 `JOIN` 或 `ROOMSTATE`。每次重连都重新发；
  - 登录：参数带聊天登录时 `PASS oauth:<令牌>`、`NICK <登录名>`（都去首尾空白，登录名转小写）；否则 `PASS SCHMOOPIIE`、`NICK justinfan<1000～99999>`，数字每次加入重新随机取（`Random.secure()`）。频道去首尾空白、转小写；
  - 心跳：每 40 s 发 `PING :tmi.twitch.tv`；服务器回 `:tmi.twitch.tv PONG tmi.twitch.tv :tmi.twitch.tv`，算作收到消息；
  - 其余用 `DanmakuSocketPolicy` 的默认值，也就是 v3 `WebScoketUtils` 的默认值：无消息 120 s（max(3 × 40 s, 90 s)）换连接，握手超时 10 s，连续失败 8 次放弃。只有一个地址，所以重连间隔依次是 2、3、4、5、6、6、6、6 s。没有加入计时器（v3 没有）；
  - 走应用的代理设置（v3 的所有弹幕 WebSocket 都经 `configureWebSocketProxyRouting`），由构造参数 `proxy` 给出；
  - 登录被拒（`NOTICE *`）时立即改用匿名昵称重开连接，不提示（问题 1）。
- **协议照 v3 的 `TwitchDanmaku`**，写成纯函数，不做 I/O：
  - 帧按 `\r\n` 或 `\n` 分行；二进制帧按 UTF-8 解码，坏字节换成 U+FFFD（v3 的 `allowMalformed`）；
  - 以 `PING` 开头的行回一行 `PONG`（把第一个 `PING` 换成 `PONG`、去首尾空白），逐行判断（问题 2）；
  - 聊天：去首尾空白后含 ` PRIVMSG ` 的行；标签在行首 `@` 到第一个空格之间，按 `;` 分项、第一个 `=` 分键值，没有 `=` 的项跳过；文字是 ` PRIVMSG ` 之后第一个 ` :` 后面的全部。字段：
    - 用户名：`display-name` 去首尾空白后不为空就用它，否则取 ` :?([^! ]+)!` 匹配到的昵称，都没有时是 `Twitch`；
    - 用户 id `user-id`，消息 id `id`（不加前缀），时间 `tmi-sent-ts`（毫秒），缺失或读不出时为空；
    - 颜色：`color` 去掉 `#` 按十六进制读，空或读不出是白色，经 T02g.1 修正后的 `LiveMessageColor.numberToColor`（问题 5）；
    - `/me` 的文字去掉 CTCP 包装 `\x01ACTION …\x01`（问题 3）；
    - 等级、粉丝牌为空，v3 没有填；
  - 标签值的反转义照 v3：依次整体替换 `\s`、`\:`、`\r`、`\n`、`\\`（问题 7）；
  - 一行解析失败（时间超出 `DateTime` 的范围）只丢这一行（问题 4）；
  - 只产出聊天。其他命令（`USERNOTICE`、`CLEARCHAT`、`CLEARMSG`、`NOTICE`、`ROOMSTATE`、`RECONNECT` 等）不解码，和 v3 一样；只有 `NOTICE *` 用来判断登录被拒。
- **登录被拒**（问题 1）：参数带聊天登录、收到 `NOTICE *`（2026-09-29 实测，编造的令牌得到 `:tmi.twitch.tv NOTICE * :Login authentication failed`；常见的客户端库还处理 `Improperly formatted auth` 等写法，这里只看 `NOTICE *`，不看文字）时，这次 `connect` 里不再用这个令牌：标为未加入，用 `session.reopen` 关掉这个连接、立即以匿名昵称重开（不提示、重开后再报一次 `DanmakuReady`）。匿名昵称收到 `NOTICE *` 不做什么。下一次 `connect`（例如重新进房）重新用参数里的登录试一次。
- **颜色**：按 T02g.1 修正后的 `numberToColor`。v3 把数字转成十六进制文字再解析，只认 4、6、8 位；录制里的颜色都是 6 位或空，结果和 v3 一样。

## 与 v3 的对照

对照方式：同一份帧分别给新代码和 v3 的解码代码（`legacy_expected.dart`），逐条比较消息的全部字段（类型、用户名、用户 id、文字、颜色、消息 id、发送时间、等级和粉丝牌字段、是否本地、`data`）和 v3 发回服务器的内容。

| 样本 | 结果 |
|---|---|
| 加入和心跳 | 匿名加入的四行、`PING :tmi.twitch.tv` 与 v3 相同；频道 ` ZarBex ` 同样变成 `JOIN #zarbex` |
| 加入与 Cookie | 11 种写法的 Cookie 经 T02c.2 的 `TwitchApi.chatLogin` 变成参数后，加入的四行与 v3 `joinRoom` 读同一 Cookie 的结果相同（空、只有令牌、只有登录名、空令牌、空登录名、名字和值两边有空格、值里有 `=`、夹在其他 Cookie 中间等），只有两种不同：同名 Cookie 重复时 v3 取最后一个、T02c.2 取第一个；名字大小写不同（`Auth-Token`）时 v3 不认、T02c.2 认。浏览器和 WebView 存下的 Twitch Cookie 不会出现这两种写法，所以没有改 T02c.2 |
| S07 发出的帧 | 录制的 `PASS SCHMOOPIIE`、`NICK justinfan39976`、`JOIN #zarbex` 与 v3 相同；`CAP REQ`（v3 还要 membership）和顺序（v3 放在第三行）是录制工具的 |
| S07 收到的 22 帧 | 18 条聊天，顺序、所在的帧和全部字段一致（3 条没有颜色，是白色）；没有需要回复的 `PING` |
| S08 移植 v3 的 2 个用例 | 一致 |
| S08 其余 22 组 | 17 组一致（含登录被拒：v3 和新代码都不产出聊天）；5 组是有意差异，测试先断言 v3 的输出，再断言新代码的：1～3、5 位的颜色（差异 5）、超出范围的时间（差异 4）、`/me`（差异 3）、`PING` 在帧首且后面有聊天、`PING` 不在帧首（差异 2） |

## 审查发现的 v3 问题

位置相对 `legacy/lib/`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 存的 Twitch Cookie 失效后（令牌过期、在浏览器里退出登录），Twitch 弹幕永远连不上：大约每 14 s 提示一次“正在尝试重连”、接着“已连接”，一条弹幕也没有，也不会停下 | `core/danmaku/twitch_danmaku.dart:76-88`；`core/common/web_socket_util.dart`（收到消息就清零失败次数） | 2026-09-29 实测：用无效的令牌登录，约 200 ms 后服务器回 `NOTICE * :Login authentication failed`，之后不处理 `JOIN`、不回 `PONG`，约 12 s 后断开（1006）。v3 不看这条通知，每次重连照旧用同一个令牌；而这条通知本身算“收到消息”，把失败次数清零，永远到不了 8 次的上限 | 收到 `NOTICE *` 时这次连接改用匿名昵称，立即重开（差异 1）。读弹幕不需要登录。同一类问题在平台层是 REG-TWITCH-006（过期 Cookie 让浏览失败），T02c.2 同样是被拒后改匿名 |
| 2 | （潜在）服务器的 `PING` 和别的行在同一帧时：`PING` 在帧首，v3 把整帧（只把 `PING` 换成 `PONG`）发回服务器，用账号登录时帧里别人的聊天行会以用户的身份发进频道；`PING` 不在帧首则不回 `PONG`，服务器过一会儿断开 | `core/danmaku/twitch_danmaku.dart:112-115` | 按整帧而不是按行判断和回复 | 逐行回复（差异 2）。只含 `PING` 的帧发出的内容与 v3 逐字相同。实测 90 s 里服务器没有发 `PING`（约 5 分钟一次），多行的帧里也没有聊天，所以线上很少遇到 |
| 3 | `/me` 消息显示成 `\x01ACTION 文字\x01`，控制字符和 “ACTION” 出现在弹幕里 | `core/danmaku/twitch_danmaku.dart:144-146` | 没有去掉 CTCP 的包装 | 去掉包装（差异 3）。实测 967 条聊天里有 5 条（多是机器人的公告） |
| 4 | （潜在）一帧里有一行的时间超出 `DateTime` 的范围时，这一帧的聊天全部丢失 | `core/danmaku/twitch_danmaku.dart:110-121、157` | 整帧只有一个 `try`，逐行的循环在第一次抛错时退出 | 逐行容错，只丢这一行（差异 4，统一原则“一行坏数据只跳过这一行”）。录制和实测里没有这种值 |
| 5 | Twitch 的默认色之一 Blue（`#0000FF`）和其他 1～3、5 位十六进制的颜色都显示成白色 | `common/models/live_message.dart:128-151` | `numberToColor` 按十六进制文字的位数解析 | T02g.1 的修正（差异 5）。实测 967 条里有 49 条（5%）受影响，其中 40 条是 `#0000FF` |
| 6 | 标签值的反转义是依次整体替换，`\\s`（转义的反斜杠后面跟 `s`）会被读成 `\ `，结尾单独的反斜杠也留着 | `core/danmaku/twitch_danmaku.dart:170-175` | 不是按 IRCv3 从左到右一次扫描 | 保留 v3：读到的标签里只有显示名可能带转义，而 Twitch 的显示名不能含反斜杠（实测 967 条里没有）。S08 用例锁定了 v3 的读法 |
| 7 | 没有标签的行，名字从文字里取：`:viewer!… PRIVMSG #room :hey! you` 的用户名是 `hey`，没有 `!` 时是 `Twitch` | `core/danmaku/twitch_danmaku.dart:147` | 正则要求昵称前有空格，行首的前缀匹配不到 | 保留 v3：请求了 tags 能力，Twitch 的聊天行总带标签（实测全部带） |
| 8 | 其他命令的文字里含 ` PRIVMSG ` 时被当成聊天（例如订阅留言写着 `x PRIVMSG #room :y`，会多出一条 `y`） | `core/danmaku/twitch_danmaku.dart:130、144` | 只看行里有没有 ` PRIVMSG `，不看命令 | 保留 v3：要观众特意这样写，名字仍是这个观众自己的显示名，不能冒充别人 |

另外两处属于框架，T06a.1 已处理：v3 的 Twitch 再次 `start` 时不关旧连接（T06a.1 差异 3），`stop` 不清 `onReady`（T06a.1 的 run 失效后不再有任何事件）。

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 用账号登录被拒（`NOTICE *`）后，这次连接改用匿名昵称立即重开，不提示 | 问题 1。令牌有效时与 v3 相同。令牌失效时约 0.2 s 后换成匿名连接，界面可能再显示一次“已连接”（M13 的 3 s 提示去重会合并） |
| 2 | 服务器的 `PING` 逐行回复，只发 `PONG` 那一行 | 问题 2 |
| 3 | `/me` 消息去掉 `\x01ACTION`、`\x01` 包装，只显示文字 | 问题 3。结尾没有 `\x01` 的也去掉开头；其他 CTCP（如 `\x01VERSION\x01`）和不在开头的不动 |
| 4 | 一行读不了（时间超出范围）只丢这一行 | 问题 4 |
| 5 | 1～3、5、7 位十六进制的颜色显示成它本来的颜色（Blue 是蓝色、`#000000` 是黑色） | 问题 5；T02g.1 对 `numberToColor` 的修正。录制里的颜色都是 6 位或空，没有变化 |
| 6 | 聊天登录取自参数：T02c.2 取房间时从 `CookieVault` 读出，放进 `TwitchDanmakuArgs.chat`；换了 Cookie 要重新进房才用新的 | v3 每次加入（包括重连）都去设置里读。弹幕包是纯 Dart，不读设置（T02c.2 问题 1）；换 Cookie 后重新进房即可 |
| 7 | 回调换成事件；参数不是 `TwitchDanmakuArgs` 时抛 `ArgumentError` | T06a.1 的统一接口。v3 把参数 `toString()` 当频道，null 会加入 `#null` |

保持 v3 行为、没有顺手改的地方：

- **打开即就绪**，不等服务器的 `JOIN` 或 `ROOMSTATE`。归档 v4 改成收到 `ROOMSTATE` 或自己的 `JOIN` 才算加入、10 s 内没有就重连，没有采用。
- **加入的顺序和能力照 v3**：`PASS`、`NICK`、`CAP REQ`、`JOIN`，请求 `twitch.tv/membership`（观众进出）。归档 v4 先发 `CAP REQ`、不要 membership。实测 v3 的顺序约 0.2 s 完成加入（收到自己的 `JOIN` 和 `ROOMSTATE`），之后的聊天都带标签。
- **有登录就用账号登录**。归档 v4 一律匿名。
- **心跳 40 s、无消息 120 s**。归档 v4 是 60 s、180 s。
- **地址不写端口，握手不带请求头**，每行单独一个文本帧、不加 CRLF。
- **消息 id 不加前缀**（归档 v4 加 `twitch:`），时间按本地时区的 `DateTime`（去重闸门只比较毫秒）。
- **不检查频道**：一个连接只加入一个频道。归档 v4 丢掉别的频道的 `PRIVMSG`。
- **不显示订阅、突袭（`USERNOTICE`）**，被管理员删除或封禁（`CLEARMSG`、`CLEARCHAT`）的消息不撤回，`RECONNECT` 不主动处理（等服务器断开后按退避重连）。
- **反转义的顺序、没有标签的行的名字、含 ` PRIVMSG ` 的其他命令**照 v3（问题 6～8）。
- **空文字的聊天照样报出**，`PRIVMSG` 没有文字部分（没有 ` :`）的行跳过。
- **每次重连换一个新的匿名昵称**。
- **走应用的代理设置**。
- **每次重连都报一次 `DanmakuReady`**，一轮失败只报一次重连（T06a.1 的运行时，和 v3 一样）。

## 回归条目的覆盖

归档规格里 Twitch 的回归条目 REG-TWITCH-001～010 都属于平台层（T02c.2），第 7 节“弹幕”没有回归条目。与弹幕有关的只有 REG-TWITCH-006（过期 Cookie），本模块的问题 1 是它在弹幕连接里的对应，测试见“登录被拒”的三个连接用例。

## 登记方式

应用（T07a.1）建 `DanmakuRegistry` 时：

```dart
SiteIds.twitch: () => TwitchDanmakuConnection(proxy: proxyPolicy),
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `proxy` | 否（默认直连） | `live_net` 的 `ProxyPolicy`，每次握手按平台 id `twitch` 取路线；v3 的弹幕走应用的代理设置，Twitch 在国内一般要经代理 |
| `connector` | 否 | 只给测试替换握手 |
| `random` | 否 | 只给测试固定匿名昵称；默认 `Random.secure()`，同 v3 |

不需要 HTTP 客户端、Cookie 或设置：频道和用户的聊天登录都在 `TwitchDanmakuArgs` 里（T02c.2 取房间时放入，Cookie 来自 `CookieVault`）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 连接状态的提示文字（登录被拒后重开时的第二次“已连接”由 3 s 去重合并） | M13（T06a.1 的原因表） |
| 平台表的登记 | T07a.1 |
| T06a.1 “8 个平台的对照表”里 Twitch 标成 T06a.8、YY 标成 T06a.9，实际编号是 SOOP T06a.8、Twitch T06a.9 | 主会话（本模块只改列出的文档行，没有动 T06a.1 的记录） |

## 上游核对

pure_live_TV `e1cca224` 的 Twitch 弹幕与 v3 相同，只把提示文字换成了多语言键（`danmaku_reconnecting`、`danmaku_connect_failed`），问题 1～5 都还在。没有可采用的修复。

## 升级条目

`docs/specs/UPGRADES.md` 里 Twitch 的 8-1～8-10 都属于平台层、T04、T09b.1、M13，没有含 T06a 的条目，没有要改的行。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 收到 `RECONNECT`（服务器维护前的通知）时主动换连接，不提示。**已做（T06a.F）** | 等服务器断开后按退避重连，出现一次重连提示 | Twitch 的 IRC 文档说收到后应当重连并重新加入 |
| 2 | 被管理员删除（`CLEARMSG`）或封禁、清屏（`CLEARCHAT`）的消息从弹幕列表撤下。**已做（T06a.F）** | 照常显示 | 实测 12 s 里就收到一条 `CLEARCHAT`；要 M13 支持按用户和消息 id 撤回 |
| 3 | 显示订阅、突袭等 `USERNOTICE`。**已做（T06a.F）** | 不显示 | 归档 v4 也不显示 |
| 4 | 登录被拒时告诉用户 Twitch 的 Cookie 已失效。**已做（T06a.F）** | 无提示（本模块改为悄悄转成匿名） | 问题 1 |

## 新增的通用能力、依赖

没有。只在 `live_danmaku.dart` 里加了一行导出，框架文件没有改。

## 测试

`twitch_test.dart` 49 个用例，`live_danmaku` 共 433 个，连续跑 3 次全部通过。另做了变异检查，下面每一种改动都会让对应的用例失败：整帧判断 `PING`（v3 的写法）、不去 `/me` 的包装、登录被拒时改用 `reconnect`（有退避和提示）或不处理、被拒后仍用令牌、重开前不标为未加入、先报就绪再发加入行、去掉 membership、心跳改成 60 s、颜色一律白色、去掉逐行容错。

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 5 | 11 种 Cookie 经 `TwitchApi.chatLogin` 后的加入行与 v3 相同（两种 T02c.2 的差别先断言 v3 的输出）；录制的发出帧与 v3 的对照；频道去空白转小写、匿名昵称的范围、登录不取随机数；心跳和地址；`NOTICE *` 的判断 |
| 录制帧（S07）对照 v3 | 1 | 22 帧逐条对照 18 条聊天，没有要回复的内容 |
| 合成帧（S08）对照 v3 | 25 | 24 组各一个用例（5 组按上面的差异变换，登录被拒那组另查 `loginRejected`），另有一个检查每组都有 v3 输出 |
| 连接 | 18 | 地址、无请求头和子协议、直连、先发加入行再就绪；账号登录的 `PASS`、`NICK`；代理路线；策略（40 s、120 s、无加入计时器、8 次）；40 s 心跳计时器和手动心跳（文本帧）；逐行回复 `PING`；回放整段录制得到 v3 的 18 条、文本帧和二进制帧都能读；登录被拒后不等退避、不提示地以匿名重开，匿名时的 `NOTICE *` 不起作用；被拒的登录在下次 `connect` 时重新使用；重开途中 `close` 不再有事件、迟到的握手被关掉；断线后 2 s 重连、换新昵称、重新加入、再次就绪；普通重连保留账号登录；退避 2、3、4、5、6、6、6、6 s 后放弃；`close` 之后没有事件、心跳和 `PONG`；换房间；参数类型；平台表登记；本地 WebSocket 服务器端到端回放整段录制并回复 `PING` |

## 后续升级（T06a.F，附录 B-7）

- 日期：2026-09-30
- 条目：上面“后续升级候选”的 1～4，即 `docs/specs/UPGRADES.md` 附录 B 的 B-7，决定“采用”。
- 改动：`twitch.dart`（协议、连接）、`twitch_test.dart`、新样本 `S09-live`、`S10-live`。框架、`live_core` 都没有改，没有新依赖。没有新设置。
- 依据：
  - Twitch 网页的聊天脚本（2026-09-30 从频道页取得的 `https://assets.twitch.tv/assets/49198-87edf11f696f172878f7.js`），IRC 分派在 `handleMessage` 里：`case"RECONNECT":this.connection.reconnect()`；`case"CLEARCHAT"` 有用户参数时报 `ban`/`timeout`（带登录名），没有时报 `clearchat`；`case"CLEARMSG"` 报 `targetMessageID`（`target-msg-id`）；`case"USERNOTICE"` 按 `msg-id` 分给 `handleSub`、`handleResub`、`handleSubGift`、`handleSubMysteryGift`、`handleRaid`、`handleAnnouncement` 等，`sharedchatnotice` 按 `source-msg-id` 再分一次，不认识的 `msg-id` 当作一条 `usernotice` 聊天消息显示；`NOTICE` 的默认分支遇到 “Login unsuccessful”“Login authentication failed” 就断开；
  - 2026-09-30 在本机（WSL，直连）匿名、只读地录了 30 个最热门频道（GQL `streams(first: 30)`）各 20 分钟，44 个连接：聊天 59401 行，`USERNOTICE` 354 行（`subgift` 101、`resub` 88、`viewermilestone` 65、`sub` 46、`submysterygift` 26、`announcement` 23、`raid` 3、`primepaidupgrade` 1、`communitypayforward` 1），`CLEARCHAT` 154 行（都带 `target-user-id` 和登录名：145 个禁言带 `ban-duration`、9 个封禁；没有清屏），`CLEARMSG` 20 行（都带 `target-msg-id`），`RECONNECT` 0 行（中途有 14 次 1006 断开，之前都没有 `RECONNECT`）。`announcement` 的 `system-msg` 都是空的，文字在行尾参数里。

### 做法

- **`RECONNECT`（候选 1）**：
  - 协议：命令是 `RECONNECT` 的行（有无标签、有无前缀都算；聊天或通知文字里的 “RECONNECT” 不算）使 `TwitchDanmakuFrame.reconnect` 为真，同一帧里前后的聊天照常报出。
  - 连接：立即用 T06a.1 的 `session.reopen` 换一个连接，用同一份登录重新加入（匿名时和每次加入一样换一个新昵称；登录被拒后仍是匿名）。换的时候不标为未加入，所以不报 `DanmakuReconnecting`；新连接打开后房间仍算已加入，也不再报 `DanmakuReady`，界面不会再出现“正在重连”“已连接”。
  - 新连接握手失败：照普通断线处理（报一次重连、退避 2 s、连上后报就绪），和 v3 一样。
  - 距上一次这样换连接不到 10 s（`TwitchDanmakuConnection.switchInterval`）又收到 `RECONNECT`：按普通重连（退避、报一次重连）。这是为了服务器反复要求时不会形成没有间隔的循环；网页每次也至少等 1 s。时间由构造参数 `now` 读取（测试注入）。
  - 同一帧里既有登录被拒又有 `RECONNECT`：只按登录被拒重开一次。
- **撤回（候选 2）**：
  - `CLEARMSG`：`LiveRetraction.message(target-msg-id)`。
  - `CLEARCHAT` 带 `target-user-id`（禁言、封禁）：`LiveRetraction.user(target-user-id)`；不带用户参数也不带 id（清屏）：`LiveRetraction.all()`。带了用户（登录名）却没有 id 的行跳过：聊天里没有登录名，没法对上，也绝不能当成清屏。`target-msg-id` 为空、只有空白的 `CLEARMSG` 同样跳过。
  - 撤回消息自己没有消息 id（Twitch 不给），`sentAt` 取 `tmi-sent-ts`，用户名、文字为空。
  - 聊天本来就带 `id`（消息 id）和 `user-id`（T06a.9 已填），没有要补的。S09 里 3 条被删的消息和 1 个被禁言的人都能在前面的聊天里按 id 对上；禁言 10 s 后这个人又说了一句，排在撤回之后（M13 只撤回已经显示的）。
- **`USERNOTICE`（候选 3）**：
  - 通知文字用 Twitch 给的 `system-msg`（英文原文，不翻译），`userName` 是这条通知的主角（订阅的人、送订阅的人、突袭来的主播）的显示名（没有时用登录名），`userId` 是 `user-id`，通知本身不带消息 id，`sentAt` 取 `tmi-sent-ts`，颜色白色。
  - 分类：`sub`、`resub`、`extendsub`、`subgift`、`anonsubgift`、`submysterygift`、`anonsubmysterygift`、`giftpaidupgrade`、`anongiftpaidupgrade`、`primepaidupgrade`、`communitypayforward`、`standardpayforward` 为 `subscription`（订阅、续订、赠送、延长、升级、转赠，`TwitchDanmakuProtocol.subscriptionNotices`）；`raid` 为 `raid`；`announcement`（管理员的公告）为 `system`，文字用公告内容（它的 `system-msg` 是空的）。
  - 其他 `msg-id`：**取舍：`system-msg` 不为空就作 `system` 通知显示**，为空就不显示。依据是网页把这些几乎都显示在聊天里（脚本里有 `unraid`、`charitydonation`、`bitsbadgetier`、`viewermilestone` 等的处理，实测只遇到连续观看记录 `viewermilestone`，65 行），而且 `system-msg` 是平台写好的一句话；不认识的新类型也照此处理，不需要跟着改代码。
  - `sharedchatnotice`（共享聊天里别的频道的事件）按 `source-msg-id` 分类，和网页一样。
  - 观众附带的话（续订留言、连续观看时说的话，即行尾参数）作为这个观众的聊天紧跟在通知后面：带这条 `USERNOTICE` 的 `id`、`user-id`、名字颜色和时间，于是 `CLEARMSG`、`CLEARCHAT` 同样能撤回它，也和其他聊天一样飞过画面、经过过滤。网页脚本也把这段话作为该观众的聊天消息交给界面（`handleResub` 的 `body`、`viewermilestone` 的 `createChatMessage`）。公告的文字已经是通知，不再重复。
  - 这三种命令的标签按 IRCv3 从左到右一次反转义（`\\` 是反斜杠，`\s` 是空格，结尾单独的反斜杠去掉）；v3 不读这些命令，没有对照。聊天仍用 v3 的读法（问题 6）。文字整段读取：v3 把 `USERNOTICE` 文字里的 ` PRIVMSG ... :` 当成聊天截断（问题 8），这三种命令现在不再这样；其他命令（`NOTICE` 等）仍照 v3。
- **Cookie 失效提示（候选 4）**：登录被拒、改用匿名重开时，先报一条 `system` 通知 `TwitchDanmakuProtocol.cookieExpiredNotice`：“Twitch 的 Cookie 已失效，弹幕已改为匿名接收，请重新填写 Twitch Cookie”（这是本应用自己的话，所以用中文；“填写 Twitch Cookie”对应 v3 账号页的“粘贴 Twitch Cookie”）。一次 `connect` 只说一次：被拒后这次连接不再用这份登录，匿名昵称不会被拒。下一次 `connect`（重新进房）重新用参数里的登录，再被拒就再说一次。通知没有用户、消息 id 和时间。

### 用户看到的变化

- Twitch 服务器维护前要求换连接时，弹幕不再断开几秒、也不再提示“正在重连”“已连接”（只有换连接那一下的握手空档，见下）。
- 被管理员删除的消息、被禁言或封禁的人的消息、清屏时的全部消息，从聊天列表撤下（M13 按撤回消息处理）。
- 聊天列表里多出订阅、续订、赠送订阅、突袭、公告、连续观看等通知行；续订等附带的话照常作为那个人的弹幕显示。
- 保存的 Twitch Cookie 失效时，进房后会看到一次“Twitch 的 Cookie 已失效……”的提示，弹幕照常以匿名接收。

### 与决定的差异

- **先关旧连接再连新的，不是先连后关。** 网页收到 `RECONNECT` 后等 1 s + 2 s × 次数再加 0～5 s 的随机抖动（第一次是 3～8 s），新建一个连接并等它加入成功，才停掉旧连接的事件、关掉旧连接，中间不漏消息。T06a.1 的运行时一个会话只有一个连接，`reopen` 先关旧的（等关闭握手，最多 2 s）再开新的，所以换连接时会漏掉一次关闭握手、打开握手和加入的时间里的聊天（录制里打开连接到收到加入确认约 0.2～0.5 s，再加上握手；经代理更长）。先连后关要框架让两个连接并存，本批只有 B-1 改框架，这里没有加，放到框架的后续（见“放到其他模块的部分”）。
- **立即换，不等 3～8 s。** 网页的等待和抖动是为了服务器维护时错开大量客户端；本应用的客户端数量相对 Twitch 可以忽略，而等待期间服务器先断开的话就会出现重连提示，正是这条要去掉的。
- **撤回按用户 id，不按登录名。** 网页的 `ban`/`timeout` 事件带登录名；聊天消息里存的是 `user-id`，登录名不在消息里，显示名还可能是中日韩文字，所以用 `CLEARCHAT` 的 `target-user-id`（录到的 154 行都有）。

### 样本

两份都是 2026-09-30 的匿名录制（`justinfan` 昵称，v3 的加入行，不发言），只保留第一个连接，`meta.json` 的 `raw` 是保留前整段的 SHA-256 和长度。

| 样本 | 频道 | 保留的帧 | 内容 |
|---|---|---|---|
| `S09-live` | `ironmouse` | 1045 帧中的 94 帧 | 欢迎和加入；`sub` 5、`subgift` 2、`submysterygift` 2（各有一次匿名赠送 `AnAnonymousGifter`）、`raid` 2、`viewermilestone` 3；`CLEARMSG` 3 和被删的 3 条聊天；`CLEARCHAT`（禁言 10 s）1 和这个人前后各 1 条聊天；另留最早的 6 条聊天；服务器 `PING` 3 次和回复、客户端心跳 |
| `S10-live` | `caedrel` | 2496 帧中的 92 帧 | 欢迎和加入；`resub` 7（4 条带留言）、`viewermilestone` 5（都带话）、`announcement` 1、`sub` 1、`submysterygift` 1、`subgift` 1；另留最早的 3 条聊天（其中 1 条是机器人的公告）；服务器 `PING` 4 次和回复、客户端心跳 |

- 脱敏（`meta.json` 的 `scrubbed` 逐项记录）：所有观众的显示名、登录名（前缀、`login`、`msg-param-*` 里的名字和登录名、`CLEARCHAT` 的参数）换成同形的假名，同一个人在各处（包括 `system-msg`、聊天文字里的提及）是同一个假名；用户 id（`user-id`、`target-user-id`、`msg-param-recipient-id`）换成同长的数字，撤回和聊天之间的对应关系保持；`client-nonce`、`msg-param-origin-id`、`msg-param-community-gift-id`、突袭头像地址里的编号换成同形的随机值；聊天文字里的 `@提及` 一律换掉。逐行看过保留的全部标签和文字后，另把一条被删消息里的两个真人姓名和一条消息里观众的另一个账号名换掉。保留：频道名和 `room-id`（公开）、消息 id（UUID）、Twitch 的匿名赠送占位名和它的 id、徽章、表情位置、订阅档位名。脚本最后检查所有原值都不再出现，门禁的 `fixture privacy` 通过。
- 删掉的帧只有聊天（S09 951 行、S10 2404 行），记在 `scrubbed` 的 `irc.PRIVMSG`。
- **未实测**：`RECONNECT`（录到 0 次）、清屏的 `CLEARCHAT`、带用户却没有 id 的 `CLEARCHAT`、`sharedchatnotice`、`unraid` 和其他少见的 `msg-id`、登录被拒后的提示（被拒本身 T06a.9 已实测），都用合成帧。

### 测试

`twitch_test.dart` 71 个用例（新增 22 个），`live_danmaku` 共 1331 个，连续跑 3 次全部通过；测试文件在时钟 +30 天、+1 年、+5 年下直接运行也都通过（样本时间只用于比较消息的 `sentAt`，不和“现在”比较；换连接的间隔用注入的时钟）。另做了变异检查，下面每一种改动都会让用例失败：换连接后照常报就绪、去掉 10 s 间隔、换连接改用普通重连、带用户没有 id 的 `CLEARCHAT` 当成清屏、不报 Cookie 提示、公告改用 `system-msg`、不报观众附带的话、突袭归为 `system`、不看 `source-msg-id`、不认 `RECONNECT`、登录被拒和 `RECONNECT` 同帧时重开两次、这三种命令改用 v3 的反转义。

| 分组 | 用例 | 内容 |
|---|---|---|
| B-7 命令（合成帧） | 11 | `CLEARMSG` 的字段；禁言、封禁、清屏；坏数据（没有或空的 `target-msg-id`、带用户没有 id、空参数、超出范围的时间只丢这一行、读不出的时间、没有标签的清屏）；订阅类 12 种和续订留言（通知与聊天逐字段）；突袭；公告、`viewermilestone`、`unraid`、`system-msg` 为空、没有标签；`sharedchatnotice`；名字的退路；IRCv3 反转义和整段文字；`RECONNECT` 的几种写法和不算的写法；`TwitchIrcLine` 的拆分和坏行 |
| B-7 录制帧（S09、S10） | 3 | S09 的消息类型顺序、14 条通知逐条（种类、名字、id、文字）、4 条撤回（目标、时间）、每条撤回都对得上前面的聊天、禁言后的那句在撤回之后；S10 的 16 条通知和 9 句观众的话逐条、公告、留言作为聊天的全部字段；S09 经连接回放得到同样的消息并回复 3 次 `PONG` |
| B-7 连接 | 8 | `RECONNECT` 立即换连接：旧连接先关、换的途中仍算已加入、旧连接迟到的帧不报、用同一登录重新加入、没有重连提示和第二次就绪；匿名时换新昵称；10 s 内第二次按普通重连（`DanmakuReconnecting`、就绪），满 10 s 又悄悄换；新连接握手失败时报一次重连再就绪；换的途中 `close` 不再有事件、迟到的握手被关掉；登录被拒和 `RECONNECT` 同帧只重开一次、之后的换连接仍是匿名；Cookie 提示每次 `connect` 一次；本地 WebSocket 服务器端到端：服务器发 `RECONNECT` 后客户端关掉第一个连接、在第二个连接上重新加入 |

原有用例的改动（都注明 B-7）：S08 的两组 `other commands carry no chat`、`a line of another command whose text holds ' PRIVMSG '` 按新读法变换 v3 的输出（前者多出订阅通知、续订留言、两条撤回，并且 `reconnect` 为真；后者的文字是整段），S08 每组另查 `reconnect`；登录被拒的两个连接用例多了 Cookie 提示。

直接运行测试文件时，最后一个用例结束约 5 s 后进程才退出：`LiveSocket` 关闭时先取消对 `dart:io` WebSocket 的订阅再调用 `close`，`dart:io` 于是收不到对方的关闭帧，要等它自己的 5 s 计时器。这是 T03a.1 的现有行为（T06a.9 的本地服务器用例同样如此，以前被失败用例的退出掩盖），不影响结果，这里没有改。

### 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 撤回（从聊天列表去掉对应的行）和通知行的显示 | M13（T06a.1“模型追加”） |
| 换连接时先连新的再关旧的（让一个会话的两个连接短暂并存，旧连接的消息在新连接加入前照常上报） | T06a.1 框架的后续；本批只有 B-1 改框架 |
