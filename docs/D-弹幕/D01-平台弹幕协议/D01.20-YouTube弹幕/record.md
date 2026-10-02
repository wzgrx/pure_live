# D01.20 弹幕（新增）：YouTube

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/youtube.dart`
  - `YouTubeDanmakuConnection`：连接（HTTP 轮询，直接继承 `DanmakuConnectionBase`）；
  - `YouTubeDanmakuProtocol`：地址、请求头、请求体、`next` 和 `get_live_chat` 回答的解析，不做 I/O；
  - `YouTubeChatEntry`（`next` 的解析结果）、`YouTubeChatPoll`（一次 `get_live_chat` 的解析结果）。
- 参数：`live_core` 的 `YouTubeDanmakuArgs(roomId, videoId)`，E03.10（23-3）已给出：
  - `roomId` 是频道号（房间身份），`videoId` 是频道正在播的那一场；
  - 在播的房间（进房、刷新、录制、搜索卡片）放进 `LiveRoom.danmakuData`，不多发请求；不在播的房间没有参数，按 D01.1 不连接；
  - 聊天只按 `videoId` 读，`roomId` 协议用不到（它是 M13 判断“同一个房间”的依据）；
  - 本模块没有改 `live_core` 的平台代码，只在 `audience.dart` 本平台那一项的注释里补了在线人数的新来源（见“在线人数”）。
- 升级条目：23-3“聊天当作弹幕，付费留言按普通聊天显示”。v3 的 YouTube 是 `EmptyDanmaku`，这是新增功能，没有 v3 行为可对照。
- 样本（都在 `fixtures/youtube/danmaku/`）：
  - `S06-live`：归档 v4 的真实录制（2026-09-27，LCS 的直播 `xd_fJRWZuVI`，45 s）：`next` 和 8 次 `get_live_chat`，94 行聊天（第一次回答的历史 73 行，之后 21 行）。本模块只加了冻结输出 `expected.json`，样本没有改；
  - `S07-live-paid`：本模块补录（2026-09-28 22:06 UTC，经代理，“直播”频道页当时人最多的直播：Kontraspor 的 `e3n116VqcrE`，49,142 人在看）：`next` 和 20 次 `get_live_chat`，约 117 s，255 行聊天，其中 6 条 Super Chat（2 条在第一次回答的历史里），另有 105 个占位、3 次删除、投票、置顶条等；
  - `S08-ended`：本模块补录（2026-09-28 22:22 UTC，经代理），直播结束后的回答：S06 那场的 `next`（聊天成了回放 `isReplay`）、用回放续页请求 `get_live_chat`（400）、没有聊天回放的已结束直播的 `next`、用 S06 录下的最后一个续页请求 `get_live_chat`（一个 `reloadContinuationData`，没有动作）和跟着它的请求（没有 `continuationContents`，只有“Chat is disabled for this live stream.”）；
  - `S09-synthetic`：合成数据（`cases.json`，由 `synthetic_cases.py` 生成）：36 个 `get_live_chat` 回答、14 个 `next` 回答、15 段会话，见“测试”；
  - 四个目录的 `expected.json` 都由 `v4_expected.dart` 生成（见“与归档 v4 的对照”）。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/youtube.dart`（`YouTubeChatProtocol`、`YouTubeChatConnector`）和它的 `runtime/base.dart`（`ConnectorBase`）；规格 `spec/sites/youtube.md` 第 7 节（2026-09-28 经代理实测）；
  - pure_live_TV `e1cca224`：`lib/platforms/youtube/youtube_site.dart:39` 仍是 `EmptyDanmaku`，没有可参考的实现；
  - `live_core` 的 `YouTubeApi`（E03.10、E03.10）：`webContext`、`apiUrl`、`apiHeaders`、`isVideoId`；
  - 2026-09-28 22:00～22:40 UTC 的只读实测：匿名、经本机代理 `127.0.0.1:7897`，不登录、不发言，只发 `next`、`get_live_chat`、`updated_metadata`、`browse`、`search` 这些读请求，见“实测”。

## 做法

- **HTTP 轮询，不用 WebSocket**：网页客户端的聊天是 InnerTube 的 `live_chat/get_live_chat` 轮询，另有推送通知告诉它“有新消息了，现在就拉”（续页里的 `invalidationId`，一个 GCM 主题，走另外的推送通道）。推送通道是未公开的协议，归档 v4 没有接，本模块也不接，只轮询。所以和快手（D01.6）一样直接继承 `DanmakuConnectionBase`：间隔用 `run.delay`，取消挂在 `run.ended` 上。框架没有改。
- **请求照适配器**：`POST https://www.youtube.com/youtubei/v1/<端点>?prettyPrint=false`，正文是 `YouTubeApi.webContext`（WEB 客户端上下文）加 `videoId` 或 `continuation`，请求头是 `YouTubeApi.apiHeaders`，走注入的 `LiveHttp`（平台 id `youtube`，代理路线和限流由应用决定）。YouTube 在大陆要走代理，和房间接口用同一条路线。
- **加入**：`next` 取聊天的第一个续页（`conversationBar.liveChatRenderer.continuations[0]`，一个 `reloadContinuationData`，即网页默认的“精选聊天”）和在线人数，再请求第一次 `get_live_chat`。第一次回答是最近的历史（S06 73 行、S07 52 行），不报（同归档 v4）；它回来就算加入，报 `DanmakuReady`，接着报 `next` 里的在线人数。
- **之后**：每次等上一次请求结束，再等回答要求的时间（`timeoutMs`，限制在 1～5 s，没有时 5 s），用上一次回答的续页再请求；报出回答里的聊天行。
- **上报聊天和在线人数**：
  - 文字聊天（`liveChatTextMessageRenderer`）是白色聊天行；
  - 付费留言（Super Chat，`liveChatPaidMessageRenderer`）按普通聊天行显示（升级条目 23-3 的做法），文字前加金额（`purchaseAmountText`，如 `TRY 550.00`，货币和数字之间是不换行空格，原样保留）；没有留言文字的只显示金额；
  - 在线人数：`next` 里在播的 `videoViewCountRenderer`（“49,142 watching now”），加入时报一次 `onlineViewers`；
  - Super Sticker、会员加入和里程碑、赠送会员、欢迎语、占位、替换、删除、投票、置顶条、横幅都不报（见“协议”）。
- **聊天结束**：回答没有续页（直播结束后先回一个 `reloadContinuationData`，跟着它请求就只剩一句“Chat is disabled for this live stream.”），以 `connectionFailed`（说明 `Chat ended: <那句话>`）结束。频道的下一场直播要由房间详情给出新的 `videoId`（M13）。

## 协议

**请求**（两个端点都是 `POST`，JSON 正文，请求头同适配器的 InnerTube 请求）：

| 端点 | 正文 | 用到的回答 |
|---|---|---|
| `youtubei/v1/next` | `{"context": <WEB>, "videoId": "<11 位视频号>"}` | 第一个 `liveChatRenderer`（在 `contents.twoColumnWatchNextResults.conversationBar` 下）：`isReplay`、`continuations[0]` 里第一个带文字 `continuation` 的项；第一个 `isLive` 为真的 `videoViewCountRenderer`：`viewCount` 文字里的数字（同适配器读 `updated_metadata` 的写法） |
| `youtubei/v1/live_chat/get_live_chat` | `{"context": <WEB>, "continuation": "<上一次的续页>"}` | `continuationContents.liveChatContinuation`：`actions`、`continuations[0]`；没有它时是聊天结束，`contents.messageRenderer.text` 是说明 |

回答大小（实测）：`next` 约 0.34～0.56 MB（每次连接一次）；`get_live_chat` 第一次（历史）约 0.1 MB，之后每次 1～40 KB，看聊天多少。

**续页**：`continuations[0]` 里第一个带文字 `continuation` 的项。

