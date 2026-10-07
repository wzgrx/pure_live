# D01.11 Picarto 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `863bbf99c`）
- 类型：平台
- 来源：已批准升级 11-7“启用 Picarto 弹幕（归档 v4 已实现）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 Picarto 弹幕，这是新增功能；2026-10-01 又做了已批准升级 B-8
- 旧编号：M5.10、T06a.11
- 相关：决定 D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（撤回 `LiveRetraction`、通知 `LiveNoticeKind`、醒目留言的 `priceText`）；平台本身 [E03.3](../../../E-直播平台/E03-海外平台/E03.3-Picarto/README.md)（弹幕参数、令牌接口录制 S06，见 [E03.3 记录](../../../E-直播平台/E03-海外平台/E03.3-Picarto/record.md)）；醒目留言栏、撤回和通知行的显示 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)；巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)；升级条目 [specs/UPGRADES.md](../../../specs/UPGRADES.md) 的 11-7、B-8
- 记录：[record.md](record.md)

## 目标

Picarto（海外绘画直播）直播间能看到聊天和实时在线人数（3.x 进房只提示一次“此平台的远端弹幕尚未接入”）；修掉归档 v4 实现的两个问题：冷清或未开播的频道每 3 分钟断一次（不发保活）、令牌被拒后用同一令牌无限重连。后来（B-8）照网站显示筹码打赏（醒目留言）、删除和清掉某人的消息（撤回）、系统通知、突袭、订阅。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | `PicartoDanmakuArgs`（`packages/live_core/lib/src/sites/picarto/picarto_api.dart:22`）：平台写法的频道名 `channelName`、频道 id `channelId`；进房时由详情给出，未开播也给，不多发请求；录制详情和关注刷新不给；频道名去空白后为空以 `connectionFailed` 结束 |
| 令牌 | 开始时 `POST https://ptvintern.picarto.tv/ptvapi`（`tokenEndpoint`，`picarto.dart:34`），GraphQL `generateJwtToken(channel_name)`（`tokenQuery`，`:38`）要匿名 JWT；最多 3 次（`tokenAttempts`，`:483`；间隔 0.5、1 s；每次 5 s 超时，`:486`），只接受三段 base64url（`:47`）；都拿不到以 `credentialsUnavailable` 结束，不开连接；JWT 没有 `exp`、`iat`，断线重连沿用；关闭时取消进行中的请求 |
| 地址 | `wss://chat.picarto.tv/chat/token=<JWT>`（`endpoint`，`:58`）；请求头 `origin: https://picarto.tv` 和 Chrome 140 的 UA（`:62`）；默认 `dart:io` 握手（服务端不在乎请求头大小写）；按平台 `picarto` 走代理路线；握手失败的诊断文字里把令牌换成 `token=…`（`_withoutToken`，`:501`） |
| 加入和保活 | 打开即就绪，不发加入消息（`onOpen`，`:565`）；每 50 s 发 `{"type":"ping","message":"__ping__"}`（`:66`、`:71`，网站的值），服务端回 `{"success":true,"code":"PONG"}`；无消息 150 s（max(3 × 50 s, 90 s)）换连接；单地址，重连间隔 2、3、4、5、6、6、6、6 s，8 次后放弃；没有加入计时器 |
| 令牌被拒 | 服务端不关连接，只回 `{"success":false,"code":"JWT_TOKEN"}`（`refusedCode`，`:74`）：标为未加入、重取令牌、`reopen`，不提示；每次 `connect` 最多换 3 次（`maxTokenRefreshes`，`:489`），第 4 次被拒或拿不到新令牌以 `credentialsUnavailable` 结束 |
| 消息 | JSON 文本帧（二进制帧也按 UTF-8 读），`type`/`t`、`messages`/`m` 两种写法都读（`decode`，`:117`）；`c` 帧每行一条（`line`，`:162`）：行的 `t` 为 `c` 的是聊天（`chat`，`:181`：`n` 名字、`u` 用户 id、`m` 文本去空白、`id`/`_id` 消息 id 不加前缀、`d` 毫秒时间、`k` 颜色按 6 位十六进制或 CSS 3 位简写，其他白色，`color`，`:396`）；`stream` 帧的 `viewers` → `onlineViewers`（`audience`，`:378`，`id` 不是本频道不报）；历史记录页（`paginated`/`p` 为真）整帧跳过；`c`（发言所在频道）不检查，多人同播时全部显示 |
| 打赏（B-8） | 带真值 `v` 的聊天行或 `ct` 行 → 醒目留言（`tip`，`:212`）：价格 `x`（大于 0 的整数，否则这一行不报），`priceText` 写 `<x> Kudos`（`tipUnit`，`:87`），头像 `i` 前加 `https://images.picarto.tv/`（`:84`），开始 `d`（没有用收到的时间），显示 60 s（`tipDuration`，`:80`）；多人同播时 `rn` 不是本频道就在附言前加“打赏给 <rn>”；外层消息带行的 `id`、`u`、`d`，可被撤回 |
| 撤回（B-8） | `rm` → `LiveRetraction.message(m.id)`（`deletion`，`:359`）；`cm` → `LiveRetraction.user(m.u)`（`clearance`，`:369`）；撤回消息自己不带 id |
| 通知（B-8） | `system` 行 → `system`（`system`，`:269`：`{link}` 换成链接文字、`{icon}` 去掉，多行用空格连起来；帧的 `c` 为 `b`（只给房管看）不报）；`raid` → `raid`（`raid`，`:297`，服务端文字，没有时拼“<n> 突袭了 <rn>”，不跳转）；`ns` → `subscription`（`subscription`，`:328`，按网站的分支拼成中文句子，名字缺了不报）；`ctt`（打赏榜）、进出名单、私信、投票、抽奖不报 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | 3.x 有这个平台但没有弹幕：`PicartoSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/picarto/picarto_site.dart:30`；`EmptyDanmaku` 在 `lib/core/danmaku/empty_danmaku.dart:9`），直播间提示一次 `remote_danmaku_not_integrated`（`modules/live_play/controllers/danmaku_controller.dart:146-150`） | `PicartoDanmakuConnection`（`packages/live_danmaku/lib/src/sites/picarto.dart:461`）继承 `DanmakuSocketConnection`；应用登记在 `apps/pure_live/lib/app/platforms.dart:217`（传 `LiveHttp`、代理） | 有聊天和人数（已做） |
| 协议 | 无 | `PicartoDanmakuProtocol`（:32）：地址 :58、保活 :66、`decode`（:117）、`chat`（:181）、打赏 `tip`（:212）、`system`（:269）、`raid`（:297）、`subscription`（:328）、撤回 `deletion`（:359）、`clearance`（:369）、人数 `audience`（:378） | 与归档 v4 对照，有意差异 16 条 |
| 保活 | 无 | 50 s 应用层保活（归档 v4 不发，冷清频道 180 s 看门狗就断） | 未开播和冷清的频道不再被当成断线 |
| 令牌被拒 | 无 | 换令牌，`maxTokenRefreshes = 3`（:489）（归档 v4 识别不了，用同一令牌无限重连） | 不再无限重连 |
| 在线人数 | 目录、详情的 `viewers` | 弹幕 `stream.viewers` 是同一个数（S04 详情 52 对 S07 的 53） | 进房后实时更新 |

