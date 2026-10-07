# D01.1 弹幕框架和过滤

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `1251ad846`）
- 类型：平台（框架，本身不写任何平台协议）
- 来源：模块重构（M5 的第 0 步）：把 3.x 的弹幕接口 `lib/core/interface/live_danmaku.dart`、WebSocket 工具 `lib/core/common/web_socket_util.dart`、二进制工具和直播间控制器里的过滤逐块移到纯 Dart 包 `packages/live_danmaku`，之后 D01.2～D01.31 各平台建在它上面
- 旧编号：M5.0、T06a.1
- 相关：决定 D-001（3.x 是基线）、D-013（打码昵称不能屏蔽，D02.1 在这里的屏蔽表加了判断）、D-017（测试里定时器至少 1 秒、不访问真实平台）；各平台 [D01.2](../D01.2-哔哩哔哩弹幕/README.md)～[D01.31](../D01.31-Kick弹幕/README.md)；过滤的后续 [D02.1](../../D02-过滤和屏蔽/D02.1-打码昵称不能屏蔽/README.md)；直播间怎么用连接和过滤 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)；网络层 `LiveSocket` 在 Q01.1
- 记录：[record.md](record.md)（做法、接口对照、8 个平台的参数表、过滤规则、相似度算法的核对、有意差异；末尾两节是 2026-09-30、10-01 的模型追加和握手失败钩子）

## 目标

3.x 每个平台各写一遍连接的生命周期（`_generation`、`_stopped`、把四个回调置空），写法不一，Twitch、SOOP 还漏了“再次 start 先关旧连接”；过滤规则写在 GetX 的直播间控制器里，测不了；相似度用的 fuzzywuzzy 是 GPL-2.0，不能随 AGPL-3.0 的应用发布。做完以后：

- 所有平台共用一个连接接口（事件流 + `connect`/`close`），生命周期在基类里做一次：`close` 返回后绝不再有事件，晚到的定时器和请求自动作废；
- WebSocket 平台只写“地址、加入包、解一帧、心跳帧”四样，重连、退避、心跳、无消息检测、加入超时由运行时统一做（参数和 3.x `WebScoketUtils` 一样）；
- 过滤（去重闸门、屏蔽、重复合并、相似度）是纯逻辑，规则和默认值与 3.x 相同，直播间、多画面、录制弹幕三处用同一个；
- 相似度换成自己写的 `partialRatio`，分数与 3.x 用的 fuzzywuzzy 完全一样。

## 3.x 和现状

