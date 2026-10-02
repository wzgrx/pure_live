# D01.6 弹幕：快手

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/kuaishou.dart`（`KuaishouDanmakuProtocol` 请求和解析、`KuaishouFeedBatch`、`KuaishouFeedRejected`、`KuaishouDanmakuConnection` 轮询连接）
- 参数：`live_core` 的 `KuaishouDanmakuArgs`（E01.5）：本场直播的 `liveStreamId`（每次开播都换）和取房间时生效的 Cookie（用户的，否则游客会话的，否则为空）。未开播的房间没有 `liveStreamId`，也就没有弹幕参数，同 v3。
- 样本：
  - `fixtures/kuaishou/danmaku/S16-live`：真实录制（2026-09-27，主播 `Kslala666`，约 29 s），来自归档。`frames.jsonl` 是 10 次 feed 请求的地址和回答，都来自主地址，每次都是 `result: 1`、`pullCycleSeconds: 3`，人数从 5.6w 降到 5.3w，共 42 条评论，没有别的类型；
  - `fixtures/kuaishou/danmaku/S17-synthetic`：本模块补的合成数据（`cases.json`），38 个回答（多层编码、`data` 外壳、`result` 的各种写法、拉取间隔的限制、人数的各种写法、各类条目、缺字段、消息 id、时间）和 15 段会话（换备用地址、开始时的重试、三次都失败、放弃前的退避、恢复后再次就绪、cursor 的去留、服务端的间隔、Cookie、空的 `liveStreamId`）。编号接在 S16 之后；
  - 两个目录的 `expected.json` 都由 `fixtures/kuaishou/danmaku/legacy_expected.dart` 生成：它把 v3 的 `KuaishouDanmaku` 整个类原样搬进独立程序（仍用 `package:crypto` 算 sha1），只把 `HttpClient.getJson` 换成按脚本回答并记下请求的桩（失败时抛出，和 v3 的客户端一样；正文按 JSON 响应头的做法先解一次），把 dio 的 `CancelToken`、日志换成桩，并在一个把每个计时器记下时长、立即触发的 zone 里跑。每段会话记下 v3 依次做的事：请求（地址、参数、请求头）、等待、`onReady`、消息、`onReconnect` 和 `onClose` 的文字、`start` 怎样结束。运行：`dart run fixtures/kuaishou/danmaku/legacy_expected.dart`（仓库根目录）。
- 参考：
  - v3：`legacy/lib/core/danmaku/kuaishou_danmaku.dart`、`core/site/kuaishou/kuaishou_site.dart`（`getDanmaku` 和三处弹幕参数）、`core/common/http_client.dart`、`common/models/live_room.dart`（`parseAudienceNumber`）、`modules/live_play/controllers/danmaku_controller.dart`（`start` 抛错时的处理），测试 `test/kuaishou_danmaku_test.dart`（4 个用例）；
  - 归档 v4（`archive/v4`，6ba709135）的 `packages/live_danmaku/lib/src/sites/kuaishou.dart`、规格 `spec/sites/kuaishou.md` 第 7 节、回归条目 REG-KUAISHOU-011～014，以及录制工具的快手脱敏规则（`tools/live_cli/lib/src/danmaku/scrub_sites.dart`）；
  - pure_live_TV `e1cca224` 的 `lib/platforms/kuaishou/kuaishou_danmaku.dart`（见“上游核对”）。

## 做法

- **不用 WebSocket**：桌面端的 WebSocket 要浏览器签名（匿名房间页的 `websocketUrls` 是空的），v3 改用移动端网页的评论 feed，匿名、不带 Cookie 也能拿到评论和在线人数（REG-KUAISHOU-011）。所以不用 D01.1 的 WebSocket 运行时，直接继承 `DanmakuConnectionBase`：间隔用 `run.delay`，取消挂在 `run.ended` 上（D01.1 已为本平台留好）。
- **请求照 v3**：
  - `GET https://livev.m.chenzhongtech.com/wap/live/feed?liveStreamId=…[&cursor=…]`；主地址拿不到可用的回答（没有响应、状态不是 2xx、正文不是 JSON）就换 `https://m.gifshow.com/wap/live/feed`，参数相同；每次请求都先试主地址；两个都失败时这次请求失败，报备用地址的错误；
  - 请求头：Android 16 上 Chrome 139 的移动端 UA、`Accept: application/json, text/plain, */*`、`Referer: https://livev.m.chenzhongtech.com/`，参数里的 Cookie 去掉首尾空白后不为空才带；
  - 第一次不带 `cursor`，之后带上一次回答的 `cursor`；回答里的 `cursor` 为空时沿用旧的，失败的请求不改它；
  - 请求走注入的 `LiveHttp`（平台 id `kuaishou`，代理路线和限流由应用决定），超时用它的默认值 20 s，和 v3 的客户端一样；
  - 同一时间只有一个请求：上一次结束后才开始等下一次（REG-KUAISHOU-014）。
