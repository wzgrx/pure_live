# D01.7 YY 直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `8122b9713`）
- 类型：平台
- 来源：模块重构（弹幕协议的第 6 个平台）：把 3.x 的 `lib/core/danmaku/yy_danmaku.dart`、`lib/core/utils/yy/yy_protocol.dart`、`lib/core/utils/yy/yy_web_socket_channel.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一
- 旧编号：M5.6、T06a.7
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；保留大小写的握手由本任务移进框架，和 SOOP 共用（[D01.8](../D01.8-SOOP弹幕/README.md)，SOOP 后来加了走代理的版本）；平台本身 [E02.1](../../../E-直播平台/E02-其他国内平台/E02.1-YY直播/README.md)（频道号、未开播房间的弹幕参数 6-7，后来的热度上报和 C-18～C-20 在 [E02.1 记录](../../../E-直播平台/E02-其他国内平台/E02.1-YY直播/record.md)“国内平台完善”“附录 C 落地”两节）；名字为空时的中文 [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)；巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)；升级条目 [specs/UPGRADES.md](../../../specs/UPGRADES.md) 的 6-7、C-18、C-20
- 记录：[record.md](record.md)

## 目标

YY 直播间的弹幕照 3.x 的匿名 H5 协议连上：匿名登录、AP 登录、加入频道、订阅，收到聊天就显示；修掉 3.x 的三个问题：XML 包装的正文整段显示、频道拒绝加入时无限重连、握手计时器偶尔误关连接。为此把 3.x 的“保留请求头大小写的 WebSocket 握手”移成框架里的共用文件。后来（E02.1）弹幕也上报房间热度，和官网标题栏的人数是同一个数。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | `YyDanmakuArgs`（`packages/live_core/lib/src/sites/yy/yy_api.dart:20`）：频道号 `topSid`、子频道号 `subSid`（短号房间已换成规范频道）；6-7 起未开播的房间进房时也带 |
| 地址 | `wss://h5-sinchl.yy.com/websocket?appid=yymwebh5&version=3.2.10&uuid=<UUID>`（`baseUrl`，`yy.dart:23`；`endpoint`，`:48`），只有这一个；UUID 是随机的第 4 版（`uuid`，`:52`），每个连接对象一个，重连和换房间都不换 |
| 握手 | 请求头 `User-Agent`（桌面 Chrome 151）、`Origin: https://www.yy.com`（`headers`，`yy.dart:27-32`），按原样顺序和大小写，用 `connectExactWebSocket`（`packages/live_danmaku/lib/src/exact_websocket.dart:21`）；总是直连，不走代理（3.x 如此；应用登记时也不传代理） |
| 包 | 小端，10 字节包头 `u32 总长（含包头）`、`u32 uri`、`u16 200`；字符串 `u16 字节数` + 字节，UCS-2 字符串 `u32 字节数` + UTF-16LE；一帧可以多包，按总长切开；读写在 `sites/yy/packet.dart`（`YyPacketReader`、`YyPacketWriter`） |
| 握手顺序 | `YyDanmakuSession`（`yy.dart:162`，不做 I/O）：匿名 UDB 登录（`778244` → `778500`，`realUri` 20078、uid 不为 0）→ AP 登录（`775684` → `775940`，结果码 200）→ 一起发加入频道（路由 `513035` 包着 `2048258`，服务名 `channelAuther`，带两个匿名频道属性）和应用订阅（`538456`：31、101、102、103、17）→ 路由回答 `512011` 里 `2048514` 的 `loginStatus` 为 4 且频道号、子频道号一致即加入 → 两个用户组订阅（`537944`，6 组和 2 组）；回答不在该来的阶段就忽略 |
| 就绪和超时 | 打开后先标为未连接（`onOpen`，`yy.dart:688`），加入成功才就绪；打开后 15 s 没加入报 `handshakeTimeout` 再重连（`joinTimeout`，`:42`）；协议失败（某一步被拒、握手数据坏了）报 `protocolError` 再重连；连续 9 次打开却没加入就以 `reconnectsExhausted` 结束（`_retry`，`:725-731`），加入后重新计数 |
| 心跳 | AP 登录发出后每 5 s 发 AP ping（`794116`，包体 `u32 0`，`heartbeat`，`:221`），之前不发；无消息 45 s 换连接（`:38`）；握手 10 s；单地址，重连间隔 2、3、4、5、6、6、6、6 s；断线详情压成一行、最多 120 字（`compactFailure`，`:95`），英文，只作诊断 |
| 聊天 | 应用 31 的 `3104600`（`_readChat`，`yy.dart:425`），来自用户组消息 `533080`、路由 `512011` 转发或按 sid 推送 `28760`；频道号或子频道号不同就丢；正文去首尾空白，空的丢；正文以 `<?xml` 或 `<msg` 开头时取所有 `txt` 元素的 `data` 依次连起来并解码 XML 实体（`chatText`，`:69`），没有 `txt` 的 XML 不算聊天；`/{tx`、`/{mg` 这类表情代码原样保留；名字是包末尾的 UTF-8 名字，空的写 `YY用户`（`anonymousUserName`，`:45`）；颜色、字号、发送者 uid、附加项读过去不用：一律白色，没有用户 id、消息 id、时间 |
| 热度（E02.1 加） | 应用 103 的 `3139586`（`_readPopularity`，`yy.dart:408`）：`u32` 热度、`u32` 1、`u32` 频道号（别的频道丢掉）、`u32` 略小的热度；报第一个数为 `popularity`，大房间约每秒 2 条；同组的 `3165186` 带一个小得多的计数，官网哪里都不显示，不读（C-18） |
| 出错 | 握手阶段的坏包算失败；加入后的坏包只记一条警告；文本帧忽略 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/`） | 现在（`packages/live_danmaku/lib/src/sites/yy.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `danmaku/yy_danmaku.dart` 的 `YyDanmaku`（:25），`YYSite.getDanmaku()`（`site/yy/yy_site.dart:27`） | `YyDanmakuConnection`（:654）继承 `DanmakuSocketConnection`；应用登记在 `apps/pure_live/lib/app/platforms.dart:215`（`YyDanmakuConnection.new`，不传代理） | 一致（已做） |
| 时长 | `heartbeatTime = 5 * 1000`（:27），`inactivityTimeout` 45 s（:93），15 s 握手计时（:140） | `heartbeatInterval`（:35）、`inactivityTimeout`（:38）、`handshakeTimeout`（:42），`socketPolicy`（:663） | 一致 |
| 协议状态机 | `utils/yy/yy_protocol.dart` 的 `YyProtocolSession`（:205），聊天 uri `_textChatUri`（:222） | `YyDanmakuSession`（:162），`beginHandshake`（:209）、`consume`（:231） | 发出的包与 3.x 逐字节相同 |
| XML 正文 | 正文原样当文字（`yy_protocol.dart:441`），录制里 2 条都是整段 XML | `chatText`（:69） | 修好（3.x 问题 1） |
| 被拒 | 被拒的回答也算“收到消息”，`WebScoketUtils` 的失败次数清零，永远重连，每轮两条提示 | 自己数 `_unjoined`（:676，清零 :682、:706，判断 :726） | 修好（3.x 问题 2）；85520900 这类一直被拒的频道约 20 s 后结束 |
| 大小写握手 | `utils/yy/yy_web_socket_channel.dart`，计时器在 `flush` 之后才建（:143-147），升级回答早于 `flush` 时会被自己的计时器关掉 | `exact_websocket.dart` 的 `ExactWebSocket`（:57）、`connectExactWebSocket`（:21），YY 和 SOOP 共用；SOOP 后来用同文件的 `connectExactWebSocketViaRoute`（:33）走代理 | 修好（3.x 问题 3） |
| 断线详情 | `_compactFailure`（:129），中文 | `compactFailure`（:95），同样压成一行、最多 120 字，英文 | 界面文字由直播间按原因给出 |
| 热度 | 应用 103 不解码 | `_popularityUri = 3139586`（:184），读法 :408-419 | 弹幕连接也更新热度（E02.1 问题 D4） |

