# D01.8 SOOP 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `e97d20574`）
- 类型：平台
- 来源：模块重构（弹幕协议的第 7 个平台）：把 3.x 的 `lib/core/danmaku/soop_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一（韩国 SOOP，原 AfreecaTV）；2026-10-01 又做了已批准升级 B-6
- 旧编号：M5.7、T06a.8
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；保留大小写的握手和 YY 共用（[D01.7](../D01.7-YY直播弹幕/README.md)，B-6 在同一文件里加了走代理的版本）；平台本身 [E03.1](../../../E-直播平台/E03-海外平台/E03.1-SOOP/README.md)（弹幕参数、TLS 和明文两个地址、7-6，见 [E03.1 记录](../../../E-直播平台/E03-海外平台/E03.1-SOOP/record.md)）；巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)；升级条目 [specs/UPGRADES.md](../../../specs/UPGRADES.md) 的 7-6、B-6
- 记录：[record.md](record.md)

## 目标

SOOP 直播间的弹幕照 3.x 的协议连上和显示；修掉 3.x 只连 TLS 端口、在 TLS 被断开的网络上永远连不上的问题（失败后换明文端口），握手最长约 20 s 改成 10 s，不再把每条聊天写进调试日志。后来（B-6）弹幕走应用的代理设置，照网页显示文字为 `1`、`-1`、含 `|` 的聊天，聊天带上发送者 id。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | `SoopDanmakuArgs`（`packages/live_core/lib/src/sites/soop/soop_api.dart:26`）：TLS 地址 `url`（`CHPT + 1`）、明文地址 `plainUrl`（`CHPT`）、`CHATNO`、握手请求头（3.x 的 API 请求头换上 `Origin: https://play.sooplive.co.kr`，存了 Cookie 时带上；键是小写）；聊天主机取 `CHDOMAIN`，没有时由 `CHIP` 拼成 `chat-<十六进制>.sooplive.com`（7-6）；房间没有聊天服务器时参数为 null |
| 地址 | 先 `url`（如 `wss://chat-6e0a4c63.sooplive.com:9001/Websocket/<主播>`），失败后 `plainUrl`（`ws://…:9000/…`），之后两个轮换（`endpoints`，`soop.dart:58`） |
| 握手 | 子协议 `chat`（`:26`）；请求头名字恢复成 3.x 的大小写（`headerName`，`:68`：`User-Agent`、`Sec-Fetch-Dest`……，顺序不变），用 `connectExactWebSocketViaRoute`（`packages/live_danmaku/lib/src/exact_websocket.dart:33`）；明文端口不带 Cookie（`_withoutPlainCookie`，`soop.dart:184`；`plainHeaders`，`:76`）；B-6 起按平台 `soop` 的代理路线，HTTP 代理时先发 `CONNECT <主机>:<端口>`，`wss` 在隧道里做 TLS；代理的用户名、密码不支持；整个握手 10 s |
| 包 | `ESC TAB`（`1B 09`）、4 位十进制服务号、6 位十进制包体字节数、`00`、包体（包头 14 字节，`:38`）；字段以换页符 `0C` 分隔；发出的包都用文本帧；切包（`packets`，`:86`）遇到前缀、服务号、长度不对或超出帧尾就停，数字照 3.x 用 `int.tryParse` 宽松读 |
| 加入 | 打开即就绪，立即发登录包 `ESC TAB 0001 000006 00 \f\f\f16\f`（`login`，`:44`），200 ms 后发加入包 `ESC TAB 0002 <CHATNO 的 UTF-8 字节数 + 6> 00 \f<CHATNO>\f\f\f\f\f`（`join`，`:51`；`joinDelay`，`:32`）；200 ms 里换了连接时旧连接的加入包不发（`_join`，`:227`）；每次重连都重新发 |
| 心跳 | 20 s 发 `ESC TAB 0000 000001 00 \f`（`heartbeat`，`:47`；`heartbeatInterval`，`:29`）；无消息 90 s（max(3 × 20 s, 90 s)）换连接；握手 10 s；两个地址，重连间隔 1、2、2、3、3、4、4、5 s，8 次后放弃；没有加入计时器 |
| 聊天 | 只有服务 5（`chatService`，`:35`；`chat`，`:118`）：字段少于 7 个不要；文字字段 1、昵称字段 6，去首尾空白，为空丢掉；B-6 起字段 2 照网页 `realID` 去掉 `(n)` 作用户 id（`userId`，`:138`，正则 `:143`）；白色；没有消息 id、时间、等级；其他服务（观众名单、标记、星气球等）不解码 |
| 没有参数 | 房间没有聊天服务器（`connect(null)`）时以 `connectionFailed`（`No chat server`）结束，不连接（`soop.dart:205`），对应 3.x 的“服务器连接失败” |
| 出错 | 收到的文本帧忽略（`onData`，`:233`，3.x 只写日志）；坏 UTF-8 换成替换字符 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/soop_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/soop.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `SoopDanmaku`（:26），`SoopSite.getDanmaku()`（`core/site/soop/soop_site.dart:41`） | `SoopDanmakuConnection`（:158）继承 `DanmakuSocketConnection`；应用登记在 `apps/pure_live/lib/app/platforms.dart:214`，传应用的 `ProxyPolicy`（注释 :213 写明 B-6） | 一致（已做） |
| 心跳和加入延时 | `heartbeatTime = 20 * 1000`（:43），加入前等 200 ms（:120） | `heartbeatInterval`（:29）、`joinDelay`（:32）、`socketPolicy`（:172） | 一致 |
| 端口 | 只连 TLS 端口（`buildDanmakuWebSocketUrl`，`soop_site.dart:590`），本机网络下 TLS 在 ClientHello 后被断开，9 次都失败 | TLS 失败后换明文端口，约 2.8 s 就绪 | 修好（3.x 问题 1） |
| 握手 | `connectCaseSensitiveWebSocket`（:82），先 TCP 10 s 再等回答 10 s，始终直连 | 共用的 `ExactWebSocket`，整个握手 10 s；B-6 起经 `CONNECT` 隧道走代理 | 修好（3.x 问题 4、5） |
| Cookie | 随握手发送，两个端口都发 | 只随 TLS 握手发，明文端口剥掉（`_withoutPlainCookie`，:184） | 不把登录 Cookie 明文发出去 |
| 过滤 | 文字是 `1`、`-1` 或含 `\|` 的整条丢（`_decodeChatPacket`，:180，判断在 :189） | 照网页全部显示（`chat`，:118） | B-6；韩国直播间观众打“1”投票常见 |
| 用户 id | 不填 | `userId`（:138），去掉 `(n)` | 去重闸门能区分同名观众（B-6） |
| 日志 | 参数、每条聊天的全部字段、文本帧写进调试日志（:76、:184、:148） | 不写 | 修好（3.x 问题 3） |