| 方面 | 3.x（`git show v3.2.11:lib/...`，文件:行） | 现在（`packages/live_danmaku/lib/src/`，文件:行） | 要做到 |
|---|---|---|---|
| 连接接口 | `LiveDanmaku`（`core/interface/live_danmaku.dart:4`）：四个可写回调 `onMessage`（`:5`）、`onReconnect`（`:9`）、`onClose`（`:12`）、`onReady`（`:13`），`start(args)`、`stop()`（`:37`），原因是写死的中文 | `DanmakuConnection`（`connection.dart:138`）：`events` 流 + `connect`（`:160`）、`heartbeat`（`:165`）、`close`（`:169`）；事件 `DanmakuReady`（`:57`）、`DanmakuReceived`（`:73`）、`DanmakuReconnecting`（`:86`，带 `DanmakuInterruption` `:24`）、`DanmakuClosed`（`:108`，带 `DanmakuCloseReason` `:37`）；状态 `DanmakuStatus`（`:5`）；`DanmakuStartFailure`（`:176`） | 原因带类型，文字由应用给（`apps/pure_live/lib/shared/rooms/room_texts.dart:171`、`:178`）（做到） |
| 生命周期 | 每个平台自己写；`stop` 后靠控制器的会话令牌兜底（`modules/live_play/controllers/danmaku_controller.dart:247` `_acceptsCallback`） | `DanmakuConnectionBase`（`connection_base.dart:16`）：每次 `connect`（`:54`）是一个 `DanmakuRun`（`:97`），平台只通过它上报（`ready` `:114`、`message` `:122`、`reconnecting` `:127`、`markDisconnected` `:135`、`closed` `:141`、可取消的 `delay` `:152`）；`close`（`:75`）、下一次 `connect`、最终关闭后这个 run 失效 | 停止后没有事件、再次连接先关旧的（做到） |
| 文字清理 | 没有 | `cleanDanmakuText`（`connection_base.dart:167`）：每条消息在 `DanmakuRun.message` 里去掉 U+FFFC 这类占位字符（文字、昵称、粉丝牌名、醒目留言），`aadad46ef` 加的 | 字体画成方框的字符不再出现（做到） |
| WebSocket 运行时 | `WebScoketUtils`（`core/common/web_socket_util.dart:73`）：连接超时 10 s（`:170`）、关闭等 2 s（`:113`）、最多 8 次（`:124`）、退避 1 s 起（`:112`） | `DanmakuSocketConnection`（`socket_connection.dart:122`）建在 `live_net` 的 `LiveSocket` 上；平台写 `target`（`:144`）、`onOpen`（`:150`）、`onData`（`:154`）和心跳帧；`DanmakuSocketPolicy`（`:15`，默认 退避 1 s `:22`、连接超时 10 s `:23`、关闭 2 s `:24`）；`DanmakuSocketTarget`（`:88`）；`DanmakuSocketSession`（`:223`：`send`、`ready`、`reconnect` `:281`、`reopen` `:291`）；加入超时默认直接重连（`onJoinTimeout` `:164`） | 参数和 3.x 一样（做到） |
| 握手被拒 | 没有（只能按普通断线重试到用尽） | `DanmakuHandshakeFailure`（`socket_connection.dart:59`，`refused`、`statusCode`）和 `onHandshakeFailure` 钩子：平台可以换请求头再握手（附录 B-1，猫耳 FM 用） | 做到（`f12bf0f8c`） |
| 平台表 | `LiveSite.getDanmaku()`，没有弹幕的平台返回 `EmptyDanmaku`（`core/danmaku/empty_danmaku.dart:9`） | `DanmakuRegistry`（`registry.dart:45`，构造时检查平台 id，`supports` `:75`）、`EmptyDanmakuConnection`（`:13`）；应用在 `apps/pure_live/lib/app/platforms.dart:196` 的 `buildDanmakuRegistry` 登记 29 个平台（`:201-239`），CC、映客、小红书、微博、LiveMe、TikTok、IPTV 不登记（注释 `:190-195`） | 做到 |
| 二进制工具 | `core/common/binary_writer.dart`、`core/common/utils/list_util.dart:3` | `BinaryWriter`（`binary.dart:10`）、`BinaryReader`（`:66`）、`ListUtil`（`:137`）；protobuf 读写 `codec/protobuf.dart`（`ProtoMessage` `:27`、`ProtoWriter` `:162`，抖音、AcFun 共用，`54baa1109`） | 做到 |
| 去重闸门 | `danmaku_message_gate.dart:9`（45 s、10 分钟、2.5 s） | `DanmakuMessageGate`（`filters/message_gate.dart:24`）：规则同 3.x；另加补回消息 `replayed` 放宽到 135 s、醒目留言到 `endTime` 前不按年龄丢（附录 B-22、B-26，`f7f0922d3`） | 做到 |
| 屏蔽 | `DanmakuController._isBlocked`（`danmaku_controller.dart:252`）、`_refreshFilters`（`:259`）：名字整名相同、文字包含屏蔽词，都去空白转小写 | `DanmakuBlockList`（`filters/block_list.dart:13`）：同 3.x；D02.1 起打码昵称（`BilibiliDanmakuProtocol.isMaskedName`）不进屏蔽集合（`:20-22`） | 做到；打码昵称见 D02.1 |
| 重复合并 | `repeated_danmaku_filter.dart:11`（默认关，窗口 5 s，1～30 s） | `RepeatedDanmakuFilter`（`filters/repeated_filter.dart:18`） | 做到 |
| 相似度 | `danmaku_similarity_filter.dart:9`，打分用 fuzzywuzzy 1.2.0（GPL-2.0） | `DanmakuSimilarityFilter`（`filters/similarity_filter.dart:18`）；`partialRatio`（`filters/partial_ratio.dart:30`，对齐 `_alignments` `:49`、`_lcs` `:124`），30 万对随机文本与 fuzzywuzzy 分数全部一致 | 分数相同、许可证干净（做到） |
| 过滤链 | `_installCallbacks`（`danmaku_controller.dart:191`）：闸门 → 屏蔽 → 重复 → 相似度（本地消息不比） | `DanmakuMessageFilter`（`filters/message_filter.dart:61`，`accepts` `:104`）同顺序，只过滤聊天；`DanmakuFilterSettings`（`:11`）对应 3.x 的 8 个设置；改设置下一条就生效 | 做到 |
| 状态提示去重 | `_addStatusMessage`（`danmaku_controller.dart:284`）：同一句 3 s 内一次 | `DanmakuNoticeThrottle`（`filters/notice_throttle.dart:4`） | 做到 |
| 表情表 | `core/emoji/models/unified_emoji_model.dart:4`、`plugins/emoji_manager.dart` | `DanmakuEmoji`（`emoji.dart:16`）、`danmakuEmojiAssets`（`:139`）：只做解析，图片和图集在应用（`apps/pure_live/lib/shared/danmaku/emotes.dart`） | 做到 |
| 发送者 | 没有 | `DanmakuSender`（`sender.dart:8`，头像地址，D01.32 加的，放在聊天消息的 `data` 里） | 见 D01.32 |

