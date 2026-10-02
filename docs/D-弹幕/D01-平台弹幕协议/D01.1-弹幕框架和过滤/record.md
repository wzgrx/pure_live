# D01.1 弹幕框架

- 日期：2026-09-29
- 目标包：`packages/live_danmaku`（纯 Dart，只依赖 `live_core`、`live_net`、`meta`）
- 范围：连接接口和共用的生命周期、建在 `live_net` 的 `LiveSocket` 上的 WebSocket 运行时、平台表、二进制工具、过滤、表情模型。各平台的协议（D01.2～D01.9）之后另做，本模块不写任何平台协议。
- 参考：
  - v3：`legacy/lib/core/interface/live_danmaku.dart`、`core/danmaku/`（8 个平台和 `empty_danmaku.dart`）、`core/common/web_socket_util.dart`、`binary_writer.dart`、`utils/list_util.dart`、`modules/live_play/controllers/` 下的过滤和 `danmaku_controller.dart`、`danmaku_settings_controller.dart`、`core/emoji/`、`plugins/emoji_manager.dart`；
  - 归档 v4（`archive/v4`，6ba709135）的 `packages/live_danmaku` 和 `spec/modules/danmaku.md`；
  - pure_live_TV `e1cca224`、flame_barrage `3eddae8`。

## 做法

- **连接是一个事件流加 `connect`/`close`**，代替 v3 的四个可写回调。v3 每个平台都手写了一遍 `_generation`、`_stopped`、把回调置空，写法不一，Twitch、SOOP 还漏了（见差异第 3 条）。现在这些都在基类 `DanmakuConnectionBase` 里做一次：
  - 每次 `connect` 是一个 `DanmakuRun`，平台代码只通过它上报；
  - `close`、另一次 `connect`、或者上报了最终关闭之后，这个 run 就失效，之后它的任何上报（包括晚到的定时器和请求）都被丢弃；
  - 事件同步送出（同步的广播流），所以 `close` 返回之后不可能再收到事件。
- **WebSocket 运行时直接用 `LiveSocket`**。Q01.1 已经把 v3 的 `WebScoketUtils` 原样移成了 `LiveSocket`（换地址、退避、最多 8 次、半开检测、关闭时中止握手），这里不再写第二套。`DanmakuSocketConnection` 只做 v3 各平台重复的那一层：打开后发加入包、就绪判定、加入超时、心跳帧、把 `LiveSocket` 的回调换成事件。
- **各平台不同的只有参数**：心跳间隔、无消息超时、加入超时放在 `DanmakuSocketPolicy`（每个平台固定）；地址、请求头、子协议放在 `DanmakuSocketTarget`（每个房间算一次）。
- **过滤是纯逻辑，从直播间控制器移出来**，规则和默认值与 v3 相同。相似度的打分换成自己写的实现，结果与 v3 用的 fuzzywuzzy 一致（见“过滤”一节）。
- **表情只移模型和解析**：图片解码、图集、资源文件依赖 Flutter，放到 A01.1。
- **从归档 v4 借鉴的只有工程写法**：密封的事件类型、按 run 失效的基类（它的 `ConnectorBase`）、测试用假连接器。没有搬它的新行为：后台 isolate、抽样、礼物、20 秒启动超时即终态、自写的“全部窗口”相似度、v3 没有的 13 个平台。

## 公开接口

| 名称 | 作用 |
|---|---|
| `DanmakuConnection` | 连接接口：`events`、`status`、`isConnected`、`heartbeatInterval`、`connect(args)`、`heartbeat()`、`close()` |
| `DanmakuEvent`：`DanmakuReady`、`DanmakuReceived`、`DanmakuReconnecting`、`DanmakuClosed` | 事件；后两个带类型化的原因（`DanmakuInterruption`、`DanmakuCloseReason`）和诊断文字 |
| `DanmakuStatus` | `idle`、`connecting`、`connected`、`reconnecting`、`closed` |
| `DanmakuConnectionBase<A>`、`DanmakuRun` | 共用的生命周期；平台实现 `start`、`stop`，`A` 是它的 `*DanmakuArgs` 类型 |
| `DanmakuStartFailure` | 平台在开始阶段因已知原因无法继续时抛出，变成 `DanmakuClosed` |
| `DanmakuSocketConnection<A>`、`DanmakuSocketSession`、`DanmakuSocketPolicy`、`DanmakuSocketTarget` | WebSocket 运行时 |
| `DanmakuRegistry`、`DanmakuConnectionFactory`、`EmptyDanmakuConnection` | 平台表 |
| `BinaryWriter`、`BinaryReader`、`ListUtil` | 二进制工具 |
| `DanmakuMessageGate`、`RepeatedDanmakuFilter`、`DanmakuSimilarityFilter`、`partialRatio`、`DanmakuBlockList`、`DanmakuMessageFilter`、`DanmakuFilterSettings`、`DanmakuNoticeThrottle` | 过滤 |
| `DanmakuEmoji`、`DanmakuEmojiAsset`、`danmakuEmojiAssets`、`danmakuEmojiListAsset` | 表情 |

