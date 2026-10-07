# D01.9 Twitch 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：模块重构（M5 的第 8 个平台）：把 3.x 的 `lib/core/danmaku/twitch_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一
- 旧编号：M5.8、T06a.9
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、聊天登录 `TwitchApi.chatLogin` [E03.2 记录](../../../E-直播平台/E03-海外平台/E03.2-Twitch/record.md)；撤回和通知的显示在直播间（C01.1）；Cookie 失效的界面提示余项在 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/README.md)；详细记录 [record.md](record.md)

## 目标

Twitch 直播间的聊天照 3.x 用 IRC over WebSocket 拿到，有登录 Cookie 就用账号、否则匿名；修掉 3.x 存的 Cookie 失效后永远“重连—已连接”循环收不到弹幕、`/me` 显示 `\x01ACTION`、蓝色名字显示成白色等问题。后来（B-7）照网页处理 `RECONNECT`（悄悄换连接）、`CLEARMSG`/`CLEARCHAT`（撤回）、`USERNOTICE`（订阅、突袭、公告通知），Cookie 失效时提示一次。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | 只有 `wss://irc-ws.chat.twitch.tv`，不带请求头和子协议；走应用的代理设置（平台 id `twitch`） |
| 加入 | 打开后依次发 `PASS`、`NICK`、`CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership`、`JOIN #<频道>`，每行一个文本帧，然后就算加入（不等服务器的 `JOIN`/`ROOMSTATE`） |
| 登录 | `TwitchDanmakuArgs.chat` 有登录时 `PASS oauth:<令牌>`、`NICK <登录名>`；否则 `PASS SCHMOOPIIE`、`NICK justinfan<1000～99999>`（每次加入重新随机）；收到 `NOTICE *`（登录被拒）立即改匿名重开，这次连接不再用令牌，并报一条“Twitch 的 Cookie 已失效……”的系统通知 |
| 心跳 | 40 s 发 `PING :tmi.twitch.tv`；服务器的 `PING` 逐行回 `PONG`；无消息 120 s 换连接；单地址，重连间隔 2～6 s |
| 聊天 | 含 ` PRIVMSG ` 的行：标签在 `@` 到第一个空格之间；名字 `display-name`（空时取前缀昵称，再没有是 `Twitch`）；`user-id`、消息 id `id`（不加前缀）、时间 `tmi-sent-ts`；颜色 `color` 经修正后的 `numberToColor`；`/me` 去掉 CTCP 包装 |
| 撤回 | `CLEARMSG` → `LiveRetraction.message(target-msg-id)`；`CLEARCHAT` 带 `target-user-id` → `.user(id)`，什么都不带（清屏）→ `.all()`；带登录名却没 id 的跳过 |
| 通知 | `USERNOTICE`：订阅类 12 种 → `subscription`，`raid` → `raid`，`announcement` → `system`（文字用公告内容），其他 `msg-id` 的 `system-msg` 非空就显示为 `system`；观众附带的话作为他的聊天紧跟在通知后 |
| `RECONNECT` | 立即用同一登录 `reopen`，不报重连也不再报就绪；10 s 内第二次按普通重连 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/twitch_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/twitch.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `TwitchDanmaku`（:9），`TwitchSite.getDanmaku()`（`core/site/twitch/twitch_site.dart:523`） | `TwitchDanmakuConnection`（:407）；应用登记在 `apps/pure_live/lib/app/platforms.dart:212` | 一致 |
| 地址和心跳 | `serverUrl`（:29），`heartbeatTime = 40 * 1000`（:27），心跳 :45 | `endpoint`（:127），`heartbeatInterval`（:130），`socketPolicy`（:418） | 一致 |
| 加入 | :84 起，每次加入去设置里读 Cookie | 匿名 `anonymousPassword`（:141）、`anonymousNick`（:145）；登录取自参数（E03.2 进房时从 `CookieVault` 读） | 加入行与 3.x 读同一 Cookie 的结果相同（11 种写法核对） |
| Cookie 失效 | 不看 `NOTICE *`，用同一令牌每约 14 s 重连一次，永不停 | 被拒改匿名重开（`loginRejected`，:24、:210），报 `cookieExpiredNotice`（:187） | 修好（3.x 问题 1） |
| 服务器 `PING` | 整帧判断（:112～114），`PING` 在帧首时把整帧（含别人的聊天）发回服务器 | 逐行回复 | 修好（3.x 问题 2） |
| `/me` | 显示 `\x01ACTION 文字\x01` | `_action`（:165）去掉包装 | 修好（3.x 问题 3） |
| 颜色 | 按十六进制位数解析，`#0000FF` 变白（实测 5% 的名字受影响） | 修正后的 `numberToColor` | 修好（3.x 问题 5） |
| 其他命令 | 只认 ` PRIVMSG `（:130），`CLEARMSG`/`CLEARCHAT`/`USERNOTICE`/`RECONNECT` 都不处理 | `command`（:229～285）、`RECONNECT`（:214） | 撤回、通知、悄悄换连接（B-7） |

