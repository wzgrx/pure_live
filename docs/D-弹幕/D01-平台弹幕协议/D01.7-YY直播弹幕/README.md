# D01.7 YY 直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：模块重构（M5 的第 6 个平台）：把 3.x 的 `lib/core/danmaku/yy_danmaku.dart`、`lib/core/utils/yy/yy_protocol.dart`、`yy_web_socket_channel.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一
- 旧编号：M5.6、T06a.7
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；保留大小写的握手和 SOOP 共用（[D01.8](../D01.8-SOOP弹幕/README.md)）；平台本身和后来的热度上报 [E02.1 记录](../../../E-直播平台/E02-其他国内平台/E02.1-YY直播/record.md)；详细记录 [record.md](record.md)

## 目标

YY 直播间的弹幕照 3.x 的匿名 H5 协议连上：匿名登录、AP 登录、加入频道、订阅，收到聊天就显示；修掉 3.x 把 XML 包装的正文整段显示、频道拒绝加入时无限重连、握手计时器偶尔误关连接这三个问题。为此把 3.x 的“保留请求头大小写的 WebSocket 握手”移成框架里的共用文件。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | `wss://h5-sinchl.yy.com/websocket?appid=yymwebh5&version=3.2.10&uuid=<UUID>`；UUID 每个连接对象一个，重连和换房间都不换 |
| 握手 | 请求头 `User-Agent`（桌面 Chrome 151）、`Origin: https://www.yy.com`，按原样大小写，用 `connectExactWebSocket`（`packages/live_danmaku/lib/src/exact_websocket.dart`）；总是直连，不走代理（3.x 如此） |
| 包 | 小端，10 字节包头 `u32 总长`、`u32 uri`、`u16 200`；字符串 `u16 长度` + 字节，UCS-2 字符串 `u32 长度` + UTF-16LE；读写在 `sites/yy/packet.dart` |
| 握手顺序 | 匿名 UDB 登录（`778244` → `778500`）→ AP 登录（`775684` → `775940`）→ 加入频道（路由 `513035` 包着 `2048258`，带两个匿名频道属性）和应用订阅（`538456`：31、101、102、103、17）→ 路由回答 `loginStatus` 为 4 且频道一致即加入 → 两个用户组订阅（`537944`） |
| 就绪和超时 | 加入成功才就绪；打开后 15 s 没加入报 `handshakeTimeout` 再重连；协议失败报 `protocolError` 再重连；连续 9 次打开却没加入就以 `reconnectsExhausted` 结束 |
| 心跳 | AP 登录后每 5 s 发 AP ping（`794116`）；无消息 45 s 换连接；单地址，重连间隔 2～6 s |
| 聊天 | 应用 31 的 `3104600`（来自用户组消息 `533080`、路由转发或按 sid 推送 `28760`）；频道或子频道不同就丢；正文以 `<?xml` 或 `<msg` 开头时取所有 `txt` 的 `data` 并解码实体；名字为空写 `YY用户`；一律白色，没有用户 id、消息 id、时间 |
| 热度 | E02.1 后加：应用 103 的 `3139586` 第一个 `u32` 作为热度（`popularity`）上报，和官网直播间标题栏的人数是同一个数 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/`） | 现在（`packages/live_danmaku/lib/src/sites/yy.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `danmaku/yy_danmaku.dart` 的 `YyDanmaku`（:25），`YYSite.getDanmaku()`（`site/yy/yy_site.dart:27`） | `YyDanmakuConnection`（:654）；应用登记在 `apps/pure_live/lib/app/platforms.dart:215`（不传代理） | 一致 |
| 时长 | `heartbeatTime = 5 * 1000`（:27），`inactivityTimeout` 45 s（:93） | `heartbeatInterval`（:35）、`inactivityTimeout`（:38）、`handshakeTimeout`（:42），`socketPolicy`（:663） | 一致 |
| 协议状态机 | `utils/yy/yy_protocol.dart` 的 `YyProtocolSession`（:205），聊天 uri（:222） | `YyDanmakuSession`（:162），不做 I/O | 发出的包与 3.x 逐字节相同 |
| XML 正文 | 原样显示整段 XML（录制里 2 条都是） | `chatText`（:69） | 修好（3.x 问题 1） |
| 被拒 | 被拒的回答也算“收到消息”，失败次数清零，永远重连，每轮两条提示 | 自己数 `_unjoined`（:676～726），超过 8 次重连就结束 | 修好（3.x 问题 2）；85520900 这类一直被拒的频道约 20 s 后结束 |
| 大小写握手 | `utils/yy/yy_web_socket_channel.dart`，升级回答早于 `flush` 时会被自己的计时器关掉 | `exact_websocket.dart` 的 `ExactWebSocket`、`connectExactWebSocket`，YY 和 SOOP 共用 | 修好（3.x 问题 3） |
| 断线详情 | `_compactFailure`（:129），中文 | 同样压成一行、最多 120 字，英文，只作诊断 | 界面文字由直播间按原因给出 |
| 热度 | 应用 103 不解码 | `_popularityUri = 3139586`（:184），读法 :402～414 | 弹幕连接也更新热度（E02.1 的 D4） |

