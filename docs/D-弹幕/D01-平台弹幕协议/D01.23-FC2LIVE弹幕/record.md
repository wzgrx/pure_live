# D01.23 弹幕（新增）：FC2 LIVE

- 日期：2026-09-30
- 目标：`packages/live_danmaku/lib/src/sites/fc2live.dart`
  - `Fc2LiveDanmakuConnection`：连接；
  - `Fc2LiveDanmakuProtocol`：心跳命令、名义地址、帧和评论的解码、用户键、颜色，不做 I/O；
  - `Fc2LiveAudience`：`user_count` 的累加；
  - `Fc2LiveNgList`：网页对评论用的屏蔽表（NG 表）。
- 参数：`live_core` 的 `Fc2LiveDanmakuArgs(频道号)`，E03.13（26-3）已给出：进房和录制详情放在 `LiveRoom.danmakuData`（在播、受限、未开播都给；刷新、卡片不给），不多发请求。本模块没有改参数。
- 升级条目：26-3“评论（弹幕），并用它更新人数”。v3 没有 FC2 评论（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 样本：`fixtures/fc2live/danmaku/S06-live`（归档 v4 的真实录制，2026-09-27 20:01 UTC，频道 29745829，约 114 s，53 行：`memberApi.php`、`getControlServer.php` 两个回答，47 个服务端帧（加入、一帧 30 条历史评论、19 帧共 20 条新评论、18 次人数更新、4 个心跳回答等），4 个客户端心跳）。帧没有改，本模块加上 v4 解码的冻结输出 `expected.json` 和生成它的 `danmaku/v4_expected.dart`，没有新录样本。`control/S04-control`、`S07-control-hd` 是 E03.13 的取流对话，本模块只拿来核对帧的形状。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/fc2live.dart`（`Fc2LiveProtocol`、`Fc2LiveConnector`）和它的运行时 `runtime/socket_connector.dart`；规格 `spec/sites/fc2live.md` 第 6、7 节；
  - 网页客户端：频道页加载的 `https://static-e.live.fc2.com/js/liveView.bundle.js?20260422` 和 `css/pc/livefc2-livePlayer.min.css?20260422`（2026-09-29 下载），见“网页客户端”；
  - E03.13 和它的“升级落地（T02.U）”一节给 D01 的说明（授权、握手、心跳、历史评论、人数）；
  - pure_live_TV `e1cca224`：`lib/platforms/fc2live/fc2_site.dart:42` 仍是 `EmptyDanmaku`，没有可参考的实现；
  - 2026-09-29 的只读实测：匿名、直连，不登录、不发言，见“实测”。

## 做法

- **建在 D01.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`），和 TwitCasting（D01.12）同一类：socket 地址要现取。平台代码只写这几样：
  - `target`：检查频道号，取第一个授权，给出名义地址；
  - `onOpen`：记下新 socket 还没加入；
  - `onData`：`connect_complete` 算加入（`session.ready()`），`comment`、`user_count` 上报，`ng_comment` 更新屏蔽表，`control_disconnection`、`move_server` 换连接；
  - `heartbeatFrame`：网页的心跳命令，编号在一次连接里递增；
  - `onJoinTimeout`：计数后换连接。
  - 换地址、退避、最多 8 次、无消息检测、停止后不再有事件，都由框架和 `LiveSocket` 负责。框架没有改。
- **每次握手都用新授权**：
  - 评论走 E03.13 的媒体控制 socket，地址和会话来自授权（`Fc2LiveSite.controlGrant`：`memberApi.php` 加 `getControlServer.php`）。授权约一分钟后失效，用过的授权再连只会收到 `control_disconnection` 4500（归档规格 §6.2 实测），而 `LiveSocket` 重连时总用同一个地址；
  - 所以交给 `LiveSocket` 的是名义地址 `https://live.fc2.com/api/getControlServer.php?channel_id=<频道号>`，本平台的握手函数（包在 `connector` 外面）每次握手先取授权，再按 `proxy.routeFor('fc2live', grant.socket)` 连 `grant.endpoint`（带 `control_token`），握手请求头用 `grant.handshakeHeaders`（`Origin`、Chrome 140 UA、`Cookie: l_ortkn=<orz_raw>`），默认握手是 `Fc2LiveControl.connect`（`dart:io`，每 15 s 一次 WebSocket ping，E03.13）；
  - 第一个授权在开始时取（就是开始的两个请求），第一次握手直接用它，不重复请求；
  - 一次 `connect` 里的授权请求绑定一个 `CancelToken`，`close` 或换频道时取消。