## 结果

- **提交**：`8122b9713`（2026-09-29，`feat(live_danmaku): YY danmaku refactored from v3 (M5.6)`）、`c5963f6a9`（2026-09-29，测试守住录制里换过的地址）；之后 `83f0e903e`（SOOP 改用共用的握手）、`083fac138`（SOOP B-6 给共用文件加了走代理的版本，YY 不受影响）、`c991163f0`（2026-10-01，E02.1 的“国内平台完善”：热度上报）、`393de73fc`（2026-10-01，附录 C-18 只改注释）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和 3.x 的对照**：`fixtures/yy/danmaku/legacy_expected.dart` 把 3.x 的 `yy_protocol.dart` 和聊天转换搬成独立程序。S08-live（频道 54880976，约 120 s，563 帧收到）握手三步的发出包、就绪、心跳一致，2 条聊天除 XML 正文外一致；S09-synthetic 38 组除 4 组 XML 正文外一致。加入路由和录制只差 trace id（录制工具写法不同）。
- **有意差异**（record.md 6 条）：XML 正文取文字、连续 9 次没加入就结束、升级后握手计时器不再起作用、失败文字英文、`connect` 只接受 `YyDanmakuArgs`、连接器在升级完成后才返回。保持 3.x：就绪要等加入、每个连接对象一个 UUID、被拒后立即按退避重连、聊天一律白色、应用 103 除热度外不解码、不走代理。
- **实测**（2026-09-29，匿名直连）：22490906、54880976 约 0.4 s 就绪；热度最高的 8 个频道 90 s 收到 41 条聊天（有 `/{mg` 表情代码，没有 XML 正文）；10 个未开播频道都能进（6-7），只有 85520900 每次被拒（`loginStatus` 10）。
- **样本**：`fixtures/yy/danmaku/` 下 S08-live（AP 登录回答里回显的录制者公网地址换成文档地址 `203.0.113.7`；已进 git 历史，按“不强推”没改历史）、S09-synthetic（`cases.json`：3 个前置帧、38 组），后来 E02.1 加了 S10-audience（`3139586`、`3165186` 各几条，数字换成合成值）。
- **测试**：`packages/live_danmaku/test/sites/yy_test.dart` 现在 68 个（当时 66 个：协议 8、录制对照 3、合成对照 39、连接 16；`c5963f6a9` 守住脱敏地址 +1，E02.1 热度 +1）。其中 38 个由 S09 的 `cases.json` 循环生成（`yy_test.dart:617`），所以 `grep -c "test("` 只数到 31。`packages/live_danmaku/test/exact_websocket_test.dart` 现在 35 个（当时 27 个；SOOP 改用共用连接器时移来 1 个，SOOP B-6 走代理 +7；其中 8 个协议错误用例由列表循环生成，`exact_websocket_test.dart:463`，`grep` 数到 28）。

