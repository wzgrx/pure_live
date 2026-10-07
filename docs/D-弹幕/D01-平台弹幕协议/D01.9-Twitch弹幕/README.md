# D01.9 Twitch 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `9f1f3de1f`）
- 类型：平台
- 来源：模块重构（弹幕协议的第 8 个平台）：把 3.x 的 `lib/core/danmaku/twitch_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一；2026-09-30 又做了已批准升级 B-7
- 旧编号：M5.8、T06a.9
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（撤回 `LiveRetraction`、通知 `LiveNoticeKind`）；平台本身 [E03.2](../../../E-直播平台/E03-海外平台/E03.2-Twitch/README.md)（聊天登录 `TwitchApi.chatLogin`，见 [E03.2 记录](../../../E-直播平台/E03-海外平台/E03.2-Twitch/record.md)）；撤回和通知行的显示 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)；Cookie 失效的界面提示余项 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/brief.md)；有代理时的真机验证 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)；升级条目 [specs/UPGRADES.md](../../../specs/UPGRADES.md) 的 B-7
- 记录：[record.md](record.md)

## 目标

Twitch 直播间的聊天照 3.x 用 IRC over WebSocket 拿到，有登录 Cookie 就用账号、否则匿名；修掉 3.x 存的 Cookie 失效后永远“重连—已连接”循环收不到弹幕、服务器 `PING` 和聊天同帧时把整帧发回服务器、`/me` 显示 `\x01ACTION`、一行坏时间丢整帧、蓝色名字显示成白色这些问题。后来（B-7）照网页处理 `RECONNECT`（悄悄换连接）、`CLEARMSG`/`CLEARCHAT`（撤回）、`USERNOTICE`（订阅、突袭、公告等通知），Cookie 失效时提示一次。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | `TwitchDanmakuArgs`（`packages/live_core/lib/src/sites/twitch/twitch_api.dart:32`）：频道登录名 `channel`（小写），同一份 Cookie 里有 `login` 和 `auth-token` 时的聊天登录 `chat`（`TwitchApi.chatLogin`，`twitch_api.dart:345`，进房时从 `CookieVault` 读）；没有就是 null，匿名加入 |
| 地址 | 只有 `wss://irc-ws.chat.twitch.tv`（`twitch.dart:127`，不写端口），不带请求头和子协议；走应用的代理设置（平台 id `twitch`） |
| 加入 | 打开后依次发 `PASS`、`NICK`、`CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership`、`JOIN #<频道>`（`join`，`:151`），每行一个文本帧、不加 CRLF，然后就算加入（`onOpen`，`:447`），不等服务器的 `JOIN`/`ROOMSTATE`；频道去空白转小写 |
| 登录 | 有登录时 `PASS oauth:<令牌>`、`NICK <登录名>`；否则 `PASS SCHMOOPIIE`（`anonymousPassword`，`:141`）、`NICK justinfan<1000～99999>`（`anonymousNick`，`:145`，每次加入重新随机）；收到 `NOTICE *`（`isLoginRejection`，`:375`）立即先报一条 `cookieExpiredNotice`（`:187`，“Twitch 的 Cookie 已失效，弹幕已改为匿名接收，请重新填写 Twitch Cookie”），再改匿名 `reopen`，这次 `connect` 不再用令牌（`_loginRejected`，`:477`）；下次进房再试 |
| 心跳 | 40 s 发 `PING :tmi.twitch.tv`（`:130`、`:134`）；服务器的 `PING` 逐行回 `PONG`（`decode` 里 `:208`）；无消息 120 s（max(3 × 40 s, 90 s)）换连接；单地址，重连间隔 2、3、4、5、6、6、6、6 s，8 次后放弃；没有加入计时器 |
| 帧 | 文本帧和二进制帧都读（二进制按 UTF-8，坏字节换 U+FFFD），按 `\r\n` 或 `\n` 分行；一行解析失败只丢这一行 |
| 聊天 | 含 ` PRIVMSG ` 的行（`chat`，`:323`，照 3.x 不看命令）：标签在 `@` 到第一个空格之间，按 3.x 的顺序整体替换反转义（`unescapeTag`，`:358`）；文字是 ` PRIVMSG ` 之后第一个 ` :` 后面的全部；名字 `display-name`（空时取前缀昵称，再没有是 `Twitch`）；`user-id`、消息 id `id`（不加前缀）、时间 `tmi-sent-ts`；颜色 `color` 经 E05.1 修正后的 `numberToColor`；`/me` 去掉 CTCP 包装（`_action`，`:165`；`_withoutAction`，`:367`） |
| 撤回（B-7） | `command`（`:249`）：`CLEARMSG` → `LiveRetraction.message(target-msg-id)`；`CLEARCHAT` 带 `target-user-id` → `.user(id)`，什么都不带（清屏）→ `.all()`；带登录名却没 id、`target-msg-id` 为空的跳过；这三种命令的标签按 IRCv3 从左到右反转义（`TwitchIrcLine.unescape`，`:83`） |
| 通知（B-7） | `USERNOTICE`：订阅类 12 种（`subscriptionNotices`，`:170`）→ `subscription`，`raid` → `raid`，`announcement` → `system`（文字用公告内容），其他 `msg-id` 的 `system-msg` 非空就显示为 `system`；`sharedchatnotice` 按 `source-msg-id` 分类；观众附带的话（续订留言等）作为他的聊天紧跟在通知后，带这条通知的 `id`、`user-id`；`system-msg` 是 Twitch 给的英文原文 |
| `RECONNECT`（B-7） | 立即用同一登录 `reopen`，不报重连也不再报就绪（`_switch`，`twitch.dart:493`）；距上次这样换不到 10 s（`switchInterval`，`:425`）就按普通重连 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/twitch_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/twitch.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `TwitchDanmaku`（:9），`TwitchSite.getDanmaku()`（`core/site/twitch/twitch_site.dart:523`） | `TwitchDanmakuConnection`（:407）继承 `DanmakuSocketConnection`；应用登记在 `apps/pure_live/lib/app/platforms.dart:212`，传应用的 `ProxyPolicy` | 一致（已做） |
| 地址和心跳 | `serverUrl`（:29），`heartbeatTime = 40 * 1000`（:27），心跳 :45 | `endpoint`（:127），`heartbeatInterval`（:130），`socketPolicy`（:418） | 一致 |
| 加入 | `joinRoom`（:76），每次加入去设置里读 Cookie（`_parseCookie`，:90），匿名昵称 :82，`PASS` :84 | `join`（:151），匿名 `anonymousPassword`（:141）、`anonymousNick`（:145）；登录取自参数（E03.2 进房时从 `CookieVault` 读） | 加入行与 3.x 读同一 Cookie 的结果相同（11 种写法核对）；换 Cookie 要重新进房 |
| Cookie 失效 | 不看 `NOTICE *`，用同一令牌每约 14 s 重连一次，永不停 | 被拒改匿名重开（`loginRejected`，:24、:210；`_loginRejected`，:477），报 `cookieExpiredNotice`（:187） | 修好（3.x 问题 1）；提示是 B-7 |
| 服务器 `PING` | 整帧判断（:112-114），`PING` 在帧首时把整帧（含别人的聊天）发回服务器 | 逐行回复（:208） | 修好（3.x 问题 2） |
| `/me` | 显示 `\x01ACTION 文字\x01` | `_action`（:165）、`_withoutAction`（:367）去掉包装 | 修好（3.x 问题 3） |
| 坏时间 | 整帧一个 `try`，一行时间超范围丢整帧 | 逐行 `try`（`decode`，:202） | 修好（3.x 问题 4） |
| 颜色 | 按十六进制位数解析，`#0000FF` 变白（实测 5% 的名字受影响） | 修正后的 `numberToColor` | 修好（3.x 问题 5） |
| 标签反转义、无标签行的名字、文字含 ` PRIVMSG ` | `_decodeTag`（:170）依次整体替换；只认 ` PRIVMSG `（:130、:144） | 聊天照 3.x（`unescapeTag`，:358；`chat`，:323） | 保持 3.x（3.x 问题 6～8，影响极小） |
| 其他命令 | `CLEARMSG`/`CLEARCHAT`/`USERNOTICE`/`RECONNECT` 都不处理 | `command`（:249-307）、`RECONNECT`（:214） | 撤回、通知、悄悄换连接（B-7） |

