# D01.13 猫耳 FM 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 13-2“猫耳弹幕（归档 v4 已实现）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有猫耳弹幕，这是新增功能
- 旧编号：M5.12、T06a.13
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（握手被拒的钩子 B-1 就是为本平台加的）；Brotli 解码 [Q01.2](../../../Q-网络和代理/Q01-请求和编码/Q01.2-Brotli解码/record.md)；平台本身和弹幕参数 [E02.4 记录](../../../E-直播平台/E02-其他国内平台/E02.4-猫耳FM/record.md)；多画面接入（N01.1）；详细记录 [record.md](record.md)

## 目标

猫耳 FM（语音直播）直播间能看到聊天、热度和真实在线人数（列表和详情只有热度，在线人数只在弹幕里）；修掉归档 v4 实现的解压炸弹、任何 `wss` 地址都发会话 Cookie、被拒后要等退避等问题。后来（B-9）显示付费提问（醒目留言）、管理员清屏（撤回）、贵族开通和 PK（通知）、礼物；（B-1）会话过期时自动换会话重连。

## 协议要点

| 项 | 内容 |
|---|---|
| 游客会话 | 开始时 `GET https://fm.missevan.com/api/user/info`（`MissevanApi.guestSession`），读 `Set-Cookie: FM_SESS`（有效 3 天）；最多 3 次（间隔 0.5、1 s，每次 5 s 超时），不跟随跳转；没有会话握手会回 HTTP 403 |
| 地址 | 详情给的 `wss://im.missevan.com/ws?room_id=<房间号>`；只认 `missevan.com` 的主机，没有 `room_id` 的补上（否则 400），别的房间的换掉（否则 500030004） |
| 握手 | API 请求头（`referer`、`origin: https://fm.missevan.com`、UA）加 `cookie: FM_SESS=<值>`；默认 `dart:io` 握手；按平台 `missevan` 走代理 |
| 帧 | 二进制：第 1 字节 1 表示 Brotli，第 2～4 字节是解压后长度（小端 24 位），之后是 Brotli 流；解压以帧头长度为上限（`brotliDecode` 的 `maxOutput`）；解出 JSON 对象或数组 |
| 加入 | 打开后发 `{"action":"join","uuid":…,"type":"room","room_id":<数字>}`（文本帧）；按 `uuid` 对应应答，`code` 0 就绪；重新加入带 `"reconnect":1`；加入超时 5 s；被拒换会话 `reopen`，第 4 次被拒以 `connectionFailed` 结束 |
| 心跳 | 30 s 发文本 `❤️`，服务端回显；无消息 90 s 换连接（服务端约 120 s 没收到心跳会断开） |
| 消息 | `message`/`new` 聊天和 `message`/`danmaku` 付费弹幕都是聊天（带等级 `titles.level`、粉丝牌 `titles.medal`）；`room`/`statistics`（约每 2 分钟）的 `score` → 热度、`online` → 在线人数；带 `room_id` 且不是本房间的跳过 |
| B-9 | `question`/`ask` → 醒目留言（`priceText` 写 `50 钻`，显示 60 s）；`admin`/`message_clear` → 撤回（`opt` 1 全部、2 按 `msg_ids`）；`noble`/* 和 `pk`、`global_pk`、`team_pk` 的提示 → 通知（HTML 去标签和“详情”链接提示）；`gift`/`send` → 礼物（`MissevanGift`） |
| B-1 | 握手回 403、401 时用 `onHandshakeFailure` 重取会话，下一次握手带新 Cookie；每轮失败只换一次 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | `MissevanSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/missevan/missevan_site.dart:38`），提示一次“尚未接入” | `MissevanDanmakuConnection`（`packages/live_danmaku/lib/src/sites/missevan.dart:687`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:219` | 有聊天、热度、在线人数（已做） |
| 协议 | 无 | `MissevanDanmakuProtocol`（:96）：心跳 30 s（:99）、加入超时 5 s（:106）、提问时长 60 s（:118、:377～379）；`onHandshakeFailure`（:847） | 与归档 v4 对照，有意差异 15 条 |
| 在线人数口径 | 3.x 的人数设置页写着猫耳只有热度 | `live_core` 的 `audience.dart` 里猫耳从 `unsupported` 改成 `roomRealtime`：卡片“优先真实在线”时显示待定，进房后由弹幕填上 | 能看真实在线（REG-MISSEVAN-002） |
| 等级 | 无 | 聊天带 `userLevel`，弹幕操作菜单照 3.x 显示 `Lv.x` | — |

## 结果

- **提交**：700066213（2026-09-29，M5.12），d3409dccf（2026-10-01，B-1、B-9）。
- **和归档 v4 的对照**：`fixtures/missevan/danmaku/v4_expected.dart` 把 v4 的协议搬成独立程序（Brotli 换成 `brotliDecode`）。S06-live（房间 246709466）3 条聊天和人数一致，S07-brotli（房间 180370487，服务端真正压缩过的帧）9 条聊天和人数一致，S08-synthetic 15 组里 10 组一致、5 组有意差异。
- **实测**（2026-09-28 匿名游客直连）：本实现进 869222422 383 ms 就绪，115 s 时收到热度 21514、在线 10；进 180370487 369 ms 就绪，130 s 11 条聊天。2026-09-30 两批 60 个房间会话共录到聊天 4886、礼物 1147、提问 7、PK 1000 多、贵族续费 1、清屏 0，本实现逐帧解码没有异常。
- **样本**：`fixtures/missevan/S05-user-info`，`fixtures/missevan/danmaku/` 的 S06-live、S07-brotli、S08-synthetic（`synthetic_cases.py` 用参考编码器生成）、S09-events（B-9 的 26 帧）。
- **测试**：`packages/live_danmaku/test/missevan_test.dart` 做完时 54 个（另做过 21 种变异），B-1、B-9 后 71 个；框架 `socket_connection_test.dart` +8；`live_core` 的 `missevan_api_test.dart` 改了一条 REG-MISSEVAN-002 断言。

## 验证

- 自动测试：`missevan_test.dart`（本地服务器端到端：查询参数、Cookie、加入、S07 的真实压缩帧、心跳回显；对旧 Cookie 回 403 后换会话加入成功）。
- 真实接口：见上面的实测。没实测到的：清屏、贵族开通、团播的 `cross_*` 和 `team_pk`、邀请 PK 被拒或超时，用合成帧。
- 真机：没有单独的真机记录；猫耳不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节里。

## 留下的问题

- 进房后最迟约 2 分钟才有第一个真实在线人数（`room/statistics` 每 120 s 一条），之前卡片“优先真实在线”时显示待定。
- 清屏“全部”用 `LiveRetraction.all()`，会连通知行一起撤下，比网站（只清聊天）多；要直播间的聊天列表区分。
- 付费提问的回答、取消不会提前撤下醒目留言（模型没有“提前结束”）。
- 幻影 PK 的提示是主播口吻（“你在幻影PK中击败……”），照原文显示。