- **解析照 v3 的 `parseFeedPayload`**（`KuaishouDanmakuProtocol.parse`）：
  - 响应先按 JSON 解一次；得到的是文字就再解，最多 3 次（feed 实际发的是“装着 JSON 的 JSON 字符串”）；外面包着对象 `data` 时取里面的（REG-KUAISHOU-012）；最后不是对象就是 `FormatException`；
  - `result` 不是 1（数字、文字“1”、1.0 都算 1）是 `KuaishouFeedRejected`，这次请求失败，不会显示为已连接，也不换备用地址（REG-KUAISHOU-013）；
  - 拉取间隔 `pullCycleSeconds` 取整，限制在 1～10 s，缺省 3 s；
  - 人数 `currentWatchingCount` 去空白后不为空时，按 `parseAudienceNumber`（`5.6w`、`1.2万`、`1,234`）换成数字，作为 `LiveAudienceUpdate(onlineViewers)`；
  - `liveStreamFeeds` 里只有 `type` 为 `comment`（不分大小写）且 `content` 去首尾空白后不为空的条目是聊天：用户名 `author.userName` 去空白，空的写“快手用户”；用户 id `author.userId`；发送时间 `time`（毫秒）；消息 id 为 `kuaishou:<id>`，没有 `id` 时用 `sha1(time \0 userId \0 content)`；白色。礼物等其他类型不显示；
  - 一次回答报出的顺序：先人数（有的话），再按顺序报评论。
- **连接照 v3**：
  - `connect`：`liveStreamId` 去空白后为空，抛 `FormatException`，不发请求；否则请求第一次回答，失败时等 0.6 s 再试，再失败等 1.4 s 再试，三次都失败就把最后一次的错误抛给调用方；拿到回答就就绪、报出消息，`connect` 在排好下一次请求后完成；
  - 之后：等回答给的间隔再请求；请求失败时连续失败次数加 1，第 1 次报 `DanmakuReconnecting(disconnected)`，分别等 1、2、4、8、8、8、8、8 s 重试，第 9 次失败以 `DanmakuClosed(reconnectsExhausted)` 结束，最后一次的错误作为诊断详情；任何一次成功清零，并且（失败后）再报一次 `DanmakuReady`；
  - 没有心跳（`heartbeatInterval` 为 0，`heartbeat()` 什么也不做），feed 本身就是连通性检查；
  - `close`、再次 `connect`：这次连接的等待立即结束，进行中的请求被取消，晚到的回答丢掉（REG-KUAISHOU-014）。v3 开始阶段两次重试之间的等待（`Future.delayed`）停不下来，只是醒来后发现换了代号就返回；现在直接结束。

## 与 v3 的对照

对照方式：同样的回答分别给新代码和 v3 的代码（`legacy_expected.dart`），回答逐个比较解析结果（cursor、间隔、人数、每条消息的全部字段：类型、用户名、用户 id、文字、颜色、消息 id、发送时间、等级和粉丝牌字段、是否本地、人数的类型和数值）；会话逐项比较整条记录（每次请求的地址、参数和请求头，每次等待的时长，事件和 v3 的提示文字，`connect` 怎样结束），顺序也要相同。

| 样本 | 结果 |
|---|---|
| S16-live 的 10 个回答 | 42 条评论和 10 个人数逐字段一致 |
| S16-live 整段会话 | 一致：11 次请求（地址、`cursor` 的变化、请求头）、10 次 3 s 的等待、1 次就绪、52 条消息，`connect` 在第一次回答后完成；10 次请求的地址也与录制工具当时请求的地址逐字相同 |
| S17 的 36 个回答 | 一致（多层编码、`data` 外壳、`result` 的写法、间隔的限制、人数、条目类型、文字去空白、缺作者、消息 id、各种时间、cursor） |
| S17 时间超出 `DateTime` 范围、时间为无穷大的 2 个回答 | v3 整个回答失败（`RangeError`、`UnsupportedError`）；新代码只跳过那一条，结果等于 v3 解析去掉那一条的回答（差异 2） |
| S17 的 15 段会话 | 一致。其中 4 段以 `connect` 抛错结束，两段（三次都失败、三次被拒）抛出的类型不同（差异 3），测试按对照表换成 v3 的类型名后比较 |

## 审查发现的 v3 问题