## 结果

- **提交**：`9f1f3de1f`（2026-09-29，`feat(live_danmaku): Twitch danmaku refactored from v3 (M5.8)`），`51c28301b`（2026-09-30，B-7：`RECONNECT`、撤回、通知、Cookie 失效提示）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和 3.x 的对照**：`fixtures/twitch/danmaku/legacy_expected.dart` 把 3.x 的加入、解码搬成独立程序（匿名昵称的随机数固定为录制的 `justinfan39976`）。S07-live（频道 `zarbex`，约 37 s，22 帧收到）18 条聊天逐字段一致；S08-synthetic 24 组里 2 组移植 3.x 的用例一致，其余 22 组 17 组一致、5 组是有意差异（颜色、超范围时间、`/me`、两种 `PING` 位置）；B-7 后有 2 组（其他命令、含 ` PRIVMSG ` 的其他命令）按新读法变换。
- **有意差异**（record.md 7 条）：登录被拒改匿名、`PING` 逐行回复、`/me` 去包装、逐行容错、颜色修正、登录取自参数、`connect` 只接受 `TwitchDanmakuArgs`。保持 3.x：打开即就绪、加入顺序和 membership、有登录就用账号、40 s/120 s、消息 id 不加前缀、不检查频道、每次重连换新匿名昵称、走代理。
- **实测**：2026-09-29 用编造的令牌登录，约 200 ms 后收到 `NOTICE * :Login authentication failed`，约 12 s 后服务器断开（证明 3.x 问题 1）；匿名收 18 个热门频道 90 s 共 967 条聊天（`/me` 5 条、受颜色问题影响 49 条）。2026-09-30 匿名录 30 个最热门频道各 20 分钟：59401 行聊天、354 行 `USERNOTICE`、154 行 `CLEARCHAT`（都带 `target-user-id`，没有清屏）、20 行 `CLEARMSG`、0 行 `RECONNECT`。
- **样本**：`fixtures/twitch/danmaku/` 下 S07-live、S08-synthetic（`cases.json` 24 组），B-7 加了 S09-live（`ironmouse` 94 帧：订阅、突袭、撤回）、S10-live（`caedrel` 92 帧：续订留言、公告），都已脱敏。
- **测试**：`packages/live_danmaku/test/twitch_test.dart` 现在 71 个（当时 49 个，另做过 10 种变异；B-7 +22，另做过 12 种变异）。其中 24 个由 S08 的 `cases.json` 循环生成（`twitch_test.dart:512`），所以 `grep -c "test("` 只数到 48。

