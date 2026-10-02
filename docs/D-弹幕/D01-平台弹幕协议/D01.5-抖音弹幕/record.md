# D01.5 弹幕：抖音

- 日期：2026-09-29
- 目标：
  - `packages/live_danmaku/lib/src/sites/douyin.dart`：`DouyinDanmakuProtocol`（地址、心跳、ACK、解码，不做 I/O）和 `DouyinDanmakuConnection`（连接）；
  - `packages/live_danmaku/lib/src/sites/douyin/protobuf.dart`：手写的 protobuf 读写（`ProtoMessage`、`ProtoWriter`），不从包里导出。
- 参数：`live_core` 的 `DouyinDanmakuArgs`，E01.4 的 `DouyinSite.getRoomDetail` 放进 `LiveRoom.danmakuData`：web_rid、本场 room_id、19 位访客号（reflow 给的 `user_unique_id`，否则适配器自己的访客号）、会话 Cookie（用户的，否则匿名 ttwid）；`headers` 给出握手头。签名用 E01.4 的 `DouyinSigner.danmakuSignature`（已与 v3 的 `getSignature` + `generateXBogus` 逐位核对）。
- 样本：
  - `fixtures/douyin/danmaku/S13-live`：真实录制（2026-09-27，匿名，房间 148108118778，约 30 s，163 帧：发出 82 帧 = 4 个心跳 + 78 个 ACK；收到 81 帧 = 78 帧消息 + 3 帧心跳回复），E 从归档复制。消息里有 215 条聊天、16 条 `WebcastRoomUserSeqMessage`，其余 18 种方法的负载在录制时已清空（见“样本”）；
  - `fixtures/douyin/danmaku/S13-vectors`：本模块补的 25 个合成向量（36 帧），见目录里的 README；
  - 两个样本的 `expected.json` 都由 `fixtures/douyin/danmaku/legacy_expected.dart` 生成（见“v3 的冻结输出”）。
