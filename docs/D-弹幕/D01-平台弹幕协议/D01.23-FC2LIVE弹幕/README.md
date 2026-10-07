# D01.23 FC2 LIVE 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 26-3“评论（弹幕），并用它更新人数”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 FC2 评论（`EmptyDanmaku`），这是新增功能，规格来自归档 v4 的实现和录制、FC2 网页客户端 `liveView.bundle.js`
- 旧编号：M5.22、T06a.23
- 相关：决定 D-001（3.x 是基线，没有的功能按已批准升级做）、D-017（测试不访问真实平台）；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、授权 `Fc2LiveSite.controlGrant` 和控制连接 `Fc2LiveControl.connect` [E03.13 记录](../../../E-直播平台/E03-海外平台/E03.13-FC2LIVE/record.md)；同一类“socket 地址要现取”的 [D01.12 TwitCasting](../D01.12-TwitCasting弹幕/README.md)；3.x 存下的旧公告由 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md) 导入时清掉，真机核对在 [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)；FC2 播放接手的余项在 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/brief.md)（第 6 阶段“FC2”，与弹幕无关）；详细记录 [record.md](record.md)

## 目标

FC2 LIVE（日本个人直播）直播间能看到评论，在线和累计人数随评论流更新；照网页的屏蔽表（NG 表）隐藏广告和骚扰评论；修掉归档 v4 实现把发送者的 `hash` 当消息 id（接到 D01.1 的去重闸门后同一个人 10 分钟内只显示第一条）、用户 id 每条都变、普通断线后用过期授权重连等问题。3.x 普通房间的公告“FC2 远端聊天尚待接入……”同时去掉。

## 协议要点

