# T06a.4 弹幕：虎牙

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/huya.dart`（`HuyaDanmakuProtocol` 编解码、`HuyaDanmakuConnection` 连接和头条留言的后台补拉）
- 参数：`live_core` 的 `HuyaDanmakuArgs`（T02a.3）：主播 UID、topSid、subSid，另带 `superChats`，由 `HuyaSite` 用自己的 HTTP 客户端读头条留言板（topSid 为 0 时为空）。回放和下播的房间没有弹幕参数，同 v3。
- 样本：
  - `fixtures/huya/danmaku/S11-live`：真实录制（2026-09-27，房间 998，主播 UID、topSid、subSid 都是 294636272，约 40 s，`frames.jsonl` 共 265 行：2 帧发出、262 帧收到，另 1 行是录制工具请求的头条留言板 HTTP 回答，不是 WebSocket 帧），来自归档。收到的帧里有命令 7（单条推送）的 110 条聊天和 uri 6501、6110、6211 等，命令 22（分组推送）的 2 条热度（8006）和 uri 6111、6892、7708 等，以及注册回应（17）和心跳回应（21）。没有头条通知（2001314），也没有带事件 id 的聊天；
  - `fixtures/huya/danmaku/S16-synthetic`：本模块补的合成帧（`cases.json`，22 组），覆盖录制里没有的分组推送聊天、各种颜色、热度、头条通知、缺字段、别的分组、未知的 uri 和命令、坏包、截断和非 Tars 数据。编号接在 T02.U 的 S15 之后；
  - 两个目录的 `expected.json` 都由 `fixtures/huya/danmaku/legacy_expected.dart` 生成：它把 v3 `HuyaDanmaku` 的解码代码（`heartbeatData`、`getJoinData`、`decodeMessage`、`_decodePush` 和六个 `HY*` 结构）和 v3 的 Tars 编解码（`pkg/tars/codec`）原样搬进独立程序，只把日志换成标准错误输出（Tars 读取器的调试日志不输出）、回调换成列表、2001314 触发的留言板补拉换成计数，模型删到只剩字段。合成帧也用 v3 的 `TarsOutputStream` 写出，结果里带上帧的字节。运行：`dart run fixtures/huya/danmaku/legacy_expected.dart`（仓库根目录）。
- 参考：
  - v3：`legacy/lib/core/danmaku/huya_danmaku.dart`、`pkg/tars/codec/`、`core/common/web_socket_util.dart`、`core/site/huya/huya_site.dart`（`getDanmaku`）、`core/site/huya/huya_utils.dart`（`getHuyaSuperChatMessageList`）、`modules/live_play/controllers/`（醒目留言的去向），测试 `test/huya_danmaku_protocol_test.dart`（8 个用例）；
  - 归档 v4（`archive/v4`，6ba709135）的 `packages/live_danmaku/lib/src/sites/huya.dart` 和规格 `spec/sites/huya.md` 第 7 节、回归条目 REG-HUYA-014、020、021；
  - pure_live_TV `e1cca224` 的 `lib/platforms/huya/huya_danmaku.dart`（见“上游核对”）。

## 做法

- **连接用 T06a.1 的 WebSocket 运行时**，平台只写四样，都照 v3：
  - 地址：只有 `wss://wsapi.huya.com` 一个，不带请求头和子协议，匿名。录制工具握手时带了 `Origin: https://www.huya.com`，v3 应用没带，照 v3；
  - 打开即就绪（v3 在 `onReady` 里先 `markConnected`、报 `onReady`），随后发命令 16 注册 `live:<主播UID>`、`chat:<主播UID>` 两个分组，紧接着发一次心跳；每次重连都重新注册；
  - 心跳：命令 20、空负载，每 60 s 一次；
  - 其余用 `DanmakuSocketPolicy` 的默认值，也就是 v3 `WebScoketUtils` 的默认值：无消息 180 s（max(3 × 60 s, 90 s)）换连接，握手超时 10 s，连续失败 8 次放弃。只有一个地址，所以重连间隔依次是 2、3、4、5、6、6、6、6 s。没有加入计时器（v3 没有）。
