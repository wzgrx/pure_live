# D01.8 SOOP 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：模块重构（M5 的第 7 个平台）：把 3.x 的 `lib/core/danmaku/soop_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一（韩国 SOOP，原 AfreecaTV）
- 旧编号：M5.7、T06a.8
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；保留大小写的握手和 YY 共用（[D01.7](../D01.7-YY直播弹幕/README.md)）；平台本身和弹幕参数 [E03.1 记录](../../../E-直播平台/E03-海外平台/E03.1-SOOP/record.md)；详细记录 [record.md](record.md)

## 目标

SOOP 直播间的弹幕照 3.x 的协议连上和显示；修掉 3.x 只连 TLS 端口、在 TLS 被断开的网络上永远连不上的问题（换到明文端口），握手最长约 20 s 改成 10 s，不再把每条聊天写进调试日志。后来（B-6）弹幕走应用的代理设置，照网页显示文字为 `1`、`-1`、含 `|` 的聊天，聊天带上发送者 id。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | `SoopDanmakuArgs` 给两个：先 `url`（TLS，`CHPT + 1`，如 `wss://chat-6e0a4c63.sooplive.com:9001/Websocket/<主播>`），失败后 `plainUrl`（明文 `CHPT`，`ws://…:9000/…`），之后两个轮换；主机取 `CHDOMAIN`，没有时由 `CHIP` 拼成 `chat-<十六进制>.sooplive.com`（附录 7-6） |
| 握手 | 子协议 `chat`；请求头名字恢复成 3.x 的大小写（`User-Agent`、`Sec-Fetch-Dest`……），用 `connectExactWebSocketViaRoute`（`packages/live_danmaku/lib/src/exact_websocket.dart`）；明文端口不带 Cookie；B-6 起按平台 `soop` 的代理路线，HTTP 代理时先发 `CONNECT` |
| 包 | `ESC TAB`（`1B 09`）、4 位服务号、6 位包体字节数、`00`、包体；字段以换页符 `0C` 分隔；都用文本帧发送 |
| 加入 | 打开即就绪，立即发登录包 `ESC TAB 0001 000006 00 \f\f\f16\f`，200 ms 后发加入包（带 `CHATNO`）；200 ms 里换了连接时旧连接的加入包不发 |
| 心跳 | 20 s 发 `ESC TAB 0000 000001 00 \f`；无消息 90 s 换连接；两个地址，重连间隔 1、2、2、3、3、4、4、5 s |
| 聊天 | 只有服务 5：字段少于 7 个不要，文字字段 1、昵称字段 6，去首尾空白，为空丢掉；B-6 起字段 2 照网页 `realID` 去掉 `(n)` 作用户 id；白色 |
| 没有参数 | 房间没有聊天服务器（参数 null）时以 `connectionFailed` 结束（3.x“服务器连接失败”） |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/soop_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/soop.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `SoopDanmaku`（:26），`SoopSite.getDanmaku()`（`core/site/soop/soop_site.dart:41`） | `SoopDanmakuConnection`（:158）；应用登记在 `apps/pure_live/lib/app/platforms.dart:214`，传应用的 `ProxyPolicy` | 一致 |
| 心跳和加入延时 | `heartbeatTime = 20 * 1000`（:43），200 ms（:120） | `heartbeatInterval`（:29）、`joinDelay`（:32）、`socketPolicy`（:172） | 一致 |
| 端口 | 只连 TLS 端口（`buildDanmakuWebSocketUrl`，`soop_site.dart:590`），本机网络下 TLS 在 ClientHello 后被断开，9 次都失败 | TLS 失败后换明文端口，约 2.8 s 就绪 | 修好（3.x 问题 1） |
| 握手 | `connectCaseSensitiveWebSocket`（:82），先 TCP 10 s 再等回答 10 s，始终直连 | 共用的 `ExactWebSocket`，整个握手 10 s；B-6 起经 `CONNECT` 隧道走代理 | 修好（3.x 问题 4、5） |
| Cookie | 随握手发送 | 只随 TLS 握手发，明文端口剥掉（`_withoutPlainCookie`，:184） | 不把登录 Cookie 明文发出去 |
| 过滤 | 文字是 `1`、`-1` 或含 `|` 的整条丢（:189） | 照网页全部显示 | B-6；韩国直播间观众打“1”投票常见 |
| 用户 id | 不填 | `realId`（:140～143） | 去重闸门能区分同名观众（B-6） |
| 日志 | 每条聊天的全部字段写进调试日志（:76、:148、:184 一带） | 不写 | 修好（3.x 问题 3） |

## 结果

- **提交**：e97d20574（2026-09-29，M5.7），83f0e903e（改用和 YY 共用的连接器，删掉私有的 `sites/soop/chat_socket.dart`），083fac138（2026-10-01，B-6）。
- **和 3.x 的对照**：`fixtures/soop/danmaku/legacy_expected.dart` 把 3.x 的包和解码搬成独立程序。S07-live（主播 `khm11903`，3586 帧）144 条聊天逐字段一致，登录、加入、心跳与 3.x、录制逐字节相同；S08-synthetic 22 组一致。B-6 之后期望改为“3.x 的输出加上用户 id，`1`/`-1`/`|` 不再丢”。
- **实测**：2026-09-29 直连，TLS 约 1 s 失败、报一次重连，约 2.8 s 就绪，25 s 收到 20 条聊天；2026-09-30 匿名录 10 个热门直播间 30 分钟，39,209 个聊天包都是 16 个字段，`|` 只在标志位字段和昵称里（证明不是分隔符）；经本机 HTTP 代理 4.4 s 就绪、30 s 48 条。
- **样本**：`fixtures/soop/danmaku/` 的 S07-live、S08-synthetic、S09-live-ones-and-bars（4 条 `1` 和一条昵称带 `|` 的聊天）。
- **测试**：`packages/live_danmaku/test/soop_test.dart` 做完时 50 个，改用共用连接器后 43 个（7 个连接器用例移到 `exact_websocket_test.dart`），B-6 后 51 个；`exact_websocket_test.dart` B-6 后 35 个（+7 个隧道用例）。

## 验证

- 自动测试：`soop_test.dart`（只认正确大小写的本地服务器端到端回放、本地假代理）、`exact_websocket_test.dart`。
- 真实接口：见上面的实测。
- 真机：没有。SOOP 要代理，[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 记为“没测”；海外平台的真机条目只在用户开着代理时做。

## 留下的问题

- TLS 不通的网络上，每次进房先出现一次“正在尝试重连”，1～2 s 后连上；以后断线也先试 TLS（有意差异 1）。
- 代理不允许 `CONNECT` 到 9000、9001 端口时会连不上，要给 SOOP 单独设直连；代理的用户名、密码不支持（应用的代理设置没有这项）。
- 文字是 `-1` 或含 `|` 的聊天没录到真实样本，只用合成帧测过。
- 星气球、进场、观众名单不显示（3.x 也不显示）。