## 结果

- **提交**：`863bbf99c`（2026-09-29，`feat(live_danmaku): Picarto danmaku (M5.10)`），`7eb985f24`（2026-10-01，`feat(live_danmaku): Picarto chip tips, notices and retractions (M5.F, B-8)`）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和归档 v4 的对照**（3.x 没有可对照的行为）：`fixtures/picarto/danmaku/v4_expected.dart` 把归档 v4 的协议搬成独立程序。令牌请求、地址、握手请求头与 v4 和录制相同；S07-live（频道 allatir，约 100 s）1 条聊天、6 次人数一致；S09-keepalive 4 次人数一致，发出的保活与录下的 3 次逐字相同；S10-token-refused v4 读不出被拒、新代码识别；S11-synthetic 23 组里 14 组一致、9 组是有意差异；B-8 后 S11 有 3 组期望改变（`system`、`raid`、`ns` 变成通知，打赏变成醒目留言）。
- **和归档 v4 的差异**（record.md 16 条），主要是：50 s 保活、令牌被拒换令牌并限次、令牌重试 3 次、只报本频道人数、历史页跳过、按行的类型报、读 `_id`、颜色照 CSS、时间超范围只丢这一行、诊断不带令牌、结束原因用 D01.1 的类型。
- **实测**（2026-09-28 匿名直连）：未开播频道 240 s 一条文本消息也没有（证明需要保活）；编造的令牌握手照样成功、立刻回 `JWT_TOKEN`；7 分钟前的令牌照样能用；本实现连 allatir 2.3 s 就绪。2026-09-30 对 45 个频道各连 150 分钟，只录到 1 次打赏、1 次 `rm`、1 条 `system`（`ct`、`cm`、`raid`、`ns` 没出现）。
- **样本**：`fixtures/picarto/danmaku/` 下 S07-live、S09-keepalive、S10-token-refused、S11-synthetic（`cases.json` 23 组），B-8 加了 S12-b8-synthetic（20 组）、S13-removed、S14-tip、S15-system；令牌都没有保存，观众字段已换成合成值。
- **测试**：`packages/live_danmaku/test/picarto_test.dart` 现在 81 个（当时 53 个，另做过 15 种变异；B-8 +28，另做过 18 种变异）。其中 23 + 20 = 43 个由 S11、S12 的 `cases.json` 循环生成（`picarto_test.dart:700`、`:728`），所以 `grep -c "test("` 只数到 40。