| 项 | 内容 |
|---|---|
| 授权 | 评论走 E03.13 的媒体控制 socket。每次握手前取新授权（约一分钟失效、只能连一次）：`POST https://live.fc2.com/api/memberApi.php`（`channel=1&profile=1&user=1&streamid=<频道号>`），在播才再 `POST /api/getControlServer.php`（逐项同 3.x），得到 `url`、`control_token`、`orz_raw`。交给 `LiveSocket` 的是名义地址 `https://live.fc2.com/api/getControlServer.php?channel_id=<频道号>`（`Fc2LiveDanmakuProtocol.endpoint`），本平台的握手函数（`_Grants.connect`）每次先取授权再连；第一个授权在开始时取（`_Grants.begin`），第一次握手直接用 |
| socket | `wss://<节点>.live.fc2.com/control/channels/<频道号>?control_token=…`，请求头 `Origin: https://live.fc2.com`、Chrome 140 UA、`Cookie: l_ortkn=<orz_raw>`；默认握手 `Fc2LiveControl.connect`（`dart:io`，每 15 s 一次 WebSocket ping）；按平台 `fc2live` 和授权给的地址选代理；失败详情里的 `control_token`、`l_ortkn` 换成 `…`（`redact`） |
| 帧 | 文本帧，每帧一个 JSON 对象 `{"name": …, "arguments": {…}}`，回答另有 `id`；不是对象、没有 `name`、超过 2 MiB（`Fc2LiveControl.messageLimit`）的丢掉；字节帧按 UTF-8 解 |
| 加入和心跳 | 收到 `connect_complete` 就绪（每个 socket 一次）；加入超时 8 s，超时换新授权重连；从 socket 打开起每 30 s 发文本帧 `{"name":"heartbeat","arguments":{},"id":<n>}`（编号在一次连接里递增，跨 socket 不重置），服务端回 `_response_`；无消息 90 s（框架默认） |
| 评论 | `comment` 的 `comments[]`：丢掉 `history: 1`（加入时重推的 30 条）、系统评论（`system_comment`：打赏 `tip`、礼物 `gift`、进出场等）和屏蔽表命中的；文字、名字按网页去 HTML 标签并解码字符引用；`anonymous` 或空名写平台给的 `[anonymous]`；用户 id 照网页 `decryptUserId` 解成稳定的用户键（`a` 加一位数字开头、不超过 12 个字符的是 FC2 账号编码，其他写 `id_<原值>`）；颜色按网页评论列表的 8 色（`red` #e63d37、`pink` #e13396、`orange` #dc7611、`yellow` #e1ac00、`green` #33bd4a、`cyan` #1b94c7、`blue` #4472f3、`purple` #b84ac5，`black` 和其他是白色）；时间是 `timestamp`（毫秒）；没有消息 id（`hash` 是发送者的） |
| 人数 | `user_count` 只带变化的字段，保留上次的值：`pc_user_count + mobile_user_count` → 在线，`pc_total_count + mobile_total_count` → 累计，变了才报 |
| 屏蔽表 | 加入时服务端推 `ng_comment`（实测 340 条）：屏蔽词（`channel_keyword`、`admin_keyword`、`keyword`）和屏蔽用户（`channel_user`、`admin_user`、`share_low`、`share_high`、`share_hyper`、`user`）；`admin_ng` 决定用不用 FC2 的表，`shared_ng_level` 1 加 `share_low`、2 再加 `share_high`；名字或文字含屏蔽词、发送者在屏蔽用户里（账号按用户键、其他按 `orz_token`）就隐藏；主播自己的评论只查 `keyword`；表在一次连接里一直保留 |
| 换连接 | `control_disconnection`（4500 授权失效、1000 直播结束、4502/4511 下线、4504 被踢等）换新授权重连并提示；`move_server` 立刻、无提示地换新授权（不直接连它给的 `url`）；这两种和加入超时连环超过 8 次（中间没有心跳回答）以 `reconnectsExhausted` 结束，一次 `status` 为 0 的心跳回答清零 |
| 开始失败 | 频道号不合规：`connectionFailed`（`Not an FC2 channel`），不发请求；授权请求抛出不可重试的错误（不存在 `NotFound`、没在播 `StreamUnavailable`、受限 `NeedsLogin`、看不懂 `ApiChanged`、`RiskControl`）以 `connectionFailed` 结束，只发了 `memberApi`；网络、限流按握手失败走框架退避（2～6 s，最多 8 次）；下播后重连时 `memberApi` 说未开播，8 次后 `reconnectsExhausted` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 评论 | `Fc2Site.getDanmaku() => EmptyDanmaku()`（`core/site/fc2live/fc2_site.dart:42`）；进房时弹幕区加一条状态“此平台的远端弹幕尚未接入；可在设置中开启本地互动，仅在本机显示。”（`modules/live_play/controllers/danmaku_controller.dart:146～150`，键 `remote_danmaku_not_integrated`） | `Fc2LiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/fc2live.dart:431`）：`target`（:467）检查频道号、取第一个授权，`onData`（:484）按 `name` 分发，`_renew`（:534）换连接并计数，`_Grants`（:580）的 `begin`（:597）和 `connect`（:619）取授权和握手；应用登记在 `apps/pure_live/lib/app/platforms.dart:230`（传 `LiveHttp` 和代理，不传 `connector`） | 有评论和人数（已做） |
| 协议 | 无 | `Fc2LiveDanmakuProtocol`（:30）：心跳 30 s（:33）、加入超时 8 s（:37）、匿名名（:42）、颜色表（:46）、心跳帧（:62）、名义地址（:67）、`redact`（:84）、`comments`（:115）、`comment`（:140）、用户键 `userId`（:180）、`color`（:192）；屏蔽表 `Fc2LiveNgList`（:215，`hides` :292）；人数 `Fc2LiveAudience`（:358） | 与归档 v4 对照，有意差异 12 条（record.md“与归档 v4 的差异”） |
| 公告 | 普通房间显示 `fc2live_chat_notice`“FC2 远端聊天尚待接入；媒体控制 WebSocket 由播放或录制独占……”（`fc2_site.dart:137`，`assets/translations/zh.json:1917`） | `Fc2LiveApi.notice`（`packages/live_core/lib/src/sites/fc2live/fc2live_api.dart:737`）对普通房间返回 null，受限、成人说明不变；3.x 原文留成 `legacyChatNotice`（:309）给对照测试 | 不再显示；3.x 存下的旧公告导入时由 `LegacyRules.isStaleNotice`（`packages/live_store/lib/src/legacy/legacy_rules.dart:11`，用在 `legacy_snapshot.dart:266`）清掉 |
| 人数 | 目录、详情的 `count`、`total` | `audience.dart:211` 仍是 `roomList`（有累计）；评论流是同一对数，进房后实时更新 | — |
| 参数 | 无 | `Fc2LiveDanmakuArgs(频道号)`（`fc2live_api.dart:146`），E03.13 已给出：进房和录制详情在播、受限、未开播都带，刷新、卡片不带 | — |

## 结果

