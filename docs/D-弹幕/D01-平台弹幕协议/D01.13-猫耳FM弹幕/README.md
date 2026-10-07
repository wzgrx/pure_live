# D01.13 猫耳 FM 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-09-29，提交 700066213）
- 类型：平台
- 来源：已批准升级 13-2“猫耳弹幕（归档 v4 已实现）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 有猫耳这个平台但没有弹幕，这是新增功能。后续的 B-1（握手被拒换会话）、B-9（付费提问、清屏、通知、礼物）是同一升级表附录 B 的条目
- 旧编号：M5.12、T06a.13
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（握手被拒的钩子 `onHandshakeFailure` 就是为本平台的 B-1 加的）；Brotli 解码 [Q01.2](../../../Q-网络和代理/Q01-请求和编码/Q01.2-Brotli解码/record.md)；平台本身和弹幕参数 [E02.4](../../../E-直播平台/E02-其他国内平台/E02.4-猫耳FM/README.md)；多画面接入 [N01.1](../../../N-多画面和投屏/N01-多画面/N01.1-多画面/record.md)；握手的 User-Agent [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)（本平台用默认的 `dart:io` 握手，受它影响）；决定 D-017（测试不访问真实平台、样本时间固定）；详细记录 [record.md](record.md)

## 目标

猫耳 FM（语音直播）直播间能看到聊天、热度和真实在线人数：列表和详情只有热度 `score`，`online` 恒为 0，真实在线人数只在弹幕里。同时修掉归档 v4 实现的 4 个问题（解压炸弹、任何 `wss` 地址都发会话 Cookie、一行坏数据丢整行、被拒后还要等退避）。后来（B-9）把付费提问显示成醒目留言，管理员清屏变成撤回，贵族开通和 PK 显示成通知，礼物进聊天列表；（B-1）会话过期、握手被拒时自动换会话重连。

## 协议要点

代码都在 `packages/live_danmaku/lib/src/sites/missevan.dart`（下面只写行号）。