## v3 回调与新接口的对照

| v3 `LiveDanmaku` | 新接口 | 说明 |
|---|---|---|
| `start(args)` | `connect(args)` | 先停掉上一个房间再连；第一次尝试结束（连上或已安排重连）时完成。参数类型不对抛 `ArgumentError`（v3 是强制转换失败）；平台在第一次尝试前抛出的其他错误照样抛给调用方（v3 快手三次拉取都失败时抛出） |
| `stop()` | `close()` | 之后不再有任何事件；重复调用、未连接时调用都无害 |
| `onReady` | `DanmakuReady` | 每次（重新）加入房间都会来一次，和 v3 一样 |
| `onMessage(LiveMessage)` | `DanmakuReceived(message)` | 聊天、醒目留言、观众数，消息模型仍是 `live_core` 的 `LiveMessage` |
| `onReconnect(文字)` | `DanmakuReconnecting(原因, detail)` | 一轮连续失败只报一次（第一次失败时）；YY 另有握手超时和协议失败两种 |
| `onClose(文字)` | `DanmakuClosed(原因, detail)` | 最终关闭；之后要再 `connect` 才会重连 |
| `heartbeatTime`（毫秒） | `heartbeatInterval`（`Duration`） | 0 表示没有心跳 |
| `heartbeat()` | `heartbeat()` | 立即发一次平台的心跳帧；运行时也按间隔自动发 |
| `isConnected`、`markConnected`、`markDisconnected` | `isConnected`、`status`；平台内部用 `run.ready()`、`run.markDisconnected()` | 状态只能由平台代码通过 run 改，界面只读 |
| `EmptyDanmaku` | `EmptyDanmakuConnection` | 见“平台表” |

原因的界面文字由 M13 给出，v3 的原文如下（pure_live_TV 已换成对应的多语言键）：

| 原因 | v3 文字 | pure_live_TV 的键 |
|---|---|---|
| `DanmakuInterruption.disconnected` | 与服务器断开连接，正在尝试重连（YY：与服务器断开连接（失败详情），正在尝试重连） | `danmaku_reconnecting` |
| `DanmakuInterruption.handshakeTimeout` | YY 弹幕协议握手超时，正在尝试重连 | `danmaku_connect_timeout` |
| `DanmakuInterruption.protocolError` | （YY 协议给出的失败文字），正在尝试重连 | 失败文字 + `danmaku_reconnecting` |
| `DanmakuCloseReason.reconnectsExhausted` | 服务器连接失败重连超过最大次数，与服务器断开连接：（最后一次失败） | `danmaku_connect_failed` + `danmaku_reconnect_exhausted` |
| `DanmakuCloseReason.connectionFailed` | 服务器连接失败（SOOP 没有聊天数据时） | `danmaku_connect_failed` |
| `DanmakuCloseReason.credentialsUnavailable` | 弹幕连接信息仍在更新，请稍后刷新房间（哔哩哔哩） | `danmaku_info_updating` |

## WebSocket 运行时

`DanmakuSocketConnection` 的平台只需写四样：`target`（房间的地址和请求头，可以等待签名或凭据）、`onOpen`（发加入包；打开即算加入的平台在这里调用 `session.ready()`）、`onData`（解码一帧）、`heartbeatFrame`。运行时负责：

- 第一次尝试结束时 `connect` 完成，之后的重连都通过事件报告；
- 连接打开时按 `joinTimeout` 启动加入计时器，超时未加入就调用 `onJoinTimeout`（默认直接重连，不单独提示；YY 覆盖为先报 `handshakeTimeout`）；平台确认加入（`ready`）、任何一次连接失败、关闭时都停掉计时器；
- 心跳、无消息检测、换地址和退避都由 `LiveSocket` 按策略执行；
- `session.reconnect(notice:)`：丢掉当前连接按退避重连，可先报一个原因（YY 的协议失败）；
- `session.reopen(target)`：换一个目标重开，不提示，失败计数重新开始（哔哩哔哩拿到新凭据后）；
- `target` 没有地址时以 `connectionFailed` 结束（见差异第 6 条）。

快手是 HTTP 轮询，不用这个运行时，直接继承 `DanmakuConnectionBase`，用 `run.delay` 和 `run.ended` 做间隔和取消（D01.6）。

## 8 个平台的对照表（D01 各平台 的输入）

