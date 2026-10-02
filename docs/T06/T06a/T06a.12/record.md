# T06a.12 弹幕（新增）：TwitCasting

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/twitcasting.dart`
  - `TwitcastingDanmakuConnection`：连接；
  - `TwitcastingDanmakuProtocol`：取地址的请求、回答的解析、推送帧的解码，不做 I/O。
- 参数：`live_core` 的 `TwitcastingDanmakuArgs(channel, movieId)`，T02c.4（12-3）已给出。
  - 进房时 `TwitcastingSite.getRoomDetail` 把它放进 `LiveRoom.danmakuData`，只在直播中、`movie.id` 大于 0 时有；不多发请求。
  - 录制详情同样带着（它就是完整详情），关注刷新不带。
  - 本模块没有改 `live_core`。
- 升级条目：12-3“评论（弹幕）”。v3 没有 TwitCasting 评论（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 样本（都来自归档，2026-09-27 直连录制）：
  - `fixtures/twitcasting/S07-pubsub`：`eventpubsuburl.php` 的请求和回答；
  - `fixtures/twitcasting/danmaku/S08-live`：频道 c:abzou_sub 约 45 s，14 行：开始时的 `eventpubsuburl.php` 回答和 13 个推送帧（12 条评论、2 个保活 `[]`，其中一帧有两条评论）；
  - 本模块新加归档 v4 解码的冻结输出 `S08-live/expected.json`，没有新录样本。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/twitcasting.dart`（`TwitcastingProtocol`、`TwitcastingConnector`）和它的运行时 `runtime/socket_connector.dart`；规格 `spec/sites/twitcasting.md` 第 7 节（来自 2026-09-27 实测）；
  - 网页播放器脚本 `https://twitcasting.tv/js/v1/PlayerPage2.js?1790573736`（2026-09-29 下载，见“网页播放器”）；
  - pure_live_TV `e1cca224`：`lib/platforms/twitcasting/twitcasting_site.dart` 仍是 `EmptyDanmaku`，没有可参考的实现；
  - 2026-09-29 只读实测：匿名、直连，不登录、不发言，见“实测”。

## 做法

- **建在 T06a.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`）。平台代码只写这几样：
  - `target`：检查参数，给出名义地址和握手请求头；
  - `onOpen`：打开即加入（`session.ready()`）；
  - `onData`：解一帧；
  - 不发心跳帧（`heartbeatFrame` 用默认的 null）。
  - 换地址、退避、最多 8 次、无消息检测、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **每次握手前都重新取一次签名地址**，和网页一样：
  - socket 地址里的 `token` 大约一小时后过期（见“实测”），`LiveSocket` 重连时却总是用同一个地址；
  - 所以交给 `LiveSocket` 的是名义地址 `https://twitcasting.tv/eventpubsuburl.php?movie_id=<直播号>`，本平台的握手函数（包在 `connector` 外面）每次握手先 POST 取新地址，再用它握手；
  - 取地址失败（网络错误、状态码不是 2xx、回答里没有 wss 地址）就当作这次握手失败，走框架的退避和 8 次上限，和 socket 握手失败一样；
  - 一次 `connect` 里取地址的请求绑定一个 `CancelToken`，`close` 或换房间时取消；
  - 框架没有改：`DanmakuSocketConnection` 的 `connector` 参数本来就允许替换握手。
- **开始时不另发请求**：第一次握手的那次 POST 就是开始的请求（网页也是这样），进房详情已经给了直播号。
- **只上报聊天**（`comment` 事件）。平台的评论流里没有在线人数，也没有醒目留言；礼物只在地址带 `gift=1` 时才推送，本实现不带（见差异 5）。
- **失败详情不带签名**：`dart:io` 握手失败的文字里有整个地址，重连用尽时的 `DanmakuClosed.detail` 会带上它；本平台把其中的 `token`、`n` 的值换成 `…`。

## 协议

取地址：

| 项目 | 内容 |
|---|---|
| 请求 | `POST https://twitcasting.tv/eventpubsuburl.php`，表单 `movie_id=<直播号>`（`application/x-www-form-urlencoded`），请求头用适配器的 `TwitcastingApi.headers`（`Referer`、`Origin`、`User-Agent: Mozilla/5.0`），以 `twitcasting` 的名义发出（走本平台的代理设置），超时同握手（10 s） |
| 回答 | `{"url":"wss://<节点>.twitcasting.tv/event.pubsub/v1/streams/<直播号>/events?token=<签名>&n=<随机>"}`（斜杠转义为 `\/`）。只接受 `wss`、主机是 `twitcasting.tv` 或它的子域名的地址，其余都算没有地址 |
| 签名 | `token` 形如 `<12 位>:::<10 位数字>:<16 位>`，中间的数字是签发时刻加 3601 秒，到时握手回 HTTP 400（实测）；两次请求给的签名不同 |
| 不能用的直播号 | `0`、非数字：HTTP 400、空回答。已结束的直播号照样给地址（不能靠它判断是否在播） |