- **开始时能判断的失败直接结束**：授权请求抛出不可重试的 `SiteError`（频道不存在 `NotFound`、没在播 `StreamUnavailable`、受限 `NeedsLogin` 或带原因的 `StreamUnavailable`、回答读不懂 `ApiChanged`、`RiskControl`），以 `DanmakuClosed(connectionFailed, <错误>)` 结束，不握手；未开播、受限、不存在都只发 `memberApi` 一个请求（E03.13 的 `controlGrant`）。网络失败、限流（可重试的错误）当作第一次握手失败，走框架的退避。之后每次重连取授权失败也都当作握手失败——主播短暂断流时 `memberApi` 会说未开播，退避期间（约 38 s）恢复就能接着收评论，真的下播就在 8 次后以 `reconnectsExhausted` 结束。
- **上报聊天和人数**：
  - 聊天：`comment` 里的评论，丢掉加入时重推的历史评论（`history: 1`，30 条）和网页屏蔽表命中的评论；系统评论（打赏、礼物、进出场）不报；
  - 人数：`user_count` 只带变化的字段，保留上一次的值，电脑加手机：在线 `pc_user_count + mobile_user_count` 报 `onlineViewers`，累计 `pc_total_count + mobile_total_count` 报 `totalViewers`，和变化前不同才报（网页的 `setUserCount`）；
  - 平台没有醒目留言、付费留言：付费的“チップ”（打赏积分）是系统评论，只有“某人打赏了多少积分”，没有观众写的文字，和礼物一样不报（见差异 8）。
- **在线人数的来源不变**：目录和详情本来就给 `count`、`total`（`audience.dart` 里 FC2 是 `roomList`，有累计），评论流的在线、累计是同一对数（S06：详情 111 / 1220，加入时 84 + 27 / 816 + 404；实测详情 144 对评论流 144）。`audience.dart` 不用改。
- **按网页的屏蔽表过滤**：服务端在加入时推 `ng_comment`（频道和 FC2 的屏蔽词、屏蔽用户，实测 340 条），网页对其他观众的评论先查表，命中就不显示。本实现照网页对“不是主播、没有自己屏蔽表的观众”的规则过滤（见“屏蔽表”）。
- **失败详情不带令牌**：`dart:io` 握手失败的文字里有整个地址（含 `control_token`），重连用尽时的 `DanmakuClosed.detail` 会带上它；本平台把 `control_token`、`l_ortkn` 的值换成 `…`。

## 协议

授权（E03.13，未改）：

| 项目 | 内容 |
|---|---|
| 请求 | `POST https://live.fc2.com/api/memberApi.php`（`channel=1&profile=1&user=1&streamid=<频道号>`），在播才再 `POST /api/getControlServer.php`（`channel_id`、`mode=play`、`channel_version=<memberApi 的 version>`、`client_version=2.1.0\n [1]` 等，逐项同 3.x）。以 `fc2live` 的名义发出，走本平台的代理设置 |
| 回答 | `url`（`wss://<节点>.live.fc2.com/control/channels/<频道号>`）、`control_token`（JWT）、`orz_raw`（握手 Cookie `l_ortkn` 的值），`status` 不为 0 是 `StreamUnavailable` |
| 有效期 | 约一分钟，一个授权只连一次 |

socket：

| 项目 | 内容 |
|---|---|
| 握手 | `<url>?control_token=<令牌>`，请求头 `Origin: https://live.fc2.com`、Chrome 140 UA、`Cookie: l_ortkn=<orz_raw>`；不需要保留大小写，用 `dart:io`（不用 `connectExactWebSocket`） |
| 保活 | WebSocket ping 每 15 s（`Fc2LiveControl.connect`，E03.13 为取流加的） |
| 下行 | 文本帧，每帧一个 JSON 对象 `{"name": …, "arguments": {…}}`；回答另有 `id` |
| 加入 | 服务端先发 `initial_connect`，随后 `connect_complete`（S06 相隔 5 ms），收到后算加入 |
| 心跳 | 客户端发 `{"name":"heartbeat","arguments":{},"id":<n>}`（文本帧），服务端回 `{"name":"_response_","id":<n>,"arguments":{"status":0}}` |

