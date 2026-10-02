# T06a.16 弹幕（新增）：SHOWROOM

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/showroom.dart`
  - `ShowroomDanmakuConnection`：连接；
  - `ShowroomDanmakuProtocol`：地址、握手请求头、订阅、心跳、参数检查、帧的解码，不做 I/O。
- 参数：`live_core` 的 `ShowroomDanmakuArgs(roomId, host, key)`，T02c.6（19-3）已给出。
  - `host`、`key` 就是 `live/live_info` 的 `bcsvr_host`、`bcsvr_key`；进房（`getRoomDetail`）和录制详情在直播中时放进 `LiveRoom.danmakuData`，不多发请求；刷新和未开播都没有；
  - 平台层已经检查过：主机是 `showroom-live.com` 或它的子域名（不带端口、路径，转成小写），键不超过 256 字、不含空白和控制字符；
  - 本模块没有改 `live_core`。
- 升级条目：19-3“评论（弹幕）”。v3 没有 SHOWROOM 评论（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 样本：`fixtures/showroom/danmaku/S06-live`（归档 v4 的真实录制，2026-09-27 18:19 UTC，房间 577362，约 71 s，25 行：订阅、18 条评论、2 个字幕更新、1 个系统通知、1 个 `t` 100、1 次 `PING` 和它的 `ACK`）。帧没有改，本模块加上 v4 解码的冻结输出 `expected.json` 和生成它的 `danmaku/v4_expected.dart`，没有新录样本。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/showroom.dart`（`ShowroomProtocol`、`ShowroomConnector`）和它的运行时 `runtime/socket_connector.dart`；规格 `spec/sites/showroom.md` 第 7 节（来自 2026-09-27 实测）；
  - 网页客户端：房间页 `https://www.showroom-live.com/r/<房间键>` 加载的 `client-cdn.showroom-live.com/assets/96f27c9d…/_nuxt/3Q1w5SdD.js`（2026-09-28 21:43 UTC 下载），里面的评论连接（`initBcsvrAdapter`）、消息类型表和它用的 reconnecting-websocket 库，见“网页客户端”；
  - pure_live_TV `e1cca224`：`lib/platforms/showroom/showroom_site.dart:45` 仍是 `EmptyDanmaku`，没有可参考的实现；
  - 2026-09-28 21:40～22:00 UTC（北京时间 29 日 05:40～06:00）的只读实测：匿名、直连、不登录、不发言，见“实测”。

## 做法

- **建在 T06a.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`），和 Twitch（T06a.9）同一类：文本帧，打开后发加入帧，按间隔发心跳。平台代码只写这几样：
  - `target`：检查参数，给出 `wss://<host>/` 和握手请求头；
  - `onOpen`：发 `SUB\t<key>`，随即就绪（`session.ready()`）；
  - `onData`：解一帧；
  - `heartbeatFrame`：`PING\tshowroom`。
  - 换地址、退避、最多 8 次、无消息检测、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **参数再检查一次**：连接也可能拿到不是平台层产生的参数（`ShowroomDanmakuArgs` 的构造函数是公开的）。检查直接调用平台层的 `ShowroomApi.danmakuArgs`，规则只有一份；不合格就以 `DanmakuClosed(connectionFailed, 'No usable comment server or key')` 结束，不握手。键里不能有制表符，否则可以借订阅帧拼出别的命令。
- **不需要保留请求头大小写**：服务端不看请求头（实测不带 `Origin`、UA 也能连），用默认的 `dart:io` 握手，不用 `connectExactWebSocket`。请求头照归档 v4 和录制带 `Origin: https://www.showroom-live.com` 和平台层的 Chrome 140 UA（`ShowroomApi.userAgent`）。
- **只上报聊天**（`t` 1）。平台的评论流里没有醒目留言、付费留言，也没有在线人数；礼物、字幕、系统通知、应援点数、下播和开播通知都不报（和 T06a.2～T06a.13 的范围一致，见差异 1）。
- **在线人数的来源不变**：评论流里没有观看人数（`t` 5 是房间的应援点数，不是人数），`audience.dart` 里 SHOWROOM 一项（累计观看、没有在线人数）不用改。

## 协议

socket：