socket：

| 项目 | 内容 |
|---|---|
| 握手 | 请求头 `Origin: https://twitcasting.tv`、`User-Agent: Mozilla/5.0`（`dart:io` 会把自己的 UA 拼在前面，实测服务端照样接受）。不需要保留大小写，用默认的 `dart:io` 握手，不用 `connectExactWebSocket`。签名不对时握手回 HTTP 400 |
| 加入 | 打开即加入，客户端不发任何消息 |
| 下行 | 文本帧，每帧一个 JSON 数组，一个元素一个事件；10 s 内没有别的事件时服务端发一个空数组 `[]` 保活 |

事件（`type`）：

| 类型 | 字段 | 本实现 | 归档 v4 |
|---|---|---|---|
| `comment` | `id`（数字）、`message`、`createdAt`（毫秒）、`author {id, name, screenName, profileImage, grade}`、`isAnonymous`、`numComments` | 白色聊天：文字是 `message` 去首尾空白，空白或不是字符串时不报；用户名 `author.name`（去首尾空白），为空时用 `screenName`；用户 id `author.id`；消息 id `id`（不加前缀）；时间 `createdAt`，不大于 0、不是整数或超出 `DateTime` 范围时为空。`grade`、`isAnonymous`、头像、`numComments` 不读 | 聊天，id 加前缀 `twitcasting:` |
| `gift` | `id`（字符串）、`message`、`isPaidGift`、`item {name, image, effectCommand, …}`、`sender` | 不报；而且不带 `gift=1` 就收不到 | 礼物（但它的地址也不带 `gift=1`，实际收不到） |
| `update_comment`、`pin_message`、`unpin_message`、`poll_status_update`、`raid`、`pin_talk_theme`、`unpin_talk_theme`、`call_*`、`joint_*` 和未知类型 | — | 不报 | 不报 |
| `[]` | — | 保活，不报；和任何帧一样重置无消息计时 | 同 |

帧不是 JSON 时丢掉这一帧；数组里不是对象的元素跳过；单独一个事件对象（不在数组里）按一个元素的数组读（同 v4，服务端没发过）；二进制帧按 UTF-8 解码（服务端没发过）。

在线人数：评论流里没有。网页的人数来自另一个要页面令牌的状态接口（`/movies/<直播号>/status/…?token=…`，定时拉取），列表接口本来就给 `current_viewer_count`（`audience.dart` 里 TwitCasting 是 `roomList`）。接入后来源没有变，`audience.dart` 不用改。

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 网页播放器 | 依据 |
|---|---|---|---|---|
| 取地址的时机 | 每次握手前（第一次和每次重连） | 每次开始一次；重连用同一个地址（只在“被拒”后重取，而这个平台从不报被拒） | 每次（重新）连接前 | 签名约一小时过期（实测）；差异 1 |
| 取地址的请求 | 表单只有 `movie_id` | 同 | `FormData`，另有 `__n`（`Date.now()`，防缓存）；口令直播带 `password` | 录制的请求就是只有 `movie_id`，实测可用 |
| 地址后缀 | 不加 | 不加 | 加 `gift=1` | 差异 5 |
| 握手请求头 | `Origin`、`User-Agent: Mozilla/5.0` | `Origin`、Chrome 140 的 UA | 浏览器 | 差异 7；实测 |
| 加入 | 打开即就绪（每次重连都报一次 `DanmakuReady`） | 同 | 打开即开始接收 | — |
| 客户端发送 | 无 | 无 | 无 | — |
| 心跳 | 不发。`heartbeatInterval` 10 s 只是无消息检测的节拍，手动 `heartbeat()` 什么也不发 | 不发，检测节拍 30 s | 不发 | 服务端每 10 s 保活（实测） |
| 无消息超时 | 30 s（10 s 检查一次，所以 30～40 s 内发现） | 90 s（3 × 30 s） | 30 s（`DISCONNECTION_THRESHOLD`，每 30 s 检查一次） | 差异 3 |
| 加入超时 | 无 | 无 | 无 | 打开即加入 |
| 断线重连 | 框架默认：只有一个名义地址，间隔 2、3、4、5、6、6、6、6 s，最多 8 次，收到任何帧清零，一轮只提示一次；每次都重新取地址 | 框架默认，不重新取地址 | 间隔（1～3 s 随机）× 2^次数，连续 3 次失败后改用 HTTP 轮询评论 | 差异 1、4 |
| 开始时取地址失败 | 当作一次握手失败：报 `DanmakuReconnecting`，按退避重试 | 终态 `credentials` | 放弃 socket，改用轮询 | 差异 2 |
| 重连后的补漏 | 不补；靠消息 id 去重（T06a.1 的闸门，10 分钟） | 不补 | 请求 `eventpolling.php`（要页面给的令牌）补拉断线期间的事件；按最近 400 个 id 去重 | 不补的原因见“与网页播放器的差异” |
| 参数不对 | 直播号不大于 0：`DanmakuClosed(connectionFailed, 'No broadcast')`，不发请求 | 终态 `credentials` | — | — |
| 关播、重新开播 | 连接照旧保持（只剩保活）；新的一场要重新进房拿新的直播号 | 同 | 页面自己轮询最新一场 | 放到 M13 |

