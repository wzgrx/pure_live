# D01.10 AcFun 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `36285b104`）
- 类型：平台
- 来源：已批准升级 10-4“接入 AcFun 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 的 AcFun 没有弹幕，这是新增功能（照网页播放页脚本和归档 v4 的实现写）
- 旧编号：M5.9、T06a.10
- 相关：决定 D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；protobuf 读写器和抖音共用（[D01.5](../D01.5-抖音弹幕/README.md)）；平台本身 [E02.3](../../../E-直播平台/E02-其他国内平台/E02.3-AcFun直播/README.md)（访客会话、`startPlay`、弹幕参数和 `refresh`，付费直播没有弹幕参数，见 [E02.3 记录](../../../E-直播平台/E02-其他国内平台/E02.3-AcFun直播/record.md)）；礼物显示 B-21 在 C01.2（AcFun 不上报礼物）；巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)
- 记录：[record.md](record.md)

## 目标

AcFun 直播间能看到弹幕和实时在线人数（3.x 进房只提示一次“此平台的远端弹幕尚未接入”）。协议是快手直播中台的加密长连接（`wss://link.xiatou.com/`），用进房时已经拿到的访客会话和票据，开始连接不多发 HTTP 请求；票据失效、会话被拒、下播时自己恢复或结束，不无限重试。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | `AcfunDanmakuArgs`（`packages/live_core/lib/src/sites/acfun/acfun_api.dart:104`，E02.3 进房时放进 `LiveRoom.danmakuData`）：作者 id、`liveId`、访客会话（用户 id、设备号、服务令牌、`acSecurity`）、票据列表、`enterRoomAttach`、`refresh`（`AcfunSite.danmakuArgs`：新访客会话 + 新 `startPlay`）；`acSecurity` 不是 16 字节 AES 密钥或没有票据时开始前先 `refresh` 一次（`target`，`acfun.dart:67-88`），仍不能用就以 `credentialsUnavailable` 结束 |
| 地址和握手 | `wss://link.xiatou.com/`（`acfun.dart:381`）；请求头取参数里的 `user-agent`（Chrome 140）和 `origin: https://live.acfun.cn`（`acfun_api.dart:132`）；默认 `dart:io` 握手（实测服务端接受小写请求头和拼了 `Dart/…` 前缀的 UA） |
| 帧 | 大端 `[u16 0xABCD][u16 1][u32 头长][u32 负载长]` + `PacketHeader`（protobuf：`appId` 13、`uid`、`instanceId`、明文长度、加密模式、注册包才有的 `tokenInfo`、`seqId`、`kpn` `ACFUN_APP`）+ 负载；负载是 16 字节 IV + AES-128-CBC 密文，模式 1 用 `acSecurity`（只用于注册和它的应答），模式 2 用注册应答给的会话密钥（必须 16 字节）；三段长度之和要等于帧长，解不开的帧丢掉，不影响连接 |
| 加入 | 打开发 `Basic.Register`（`onOpen`，`acfun.dart:101`）；注册应答后发 `Basic.KeepAlive` 和进房 `Global.ZtLiveInteractive.CsCmd` 的 `ZtLiveCsEnterRoom`（带票据、`liveId`、`enterRoomAttach`、`reconnectCount` = 本次 `connect` 之前开过的连接数）；进房应答错误码 0 时就绪；加入超时 10 s（`defaultPolicy`，`:48-51`），第一次只换连接，连续第二次刷新参数（`onJoinTimeout`，`:182`） |
| 心跳 | 10 s 发 `ZtLiveCsHeartbeat`（只在进房后，`heartbeatFrame`，`:282`），每第 5 次心跳带一次保活（`heartbeatsPerKeepAlive`，`:55`，即 50 s，网页的值）；进房应答里的心跳间隔（录制和实测都是 10000 ms，`heartbeatInterval`，`:496`）不用来改策略；无消息 90 s 换连接；单地址，重连间隔 2～6 s，8 次后放弃 |
| 推送 | 每个 `Push.*` 先回一帧确认（同一 `command`、没有负载，不占上行序号）再上报；`Push.ZtLiveInteractive.Message` 里是 `ZtLiveScMessage`（类型、压缩 2 为 gzip、内容），由 `push`（`acfun.dart:515`）解 |
| 消息 | `ZtLiveScActionSignal` → `CommonActionSignalComment`（`_comment`，`:564`）：聊天，文本字段 1、发送时间毫秒字段 2、用户 `{1 id, 2 昵称}`，白色，没有消息 id；`ZtLiveScStateSignal` → `CommonStateSignalDisplayInfo.watchingCount`（`_displayInfo`，`:589`）：在线人数 `onlineViewers`（可能带“万”，用 `parseChineseCount`）；礼物、香蕉、点赞、进场、关注、榜单、红包、最近评论不报；一个信号、一条评论解不开只跳过它 |
| 恢复 | 票据失效（应答错误码 2、3、4、7，`ticketErrors`，`:425`，或 `ZtLiveScTicketInvalid`）先在同一连接上换下一张再进房；注册被拒、信封错误码非 0、其他应答错误码、状态变化 1、2、4（`refreshingStatuses`，`:430`）、票据都失效过、连续两次加入超时：刷新参数后 `reopen`，不提示；自上次加入以来刷新 3 次（`maxRefreshes`，`:59`）仍失败就以 `credentialsUnavailable` 结束；刷新时抛 `StreamUnavailable`（下播、付费直播）以 `connectionFailed` 结束（`_closeReason`，`:272`）；结束详情只写错误种类，不带访客令牌 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | 3.x 有这个平台但没有弹幕：`AcfunSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/acfun/acfun_site.dart:34`；`EmptyDanmaku` 在 `lib/core/danmaku/empty_danmaku.dart:9`，`start` 什么都不做 :39）；直播间见到 `EmptyDanmaku` 就提示一次 `remote_danmaku_not_integrated`“此平台的远端弹幕尚未接入；可在设置中开启本地互动，仅在本机显示。”（`modules/live_play/controllers/danmaku_controller.dart:146-150`） | `AcfunDanmakuConnection`（`packages/live_danmaku/lib/src/sites/acfun.dart:36`）继承 `DanmakuSocketConnection`；应用登记在 `apps/pure_live/lib/app/platforms.dart:216`，传应用的 `ProxyPolicy` | 有聊天和在线人数（已做） |
| 协议 | 无 | `AcfunDanmakuProtocol`（:379，分帧、加解密、推送解码）、`AcfunDanmakuLink`（:611，一条连接的序号、`instanceId`、会话密钥、要发的帧）、`AcfunDanmakuPacket`（:342） | 与归档 v4 录制逐字节一致 |
| 时序 | 无 | `defaultPolicy`（:48-51）：心跳 10 s、加入超时 10 s；保活每 5 次心跳（:55）；`maxRefreshes = 3`（:59） | 280 s 实测不断开 |
| 开始前的请求 | 无 | 不发；参数不能用时 `refresh` 一次（2 个请求） | 归档 v4 每次开始 3 个请求（登录、`startPlay`、礼物表） |
| 在线人数来源 | 列表和详情的 `onlineCount` | 弹幕的 `watchingCount` 是同一个数（录制结束时 70～71 对接口 71，实测 60～61 对列表 60） | 进房后实时更新 |
| 付费直播 | 无弹幕 | 进房没有票据，也就没有弹幕参数；直播间照样 `connect(null)`，基类抛 `ArgumentError`（`packages/live_danmaku/lib/src/connection_base.dart:55`），聊天区提示“弹幕服务器连接失败”（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:839-844`） | 见“留下的问题” |

## 结果

- **提交**：`36285b104`（2026-09-29，`feat(live_danmaku): AcFun danmaku (M5.9)`）；`54baa1109`（2026-09-29，protobuf 读写器从 `sites/douyin/` 移到 `src/codec/protobuf.dart`，两边共用）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和归档 v4 的对照**（3.x 没有可对照的行为）：`fixtures/acfun/danmaku/v4_expected.dart` 把归档 v4 的会话和协议搬成独立程序生成冻结输出。S07-live（房间 41254970，5 分钟，784 行：3 个 HTTP 和 781 个链路帧）收到的 390 帧命令、序号、错误码逐帧一致（1 条聊天、151 次在线人数），本实现写出的 391 个发出帧明文逐字节相同（注册 1、保活 6、进房 1、心跳 30、推送确认 353）。
- **和归档 v4 的差异**（record.md 11 条）：开始不再自己登录和 `startPlay`；不请求礼物表、不报礼物和香蕉；票据失效先换票据；保活按心跳次数；心跳固定 10 s；加入超时两级；结束原因用 D01.1 的类型并限 3 次刷新；坏信号只跳过自己；`reconnectCount` 照实报；会话密钥必须 16 字节；信封错误码非 0 统一刷新。
- **实测**（2026-09-29 匿名直连，房间 40740702）：70 s 和 280 s 两次分别 317 ms、232 ms 就绪，全程不断开（跨过 5 次保活、约 28 次心跳），在线人数 60～61 与列表一致；两次都没人发聊天，聊天解码以录制为准。
- **样本**：`fixtures/acfun/danmaku/S07-live`（`frames.jsonl`、`meta.json`、`expected.json`）补做了链路会话号 `instanceId` 的脱敏（头部 780 处、注册应答解密改写后用原 IV 重新加密）。
- **测试**：`packages/live_danmaku/test/sites/acfun_test.dart` 38 个，和当时相同（协议 11、录制 4、连接 23，含本地 WebSocket 服务器端到端；没有循环生成的用例）。

## 验证

- 自动测试：`acfun_test.dart`——分帧和坏帧、`acSecurity` 的几种不能用的形式、加解密；注册、保活、进房、心跳序号，推送确认不占序号；推送解码（普通和 gzip 的评论、在线人数含“万”、票据失效和状态变化、坏信号只跳过自己）；S07 390 帧对照归档 v4、391 个发出帧逐字节；连接（只在进房应答后就绪、每第 5 次心跳带保活、换票据、刷新的各种触发和 3 次上限、下播以 `connectionFailed` 结束、详情不带令牌、加入超时两级、本地 WebSocket 服务器端到端）。
- 真实接口：见上面的实测（2026-09-29）。
- 真机：没有单独的真机记录；AcFun 不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)里（第 1 节第 1 条只列了国内五大平台、YY、CC，第 2 节第 1 条只列了国内五大平台）。登记表状态是“完成”。真机上要看：进一个在播的 AcFun 直播间，聊天区显示“已连接”、有人发言时出现聊天、人数随弹幕更新、待 50 s 以上不断开。

## 留下的问题

- 礼物、香蕉不上报：要显示的话需按 `startPlay` 的参数请求礼物表（归档 v4 的做法）；B-21 的礼物显示（C01.2）只覆盖已上报礼物的平台，没有任务，要做先在 V01 提议（D-026）。
- 心跳间隔固定 10 s，不读进房应答里的值（录制和实测都是 10000 ms）：没有任务，以后见到别的值再改成按应答设置。
- 付费直播进房没有弹幕参数，直播间提示的是“弹幕服务器连接失败”（`room_controller.dart:844`），用户看不出是付费直播的原因：没有任务；更合适的是参数为空时不连、显示“该直播间没有弹幕”，归直播间（C01 组），见报告。
- 真机：建议在真机清单第 2 节第 1 条加上 AcFun（见报告）；真机结果等 [S03.1](../../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md) 统一验证。