- 参考：
  - v3：`legacy/lib/core/danmaku/douyin_danmaku.dart`、`core/danmaku/proto/douyin.proto` 和生成的 `douyin.pb.dart`、`core/common/web_socket_util.dart`、`core/site/douyin/douyin_site.dart`（`getDanmaku`、参数的来源）、测试 `test/douyin_danmaku_protocol_test.dart`（6 个用例）；
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/douyin.dart`、`codec/protobuf.dart`，规格 `spec/sites/douyin.md` 第 7 节，回归条目 REG-DOUYIN-002、003，录制工具 `tools/live_cli/lib/src/danmaku/scrub_sites.dart`；
  - pure_live_TV `e1cca224`：`lib/platforms/douyin/douyin_danmaku.dart`（见“上游核对”）。

## 做法

- **连接用 D01.1 的 WebSocket 运行时**，平台只写四样，都照 v3：
  - `target`：本场的两个地址（下表）和房间的握手头；签名在这里算，每次 `connect` 算一次，之后的重连沿用（v3 如此）；
  - `onOpen`：打开即就绪，随后发一个 `hb` 帧作为加入（v3 的 `joinRoom`）；每次重连都重发；
  - `onData`：解码一帧；要 ACK 时先发 ACK，再上报消息；
  - `heartbeatFrame`：`PushFrame{payloadType: "hb"}`。
- **protobuf 手写，不加依赖**。v3 用 `package:protobuf` 6.1.0 和生成的 7500 行类，工作区和 Dart SDK 里都没有 protobuf 运行时。实际只用到 `PushFrame`、`HeadersList`、`Response`、`Message`、`ChatMessage`、`Common`、`User`、`RoomUserSeqMessage` 的十来个字段，所以写了一个按层读取的读取器和一个写入器（约 200 行），在正常数据上的结果与 v3 的运行时相同：
  - 单个字段取最后一次出现的值；字段用了与声明不同的 wire type 时当作未知字段忽略；
  - 单个消息字段出现多次时合并（等于把各次的字节连起来读）；
  - bool 看变长整数的低 32 位（v3 运行时的 `readBool`）；
  - 字符串按 UTF-8 解码，坏字节换成替换字符；
  - 截断、超过 10 字节的变长整数、字段号 0、长度超出 int32、不成对的 group 结束、wire type 6 和 7 都是 `FormatException`；group 跳过。
- **解码照 v3 的 `decodeMessage`**：
  - `payloadEncoding` 转小写等于 `gzip`，或负载以 `1f 8b` 开头时，用 `dart:io` 的 gzip 解压（与 v3 同一个实现），否则原样；
  - `Response.needAck` 为真时回 `PushFrame{logId: 原帧 logId, payloadType: "ack", payload: internalExt}`，三个字段都写，即使为 0 或空（v3 生成的类对显式赋值的字段照写）；
  - `WebcastChatMessage`：`common.roomId` 不为 0 且与本场 room_id 不同就丢；消息 id 取 `common.msgId`，为 0 时取外层 `Message.msgId`，都为 0 时为空，加前缀 `douyin:`；`common.createTime` 大于 10¹¹ 按毫秒，否则按秒，不大于 0 时没有时间；用户名 `user.nickName`，用户 id `user.id`（没有 `user` 时为 `0`，同 v3）；颜色一律白色；
  - `WebcastRoomUserSeqMessage`：`onlineUserForAnchor`（如 `30.6万`）含数字时，按 `parseAudienceNumber` 上报在线人数（`onlineViewers`）；
  - 其他方法（进场、礼物、点赞、关注、榜单等）忽略，和 v3 一样。
- **帧本身读不出来时整帧丢弃，不回 ACK**（同 v3）：`PushFrame`（含它的 `headersList`）、解压、`Response`（含每个 `Message` 外壳和 `routeParams`）任何一处出错。v3 生成的类会把这些一次读完，所以这里也在处理前把它们读一遍。聊天和在线人数的负载各自解码，一条出错只丢这一条（差异 2）。

## 连接

| 项目 | 值（与 v3 相同） |
|---|---|
| 地址 | `wss://webcast100-ws-web-lq.douyin.com/webcast/im/push/v2/`、`wss://webcast100-ws-web-hl.douyin.com/webcast/im/push/v2/`，同一组查询参数（REG-DOUYIN-002） |
| 查询参数 | v3 的 31 个，顺序相同：`app_name=douyin_web`、`version_code=180800`、`webcast_sdk_version=1.0.15`、`update_version_code=1.0.15`、`compress=gzip`、`cursor=h-1_t-<开始时的毫秒>_r-1_d-1_u-1`、……、`user_unique_id=<访客号>`、……、`browser_version=<UA 去掉 "Mozilla/">`、……、`room_id=<本场 room_id>`、`need_persist_msg_count=15`、`heartbeatDuration=0`、`signature=<签名>`。签名作为查询参数值编码（`+`、`/` 变成 `%2B`、`%2F`）。测试核对与 v3 的 `buildServerUrls` 和录制的握手地址逐字相同 |
| 请求头 | `user-agent`（Chrome 134）、`cookie`（去空白后非空才带，带原值）、`origin: https://live.douyin.com`、`referer: https://live.douyin.com/<web_rid>`，即 `DouyinDanmakuArgs.headers`；与 v3 的 `buildHandshakeHeaders` 只差名字大小写（`dart:io` 发送时都转小写） |
| 就绪 | 打开即就绪（`DanmakuReady`），随后发 `hb` |
| 心跳 | 10 s，`PushFrame{payloadType: "hb"}`（4 字节 `3a 02 68 62`，与录制相同）；服务端的心跳回复不处理 |
| 无消息超时 | 45 s（v3 单独设的 `inactivityTimeout`；由 `LiveSocket` 每个心跳周期检查一次） |
| 重连 | 默认：失败后立刻换另一个地址，两个地址轮流，等待 1、2、2、3、3、4、4、5 s，连续 8 次后 `reconnectsExhausted`；收到任何消息清零 |
| 加入超时 | 没有（v3 没有） |

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.douyin: () => DouyinDanmakuConnection(proxy: proxyPolicy),
  // …
});
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `proxy` | 否（默认直连） | `live_net` 的 `ProxyPolicy`，每次握手按平台 id `douyin` 取路线；v3 的弹幕走应用的代理设置 |
| `connector` | 否 | 替换 `dart:io` 的握手；抖音不需要保留大小写的握手，只给测试用 |
| `random`、`now` | 否 | 签名的随机字节和游标时间，只给测试固定结果，应用不传 |