- **提交**：ecfea58fb（2026-09-30，本任务的代码）。之后本平台的弹幕代码只有 docs v1 改编号时动过注释（c613b73f9、9dfbb424d），行为没有变。
- **和归档 v4 的对照**：`fixtures/fc2live/danmaku/v4_expected.dart` 把 v4 的 `Fc2LiveProtocol` 原样搬成独立程序，输出 `S06-live/expected.json`。S06-live（频道 29745829，约 114 s）47 个服务端帧逐帧一致：第 10 行 30 条历史评论不报，20 条聊天，27 个人数；授权回答经 `Fc2LiveSite.controlGrant` 得到的地址就是录下的握手地址；4 个心跳与录制文字相同（v4 发二进制，这里发文本）。差别都是有意的：消息 id 为空（v4 用 `fc2live:<hash>`）、用户 id 是网页的用户键。
- **实测**（2026-09-29 匿名直连）：推荐里 56 个房间，进人最多的（144 人）1.2～1.3 s 就绪，95 s 收到 7 条聊天、14 个人数（在线 144 与详情相同），3 个心跳都有回答，没有重连；屏蔽表挡下 31 条里的 1 条，正是服务端标了 `ng_comment_keyword` 的那条；12 个发送者里 3～4 个的 `encrypted_user_id` 每条都变，解码后每人一个键。
- **样本**：`fixtures/fc2live/danmaku/S06-live`（归档的真实录制，`frames.jsonl`、`meta.json` 没有改），新加冻结输出 `expected.json` 和生成它的 `v4_expected.dart`。
- **测试**：`packages/live_danmaku/test/sites/fc2live_test.dart` 现在 34 个（和做完时一样，没有循环生成的用例）：协议 13、录制 4、连接 17（含 `IoLiveHttp` 和默认握手的本地服务器端到端）。`live_core` 的 FC2 测试改了公告断言（76 个不变）。

## 验证

- 自动测试：`fc2live_test.dart` 覆盖心跳命令和时序常量、名义地址往返、令牌去除、帧的各种坏形状、评论各字段和不报的评论、去标签和匿名名、10 种偏移的用户键、颜色、人数累加、屏蔽表各类型和开关；录制对照 v4 冻结输出、用连接重放整份录制；连接的授权、请求头、代理路由、只就绪一次、断线换新授权、`control_disconnection` 和 `move_server`、服务端连环要求重连时结束、加入超时、关闭时取消授权请求。
- 真实接口：2026-09-29 匿名直连跑过（见上面的实测）。没录到 `move_server`（给的 `url` 是否带令牌不明，所以改为重取授权）。
- 真机：没有单独的真机记录；S02.2、S02.3 的记录里没有 FC2。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列哔哩哔哩、斗鱼、虎牙、抖音、快手，没有 FC2 弹幕的条目；海外平台要代理，清单“准备”一行写明只在用户开着代理时做。真机上要看：进一个在播的 FC2 直播间，聊天区“已连接”，有评论时出现、人数随之变化，长时间看不出现反复的重连提示。

## 留下的问题

- 3.x 存下的关注里的旧公告：已由 J02.1 处理（导入时 `LegacyRules.clearStaleNotice` 清掉含“远端聊天尚待接入”的公告）；覆盖安装的真机核对在 J06.1（未开始）。
- 匿名名字显示平台给的 `[anonymous]`，没有换成界面语言的“匿名”：没有任务（平台层的文字随界面语言是 Z05.2 的范围，这个名字来自平台数据，不在它列出的清单里；要改时在 Z05.2 第 3 阶段“弹幕系统消息按界面语言”一起定）。
- 用户 id 可能是解码出的 FC2 账号编号，只用来区分发送者：没有任务（界面现在不显示用户 id）。
- 打赏（`tip`）、礼物（`gift`）不显示：没有任务。B-21 的礼物显示（C01.2）只显示已上报礼物的平台，本平台要先在协议层解 `system_comment` 的 `tip_amount`、`gift_id`，礼物名要查 `memberApi` 的 `gift_list`。
- 历史评论不报（网页放进评论列表），刚进房时看不到之前的评论：没有任务，有意如此（归档规格和 E03.13 的要求，避免旧弹幕刷屏）。
- `move_server` 没有录到：没有任务，按网页客户端实现、合成帧测试，录到时再核对。
- 没有真机结果：没有任务；真机清单没有海外平台弹幕的条目（见“验证”）。