## 验证

- 自动测试：`yy_test.dart`——地址、请求头顺序、时长、UUID；包的读写；发出的包与 3.x 逐字节相同、与录制只差 trace id；录制里的地址已脱敏；XML 正文规则；S08 563 帧和 S09 38 组对照 3.x；S10 热度只报本频道的 `3139586`；连接（直连、未就绪、5 s AP ping、被拒后重连同一 UUID、连续被拒 8 次重连后结束、加入后重新计数、15 s 握手超时、退避、换房间、未开播房间、本地 WebSocket 服务器经 `connectExactWebSocket` 端到端）。`exact_websocket_test.dart`——原始 TCP 服务器收到的请求与 `handshake` 逐字节相同、帧和掩码、8 种协议错误的关闭代码、握手失败、和 `dart:io` 服务器互通，B-6 后还有代理隧道。
- 真实接口：上面的 2026-09-29 实测；E02.1 的“国内平台完善”（2026-10-01）22490906、1414787911 各 2 分钟，0.77 s 加入，凌晨没有聊天，`3139586` 215 条和 8 条；C-18 核对时在官网直播间确认标题栏人数就是 `3139586` 的热度（E02.1 记录）。
- 真机：没有单独的真机记录。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 1 节第 1 条要进 YY 直播间（看播放），第 2 节的弹幕条目（第 1 条只列哔哩哔哩、斗鱼、虎牙、抖音、快手）没有 YY；结果一列都还是空的。登记表状态是“完成”。

## 留下的问题

- `3165186` 带一个小得多的计数（2050 对热度 146 万），像真实在线人数，但官网不显示它，核对不了：附录 C-18，[specs/UPGRADES.md](../../../specs/UPGRADES.md) 记为“受阻，未排”，没有任务。
- 礼物：匿名连接收不到，礼物在应用 15012，要多订阅并解新格式：附录 C-20，“受阻，未排”，没有任务。
- YY 的表情代码（`/{tx`、`/{mg`）原样显示成文字：3.x 没有 YY 的表情表，没有任务；要做先找到网页的表情表，按 D-026 在 V01 提议。
- 名字为空时的 `YY用户`（`yy.dart:45`）是写死的中文，英文界面也是中文（pure_live_TV 用 `danmaku_anonymous_user`）：归 [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md) 的 C 类（弹幕层的中文文字）。
- 不走代理：用户开着代理时 YY 弹幕仍直连（3.x 如此）。没有任务；要走代理时照 SOOP（B-6）改用 `connectExactWebSocketViaRoute`，并在登记处传代理。
- YY 不在真机清单第 2 节：建议在清单第 2 节第 1 条加上 YY（文档维护，见报告）；真机结果等 [S03.1](../../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md) 统一验证。
