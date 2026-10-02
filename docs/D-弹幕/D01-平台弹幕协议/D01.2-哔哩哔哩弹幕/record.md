# D01.2 弹幕：哔哩哔哩

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/bilibili.dart`（`BilibiliDanmakuConnection` 连接，`BilibiliDanmakuProtocol` 编码和解码，不做 I/O）
- 参数：`live_core` 的 `BilibiliDanmakuArgs`（E01.1 的 `BilibiliSite.getRoomDetail` 放进 `LiveRoom.danmakuData`）
- 样本：
  - `fixtures/bilibili/danmaku/S13-live`：真实录制（2026-09-27，游客，房间 5050，60 s，protover 2），E 从归档复制；本模块补做了脱敏（见“样本”）。
  - `fixtures/bilibili/danmaku/S13-vectors`：28 个合成向量、39 条消息，补上录制里没有的醒目留言、`p_is_ack`、完整昵称和各种畸形帧。
  - 两个样本都附有 v3 解码的冻结输出 `expected.json`，生成方法见下文。
- 参考：
  - v3：`legacy/lib/core/danmaku/bilibili_danmaku.dart`、`legacy/test/bilibili_danmaku_protocol_test.dart`；
  - 归档 v4：`packages/live_danmaku/lib/src/sites/bilibili.dart`、`spec/sites/bilibili.md` 第 7 节和回归条目 REG-BILIBILI-008～015、022，ADR 0019（protover 2）；
  - pure_live_TV `e1cca224`：`lib/platforms/bilibili/bilibili_danmaku.dart` 比 v3 旧（没有 `support_ack`、`queue_uuid`、ACK），只是文字换成了多语言键，没有可采纳的修复。

## 做法

- **建在 D01.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`）。平台代码只写四样：`target`（凭据、地址、请求头）、`onOpen`（发认证包）、`onData`（解码一条消息）、`heartbeatFrame`。换地址、退避、最多 8 次、无消息超时、停止后不再有事件，都由框架和 `LiveSocket` 负责，与 v3 的 `WebScoketUtils` 相同。
- **协议写成纯函数**：`BilibiliDanmakuProtocol.decode(消息)` 按顺序给出三种条目——要上报的消息（`LiveMessage`）、要回的 ACK 包、认证回复的 `code`；连接按顺序处理，所以事件和发包的先后与 v3 在解码中途直接回调完全一样。解码逐行对照 v3：
  - 16 字节大端包头，按无符号读；一条消息里的多个包、压缩包里的整段包序列都递归拆开（REG-BILIBILI-008）；
  - v3 的上限原样保留：单条消息 8 MiB、解压后 16 MiB（边解压边检查）、4096 个包、压缩嵌套 2 层；帧长为 0、截断、头长小于 16、尾部多出字节时，丢掉这条消息剩下的部分，前面已解出的照常上报（REG-BILIBILI-009）；
  - op 3：4 字节热度 → `online`（`popularity`）；op 5：protover 2 用 zlib 解压后递归，其余版本按 JSON 文本；op 8：认证回复，正文为空算 `code 0`，不是对象或没有 `code` 算 −1，不是 JSON 时丢掉这条消息剩下的部分；
  - `DANMU_MSG`（`cmd` 含这个词即可）：文本 `info[1]`，颜色 `info[0][3]`（只认整数，0 为白色），时间 `info[0][4]`（大于 1e11 按毫秒，否则按秒），消息 id `bilibili:` + `info[0][5]`，用户 id `info[2][0]`；`info[2]` 为空或没有时不上报；
  - 昵称：`info[0][15]`（可能是 JSON 文本）的 `user.base.name` 或 `origin_info.name`、顶层 `uinfo`、`data.uinfo`、`info[2][1]`，取第一个没有打码的（`**` 或 `＊＊`），全被打码时取第一个 rich 候选，都没有时用 `info[2][1]`（不去空白，同 v3）（REG-BILIBILI-013）；
  - `WATCHED_CHANGE`：`data.num` 为不小于 0 的整数时上报累计观看（`totalViewers`）；
  - `SUPER_CHAT_MESSAGE`：醒目留言，外层消息的用户名和文本都是 `SUPER_CHAT_MESSAGE`、白色，同 v3；`data` 的读法见差异 3；
  - `p_is_ack` 为 true、`msg_id` 和 `cmd` 非空、`p_msg_type` 是整数时，先回 op 24 的 ACK，再上报这条消息；字段不全不回 ACK，消息照常（REG-BILIBILI-011）。