## 验证

- 自动测试：`twitch_test.dart`——11 种 Cookie 的加入行对照 3.x；S07 22 帧、S08 24 组对照 3.x；B-7 合成帧（撤回、通知 12 种、公告、`sharedchatnotice`、`RECONNECT` 写法）；S09、S10 录制帧的通知和撤回逐条、撤回对得上前面的聊天；连接（账号登录、代理路线、40 s 心跳、逐行回 `PING`、登录被拒后不等退避以匿名重开并提示一次、`RECONNECT` 立即换连接不报重连和就绪、10 s 内第二次按普通重连、退避、换房间、本地 WebSocket 服务器端到端含服务器发 `RECONNECT` 后在第二个连接上重新加入）。
- 真实接口：见上面的实测。没实测到的：`RECONNECT`、清屏的 `CLEARCHAT`、带用户没 id 的 `CLEARCHAT`、`sharedchatnotice`、登录被拒后的提示（被拒本身实测过），都用合成帧。
- 真机：没有单独的真机记录。Twitch 要代理，[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 没测；[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 5 节第 7 条（有代理时进 Twitch、Kick 直播间，预期只写了“能播”）归 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)，结果还是空的。登记表状态是“完成”。

## 留下的问题

- 收到 `RECONNECT` 时先关旧连接再连新的，中间约 0.2～0.5 s 加握手时间的聊天会漏掉；先连后关要框架让一个会话的两个连接并存：没有任务（D01.1 框架的后续，录到 0 次 `RECONNECT`，收益小）。
- Cookie 失效提示目前是聊天列表里的一行系统通知；账号页、平台层的 Cookie 提示去向 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/brief.md)（暂停，“Twitch Cookie 提示和编码”阶段，附录 B-7 的余项）。
- `USERNOTICE` 的 `system-msg` 是 Twitch 给的英文原文，不翻译：没有任务（平台给的内容不翻译，见 Z05.2 的范围）。
- 真机：建议在 S02.4 的第 12 步（真机清单第 5 节第 7 条）加一句“Twitch 有弹幕”，一并看弹幕（见报告）。