所有 WebSocket 平台在 v3 都用 `WebScoketUtils` 的默认值：握手超时 10 s，关闭握手最多等 2 s，连续失败 8 次放弃，退避基数 1 s（失败后立刻换下一个地址，每试完一轮所有地址多等 1 倍，最多 6 倍），收到任何消息清零失败次数，无消息超时默认取 max(3 × 心跳间隔, 90 s)。这些正是 `DanmakuSocketPolicy` 的默认值，下表只列各平台不同的地方。

| 平台 | 传输 | 地址（`DanmakuSocketTarget`） | 心跳间隔 / 心跳帧 | 无消息超时 | 重连 | 就绪的判定 | 其他 |
|---|---|---|---|---|---|---|---|
| 哔哩哔哩（D01.2） | WebSocket，二进制，16 字节包头（大端），zlib / brotli 压缩 | 凭据给的 `serverUrls`（为空时 `wss://broadcastlv.chat.bilibili.com/sub`）；请求头用凭据给的，否则只带 Cookie | 30 s；操作码 2、空包体 | 90 s | 默认 | 打开后发认证包（操作码 7）；收到操作码 8 且 `code == 0`、当前未连接时就绪，就绪时先发一次心跳。`joinTimeout` 8 s，超时直接重连 | 开始时没有 token：刷新凭据最多 3 次（间隔 500 ms、1000 ms），仍没有则 `credentialsUnavailable`。`code != 0`：停掉加入计时器、标为未连接、刷新凭据（每次开始最多 3 次）后 `reopen`。`p_is_ack` 的包回操作码 24 |
| 斗鱼（D01.3） | WebSocket，二进制，STT 文本 + 小端包头 | `wss://danmuproxy.douyu.com:8506` | 45 s；`type@=mrkl/` | 135 s | 默认 | 打开即就绪，随后发 `loginreq` 和 `joingroup`（gid −9999） | 包里的 `rid` 与房间不同就丢；“疑似机器人”过滤由设置决定，默认关闭，工厂注册时把设置的读取函数传进去 |
| 虎牙（D01.4） | WebSocket，二进制，TARS | `wss://wsapi.huya.com` | 60 s；`EWSCmdC2S_HeartBeatReq`（20） | 180 s | 默认 | 打开即就绪，随后发 `RegisterGroupReq`（16，分组 `live:uid`、`chat:uid`），紧接着发一次心跳 | 收到 2001314 时在后台拉醒目留言，重试间隔 0、600、1800、4000 ms；pure_live_TV 给这个请求加了 3 s 超时 |
| 抖音（D01.5） | WebSocket，二进制，protobuf `PushFrame`，gzip | `webcast100-ws-web-lq.douyin.com`、`webcast100-ws-web-hl.douyin.com` 两个地址，带签名的同一组查询参数；请求头 UA、Cookie、Origin、Referer | 10 s；`payloadType = hb` 的 `PushFrame` | 45 s | 默认 | 打开即就绪，随后发一个 `hb` 帧作为加入 | 签名在连接前本地算（X-Bogus）；`needAck` 时回 `ack` 帧；聊天的房间号不符就丢 |
| 快手（D01.6） | HTTP 轮询（移动端 feed，`livev.m.chenzhongtech.com`，失败换 `m.gifshow.com`） | — | 无（0） | — | 失败后等 1、2、4、8、8… s，第 1 次失败提示重连，超过 8 次 `reconnectsExhausted` | 第一次拉取成功（此前未连接时）就绪 | 开始时拉取最多 3 次（间隔 600、1400 ms），都失败则抛给调用方；下次拉取的间隔取服务端的 `pullCycleSeconds`（限制在 1–10 s，缺省 3 s） |
| SOOP（D01.8） | WebSocket，文本和二进制混合，子协议 `chat` | 平台数据给的地址；请求头为站点请求头加 UA、Origin | 20 s；`ESC\t000000000100\f` | 90 s | 默认 | 打开即就绪，随后发连接包，200 ms 后发加入包（用 `run.delay`） | 握手要保留请求头大小写，需要自带的连接器（v3 的 `connectCaseSensitiveWebSocket`，不走代理）；没有平台数据时 `connectionFailed` |
| Twitch（D01.9） | WebSocket，文本（IRC） | `wss://irc-ws.chat.twitch.tv` | 40 s；`PING :tmi.twitch.tv` | 120 s | 默认 | 打开后发 `PASS`、`NICK`、`CAP REQ`、`JOIN`，然后就绪 | 有登录 Cookie（`auth-token`、`login`）用账号，否则匿名 `justinfan` + 随机数；服务端 `PING` 回 `PONG` |
| YY（D01.7） | WebSocket，二进制，YY 协议（小端） | 由随机 uuid 生成的 H5 服务地址；请求头 UA、Origin | 5 s；协议会话生成的心跳包 | 45 s | 默认 | 打开后发协议握手（先标为未连接）；协议报告握手完成时就绪。`joinTimeout` 15 s，超时报 `handshakeTimeout` 再重连 | 需要保留大小写的连接器（不走代理）；协议失败时报 `protocolError` 再重连；断开提示带上最后一次失败（覆盖 `reconnectDetail`） |