- **编码照 v3**：包用 D01.1 的 `BinaryWriter` 写（protover 0、seq 1），认证包的字段和顺序同 v3（`uid`、`roomid`、`protover`、`buvid`、`support_ack`、`queue_uuid`、`scene`、`platform`、`type`、`key`），`queue_uuid` 每次认证新生成 8 位小写十六进制。和录制里归档 v4 发出的认证包、心跳包逐字节相同（测试核对）。

## 连接

| 项目 | 值（与 v3 相同，除非注明） |
|---|---|
| 地址 | 凭据的 `servers`（E01.1 已把通用网关排在最前，再接 `host_list` 的节点）；为空时 `wss://broadcastlv.chat.bilibili.com/sub` |
| 请求头 | 凭据的 `headers`（UA、Origin、Referer、同一份 Cookie）。v3 的参数另有单独的 `cookie`，请求头为空时只带 Cookie；v4 的参数把 Cookie 放在请求头里，效果相同 |
| 心跳 | 30 s，op 2、空包体；连接打开就开始按间隔发，认证完成前也发（v3 如此） |
| 无消息超时 | 90 s（max(3 × 30 s, 90 s)，策略里不单独写） |
| 重连 | 默认：失败后立刻换下一个地址，每轮多等 1 s，最多 8 次，收到任何消息清零 |
| 加入 | 每次打开都发认证包（op 7）；认证回复 `code 0` 且当前未加入时，先发一次心跳再报 `DanmakuReady`；已加入时再收到 `code 0` 什么也不做 |
| 加入超时 | 8 s 没有认证成功就直接重连，不单独提示（框架的默认 `onJoinTimeout`） |
| 开始时没有 token | 先刷新凭据，最多 3 次，间隔 500 ms、1000 ms（刷新抛错也算一次）；仍没有就 `DanmakuClosed(credentialsUnavailable)`，不开连接。等待用 `run.delay`，中途 `close` 立即结束 |
| 认证被拒（`code != 0`） | 停掉加入计时器、标为未加入、刷新凭据；拿到新 token 就用新凭据 `reopen`（关掉旧连接，失败计数重新开始，不提示）。每次 `connect` 最多刷新 3 次；刷新进行中再被拒不另起刷新。拿不到新 token 或次数用完时结束，见差异 2 |
| 重连后的凭据 | 沿用当前凭据，只有认证被拒才换 |