应用里用这个框架的三处：直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart`（`_filter` `:102`、`_statusLines` `:103`、`_reloadFilter` `:340`、`_syncDanmaku` `:809`、`_onDanmaku` `:848`、`_onMessage` `:868`）、多画面 `features/multiview/logic/multiview_controller.dart:164`、录制弹幕 `app/recording.dart:53`。

## 结果

- 做法（详见 [record.md](record.md)“做法”“公开接口”）：连接改成事件流加 `connect`/`close`；基类按 run 失效；WebSocket 运行时直接用 Q01.1 的 `LiveSocket`，不写第二套；各平台不同的只有 `DanmakuSocketPolicy`（心跳、无消息超时、加入超时）和 `DanmakuSocketTarget`（地址、请求头、子协议）；过滤从直播间控制器移出来；表情只移模型和解析。从归档 v4 只借工程写法（密封事件、按 run 失效、假连接器），没有搬它的新行为（后台 isolate、抽样、20 秒启动超时即终态等）。
- 和 3.x 的有意差异 11 条（record“与 v3 的有意差异”）：回调改事件流、停止后绝无事件、再次连接一定先关旧的、所有平台 `connect` 都等第一次尝试结束（3.x SOOP 不等）、最终关闭后晚到的上报丢弃、没有地址时以 `connectionFailed` 结束（3.x 一直停在“连接中”）、加入计时器每次失败都停、相似度自己实现、二进制工具两处小改、表情表类型不对当空、平台表检查 id。保留不改的 3.x 行为 4 条（一轮失败只提示一次、每次重新加入都发就绪、YY 握手超时两条提示、哔哩哔哩认证前就发心跳）。
- 后来加的（都只做添加，默认行为不变）：
  - 2026-09-29 `54baa1109`：protobuf 读取挪到 `src/codec/`，抖音和 AcFun 共用。
  - 2026-09-30 `1ceb4f290`：`LiveMessageType` 末尾加 `retraction`（`LiveRetraction`：按消息、按用户、全部）和 `notice`（`LiveNoticeKind`），去重闸门的键加上撤回目标。
  - 2026-10-01 `f12bf0f8c`：握手失败钩子（附录 B-1）；`f7f0922d3`：补回消息 `replayed` 和醒目留言的年龄规则（B-22、B-26）；`aadad46ef`：`cleanDanmakuText`；`fffd28b31`：消息带表情图片（`LiveMessage.emotes`）。
  - 2026-10-02 `7f8ee2553`：来源房间、名字颜色和徽章（E06.1）；`40dc22279`：屏蔽表忽略打码昵称（D02.1）；`2eea8022a`：`DanmakuSender`（D01.32）。
- 提交：`1251ad846`（2026-09-29，`feat(live_danmaku): danmaku framework refactored from v3`）。
- 测试：框架部分现在 124 个（当时 104 个）：`connection_test.dart` 17（当时 16）、`socket_connection_test.dart` 28（当时 18，B-1 加了 8 个，之后又加 2 个）、`binary_test.dart` 14、`message_gate_test.dart` 20（13，B-26 +5 等）、`repeated_filter_test.dart` 7、`similarity_test.dart` 16（含 40 组 fuzzywuzzy 分数）、`message_filter_test.dart` 14（13，D02.1 +1）、`emoji_test.dart` 8（7）；另有 `exact_websocket_test.dart` 28（D01.7 加的保留大小写握手，YY、SOOP 共用）、`emotes_test.dart` 5（平台给的表情图片）。都在 `packages/live_danmaku/test/`。

## 性能任务：测量

不是性能任务。相似度过滤每条消息最多和最新 96 条比较（`similarity_filter.dart`），去重闸门最多记 4096 条、重复合并最多 1024 条，都有上限。

## 验证

- 自动测试：上面的 124 个；`cd packages/live_danmaku && dart test`。`socket_connection_test.dart` 里有一个真实的本地 WebSocket 服务器（连上、回 403、换 Cookie 再连）。相似度的分数用 fuzzywuzzy 1.2.0 在临时目录做过 30 万对差分（record“过滤”），测试里写死 40 组。
- 真实接口：框架本身不连平台；各平台任务各自跑过真实接口（见 D01.2～D01.31 的“验证”）。
- 真机：没有单独的真机记录。框架通过各平台间接用到：[S02.2 冒烟](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)（2026-10-02，构建 `288fec0ec`）进直播间看到飞行弹幕和系统提示。断网重连、屏蔽和过滤是 [CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 2 节第 1 条、第 4 条，还没有填结果；断网重连那一步排在 S02.6 第 1 阶段。

## 留下的问题

- `LiveMessageType.gift` 的注释还写“Gift (not shown yet)”（`packages/live_core/lib/src/live_message.dart:8`），礼物早已在聊天列表单独一行显示（B-21，C01.2）：注释过时，没有任务；下次改这个文件时顺手改。
- `apps/pure_live/lib/app/platforms.dart` 和 `packages/live_danmaku/lib/live_danmaku.dart:1-5` 的注释还用旧编号（M5、M5.1–M5.8、M5.17/M5.18），按注释找文档要先查 [MAPPING.md](../../../MAPPING.md)：和其他组一样，Z 组一次性替换。
- 网易 CC：3.x 把 CC 和 IPTV 一起排除，不连也不提示（`danmaku_controller.dart:327`）；4.x 只排除 IPTV（`room_controller.dart:811`），CC 没登记弹幕，会提示一次“平台不提供弹幕”。行为差别很小，算可以接受；CC 弹幕要登录后再试（附录 C-22，未排）。
- 头像暂时借用 `LiveMessage.data`（`DanmakuSender`），以后更多平台给头像时应在 `LiveMessage` 上加正式字段：D01.32 记录“需要维护者决定的”第 1 条，没有任务。
- 握手被拒时 `connectExactWebSocket`（YY、SOOP）拿不到 HTTP 状态码（record 末节“没改的地方”）：现在没有平台需要，不做。