## 平台表

`DanmakuRegistry` 代替 v3 的 `LiveSite.getDanmaku()`（`live_core` 不能依赖本包）：

- 应用启动时建一次：`DanmakuRegistry({SiteIds.douyu: () => DouyuConnection(...), ...})`，键是平台 id（大小写和空格忽略）。每个工厂自己带上所需的东西（代理策略、HTTP 客户端、Cookie、斗鱼的过滤设置），这正是 v3 在 `getDanmaku()` 里做的。
- 不是受支持平台的 id、或同一平台注册两次，构造时抛 `ArgumentError`。
- `connectionFor(平台)` 每次返回一个新连接，和 v3 每个直播间 `getDanmaku()` 一次一样；没注册的平台返回 `EmptyDanmakuConnection`。
- **界面怎么知道“这个平台没有弹幕”**：`registry.supports(平台)` 为 false（或拿到的是 `EmptyDanmakuConnection`）。这时照 v3（`engine is EmptyDanmaku`）：不连接、只提示一次 `remote_danmaku_not_integrated`、把会话当作已就绪，画中画返回时不重试。IPTV 和网易 CC 在 v3 里干脆不连（`except = [iptv, cc]`），也不提示，M13 保持。
- 本模块结束时表里还没有平台（`DanmakuRegistry.empty()`）。D01.2～D01.9 各加一个；其余平台照 v3 保持没有弹幕，给它们加弹幕列为升级候选。

## 二进制工具

照 v3 移植 `BinaryWriter`、`BinaryReader`（同一个文件里）和 `ListUtil`：

- 写：1 字节无符号（取低 8 位），2、4、8 字节按补码、可选大小端，超出宽度的值保留低位；浮点 4、8 字节；其他宽度写同样多个 0，和 v3 一样。
- 读：1 字节无符号，2、4、8 字节有符号；其他宽度读出 0 并跳过；越界抛 `RangeError`，读取失败时位置不变。
- `ListUtil.splitList` 按分隔元素切开，两端和相邻的分隔符产生空段（SOOP 用它切聊天包）；`subList` 按大小切块。
- v3 的二进制工具里没有变长整数。v3 弹幕里的变长整数只在抖音的 protobuf 生成代码（D01.5 决定手写还是用 protobuf）和 TARS 里，后者已经在 `live_core/src/tars.dart`（E01.3）。

## 过滤

`DanmakuMessageFilter` 按 v3 `DanmakuController` 的顺序处理聊天消息，其他类型（观众数、醒目留言）不过滤：

| 步骤 | 类 | 开关和默认值 | 规则 |
|---|---|---|---|
| 1 去重闸门 | `DanmakuMessageGate` | 总是开 | 有平台时间且早于 45 s（含 45 s 通过），或晚于本机 10 分钟以上：丢弃。有消息 id：10 分钟内同 id 只收一次（含 10 分钟）。没有 id：按（类型、用户 id 和用户名去空白转小写、文本去首尾空白）2.5 s 内只收一次（含 2.5 s），被拒的重复不延长窗口。最多记 4096 条，超过 10 分钟的逐出 |
| 2 屏蔽 | `DanmakuBlockList` | 总是开（名单为空时不起作用） | 名单去首尾空白、转小写、去掉空项。用户名去空白转小写后整名相同即屏蔽；文本转小写后包含任一屏蔽词即屏蔽 |
| 3 重复合并 | `RepeatedDanmakuFilter` | 默认关；窗口默认 5 s，使用时限制在 1–30 s | 只看平台聊天（本地消息、空文本、其他类型不管）。文本去首尾空白、连续空白合成一个空格、转小写后比较；窗口内再次出现就隐藏（含窗口边界），每次出现（包括被隐藏的）都重新计时；关掉时清空记录；最多记 1024 条 |
| 4 相似度 | `DanmakuSimilarityFilter` | 默认关；阈值 85，缓存 3 s，最多 100 条，每条最多比较最新的 96 条 | 只看平台消息（本地消息不比较）。文本只去首尾空白，大小写、表情、标点都算；空文本不显示。与缓存中文本完全相同，或与最新 96 条之一的部分匹配分数达到阈值（含阈值），就隐藏并刷新那一条的时间；超过缓存时长（严格大于）的丢掉 |

另外两处与界面无关的逻辑也移了进来：

- `DanmakuNoticeThrottle`：同一条状态提示 3 s 内只显示一次，被丢的那次不延长窗口（v3 `_addStatusMessage`）。
- `DanmakuFilterSettings`：对应 v3 的设置项 `collapseRepeatedDanmaku`、`repeatedDanmakuWindowSeconds`、`enableDanmakuSimilarityFilter`、`danmakuSimilarityThreshold`、`danmakuSimilarityCacheDuration`、`danmakuSimilarityMaxCacheSize`，以及收藏设置里的 `blockedDanmakuUsers`、`shieldList`。改设置后下一条消息就生效，不用重连；相似度关掉时清空它的缓存。换房间时调用 `clear()`。