| 项目 | 内容 |
|---|---|
| 地址 | `wss://<bcsvr_host>/`（443 端口；网页写作 `wss://<host>:443`，是同一个地址）。`live_info` 的 `bcsvr_port` 是 8080，实测 `wss://<host>:8080` 握手 10 s 超时，不用 |
| 握手 | 请求头 `Origin`、`User-Agent`（见上）；约 1.3 s 打开 |
| 订阅 | 打开后发文本帧 `SUB\t<bcsvr_key>`。`bcsvr_key` 形如 `<16 位十六进制>:<live_id>`，每场直播一个，所有观众相同，不需要令牌。服务端不确认订阅：键不对或不订阅都只是收不到 `MSG`（实测） |
| 心跳 | 发 `PING\tshowroom`，服务端约 0.3 s 内回 `ACK\tshowroom` |
| 下行 | 文本帧 `MSG\t<bcsvr_key>\t<JSON 对象>`，对象的 `t` 是消息类型 |

消息（`t`；名称取自网页的类型表，字段是实测的）：

| `t` | 网页的名称 | 字段 | 本实现 | 归档 v4 |
|---|---|---|---|---|
| 1 | `COMMENT` | `cm` 评论、`ac` 名字、`u` 用户 id、`created_at`（秒）、`cl` 等级、`av` 头像 id、`cifn`/`cbisc`/`cbiec` 等级徽章、`ua`、`aft`、`at`、`d` | 白色聊天（见下） | 聊天，不读 `cl` |
| 2 | `GIFTING` | `g` 礼物 id、`n` 数量、`gt`、`h`，以及和评论相同的用户字段 | 不报（差异 1） | 礼物，名字写 `#<g>` |
| 11、17 | `GIFT_ONLY`、`ANIMATION_GIFT` | 礼物 | 不报 | 不报 |
| 5 | `SUPPORT_POINT_UPDATE` | `p` 点数、`c` | 不报 | 不报 |
| 8、9 | `TELOP_START`、`TELOP_END` | `telop`、`telops`、`interval`、`api` | 不报 | 不报 |
| 18 | `LIVE_SYSTEM_LOG` | `m`、`me`（日文、英文通知，带观众名字）、`c`、`u`、`tt` | 不报 | 不报 |
| 101、104 | `LIVE_END`、`LIVE_START` | — | 不报（见“放到其他模块的部分”） | 不报 |
| 100 | （网页的表里没有） | 只有 `created_at` | 不报 | 不报 |
| 3、4、6、20、23～35、403、1001 等 | 投票、推特头像、欢迎语、联动对战、卡拉 OK、电商、排行评论… | — | 不报 | 不报 |

评论解成白色聊天：

- 文字是 `cm` 去首尾空白；是整数时照网页写成数字；空白、其他类型不报。纯数字的评论（“1”“2”…）是 SHOWROOM 观众的数数习惯，照常上报；
- 用户名 `ac`、用户 id `u`（整数或字符串）；
- 等级 `cl` 大于 0 时填进 `userLevel`（网页只在大于 0 时显示“Class <cl>”徽章；v3 的消息菜单显示成“Lv.<cl>”）；
- 时间 `created_at`（秒），不大于 0、不是整数或超出 `DateTime` 范围时为空；
- 平台不给消息 id，`messageId` 留空，由 T06a.1 的闸门按没有 id 的规则去重（差异 2）。
- 头像、徽章图片和颜色、`ua`、`aft`、`at`、`d` 不读。

帧的解法：以 `MSG\t` 开头，第一个和第二个制表符之间的键必须等于本次订阅的键（规格 §7.3），第二个制表符之后整段按 JSON 读（合法 JSON 的字符串里不会有未转义的制表符）。`ACK`、别的键、不是 JSON、JSON 不是对象、其他类型都丢掉这一帧；二进制帧按 UTF-8 解码（服务端没发过）。

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 网页客户端 | 依据 |
|---|---|---|---|---|
| 地址 | `wss://<host>/`，一个 | 同；没有主机时用 `online.showroom-live.com` | `wss://<host>:443` | 平台层总会给主机 |
| 握手请求头 | `Origin`、Chrome 140 UA | 同 | 浏览器 | 实测不带也能连 |
| 加入 | 打开后发 `SUB`，随即就绪；每次重连都重发、再报一次 `DanmakuReady` | 同（打开即加入） | `onopen` 里发 `SUB` | 服务端不确认订阅 |
| 心跳 | 每 60 s 发 `PING\tshowroom`，打开后第一次在 60 s 时（不在加入时立刻发）；手动 `heartbeat()` 立即发一次 | 同（`heartbeatOnJoin` 为 false） | 不发 | 没人说话的房间除 `ACK` 外可能什么都没有（实测 90 s 里只收到 `ACK`），靠它喂无消息检测 |
| 无消息超时 | max(3 × 60 s, 90 s) = 180 s（每 60 s 检查一次，所以 180～240 s 内发现，这期间发出的 3 次 `PING` 都没有回答） | 同 | 无（靠浏览器报告断开） | 框架默认 |
| 加入超时 | 无 | 无 | 无 | 打开即加入 |
| 断线重连 | 框架默认：只有一个地址，间隔 2、3、4、5、6、6、6、6 s，最多 8 次，收到任何帧清零，一轮只提示一次；用同一个键重新订阅 | 框架（v4 的运行时），同一个键 | reconnecting-websocket 的默认值：第一次等 1～5 s（随机），之后每次 × 1.3，最多 10 s，不限次数，握手 4 s 超时 | 框架的统一做法 |
| 参数不对 | `connectionFailed`，不握手 | 终态 `credentials` | — | — |
| 下播、重新开播 | 不处理：连接保持（只剩 `ACK`）；新的一场键不同，要重新进房拿新参数 | 同 | `t` 101 标记下播；`t` 104 刷新整页 | 放到 M13 |