凭据状态（当前参数、刷新次数、是否在刷新）属于一次 `connect`（`DanmakuRun`）：被取代或关闭之后，晚到的刷新结果直接丢掉，不会影响新的连接（见问题 2）。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.bilibili: () => BilibiliDanmakuConnection(proxy: proxyPolicy),
  // …
});
```

- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `bilibili` 选路由，和接口请求用同一份设置。
- 不需要 HTTP 客户端、Cookie 或设置：房间的 `BilibiliDanmakuArgs` 已带上请求头（含登录 Cookie）和 `refresh`（绑定 `BilibiliSite` 自己的 HTTP 客户端和会话）。
- `connector` 可选，默认 `dart:io` 的握手；哔哩哔哩不需要保留大小写的握手。
- `policy`、`credentialRetryDelay`、`random` 只给测试缩短时间和固定 `queue_uuid`，应用不传。

## v3 的冻结输出

`fixtures/bilibili/danmaku/legacy_expected.dart` 生成两个样本的 `expected.json`（在仓库根目录运行 `dart run fixtures/bilibili/danmaku/legacy_expected.dart`）：

- 把 v3 的 `BiliBiliDanmaku`（解码、编码、ACK、昵称、认证回复、凭据刷新）和它用到的 `BinaryWriter`、`asT`、`LiveMessage`、`LiveMessageColor`（含 v3 的 `numberToColor`）、`LiveAudienceUpdate`、`LiveSuperChatMessage` 原样搬进一个程序。
- 只替换了：
  - `WebScoketUtils`（桩，解码只经 `packetSender` 发包，同 v3 自己的测试）；
  - `package:brotli`（抛错的桩：brotli 0.6.0 的 SDK 约束是 `<3.0.0`，Dart 3 装不上；样本里没有 protover 3 的包）；
  - `CoreLog`（记下错误类型）、`@visibleForTesting`；
  - `start`、`_connect`、`stop` 这些 socket 生命周期（`_connect` 换成记录调用的桩）。
- 一个样本（S13-live）或一个向量用同一个 v3 实例，`danmakuArgs` 设成房间参数，`refresh` 记下调用、永不完成（后面的帧不依赖它的结果）。每条收到的二进制消息按顺序记下效果：上报的消息（投影成各字段）、发出的包（Base64）、`onReady`、凭据刷新、记录的错误类型。
- S13-vectors 的 `frames.jsonl` 也由它写出（合成，没有 `meta.json`，说明见样本目录的 README）。

## 与 v3 的对照

对照方式：测试用假 socket 把每条收到的消息交给新连接，按顺序记下同样的效果（事件、发包、刷新调用），与冻结输出逐条比较；v3 记录的错误不比较（新解码不写日志，错误作为 `decode` 的返回值）。

| 样本 | 结果 |
|---|---|
| S13-live，161 条收到的消息 | 全部一致：认证回复（心跳 + 就绪）、2 次心跳回复的热度 1、44 条打码昵称的聊天、11 次累计观看；其余通知（进场、点赞、广播等）两边都不上报。发出的认证包、心跳包与录制逐字节相同 |
| S13-vectors，28 个向量、39 条消息 | 除下面 5 处有意差异外全部一致：分帧（多包、嵌套、帧长为 0、截断、越界、头长过小、嵌套过深、zlib 损坏）、protover 0/1/4 的文本、未知 op、热度、认证回复的各种形式、颜色、时间和 id、`info` 的各种残缺、昵称的 13 种组合、累计观看、醒目留言、ACK、忽略的通知 |

5 处有意差异（测试逐条断言，且断言每一处仍然需要）：颜色 `0x0000FF`、`0x0A0A0A`（差异 4）；两条醒目留言的 `messageId`，其中一条的协议相对头像地址（差异 3）。

## 审查发现的 v3 问题

| # | 位置 | 根因 | 处理 |
|---|---|---|---|
| 1 | `bilibili_danmaku.dart:161-177` `_refreshCredentialsAndReconnect` | 认证被拒后刷新不到新 token（刷新失败、返回空、或 3 次用完）就直接返回：被拒的连接留着，服务端断开后 `WebScoketUtils` 用被拒的 token 重连；认证回复本身算“收到消息”，失败计数每次清零，于是每轮都提示“正在尝试重连”，永远不会走到最终关闭 | 结束为 `DanmakuClosed(credentialsUnavailable)`（差异 2） |
| 2 | 同文件 `:92-103`、`:161-176` | `_refreshingCredentials`、刷新次数、`danmakuArgs` 属于实例；`start` 把 `_stopped` 复位。v3 同房间断开后重建会复用实例，上一次会话没完成的刷新会在新会话里生效：关掉新会话的连接、用旧会话拿到的凭据重连；它的 `_refreshingCredentials` 还会挡住新会话的第一次刷新 | 凭据状态绑定到 `DanmakuRun`，被取代后的结果丢掉（框架的按 run 失效） |
| 3 | 同文件 `:134-136` | `onMessage: (e) { decodeMessage(e); }` 把任何帧都当字节数组；收到文本帧时在监听器里抛类型错误（没有被捕获） | 文本帧忽略。哔哩哔哩实际不发文本帧 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | **已做（D01 后续升级（原 M5.F））：改回 protover 3，见文末“后续升级”。** 认证包请求 protover 2（zlib），v3 是 3（brotli）；万一收到 protover 3 的包就跳过，同一条消息的其他包照常解码 | v3 用的 `brotli` 0.6.0 的 SDK 约束是 `<3.0.0`，Dart 3.13 装不上，工作区和 SDK 也没有 brotli 解码；`dart:io` 自带 zlib。服务端按 2 回 zlib 包：S13-live（2026-09-27）就是用 protover 2 录的，153 个 zlib 包。代价只是压缩率略低。归档 v4 的 ADR 0019 做了同样的决定 |
| 2 | 认证被拒而拿不到新凭据（刷新失败或返回空 token，或本次 `connect` 已刷新 3 次）时，以 `DanmakuClosed(credentialsUnavailable)` 结束，界面文字同 v3 开始时拿不到 token 的提示（“弹幕连接信息仍在更新，请稍后刷新房间”） | 问题 1：v3 在这种情况下会无限重连并反复提示 |
| 3 | 醒目留言的 `data` 按 E01.1 快照 `BilibiliApi.superChats` 的读法：`messageId` 取 `data.id`，头像地址先规范化（协议相对地址补成 https）再加 `@200w.jpg`，文本字段去首尾空白、缺了是空字符串，开始或结束时间缺失或不大于 0 时不上报，价格接受整数形式的小数 | 直播间把快照和弹幕里的醒目留言合到一个集合里，按 `messageId` 去重（两边都没有 id 才比用户、文本、价格）。E01.1 的快照已经带 id，弹幕里的如果不带，同一条会显示两次。v3 的快照和弹幕都不带 id，所以没有这个问题。正常数据下其余字段与 v3 相同；v3 对缺字段的数据会抛错丢弃或写出 `"null"` |
| 4 | 颜色用 E05.1 修正后的 `LiveMessageColor.numberToColor` | v3 按十六进制位数解析，1～3、5、7 位的颜色（如蓝色 `0x0000FF`）都成了白色（E05.1 已记录）。录制里的颜色都是 4 或 6 位，结果与 v3 相同 |
| 5 | `info`、`info[0]`、`info[2]` 不是数组时整条丢弃 | v3 对字符串或对象形状会读出单个字符或空值，有时照样显示一条聊天。协议里不会出现 |
| 6 | 文本帧忽略 | 问题 3 |
| 7 | 解码错误不写日志，作为 `decode` 的返回值 | 包里没有日志设施（D01.1）；界面上看不出区别 |

保持 v3 行为、没有顺手改的地方：

- **游客的心跳回复热度是 1**（S13-live 两次都是 1），照样上报。v3 在直播间合并房间信息时丢掉这种骤降（`LiveRoom.withAudienceFallbackFrom`，已在 `live_core`），M13 照用；归档 v4 在协议层直接丢掉（REG-BILIBILI-015 的写法），没有采用。
- 认证完成前就按间隔发心跳；认证回复之前收到的聊天照常上报。
- 加入超时直接重连、不单独提示；每次重新加入都报 `DanmakuReady`。
- 开始时没有 token 而参数里也没有 `refresh`：照样等完 500 ms、1000 ms 再结束。
- 时间为 0 或负数时得到 1970 年前后的时间（过滤闸门会丢掉这条）。平台实际不发这种值。
- 昵称的 `info[2][1]` 不去空白。

## 回归条目的覆盖

- REG-BILIBILI-008、009：分帧和上限，S13-vectors 的分帧向量加协议测试（8 MiB、4096 个包、16 MiB 解压）。
- REG-BILIBILI-010：通用网关在前（E01.1 的参数，空时用网关）、8 s 认证超时、被拒换 token。
- REG-BILIBILI-011：认证包字段、ACK。
- REG-BILIBILI-012：uid 来自参数（E01.1 从同一份 Cookie 取）。
- REG-BILIBILI-013：昵称的取法；提示由 M13 用 `BilibiliDanmakuConnection.isMaskedName` 判断。
- REG-BILIBILI-015：见上面“保持 v3 行为”第一条。
- REG-BILIBILI-022：重连中和最终关闭分开（框架）。

## 样本

- S13-live 的脱敏补做：录制工具只替换了完整昵称，`ENTRY_EFFECT` 的 `copy_writing`、`copy_writing_v2` 里截断过的昵称（如 `<%仿生人不会爱上...%>`）和 `NOTICE_MSG` 礼物广播里的送礼人没被换掉。11 条消息里的 15 个名字换成了同一条通知里 `uinfo` 已有的合成名的截断形式（或新的 `观众34`、同形字符），压缩包解压、修改、重新压缩，记进 `meta.json` 的脱敏记录；受礼的主播名是公开的，保留。这些通知不被解码，冻结输出不受影响。访客编号、buvid、token、头像在录制时已换成合成值，没有出口地址。
- S13-vectors 全部合成，醒目留言的字段形状照 `fixtures/bilibili/S06-live` 的 `super_chat_info.message_list[0]`，用户和头像是合成的。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 游客昵称打码的提示（每个会话一次，`bilibili_guest_name_masked`） | M13，判断用 `BilibiliDanmakuConnection.isMaskedName` |
| 醒目留言快照（`getMessageList`）和与弹幕的合并 | M13；快照接口在 E01.1（`BilibiliSite.getSuperChatMessage`） |
| 热度骤降到 1 的处理 | M13 合并房间时用 `LiveRoom.withAudienceFallbackFrom` |
| 关闭、重连原因的界面文字 | M13（D01.1 的原因表） |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | D01 各平台完成后删除 |

## 测试

`test/sites/bilibili_test.dart` 23 个用例，`live_danmaku` 共 127 个，连续跑 3 次全部通过：

- 协议 6 个：包头和心跳、认证包（字段、顺序、protover 2、`queue_uuid`）、出错时保留已解出的部分、跳过 brotli、三个上限、打码判断；
- 冻结输出 2 个：S13-live 逐条对照（含认证包、心跳包与录制逐字节相同），S13-vectors 逐向量对照（有意差异逐条断言）；
- 连接 15 个：默认时序和平台表登记、握手（地址、请求头、认证包、只在认证回复后就绪、心跳紧跟其后、重复回复不再就绪）、空地址用网关、认证前的心跳、加入超时换地址重新认证、断线重连后重新加入、ACK 在消息之前发出、开始时刷新凭据（3 次、1 倍和 2 倍间隔、换用新地址和请求头）、仍无 token 时结束且不开连接、开始途中关闭、被拒后刷新并 `reopen`（不提示、刷新中不重复）、拿不到新凭据时结束、每次最多刷新 3 次、关闭或换房间后旧的刷新不起作用、真实的本地 WebSocket 服务器（认证、回复、zlib 通知、心跳）。

另外用 11 个变异（改消息 id 前缀、去掉打码判断、去掉“已加入”判断、不回 ACK、接受负的观看数、改颜色、去掉就绪前的心跳、放宽包数上限、改 protover、去掉醒目留言 id、时间不换算）检查过，每个都会让测试失败。

## 后续升级（D01 后续升级（原 M5.F），附录 B-3）

- 日期：2026-09-30
- 条目：B-3 弹幕改回 protover 3（Brotli），和网页一致。决定：采用（Q01.2 已有解码器）；先匿名录 protover 3 样本。
- 改动：`packages/live_danmaku/lib/src/sites/bilibili.dart`（两处）、`fixtures/bilibili/danmaku/legacy_expected.dart`、三个新样本、测试。框架、`live_net`、`live_core` 都没有改。

### 做法

- 认证包的 `protover` 改回 3（`BilibiliDanmakuProtocol.protocolVersion`），其余字段和顺序不变。
- op 5、protover 3 的包：`brotliDecode(包体, maxOutput: 16 MiB)`（live_net，Q01.2），解出的是另一段包序列，和 zlib 一样递归拆开。上限与 zlib 共用：解压后 16 MiB、4096 个包、嵌套 2 层（brotli 和 zlib 混着嵌套也按层数算）。protover 2（zlib）照旧能解，S13-live 的回放和万一回 zlib 的服务端都不受影响。
- 不加设置：网页只用 3，没有需要用户选的东西。
- 用户看到的变化：没有，消息和以前一样（见下面的对照）。流量少一些：同一段 240 s，brotli 连接收到 1,027,707 字节，zlib 连接 1,182,487 字节（少约 13%）。

### 依据

- 网页（2026-09-30 取的 `s1.hdslb.com/bfs/blive-engineer/live-web-player/room-player.prod.min.js`，`room-player.dm.prod.min.js` 同样）：
  - 弹幕 socket 的 `userAuthentication` 写死 `protover:3`，其后是 `buvid`、`support_ack:!0`、`queue_uuid`、`scene`，再加 `platform: web`、`type: 2`、`key`（与 v3、本实现的字段相同）；
  - 解包只认两种版本：`WS_BODY_PROTOCOL_VERSION_NORMAL`（JSON）和 `WS_BODY_PROTOCOL_VERSION_BROTLI`（`window.BrotliDecode` 后递归），其他版本只计数（`_stats.unrecognizedVer`），所以网页根本不解 zlib；
  - 每个包各自包在 `try{…}catch(e){}` 里，坏包静默跳过，接着解同一条消息的下一个包。
- 服务端的压缩：用参考编码器（Python `brotli` 1.2.0）重新压缩解出的内容，抽查的 41 个包在窗口 22 下都能逐字节重现，其中 39 个就是默认参数（质量 11、窗口 22），另 2 个是小包，更低的质量已经相同。所以样本脱敏后用默认参数重新压缩，得到的就是服务端会发的字节。
- 录制：见“样本”。

### 逐帧对照

同一房间、同一时刻开两个匿名连接，一个请求 protover 3（本实现），一个把认证包改成 protover 2，各录 240 s（`S13-protover3`、`S13-protover2-paired` 是其中对齐的几段）。

| 收到的 | protover 3 连接 | protover 2 连接 | 结果 |
|---|---|---|---|
| 认证回复（op 8） | 1 条 `{"code":0}` | 同 | 就绪，先发一次心跳 |
| 心跳回复（op 3） | 9 条，值都是 1 | 同 | 热度 1（游客，同 D01.2） |
| 压缩的通知（op 5） | 951 条消息，每条只有一个 protover 3 包 | 951 条，每条一个 protover 2 包 | 解出 2570 条通知，两边逐条相同（按内容比较的多重集相等）。979 条收到的消息里 916 条内容完全相同，其余 63 条只是相邻消息之间聊天的分组和先后不同 |
| 明文通知（op 5，protover 0） | 18 条 | 同 | 相同 |
| 上报的消息 | 1451 条聊天、46 次累计观看、9 次热度、6 条醒目留言，1 次就绪 | 同 | 按内容比较完全相同。6 条醒目留言都带 `p_is_ack`，两边各回了 6 个 ACK |
| 解码失败（brotli 流损坏、截断、流后多余字节、解出的不是包序列、超过 16 MiB、嵌套超过 2 层） | 未实测（服务端没发过坏包），用合成帧 | — | `decode` 返回 `FormatException`；这条 WebSocket 消息里之前解出的照常上报，之后的丢掉。服务端每条消息只放一个包（两份录制 1958 条消息都是），丢掉的就是这一包。连接不断开、不重连、不提示，下一条消息照常解码。与 zlib 包和 v3 的处理相同；包里没有日志设施，错误只作为返回值（D01.2 差异 7） |

### 3.x 的冻结输出

- `legacy_expected.dart` 里 `package:brotli` 的抛错桩换成 live_net 的 `brotliDecode`，外面仍是 3.x 用的分块接口（缓存输入，`close` 时解，按 16 KiB 分块交给 3.x 的有界接收器），做法同 D01.13 猫耳。它现在写出五个样本的 `expected.json`；S13-live、S13-vectors 的输出和 `frames.jsonl` 逐字节不变。
- 核对 `package:brotli` 0.6.0 本身：把它的源码放在临时目录，绕过 SDK 约束在 Dart 3.13 上运行（不进仓库），走 3.x 的分块路径和有界接收器：
  - 73 个合法的 brotli 流（录制 60 个、向量 13 个，含嵌套）两者解出的字节完全相同；
  - 截断的流、流后多余字节（0 或 1、2、3）两者都拒绝；
  - 损坏的 5 字节 `01 02 03 04 05`：0.6.0 卡死（10 s 没有结果，另一次 60 s），见下面的问题 4；冻结输出里记的是 Q01.2 的判定。
- S13-protover3 和 S13-protover2-paired 的 `expected.json` 逐字节相同：3.x 对两个连接的每一条消息效果都一样。

### 审查发现的 v3 问题（B-3 相关）

| # | 位置 | 根因 | 处理 |
|---|---|---|---|
| 4 | `bilibili_danmaku.dart:360-366` `_decodeCompressedBody` 用的 `package:brotli` 0.6.0 | 某些坏的 Brotli 流（例如 5 字节 `01 02 03 04 05`）让解码器死循环。3.x 在 WebSocket 的监听回调里同步解码，也就是界面所在的 isolate，一个坏包就会让整个应用卡住 | Q01.2 的解码器对坏流一律抛 `FormatException`（输入末尾之后补零、用到补的零就报截断，不会空转）；向量 `brotli-corrupt` 和协议测试覆盖。服务端没发过坏包 |

### 与决定的差异

- 没有。唯一与网页不同的是坏包：网页逐包 `try/catch`，坏包之后同一条消息里的包照解；这里同 v3 和 zlib，丢掉这条消息剩下的部分。服务端每条消息只放一个包，实际没有区别，所以没有改（改了还会改变 zlib 的既有行为）。

### 样本

- `S13-protover3`（80 行：1 个认证包、4 次心跳、6 个 ACK，69 条收到的消息：1 个认证回复、4 个心跳回复、4 条明文通知、60 个 brotli 包）：
  - 2026-09-30 15:16 UTC，直连，游客（不登录、不发言），房间 1700301235（推荐列表里醒目留言快照最多的歌房，便于录到醒目留言），240 s。录制脚本 `record.dart` 用两个 `BilibiliDanmakuConnection`，各接一个记录帧的 `connector`；配对的那个在发出时把认证包的 `protover` 改成 2。
  - 保留原始录制第 0～19、358～377、613～623、668～687、789～795、993～994 行（0 起算，共 996 行）。每一段的起止都选在两个连接“已收到的通知完全相同”的位置，所以两份样本各段的通知一致；这几段含全部 6 条醒目留言、4 次心跳回复、开头的认证和 `LOG_IN_NOTICE`。
  - 解出 139 条通知：66 条聊天、3 次累计观看、6 条醒目留言、3 条日文醒目留言，其余是进场、互动、榜单、礼物等不解码的通知。
- `S13-protover2-paired`：同一时刻的 protover 2 连接，同样的行号（两份录制的收发行完全对齐）。认证包是录制脚本改写后发出的（protover 2）。
- `S13-brotli-vectors`：10 个合成向量（没有 `meta.json`，说明见样本目录的 README），由 `legacy_expected.dart` 写出：brotli 里的多个包、7 字节的元块（包头和 JSON 跨元块）、brotli 与明文包和认证回复同在一条消息、brotli 里要 ACK 的通知、空流、损坏、截断、解出的不是包序列、嵌套到上限（brotli 套 zlib、zlib 套 brotli、brotli 套 brotli）和超过上限。Brotli 流用未压缩的元块写成，参考解码器逐个核对过。
- 脱敏（`build.py`，和 `record.dart` 一样不进仓库；两份样本用同一张替换表，所以替换后仍逐条相同）：
  - 认证包的 `buvid`、`key` 换成同形的合成值；握手的 Cookie 写成 `<redacted>`；
  - `DANMU_MSG`：`info[2]` 的 uid（游客看到的都是 0）和打码昵称（如 `离***` 换成 `观***`；替换后的名字不会是录制里出现过的任何名字）、`info[0][7]`（发送者摘要）、`info[0][15].user` 的昵称和头像（头像路径就能认出人，换成同形的 40 位十六进制）、`extra` 里的 `user_hash`（和可能有的 `reply_uname`、`reply_mid`）；
  - 醒目留言（含日文版）：`uid`、`uinfo` 的 uid、昵称、头像，`user_info` 的 `uname`、`face`，`token`；醒目留言观众的昵称是完整的（不打码），换成同样长度的合成名；
  - 其余不解码的通知只留 `cmd`（进场、互动、`ONLINE_RANK_V3` 榜单、点赞者、礼物、全站广播、`DM_INTERACTION`）；只含房间统计或主播公开信息的（`LOG_IN_NOTICE`、`ONLINE_RANK_COUNT`、`LIKE_INFO_V3_UPDATE`、`POPULAR_RANK_CHANGED`、`RANK_CHANGED_V2`、`ROOM_REAL_TIME_MESSAGE_UPDATE`、`STOP_LIVE_ROOM_LIST`、`WATCHED_CHANGE`）原样保留；
  - 保留：聊天和醒目留言的文字、醒目留言 id（快照里公开）和价格、时间、消息 id（`info[0][5]`、`id_str`、`msg_id`）、主播的名字、uid、房间号和粉丝牌；
  - 替换后的内容（解压后）里找不到任何原值（名字、uid、头像摘要、`user_hash`、发送者摘要、`token`、buvid、Cookie 值），也没有 IPv4 地址；门禁的 `fixture privacy` 通过。服务端 JSON 的写法（Go：`<`、`>`、`&` 写成 `<` 等）照原样保留，没改动的通知与录制逐字相同。
- `meta.json` 记下握手、保留的行、原始录制的 SHA-256 和长度、脱敏记录。

### 测试

`test/sites/bilibili_test.dart` 28 个用例（原 23 个，+5），`live_danmaku` 共 1314 个，连续跑 3 次全部通过；测试文件在 `SHIFT_SECONDS` 为 0、30 天、1 年、5 年下直接运行都通过并正常退出（没有用到“现在”）。

- 改了期望的原有用例（都注明 B-3）：认证包的 `protover` 改为 3；S13-live 发出的认证包 = 录制的认证包把 2 换成 3，其余逐字节相同；“跳过 brotli”换成下面的解码测试；真实的本地 WebSocket 服务器改为检查认证包的 protover 是 3，回 brotli 和 zlib 各一个通知，结束时也关掉服务端的 WebSocket。
- 新增协议 2 个（连同替换的 1 个共 3 个）：brotli 包按 zlib 的方式解（多个包、跨元块、与明文包同在一条消息、brotli 与 zlib 互相嵌套、空流、ACK）；坏的 brotli 包（损坏、截断、流后多余字节、不是包序列）保留之前的、返回错误、之后的丢掉、下一条消息不受影响，嵌套超过 2 层；16 MiB 上限（参考编码器写的 32 字节流能解出 16 MiB + 1 字节，被拒；正好 16 MiB 的能解完）。
- 新增冻结输出 3 个：
  - S13-protover3：本连接发出的认证包与录制逐字节相同；每条收到的消息与 3.x 的效果逐条相同，差异只有醒目留言的 `messageId`（D01.2 差异 3，逐条断言 6 个 id）；66 条聊天、4 次热度、3 次累计观看；第一条聊天和第一条醒目留言断言到每个字段；录制里发出的 ACK 与本连接发出的逐字节相同，其余发出的都是心跳；
  - S13-protover2-paired：两份录制每条消息解出的通知逐条相同，每条消息只有一个包（brotli 对 zlib），两个连接的效果逐条相同，3.x 的冻结输出也相同；
  - S13-brotli-vectors：10 个向量与 3.x（Q01.2 代替 `package:brotli`）逐条相同。
- 另外用 5 个变异（protover 改回 2、跳过 brotli 包、去掉 16 MiB 上限、brotli 不算嵌套层数、吞掉 brotli 的错误）检查过，每个都会让测试失败。

### 放到其他模块的部分

- 没有。Q01.2 记录“留给其他模块”表里 D01.2 那一行（“要不要改……在那一步决定，并补 protover 3 的样本”）由本节决定，Q01.2 的记录没有改。