## 结果

- **提交**：8122b9713（2026-09-29，M5.6）；之后 c991163f0（2026-10-01，E02.1 的“国内平台完善”：热度上报）、393de73fc（附录 C-18 只改注释）。
- **和 3.x 的对照**：`fixtures/yy/danmaku/legacy_expected.dart` 把 3.x 的 `yy_protocol.dart` 和聊天转换搬成独立程序。S08-live（频道 54880976，563 帧）握手三步的发出包、就绪、心跳一致，2 条聊天除 XML 正文外一致；S09-synthetic 38 组除 4 组 XML 正文外一致。加入路由和录制只差 trace id（录制工具写法不同）。
- **实测**（2026-09-29，匿名直连）：22490906、54880976 约 0.4 s 就绪；热度最高的 8 个频道 90 s 收到 41 条聊天；10 个未开播频道都能进（附录 6-7），只有 85520900 每次被拒（`loginStatus` 10）。
- **样本隐私**：AP 登录回答里回显的录制者公网地址换成文档地址 `203.0.113.7`（已进 git 历史，按“不强推”没改历史）。
- **测试**：`packages/live_danmaku/test/sites/yy_test.dart` 66 个（协议 8、录制对照 3、合成对照 39、连接 16），`test/exact_websocket_test.dart` 27 个（握手、帧、协议错误、与 `dart:io` 服务器互通）；E02.1 另加 1 个热度用例。

## 验证

- 自动测试：`yy_test.dart`、`exact_websocket_test.dart`（原始 TCP 服务器收到的请求与 `handshake` 逐字节相同）。
- 真实接口：上面的实测；E02.1 的“国内平台完善”22490906、1414787911 各 2 分钟，0.77 s 加入，热度约每秒 2 条。
- 真机：没有单独的真机记录；YY 不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条的五个平台里，关注列表准备里有 YY 直播间。

## 留下的问题

- `3165186` 带一个小得多的计数（2050 对热度 146 万），像真实在线人数，但官网不显示它，核对不了：附录 C-18 受阻，没做。
- 礼物：匿名连接收不到，礼物在应用 15012，要多订阅并解新格式：附录 C-20 受阻，没做。
- YY 的表情代码（`/{tx`、`/{mg`）原样显示成文字：3.x 没有 YY 的表情表，列为候选，归 A 组的表情（没有登记任务）。
- 名字为空时的 `YY用户` 还是写死的中文，没走翻译（pure_live_TV 用 `danmaku_anonymous_user`）；归 [D06.1](../../D06-弹幕功能余项/D06.1-弹幕功能余项/README.md) 一类的余项，目前没有单独登记。
- 不走代理：用户开着代理时 YY 弹幕仍直连（3.x 如此）。