不需要 HTTP 客户端、Cookie 或设置：房间号、访客号、Cookie 都在 `DouyinDanmakuArgs` 里（E01.4 在取详情时放进去，Cookie 变了会换会话），签名在本地算。

## v3 的冻结输出

`fixtures/douyin/danmaku/legacy_expected.dart` 生成两个样本的 `expected.json` 和 `S13-vectors/frames.jsonl`：

- 把 v3 `DouyinDanmaku` 的 `decodeMessage`、`unPackWebcastChatMessage`、`unPackWebcastRoomUserSeqMessage`、`sendAck`、`heartbeat`、`joinRoom`、`buildServerUrls`、`buildHandshakeHeaders` 和 `start` 里的查询参数原样搬进一个程序，连同 `DouyinDanmakuArgs`、`DouyinRequestParams`、`LiveRoom.parseAudienceNumber`，以及 `LiveMessage`、`LiveMessageColor`、`LiveAudienceUpdate` 用到的部分。protobuf 用 v3 生成的 `douyin.pb.dart`，跑在 v3 的运行时上（protobuf 6.1.0、fixnum 1.1.x）。
- 只替换了：`WebScoketUtils`（桩，`sendMessage` 记下发出的帧）、`CoreLog`（记下错误类型）；`start`、`stop`、`getSignature` 这些 socket 生命周期和随机签名没有搬（签名 E01.4 已核对），`start` 里包着解码的 `try/catch` 照搬。
- protobuf 运行时不是工作区的依赖，所以由 `legacy_expected.sh` 在临时目录建一个一次性的包（离线从 pub 缓存取 protobuf 和 fixnum，从 `archive/v4` 取生成的类）来运行，运行完删掉，仓库不加依赖。运行：`bash fixtures/douyin/danmaku/legacy_expected.sh`（仓库根目录）。输出是确定的，连续运行两次逐字节相同。
- 一个样本（S13-live）或一个向量用同一个 v3 实例，参数是房间的参数（S13-live 取 `meta.json` 的 `danmakuKeys`）。每一帧收到的数据按顺序记下效果：发出的帧（Base64）、上报的消息（投影成各字段）、记录的错误类型。另外记下心跳帧、按录制的游标时间和签名算出的两个地址、三种 Cookie（无、有、空白）下的握手头。

## 与 v3 的对照

对照方式：同一帧分别给新代码和冻结输出，逐条比较效果（ACK 的字节、消息的全部字段和顺序）；v3 记录的错误只比较“有没有”：v3 某帧报了错，新代码这一帧也要报告错误，反之亦然。连接测试再把整段录制交给连接，按发送和事件的先后与冻结输出比较。

| 样本 | 结果 |
|---|---|
| S13-live 发出的帧 | 心跳与 v3 逐字节相同；78 个 ACK 与 v3 的 `sendAck` 逐字节相同，也与录制的 78 个发出帧相同；两个地址与 v3 逐字相同，第一个与录制的握手地址相同 |
| S13-live 收到的 81 帧 | 全部一致：78 个 ACK、215 条聊天（没有一条带 `createTime`，`sentAt` 都为空）、16 次在线人数（`30.6万` 得 306000 等），先后顺序也相同；3 帧心跳回复两边都不处理 |
| S13-live 换成别的 room_id | 聊天全部丢弃，在线人数和 ACK 照常 |
| S13-vectors 21 个向量 | 一致：gzip 的五种判定（编码、大写的编码、魔数，以及编码说 gzip（含大写）而负载不是 gzip）、不要 ACK、ACK 的 logId 为 0 或超过 2^63、internalExt 为空、`needAck` 只有高位、时间的毫秒/秒/0/缺失/正好 10¹¹、消息 id 的三级取法和负的外层 id、房间号相同/不同/0/缺失、没有用户或文字、带头像和徽章的完整用户、`common` 分两次出现、字段用了别的 wire type、在线人数的各种文字、其他方法、心跳回复、10 种畸形帧（截断的各层、坏 gzip、截断的 gzip、字段号 0、空帧） |
| S13-vectors 4 个向量 | 有意差异，测试先断言 v3 的输出，再断言新代码的：坏的聊天之后的聊天和在线人数、坏的在线人数之后的聊天、时间超出范围的聊天之后的聊天（差异 2）；room_id 和 id 超过 2^63 的聊天（差异 1） |