## 网页播放器

`PlayerPage2.js` 里与评论有关的部分（压缩后的类名不固定，按作用描述）：

- 取地址：`POST ${baseUrl}eventpubsuburl.php`，`FormData` 有 `movie_id`、`__n`，登录或口令直播另有 `password`（或推流工具的 `user_id`、`key`）；状态码不是 200 就失败；拿到的地址追加 `gift=1`。
- 连接的状态机：初始 → 取地址 → 连接中 → 接收中；断开或出错进入重连，等（1000 + 2000 × 随机数）× 2^次数 毫秒后**重新取地址**；次数到 3 就报错，改用 HTTP 轮询评论（非推流者）。接收中每 30 s 检查一次，30 s 没有收到任何消息就重连；打开后次数清零。
- 收到的数组先按事件 `id` 去重（最近 400 个），再按 `type` 分发：`comment`（评论和评论数）、`update_comment`、`gift`、`call_*`、`pin_message`、`unpin_message`、`poll_status_update`、`raid`、`pin_talk_theme`、`unpin_talk_theme`、`joint_*`。
- 重连成功后请求 `eventpolling.php?token=<页面令牌>` 补拉一次。
- 观众数不在评论流里，由另一个状态接口定时拉取。

## 登记方式

应用（T07a.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.twitcasting: () => TwitcastingDanmakuConnection(http: twitcastingHttp, proxy: proxyPolicy),
  // …
});
```

- `http`：应用给 `TwitcastingSite` 的同一个 `LiveHttp`。请求以 `twitcasting` 的名义发出，代理和限流按平台 id。
- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `twitcasting` 选 socket 的路由，和接口请求用同一份设置。
- 不需要 Cookie：全程匿名，v3 也没有 TwitCasting 的 Cookie 设置。
- `connector`、`policy` 只给测试用，应用不传。默认握手是 `dart:io`，不需要 `connectExactWebSocket`。
- 参数来自 `getRoomDetail`（和录制详情）；未开播的房间没有参数，按 T06a.1 不连接。

## 与归档 v4 的对照

- 解码的对照：`fixtures/twitcasting/danmaku/v4_expected.dart` 把归档 v4 的 `TwitcastingProtocol.socket` 和 `TwitcastingProtocol.decode` 原样搬进一个独立程序，只替换它从别处引用的事件类型（`DanmakuChat`、`DanmakuGift`）和 `DecodeContext`。它读录下的 `eventpubsuburl.php` 回答和每个推送帧，写下 socket 地址和每帧解出的事件（投影）。运行：在仓库根目录 `dart run fixtures/twitcasting/danmaku/v4_expected.dart`，结果在 `S08-live/expected.json`，`generator` 字段写明来源。
- 测试用同一份录制跑新代码：

| 对照 | 结果 |
|---|---|
| `eventpubsuburl.php` 的回答 | 解出的地址与 v4 相同，也等于 `meta.json` 记下的握手地址 |
| 13 个推送帧 | 逐帧一致：12 条聊天（消息 id、用户 id、用户名、文字、时间），2 个保活没有消息。唯一的差别是 v4 的 id 带 `twitcasting:` 前缀（差异 6），比较时给新代码的 id 加上 |
| 用连接重放录制 | 1 次 POST、1 个 socket、就绪 1 次，12 条聊天按顺序上报，客户端没有发过任何帧 |
| 录制的请求（S07-pubsub） | 新代码的请求（方法、地址、表单）与录下的请求匹配（`ReplayHttp`），回答解出录下的地址 |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 每次握手前重新取签名地址 | 签名约一小时后过期（实测：签名里的时刻 = 签发时刻 + 3601 s，放 3540 s 的地址能连、放 3640 s 的握手回 400）。v4 重连时用开始时的地址：开始一小时后再断线，每次重连都握手失败，直到用尽重连次数。网页每次重连也重新取 |
| 2 | 开始时取地址失败不是终态，按握手失败重试 | 和 socket 握手失败一致；一次网络抖动不该让整场直播没有评论。直播号本身不对（0、非数字）进不到这里：参数只在 `movie.id` 大于 0 时才有，否则直接 `connectionFailed` |
| 3 | 无消息 30 s（每 10 s 检查）就换连接 | 服务端每 10 s 保活，30 s 是网页的阈值（连续 3 次保活没到）。v4 是 90 s |
| 4 | 重连按框架默认（最多 8 次），不改成轮询 | 框架的统一做法；网页 3 次失败后改用 HTTP 轮询评论，轮询接口要页面给的令牌，本实现不做 |
| 5 | 不要礼物（地址不加 `gift=1`），也不解码 `gift` 事件 | v3 所有平台都不显示礼物（`LiveMessageType.gift` 注明“not shown yet”），T06a.2～T06a.10 也都不上报。v4 解码 `gift`，但它的地址同样不带 `gift=1`，实测不带时收不到礼物，所以 v4 那段代码实际不会运行。以后要显示礼物（包括带留言的付费礼物 `isPaidGift`）时再加 |
| 6 | 消息 id 不加 `twitcasting:` 前缀 | 和 T06a.2～T06a.10 一致：去重只在一个房间内，前缀没有作用 |
| 7 | 请求和握手都用适配器的请求头（UA `Mozilla/5.0`） | 与 T02c.4 的所有请求一致（v3 的 `playHeaders`）；实测 POST 和握手都接受。v4 用 Chrome 140 的 UA |
| 8 | 用户名为空时用 `screenName` | 网页评论列表同时显示名字和 `screenName`；名字为空时总比空白好。录制和实测里名字都不为空，结果与 v4 相同 |
| 9 | 文字必须是字符串；时间超出 `DateTime` 范围时为空 | v4 把任何值转成文字（数字也会成为评论）；时间超出范围时 `DateTime.fromMillisecondsSinceEpoch` 抛错，整帧丢掉 |
| 10 | socket 地址的主机必须是 `twitcasting.tv` 或它的子域名 | v4 只看是否以 `twitcasting.tv` 结尾，`eviltwitcasting.tv` 也能通过 |
| 11 | 失败详情里去掉签名 | 与 T06a.10 一样，诊断文字不带令牌 |

## 与网页播放器的差异

- 不补拉断线期间的评论（网页用 `eventpolling.php`，要页面给的令牌，需要多请求频道页）；重连后靠消息 id 去重，断线期间的评论会缺。
- 不改用轮询；不加 `gift=1`；表单不带 `__n`（POST 不会被缓存，录制和实测都不带）。
- 退避按框架（见上表），不是网页的随机倍增。

## 实测

2026-09-29（北京时间，UTC 为 9-28 19:00～20:30）只读、匿名、直连，没有登录，没有发言，结果没有存成样本，输出里只看数量和形状，不记用户的值。

- **取地址**：
  - 同一直播号连取两次，签名不同、节点相同；
  - 直播号 `0`、`abc`：HTTP 400、空回答；已结束的直播号（样本里 2026-09-27 那场）仍给地址；
  - 适配器的请求头（UA `Mozilla/5.0`）可以取地址，也可以握手。
- **签名**：`token` 中间的 10 位数字减去当时的 Unix 时间是 3601 s；一个取来后放了 330 s 才用、一个用过一次后 150 s 再用的地址都能连上；把签名改掉，握手回 HTTP 400。
- **过期**：同一时刻取的两个地址，放 3540 s 后握手成功，放 3640 s 后握手回 HTTP 400，和签名里的时刻相符：地址约一小时后失效，重连必须重新取（差异 1）。已经连着的 socket 到时会不会被断开没有验证（要连一个多小时）；两种情况本实现都能处理：不断就一直用，断了就取新地址重连。
- **保活**：没人说话的房间（0 位观众），`[]` 每 10.0 s 一个，130 s 里 13 个；人多的房间只在 10 s 没有事件时才发。
- **事件**：推荐里人最多的房间（约 1100 位观众），两个 socket 同时接 150 s：都收到 63 条评论；带 `gift=1` 的多收到 1 个 `gift`（活动通知，`isPaidGift: false`），不带的没有礼物。评论的字段全都是 `author, createdAt, id, isAnonymous, message, numComments, type`，作者的字段是 `grade, id, name, profileImage, screenName`；另一分钟的 43 条评论里没有 HTML 转义，`id` 都是数字。
- **本实现**：`TwitcastingSite.getRecommendRooms` 取推荐，进人最多的房间（`getRoomDetail` 给出参数），用默认的 `dart:io` 握手和默认的时序连接：1449 ms 就绪（POST 加握手），120 s 里收到 52 条聊天，都有消息 id、时间和用户名，没有重连。

## 样本

- 没有新录样本，`frames.jsonl` 和两个 `meta.json` 没有改动。新加的只有 `S08-live/expected.json`（归档 v4 的解码输出）和生成它的 `v4_expected.dart`，里面只有已脱敏的值。
- 逐个字段检查了 `S08-live` 的 14 行和 `S07-pubsub`：
  - 取地址的回答和握手地址：`token`、`n` 录制时已换成同形的合成值；主机 `202-218-171-231.twitcasting.tv` 是服务端节点，不是调用方地址；
  - 评论：`id`、作者的 `id`、`name`、`screenName`、`profileImage` 录制时已换成同形的合成值（匿名评论的名字是 `观众1`～`观众9`，头像地址连协议名都是随机字母）；`grade`、`isAnonymous`、`numComments`、`createdAt` 和评论文字是公开的直播间内容，保留；
  - `S07-pubsub` 的 Set-Cookie `did`、`hl` 录制时已换掉；
  - 找不到 IPv4 地址、真实头像路径、Cookie。门禁的 `fixture privacy` 通过。
- 频道名、直播号是公开信息，按 T02c.4 的口径保留。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | T07a.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（T06a.1 的原因表） |
| 主播重新开播后换新的直播号 | M13：进房详情（或直播间的定时刷新）给出新的 `movieId` 时重新 `connect`。旧的连接不会自己结束，只剩保活 |
| 口令直播的评论 | M13 决定是否提示。口令直播现在不能播放（T02.U 12-5），网页取地址时会带口令；没有找到口令直播的样本，匿名能否取地址没有验证 |
| 显示礼物（若以后要做） | M13 统一决定；本平台要在地址后加 `gift=1`，再解码 `gift` 事件（`isPaidGift` 和 `message` 可以当作付费留言） |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | T06a 各平台完成后删除 |

## 受阻

没有。

## 测试

`test/sites/twitcasting_test.dart` 24 个用例，`live_danmaku` 共 583 个，连续跑 3 次全部通过：

- 协议 8 个：取地址的请求（方法、表单、请求头、超时、取消、以平台名义）；录下的请求和回答（`ReplayHttp` 匹配 S07-pubsub）；不能用的回答（状态码、非 JSON、没有地址、`ws`/`https`、冒充的主机）；名义地址和直播号的往返、其他地址；签名的去除；一条评论的各字段；评论的边界（空白和非字符串文字、没有作者、名字回退、各种 id、时间的 0、负数、上限和越界）；帧（保活、坏 JSON、非数组、其他事件类型、嵌套数组、字节帧、单个事件）。
- 录制 3 个：取地址的回答与 v4 和 `meta.json` 一致；13 个推送帧与 v4 的冻结输出逐帧一致；用连接重放整份录制。
- 连接 13 个：
  - 默认时序和平台表登记；握手（先 POST、再用签名地址、请求头、代理路由、打开即就绪、聊天）；不论节拍还是手动心跳都不发任何帧；
  - 断线后重新取地址再连、再次就绪；开始时 POST 失败（网络错误、503、没有地址）按握手失败重试后加入；socket 握手失败也重新取地址；连续失败用尽后 `reconnectsExhausted` 且详情里没有签名；连续拿不到地址同样结束；
  - 无消息 30 s 的检测（按比例缩短：有保活时不换，没有时换新地址）；
  - 参数不对直接结束、不发请求；POST 进行中关闭会取消请求、没有 socket 和事件；关闭后没有事件、再次 `connect` 换直播号并取消旧请求；
  - 真实的本地服务器：`IoLiveHttp` 发表单 POST，默认的 `dart:io` 握手（路径和签名、`Origin`、UA），保活和聊天。