- **协议照 v3 的 `HuyaDanmaku`**，写成纯函数，编解码用 T02a.3 放在 `live_core` 的 Tars（`TarsWriter`、`TarsStruct`）：
  - 帧：tag 0 命令号，tag 1 负载字节。只看命令 7（负载 tag 1 uri、tag 2 消息体）和 22（负载 tag 0 分组、tag 1 条目列表，每条 tag 0 uri、tag 1 消息体、tag 2 事件 id），其他命令忽略；
  - uri 1400 是聊天：发送者 tag 0（其中 tag 0 uid、tag 2 昵称）、内容 tag 3、弹幕格式 tag 6（其中 tag 0 颜色）。颜色不大于 0 是白色（虎牙默认色是 −1），否则经过 `LiveMessageColor.numberToColor`；
  - uri 8006 是热度，`LiveAudienceUpdate` 标为 `popularity`（REG-HUYA-014），值取 tag 0，缺失为 0；
  - 消息 id：只有命令 22 的条目有，写成 `huya:<事件id>`；命令 7 的消息没有 id，同 v3；
  - 缺字段按 v3 的默认值：uid 0（用户 id 为 `0`）、空字符串、颜色 0。文字为空的聊天照样报出，同 v3；
  - 一个条目的消息体解不开，只丢这一条，同一帧里后面的照常（审查问题 1）；整帧不是 Tars 时什么也不报。
- **头条留言（醒目留言）照 v3**：uri 2001314 只是通知，消息体不读。连接在后台调用 `HuyaDanmakuArgs.superChats` 读留言板：
  - 第一次立即，之后再等 0.6、1.8、4 s，最多 4 次；每次最多等 3 s（v3 在拉取外面也套了 3 s）；失败或超时就等下一次；
  - 本次连接里没见过的条目才报出（按事件 id，`LiveSuperChatMessage` 的相等规则），最多记 512 条；已经报过条目之后，某一次拉到了新条目就不再重试（留言板已经跟上）；
  - 同一时间只有一轮补拉；补拉期间再来通知，结束后再补一轮（多个通知也只补一轮）；
  - 解码不等补拉，弹幕照常；`close`、换房间之后，还没回来的结果丢掉，剩下的等待立即结束（`DanmakuRun.delay`）；
  - 没有 `superChats`（topSid 为 0）时通知不起作用，同 v3。
- **醒目留言的消息**：类型 `superChat`，用户名和文字都是 `SUPER_CHAT_MESSAGE`，白色，数据是留言板给的 `LiveSuperChatMessage`（T02a.3 解析：配色 `#ffffff`/`#246488`、id `huya:<lMessageId>`）。
- **颜色**：按 T02g.1 修正后的 `numberToColor`。v3 把数字转成十六进制文字再解析，只认 4、6、8 位；录制里的颜色都是 6 位或 −1，结果和 v3 一样。

## 与 v3 的对照

对照方式：同一份帧分别给新代码和 v3 的解码代码（`legacy_expected.dart`），逐条比较消息的全部字段（类型、用户名、用户 id、文字、颜色、消息 id、发送时间、等级和粉丝牌字段、是否本地、热度的类型和数值）和头条通知的个数。

| 样本 | 结果 |
|---|---|
| S11-live 发出的帧 | 注册包、心跳包与 v3 的 `getJoinData`、`heartbeatData` 逐字节相同，也与录下的两帧发出帧相同 |
| S11-live 收到的 262 帧 | 112 条消息，顺序、所在的帧和全部字段一致：110 条聊天（58 条默认色为白色，其余 52 条是 8 种 6 位颜色，都没有消息 id），2 条热度（5413644，带 `huya:` id）；头条通知 0 个 |
| S16 合成帧的字节 | `live_core` 的 `TarsWriter` 写出的 22 帧与 v3 的 `TarsOutputStream` 逐字节相同 |
| S16 移植 v3 的用例（分组推送的热度、头条通知） | 一致 |
| S16 分组推送的聊天、单条推送、默认色、颜色 0、没有格式、4 位和 6 位颜色、热度（分组、单条、缺数值）、两个通知夹一条聊天、单条推送的通知、缺发送者、空文字、长文字（string4）、别的分组和频道、未知 uri、其他命令、截断的帧、不是 Tars | 一致 |
| S16 v3 解析不了的颜色 | v3 把 255、0x0A0A0A、0x1FF0000、100 都显示成白色；新代码是 `#0000ff`、`#0a0a0a`、`#ff0000`、`#000064`（差异 3） |
| S16 分组里有一条坏消息体 | v3 只报出它前面的一条；新代码还报出后面的一条（差异 1） |
| S16 文字不是合法 UTF-8 | v3 什么也不报（这一条和后面的都丢了）；新代码报出一条替换字符 `U+FFFD` 的聊天和后面的一条（差异 4） |
| S16 发送者 uid 是 −1（Tars int8） | v3 的用户 id 是 `255`；新代码是 `-1`（差异 4） |