## 审查发现的 v3 问题

位置相对 `legacy/lib/`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 2038-01-19 03:14:08（UTC）以后开播的房间，弹幕全部被丢掉 | `core/danmaku/douyin_danmaku.dart:228-230、248` | `Common.roomId`、`msgId`、`User.id` 是 uint64，生成的类读成 `Int64`，`toString()` 按有符号打印。抖音的 room_id 高 32 位是开播的 Unix 秒（7690183442860198697 >> 32 = 1790510360，即 2026-09-27 11:59:20），到 2^31 秒时越过 2^63，打印成负数，和参数里的无符号 room_id 永远不等 | 按无符号打印（差异 1）。现在的编号都小于 2^63，结果不变 |
| 2 | 一帧里一条消息读不出来（或时间超出 `DateTime` 的范围），同一帧后面的聊天和在线人数全部丢失 | `core/danmaku/douyin_danmaku.dart:137-143、218-223、235-237` | 整帧只有 `start` 里的一个 `try`；逐条解码的循环在第一次抛错时就退出 | 每条消息单独解码，出错只丢这一条（差异 2）；帧本身读不出来时仍整帧丢弃、不回 ACK |

没有发现别的问题。v3 的 `getSignature` 出错时返回空签名照常连接（`:330-333`），但 MD5 的十六进制串总是合法的 X-Bogus 输入，这条路径走不到，`DouyinSigner` 也没有失败的情况。

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | uint64 的 room_id、消息 id、用户 id 按无符号打印 | 问题 1。2^63 以下与 v3 相同；外层 `Message.msgId` 是 int64，照 v3 按有符号 |
| 2 | 聊天、在线人数的负载各自解码，一条出错（含时间超出范围）只丢这一条 | 问题 2，也是升级决定“统一原则”里的“容错：一行坏数据只跳过这一行”。时间超出范围的聊天本身仍丢掉，和 v3 一样（哔哩哔哩同样处理） |
| 3 | 只检查用到的那一层的格式：v3 生成的类会把聊天里的头像、徽章、富文本等嵌套消息也读一遍，其中有坏数据就整条失败；新代码不读这些，照样显示 | 只影响畸形数据，正常数据的结果相同。整数字段以长度分隔的方式出现时，v3 的运行时把长度当值读、再把后面的字节当字段读（通常报错）；新代码忽略这个字段 |
| 4 | 回调换成事件，`connect` 只接受 `DouyinDanmakuArgs`（其他类型抛 `ArgumentError`） | D01.1 的统一接口；v3 强制转换失败时抛类型错误 |
| 5 | 解码错误不写日志，作为 `decode` 返回值的 `errors` | 包里没有日志设施（D01.1）；界面上看不出区别 |

保持 v3 行为、没有顺手改的地方：