| 种类 | 出现在 | `timeoutMs` | 本实现 |
|---|---|---|---|
| `reloadContinuationData` | `next`；直播结束后的回答（S08） | 没有 | 跟着它的回答是“重新开始”的历史，不报（和第一次回答一样）；等 5 s |
| `invalidationContinuationData` | 所有录到的轮询回答 | 10000（网页靠推送，没推送时 10 s 后再拉） | 等 5 s |
| `timedContinuationData` | 录制里没有（合成数据） | 回答给的 | 限制在 1～5 s |
| 其他 | — | 回答给的 | 同上 |

**动作**：

| 动作 / 条目 | 含义 | 本实现 | 归档 v4 |
|---|---|---|---|
| `addChatItemAction.item.liveChatTextMessageRenderer` | 文字聊天 | 聊天行 | 聊天行 |
| `…liveChatPaidMessageRenderer` | Super Chat | 聊天行，金额在前 | 同 |
| `…liveChatPaidStickerRenderer` | Super Sticker（付费贴图，没有文字） | 不报 | 不报 |
| `…liveChatMembershipItemRenderer`、`…liveChatSponsorshipsGift*Renderer` | 会员加入、里程碑、赠送会员 | 不报 | 不报 |
| `…liveChatViewerEngagementMessageRenderer` | 欢迎语、提示 | 不报 | 不报 |
| `…liveChatPlaceholderItemRenderer` | 占位（“精选聊天”里被隐藏的行） | 不报 | 不报 |
| `replaceChatItemAction` | 替换一行 | 不报 | 不报 |
| `removeChatItemAction`、`removeChatItemByAuthorAction`、`markChatItem…AsDeletedAction` | 删除一行、删除某人的所有行 | 不报（已飞出的弹幕收不回来） | 不报 |
| `addLiveChatTickerItemAction`、`updateLiveChatPollAction`、`showLiveChatActionPanelAction`、`addBannerToLiveChatCommand`、`liveChatReportModerationStateCommand` | 置顶条、投票、面板、横幅、审核状态 | 不报 | 不报 |

占位和替换的实测：“精选聊天”里占位很多（S07 105 个、另一场 150 s 60 个），录到的时间里没有一个被替换出来；S06 唯一一次 `replaceChatItemAction` 替换的是一行已经显示过、内容完全相同的聊天。所以不报替换不会漏行（同 v4）。

**聊天行的字段**：

| `LiveMessage` | 取值 | 与归档 v4 |
|---|---|---|
| 类型、颜色 | 聊天、白色（付费留言也是） | 同 |
| 文本 | `message.runs` 依次拼起来再去首尾空白：文字原样；标准 emoji 写成字符本身（`emojiId`，如 `😂`），没有时用第一个 `shortcuts`；频道自定义表情写成第一个 `shortcuts`（如 `:face-purple-crying:`）。付费留言是“金额 + 空格 + 文本”再去首尾空白。空的整行不报 | v4 的 emoji 一律写 `shortcuts` 的第一个（`:face_with_tears_of_joy:`），见差异 2；金额只读 `simpleText`，见差异 4 |
| 用户名 | `authorName.simpleText`（写成 `runs` 时拼起来），原样 | v4 只读 `simpleText`（差异 4） |
| 用户 id | `authorExternalChannelId`，是文字时才要 | v4 把任何值转成文字（差异 4） |
| 消息 id | `id`，不加前缀 | v4 加 `youtube:`（差异 1） |
| 时间 | `timestampUsec`（微秒，十进制文字或整数），正数且在 `DateTime` 范围内；本地时区（同一时刻） | v4 用 UTC；0 和负数也当时间；超出范围时整个回答抛错（差异 3） |
| 等级、粉丝牌 | 空（`authorBadges` 不读） | 同 |

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 网页客户端 | 依据 |
|---|---|---|---|---|
| 请求头 | `YouTubeApi.apiHeaders`（UA、`accept: application/json`、`accept-language: en-US`、`SOCS=CAI`、`referer`、`origin`）加 JSON 内容类型 | 内容类型、`origin`、`SOCS=CAI`、UA，值相同 | 浏览器 | 差异 13；和适配器的 InnerTube 请求一致 |
| 开始前的请求 | 无（参数由进房详情给出） | 无 | 页面先取观看页 | — |
| 参数不对 | `videoId` 去首尾空白后不是 11 位视频号：`connectionFailed`（`No broadcast`），不发请求 | 只检查是否为空（`offline`） | — | 差异 14 |
| 加入 | `next`，再第一次轮询；第一次回答（历史）不报；回来就报 `DanmakuReady`，再报在线人数 | 同，不报在线人数 | 显示历史 | S06、S07；差异 8 |
| 没有聊天 | `next` 没有 `liveChatRenderer`：`connectionFailed`（`No live chat`）；聊天是回放（`isReplay`）：`connectionFailed`（`Chat replay only`）；都不轮询 | 没有时 `offline`；回放时用回放续页请求 `get_live_chat`（实测 400），第三次失败 `failed` | 显示回放或说明 | S08；差异 6 |
| 开始时失败 | `next` 和第一次轮询合计失败 3 次（间隔 2 s，`next` 失败也重试）后 `connectionFailed`，说明是最后一次的错误；开始阶段不报重连 | `next` 失败立即 `failed`；第一次轮询失败报“重连中”，第三次失败 `failed` | — | 差异 9 |
| 第一次回答就没有续页 | `connectionFailed`（`Chat ended…`），不报就绪 | 先加入再 `offline` | — | 差异 10 |
| 轮询间隔 | 上一次请求结束后，等 `timeoutMs`，限制在 1～5 s，没有时 5 s（实测每 5.8～6 s 一次） | 同 | 等推送，没有推送时 `timeoutMs`（10 s） | 规格 §7.4；S06、S07 的时间 |
| 失败重试 | 2 s 后用同一个续页再请求；连续第 1 次失败报 `DanmakuReconnecting(disconnected)`（带错误说明），第 8 次以 `reconnectsExhausted` 结束；失败后成功再报 `DanmakuReady` | 同（状态改回 connected） | — | 规格 §7.5；差异 11 |
| `reload` 续页 | 跟着它的回答是重新开始的历史，不报 | 全部报出 | 重新载入聊天列表 | 差异 7 |
| 聊天结束 | 回答没有续页：报完这次的聊天行，`connectionFailed`（`Chat ended[: 说明]`） | 同（`offline`） | 显示说明 | S08 |
| 心跳 | 没有（`heartbeatInterval` 为 0，`heartbeat()` 什么也不做） | 没有 | — | 轮询本身就是连通检查 |
| 在线人数 | 加入时报一次 `next` 里的人数 | 不报 | 每 5 s 请求一次 `updated_metadata` | 差异 8；候选 2 |
| 请求时限 | 15 s | 15 s（它的请求默认值） | — | — |
| 关闭、换房间 | 进行中的请求被取消，等待立即结束，晚到的回答丢掉 | 同 | — | D01.1 |
| 代理 | 按平台 `youtube` 取路线（`LiveHttp` 里） | 同 | — | — |

同一时间只有一个请求：上一次结束后才开始等下一次。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.youtube: () => YouTubeDanmakuConnection(http: liveHttp),
  // …
});
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `http` | 是 | `live_net` 的 `LiveHttp`，用应用交给 `YouTubeSite` 的那一个：请求按平台 id `youtube` 取代理路线和限流 |

不需要 Cookie、账号或设置：聊天全程匿名，适配器也不注入 `CookieVault`。参数来自在播房间的详情；不在播的房间没有参数，按 D01.1 不连接。

## 与归档 v4 的对照

对照方式：

