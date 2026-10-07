# D01.10 AcFun 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 10-4“接入 AcFun 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 的 AcFun 没有弹幕，这是新增功能
- 旧编号：M5.9、T06a.10
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；protobuf 读写器和抖音共用（[D01.5](../D01.5-抖音弹幕/README.md)）；平台本身、访客会话和弹幕参数 [E02.3 记录](../../../E-直播平台/E02-其他国内平台/E02.3-AcFun直播/record.md)；详细记录 [record.md](record.md)

## 目标

AcFun 直播间能看到弹幕和实时在线人数（3.x 只提示一次“没有弹幕”）。协议是快手直播中台的加密长连接，照网页播放页脚本和归档 v4 的实现写，用进房时已经拿到的访客会话和票据，开始连接不多发 HTTP 请求。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | `wss://link.xiatou.com/`；请求头取参数里的 UA（Chrome 140）和 `Origin: https://live.acfun.cn`；默认 `dart:io` 握手即可（实测服务端接受小写请求头） |
| 参数 | `AcfunDanmakuArgs`（E02.3 进房时放进 `LiveRoom.danmakuData`）：访客 id、服务令牌、`acSecurity`（16 字节 AES 密钥）、`liveId`、票据列表、`enterRoomAttach`、`refresh`（新访客会话 + 新 `startPlay`）；只有参数不能用时才调用 `refresh` |
| 帧 | 大端 `[u16 0xABCD][u16 1][u32 头长][u32 负载长]` + `PacketHeader`（protobuf）+ 负载；负载是 16 字节 IV + AES-128-CBC 密文，模式 1 用 `acSecurity`（只用于注册），模式 2 用注册应答给的会话密钥 |
| 加入 | 打开发 `Basic.Register`；注册应答后发 `Basic.KeepAlive` 和进房 `ZtLiveCsEnterRoom`（带票据、`liveId`、`reconnectCount`）；进房应答错误码 0 时就绪；加入超时 10 s，第一次只换连接，连续第二次刷新参数 |
| 心跳 | 10 s 发 `ZtLiveCsHeartbeat`（只在进房后），每第 5 次心跳带一次保活（50 s，网页的值）；每个推送都先回确认（不占上行序号） |
| 消息 | `Push.ZtLiveInteractive.Message` 里的 `ZtLiveScMessage`（可能 gzip）：`CommonActionSignalComment` → 聊天（白色，没有消息 id）；`CommonStateSignalDisplayInfo.watchingCount` → 在线人数（可能带“万”）；礼物、香蕉、点赞、进场、关注不报 |
| 恢复 | 票据失效（应答错误码 2、3、4、7 或 `ZtLiveScTicketInvalid`）先在同一连接换下一张；注册被拒、命令出错、下播（状态变化 1、2、4）、票据都失效时刷新参数后 `reopen`；自上次加入以来刷新 3 次仍失败就结束；下播（`StreamUnavailable`）以 `connectionFailed` 结束 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | `AcfunSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/acfun/acfun_site.dart:34`），直播间提示一次“此平台的远端弹幕尚未接入” | `AcfunDanmakuConnection`（`packages/live_danmaku/lib/src/sites/acfun.dart:36`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:216` | 有聊天和在线人数（已做） |
| 协议 | 无 | `AcfunDanmakuProtocol`（:379，分帧、加解密、推送解码）、`AcfunDanmakuLink`（:611，一条连接的序号、`instanceId`、会话密钥）、`AcfunDanmakuPacket`（:342） | 与归档 v4 录制逐字节一致 |
| 时序 | 无 | `defaultPolicy`（:48～50）：心跳 10 s、加入超时 10 s；`maxRefreshes = 3`（:59） | 280 s 实测不断开 |
| 在线人数来源 | 列表和详情的 `onlineCount` | 弹幕的 `watchingCount` 是同一个数（录制 70～71 对接口 71） | 进房后实时更新 |

## 结果

- **提交**：36285b104（2026-09-29，M5.9）；54baa1109（protobuf 读写器从 `sites/douyin/` 移到 `src/codec/protobuf.dart`，两边共用）。
- **和归档 v4 的对照**：`fixtures/acfun/danmaku/v4_expected.dart` 把归档 v4 的会话和协议搬成独立程序生成冻结输出。S07-live（房间 41254970，5 分钟，784 行）收到的 390 帧命令、序号、错误码逐帧一致（1 条聊天、151 次在线人数），本实现写出的 391 个发出帧明文逐字节相同（注册 1、保活 6、进房 1、心跳 30、推送确认 353）。
- **和归档 v4 的差异**（record.md 11 条）：开始不再自己登录和 `startPlay`（v4 每次 3 个请求）；不请求礼物表、不报礼物；票据失效先换票据；保活按心跳次数；`reconnectCount` 照实报；会话密钥必须 16 字节；坏信号只跳过自己。
- **实测**（2026-09-29 匿名直连，房间 40740702）：70 s 和 280 s 两次分别 317 ms、232 ms 就绪，全程不断开，在线人数 60～61 与列表一致；两次都没人发聊天，聊天解码以录制为准。
- **样本**：`fixtures/acfun/danmaku/S07-live` 补做了链路会话号 `instanceId` 的脱敏（头部 780 处、注册应答重新加密）。
- **测试**：`packages/live_danmaku/test/sites/acfun_test.dart` 38 个（协议 11、录制 4、连接 23，含本地 WebSocket 服务器端到端）。

## 验证

- 自动测试：`acfun_test.dart`。
- 真实接口：见上面的实测。
- 真机：没有单独的真机记录；AcFun 不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节里。真机上要看：进一个在播的 AcFun 直播间，弹幕区显示“已连接”、有人发言时出现聊天、人数随弹幕更新。

## 留下的问题

- 礼物、香蕉不上报：要显示的话需按 `startPlay` 的参数请求礼物表（归档 v4 的做法）；B-21 的礼物显示没有覆盖 AcFun，没有登记任务。
- 心跳间隔固定 10 s，不读进房应答里的值（录制和实测都是 10000 ms）；以后见到别的值再改。
- 付费直播进房没有票据，也就没有弹幕参数，直播间会显示弹幕连接失败一类的状态；提示文字归直播间（C01）。