## 验证

- 自动测试：`picarto_test.dart`——令牌请求和读法（S06、S07、S09）、地址和握手头与 v4 和录制相同、保活与 S09 发出的帧相同；S07、S09、S10 和 S11 23 组对照 v4；B-8 的 S12 20 组、打赏和撤回和通知逐字段、S13 `rm` 撤回的正是前一行聊天、S14 录到的打赏、S15 录到的系统通知；连接（令牌 3 次后成功、拿不到令牌不开连接、取令牌时关闭取消请求、50 s 保活、只报本频道人数、被拒后换令牌立刻重开、第 4 次被拒结束、断线用同一令牌重连、退避详情不带令牌、换房间取新令牌、本地 WebSocket 服务器端到端：路径里的令牌、Origin、录制的帧、保活和应答）。
- 真实接口：见上面的实测。没实测到的：`ct` 帧、`cm`、`raid`、`ns`、带链接和房管专用的 `system`，都用合成帧。
- 真机：没有单独的真机记录。Picarto 是海外平台，要代理；[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)里没有 Picarto 的条目（第 5 节第 7 条只有 Twitch、Kick）。登记表状态是“完成”。

## 留下的问题

- `rm` 撤下整行，网站是留一行“已删除”文字：撤回模型（D01.1）没有替换文字，没有任务。
- 打赏附言里的 chipmote（`kudo100`）照文字显示，不换图片；打赏框的边框颜色帧里没有：没有任务（飞行弹幕的表情图在 D03.2，Picarto 没有表情表）。
- 醒目留言 60 s 后离开醒目留言栏是自定的（网站没有时长，取哔哩哔哩最短一档）：没有任务。
- 突袭后不跟随跳转到被突袭的频道：不在 B-8 里，不做。
- 真机：建议在真机清单第 5 节第 7 条（有代理时的海外平台）加上 Picarto 的弹幕，由 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 一起看（见报告）。