测试里把这四处差异写成对 v3 输出的变换：先断言 v3 的输出确实如上，再断言新代码等于变换后的结果，其余用例要求完全相等。

## 审查发现的 v3 问题

位置相对 `legacy/lib/`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 分组推送（命令 22）里有一条消息解不开，同一帧后面的消息全部丢失 | `core/danmaku/huya_danmaku.dart:171-190` | 整帧只有一个 `try`，逐条 `await _decodePush` 都在里面 | 每个条目单独解码，坏的只丢这一条（同 T06a.3 斗鱼的 REG-DOUYU-021） |
| 2 | 收到文本帧会在 socket 回调里抛类型错误 | `core/danmaku/huya_danmaku.dart:102-104` | `decodeMessage` 的参数是 `List<int>`，回调传进来的是 `dynamic` | 文本帧忽略。虎牙只发二进制帧，线上没有影响 |
| 3 | 聊天颜色：默认色 −1 能显示成白色，全靠两个错误相互抵消；1～3、5、7 位十六进制的颜色都成了白色 | `pkg/tars/codec/tars_input_stream.dart:48-50`；`common/models/live_message.dart:128-151` | Tars 的 int8 按无符号读，−1 读成 255；`numberToColor` 解析十六进制文字，`ff` 只有 2 位，于是回到白色 | 共用的 Tars 按有符号读（T02a.3 问题 19），−1 按“不大于 0 是白色”显示；`numberToColor` 用 T02g.1 的修正 |
| 4 | 消息体里有不合法的 UTF-8 时，这一条和同帧后面的都丢失 | `pkg/tars/codec/tars_input_stream.dart:348, 360` | 字符串用严格的 `utf8.decode`，出错抛异常 | 共用的 Tars 把坏字节换成 `U+FFFD`（T02a.3） |
| 5 | 发送者结构把 `lMid` 也从 tag 0 读 | `core/danmaku/huya_danmaku.dart:397-398` | 抄错了 tag（归档规格 §7.4 已记录） | 不影响 v3 的输出（`lMid` 从没用过）；新代码不读这个字段 |

另外核对了归档 v4 的两处改动，发现它们有问题，没有采用：

- 归档 v4 把聊天的 tag 1 当成主播 UID，不等于本房间主播时丢弃。按虎牙的 `MessageNotice` 定义，tag 1 是频道号 `lTid`、tag 2 是子频道 `lSid`、tag 11 才是主播 `lPid`；S11 的房间三者正好都是 294636272（S11 里还有 tag 1、tag 2 为 0 的聊天），T02a.3 录到的三个直播间也都是频道号等于主播 UID，所以没被发现。两者在虎牙的接口里是不同的字段（`lChannelId` 和 `lPresenterUid`），不保证相等；一旦不等，这个检查会把整个房间的聊天丢光。v3 也不检查；
- 归档 v4 只收分组 id 等于本连接注册分组的命令 22。v3 不检查；服务端只推送注册过的分组（S11 的分组 id 都是 `live:<主播UID>`），v3 在这里没有问题。

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 分组推送里坏的条目只丢自己 | 问题 1。统一原则“容错” |
| 2 | 文本帧忽略 | 问题 2 |
| 3 | 1～3、5、7 位十六进制的颜色显示成它本来的颜色 | 问题 3；T02g.1 对 `numberToColor` 的修正。录制里的颜色都是 6 位或 −1，没有变化 |
| 4 | Tars 的 int8 按有符号读（uid −1 不再变成 255）；不合法的 UTF-8 换成 `U+FFFD`，不再丢掉整帧 | 问题 3、4；T02a.3 的共用 Tars。都只在坏数据或罕见的负数上出现 |
| 5 | 留言板由 `HuyaDanmakuArgs.superChats` 读，不再在弹幕里直接调用全局的 `getHuyaSuperChatMessageList` | `live_danmaku` 不带平台的 HTTP 客户端；请求的字段、请求头和解析与 v3 相同（T02a.3 逐字段核对），请求本身 3 s 超时（REG-HUYA-022），连接外面仍保留 v3 的 3 s |
| 6 | 回调换成事件，`connect` 只接受 `HuyaDanmakuArgs`（其他类型抛 `ArgumentError`） | T06a.1 的统一接口；v3 是强制转换失败 |
| 7 | 停止或换房间时，补拉的等待立即结束 | v3 等完才检查会话号，结果同样丢掉；界面上看不出区别 |
| 8 | 同一帧的条目同步依次处理 | v3 每条之间 `await` 一次，只影响微任务的先后，顺序不变 |