- **在线人数取 `onlineUserForAnchor` 的文字**（`30.6万` 得 306000），不取同一消息里的精确整数 `total`（305503）。归档 v4 改成先取 `total`；E01.4 在接口层做了“精确整数优先”，但弹幕这里没有小房间的样本，证明不了 `total` 在所有房间都是在线人数，改了还会让数字和 v3 不同，列为升级候选。
- **聊天的时间只看 `common.createTime`**。录到的 215 条聊天都没有它，只有 `ChatMessage.eventTime`（字段 15，秒），所以 `sentAt` 都为空，和 v3 一样；D01.1 的去重闸门对没有时间的消息不做时间检查，只按消息 id 去重。归档 v4 用 `eventTime` 兜底，那会让 45 s 前的历史消息被闸门丢掉，改变显示，列为升级候选。
- **文字为空的聊天照样上报**，没有用户时用户 id 为 `0`。录制里没有这种聊天。
- **重连沿用第一次的游标和签名**；主播重新开播后 room_id 会变，旧的 room_id 收不到新场次的弹幕，要重新进房才会拿到新参数（归档规格也标着“待确认”）。
- **room_id 为空时照样连接**（E01.4 在详情没有本场 room_id 时给空字符串）；这时带房间号的聊天都会被丢掉。
- **不处理服务端的心跳回复**，也不回应 `Response` 里的 `heartbeatDuration`（录到的是 15），按固定的 10 s 发心跳。
- **不显示礼物、进场、点赞、关注、榜单**：v3 没有显示。归档 v4 解了礼物，D01.1 已决定不搬。
- **文本帧忽略**：v3 在监听器里把它当字节数组解码，类型错误被 `try` 接住，效果相同。
- 打开即就绪，每次重连都报 `DanmakuReady`，一轮失败只报一次重连（D01.1 的运行时，和 v3 一样）。

## 回归条目的覆盖

归档规格里 E01.4 留给 D01 的部分：

- REG-DOUYIN-002：签名作为参数值编码（`+`、`/` 不会变成空格），两个 webcast100 节点轮流重连。测试：地址与 v3 和录制逐字相同、`A+B/C=` 编码成 `A%2BB%2FC%3D`、重连在两个节点间交替。
- REG-DOUYIN-003：SDK 1.0.15、`need_persist_msg_count=15`、握手带 Referer、45 s 静默重连。测试：查询参数、握手头（含本地 WebSocket 服务器收到的请求）、策略的 45 s。19 位访客号在 E01.4。

## 样本

- S13-live 检查过，不需要再脱敏：录制工具（`DouyinFrameScrubber`）已经把聊天的发送者重建成只有合成的 id（同样位数的随机数字）和合成的昵称（`观众N` 或同形字符），去掉了 `Common.user`、`RoomUserSeqMessage` 的榜单和座位（观众列表），清空了其余 18 种方法（进场、榜单、粉丝团、点赞、关注等）的负载；握手的访客号、签名、Cookie 也已换掉。剩下的只有消息 id、房间号（公开）、游标、`internalExt`（服务端的时间和版本号）和公开的聊天文字、在线人数，没有头像路径、用户编号或出口地址。本模块没有改动录制文件。
- S13-vectors 全部合成，编号和昵称取自 S13-live 里已经合成过的值，头像地址、`secUid` 等是写明 `synthetic` 的假值。

## 框架层的发现（没有改）

- `dart:io` 的 `WebSocket.connect` 把传入的 `user-agent` 加在默认值后面，握手实际发出的是 `Dart/3.13 (dart:io), Mozilla/5.0 …`（本地服务器测试记下了这一点）。v3 的 `IOWebSocketChannel.connect` 走同一条路径，归档 v4 录 S13-live 时也是这样发的，抖音照常下发弹幕，所以行为与 v3 相同，没有改。所有带 UA 的平台（哔哩哔哩、抖音、SOOP、YY 等）都一样；要改应在 `live_net` 的 `connectIoSocket` 里给客户端设 `userAgent`，属于 Q01.1/M5.0，需要另行决定。

## 后续升级候选

以下会改变用户看到的数字或消息，按规则保持 v3，由用户决定是否采用：

- 在线人数优先取 `RoomUserSeqMessage.total`（精确整数），没有时再用 `onlineUserForAnchor`（与 E01.4 接口层的“精确整数优先”一致）。**已做（D01 后续升级（原 M5.F））**
- 聊天没有 `common.createTime` 时用 `eventTime`（秒）作为发送时间。**已做（D01 后续升级（原 M5.F））**
- 连接耗尽或长时间没有聊天时重新取详情，确认本场 room_id 是否变了（主播重新开播）。**已做（D01 后续升级（原 M5.F））**