消息（`name`）：

| 名称 | 内容 | 本实现 | 归档 v4 |
|---|---|---|---|
| `connect_complete` | — | 加入：`DanmakuReady`（每个 socket 一次） | 加入 |
| `comment` | `arguments.comments[]`：`user_name`、`comment`、`color`、`size`、`lang`、`timestamp`（毫秒）、`encrypted_user_id`、`orz_token`、`hash`、`anonymous`、`history`，有时 `owner`、`ng_comment_keyword`；系统评论没有 `comment`，有 `system_comment`（`tip`、`gift`、`login`、`logout`、`translate`、`survey`、`link_share`） | 聊天（见下）；历史、系统评论、屏蔽表命中的不报 | 聊天，丢历史 |
| `user_count` | `pc_user_count`、`mobile_user_count`、`pc_total_count`、`mobile_total_count`，只带变化的 | 在线、累计（见上） | 同 |
| `ng_comment` | `admin_ng`、`shared_ng_level`、`ng_comments[]` | 更新屏蔽表 | 不读 |
| `_response_` | 心跳的回答 | `status` 为 0 时清零“服务端要求重连”的计数 | 不读 |
| `control_disconnection` | `code`（4500 授权失效，1000 直播结束，4502/4511 下线，4504 被踢等，见网页客户端） | 换新授权重连（有重连提示） | 换新授权重连 |
| `move_server` | `url` | 立刻、无提示地换新授权重连 | 不读 |
| `initial_connect`、`connect_data`、`video_information`、`point_information`、`media_disconnection` 和未知名称 | — | 不报 | 不报 |

帧不是 JSON 对象、没有 `name`、超过 2 MiB（`Fc2LiveControl.messageLimit`）都丢掉这一帧；二进制帧按 UTF-8 解码（服务端没发过）。

评论解成聊天：

- 文字是 `comment`，照网页的显示去掉 HTML 标签、解码字符引用（`&lt;`、`&amp;`…，`decodeHtmlEntities`）、去首尾空白；不是字符串或解出来是空白就不报；
- 用户名是 `user_name`，同样去标签、解码；评论标了 `anonymous`（网页隐藏这种评论的名字）或名字为空时写平台给匿名评论的 `[anonymous]`；
- 用户 id 是网页的用户键（`decryptUserId`）：`encrypted_user_id` 以 `a` 加一位数字开头、不超过 12 个字符的是 FC2 账号的编号，按那位数字作偏移编码，同一个人每条评论的编码都不同，所以照网页解码成 `id-<n>-<n>…`；其他的（匿名访客的 26 位 id）写 `id_<原值>`；
- 时间是 `timestamp`（毫秒），不大于 0、不是整数或超出 `DateTime` 范围时为空；
- 颜色按名字取网页评论列表的颜色：`red` #e63d37、`pink` #e13396、`orange` #dc7611、`yellow` #e1ac00、`green` #33bd4a、`cyan` #1b94c7、`blue` #4472f3、`purple` #b84ac5；`black`（网页默认）和其他值是白色（弹幕默认）；
- 没有消息 id：`hash` 是发送者的，不是评论的（S06 里同一个 `hash` 出现在 7 条不同的评论上），交给 D01.1 闸门按没有 id 的规则去重；
- `size`、`lang`、`owner`（主播自己的评论）、头像不读。

## 屏蔽表

网页（`setNgCommentList`、`_hasNg`）对一个不是主播、没登录（没有自己的屏蔽表）的观众这样做，本实现（`Fc2LiveNgList`）照做：

- 表项有 `type`：屏蔽词 `channel_keyword`、`admin_keyword`、`keyword`，屏蔽用户 `channel_user`、`admin_user`、`share_low`、`share_high`、`share_hyper`、`user`。`mode` 为 `add` 或没有时按 `ng_comment_id` 加入（id 为 0 或空时单独保存），其他 `mode` 按 id 删除，没有 id 时删掉相同的表项；其他类型不认。
- `admin_ng` 决定 FC2 的表（`admin_*`）用不用；`shared_ng_level` 1 加上共享表 `share_low`，2 再加 `share_high`；`share_hyper`、频道的表和 `keyword`/`user` 总是用。实测匿名观众收到的是 `admin_ng` 1、`shared_ng_level` 2。
- 一条评论命中下面任一条就不显示：
  - 名字（匿名评论不查）或文字含有屏蔽词：都转小写，按网页比较时的写法（去标签、解码后再把 `&`、`<` 转回 `&amp;`、`&lt;`）；
  - 发送者在屏蔽用户里：FC2 账号按解码后的用户键比，其他人按 `orz_token` 比（空值不算）；
  - 主播自己的评论（`owner` 1）只查 `keyword`，频道和 FC2 的表都不管。