设置存储时的范围（阈值 50–100、缓存 1–60 s、条数 20–1000、重复窗口 1–30 s）由 J02.1 在读写设置时限制，和 v3 的 `DanmakuSettingsController` 一样；过滤器本身只做 v3 在使用处做的限制（阈值 0–100、条数 1–1000、比较条数 1–256、重复窗口 1–30 s）。

**相似度的打分**：v3 用 fuzzywuzzy 1.2.0 的 `partialRatio`。这个包是 GPL-2.0（没有写“或更高版本”），不能随 AGPL-3.0 的应用发布，归档 v4 的 ADR 0006 已决定去掉。归档 v4 和 pure_live_TV 都换成了别的打分（v4 检查所有等长窗口，TV 用单位代价的编辑距离），分数和 v3 不同。这里按公开的算法（Python fuzzywuzzy + python-Levenshtein 的 partial ratio）独立实现 `partialRatio`，目标是分数与 v3 完全相同：

- 按 UTF-16 码元、区分大小写比较；两者等长时第二个参数当作较短的一方；
- 对齐位置取自较短文本到较长文本的一条编辑路径：去掉公共前缀和后缀后，在编辑距离矩阵上从末尾回溯，优先顺序是相等字符的对角线、继续当前的插入或删除、替换、新的插入、新的删除；路径上每段相等字符（和公共前缀）给出一个对齐位置，两串末尾再算一个；
- 每个对齐位置在较长文本里取与较短文本等长的窗口（到末尾为止），得分 2 × 最长公共子序列 / 两者长度之和；任一得分超过 0.995 直接为 100，否则取最高分 × 100 四舍五入。

核对方法：在临时目录里用 fuzzywuzzy 1.2.0 做差分测试，30 万对随机文本（小字母表、中文、表情和代理对、嵌入和单字符变异）全部一致；故意去掉前缀处理的变体会出现 400 多处不一致，说明测试能发现细微差别。fuzzywuzzy 不是本包的依赖，测试里的期望值是用它算出后写死的 40 组（其中 15 组是“检查所有窗口”会得出不同结果的文本）。

## 表情

- `DanmakuEmoji`（v3 `UnifiedEmojiModel`）：按平台解析 v3 打包的表情表：
  - 哔哩哔哩：`emoji` 字段，空则用表里的键；
  - 抖音：`display_name`，图片取 `emoji_url.url_list` 的第一个；
  - 斗鱼：表里的键，没有方括号时加上；
  - 虎牙：`sName`，`sEscape` 作第二个键，图片优先 `sFlexiUrl`。
  - 其他平台得到空的表情，不会注册。v3 也打包了快手和网易 CC 的表，但从没读进来（快手的格式和哔哩哔哩一样，支持它列为升级候选）。
- `danmakuEmojiAssets`：v3 `EmojiManager.preload` 里去掉图片解码的部分：跳过没有本地文件的表情，同一张图的表情排在一起，按图片第一次出现的顺序，路径 `assets/emo/images/<平台>/<文件>`。它正好对应 flame_barrage 的 `EmojiInfo`（id、asset、keys；宽高由解码得到）。

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 回调改为事件流，原因带类型，界面文字由 M13 给出 | 可测试；协议层不再写死中文（和 Q01.1 第 9 条同一个问题）。对照表见上 |
| 2 | 停止后绝不会再有事件，由基类保证 | v3 靠每个平台把回调置空、再由控制器的会话令牌兜底；界面看到的效果相同 |
| 3 | 再次 `connect` 一定先关掉上一个连接 | v3 的 Twitch 和 SOOP 在第二次 `start` 时不关旧连接，全靠控制器每次先 `stop`；现在由基类保证，不再依赖调用方 |
| 4 | 所有平台的 `connect` 都等第一次尝试结束 | v3 的 SOOP 不等（`connect()` 没有 await）。连接超时 10 s 小于控制器的 20 s 启动超时，界面上看不出区别 |
| 5 | 最终关闭之后，这次连接里晚到的定时器和请求（比如虎牙醒目留言的补拉）不再上报 | v3 这时控制器已经释放了房间，同样会丢掉 |
| 6 | 目标里没有地址时以 `connectionFailed` 结束 | v3 的 `WebScoketUtils` 直接返回，界面一直停在“连接中” |
| 7 | 加入计时器在每次连接失败时都停掉 | v3 只在一轮失败的第一次停；计时器若在握手进行中触发，会多算一次失败。提示的时机不变 |
| 8 | 相似度用自己的实现 | 许可证；分数与 v3 相同（见上） |
| 9 | `BinaryWriter()` 可以不传列表；`ListUtil.subList` 的块大小小于 1 时抛错 | 前者只是省一个参数；后者 v3 会死循环（v3 没有调用方） |
| 10 | 表情表里类型不对的字段当作空字符串 | v3 会抛类型错误，整张表加载失败。打包的数据里没有这种情况 |
| 11 | 平台表构造时检查平台 id | 防止拼错的 id 让一个平台悄悄变成“没有弹幕” |