- `fixtures/youtube/danmaku/v4_expected.dart` 把归档 v4 的 `YouTubeChatProtocol`（`headers`、`endpoint`、`nextBody`、`chatBody`、`initialContinuation`、`parse`）和 `YouTubeChatConnector`（设置和 `run` 循环）原样搬进一个独立程序；它依靠的 `ConnectorBase` 换成记录器（每次 `pause` 记下时长后立即返回，`status`、`joined`、`terminal` 都记下），传输换成按脚本回答并记下请求的桩（失败的状态码照 v4 抛 `FormatException('HTTP <状态> <端点>')`，脚本用完时相当于 `close`）。解析抛错记为 `{"throws": 类型}`。
- 它写下：v4 的设置；每个录下的回答的解析结果（`next` 的续页，`get_live_chat` 的聊天行、续页、`timeoutMs`，每行记下来自第几个动作）；录下的会话（S06 接上 S08 的聊天结束、S07 整段、S08 的回放和没有聊天的开始）；S09 的每个回答、`next` 和会话。运行：在仓库根目录 `dart run fixtures/youtube/danmaku/v4_expected.dart`，`generator` 字段写明来源。
- 测试把 v4 的聊天行按差异 1～4 换成新的模型（文本按动作里的 `runs` 用两种规则各拼一次，v4 的必须和 v4 写下的一致），逐个回答、逐段会话比较；会话里 v4 的状态按差异 11 换成新的事件。有意的差异在测试里逐个写明：先断言 v4 的输出，再断言新代码的。

| 对照 | 结果 |
|---|---|
| 地址、请求体、时序设置 | 与 v4 相同：两个端点、`webContext`、最多 8 次失败、间隔 1～5 s、重试 2 s、请求 15 s、加入时第 3 次失败结束；请求头见差异 13 |
| S06 的 9 个回答 | 续页、`timeoutMs` 一致；94 行聊天按差异 1～4 一致（其中 8 行的 emoji 写法不同） |
| S07 的 21 个回答 | 一致；255 行（6 条 Super Chat；19 行的 emoji 写法不同） |
| S08 的 5 个回答 | 一致（400 的回答两边都不解析） |
| S06 接 S08 的会话 | 请求、续页、等待（每次 5 s）、21 行聊天、结束都一致 |
| S07 的会话 | 一致，另有加入后的在线人数 49,142（差异 8）；203 行聊天，其中 4 条 Super Chat |
| S08 的两种开始 | 没有聊天：一致；回放：v4 请求 3 次 `get_live_chat`（400）后结束，新代码直接结束（差异 6） |
| S09 的 36 个回答 | 31 个按差异 1～4 一致，5 个是其他差异（3、4、5、12），见测试 |
| S09 的 14 个 `next` | 13 个一致，1 个是差异 5 |
| S09 的 15 段会话 | 7 段一致（加入后的在线人数除外），8 段是差异 6、7、9、10、14 |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 消息 id 不加 `youtube:` 前缀 | 与 D01.11～D01.14 的新平台一致：去重闸门按房间内的 id 比较 |
| 2 | 标准 emoji 写成字符本身，频道自定义表情写成它的 `:名字:` | 网页上标准 emoji 的替代文字就是字符本身（`emojiId`、`accessibility.label`），v4 写成 `:face_with_tears_of_joy:` 这样的英文代号，弹幕里读不懂；自定义表情的 `emojiId` 是 `UC…/…` 这样的编号，v4 在没有 `shortcuts` 时会把它写出来 |
| 3 | 时间是本地时区的同一时刻；不是正数、超出 `DateTime` 范围时这一行没有时间 | v4 超出范围时整个回答抛错，被当成失败，用同一个续页重试，拿到的还是同一个回答，8 次后断开（统一原则“一行坏数据只跳过这一行”）；0 和负数会被去重闸门当作过期消息丢掉。时区与其他平台一致 |
| 4 | 用户 id、消息 id 只收文字；用户名、金额写成 `runs` 时也读 | v4 会把数字、对象转成文字当用户 id；`runs` 写法 v4 读不出来，金额读不出时整条付费留言（没有留言文字的）会丢 |
| 5 | 回答不是 JSON 对象（数组、字符串）算一次失败 | v4 把 `get_live_chat` 的这种回答当作聊天结束，把 `next` 的当作可以搜索的数据；一个坏回答就永久结束聊天不合理 |
| 6 | `next` 标明聊天是回放（`isReplay`）时直接以 `connectionFailed`（`Chat replay only`）结束 | 直播已结束；v4 拿回放续页请求 `get_live_chat`，实测回 400，要失败 3 次（约 4 s）才结束，结束原因还是“失败” |
| 7 | 跟着 `reloadContinuationData` 的回答当作历史，不报 | 那是重新开始的聊天列表（最近几十行，和已经显示过的重复）；v4 全部报出 |
| 8 | 加入时报 `next` 里的在线人数 | `next` 本来就要请求，人数在里面，不多发请求；按 `audience.dart` 的约定上报 |
| 9 | 开始阶段 `next` 失败也重试，`next` 和第一次轮询合计 3 次；开始阶段不报重连 | v4 的 `next` 一次失败就结束；框架里 `connect` 还没完成时不报重连（同快手） |
| 10 | 第一次回答就没有续页时直接结束，不先报就绪 | 聊天已经结束，报“已连接”再马上断开没有意义 |
| 11 | 结束原因用 D01.1 的类型：v4 的 `offline`、`failed` 是 `connectionFailed`（说明写明哪一种），`maxRetries` 是 `reconnectsExhausted`；失败后恢复报 `DanmakuReady` | D01.1 的统一接口；v4 只是把状态改回 connected，界面上相同 |
| 12 | `timeoutMs` 只读续页那一项的 | v4 读 `continuations[0]` 里任何一项的；只在没有续页（聊天已结束、不会再等）时有区别 |
| 13 | 请求头用适配器的 `apiHeaders`，比 v4 多 `accept`、`accept-language: en-US`、`referer` | 与 E03.10 的 InnerTube 请求一致；实测两种都能用。`accept-language` 固定英文，结束说明是英文 |
| 14 | 参数必须是 11 位视频号，否则 `connectionFailed`（`No broadcast`），不发请求 | v4 只检查是否为空，不合规的号会发一个注定失败的 `next` |

没有改的地方：端点、请求体、默认的“精选聊天”续页、第一次回答不报、间隔 1～5 s（没有时 5 s）、失败重试 2 s、最多 8 次、请求 15 s、一次只有一个请求、只读文字和付费留言两种条目、付费留言的写法（金额、空格、留言）、占位和替换不报。

## 与网页客户端的差异

- 网页拿到的续页是 `invalidationContinuationData`（`timeoutMs` 10 s），靠推送通知知道有新消息；这里不接推送，所以按 v4 缩到最多 5 s 一次，实测延迟（消息时间到收到）中位数 3.4 s、最多 7.7 s。
- 网页进房时显示最近的历史；这里不显示（同 v4，弹幕只飞新的）。
- 网页默认“精选聊天”（Top chat），可以切到“全部消息”（Live chat）；这里只用默认的（候选 1）。
- 网页显示 Super Sticker、会员、赠送会员、投票、置顶条，删除的行会从列表里拿掉；这里只报文字和 Super Chat（候选 3、5）。
- 网页每 5 s 请求一次 `updated_metadata` 更新在线人数；这里只在加入时报一次（候选 2）。

## 实测

2026-09-28 22:00～22:40 UTC，匿名、经本机代理 `127.0.0.1:7897`，只发读请求，没有登录、没有发言。用 Python 小脚本和本实现（`IoLiveHttp`，`youtube` 走代理）。

- **录制**：见“样本”。三场直播的回答大小：`next` 343～562 KB，第一次 `get_live_chat` 103～120 KB，之后 2.6～38 KB；每次轮询间隔 5.8～6 s（5 s 等待加请求时间）；所有轮询回答都是 `invalidationContinuationData`、`timeoutMs` 10000。
- **本实现，在播**（`e3n116VqcrE`，约 4 万人在看，120 s）：2.8 s 就绪，在线人数 40,737；收到 113 行聊天，其中 6 条 Super Chat，没有重复的消息 id；关闭后状态为 `idle`。
- **本实现，已结束**：S06 那场（回放）2.2 s 以 `connectionFailed`（`Chat replay only`）结束；没有回放的已结束直播和普通视频（`dQw4w9WgXcQ`）都是 `No live chat`；都只发了一个 `next`。
- **聊天结束的样子**：直播结束后，用旧续页请求得到一个 `reloadContinuationData`、没有动作；跟着它请求得到没有 `continuationContents` 的回答（`contents.messageRenderer`：“Chat is disabled for this live stream.”）。v4 和本实现都在这里结束。
- **错误的续页**：随便写的续页、回放续页、只有正文没有续页，都回 400 `INVALID_ARGUMENT`。
- **“全部消息”视图**：`next` 的 `viewSelector` 里“精选聊天”和“全部消息”各有一个短续页，单独拿去请求都回 400；它们只是网页切换视图时和当前续页一起用的，要切换就得改写默认续页里的一个字段（未公开的格式），没有做（候选 1）。
- **`updated_metadata`**：第一次约 157 KB（Lofi Girl，大半是周边商品），之后用它给的续页每 5 s 一次，每次约 8 KB，只有在线人数。