（见末尾“后续升级（D01 后续升级（原 M5.F），附录 B-5）”一节。）

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 连接状态的提示文字 | M13（D01.1 的原因表） |
| 在线人数合并进直播间 | M13（`LiveRoom` 的合并规则，E05.2） |
| 抖音表情（`assets/emo/json/douyin.json`，解析在 D01.1 的 `DanmakuEmoji`） | A01.1 |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | D01 各平台完成后删除 |

## 上游核对

pure_live_TV `e1cca224` 的 `douyin_danmaku.dart` 与 v3 逐行相同，只是提示文字换成了多语言键（`danmaku_reconnecting`、`danmaku_connect_failed`，D01.1 已记录）、注释改成英文。没有可采用的修复。

## 测试

`test/sites/douyin_test.dart` 50 个用例，`live_danmaku` 共 217 个，连续跑 3 次全部通过：

| 分组 | 用例 | 内容 |
|---|---|---|
| protobuf 读取器 | 4 | 10 字节变长整数和无符号打印、超长和截断；字段号 0、坏长度、wire type 6/7、孤立的 group 结束；group 跳过、fixed32/64；最后一个值、wire type 过滤、消息合并、bool 的低 32 位、坏 UTF-8 |
| 发出的帧和握手 | 4 | 心跳与 v3、录制相同；地址与 v3、录制相同，签名编码；三种 Cookie 下的握手头与 v3 相同；ACK 写出空字段、logId 超过 2^63 |
| 录制帧（S13-live）对照 v3 | 3 | 81 帧逐条对照（78 个 ACK、215 条聊天、16 次在线人数）；ACK 与录制的发出帧相同；换 room_id 丢掉聊天 |
| 合成帧（S13-vectors）对照 v3 | 26 | 25 个向量各一个用例（4 个按差异变换），另有一个检查每个差异都还需要 |
| 连接 | 13 | 第一个节点、签名、游标、握手头、就绪和加入心跳；策略（10 s、45 s、无加入计时器、8 次）；10 s 心跳计时器和手动心跳；回放整段录制，发送和事件的先后与 v3 相同；别的房间和文本帧；带 Cookie 的握手；断线 1 s 后换到另一个节点、地址不变、重新加入；退避 1、2、2、3、3、4、4、5 s 且节点交替，之后放弃；`close` 之后没有事件、ACK 和心跳；换房间关掉旧连接并按新 room_id 过滤；参数类型；平台表登记；本地 WebSocket 服务器端到端（路径、查询参数、请求头、ACK、消息、心跳） |

另外用 15 个变异（按有符号打印 id、编码区分大小写、bool 读 64 位、不读请求头、不读 routeParams、去掉房间过滤、去掉外层 id、毫秒阈值含等号、在线人数改用 `total`、不发加入心跳、静默超时用默认值、整帧失败、ACK 省略空负载、消息只取最后一次、取值不看 wire type）检查过，每个都会让测试失败。

## 后续升级（D01 后续升级（原 M5.F），附录 B-5）

- 日期：2026-10-01（样本 2026-09-30 录制）
- 条目：B-5“在线人数优先用精确整数；聊天缺发送时间时用事件时间；连接耗尽后确认本场是否换了（主播重新开播）”。
- 新样本 `fixtures/douyin/danmaku/S13-audience`：匿名、只读、直连，同时录了 5 个直播间 150 s（详情里的在线人数 2、5、2013、9812、77726；录制程序用 `DouyinSite` 取详情，再用 `DouyinDanmakuConnection` 加一个记帧的 connector）。每个房间取前 60 s 里带聊天或在线人数的帧，只留这两种消息里解码要读的字段；聊天的发送者换成合成值（同样位数的随机 id 和“观众N”；抖音给部分观众的占位 id 111111 保留，打码的昵称换掉），聊天文字里的 @昵称换成 `@观众`；在线人数消息去掉榜单和座位。帧和 `Response` 的其他字段（请求头、logId、编码、游标、internalExt、needAck）照录制，gzip 的负载重新压缩。握手的签名、访客号和 Cookie 不保存。见 `meta.json`。门禁的 `fixture privacy` 通过。