## 结果

- **提交**：`e97d20574`（2026-09-29，`feat(live_danmaku): SOOP danmaku refactored from v3 (M5.7)`），`83f0e903e`（2026-09-29，改用和 YY 共用的连接器，删掉私有的 `sites/soop/chat_socket.dart`），`083fac138`（2026-10-01，B-6：代理、`1`/`-1`/`|`、发送者 id）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和 3.x 的对照**：`fixtures/soop/danmaku/legacy_expected.dart` 把 3.x 的包和解码搬成独立程序。S07-live（主播 `khm11903`，约 20 s，3586 帧收到）144 条聊天逐字段一致，登录、加入、心跳与 3.x、录制逐字节相同，每帧切出的包长加起来正好等于帧长；S08-synthetic 22 组一致。B-6 之后期望改为“3.x 的输出加上用户 id，`1`/`-1`/`|` 不再丢”（S08 有 5 组按这条变换）。
- **有意差异**（record.md 8 条）：TLS 失败后换明文端口并轮换、Cookie 只随 TLS 握手、请求头名字恢复大小写、加入包只发给打开它的那次连接、整个握手 10 s、请求头有换行时拒绝、`connect(null)` 以 `connectionFailed` 结束、不写调试日志。保持 3.x：打开即就绪、固定等 200 ms 再加入、包用文本帧、不显示星气球进场名单、数字宽松读。
- **实测**：2026-09-29 直连，TLS 约 1 s 失败、报一次重连，约 2.8 s 就绪，25 s 收到 20 条聊天；2026-09-30 匿名录 10 个热门直播间 30 分钟，39,209 个聊天包都是 16 个字段，`|` 只在标志位字段和昵称里（证明不是分隔符），文字是 `1` 的 4 条；经本机 HTTP 代理 4.4 s 就绪、30 s 48 条（同时直连 2.7 s 就绪、30 s 57 条）。
- **样本**：`fixtures/soop/danmaku/` 下 S07-live、S08-synthetic（`cases.json` 22 组），B-6 加了 S09-live-ones-and-bars（4 条 `1` 和一条昵称带 `|` 的聊天，id 和昵称已换成合成值）。
- **测试**：`packages/live_danmaku/test/soop_test.dart` 现在 51 个（当时 50 个；改用共用连接器后 43 个，7 个连接器用例移到 `exact_websocket_test.dart`；B-6 +8）。其中 22 个由 S08 的 `cases.json` 循环生成（`soop_test.dart:633`），所以 `grep -c "test("` 只数到 30。`exact_websocket_test.dart` B-6 后 35 个（+7 个隧道用例）。