## 样本

- **S06-live**：归档的录制，没有改。检查过：作者名、频道号是归档录制工具换过的化名；续页令牌解开后只有主播的频道号和视频号；没有 IPv4 地址、Cookie、访客编号（`responseContext` 没有录）。
- **S07-live-paid**（新录）：
  - 只保留聊天读的部分：`next` 的 `conversationBar` 和 `videoPrimaryInfoRenderer.viewCount`；`get_live_chat` 的 `continuations` 和 `actions`（`responseContext` 里的访客编号、`frameworkUpdates` 等不要）；
  - 去掉追踪参数、作者头像、右键菜单（它的 `params` 里编码着作者的频道号）、`clientId`、回复和点赞按钮（`params` 里有频道号）、排行徽章；聊天读不到的动作（置顶条、投票、面板）只留类型 `{}`；
  - 每位观众的名字（包括文字里 @ 到的）换成同形的合成名字，频道号换成 `UC` 加 22 位的合成值，同一个人在各帧用同一组值；主播 Kontraspor 的名字和频道号是公开的，保留；
  - 续页令牌里带着 Super Chat 置顶条上观众的频道号（Base64 里的 protobuf），所以整条换成同形同长度的合成值（前 7 个字符和 `%3D` 结尾保留），回答里的续页和下一次请求的续页换成同一个值，链条仍然对得上；
  - 写入前逐个字符串检查（原样、百分号解码、嵌套 Base64 解码后）找不到任何原来的名字、频道号、头像路径和 IPv4 地址，否则拒绝写入；每帧另记下请求（`request`）和状态码。`meta.json` 记着原始回答的 SHA-256 和长度、每条脱敏规则。
- **S08-ended**（新录）：回答里没有观众；续页是真实的（解开后只有主播和视频号），这样第 4 帧的请求就是 S06 最后一帧给的续页，两段样本能接起来测“聊天结束”；`responseContext` 同样没有录。
- **S09-synthetic**：名字、id、令牌、时间都是编造的。
- 门禁的 `fixture privacy` 通过。录制和脱敏用的是 Python 小脚本（只读请求；逐层解码、替换、核对），没有放进仓库，`meta.json` 的 `tool` 写明了做法。

## 回归条目的覆盖

归档规格没有 REG-YOUTUBE 条目。§10“踩过的坑”三条都属于平台层（E03.10）；与聊天有关的只有“接口和媒体走同一出口”：聊天请求也以 `youtube` 的名义走同一条代理路线。

## 受阻

没有。没能验证的：

- `timedContinuationData`：录制里没出现（都是 `invalidationContinuationData`），只用合成数据测过。
- Super Sticker、会员、赠送会员：只在另一场的录制里见过会员加入，没有放进样本；它们都不报，合成数据覆盖了“不报”。
- 长时间轮询是否被限流：实测最长一次 150 s（约 26 次请求），没有遇到 429；遇到时按失败重试，8 次后结束。

## 后续升级候选（由用户决定）

| # | 内容 | 现状 | 依据 |
|---|---|---|---|
| 1 | 用“全部消息”（Live chat）代替“精选聊天”（Top chat） | **已做（D01 后续升级（原 M5.F））**：新增设置“显示全部聊天”，默认关（见文末）。原现状：精选聊天：网页和 v4 的默认，垃圾消息少，但会隐藏一部分（S07 两分钟 105 个占位） | 要改写续页令牌的一个字段（未公开格式），`viewSelector` 的短续页单独用回 400（见“实测”） |
| 2 | 在线人数随直播更新：每 5 s（或更慢）请求 `updated_metadata` | **已做（D01 后续升级（原 M5.F））**：每 30 s 一次。原现状：只在加入时报一次 | 网页的做法；之后每次约 8 KB |
| 3 | Super Chat 显示为醒目留言（带金额、颜色、显示时长），Super Sticker、会员、赠送会员显示为提示 | **已做（D01 后续升级（原 M5.F））**。原现状：Super Chat 是普通聊天行，其余不显示（升级条目 23-3 的做法） | 金额是各国货币，醒目留言模型的价格是整数，要先定换算和排序；回答里有颜色（`headerBackgroundColor` 等） |
| 4 | 频道自定义表情显示图片 | 放 A01.1（附录 B-13 的决定），仍显示 `:名字:` | 条目里有图片地址（`yt3.ggpht.com`），属于 A01.1 的表情 |
| 5 | 删除的消息从弹幕列表里拿掉 | **已做（D01 后续升级（原 M5.F））**：删除动作报为撤回。原现状：不处理 | `removeChatItemAction` 给出消息 id，界面在 M13 |

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字；`connectionFailed` 的几种说明（`No broadcast`、`No live chat`、`Chat replay only`、`Chat ended…`） | M13（D01.1 的原因表） |
| 聊天结束后跟到频道的下一场：刷新房间详情，`videoId` 变了就重新 `connect` | M13 |
| 房间公告 `youtube_chat_notice`（3.x：“远端聊天尚待接入……”）和 E03.10 建议的目录说明里“暂不支持聊天”一句，接入后都要改写 | 公告已在平台层改好：`YouTubeApi.chatNotice` 去掉“远端聊天尚待接入”，只说明在线人数的来源；3.x 原文留作 `legacyChatNotice` 给对照测试和 J02.1 迁移。目录说明和翻译在 M13 |
| 进房详情的在线人数和弹幕加入时报的人数不同时显示哪个 | M13（其他平台也是后到的覆盖先到的） |
| 上面的候选 | A01.1、M13 |
| `live_core` 的 `LiveDanmaku`、`YouTubeSite.getDanmaku()` | D01 各平台完成后删除 |

## 在线人数

`audience.dart` 里 YouTube 仍是 `roomRealtime`（口径是在线人数，不用累计播放量），能力没有变，只在注释里补上了这个来源：`next` 回答里的 `videoViewCountRenderer` 和观看页、`updated_metadata` 的是同一个渲染器，弹幕连接加入时报一次 `LiveAudienceUpdate(onlineViewers)`。

另外注意到：E03.10（23-2）以后，推荐和搜索的卡片也带着“N watching”在线人数，严格说已经是 `roomList`；那属于平台层，本模块没有改这个值，留给 E06 平台层升级 或 M13 核对。

## 新增的通用能力、依赖

没有。框架文件没有改，没有新依赖；只在 `live_danmaku.dart` 里按字母顺序加了一行导出，`live_core` 只改了 `audience.dart` 里 YouTube 那一项的注释。

## 测试

`test/sites/youtube_test.dart` 93 个用例，`live_danmaku` 共 827 个，连续跑 3 次全部通过；直接运行测试文件（`tools/timeshift/run.sh` 的做法）在时钟 +30 天、+5 年下也通过并正常退出（测试不依赖当前时间，样本时间只做对照）。

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 7 | 端点、请求体、时序设置与 v4 相同，请求头是适配器的（差异 13）；间隔的限制；`next` 的续页、回放、在线人数（S06、S07、S08）；Super Chat 的写法和一行的全部字段（S07，金额里的不换行空格）；emoji 的两种写法（合成、S06 的 `👴`）；聊天结束的两个回答（S08）；在线人数消息 |
| 录制对照 v4 | 3 | S06、S07、S08 的每个回答（聊天行按差异 1～4 换算后逐字段一致，行数 94、255、0） |
| 合成回答（S09）对照 v4 | 38 | 36 个回答各一个用例（5 个按差异 3、4、5、12 单独断言），一个检查每个都有 v4 输出，一个检查续页的种类和等待 |
| 合成 `next`（S09）对照 v4 | 16 | 14 个各一个用例（1 个是差异 5），一个检查覆盖，一个检查在线人数和回放 |
| 会话对照 v4 | 21 | S06 接 S08 的聊天结束（请求、续页、等待、21 行、结束说明）；S07（加上在线人数，203 行、4 条 Super Chat）；S08 的回放（差异 6）和没有聊天；15 段合成会话各一个用例（8 段按差异 6、7、9、10、14 写出新代码的整条记录），一个检查覆盖；结束和重连的说明、每个事件后的状态 |
| 连接 | 8 | 没有心跳、平台表登记；参数类型、视频号去空白；请求的方法、地址、请求头、正文、平台 id、15 s、取消令牌；`connect` 在加入后完成、状态和事件的顺序；开始时的请求被 `close` 取消且之后没有事件；等待中 `close` 后计时器取消、不再请求；换一场直播时旧的晚到回答被丢掉；本地 HTTP 服务器端到端（线上的请求头和正文、S07 的回答、中途一次 503 后重连并再次就绪） |