保持 v3 行为、没有顺手改的地方：

- 一轮连续失败只提示一次重连；这一轮里连上又断（中间没收到消息）不再提示，`isConnected` 也保持为 true，直到下一轮。改掉会改变画中画返回时是否重建连接的判断。
- 每次重新加入都发 `DanmakuReady`（界面会再显示一次“已连接”，由 3 s 的提示去重兜住）。
- YY 握手超时会连续出现两条重连提示（握手超时一条，连接自己的一条）。
- 哔哩哔哩在认证完成前就按间隔发心跳。

## 放到其他模块的部分

| v3 内容 | 去向 | 说明 |
|---|---|---|
| `DanmakuController` 的会话管理 | M13 直播间 | 串行化的连接和断开、房间键 `平台:房间号`、启动超时 20 s（超时提示 `danmaku_connection_timeout` 并停止）、停止超时 5 s、同房间且已就绪时不重连（画中画返回）、同房间已断开时重建但保留已显示的弹幕、换房间时清屏并调用 `DanmakuMessageFilter.clear()`；按消息类型分发（聊天进列表和画面，观众数更新房间，醒目留言进醒目留言栏）；随“显示弹幕”和“画中画弹幕”开关启停，IPTV 和网易 CC 不连。新接口不再需要会话令牌 |
| 状态提示的文字 | M13 | `connect_danmaku_server`、`danmaku_connected`、`recording_mode_notice`、`remote_danmaku_not_integrated`，以及上面“原因”表里的文字；3 s 去重用 `DanmakuNoticeThrottle` |
| 哔哩哔哩游客昵称被打码的提示 | M13（判定可由 D01.2 提供） | 每个会话一次：平台是哔哩哔哩且用户名匹配 `\*{2,}|＊{2,}` 时提示 `bilibili_guest_name_masked` |
| `danmaku_session_host.dart` | M13 | 直播间给控制器的界面接口 |
| `danmaku_presentation_recovery.dart` | M13 | 画中画返回后的恢复：等 180 ms 合并信号，被挡住时 120 ms 后重试，恢复进行中来的请求在结束后重放 |
| 弹幕设置页、设置的存储和范围限制 | M13、J02.1 | 过滤相关设置的默认值见上表 |
| `EmojiManager` 的加载和解码、`EmojiAtlas`、`noEmojiMode` | A01.1 | 读 `assets/emo/json/<平台>.json`（用本包解析），按 24×24 解码图片、每批 6 张、换平台时整体替换。v3 的一个问题留给 A01.1：网易 CC 的平台 id 是 `cc`，文件却叫 `netease_cc.json`，加载失败时会留着上一个平台的图集 |
| `assets/emo`（24 MB 的表情表和图片） | A01.1、I01.1 | 应用资源 |
| 画面弹幕渲染（flame_barrage）、弹幕列表、滚动 | A01.1、M13 | flame_barrage 期望的消息是 `BarrageMessage`（id、content、timestamp、type、userId、userName、priority），由 `LiveMessage` 转换 |
| `live_core` 的 `LiveDanmaku`、`EmptyDanmaku`、`LiveSite.getDanmaku()` | D01 各平台完成后删除 | 本模块不改其他包；应用改用 `DanmakuRegistry` |
| 大小写敏感的 WebSocket 握手（v3 `yy_web_socket_channel.dart`） | D01.7、D01.8 | 已完成：D01.7 新增共享的 `src/exact_websocket.dart`（`connectExactWebSocket`），YY 和 SOOP 都用它 |

## 上游核对

- pure_live_TV `e1cca224`：`LiveDanmaku` 接口和 `WebSocketUtils` 与 v3 相同，只是类名改正、文字换成多语言键（上面的对照表用了这些键）。它的相似度过滤换成了分数不同的实现，没有采用。平台协议里值得带到 D01 各平台 的是虎牙醒目留言请求的 3 s 超时（D01.4）。
- flame_barrage `3eddae8`：只看了它期望的消息和表情模型（见上），渲染属于 A01.1。
- 归档 v4：见“做法”最后一条。

## 测试

104 个用例，连续跑 5 次（并发 8）全部通过：