## 验证

- 自动测试：`soop_test.dart`——发出的包与 3.x、录制逐字节相同；地址与录制的两次握手相同；请求头大小写和顺序、明文端口去 Cookie；S07 3586 帧、S08 22 组对照 3.x；B-6 的 S09、`realID` 写法、同名观众和同账号两个会话的去重；连接（打开即就绪、登录后 200 ms 加入、20 s 心跳、TLS 失败 1 s 后换明文端口、只有 `CHIP` 时的主机、旧连接的加入包不发、两个端口轮换退避、`connect(null)`、只认正确大小写的本地服务器端到端回放、经本地假代理端到端）。`exact_websocket_test.dart` 的隧道用例（`CONNECT` 请求、代理拒绝、不回答、`wss` 在隧道里 TLS）。
- 真实接口：见上面的实测（2026-09-29、09-30）。
- 真机：没有单独的真机记录。SOOP 要代理，[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 没测海外平台；[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)里没有 SOOP 的条目（第 5 节第 7 条只有 Twitch、Kick，第 6 条播放代理只看媒体请求）。登记表状态是“完成”。

## 留下的问题

- TLS 不通的网络上，每次进房先出现一次“正在尝试重连”，1～2 s 后连上；以后断线也先试 TLS（有意差异 1）：没有任务，是为了在能连 TLS 的网络上和 3.x 一样。
- 代理不允许 `CONNECT` 到 9000、9001 端口时会连不上，要给 SOOP 单独设直连；代理的用户名、密码不支持（应用的代理设置没有这项）：没有任务。
- 文字是 `-1` 或含 `|` 的聊天没录到真实样本（30 分钟 3.9 万条里一条也没有），只用合成帧测过：没有任务。
- 握手 UA 开关的隐患（2026-10-07 读代码发现）：`apps/pure_live/lib/app/platforms.dart:214` 把 `danmakuHandshake()` 的连接器也传给了 SOOP；开关 `PURE_LIVE_PLAIN_WS_UA` 打开时它是 `dart:io` 的 `connectIoSocket`（`:249-258`），会顶替 `connectExactWebSocketViaRoute`，请求头名字变小写，SOOP 服务器不回答（REG-SOOP-001，3.x 问题 2）。默认关，现在不受影响；注释 `:247` 只写了“YY and FC2 keep their own”。去向 [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)：打开开关前 SOOP 登记处不传 `connector`（或把 SOOP 和 YY、FC2 一样排除）。
- 星气球、进场、观众名单不显示（3.x 也不显示）：没有任务，要做先在 V01 提议（D-026）。
- 真机：建议在真机清单第 5 节第 7 条（有代理时的海外平台）加上 SOOP 的弹幕，和 Twitch、Kick 一起由 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 验证（见报告）；目前没有结果。