- 表在一次连接里一直保留（每个新 socket 加入时服务端会再推一次，按 id 覆盖）。

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 网页 | 依据 |
|---|---|---|---|---|
| 取授权的时机 | 开始时一次（第一次握手用它），之后每次握手前 | 开始时；只在 `control_disconnection` 后重取，其他断线用旧授权重连 | 进房时 | 授权约一分钟失效（规格 §6.2）；差异 1 |
| 开始时取授权失败 | 不可重试的错误：`connectionFailed` 结束；网络、限流：当作握手失败重试 | 全部终态（`offline`、`noRoom`、`credentials`、`grant`） | 显示原因 | 差异 2 |
| 握手请求头 | `Origin`、Chrome 140 UA、`Cookie: l_ortkn` | `Origin`、`Cookie` | 浏览器 | 与 E03.13 的控制连接相同 |
| 加入 | 收到 `connect_complete`；每次重连都再报一次 `DanmakuReady` | 同 | 同 | — |
| 加入超时 | 8 s，超时换新授权重连 | 8 s | 无 | 同 v4；S06 里 5 ms 就到 |
| 心跳 | 从 socket 打开起每 30 s 发一次文本帧，编号在一次连接里从 1 递增（跨 socket 不重置）；手动 `heartbeat()` 立即发一次 | 加入时立刻发一次，之后每 30 s，二进制帧 | 从打开起每 30 s（`setInterval`），编号整页递增，10 s 没回答只记日志 | 网页；差异 7 |
| WebSocket ping | 每 15 s | 无 | 浏览器自己的 | E03.13 的控制连接（3.x） |
| 无消息超时 | 90 s（每 30 s 检查一次，所以 90～120 s 内发现） | 90 s | 无 | 框架默认；每 30 s 至少有心跳回答 |
| 断线重连 | 框架默认：一个名义地址，间隔 2、3、4、5、6、6、6、6 s，最多 8 次，一轮只提示一次；每次新授权 | 框架（v4 的运行时） | 不自动重连，按关闭码显示“配信終了”、错误码等 | 框架的统一做法 |
| `control_disconnection` | 换新授权重连，有提示 | 同（每次开始最多 50 次） | 记下关闭码，由关闭时显示 | 差异 10 |
| `move_server` | 立刻无提示地换新授权重连 | 不处理 | 等挂起的请求结束后连 `url` | 差异 9 |
| 服务端要求的重连连环发生 | `control_disconnection`、`move_server`、加入超时累计超过 8 次（中间没有心跳回答）就以 `reconnectsExhausted` 结束；一次心跳回答清零 | 每次开始最多 50 次 | — | 这几种情况 socket 已经收到过消息，`LiveSocket` 的失败计数被清零，不加这个计数会无限重连 |
| 参数不对 | 频道号不合规：`connectionFailed`（`Not an FC2 channel`），不发请求 | 终态 | — | — |
| 下播 | socket 被服务端关闭或 `control_disconnection` 1000 后重连，取授权时 `memberApi` 说未开播，按退避重试 8 次后 `reconnectsExhausted` | 终态 `offline` | 显示“配信終了” | 差异 2 |

## 网页客户端

`liveView.bundle.js?20260422` 里与评论有关的部分（压缩后的名字不固定，按作用描述）：