| 测试文件 | 用例 | 内容 |
|---|---|---|
| `connection_test.dart` | 16 | 基类：事件顺序、同步送出、`close` 后没有事件、重复 `close`、最终关闭后 run 失效并释放、再次 `connect` 先停旧的、开始途中 `close`、`DanmakuStartFailure`、其他错误抛给调用方、被取代的 run 出错不抛、参数类型不对、`markDisconnected`、`delay` 提前结束；空连接；平台表（查找、每次新建、未注册平台、非法和重复 id、空表） |
| `socket_connection_test.dart` | 18 | 假连接器：打开即就绪和心跳、平台确认后就绪、加入超时重连、确认后不再超时、YY 式的超时提示、协议失败、无消息时换地址且一轮只提示一次、提示带失败详情、退避序列（记录计时器：1、2、2、3、3、4、4、5 倍）和 8 次后放弃、收到消息后重新计数、`close` 后没有事件和心跳、`close` 中止卡住的握手、换房间关掉旧连接、`reopen`、开始失败不开连接、没有地址、手动心跳；再加一个真实的本地 WebSocket 服务器 |
| `binary_test.dart` | 14 | 哔哩哔哩和斗鱼的包头、各宽度的补码和大小端、截断、不支持的宽度、浮点、读写往返、读的符号、越界、`splitList`（含 SOOP 聊天包）、`subList` |
| `message_gate_test.dart` | 13 | 移植 v3 的 4 个用例；另加 45 s 和 10 分钟的边界、未来时间、过期消息不入表、id 窗口含边界、无 id 窗口不滑动、键的大小写规则、类型在键里、满时逐出最旧、`clear` |
| `repeated_filter_test.dart` | 7 | 移植 v3 的 2 个用例；另加空白和大小写、表情、窗口边界和滑动、其他类型和本地消息、满时逐出、`clear` |
| `similarity_test.dart` | 16 | `partialRatio` 的 40 组 fuzzywuzzy 分数、大小写和码元；移植 v3 的 4 个用例；另加默认值、阈值边界、去空白规则、部分匹配、过期边界、隐藏时刷新、只比较最新的、满时逐出、设置的限制和立即裁剪 |
| `message_filter_test.dart` | 13 | 屏蔽名单的规则；过滤链的默认值、顺序（闸门先于屏蔽）、重复窗口的限制、相似度对本地消息不生效、设置即时生效和关闭时清空、其他类型不过滤、`clear`；提示去重 |
| `emoji_test.dart` | 7 | 四个平台的解析规则、其他平台为空、非对象的条目、图集条目的顺序和路径 |

## 模型追加（D01 后续，2026-09-30）

各平台的后续升级（Twitch 的 CLEARMSG/CLEARCHAT/USERNOTICE、Picarto 的删除和系统通知等）需要两种 3.x 没有的消息，所以在 `live_core` 的 `LiveMessageType` 末尾加了两项（3.x 的四项顺序不变）：

| 类型 | `data` | 含义 | 界面（M13） |
|---|---|---|---|
| `retraction` | `LiveRetraction` | 撤回已经显示的消息：`.message(id)` 按平台消息 id 撤回一条，`.user(id)` 撤回某个发送者的全部，`.all()` 清空 | 从聊天列表里去掉对应的行；已经飞出去的弹幕不追 |
| `notice` | `LiveNoticeKind`（`system`、`subscription`、`raid`） | 平台或房间的通知，文字在 `message` | 在聊天列表里单独一行显示，不作为弹幕飞出 |

- 过滤：重复、相似和屏蔽词过滤只作用于聊天，这两种不受影响。
- 去重闸门：没有消息 id 时的键原来是“类型 + 用户 + 文字”，撤回的文字是空的，两次不同的撤回会被当成重复，所以键里加上撤回目标。撤回消息本身不要填被撤回消息的 id 作 `messageId`，否则会和原消息撞键。

**补回的消息（D01 后续升级（原 M5.F），附录 B-22、B-26，2026-10-01）**：`LiveMessage` 加了 `replayed`（布尔，默认 `false`，只做添加）：这条是断线续接补回的，或进房时平台给的积压（例如仍在显示的醒目留言），不是刚发生的。去重闸门（`DanmakuMessageGate`）相应加了两条年龄规则，上面“过滤”表第 1 步的其他规则（未来 10 分钟以外丢弃、id 10 分钟、无 id 2.5 s、不滑动、4096 条）和 id 去重都不变：