## 网页客户端

`3Q1w5SdD.js` 里与评论有关的部分（压缩后的名字不固定，按作用描述）：

- 连接：`new ReconnectingWebSocket("wss://" + bcsvr_host + ":443")`，不带选项；`onopen` 里发 `"SUB\t" + bcsvr_key`；
- 收到：取 `data.split("\t")[2]` 按 JSON 解析（不检查键），按 `t` 分发。类型表：`COMMENT` 1、`GIFTING` 2、`VOTE_START` 3、`VOTE_END` 4、`SUPPORT_POINT_UPDATE` 5、`TWITTER_ICON` 6、`TELOP_START` 8、`TELOP_END` 9、`GIFT_ONLY` 11、`ANIMATION_GIFT` 17、`LIVE_SYSTEM_LOG` 18、`WELCOME_COMMENT` 20、联动对战 23～31、`RADIO_IMAGE_CHANGE` 33、`BROADCAST_MODE_CHANGE` 34、`KARAOKE_STATUS` 35、`LIVE_END` 101、`LIVE_START` 104、`EC_PURCHASE_ANIMATION` 403、`RANKING_COMMENT` 1001；
- 评论：显示 `cm`、`ac`、头像 `av`、`created_at`，`cl` 大于 0 时显示“Class <cl>”徽章（`UserClassLevel` 组件）；登录用户自己的评论跳过（本实现是匿名的，不涉及）；
- 不发心跳；重连用 reconnecting-websocket 的默认值（见上表）。

## 登记方式