保持 v3 行为、没有顺手改的地方：

- **打开即就绪**，不等注册回应（命令 17）；服务端的心跳回应（命令 21）不看；没有加入计时器。
- **握手不带 `Origin`**：v3 应用一直这样连，能收到弹幕。
- **主播 UID 为 0 时照样连接**，注册 `live:0`、`chat:0`（归档规格记为待确认，归档 v4 改成不连）。T02a.3 只给直播中的房间弹幕参数。
- **单条推送（命令 7）的聊天没有消息 id**：录制的 110 条聊天都走命令 7。负载的 tag 5 和聊天的 tag 20 都有平台的消息 id（归档 v4 用了 tag 20），用上它能让去重闸门按 id 判断重连后重放的消息，但会把“2.5 s 内同一用户同一文字只显示一次”变成“同 id 只显示一次”，改变了可见行为，没有做；可以作为升级候选。**已做（T06a.F）**：用 tag 5，见末尾“后续升级”一节。
- **不检查分组和频道**（见上一节）；文字为空的聊天照样报出。
- **不显示礼物、进场、贵宾席等其他 uri**：v3 没有显示。
- **留言板的初次读取不在连接里**：v3 由直播间在进房时调用 `getSuperChatMessage`（M13），连接只在收到通知后补拉；每次连接从空的记录开始，已经显示过的留言由直播间按 `LiveSuperChatMessage` 的相等规则合并。
- **每次重连都报一次 `DanmakuReady`**，一轮失败只报一次重连（T06a.1 的运行时，和 v3 一样）。

## 回归条目的覆盖

归档规格里属于弹幕的三条都有测试：

- REG-HUYA-014（8006 是热度，不是在线人数）：S11 的两条和 S16 的三组热度用例；
- REG-HUYA-020（`wsapi.huya.com`、命令 16 注册 `live:`/`chat:`、命令 20 心跳、解析命令 7 和 22）：注册包和心跳包与 v3、录制逐字节相同，连接测试检查地址、注册、立即心跳和 60 s 心跳，S11 和 S16 覆盖两种推送；
- REG-HUYA-021（后台有限重试、按事件 id 去重、按会话丢弃旧结果）：移植 v3 的 4 个用例（后台补拉不阻塞解码、重复的快照只报一次、内容相同 id 不同的两条都报、旧房间的结果不影响新房间），另加通知排队、失败和超时后继续、关闭后丢弃、没有 topSid。

## 登记方式

应用（T07a.1）建 `DanmakuRegistry` 时：