### 1. 在线人数优先用 `total`

- 做法：`RoomUserSeqMessage.total`（字段 3）大于 0 时就用它；否则照 v3，用 `onlineUserForAnchor`（字段 10）含数字时的文字。仍报为 `onlineViewers`。
- 依据：S13-audience 五个房间的 67 条和 S13-live 的 16 条在线人数消息，`total` 都是文字四舍五入之前的数：2 和“2”、5 和“5”、1986 和“1986”、10371 和“1.0万”、77918 和“7.8万”、305503 和“30.6万”。1 万以下两者相同，1 万以上相差不超过 500（文字只留一位小数）。D01.5 当时担心的“没有小房间的样本”由 2 人、5 人的房间补上了；E01.4 接口层本来就是精确整数优先。
- 用户看到的变化：1 万人以上的房间显示精确人数（305503，以前 306000），1 万以下不变；只有 `total`、文字不含数字（如“暂无”）的消息现在也会更新人数。

### 2. 聊天缺 `createTime` 时用 `eventTime`

- 做法：`common.createTime` 大于 0 时照旧；否则用 `ChatMessage.eventTime`（字段 15），同样大于 10¹¹ 当毫秒、否则当秒。为 0、缺失、类型不对、超出 `DateTime` 范围时没有时间，聊天照样显示（`createTime` 超出范围仍丢掉整条，同以前）。
- 依据：S13-live 的 215 条、S13-audience 的 333 条聊天都没有 `createTime`，都有 `eventTime`（秒）；收到时距 `eventTime` 0.8～14.2 s，都在去重闸门的 45 s 以内。进房时服务端也没有补发更早的聊天。
- 用户看到的变化：聊天有了发送时间，去重闸门开始对抖音做时间检查，比收到时早 45 s 以上的丢掉。录制里没有这样的聊天，平时看不出区别；本机时钟与抖音相差 45 s 以上时会丢聊天，这是所有带发送时间的平台共有的情况。
- 另一个发现（与本条无关，行为不变）：抖音会把少数聊天在约 0.6 s 后用同一个 msgId 再推一次（S13-audience 333 条里有 8 条），去重闸门按 id 去掉，以前也是这样。

### 3. 主播重新开播时换到新场次

- 详情从哪里来：照抖音连接现有的写法——房间号、访客号、Cookie 都由 `DouyinSite` 放进 `DouyinDanmakuArgs`，连接不带 HTTP 客户端——在 `DouyinDanmakuArgs` 加了回调 `refresh`（`Future<DouyinDanmakuArgs?> Function()?`），和哔哩哔哩、AcFun 参数里的 `refresh` 同一种做法。`DouyinSite.getRoomDetail` 放进去的是 `() => danmakuArgs(webRid)`：新发一次详情请求，直播中且有本场 room_id 时返回新参数，否则返回 null。改动都在 `live_core` 的抖音目录（`douyin_api.dart`、`douyin_site.dart`），只是添加。应用登记平台表的写法不变。
- 什么时候查：
  - **重连耗尽时**：`LiveSocket` 连续失败 8 次放弃后，先查一次。room_id 变了就换到新场次：新签名、新游标，失败次数从头算，不报提示；没变、不在直播、查询失败或超时，就照旧以 `reconnectsExhausted` 结束（只是多等一次查询）。
  - **长时间没有任何消息时**：每分钟看一次这一分钟里有没有收到消息（任何 method 都算，包括不显示的进场、点赞；心跳回复不算）。连续 2 分钟没有就查一次；还是同一场就接着等，之后分别在再连续 4、8 分钟后查，以后每 16 分钟查一次；收到任何消息就从头算。room_id 变了就换过去，其他情况什么都不做，连接照旧。
  - 同一时间只有一次查询，两种情况同时需要时共用；每次最多等 10 s；`close` 或换房间之后回来的结果丢掉。
  - 参数里没有 `refresh`（测试或别处构造的参数）时不计时、不查，和以前完全一样。