## 后续升级（D01 后续升级（原 M5.F），附录 B-13）

- 日期：2026-09-30
- 条目：附录 B-13（本记录候选 1、2、3、5；候选 4 频道表情图片按决定放 A01.1）。2026-09-30 用户答复“按建议全部处理”。
- 改动：只有 `packages/live_danmaku/lib/src/sites/youtube.dart`、它的测试和 `fixtures/youtube/danmaku/` 下两个新样本。框架、`live_net`、`live_core` 都没有改；改写续页用的是弹幕包里已有的 `src/codec/protobuf.dart`（`ProtoMessage`、`ProtoWriter`，D01.5 加的），没有改它。
- 本节取代前文里与之冲突的说法：“付费留言按普通聊天显示”“删除不报”“在线人数只在加入时报一次”“只用精选聊天”。

### 做法

**1. Super Chat 显示为醒目留言**（`liveChatPaidMessageRenderer` → `LiveMessageType.superChat`，`data` 是 `LiveSuperChatMessage`）

| 字段 | 取值 | 依据 |
|---|---|---|
| `priceText` | `purchaseAmountText` 原文去首尾空白，原币种，不换算（`¥1,563`、`R$100.00`、`TRY 550.00`，货币和数字之间的不换行空格保留） | 网页显示的就是这段文字 |
| `price` | 0 | 聊天条目里没有数字金额：`liveChatPaidMessageRenderer` 只有 `purchaseAmountText`（S07、S10 全部 17 条都是）。网页脚本（`live_chat_polymer.js`，2026-09-30 取的 `d57c41d2` 版）里的 `amountMicros`、`priceMicros`、`purchasePriceMicros` 只出现在购买流程（打赏面板的 `suggestedAmounts`、`startBuyFlowWithTransactionParamAndProductData`），不在收到的聊天里 |
| `message` | 留言的 `runs`，写法同聊天行（emoji 字符、自定义表情 `:名字:`）；只有金额没有留言时为空 | — |
| `userName`、`messageId` | `authorName`、`id` | 同聊天行 |
| `face` | `authorPhoto.thumbnails` 最后一张（最大）的 https 地址，`//` 开头的补 `https:`，其他为空 | 录制样本去掉了头像，只用合成数据测 |
| `backgroundColor`、`backgroundBottomColor` | `headerBackgroundColor`、`bodyBackgroundColor`（ARGB 整数）写成 `#rrggbb`（去掉透明度，`LiveMessageColor.numberToColor`）；不是 32 位整数时为空 | 3.x 的醒目留言卡片上半截（名字、金额）用 `backgroundColor`，下半截（留言）用 `backgroundBottomColor`，正好对应网页的 header 和 body |
| `startTime` | `timestampUsec`；没有时用收到的时间（连接的 `now` 参数，测试里固定） | 任务要求 |
| `endTime` | `startTime` 加网页置顶栏的时长：同一个回答里 `id` 相同的 ticker 条目（`addLiveChatTickerItemAction` 的 `fullDurationSec`）；没有时按 `headerBackgroundColor` 查档位表；两样都没有时 60 s | 见下 |

外层 `LiveMessage` 的 `userName`、`userId`、`message`、`messageId`、`sentAt` 与之一致。金额和留言都为空的不报（同以前的规则）。第一次回答（历史）里的 Super Chat 和聊天行一样不报。

**显示时长**：网页把 Super Chat 按金额分档，置顶在聊天上方的 ticker 里一段时间，这段时间由服务器在 ticker 条目里给出（`fullDurationSec`；`durationSec` 是剩余时间）。录制里每条新 Super Chat 的 ticker 条目都紧跟在它后面、在同一个回答里，所以直接用它；红色一档按金额从 1 h 到 5 h 不等（S10 里 `R$100.00` 3600 s、`¥20,000` 7200 s，原始录制里还有 10800 s），只有 ticker 知道。没有 ticker 条目时按档位（YouTube 帮助中心的 Super Chat 档位表，美元计；颜色和时长都在录制里核对过）：

| 档位（美元） | 颜色（header / body） | 网页置顶 | 本实现 | 录到的 |
|---|---|---|---|---|
| 1–1.99 | 蓝 `#1565c0` / `#1565c0` | 不置顶 | 60 s | 没录到（色值按常用的档位色表，未实测） |
| 2–4.99 | 浅蓝 `#00b8d4` / `#00e5ff` | 不置顶 | 60 s | S10 `¥320`、S07 `TRY 22.00`：没有 ticker 条目 |
| 5–9.99 | 绿 `#00bfa5` / `#1de9b6` | 2 min | 120 s | S10 `¥500` ticker 120 |
| 10–19.99 | 黄 `#ffb300` / `#ffca28` | 5 min | 300 s | S10 `¥1,563` ticker 300 |
| 20–49.99 | 橙 `#e65100` / `#f57c00` | 10 min | 600 s | S10 `$20.00`、`¥3,200` ticker 600 |
| 50–99.99 | 品红 `#c2185b` / `#e91e63` | 30 min | 1800 s | S10 `¥5,000`、`₩50,000` ticker 1800 |
| 100 以上 | 红 `#d00000` / `#e62117` | 1–5 h | 3600 s（有 ticker 时用它） | S10 3600、7200 |

不置顶的两档和不认识的颜色取 60 s（网页没有时长，这是我选的）：醒目留言栏总要显示一会儿才看得到；比最低的置顶档（2 min）短，贵的一档不会比便宜的一档先消失；和哔哩哔哩最低一档（30 元 60 s）相同。

**2. Super Sticker、会员、赠送会员显示为通知**（`LiveMessageType.notice`，`data` 是 `LiveNoticeKind.subscription`）

`message` 是一整句（名字在前），平台原文不翻译；网页上没有现成句子的只有 Super Sticker，用中文把原文连起来。`userName`、`userId`（`authorExternalChannelId`）、`messageId`、`sentAt` 照条目填，方便按人撤回和去重。

| 条目 | `message` | 样本 |
|---|---|---|
| `liveChatMembershipItemRenderer`（新会员） | `名字 headerSubtext`：`@x Welcome to 生贄の祭壇!` | S10 真实 |
| 同上（里程碑） | `名字 headerPrimaryText（headerSubtext）：会员留言`：`@x Member for 65 months（生贄の祭壇）：今年も…` | S10 真实 |
| `liveChatPaidStickerRenderer` | `名字 送出 Super Sticker 金额：贴图说明`（说明是 `sticker.accessibility` 的文字，网页上图片的替代文字）：`@x 送出 Super Sticker ¥3,000：Pear character dancing…` | S10 第一次回答的 ticker 里带着的同一个渲染器（真实），包成聊天条目测 |
| `liveChatSponsorshipsGiftPurchaseAnnouncementRenderer` | `名字 header.liveChatSponsorshipsHeaderRenderer.primaryText`：`@x Sent 50 Korone Ch. 戌神ころね gift memberships` | 同上（ticker 里的真实渲染器，没有自己的 `id`、时间）；带 `id`、时间的聊天条目是合成的，未实测 |
| `liveChatSponsorshipsGiftRedemptionAnnouncementRenderer` | `名字 message`：`@x received a gift membership by @y` | 合成，未实测（结构照常见写法） |