```dart
SiteIds.huya: () => HuyaDanmakuConnection(proxy: proxyPolicy),
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `proxy` | 否（默认直连） | `live_net` 的 `ProxyPolicy`，每次握手按平台 id `huya` 取路线；v3 的弹幕走应用的代理设置 |
| `connector` | 否 | 只给测试替换握手 |

不需要 HTTP 客户端、Cookie、账号或设置：弹幕是匿名连接；读留言板的函数由 `HuyaSite` 放进 `HuyaDanmakuArgs.superChats`，用的是适配器自己的 HTTP 客户端和代理（v3 读留言板也不带 Cookie）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 进房时读一次完整的留言板（`HuyaSite.getSuperChatMessage`，T02a.3 已提供）、醒目留言栏和按相等规则合并、过期清理 | M13 |
| 连接状态的提示文字、弹幕列表、热度显示 | M13（T06a.1 的原因表） |
| 虎牙表情（`assets/emo/json/huya.json`，解析在 T06a.1 的 `DanmakuEmoji`） | T01a.1 |
| 电视端是否把虎牙弹幕统一成白色（见“上游核对”） | T18 |
| 平台表的登记 | T07a.1 |

## 上游核对

pure_live_TV `e1cca224` 的虎牙弹幕与 v3 基本相同：提示文字换成了多语言键（T06a.1 已记录）；聊天一律白色，理由是电视上满屏的彩色字不好读。这是电视端的取舍，手机和桌面照 v3 显示颜色，没有采用，留给 T18 决定。T06a.1 的对照表提到“pure_live_TV 给留言板请求加了 3 s 超时”，其实 v3 的代码里已经有了（`huya_danmaku.dart:259`，`huya_utils.dart:47`），这里照 v3 保留，没有新的修复可采用。

## 升级条目

`docs/specs/UPGRADES.md` 里虎牙只有 3-1（回放），不涉及 T06a。T02.U 记录已说明回放房间不给弹幕参数，同 v3。

## 测试

`huya_test.dart` 47 个用例，`live_danmaku` 共 191 个，连续跑 3 次全部通过：

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 4 | 注册包和心跳包与 v3、录制逐字节相同（移植 v3 的 2 个用例）；颜色规则；醒目留言消息的形状；留言条目按事件 id 相等（移植 v3 的用例） |
| 录制帧（S11）对照 v3 | 1 | 262 帧逐条对照 112 条消息和通知个数 |
| 合成帧（S16）对照 v3 | 23 | 22 组各一个用例（4 组按上面的差异变换），另有一个检查每组都有 v3 输出、`TarsWriter` 写出的帧与 v3 逐字节相同 |
| 连接 | 19 | 地址、无请求头、打开即就绪、注册和立即心跳；策略（60 s、180 s、无加入计时器、8 次）；60 s 的心跳计时器和手动心跳；回放整段录制得到 v3 的 112 条；头条补拉（不阻塞解码、重试间隔 0.6/1.8/4 s、只报一次、有基线时拿到新条目就停、同内容不同 id、通知排队只补一轮、失败和 3 s 超时后继续、没有 topSid、换房间丢弃旧结果、关闭后丢弃）；断线后 2 s 重连、重新注册、再次就绪；退避 2、3、4、5、6、6、6、6 s 后放弃；`close` 之后没有事件和心跳；文本帧；参数类型；平台表登记；本地 WebSocket 服务器端到端回放 |

## 后续升级（T06a.F，附录 B-4）

- 日期：2026-10-01（样本 2026-09-30 录制）
- 条目：B-4“用平台消息 id 去重，断线重连后不再重复显示”。

### 做法

- 单条推送（命令 7）负载的 tag 5 `lMsgId` 作为消息 id，写成 `huya:<lMsgId>`：和分组推送（命令 22）条目的 tag 2 是同一个字段、同一种写法。不大于 0、缺失或不是整数时没有 id，和以前一样。聊天和单条推送的热度都带上（热度不经过去重闸门）。
- 连接本身不去重，去重由 T06a.1 的去重闸门按 id 做：10 分钟内同一个 id 只收一次。有 id 的消息不再按“类型 + 用户 + 文字，2.5 s”去重。

### 依据：为什么用 tag 5，不用聊天的 tag 20

- 网页脚本 `fedlib.msstatic.com/fedbasic/huyabaselibs/taf-signal/taf-signal.global.0.1.2.prod.js`（房间页 2026-09-30 引用的版本）：
  - `WSPushMessage` 的字段是 `ePushType, iUri, sMsg, iProtocolType, sGroupId, lMsgId, iMsgTag`（tag 0～6），`WSMsgItem` 是 `iUri, sMsg, lMsgId`；
  - 收到命令 7（`EWSCmdS2C_MsgPushReq`）、命令 22（`EWSCmdS2C_MsgPushReq_V2`）和 P2P 数据时，都先调用 `filterMessage(…, lMsgId)`：`lMsgId` 在最近 1000 个里出现过（`signalCache`，环形，`MAX_MESSAGE_COUNT=1e3`）就丢掉，并打印“重复的消息id”。这个缓存建在连接对象上，断线重连后仍在；
  - 聊天的 tag 20 是 `MessageNotice.sMessageId`，脚本里只有定义和读写，没有用到。
- 样本：
  - S11-live 的 110 条聊天，tag 5、tag 20 各不相同；
  - 新录的 `S17-reconnect`：两条连接（A、B）同时进 998 房间，A 在 50.4 s 断开，5 s 后重连为 A2。同一条聊天在两条连接上的 tag 5 和 tag 20 都相同（A 的 124 条、A2 的 61 条都能在 B 的 189 条里找到，用户和文字也相同）；同一连接里都不重复；A2 没有收到任何在它连上之前发出的聊天，也就是重新注册分组不补发历史。
- tag 5 和 tag 20 都稳定、唯一。选 tag 5：网页按它去重，分组推送的条目也只有它。

### 用户看到的变化

- 同一条消息被送到两次时只显示一次（网页防的就是这种情况：P2P 和 WebSocket 各送一次、服务端重发）。录制里没有出现重复，重连也不补发，所以平时看不出区别。
- 同一观众 2.5 s 内重复发同一句话，现在每条都显示，以前只显示第一条。S17 里就有：一位观众 2.4 s 内三次“不小心购买此产品998”，现在 3 条，以前 1 条。这和网页一致（网页只按 `lMsgId` 去重）。想合并重复弹幕的用户可以打开“折叠重复弹幕”（T06a.1 的 `RepeatedDanmakuFilter`，默认关）。

### 与决定的差异

没有。决定只写“用平台消息 id 去重”；用哪个字段，依据见上。

### 样本

`fixtures/huya/danmaku/S17-reconnect`：匿名、只读、直连，约 105 s，自写的录制程序（`dart:io` 的 WebSocket，不带额外请求头；每条连接只发注册包和心跳）。只留聊天推送（命令 7、uri 1400）和连接的打开、关闭标记，其余 868 帧（其他 uri、分组推送、注册和心跳的回应）不留。发送者换成合成值（同样位数的随机 uid 和“观众N”，同一个人在各帧、各连接里保持一套值），装饰（粉丝牌、贵族标识）、@、图标、标签和场景格式清空；其余字段（含 tag 5 和 tag 20）按录制原样重新编码（Tars 编解码对 374 条录制聊天逐字节往返一致）。见 `meta.json`。门禁的 `fixture privacy` 通过。

### 测试

`huya_test.dart` 52 个（原 47 个，加 5 个），`live_danmaku` 共 1329 个，连续跑 3 次全部通过：

| 内容 | 用例 |
|---|---|
| 原有的 S11 对照和两个回放用例（连接回放、本地 WebSocket 服务器） | 期望改为“v3 的输出，单条推送的消息带上 `huya:<lMsgId>`”，测试里注明 B-4；另断言 v3 的 110 条聊天都没有 id，现在都有且互不相同 |
| S17：同一聊天在各连接上 id 相同、连接内不重复、重连后不补发；tag 20 同样稳定 | 1 |
| 去重闸门：三条连接的聊天只放过 189 条；稍后原样再送一遍，全部丢掉 | 1 |
| 同一观众 2.5 s 内的重复：有 id 时每条都显示，去掉 id（v3 的样子）时只剩第一条 | 1 |
| 合成帧：tag 5 为 0、负数、缺失、字符串时没有 id；单条推送的热度带 id；分组条目仍用 tag 2；坏消息体照样跳过；头条通知不受影响 | 1 |
| 连接：断线重连后服务端再送一次同一条，连接照报两条同 id，闸门只放一条；同一句话换了 id 照样显示 | 1 |

### 放到其他模块的部分

没有。去重闸门在 T06a.1，由 M13 的过滤链调用。
