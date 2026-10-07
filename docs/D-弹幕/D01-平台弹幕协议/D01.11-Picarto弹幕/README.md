# D01.11 Picarto 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 11-7“启用 Picarto 弹幕（归档 v4 已实现）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 Picarto 弹幕，这是新增功能
- 旧编号：M5.10、T06a.11
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和弹幕参数 [E03.3 记录](../../../E-直播平台/E03-海外平台/E03.3-Picarto/record.md)；附录 B-8 的筹码打赏、撤回、通知；详细记录 [record.md](record.md)

## 目标

Picarto（海外绘画直播）直播间能看到聊天和实时在线人数；修掉归档 v4 实现的两个问题：冷清或未开播的频道每 3 分钟断一次（不发保活），令牌被拒后用同一令牌无限重连。后来（B-8）照网站显示筹码打赏（醒目留言）、删除和清掉某人的消息（撤回）、系统通知、突袭、订阅。

## 协议要点

| 项 | 内容 |
|---|---|
| 令牌 | 开始时 `POST https://ptvintern.picarto.tv/ptvapi`（GraphQL `generateJwtToken(channel_name)`）要匿名 JWT，最多 3 次（间隔 0.5、1 s，每次 5 s 超时），只接受三段 base64url；JWT 没有过期时间，断线重连沿用 |
| 地址 | `wss://chat.picarto.tv/chat/token=<JWT>`；请求头 `origin: https://picarto.tv` 和 Chrome 140 的 UA；默认 `dart:io` 握手；按平台 `picarto` 走代理路线 |
| 加入和保活 | 打开即就绪；每 50 s 发 `{"type":"ping","message":"__ping__"}`（网站的值），服务端回 `{"success":true,"code":"PONG"}`；无消息 150 s 换连接；单地址，重连间隔 2～6 s |
| 令牌被拒 | 服务端不关连接，只回 `{"success":false,"code":"JWT_TOKEN"}`：标为未加入、重取令牌、`reopen`，不提示；每次连接最多 3 次，第 4 次被拒以 `credentialsUnavailable` 结束 |
| 消息 | JSON 文本帧，`type`/`t`、`messages`/`m` 两种写法都读：`c` 帧每行一条聊天（`n` 名字、`u` 用户 id、`m` 文本、`id`/`_id`、`d` 时间、`k` 颜色按 CSS 读）；`stream` 帧的 `viewers` → 在线人数（`id` 不是本频道不报）；历史记录页（`paginated`/`p`）跳过 |
| B-8 | 带 `v` 的行或 `ct` 行 → 醒目留言（价格 `x`，`priceText` 写 `<x> Kudos`，显示 60 s，同播时附言前加“打赏给 <rn>”）；`rm` → 撤回一条，`cm` → 撤回某人全部；`system`、`raid`、`ns` → 通知（订阅句子拼成中文） |
| 诊断 | 握手失败的文字里把令牌换成 `token=…` |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | `PicartoSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/picarto/picarto_site.dart:30`），提示一次“尚未接入” | `PicartoDanmakuConnection`（`packages/live_danmaku/lib/src/sites/picarto.dart:461`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:217`（传 `LiveHttp` 和代理） | 有聊天和人数（已做） |
| 协议 | 无 | `PicartoDanmakuProtocol`（:32）：地址 :58、保活 :66、`decode`（:117）、打赏 `tip`（:212）、`system`（:269）、`raid`（:297）、`subscription`（:328）、撤回 `deletion`（:359）、`clearance`（:369） | 与归档 v4 对照，有意差异 16 条 |
| 令牌刷新上限 | 无 | `maxTokenRefreshes = 3`（:489） | 不再无限重连 |
| 在线人数 | 目录、详情的 `viewers` | 弹幕 `stream.viewers` 是同一个数 | 进房后实时更新 |

## 结果

- **提交**：863bbf99c（2026-09-29，M5.10），7eb985f24（2026-10-01，B-8）。
- **和归档 v4 的对照**：`fixtures/picarto/danmaku/v4_expected.dart` 把归档 v4 的协议搬成独立程序。令牌请求、地址、握手请求头与 v4 和录制相同；S07-live（频道 allatir）1 条聊天、6 次人数一致；S09-keepalive 4 次人数一致；S10-token-refused v4 读不出被拒、新代码识别；S11-synthetic 23 组里 14 组一致、9 组是有意差异。
- **实测**（2026-09-28 匿名直连）：未开播频道 240 s 一条文本消息也没有（证明需要保活）；编造的令牌握手照样成功、立刻回 `JWT_TOKEN`；7 分钟前的令牌照样能用；本实现连 allatir 2.3 s 就绪。2026-09-30 对 45 个频道各连 150 分钟，只录到 1 次打赏、1 次 `rm`、1 条 `system`（`ct`、`cm`、`raid`、`ns` 没出现）。
- **样本**：`fixtures/picarto/danmaku/` 的 S07-live、S09-keepalive、S10-token-refused、S11-synthetic、S12-b8-synthetic、S13-removed、S14-tip、S15-system。
- **测试**：`packages/live_danmaku/test/picarto_test.dart` 做完时 53 个（另做过 15 种变异），B-8 后 81 个（+28，另做过 18 种变异）。

## 验证

- 自动测试：`picarto_test.dart`（本地 WebSocket 服务器端到端：路径里的令牌、Origin、录制的帧、保活和应答）。
- 真实接口：见上面的实测。没实测到的：`ct` 帧、`cm`、`raid`、`ns`、带链接和房管专用的 `system`，都用合成帧。
- 真机：没有；海外平台要代理，归 S02.4 一类的验证。

## 留下的问题

- `rm` 撤下整行，网站是留一行“已删除”；撤回模型没有替换文字。
- 打赏附言里的 chipmote（`kudo100`）照文字显示，不换图片；表情图片归 A 组。
- 醒目留言 60 s 后离开醒目留言栏是自定的（网站没有时长，取哔哩哔哩最短一档）。
- 突袭后不跟随跳转到被突袭的频道（不在 B-8 里，不做）。