- 控制连接类：`_id` 从 1 开始、整页递增；`get_hls_information`、`heartbeat` 等几种命令打开即发，其他命令等 `connect_complete`；`_onopen` 启动每 30 s 的心跳，回答 10 s 不到只记日志；收到 `move_server` 时等挂起的请求结束后连它给的 `url`；`connect_complete` 解开等待。
- 关闭码：`1000` 显示“配信終了”，`4502`、`4511` 显示下线，`4500`、`1001`～`1011`、`4001`、`4114`、`4117`、`4118` 显示“错误（码）”，`4101`、`4105`、`4109`～`4111` 是付费，`4503`、`4504`、`4515` 是人数限制或被踢；`control_disconnection` 的 `code` 用来补 1005。网页自己不重连。
- 评论（`setComment`）：名字、文字先 `_removeTag`（按 HTML 取纯文字，再把 `&`、`<` 转义），显示时把 `&lt;`、`&amp;` 转回；`encrypted_user_id` 经 `decryptUserId` 成用户键；`anonymous` 或名字为空时名字换成“匿名”；有 `comment` 的是评论，有 `system_comment` 的是系统消息（`tip` 打赏积分、`gift` 礼物、`login`/`logout` 只给主播看、`translate`、`survey`、`link_share`）；历史评论（`history` 1）只进评论列表，不上画面；屏蔽表命中的评论隐藏。
- 人数（`setUserCount`）：电脑、手机分别保留上一次的值，在线是两者之和；累计同样。
- 颜色：评论列表按颜色名加 CSS 类（颜色值见上），画面上的弹幕不带颜色。
- 屏蔽表：见上一节。`connect_complete` 后登录用户另外请求自己的表（`get_user_ng_comment`），匿名观众没有。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.fc2Live: () => Fc2LiveDanmakuConnection(http: fc2Http, proxy: proxyPolicy),
  // …
});
```

- `http`：应用给 `Fc2LiveSite` 的同一个 `LiveHttp`。授权请求以 `fc2live` 的名义发出，代理和限流按平台 id。连接内部用它建一个只取授权的 `Fc2LiveSite`。
- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `fc2live` 和授权给的 socket 地址选路由，和接口请求同一个出口（REG-NET-005）。
- 不需要 Cookie：全程匿名，v3 也没有 FC2 的 Cookie 设置。
- `connector`、`policy` 只给测试用，应用不传。默认握手是 `Fc2LiveControl.connect`，不需要 `connectExactWebSocket`。
- 参数来自 `getRoomDetail`（和录制详情），未开播、受限的频道也有参数：连接会用一个 `memberApi` 请求判断后以 `connectionFailed` 结束。

## 与归档 v4 的对照

- 解码的对照：`fixtures/fc2live/danmaku/v4_expected.dart` 把归档 v4 的 `Fc2LiveProtocol`（`colors`、`command`、`decode` 和它们用到的私有函数）原样搬进一个独立程序，只替换它从别处引用的事件类型（`DanmakuChat`、`DanmakuOnline`、`AudienceKind`）、`DanmakuColors` 和 `DecodeContext`；`headers` 要 v4 的授权类型，没搬。它写下 v4 的 1～4 号心跳命令，再用一份人数表读完录制里每个服务端帧，写下每帧的事件（投影）和加入、被拒的标记。运行：在仓库根目录 `dart run fixtures/fc2live/danmaku/v4_expected.dart`，结果在 `S06-live/expected.json`，`generator` 字段写明来源。
- 测试用同一份录制跑新代码：

| 对照 | 结果 |
|---|---|
| 授权和握手 | 录下的两个回答经 `Fc2LiveSite.controlGrant` 得到的地址正是 `meta.json` 记下的握手地址；两个请求的表单与 E03.13 相同；握手 Cookie 是回答里的 `orz_raw`（录制时记为 `<redacted>`） |
| 47 个服务端帧 | 逐帧一致：第 4 行加入，第 10 行 30 条历史评论都不报，20 条聊天（用户名、文字、时间、颜色），27 个人数（在线、累计的值和顺序）。差别都是有意的：消息 id 为空（v4 `fc2live:<hash>`，差异 3）、用户 id 是网页的用户键（比较时把 v4 的原值换成键，差异 4）；录制里的颜色都是 `black`，两边都是白色 |
| 客户端帧 | 4 个心跳与 v4 的命令、录制里发出的帧文字相同（v4 发二进制，这里发文本，差异 7） |
| 用连接重放录制 | 2 个请求、1 个 socket，`connect_complete` 时就绪一次，没有重连；聊天和人数按顺序与上面相同；在录制发心跳的位置手动发心跳，发出的帧就是录下的 4 帧 |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 每次握手都用新授权 | v4 只在收到 `control_disconnection` 后重取；socket 普通断线后它用旧授权重连，授权超过一分钟就必然先吃一次 4500 再重取，多一次失败和提示 |
| 2 | 开始时只有不可重试的失败才结束（原因都是 `connectionFailed`）；网络、限流按握手失败重试；连上之后取授权失败一律按握手失败重试 | 一次网络抖动不该让整场直播没有评论（同 D01.12）；主播短暂断流时 `memberApi` 会暂时说未开播，v4 这时直接终态，这里退避期间恢复就能接上 |
| 3 | 消息 id 为空 | **v4 的 bug**：它用 `fc2live:<hash>` 当消息 id，而 `hash` 是发送者的（S06 里一人 7 条评论同一个 `hash`，实测也是）。接到 D01.1 的闸门上，同一个人 10 分钟内只有第一条评论能显示 |
| 4 | 用户 id 是网页的用户键 | v4 用 `encrypted_user_id` 原值：FC2 账号的编码每条评论都变（实测 12 个发送者里 3～4 个有多个原值，解码后都是一个键），同一个人会被当成不同的人 |
| 5 | 文字、名字按网页去标签、解码字符引用；`anonymous` 的评论不显示名字；文字、名字只收字符串 | 服务端按 HTML 发文字（网页先按 HTML 取纯文字）；网页隐藏匿名评论的名字，这里也不能显示。v4 把任何值转成文字，原样显示 |
| 6 | 颜色用网页评论列表的颜色值 | 按平台数据；v4 用通用的纯色（红 #ff0000 等）。`black` 两边都是白色 |
| 7 | 心跳是文本帧，从 socket 打开起每 30 s，第一次在 30 s 时 | 照网页；v4 发二进制帧（服务端也收，实测），加入时立刻发一次。实测文本心跳都有回答 |
| 8 | 系统评论（打赏、礼物等）不报 | v3 所有平台都不显示礼物（`LiveMessageType.gift` 注明“not shown yet”），D01.2～D01.16 也都不报；打赏没有观众写的文字，不是醒目留言。v4 同样不报 |
| 9 | 处理 `move_server`：立刻无提示地换新授权重连 | 网页会跟着换节点；v4 不处理，服务端迁移时只能等断线。没有录到这条消息，给的 `url` 是否带令牌不明，所以不直接连它，而是重取授权（`getControlServer` 给出当前的节点） |
| 10 | 服务端要求的重连连环超过 8 次（中间没有心跳回答）就结束 | v4 每次开始最多 50 次；这里与框架的 8 次一致，并在会话正常（心跳有回答）后清零 |
| 11 | 应用屏蔽表 | 网页不显示命中频道或 FC2 屏蔽表的评论（广告、骚扰），v4 没做，会把这些评论显示出来 |
| 12 | 握手带 UA，socket 每 15 s ping | 与 E03.13 的控制连接（3.x）相同；v4 不带 UA |

没有改的：授权的两个请求、握手地址、`connect_complete` 算加入、加入超时 8 s、30 s 心跳间隔、90 s 无消息、丢掉 `history` 1 的历史评论、人数的累加方式和“变了才报”、`control_disconnection` 后重取授权。

## 与网页的差异

- 历史评论：网页放进评论列表（不上画面），这里不报（归档规格和 E03.13 的要求：避免旧弹幕刷屏）。
- `control_disconnection` 和断线：网页不重连，这里按框架退避重连；`move_server` 重取授权而不是连给的地址（差异 9）。
- 匿名的名字写平台给的 `[anonymous]`，网页写“匿名”（界面文字由 M13 决定）。
- 评论带颜色上画面（网页画面上的弹幕不带颜色，只在评论列表里有）。
- 心跳没回答不单独处理，靠 90 s 无消息检测（网页只记日志）。
- 屏蔽表只有平台推的；网页的登录用户还有自己的表，本应用没有登录。评论上偶尔有 `ng_comment_keyword` 字段（实测一条命中屏蔽词的历史评论带 −1），网页不读，这里也不读（表已经能判断）。

## 实测

2026-09-29 只读、匿名、直连，没有登录，没有发言。用一个临时程序（没有提交）走一遍 `Fc2LiveSite.getRecommendRooms` 和 `getRoomDetail`，再用本实现连接，输出里只看数量、字段名和形状，不记用户的值；结果没有存成样本。

- **本实现**：推荐里 56 个房间，52 个不受限，进人最多的（144 人）；约 1.2～1.3 s 就绪（两个请求加握手），95 s 里收到 `initial_connect`、`connect_complete`、`connect_data`、`video_information`、`point_information`、`ng_comment` 各 1 个，`user_count` 9 个，`comment` 8 帧（第一帧是 30 条历史），心跳 3 个（文本帧）都有 `_response_`；上报 7 条聊天、14 个人数（在线 144 与详情相同），没有重连。
- **评论的字段**：31 条评论都有 `user_name`、`timestamp`、`encrypted_user_id`、`orz_token`、`hash`、`comment`、`color`、`size`、`lang`、`anonymous`，30 条有 `history`，1 条有 `ng_comment_keyword`。
- **用户键**：按 `hash` 分出 12 个发送者，3～4 个发送者的 `encrypted_user_id` 不止一个（都是 `a` 加数字开头的 10 位账号编码），解码后每人一个键；账号编码也出现在 `anonymous` 的评论上（12～13 条），5 条署名评论都是账号编码。
- **屏蔽表**：`ng_comment` 带 `admin_ng` 1、`shared_ng_level` 2 和 340 条表项，类型是 `admin_keyword`、`admin_user`、`share_low`、`share_high`、`share_hyper`、`channel_user`、`channel_keyword`，字段是 `mode`、`ng_keyword`、`type`、`ng_encrypted_user_id`、`ng_orz_token`、`ng_comment_id`。本实现的表挡下 31 条里的 1 条（一条历史评论），正是服务端标了 `ng_comment_keyword` 的那条。

## 样本

- 没有新录样本，`frames.jsonl` 和 `meta.json` 没有改动。新加的只有 `S06-live/expected.json`（归档 v4 的解码输出）和生成它的 `v4_expected.dart`，里面只有已脱敏的值。
- 逐个字段检查了 `S06-live` 的 53 行：
  - 授权回答的 `control_token`、`orz`、`orz_raw` 和握手地址里的令牌录制时已换成同形的合成值，握手 Cookie 记为 `<redacted>`；节点主机 `us-west-1-media-worker1083.live.fc2.com` 是服务端，不是调用方地址；
  - `memberApi` 回答里 `user_data` 是匿名访客（`userid` 0），没有出口地址、访客编号；主播的频道号、名字、FC2 编号是公开信息，按 E03.13 的口径保留；
  - 评论的 `encrypted_user_id`、`orz_token`、`hash` 录制时已换成同形的合成值（`meta.json` 的 `person`），名字都是 `[anonymous]`；原来的账号编码被换过之后不再以 `a` 加数字开头，所以样本里解不出任何账号编号；
  - 客户端帧（`b64`）只有 4 个心跳命令；服务端没有回显调用方地址的消息。门禁的 `fixture privacy` 通过。

## 房间公告（`fc2live_chat_notice`）

评论接上后，3.x 给普通房间的公告“FC2 远端聊天尚待接入；媒体控制 WebSocket 由播放或录制独占，并保持到原生输入完整释放。”不对了：前半句已经不成立，后半句是开发说明，对观众没用。按 UPGRADES“说明文字”的原则（公告说人话，没有要说的就不显示），`live_core` 里这样改（主会话 2026-09-30 追加的要求）：

- `Fc2LiveApi.notice` 对不受限、不是成人内容的房间返回 null（原来是这条公告）；受限说明、成人说明不变。`noticeText` 去掉 `fc2live_chat_notice`，3.x 的原文留成 `Fc2LiveApi.legacyChatNotice`，给对照测试和 J02.1 用；
- 对照测试：v3 冻结输出里这些房间的 `notice` 列为有意差异（D01.23），并断言 v3 那边正是 `legacyChatNotice`、新代码为空（S01 的全部卡片和切片、S02 在播的四种深度和两个精确查找）；S02 未开播的投影改为 `notice: null`；
- 顺带把 `Fc2LiveDanmakuArgs`、`Fc2LiveSite` 文档注释里的“D01”写成 `live_danmaku` 的 `Fc2LiveDanmakuConnection`（D01.23）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（D01.1 的原因表） |
| 匿名评论的名字 `[anonymous]` 显示成界面语言的“匿名” | M13（也可以照网页不显示名字） |
| 用户 id 只用来区分发送者，不要显示：匿名评论的键也可能是解码出的 FC2 账号编号 | M13 |
| FC2 公告：普通房间不再有公告；界面按 `Fc2LiveRoomData` 显示受限、成人说明（E03.13）。**合并时空公告不覆盖存下的**，所以 3.x 存下的关注里的 `legacyChatNotice` 要由 J02.1 迁移时清掉；房间从受限变回普通后，存下的受限说明也会留着，界面不要直接显示存下的 FC2 公告 | J02.1、M13 |
| E03.13“留给其他模块”里 `fc2live_chat_notice` 的文字建议作废：这个键不再使用，不用翻译 | M13 |
| 显示打赏、礼物（若以后要做） | M13 统一决定；本平台要解系统评论 `tip`、`gift`（`tip_amount`、`gift_id`，礼物名要查 `memberApi` 的 `gift_list`） |
| 录制时是否带评论 | H01.1（录制详情也带参数，E03.13） |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | D01 各平台完成后删除 |

## 新增的通用能力、依赖

没有。框架没有改，没有新依赖。`live_core` 只改了本平台的 `fc2live_api.dart`（公告，见上）、`fc2live_site.dart`（文档注释）和 `fc2live_api_test.dart`（对照测试的公告）；授权、控制连接照用 E03.13 公开的 `Fc2LiveSite.controlGrant`、`Fc2LiveGrant`、`Fc2LiveControl.connect`、`Fc2LiveControl.messageLimit`。

## 受阻

没有。

## 测试

`test/sites/fc2live_test.dart` 34 个用例，`live_danmaku` 共 785 个，连续跑 3 次全部通过；直接运行本文件（`tools/timeshift` 的方式）进程正常退出；本文件和 `live_core` 的两个 FC2 测试文件在时钟 +30 天、+1 年、+5 年下都通过（被测代码不拿样本时间和“现在”比较）。`live_core` 的 FC2 用例数不变（76 个，改了公告的断言）。

- 协议 13 个：心跳命令、时序常量、名义地址和频道号的往返、其他地址；令牌和 Cookie 的去除；帧（文本、字节、坏 UTF-8、2 MiB 边界、不是对象、没有名字、参数缺失）；一条评论的各字段；不是聊天的评论（各种 `history` 值、系统评论、空白和非字符串文字）；去标签和解码、匿名名字、比较用的转义；用户键（10 种偏移解码成同一个键、各种不解码的值）；颜色表；时间的边界；人数的累加和“变了才报”；屏蔽表的屏蔽词（频道、FC2 开关、转义、大小写、名字、匿名、主播）、屏蔽用户（解码键、`orz_token`、共享表的级别、删除、按 id 或按值）、没有 id 的表项。
- 录制 4 个：授权回答得到录下的握手地址和请求；47 个服务端帧与 v4 的冻结输出逐帧一致（有意差异按上表换算）；`hash` 属于发送者；用连接重放整份录制。
- 连接 17 个：
  - 默认时序和平台表登记；握手（授权的地址、请求头、按授权地址选路由，`connect_complete` 前不就绪、每个 socket 只就绪一次，历史评论和其他消息不报，只发心跳）；屏蔽表在连接里生效；心跳按间隔发、手动发、编号跨 socket 递增；
  - 开始时未开播、受限、不存在只发 `memberApi` 就结束；授权回答被拒、读不懂、403 也结束；频道号不合规不发请求，参数类型不对抛 `ArgumentError`；第一个授权网络失败时提示、重试后加入；
  - 断线后换新授权重连（新令牌、新 Cookie），人数跨 socket 保留；`control_disconnection` 重连有提示；`move_server` 立刻无提示地换 socket，旧 socket 的消息不再上报；服务端连续要求重连时结束、有心跳回答时继续；加入超时换连接、连续超时结束；握手连续失败后结束且详情不带令牌，每次握手的授权都不同；取第一个授权时关闭会取消请求、没有 socket 和事件；关闭后没有事件，再次 `connect` 换频道；
  - 真实的本地服务器：`IoLiveHttp` 发两个表单 POST，默认握手 `Fc2LiveControl.connect`（路径和令牌、`Origin`、UA、Cookie），服务端推加入、人数、历史和新评论，客户端发心跳、服务端回答；结束时关掉服务端所有升级后的 WebSocket 和服务器。