- `replayed` 的消息，平台时间的年龄上限用新的 `maxReplayAge`（默认 135 s，含 135 s 通过），不用 45 s。135 s 是 17LIVE 的续接窗口：Ably 的 `connectionStateTtl` 120 s 加 `maxIdleInterval` 15 s，超过它就不再续接（D01.30 的 B-14），补回来的消息不会更老；
- 醒目留言（`data` 是 `LiveSuperChatMessage`，不看类型）在它的 `endTime` 之前（严格早于）不按年龄丢，它本来就按自己的显示时长显示（YouTube 进房时补报的置顶 Super Chat 可能是一小时前的）；到了 `endTime` 照上一条的年龄规则；
- 年龄不合格的消息照旧在记 id 之前丢掉，所以之后同一 id 的新消息仍能通过。
- 使用者：YouTube 进房时补报仍在置顶的 Super Chat（B-22，D01.20 末节），17LIVE 续接后服务端补发的积压（B-26，D01.30 末节）。
- 过滤链 `DanmakuMessageFilter` 没有改：仍只让聊天过闸门，醒目留言等其他类型直接通过。M13 按类型分发时若让醒目留言也过闸门（例如按 id 去掉进房补报后又正常收到的同一条），上面第二条规则保证它们不会因为年龄被丢；3.x 的醒目留言栏本来就按 `messageId` 判等去重。
- 测试：`test/message_gate_test.dart` 新增 5 个（共 20 个，原有 15 个不变）：`replayed` 的 135 s 边界（含）和再多 1 ms、同样年龄不带 `replayed` 的被丢、没有时间不看年龄；`maxReplayAge` 可设、未来 10 分钟的限制对 `replayed` 不变；醒目留言显示中（早两小时也通过）、正好到 `endTime`、已结束时回到 45 s 或 135 s、未来时间照样丢、没有 id 时照旧按文字去重；只有 `data` 是 `LiveSuperChatMessage` 才算醒目留言；`replayed` 和原消息同 id 只收一次、进房补报的醒目留言和之后同一条只收一次、过老的不入表。变异检查：不看 `replayed`、去掉醒目留言规则、`endTime` 那一刻也算显示中、显示中的醒目留言不查未来时间，都有用例失败。

## 后续升级（D01 后续升级（原 M5.F），附录 B-1）

B-1“握手被拒（会话失效）时换会话重连”要框架在握手失败时把原因交给平台（猫耳 D01.13 候选 4：`FM_SESS` 过期后握手变成 HTTP 403，原来只能按普通断线重试到用尽）。只做了添加，默认行为不变。

- **`DanmakuHandshakeFailure`**：一次失败的握手，`endpoint`、`error`（连接器抛出的原样），`refused`（服务端有回答但没升级，即 `WebSocketException`；连不上、超时、TLS 错误为 false），`statusCode`（`dart:io` 的 `WebSocketException.httpStatusCode`，例如 403）。
- **`DanmakuSocketConnection.onHandshakeFailure(session, failure)`**：握手失败时调用（只在这次运行、这个 socket 仍是当前的时候）。返回请求头（立即返回，或返回一个 Future）时，这个 socket 之后的握手改用它（例如带新会话的 Cookie）；下一次握手先等这个 Future 结束。返回 null（默认）什么也不改、不等待；Future 出错或钩子抛错按 null 处理。
- **重连不变**：失败仍由 `LiveSocket` 按原来的方式处理（一轮只报一次 `DanmakuReconnecting`、换地址、退避、最多 8 次、收到消息清零），钩子只决定下一次握手带什么请求头。
- **做法**：运行时给 `LiveSocket` 的连接器包一层（`_open` 里），每次握手都经过它：先等进行中的更换，再用当前的请求头调用平台原来的连接器（没有就是 `connectIoSocket`），失败时把错误交给钩子再原样抛出。换的只是请求头：地址和子协议不变（凭据在地址里的平台仍用 `session.reopen`）；只作用于这个 socket，`reopen`、换房间都从新目标的请求头开始。
- **没改的地方**：`live_net` 的 `LiveSocket` 没有改。`connectExactWebSocket`（YY、SOOP）的异常只在文字里写状态行，没有加 `httpStatusCode`：加了会改变 YY 断线提示里的失败文字；这时 `refused` 为 true、`statusCode` 为空。
- **使用者**：猫耳（403、401 时换游客会话，每轮失败一次，见 D01.13 末节）。其他平台没有覆盖这个钩子。
- **测试**：`test/socket_connection_test.dart` 新增 8 个（共 26 个）：被拒的握手报给平台、`endpoint`/`refused`/`statusCode` 正确，换过的请求头在退避后的握手上；下一次握手等更换结束；立即返回的请求头马上生效，null、默认、失败的 Future、抛错的钩子都保持原请求头；连不上和超时也报但不算被拒、没有状态码，升级头不对算被拒；更换途中关闭后不再握手、不改请求头、没有事件；`reopen` 和换房间用自己目标的请求头；已关闭的 socket 的失败不报；本地服务器回 403 时拿到 `dart:io` 的状态码，换 Cookie 后连上（服务端的 WebSocket 在结束时关闭）。原有 18 个用例不变，全部通过；变异检查：握手不用换过的请求头、不等更换、关闭后仍调用钩子，都有用例失败。