- 依据：录到的最小房间（2 人）里，两帧消息之间最长 10.6 s，在线人数消息之间最长 67 s（原始录制 150 s），所以 2 分钟没有任何消息基本说明本场已经结束或者连着旧的 room_id。之后逐次拉长间隔，是为了主播一直不开播时少发请求（最多每小时约 4 次）。主播下播后重新开播的真实过程没有录到，用合成帧测试，**未实测**；详情返回新 room_id 由 E01.4 的样本覆盖。
- 框架的添加：`DanmakuSocketConnection.onReconnectsExhausted(session, lastFailure)`（`packages/live_danmaku/lib/src/socket_connection.dart`）。默认返回 false，照旧以 `reconnectsExhausted` 结束；平台返回 true 时由平台自己 `reopen` 或结束。目前只有抖音覆盖它。
- 用户看到的变化：主播断流后重新开播，弹幕会在 2～3 分钟内（或重连耗尽时）自动接上新场次，不再停在旧场次；界面上只是多一次“已连接”。

### 与决定的差异

- 决定只写了“连接耗尽后确认”；任务说明还要求“长时间没有任何消息”时也确认，两种都做了。“长时间”取 2 分钟，并逐次拉长，理由见上。
- 三条都不加设置。

### 测试

`douyin_test.dart` 63 个（原 50 个，加 13 个），`socket_connection_test.dart` 20 个（加 2 个），`live_core` 的 `douyin_site_test.dart` 52 个（加 1 个）；`live_danmaku` 共 1329 个，连续跑 3 次全部通过：

| 内容 | 用例 |
|---|---|
| 原有的 S13-live、S13-vectors 对照和两个回放用例（连接回放、本地 WebSocket 服务器） | 期望改为“v3 的输出加上 B-5”：没有时间的聊天取它的 `eventTime`，在线人数取 `total`（测试里注明 B-5，按帧独立读出这两个字段）；另断言 215 条聊天都有时间、16 次在线人数是 305503、305911……。`online-counts` 向量整体改写：8 条都报出，值为 `total`（v3 只报文字含数字的 5 条） |
| S13-audience：五个房间的在线人数都等于 `total`，与文字的关系如上 | 1 |
| S13-audience：333 条聊天都有 `eventTime`、收到时距它 0～15 s；去重闸门只去掉 8 条重复推送 | 1 |
| 合成帧：在线人数的取法（`total` 为 0、缺失、负数、字符串时用文字）；聊天时间的取法（`createTime` 优先，`eventTime` 为 0、缺失、字符串、超出范围、uint64 高位时没有时间）；帧里消息的计数 | 3 |
| 连接：没有 `refresh` 时不计时；安静 2 分钟后查到新场次，不报提示换过去（新签名和游标），旧 room_id 的聊天丢掉；同一场时查询间隔 2、4、8、16、16 分钟，收到消息（包括只有进场消息的帧）后重新计时；同步抛错、失败、不回答（10 s 超时）、null、空 room_id 都不影响连接；耗尽后查到新场次，接上而不结束；耗尽后同一场或查不到，照旧以 `reconnectsExhausted` 结束；查询中 `close`，结果丢掉；安静检查进行中又耗尽，共用同一次查询、不结束 | 8 |
| 框架：平台接管后 `reopen` 到别处；平台接管后自己结束 | 2 |
| `DouyinSite`：`refresh` 新发一次详情请求，直播中返回新参数（仍带 `refresh`），下播返回 null | 1 |

另外用 2 个变异检查过新代码（“查询期间已被另一处换过”不再算成功、只把显示出来的消息算作活动），都会让测试失败。

### 放到其他模块的部分

没有。换场次时界面上多出的“已连接”由 M13 的 3 s 提示去重处理（D01.1 已有）。