没有文字的（会员条目两个标题都空、赠送条目没有 `header`）不报。名字为空时句子从平台原文开始。Super Sticker 在三种通知里没有更贴切的，按决定归入 `subscription`（和会员同属付费支持）。

**3. 删除的消息撤下**（`LiveMessageType.retraction`，`data` 是 `LiveRetraction`）

网页脚本的 `handleLiveChatAction_`（同上版本）处理四种删除动作：

| 动作 | 网页的处理 | 本实现 | 样本 |
|---|---|---|---|
| `removeChatItemAction`（`targetItemId`） | 从列表里拿掉这一条 | `LiveRetraction.message(targetItemId)` | S07 3 次（真实），2026-09-30 实测 Lofi Girl 3 次 |
| `markChatItemAsDeletedAction`（`targetItemId`、`deletedStateMessage`） | 内容换成“[message deleted]”之类 | 同上 | 合成，未实测 |
| `removeChatItemByAuthorAction`（`externalChannelId`） | 拿掉这个人的所有条目（比较 `authorExternalChannelId`，Super Chat、会员也算） | `LiveRetraction.user(externalChannelId)` | S06 2 次（真实，1 次在历史里） |
| `markChatItemsByAuthorAsDeletedAction`（`externalChannelId`） | 这个人的所有条目标为已删除 | 同上 | 合成，未实测 |

撤回消息自己的 `messageId` 为空（这些动作没有自己的 id），不会和原消息在去重闸门里撞键；目标为空、不是文字的不报。聊天行、醒目留言、通知本来就带着同一套 `messageId`、`userId`，不用补。历史回答里的删除不报（那些行本来就没显示）。`replaceChatItemAction` 仍不读（见“协议”的占位说明）；`clearChatWindowAction` 是网页自己重载列表时的清空，录制里从没出现，不读。

**4. 在线人数每 30 秒更新**（`updated_metadata`）

- 加入后每 30 s 请求一次，报 `LiveAudienceUpdate(onlineViewers)`。第一次按视频号（`{"context", "videoId"}`，适配器 `YouTubeApi.metadataBody` 的写法），之后用上一次回答的续页（`continuation.timedContinuationData.continuation`，`YouTubeApi.continuationBody`）。人数的读法同 `next`：第一个 `isLive` 的 `videoViewCountRenderer` 的数字。
- 网页也是这样：`next` 里的 `updatedMetadataEndpoint` 是 `{videoId, initialDelayMs: 5000, params: "IAE="}`，之后每 5 s 用续页（`timeoutMs` 5000）。实测带不带 `params` 回答一样大，所以不带（和适配器一致）。续页隔 30 s 再用也被接受（S10）。
- 请求失败、回答不是 JSON 对象：不报、不提示重连、不影响聊天，下一轮改回按视频号请求；回答里没有在线人数（直播已结束时是“102,275 views”，`timeoutMs` 20000，S11）：不报，续页照用。聊天结束或 `close` 后不再请求，进行中的请求被取消。
- 大小（实测）：Korone 每次 7.8 KB；Koseki Bijou 每次 19.7 KB；Lofi Girl 第一次（按视频号）182 KB（带周边商品栏），之后 8–16 KB。

**5. 新增设置“显示全部聊天”**（候选 1）

- 参数：`YouTubeDanmakuConnection(http: …, allChat: …)`，默认 `false`（照网页用“精选聊天”）。打开时读网页的“Live chat”视图（全部消息）。
- 做法（照“实测”一节的发现）：续页令牌是 base64url（`=` 写成 `%3D`）的 protobuf，最外层字段 119693434 里的字段 16 的字段 1 是视图：4 是 Top chat，1 是 Live chat。`next` 的 `viewSelector` 里两个短续页只有这一处不同（S06、S10 都是真实的），单独用会被拒（400），所以改写聊天自己的续页（`YouTubeDanmakuProtocol.allChatContinuation`）：只改这个 varint，其他字段原样复制；把 Top chat 的短续页改写后正好得到网页自己的 Live chat 短续页。服务器之后回的续页都带着 1（S10 全部），所以只改写“重新开始”的续页：第一个（`next` 的）和之后的 `reloadContinuationData`。
- 改写不了（不是这种消息，如回放的 `op2w0wR…`；视图不是 4 或 1；字段重复；路径上有定长字段或 group；令牌坏了）：直接用原来的续页，不多发请求。
- 被拒：改写后的请求回 4xx，或回答里没有聊天（没有续页）：马上用原来的续页再请求一次，不算失败、不提示重连，这次连接之后都用精选聊天。原来的续页也没有聊天，才按聊天结束处理。5xx、网络错误、回答不是 JSON 对象：照常算一次失败，2 s 后仍用改写后的续页重试。
- 实测（2026-09-30，本实现，经代理）：Korone（两种视图同时录 150 s，Python 脚本）全部消息 1200 行、精选 778 行；Koseki Bijou 100 s 两种视图都是 93 行；Lofi Girl 120 s 全部消息 109 行、精选 105 行，3 次删除两边相同。改写后的续页一次也没被拒，所以“被拒”的处理只用合成数据测过。
- 设置（留给 J02.1 存储、M13 显示）：建议键名 `youtubeShowAllChat`（布尔，默认 `false`）；界面文字“显示全部聊天”，说明“YouTube 默认只显示精选聊天，可能隐藏疑似垃圾消息；打开后显示全部消息”。改了之后下一次连接生效（M13 改设置时重连）。登记改为 `SiteIds.youtube: () => YouTubeDanmakuConnection(http: liveHttp, allChat: settings.youtubeShowAllChat)`。

### 与决定的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 醒目留言的 `price` 一律 0 | 回答里没有数字金额（见上）；排序和换算留给界面按 `priceText` 决定 |
| 2 | 在线人数每次不止 8 KB：7.8–20 KB，按视频号的第一次可能 182 KB | 看频道（周边商品栏、简介长短）；网页第一次也是按视频号，同样大；失败后才会再按视频号请求 |
| 3 | 显示时长优先用 ticker 的 `fullDurationSec`，档位表只在没有 ticker 条目时用 | 红色一档 1–5 h 只有 ticker 知道；两者在录到的档位上一致 |
| 4 | Super Sticker 的通知种类也是 `subscription` | 模型只有 `system`、`subscription`、`raid` 三种，付费贴图和会员同属支持主播 |

### 新样本和脱敏

- **S10-live-all-chat**（2026-09-30 15:12 UTC，经代理，匿名只读）：Korone Ch. 的生日直播 `lNPh7CdwkWk`（约 1.6 万人在看），“Live chat”视图：`next`、第一次 `get_live_chat`（续页是 `next` 的改写）、之后 4 次轮询、2 次 `updated_metadata`（按视频号、按续页，相隔 30 s）。11 条 Super Chat（7 条在第一次回答里）、会员（新会员 1、里程碑 4）、第一次回答的 58 个 ticker 条目（其中 3 个 Super Sticker、1 次赠送 50 份会员）。脱敏同 S07：观众名字（包括文字和 ticker 说明里 @ 到的）换成同长度合成名，频道号换成合成值（主播的公开频道号保留），头像、右键菜单、回复和点赞按钮、徽章、`clientId`、emoji 图片都去掉；第一次回答（历史，不报）的 73 条文字聊天去掉以减小体积；续页原样保留（解开后只有主播频道号、视频号、时间和视图字段）。写入前逐个字符串（原样、百分号解码、嵌套 Base64 解码后）检查找不到任何原名、频道号、头像路径。438 KB。
- **S11-metadata-ended**（2026-09-30 15:29 UTC）：刚结束的直播（Subaru Ch. `n4eqMMG3mYE`）的两次 `updated_metadata`，只留续页和 `updateViewershipAction`（`responseContext` 里的访客编号去掉）。
- 两个样本都没有 v4 的 `expected.json`（v4 没有这些功能；S10 的聊天行和以前走同一段代码，由 S06、S07 的对照覆盖）。门禁的 `fixture privacy` 通过。