位置相对 `legacy/lib/`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | （潜在）一条评论的时间超出 `DateTime` 的范围（绝对值大于 8.64 × 10¹⁵ ms）或是无穷大时，整个回答失败；因为 cursor 没有前进，之后每次重试拿到的都是同一个回答，约 47 s 后弹幕彻底断开 | `core/danmaku/kuaishou_danmaku.dart:275、285、301、138` | 每条评论的换算（`toInt`、`DateTime.fromMillisecondsSinceEpoch`）会抛错，却和整个回答在同一个 `try` 里；cursor 只在解析成功后更新 | 这样的条目只跳过这一条（统一原则“一行坏数据只跳过这一行”）。录制里没有这种值 |
| 2 | 主地址不响应（超时而不是拒绝连接）时，备用地址来不及起作用：一次请求最多等 20 s，第一次拉取要先等主地址超时才试备用地址，而直播间的启动超时也是 20 s，界面会先报“连接超时”并停止 | `core/danmaku/kuaishou_danmaku.dart:217-245`；`core/common/http_client.dart:11-13`；`modules/live_play/controllers/danmaku_controller.dart:162` | 请求超时和启动超时相同 | 保持 v3 的 20 s（改超时会改变慢网络下的行为，不在已批准的升级里）；M13 定启动超时时一并考虑，记在下面“放到其他模块的部分” |

另外核对了样本的隐私：归档录制工具的快手规则已经把每条评论的作者（`userName` 换成“观众N”或同形字母、`userId` 换成同位数的数字、`headurl` 和 `userText` 换成同形值）和评论文字换成了合成值，地址里的 `liveStreamId` 也已替换（`meta.json` 的 `scrubbed` 有记录）。`cursor` 是服务端的翻页标记，不含个人信息。回答里没有进场、榜单或设备字段，所以不需要再补脱敏，`frames.jsonl` 和 `meta.json` 没有改动。

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 回调换成事件；`connect` 只接受 `KuaishouDanmakuArgs`，其他类型抛 `ArgumentError`（v3 把任何值 `toString()` 当成 `liveStreamId`） | D01.1 的统一接口 |
| 2 | 读不了的评论条目（时间超出范围或是无穷大）只跳过这一条 | 问题 1 |
| 3 | 开始失败时抛出的错误有类型：`TransportFailure`、`HttpStatusFailure`（例如 502）、`FormatException`（正文或结构不对）、`KuaishouFeedRejected`（带 `result`）；v3 是 `CoreError`（它的 HTTP 客户端对任何失败的请求都抛这个）、`FormatException`、`StateError` | Q01.1 的类型化错误。v3 的直播间控制器对这些错误只写日志、不提示（只有超时才提示），界面上看不出区别 |
| 4 | 主地址回答了 2xx 但正文不是 JSON 时，一律换备用地址 | v3 由 dio 按响应头决定：声明为 JSON 的，解不开就换备用地址（和现在一样）；声明为别的类型（例如风控页的 `text/html`），正文交给解析，解析失败算这次请求失败，不换备用地址。新代码不看响应头，多一次请求，换来备用地址可能给出的回答 |
| 5 | 最终关闭带上最后一次失败作为诊断详情；原因是 `reconnectsExhausted` | v3 的快手文字是“服务器连接失败：快手弹幕重连超过最大次数”，与 WebSocket 平台的同一种原因（“服务器连接失败重连超过最大次数，与服务器断开连接：…”）措辞不同。M13 按原因给出一种文字 |
| 6 | 失败不写日志 | 包里没有日志设施（D01.1）；诊断信息在事件的 `detail` 和抛出的错误里 |
| 7 | 没有 v3 构造参数 `fetcher`、`minimumPollDelay` | 两者是 v3 测试用的替换点：请求改由注入的 `LiveHttp` 发；最小间隔 1 s 从来用不上（服务端间隔限制在 1～10 s，退避至少 1 s） |
| 8 | `close` 和换房间时，开始阶段的重试等待立即结束 | v3 的 `Future.delayed` 停不下来（最多多等 1.4 s），醒来后不再请求。现在 `connect` 更早完成，界面上看不出区别 |

保持 v3 行为、没有采用归档 v4 做法的地方：

- **被拒的回答（`result` 不是 1）不换备用地址**，也不区分各种 `result`（含义待确认）。归档 v4 对任何失败都换备用地址。
- **开始时三次都失败就抛给调用方**（D01.1 对照表）。归档 v4 改成以“失败”结束。
- **每次请求最多 20 s**。归档 v4 用 10 s（见问题 2）。
- **时间为 0 或负数时仍按 1970 年**，会被 D01.1 的去重闸门当作过期消息丢掉（和 D01.3 斗鱼的 `cst=0` 一样）。归档 v4 把不大于 0 的当作没有时间；录制里没有这种值。
- **每次回答都报一次人数**，即使没有变化。
- **没有名字的评论者叫“快手用户”**。pure_live_TV 换成了多语言键 `danmaku_anonymous_user`，这是界面文字的事，留给 M13。
- **每次从失败中恢复都再报一次 `DanmakuReady`**，一轮连续失败只报一次重连。