## 结果

- **提交**：9f1f3de1f（2026-09-29，M5.8），51c28301b（2026-09-30，B-7）。
- **和 3.x 的对照**：`fixtures/twitch/danmaku/legacy_expected.dart` 把 3.x 的加入、解码搬成独立程序（匿名昵称的随机数固定为录制的 `justinfan39976`）。S07-live（频道 `zarbex`，22 帧）18 条聊天逐字段一致；S08-synthetic 24 组里 17 组一致、5 组是有意差异（颜色、超范围时间、`/me`、两种 `PING` 位置）。
- **实测**：2026-09-29 用编造的令牌登录，约 200 ms 后收到 `NOTICE * :Login authentication failed`，约 12 s 后服务器断开（证明 3.x 问题 1）；匿名收 18 个热门频道 90 s 共 967 条聊天做统计。2026-09-30 匿名录 30 个最热门频道各 20 分钟：59401 行聊天、354 行 `USERNOTICE`、154 行 `CLEARCHAT`、20 行 `CLEARMSG`、0 行 `RECONNECT`。
- **保持 3.x 没改的**：标签反转义的顺序、没有标签的行的名字、文字含 ` PRIVMSG ` 的其他命令（3.x 问题 6～8，影响极小）；打开即就绪；请求 membership；有登录就用账号；每次重连换新匿名昵称。
- **样本**：`fixtures/twitch/danmaku/` 的 S07-live、S08-synthetic、S09-live（`ironmouse`：订阅、突袭、撤回）、S10-live（`caedrel`：续订留言、公告）。
- **测试**：`packages/live_danmaku/test/twitch_test.dart` 做完时 49 个（另做过 10 种变异），B-7 后 71 个（+22，另做过 12 种变异）。

## 验证

- 自动测试：`twitch_test.dart`（本地 WebSocket 服务器端到端回放、`RECONNECT` 后在第二个连接上重新加入）。
- 真实接口：见上面的实测。没实测到的：`RECONNECT`、清屏的 `CLEARCHAT`、`sharedchatnotice`、登录被拒后的提示（被拒本身实测过），都用合成帧。
- 真机：没有。Twitch 要代理，[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 记为“没测”，归 S02.4。

## 留下的问题

- 收到 `RECONNECT` 时先关旧连接再连新的，中间约 0.2～0.5 s 加握手时间的聊天会漏掉；先连后关要框架让一个会话的两个连接并存（D01.1 框架的后续，没有登记任务）。
- Cookie 失效提示目前是聊天列表里的一行系统通知；账号页、平台层的 Cookie 提示随 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/README.md)（附录 B-7 的余项）。
- `USERNOTICE` 的 `system-msg` 是 Twitch 给的英文原文，不翻译。