### 没能实测的部分

- 蓝色一档（1–1.99 美元）的颜色；赠送会员、领取赠送会员作为聊天条目的写法（录到的是 ticker 里带的购买公告）；`markChatItemAsDeletedAction`、`markChatItemsByAuthorAsDeletedAction`；服务器拒绝改写后的续页；聊天中途收到 `reloadContinuationData` 时改写的效果（用 S06 结束时真实的 reload 续页合成了会话）。

### 新发现（留给用户决定）

- **已做（D01 后续升级（原 M5.F），附录 B-22，见文末）**。进房时网页 ticker 里仍在置顶的 Super Chat（第一次回答的 ticker 条目带着完整渲染器和剩余时间，S10 有 50 条）没有补报到醒目留言栏；照现有规则第一次回答不报。补报的话，进房就能看到还在置顶的醒目留言（像哔哩哔哩进房拉醒目留言板那样）。
- **已做（D01 后续升级（原 M5.F），附录 B-23，见文末）**。录到一种新条目 `giftMessageViewModel`（YouTube 的新礼物，“sent Donut”，Raora Panthera 的直播 5 分钟 3 次），没有读。要上报为礼物（`LiveMessageType.gift`，界面暂不显示）或显示为通知，需要另定（和 B-21 一起）。

### 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 设置“显示全部聊天”的存储和界面 | J02.1、M13 |
| 醒目留言栏、通知行、撤回（从列表里去掉）的显示 | M13 |
| 频道自定义表情显示图片（候选 4） | A01.1 |

### 测试

`test/sites/youtube_test.dart` 从 93 个增加到 124 个，`live_danmaku` 共 1340 个，连续跑 3 次全部通过；直接运行测试文件在时钟 +30 天、+5 年下也通过并正常退出（醒目留言没有平台时间时的“现在”由 `now` 参数固定）。

| 分组 | 用例 | 内容 |
|---|---|---|
| B-13：醒目留言 | 7 | S07 的 6 条（档位时长、一条的全部字段）；S10 的 11 条（时长等于 ticker 的 `fullDurationSec`，浅蓝没有 ticker 为 60 s，颜色）；档位表和不认识的颜色；ticker 条目的边界（先于留言、0、文字、负数、别的 id、空 id）；没有平台时间、颜色越界、头像三种写法、金额写成 `runs` 或不是文字、金额和留言都空；S09 的合成留言；过滤不作用于醒目留言、通知、撤回 |
| B-13：通知 | 4 | S10 的新会员和里程碑（逐字段）；S10 ticker 里的 Super Sticker 和赠送会员；合成的领取赠送、购买赠送和没有文字的条目；S09 的贴图和会员 |
| B-13：撤回 | 4 | S07 按 id、S06 按人；四种动作的顺序、id 缺失或为空或不是文字、`replaceChatItemAction` 和 `clearChatWindowAction` 不读；S09 的删除；去重闸门放过撤回、不和原消息撞键 |
| B-13：在线人数 | 4 | S10、S11 的回答（人数、续页、结束后没有人数、坏回答）；会话里每 30 s 一次、先按视频号再按续页、关闭时取消；失败、坏回答、超时、没有人数都不报也不影响状态，下一轮按视频号；加入前和聊天结束后不请求 |
| B-13：全部聊天 | 13 | 网页两个短续页互为改写；S10 改写结果就是服务器接受的那个、回答都带 1；改写只动一个字节；16 种改写不了的令牌；S10 整段会话的请求和录制一致；默认关；被拒（400）马上退回且之后不再改写；回答没有聊天时退回；5xx 和坏回答照常重试、被拒不算失败；改写不了时只发一次；中途的 reload 续页也改写；等待改写结果时关闭；本地 HTTP 服务器上的 400 退回 |

原有测试的改动（都在测试里注明 B-13）：原“Super Chat 按聊天行显示”的用例换成醒目留言的用例；与 v4 对照时，v4 的付费聊天行对应新代码的醒目留言（金额加留言作为一行比较），撤回和通知 v4 没有，对照时略过、另外断言；S06、S07 会话另外断言撤回；会话里 `updated_metadata` 的请求和 30 s 等待只在专门的用例里记录。

## 后续升级（D01 后续升级（原 M5.F），附录 B-22、B-23）

- 日期：2026-10-01
- 条目：`docs/specs/UPGRADES.md` 附录 B 的 B-22（进房时补上置顶栏里仍在显示的 Super Chat）、B-23（读新礼物 `giftMessageViewModel`，以礼物上报，界面暂不显示），即上一节“新发现”的两条。2026-10-01 用户答复“按建议全部处理”。
- 改动：`packages/live_danmaku/lib/src/sites/youtube.dart`、它的测试、新样本 `fixtures/youtube/danmaku/S12-gifts`；模型 `LiveMessage.replayed` 和去重闸门的两条年龄规则（本任务一起加的，见 D01.1 记录“模型追加”一节末尾）。框架、`live_net` 没有改，`live_core` 本平台的代码没有改；没有新依赖；两条都不需要设置。
- 本节取代前文里与之冲突的说法：“第一次回答不报”（其中仍在置顶的 Super Chat 现在要报）、“`giftMessageViewModel` 没有读”。

### 做法

**B-22：进房时补报仍在置顶的 Super Chat**

- 网页：第一次回答（历史）里带着置顶栏（ticker）的全部条目（`addLiveChatTickerItemAction`）。Super Chat 的条目是 `liveChatTickerPaidMessageItemRenderer`：`id`、`durationSec`、`fullDurationSec`、颜色，和 `showItemEndpoint.showLiveChatItemEndpoint.renderer` 里嵌着的完整 `liveChatPaidMessageRenderer`（点开置顶条时显示的就是它）。S10 第一次回答有 50 条这样的条目（另有 3 个 Super Sticker、4 个会员、1 次赠送会员的条目）。
- 本实现：`YouTubeChatPoll.pinned`：每个 `liveChatTickerPaidMessageItemRenderer`，`durationSec` 是大于 0 的整数、里面嵌着付费留言的，照 B-13 的规则解成醒目留言，标 `replayed: true`；同一 id 只取第一个；按发送时间从早到晚排（时间相同的保持置顶栏里的顺序），和实时收到的顺序一样。连接只报第一次回答（进房）的：顺序是 `DanmakuReady`、`next` 的在线人数、这些醒目留言。之后回答里的置顶条目不报（新的 Super Chat 本来就作为聊天条目来，B-13 用它的 `fullDurationSec` 定时长），reload 之后的历史也不报。
- 字段：id、名字、频道号、留言、`priceText`、`price` 0、颜色、头像都和 B-13 的醒目留言一样取；`startTime`、`sentAt` 是它原来的 `timestampUsec`（没有时用收到回答的时间）；`endTime` 是收到回答的时间加 `durationSec`。
- `durationSec`、`fullDurationSec` 的含义（S10 核实）：`fullDurationSec` 是这一档的置顶总时长（120、300、600、1800、3600、7200、10800 s），`durationSec` 是服务器回答时剩下的秒数：50 条都满足“`fullDurationSec` −（收到时间 − 发送时间）− `durationSec`”在 5.1～6.0 s 之间（第一次回答生成和传回用了几秒，`durationSec` 又是取整的）。网页脚本（`live_chat_polymer.js`，2026-09-30 的 `d57c41d2` 版）：置顶条目的 `dataChanged` 调 `startCountdown(durationSec, fullDurationSec)`，从收到时起倒数 `durationSec` 秒，到 0 就收起，`fullDurationSec` 只用来算进度条的比例；另外只有 `durationSec === fullDurationSec` 的条目（刚来的）才提醒“有新的付费留言”（`maybeAddNewMessageReminder`、按钮的 `startBubble`），进房时的旧条目不提醒。所以结束时间取“收到 + `durationSec`”，和网页置顶条消失的时刻一致。动作外层还有一个文字的 `durationSec`（`"113"`），网页不读，这里也不读。
- 不会重复：消息 id 就是之后正常收到的那一条的 id（ticker 条目的 `id` 和嵌着的 `liveChatPaidMessageRenderer.id` 相同，S10 50 条都相同；第一次回答里同时作为历史条目的 7 条也是同一 id）。去重闸门按 id 只收一次；醒目留言栏（3.x 的 `superChats` 集合）按 `messageId` 判等。
- 去重闸门：这些醒目留言大多早于 45 s（S10 最早的一条是 13 分钟前发的），闸门对 `endTime` 还没到的醒目留言不按年龄丢（D01.1 末节），所以都能显示。过滤链目前只让聊天过闸门，醒目留言本来就直接通过。