## 回归条目的覆盖

归档规格里 E01.5 留给 D01 的四条都有测试：

- 011（改用移动端 feed 轮询）：地址、参数、请求头与 v3 相同，录制整段回放一致；
- 012（1～3 层编码、`data` 外壳）：S17 的一到五层、`data` 外壳和非对象的 `data`，以及移植的 v3 用例；
- 013（`result != 1` 是失败，不能显示为已连接）：S17 的 `result` 各种写法、被拒三次抛出 `KuaishouFeedRejected`、被拒后不就绪、跟随时被拒算一次失败；
- 014（串行轮询、单个计时器、按连接丢弃晚到的回答）：一次只有一个请求和一个等待（会话记录）；开始时的请求被 `close` 取消、`connect` 正常完成、之后没有事件（移植 v3 的用例）；等待中 `close` 后计时器取消、不再请求；换房间后旧房间晚到的回答被丢掉。

## 登记方式

应用（I01.1）建 `DanmakuRegistry` 时：

```dart
SiteIds.kuaishou: () => KuaishouDanmakuConnection(http: liveHttp),
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `http` | 是 | `live_net` 的 `LiveHttp`，用应用交给 `KuaishouSite` 的那一个：请求按平台 id `kuaishou` 取代理路线和限流。v3 的 feed 请求走应用的全局 HTTP 客户端和代理设置 |

不需要单独的 Cookie、账号或设置：Cookie 已在 `KuaishouDanmakuArgs` 里（E01.5 在取房间时放入）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 连接状态的提示文字（`reconnectsExhausted` 的文字见差异 5）；`connect` 抛错时照 v3 只记日志、不提示 | M13（D01.1 的原因表） |
| 启动超时（v3 为 20 s）与每次请求 20 s 的关系（问题 2） | M13 |
| 用弹幕的 `onlineViewers` 更新直播间人数（房间页不给人数，REG-KUAISHOU-016） | M13 |
| “快手用户”的多语言文字 | M13 |
| 快手表情：评论里有 `[主的]` 这类表情代码，v3 打包了 `assets/emo/json/kuaishou.json` 但没读进来（D01.1 已列为升级候选，不在 `docs/specs/UPGRADES.md` 的已批准条目里） | A01.1（需先问用户） |
| 平台表的登记 | I01.1 |

## 上游核对

pure_live_TV `e1cca224` 的快手弹幕与 v3 相同，只把提示文字和“快手用户”换成了多语言键。没有可采用的修复。

## 升级条目

`docs/specs/UPGRADES.md` 里快手没有编号以 `5-` 开头的条目（E06 平台层升级 记录也写明没有），附录的 A-2、A-3 属于 M13，都不涉及弹幕。

## 新增的依赖

`packages/live_danmaku/pubspec.yaml` 加了 `crypto: ^3.0.7`：消息 id 照 v3 用 sha1，和 `live_core` 用的是同一个包、同一个版本（工作区早已锁定 3.0.7，`pubspec.lock` 没有变化），不是新的第三方依赖。

## 测试

`kuaishou_test.dart` 70 个用例，`live_danmaku` 共 284 个，连续跑 3 次全部通过：

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 5 | 地址、请求头（Cookie 去空白、空的不带）、参数；开始重试间隔、退避、放弃次数、缺省间隔、没有心跳；移植 v3 的 2 个用例（两层编码的评论和人数、被拒的回答），人数排在评论前；没有人数时只报评论 |
| 录制（S16）对照 v3 | 2 | 10 个回答逐个对照；整段会话逐项对照，请求地址与录制逐字相同 |
| 合成回答（S17）对照 v3 | 39 | 38 个回答各一个用例（2 个按差异 2 变换），另有一个检查每个都有 v3 输出 |
| 合成会话（S17）对照 v3 | 16 | 15 段会话各一个用例，另有一个检查每段都有 v3 输出 |
| 连接 | 8 | 开始失败时抛出的类型（502、被拒、格式、空的 `liveStreamId`、传输失败）且回到空闲、没有事件；状态随就绪、重连、再次就绪变化，第 9 次失败以 `reconnectsExhausted` 结束并带上详情，共 19 次请求；开始时的请求被 `close` 取消（移植 v3 的用例）；等待中 `close` 后计时器取消、不再请求；换房间后旧房间晚到的回答被丢掉、新房间不带旧 cursor 并带自己的 Cookie；参数类型；平台表登记；本地 HTTP 服务器端到端：录制的回答、503 后换备用地址、线上的请求头和 Cookie、事件与 v3 相同 |