应用（T07a.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.showroom: () => ShowroomDanmakuConnection(proxy: proxyPolicy),
  // …
});
```

- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `showroom` 选 socket 的路由，和接口请求用同一份设置。
- 不需要 HTTP 客户端、Cookie：开始时不发请求，全程匿名，v3 也没有 SHOWROOM 的 Cookie 设置。
- `connector`、`policy` 只给测试用，应用不传。默认握手是 `dart:io`，不需要 `connectExactWebSocket`。
- 参数来自 `getRoomDetail`（和录制详情）；未开播、刷新得到的房间没有参数，按 T06a.1 不连接。

## 与归档 v4 的对照

- 解码的对照：`fixtures/showroom/danmaku/v4_expected.dart` 把归档 v4 的 `ShowroomProtocol` 原样搬进一个独立程序，只替换它从别处引用的 `TextFrame`、事件类型（`DanmakuChat`、`DanmakuGift`）和 `DecodeContext`。它用 `meta.json` 的 `danmakuKeys` 写下 socket 地址、握手请求头、订阅帧、心跳帧和间隔，再用 `decode` 读每个收到的帧，写下解出的事件（投影）。运行：在仓库根目录 `dart run fixtures/showroom/danmaku/v4_expected.dart`，结果在 `S06-live/expected.json`，`generator` 字段写明来源。
- v4 的消息 id 最后一段是文本的 `String.hashCode`，Dart 不保证它在不同 SDK 间不变，所以测试只比较它前面的部分。
- 测试用同一份录制跑新代码：

| 对照 | 结果 |
|---|---|
| 地址、请求头、订阅帧、心跳帧、心跳间隔 | 与 v4 相同，也等于 `meta.json` 记下的握手和录制里发出的两帧（`SUB`、`PING`） |
| 进房给的参数 | 平台层从 `S04-live-info-live`（同一场直播）解出的 `ShowroomDanmakuArgs` 正是录制的主机和键，用它连接得到录制的地址和订阅帧 |
| 23 个收到的帧 | 逐帧一致：18 条聊天（用户 id、用户名、文字、时间），字幕更新、系统通知、`t` 100 和 `ACK` 都没有消息。差别只有消息 id：v4 自己拼一个（`showroom:<u>:<created_at>:<哈希>`，测试核对了前两段），新代码留空（差异 2）；录制里没有 `cl`，两边的等级都为空 |
| 用连接重放录制 | 1 个 socket、就绪 1 次，发出的帧与录制相同（打开时 `SUB`，手动心跳时 `PING`），18 条聊天按顺序上报 |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 不上报礼物（`t` 2） | v3 所有平台都不显示礼物（`LiveMessageType.gift` 注明“not shown yet”），T06a.2～T06a.13 也都不报。v4 报，但礼物名只有编号（`#<g>`，礼物表要另外的接口，规格 §12 待确认 2） |
| 2 | 消息 id 留空 | 平台不给 id。和 T06a.2～T06a.13 一样，没有 id 就交给 T06a.1 闸门的无 id 规则：同一用户的同一文字 2.5 s 内只收一次，已经包含 v4 这个 id 能去掉的情况（同一用户同一秒的同一文字）。拼出来的 id 还会让闸门跳过这条规则 |
| 3 | 等级取 `cl`（大于 0 时） | 网页在评论旁显示这个等级；按“字段按平台数据填”。v4 不读。2026-09-27 的录制里还没有这个字段 |
| 4 | 文字只接受字符串和整数，用户名只接受字符串和整数；时间超出 `DateTime` 范围时为空 | v4 把任何值转成文字（`true`、对象也会成为评论）；时间超出范围时 `DateTime.fromMillisecondsSinceEpoch` 抛错，整帧丢掉 |
| 5 | 参数用平台层的规则再检查：主机可以是 `showroom-live.com` 本身、每段标签合法、转成小写；键不能有空白和控制字符。不合格是 `connectionFailed` | v4 用 `^[a-z0-9.-]+\.showroom-live\.com$`（`..showroom-live.com` 也能通过，大写的主机被拒），不检查键（带制表符的键会在订阅帧里拼出别的命令），失败时报 `credentials`；没有主机时退回 `online.showroom-live.com`，现在平台层总会给主机 |

没有改的：地址、请求头、订阅、心跳和间隔、打开即加入、无消息超时、按键过滤、`t` 的判定（整数 1 或字符串 `"1"`）都与 v4 相同。

## 与网页客户端的差异

- 发心跳（网页不发）：见“连接和时序”。
- 按键过滤（网页不查键）：规格 §7.3；一个 socket 只订阅一个键，实测从没收到别的键。
- 退避按框架（最多 8 次），不是网页的无限重试。
- 不处理下播（101）和开播（104）：网页据此标记下播、刷新整页，这里的连接不管房间状态，由 M13 决定。

## 实测

2026-09-28 21:40～22:00 UTC（北京时间 29 日 05:40～06:00）只读、匿名、直连，没有登录，没有发言。用一个只依赖 `dart:io` 的小程序连接，输出里只看数量、字段名和类型，不记用户的值；结果没有存成样本。

- **取参数**：`live/live_info` 在播时给 `bcsvr_host`（`online.showroom-live.com`）、`bcsvr_port`（8080）、`bcsvr_key`（`<16 位十六进制>:<live_id>`）。`live/onlives` 的每行也带 `bcsvr_key`（本实现不用）。
- **握手**：带 `Origin` 和 UA、什么都不带，都约 1.3 s 打开；`wss://<host>:8080` 10 s 内握手不成功。
- **订阅**：错键（`0000000000000000:<live_id>`）和不订阅都只收到 `ACK`，没有任何 `MSG`，服务端也不断开。
- **心跳**：每次 `PING\tshowroom` 约 0.3 s 后收到 `ACK\tshowroom`。一个 300 s 不发 `PING` 的连接没有被服务端断开。
- **下行**：同时连 6 个人最多的房间 90 s，另外一个人多和一个人少的房间各 250 s、300 s：
  - 收到的 `t` 有 1、2、5、8、17、18、35、100，都是整数；6 个房间 90 s 里的 47 条评论，字段都是 `ac, aft, at, av, cbiec, cbisc, cifn, cl, cm, created_at, d, t, u, ua`，`u`、`cl`、`created_at` 是整数，`cm`、`ac` 是字符串，`cl` 都大于 0；评论的 `created_at` 与本机时间相差都在 5 s 以内；
  - `t` 8 在有的房间每 30 s 一个，但有一个房间 90 s 里除了 `ACK` 什么都没有，所以心跳是必要的；
  - `t` 100 只有 `created_at`，在有的房间约 30～50 s 一个（网页的类型表里没有）；
  - 没有观看人数类的消息。