**B-23：新礼物 `giftMessageViewModel`**

- 条目（原始录制的 3 条）：`addChatItemAction.item.giftMessageViewModel`：`text.content`（`sent Donut`）、`authorName.content`（`@名字 `，末尾有空格）、`id`、`authorAvatar`、`giftImage.sources`（`//www.gstatic.com/youtube/img/pdg/gift/assets/donut.png=w480-h480` 和 `=w640-h640`）、`giftImageA11yLabel`（`@名字 sent a gift, Donut`）、`rendererContext`（追踪）。没有频道号、时间、价格、数量。网页（同一版脚本的 `yt-gift-message-view-model`）显示头像、名字、`text` 和礼物图，没有别的。
- 本实现：`LiveMessageType.gift`，白色；`userName` 是 `authorName.content`、`message` 是 `text.content`（都去首尾空白），`messageId` 是 `id`；`userId`、`sentAt` 录制里没有，条目带 `authorExternalChannelId`、`timestampUsec` 时照读（写法同聊天行）。`data` 是新的 `YouTubeGift`（照 `BaiduLiveGift` 的写法：不可变、判等、`toString`）：`name`（`text` 去掉开头的 `sent `，请求固定英文；不是这种写法时为空）、`text`、`image`（`giftImage.sources` 最后一个即最大的 https 地址，`//` 开头的补 `https:`，其他为空）。没有 `text` 的不报。第一次回答里的礼物和聊天一样是历史，不报。
- 撤回：礼物条目没有频道号，`removeChatItemByAuthorAction`（按人撤回）对不上它；按 id 的撤回照常对得上。界面暂不显示礼物，没有影响。

### 与决定的差异

| # | 决定 | 本实现 | 原因 |
|---|---|---|---|
| 1 | 进房时补上置顶栏里仍在显示的 Super Chat | 只补 Super Chat；置顶栏里的 Super Sticker、会员、赠送会员不补 | 决定写的是 Super Chat；那三种是通知（B-13），进房时补报已经过去的通知只会刷屏 |
| 2 | 同上 | 只在进房（第一次回答）时补，聊天中途 reload 之后的历史不补 | 录制里 reload 只在聊天结束时出现；中途 reload 的置顶条目几乎都是已经报过的，而闸门只记 10 分钟内的 id |
| 3 | 以礼物上报 | `userId`、`sentAt` 通常为空 | 条目里没有 |

### 新样本和脱敏

- **S12-gifts**：取自 B-13 录制时的原始数据（2026-09-30 15:35 UTC，经代理，匿名只读，不登录、不发言），Raora Panthera Ch. hololive 的直播 `aGHE6jSxncw`（约 3,300 人在看），“Live chat”视图。第一次回答（历史）里有 3 条 `giftMessageViewModel`（Donut、Ramen、Heart），之后 31 次轮询（约 267 s）没有再出现。样本只留这个回答的续页和这 3 条：
  - 去掉 `clickTrackingParams`、`clientId`、`rendererContext`（追踪参数）和送礼人头像 `authorAvatar`；
  - 送礼人名字（`authorName.content`，末尾空格保留；`giftImageA11yLabel` 开头的名字）换成同长度合成名，一人一个；
  - 续页和请求的续页原样保留（解开后只有主播的公开频道号、视频号、时间和视图字段）；礼物图片是平台的公开资源，保留；
  - 脚本写入前逐个字符串（原样、百分号解码、嵌套 Base64 解码后）检查找不到原来的名字和头像路径，否则拒绝写入。`meta.json` 记着原始录制的 SHA-256、长度和每条脱敏规则。门禁的 `fixture privacy` 通过。
- B-22 用 S10 已有的第一次回答（50 条置顶 Super Chat 的真实条目），没有补录。S07 的置顶条目在脱敏时换成了 `{}`，没有可补报的。
- 两者都没有 v4 的 `expected.json`（v4 没有这些功能）。

### 没能实测的部分

- B-22：进房补报的 Super Chat 之后又作为聊天条目收到（同一 id）的情形没有录到（S10 之后的回答里没有这 50 个 id），按 id 去重只用合成数据测；`durationSec` 为 0、负数、文字、缺失，条目里嵌的不是付费留言、没有 id，都是合成数据。
- B-23：礼物出现在之后轮询里的样子没有录到（录到的 3 条都在第一次回答里），用录下的条目放进合成的后续回答测；带频道号、时间的写法是合成的。
- 两条都没有接到真实服务器上用本实现跑，协议和录制逐项对照过。

### 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 礼物的显示（和其他平台的礼物一起定） | M13（附录 B-21） |
| 醒目留言栏：进房补报的和之后同一条按 `messageId` 合并、到 `endTime` 移除 | M13 |
| 过滤链是否让醒目留言也过去重闸门 | M13 |

### 测试

`test/sites/youtube_test.dart` 从 124 个增加到 132 个（B-22 5 个、B-23 3 个），`live_danmaku` 共 1544 个，连续跑 3 次全部通过；本平台测试文件在时钟 +30 天、+1 年、+5 年下直接作为 Dart 程序运行通过并正常退出（收到回答的时间由连接的 `now` 参数和 `chat(now:)` 固定，S10 的取 `meta.json` 的 `capturedAt` 加帧的 `t`）。

| 分组 | 用例 | 内容 |
|---|---|---|
| B-22 | 5 | S10 第一次回答的 50 条：`replayed`、从早到晚、`endTime` 等于收到时间加 `durationSec`、`durationSec` 与 `fullDurationSec` 和发送时间的关系（差 4～7 s）、最早和最晚的两条、最贵的一条（NT$5,633.00，10800 s 档）逐个字段；历史里的 7 条和补报的同一条除结束时间和 `replayed` 外相同，闸门放过 50 条补报的、再来的同 id 不收，S07 没有；哪些置顶条目算（`durationSec` 为 0、负数、文字、缺失，没有嵌入、贴图条目、嵌的是会员、没有金额和留言、重复 id、没有 id 两条、没有时间、按时间排序且同时间保持顺序），同一回答里的 Super Chat 仍按 `fullDurationSec`；连接：加入后在在线人数之后报出，之后的回答和 reload 之后的历史里的置顶条目不报，新的 Super Chat 照常报一次；S10 经连接报出的 50 条都过过滤链和闸门 |
| B-23 | 3 | S12 的 3 条礼物逐个字段（`YouTubeGift` 的名字、文字、图片，判等、`toString`）；字段的取法和坏数据（去空白、名字不是 `sent ` 开头、http 图片、空列表、`giftImage` 不是对象、频道号和时间有时照读、负数时间、名字不是对象、没有文字或文字不是字符串）；经连接：第一次回答里的礼物不报，之后回答里的报为礼物，过滤链放过，闸门按 id 去重 |

原有测试的改动 4 处，都在测试里注明 B-22 或 B-23：S10 每 30 s 取在线人数的会话（加入后多了 50 条补报的醒目留言）、S10 打开“显示全部聊天”的会话（醒目留言从 4 条变成 4 + 50 条）、本地 HTTP 服务器上的 400 退回（同样多了补报的醒目留言）、合成的通知用例里的 `giftMessageViewModel`（原来不读，现在是礼物）；测试里消息的投影在 `replayed` 为真时多一个 `replayed` 字段。

另做了变异检查，每一种都有用例失败：补报的不报、结束时间改按 `fullDurationSec`、不标 `replayed`、不排序、`durationSec` 为 0 也算、同 id 不去重、不读礼物、礼物名字不去掉 `sent `。