| 项 | 内容 |
|---|---|
| 游客会话 | 每次 `connect` 先 `GET https://fm.missevan.com/api/user/info`（`MissevanApi.guestSession`），读 `Set-Cookie` 开头的 `FM_SESS=`（`session` :206，值只收 RFC 6265 的 cookie-octet；`FM_SESS.sig` 不要；有效 3 天）；请求头用参数里的 API 请求头，不跟随跳转；最多 3 次（`sessionAttempts` :712，间隔 0.5 s、1 s），每次最多 5 s（`sessionTimeout` :715）；都拿不到以 `credentialsUnavailable` 结束、不开连接（`_session` :748、`target` :733～743）。没有会话时握手回 HTTP 403 |
| 地址 | 详情给的 `wss://im.missevan.com/ws?room_id=<房间号>`（`MissevanDanmakuArgs.url`）；`endpoint`（:186～202）只认 `wss`、主机是 `missevan.com` 或其子域、没有用户信息的地址；没有 `room_id` 的补上（否则握手 400），`room_id` 是别的房间或查询串坏掉的换成 `wss://im.missevan.com/ws?room_id=<房间号>`（否则加入回 500030004）；房间号不合 `MissevanApi.idPattern` 时直接 `connectionFailed`（:735～737），不发请求 |
| 握手 | API 请求头（`referer`、`origin: https://fm.missevan.com`、UA `Mozilla/5.0`）去掉原有的 Cookie，加 `cookie: FM_SESS=<值>`（`handshakeHeaders` :217）；默认 `dart:io` 握手；按平台 `missevan` 走代理（`platforms.dart:219` 传 `proxy`、`connector`） |
| 帧 | 二进制：第 1 字节 1 表示 Brotli（`brotliFlag` :109），第 2～4 字节是解压后长度（小端 24 位），第 5 字节起是 Brotli 流（`headerLength` :112）；`text`（:249～261）用 `brotliDecode(..., maxOutput: 长度)`，超过就停，长度不等、标志不是 1、长度不大于 4、流解不开的帧丢掉；UTF-8 坏字节换成 U+FFFD。文本帧照原样按 JSON 读。解出 JSON 对象或对象数组 |
| 加入 | 打开后发文本 `{"action":"join","uuid":<随机 v4 UUID>,"type":"room","room_id":<数字>}`（`join` :226、`onOpen` :783～790）；只认这次 `uuid` 的 `room`/`join` 应答（`decode` :308～313），`code` 0 且未就绪时报就绪；这次 `connect` 加入过之后重新加入带 `"reconnect":1`；加入超时 5 s（`joinTimeout` :106），超时换连接、不单独提示 |
| 被拒 | 应答 `code` 不是 0：标为未加入，重新取游客会话后 `reopen`，不提示（`_refused` :815～838）；每次 `connect` 最多 3 次（`maxRejoins` :718），第 4 次以 `connectionFailed` 结束，详情写 `Join refused: <码> <原因>`；被拒后拿不到会话以 `credentialsUnavailable` 结束 |
| 心跳 | 30 s（`heartbeatInterval` :99）发文本 `❤️`（`heartbeat` :102、`heartbeatFrame` :866），连上就按间隔发，服务端约 50 ms 回显，回显不上报；无消息超时取框架默认 max(3 × 30 s, 90 s) = 90 s（`socketPolicy` :706～709 只写心跳和加入超时）；服务端约 120 s 收不到心跳会断开 |
| 重连 | 框架默认（`DanmakuSocketPolicy`，`packages/live_danmaku/lib/src/socket_connection.dart:15～25`）：只有一个地址，间隔 2、3、4、5、6、6、6、6 s，连续 8 次失败以 `reconnectsExhausted` 结束，收到任何消息清零；重连沿用会话 |
| B-1 握手被拒 | 握手回 401、403（`sessionRefusals` :723）时 `onHandshakeFailure`（:847～852）重新取会话，把新 Cookie 交给下一次握手；每轮连续失败只换一次，连接打开过才重新计（`onOpen` 里清 `sessionRenewed`）；拿不到会话以 `credentialsUnavailable` 结束；其他握手失败（连不上、超时、400、404、5xx）不换 |
| 聊天 | `message`/`new` 和 `message`/`danmaku`（付费弹幕，网站当带气泡的飞行弹幕）都是聊天（`chat` :606～630）：文字 `message` 去首尾空白，空的不报；用户名 `user.username`、用户 id `user.user_id`；消息 id `msg_id`（不加前缀）；时间 `time`（毫秒，录到的聊天都没有）；颜色白色；等级是 `titles` 里 `type` 为 `level` 的 `level`，粉丝牌是 `type` 为 `medal` 的 `name`、`level` |
| 人数 | `room`/`statistics`（约每 2 分钟一条）：`score` → 热度 `popularity`、`online` → 在线人数 `onlineViewers`（`audience` :636～652），整数或数字文字、不小于 0 |
| 房间过滤 | 带 `room_id` 且不是本房间的对象跳过（:315～316），没有 `room_id` 的算本房间 |
| B-9 付费提问 | `question`/`ask` → 醒目留言（`question` :352）：id `question_id`，用户名和头像取外层 `user`，没有时取 `question` 里的，头像只收 https；文字 `question.question`；价格 `question.price`（整数，不小于 0），`priceText` 写 `<价格> 钻`（:377）；开始 `created_time`，没有用收到的时间；显示 60 s（`questionDuration` :118，:379）；颜色留空 |
| B-9 清屏 | `admin`/`message_clear` → 撤回（`retractions` :390）：`opt` 1 一条 `LiveRetraction.all()`，`opt` 2 按 `msg_ids` 每个 id 一条（去重、跳过空的）；其他 `opt` 不报 |
| B-9 通知 | `noble`/*（开通、续费、团播的 `cross_*`，`noble` :419，改成第三人称“观众甲 开通了神话贵族”）、`pk`/*（`pk` :447，固定文字 `pkLines` :128、按结果 `pkResults` :137；邀请超时只在邀请方显示）、`global_pk`/*（幻影 PK，`globalPk` :465，`globalPkLines` :141、`globalPkResults` :165）、`team_pk`/*（`teamPk` :480）、花神赐福（`raid` :488，只在 `raidEvents` :168 的事件里）→ 通知；提示是 HTML，`plainText`（:501）去掉灰色“详情”类链接提示、图片和标签，解码实体，合并空白 |
| B-9 礼物 | `gift`/`send` → 礼物（`gift` :518、`MissevanGift` :16）：id `gift_id`、名字、数量 `num`（至少 1）、单价（钻石）、图标（https）；幸运礼物把送出的那件放 `luckyGift`；文字 `<礼物名> ×<数量>`；消息 id `oid`，连击的全 0 `oid` 不填。`gift`/`cross_send`（送给团播里别的房间）不报 |
| 不报的 | `user`/`connect`、进场、榜单、全站通知 `notify`/*、`question`/`answer`、`super_fan`/* 等 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | 3.x 有猫耳这个平台但没有弹幕：`MissevanSite.getDanmaku() => EmptyDanmaku()`（`core/site/missevan/missevan_site.dart:38`）；直播间见到 `EmptyDanmaku` 时只提示一次 `remote_danmaku_not_integrated`“此平台的远端弹幕尚未接入……”（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `MissevanDanmakuConnection`（`missevan.dart:687`）继承 `DanmakuSocketConnection`；协议 `MissevanDanmakuProtocol`（:96）；应用登记在 `apps/pure_live/lib/app/platforms.dart:219` | 有聊天、热度、在线人数（已做） |
| 在线人数口径 | 人数设置页把猫耳列为只有热度（`modules/settings/pages/audience_metric_settings_page.dart:20`，说明“公开 score 是平台热度，未提供独立的并发在线人数”） | `packages/live_core/lib/src/audience.dart:271～275` 猫耳是 `roomRealtime`：列表卡片“优先真实在线”时显示待定，进房后由弹幕的 `online` 填上；不开这个设置时照旧显示热度 | 能看真实在线人数（REG-MISSEVAN-002，已做） |
| 等级 | 3.x 长按弹幕的面板在 `userLevel` 不为空时显示 `Lv.N`（`modules/live_play/widgets/danmaku/danmaku_message_actions.dart:19`），但猫耳没有弹幕 | 聊天带 `userLevel`（`missevan.dart:624`），但 4.x 的长按面板 `RoomMessagePanel`（`apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:112～150`）只显示“名字：内容”，不显示等级；粉丝牌在聊天列表里显示（`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:721～725`） | 等级见“留下的问题” |
| 醒目留言、撤回、通知、礼物 | 无 | 直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:893～910` 分别进醒目留言、`chat.retract`、通知行、礼物行（礼物受“显示礼物”开关控制，B-21） | 已做 |
| 清屏“全部” | 无 | `LiveRetraction.all()` 交给 `ChatFeed.retract`（`apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart:154～159`），只去掉聊天行，状态行、通知、礼物保留，和网站只清聊天一致 | 已做 |

## 结果

- **提交**：700066213（2026-09-29，首次实现：连接、游客会话、加入、心跳、聊天和人数）；d3409dccf（2026-10-01，B-1 握手被拒换会话、B-9 付费提问、清屏、通知、礼物）。之后的消息文字规范化（去掉占位字符、保留零宽空格）属于 [S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md)。
- **和归档 v4 的对照**：`fixtures/missevan/danmaku/v4_expected.dart` 把 v4 的协议搬成独立程序（`package:brotli` 换成 `brotliDecode`），对 S06、S07、S08 写下冻结输出 `expected.json`。S06-live（房间 246709466）11 个收到的帧一致（3 条聊天、热度 105019、在线 22）；S07-brotli（房间 180370487，服务端真正压缩过的帧）19 个收到的帧一致（9 条聊天、热度 6374、在线 9）；S08-synthetic 15 组 72 帧里 10 组一致、5 组是有意差异。B-9 之后“不报礼物”这条差异取消，S08 两组带礼物的合成帧和 v4 相同。
- **有意差异**（record.md“与归档 v4 的差异”15 条）：消息 id 不加 `missevan:` 前缀；只认这次 `uuid` 的应答；文本是列表或对象时不报、粉丝牌名坏了只丢名字；时间越界只让这一行没有时间；解压以帧头长度为上限；地址只认猫耳主机并补 `room_id`；会话请求和握手都带 API 请求头；加入和心跳用文本帧；重新加入带 `reconnect: 1`；加入超时 5 s；心跳连上就发；被拒换会话立刻重开；会话请求失败再试两次；结束原因用 D01.1 的类型。
- **样本**：`fixtures/missevan/S05-user-info`（游客会话回答）；`fixtures/missevan/danmaku/` 下 S06-live（归档的真实录制）、S07-brotli（2026-09-28 补录、已脱敏并重新压缩）、S08-synthetic（`synthetic_cases.py` 用参考编码器生成，15 组）、S09-events（B-9 的 26 帧，2026-09-30 两批录制里挑出、已脱敏）。
- **测试**：`packages/live_danmaku/test/missevan_test.dart` 现在运行 71 个用例（源码里 55 个 `test(`，其中 3 个在循环里：S06/S07 对照 v4 各一个、S08 每组一个共 15 个、回放 S06/S07 各一个）；首次实现时 54 个，B-1、B-9 后 71 个（+6、+11）。框架 `test/socket_connection_test.dart` 为 B-1 加了 8 个；`live_core` 的 `missevan_api_test.dart` 改了 REG-MISSEVAN-002 那一条断言。首次实现时做过 21 种变异、B-1/B-9 做过 20 种，都能被测试发现。

## 验证

- 自动测试：`missevan_test.dart` 分四组——协议（会话、地址、请求头、加入、心跳、帧格式、`audience.dart` 是 `roomRealtime`）、录制帧对照 v4（S06、S07 逐帧）、合成帧对照 v4（S08 每组一个）、连接（会话重试和 4 种拿不到会话的情形、加入应答和超时、被拒换会话和第 4 次结束、退避 2～6 s、换房间、关闭后无事件、本地 WebSocket 服务器端到端：查询参数、Cookie、加入、S07 的真实压缩帧、心跳回显）；B-9 11 个（S09 26 帧逐帧和网站显示一致、醒目留言每个字段、清屏、贵族、三种 PK、礼物）；B-1 6 个（403、401 换会话、每轮只换一次、其他失败不换、换不到会话结束、本地服务器对旧 Cookie 回 403 后换会话加入成功）。测试时间都固定，在 +30 天、+1 年、+5 年下运行都通过。
- 真实接口：2026-09-28（UTC 20:20～20:55）匿名游客直连：进 869222422 383 ms 就绪，115 s 收到热度 21514、在线 10；进 180370487 369 ms 就绪，130 s 收到 11 条聊天，65 s 收到热度 414、在线 6。2026-09-30 两批各连推荐前 30 个房间（900 s、840 s），共 60 个房间会话：聊天 4886、礼物 1147、提问 7、PK 和幻影 PK 1000 多条、贵族续费 1、清屏 0；本实现逐帧解码全部录制，没有异常。没实测到的（清屏、贵族开通、团播 `cross_*` 和 `team_pk`、邀请 PK 被拒或超时）用合成帧。
- 真机：没有单独的真机记录。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列了哔哩哔哩、斗鱼、虎牙、抖音、快手，没有猫耳；[S02.2](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)、[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 和 [E02.4](../../../E-直播平台/E02-其他国内平台/E02.4-猫耳FM/README.md)（“没有在 K90 上专门看过”）都没有猫耳弹幕的结果。登记表是“完成”，按 D-029 这个平台的弹幕还算“没验证”。

## 留下的问题

- 进房后最迟约 2 分钟才有第一个真实在线人数（`room/statistics` 每 120 s 一条，实测第一条在加入后 15～65 s 不等），之前卡片“优先真实在线”时显示待定：平台就是这样发的，没有任务。
- 付费提问的回答、取消（`question`/`answer`）不会提前撤下醒目留言，固定显示 60 s：消息模型没有“提前结束醒目留言”，没有任务；要做需要先在 `LiveSuperChatMessage` 上加结束事件，再开任务。
- 幻影 PK 的提示是主播口吻（“你在幻影PK中击败……”），网站给观众看的也是这句，照原文显示：不改，没有任务。
- 聊天带等级 `userLevel`，3.x 的长按面板会显示 `Lv.N`，4.x 的 `RoomMessagePanel`（`message_panel.dart:112～150`）不显示，所有带等级的平台都一样：没有任务，归 A08 弹幕界面，要不要加回需要维护者决定（A07.6 确认的长按面板设计里没有等级一行）。
- 会话中途过期的情况（连续挂着超过 3 天）已由 B-1 处理；清屏“全部”会不会多清通知的问题已由聊天列表只清聊天行解决（`chat_feed.dart:154～159`），都不再是问题。
- 握手的 User-Agent 去掉 `Dart/<版本>` 前缀要先在 K90 上逐平台验证：[Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)。
- 真机上没看过：进一个在播的猫耳直播间，看聊天、粉丝牌、热度和约 2 分钟后的在线人数、醒目留言（付费提问）、礼物行：没有单独的任务，建议加进真机清单第 2 节（归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 一类的补验）。