- **本实现**：没有接到真实服务器上跑（测试用本地服务器）；协议和上面逐项对照过，与实测一致。

## 样本

- 没有新录样本，`frames.jsonl` 和 `meta.json` 没有改动。新加的只有 `S06-live/expected.json`（归档 v4 的解码输出）和生成它的 `v4_expected.dart`，里面只有已脱敏的值。
- 逐个字段检查了 `S06-live` 的 25 行：
  - 评论的 `u`、`ac` 录制时已换成同形的合成值（`meta.json` 的 `scrubbed`：名字是 `观众1`～`观众6`，用户 id 是 7 位数字）；评论只有 `t`、`cm`、`created_at`、`u`、`ac` 五个字段（实测的评论有 14 个，头像 id `av` 等没有保留下来）；其他类型的消息只留了 `t`（`scrubbed` 的 `dropped`），所以系统通知里的观众名字也不在样本里；
  - `bcsvr_key` 是这场直播的公开订阅键（所有观众相同，`live/onlives` 也公开给出），T02c.6 已按公开信息保留；
  - 找不到 IP 地址、头像路径、令牌、Cookie。门禁的 `fixture privacy` 通过。
- 房间号是公开信息，按 T02c.6 的口径保留。

## 受阻

没有。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | T07a.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（T06a.1 的原因表） |
| 主播重新开播后换新的键 | M13：进房详情（或直播间的定时刷新）给出新的 `ShowroomDanmakuArgs` 时重新 `connect`。旧的连接不会自己结束，只剩 `ACK` |
| 下播提示 | M13 决定是否要：评论流在下播时发 `t` 101、开播时发 `t` 104，网页据此标记下播或刷新页面；本实现不报这两种消息，要用时在协议层加一个事件 |
| 显示礼物（若以后要做） | M13 统一决定；本平台要解 `t` 2（以及 11、17），礼物名要另查礼物表（规格 §12 待确认 2） |
| 录制时是否带评论 | T08a.1（录制详情也带参数，T02c.6） |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | T06a 各平台完成后删除 |

## 新增的通用能力、依赖

没有。框架没有改，没有新依赖；`live_core` 没有改，参数检查直接用平台层已有的 `ShowroomApi.danmakuArgs`。

## 测试

`test/sites/showroom_test.dart` 17 个用例，`live_danmaku` 共 707 个，连续跑 3 次全部通过；本文件在时钟 +30 天、+1 年、+5 年下直接运行（`tools/timeshift` 的方式）也都通过，进程正常退出：

- 协议 5 个：地址、订阅、心跳、`ACK`、握手请求头；参数检查（大写主机转小写、256 字的键、冒充的主机、端口、路径、IP、空键、空白、制表符、控制字符、257 字）；一条评论的各字段（按实测的字段形状合成）；评论的边界（空白和非字符串文字、整数文字、字符串 `"1"` 的类型、其他 16 种 `t`、没有名字和 id、各种等级、时间的 0、负数、上限和越界）；帧（`ACK`、`PING`、截断、坏 JSON、数组、别的键、键的前缀和后缀、大小写、字节帧和坏的 UTF-8、转义的制表符、礼物、字幕、系统通知、下播、开播）。
- 录制 4 个：地址、请求头、订阅、心跳与 v4 和 `meta.json`、录制发出的帧一致；`S04-live-info-live` 经平台层解出的参数就是录制的那场直播；23 个收到的帧与 v4 的冻结输出逐帧一致；用连接重放整份录制。
- 连接 8 个：
  - 默认时序和平台表登记；握手（地址、请求头、代理路由、打开时发 `SUB`、就绪、别的键和 `ACK` 不上报）；
  - 按间隔发 `PING`、有 `ACK` 时不换连接、手动心跳，`PING` 没有回答时换连接并重新订阅；断线后重连、重新订阅、再次就绪；握手失败后重试，连续失败用尽后 `reconnectsExhausted`；
  - 参数不对直接结束、不握手，参数类型不对抛 `ArgumentError`；关闭后没有事件、不再发帧，再次 `connect` 换房间（旧 socket 和旧键的帧都不上报）；
  - 真实的本地服务器：默认的 `dart:io` 握手（路径、`Origin`、UA），服务端收到 `SUB` 和 `PING`、回 `ACK`，字幕更新不上报、聊天上报；结束时关掉服务端所有升级后的 WebSocket 和服务器，直接运行测试文件时进程能退出。
