# D01.3 斗鱼 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：模块重构（M5 的第 2 个平台）：把 3.x 的 `lib/core/danmaku/douyu_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一
- 旧编号：M5.2、T06a.3
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和后来的礼物、下播通知 [E01.2 记录](../../../E-直播平台/E01-国内五大平台/E01.2-斗鱼/record.md)；设置“过滤斗鱼疑似机器人弹幕”在 J 组（设置存储）和 A08（屏蔽词页的开关）；详细记录 [record.md](record.md)

## 目标

斗鱼直播间的弹幕照 3.x 连上和显示：聊天、醒目留言、语音醒目留言，“疑似机器人”过滤开关照旧生效；同时修掉 3.x 的 STT 递归解析把 `@Alice` 显示成 `@lice`、链接变成列表、语音醒目留言没有头像、开箱通知当成 0 元醒目留言这几个问题。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | 只有 `wss://danmuproxy.douyu.com:8506`，匿名，不带请求头和子协议；房间号是 `DouyuDanmakuArgs` 里的真实房间号（E01.2 由 `betard` 的 `room.room_id` 换算，靓号和别名已换掉） |
| 包 | `长度(4) 长度(4) 类型(2) 加密(1) 保留(1) 包体 \0`，小端，长度 = 8 + 包体 + 1，客户端类型 689；按每个包自己的长度切开（一帧多包），长度小于 9 或越界停止 |
| 加入 | 打开即就绪，随后发 `type@=loginreq/roomid@=<房间号>/` 和 `type@=joingroup/rid@=<房间号>/gid@=-9999/`；每次重连都重新发；没有加入计时器 |
| 心跳 | 45 s 发 `type@=mrkl/`；无消息 135 s 换连接；只有一个地址，重连间隔 2、3、4、5、6、6、6、6 s，8 次后放弃 |
| 文本格式 | STT（`key@=value/`，`@A` 表示 `@`、`@S` 表示 `/`）；4.x 的 `DouyuStt` 按层解析，每个值只反转义一次 |
| 消息 | `chatmsg` 聊天（`nn`、`uid`、`txt`、`col` 6 色表、`cst` 时间、`cid` → `douyu:<cid>`；`rid` 不同就丢）；`comm_chatmsg` 醒目留言（价格或时长不大于 0 的不算）；`voice_trlt` 语音醒目留言；后来加了 `dgb` 礼物（聊天列表里单独一行，B-21）、`rss` 下播通知（本房间 `ss@=0` 时结束连接） |
| 过滤 | 没有 `dms` 且 `if` 不是 `1` 的聊天，只在设置 `filterDouyuSuspectedAutomatedMessages` 打开时丢；每条疑似的读一次设置，改了不用重连 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/douyu_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/douyu.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `DouyuDanmaku`（:14），`DouyuSite.getDanmaku()`（`core/site/douyu/douyu_site.dart:70`）把设置读取函数传进去 | `DouyuDanmakuConnection`（:346）；应用登记在 `apps/pure_live/lib/app/platforms.dart:203`，同样传 `settings.get(Settings.filterDouyuSuspectedAutomatedMessages)` | 一致 |
| 地址和心跳 | `serverUrl`（:45）、`heartbeatTime = 45 * 1000`（:21） | `socketPolicy`（:357）、`heartbeatInterval`（:99） | 一致 |
| 加入包 | :93～94 | `DouyuDanmakuProtocol` 的加入包（:127～130），用 UTF-8 字节数算包长 | 一致；包长 3.x 按 UTF-16 码元（只发 ASCII，线上没影响） |
| STT 解析 | `sttToJObject`（:118、:267～295）每个值递归猜结构，普通文字被反转义两次 | `DouyuStt`（:60）按层解析 | 修好：文字和昵称不再被改 |
| 聊天 | 同 4.x 字段 | `_chat`（:218 起） | 147 条录制聊天逐字段一致 |
| 醒目留言 | 只检查字段在不在（:159～178），开箱通知变成 0 元醒目留言 | 价格或时长不大于 0 的不算（:241 起） | 修好 |
| 语音醒目留言头像 | 永远是空（:188～189） | `https://` + `uat` 第二项（:268～284） | 修好 |
| 礼物、下播 | 不处理 | `dgb` 报成礼物（:295）；`rss` 下播时 `read`（:168）报告结束，连接以 `connectionFailed`（`Broadcast ended`，:362、:390）结束 | 礼物在聊天列表里单独一行（B-21，C01.2）；下播后不再一直重连 |

## 结果

- **提交**：04717fcf9（2026-09-29，M5.2）。之后同一文件的改动属于 E01.2：8eca75a32（礼物上报，“国内平台完善”）、398f68f87（下播通知结束连接，附录 C-6）。
- **和 3.x 的对照**：`fixtures/douyu/danmaku/legacy_expected.dart` 把 3.x 的解码代码搬成独立程序生成冻结输出。S13-live（房间 9999，183 帧）的 147 条聊天顺序和全部字段一致，发出的 `loginreq`、`joingroup`、心跳和 3.x、录制逐字节相同；S14-synthetic 17 组合成帧除 3 处有意差异（文字不再被改、语音醒目留言有头像、开箱通知不是醒目留言）外一致。
- **有意差异**：record.md“与 v3 的有意差异”6 条；保持 3.x 的地方：打开即就绪、只检查聊天的 `rid`、`cst=0` 仍是 1970 年（被去重闸门丢掉）、每个包最后一个字节不检查。
- **样本**：`fixtures/douyu/danmaku/` 的 S13-live、S14-synthetic，后来加了 S15（礼物）、S16-broadcast-end（下播包）。
- **测试**：`packages/live_danmaku/test/douyu_test.dart` 做完时 40 个（协议 6、录制对照 3、合成对照 18、连接 13）；E01.2 的礼物 +3、下播 +2，现在 45 个。

## 验证

- 自动测试：`douyu_test.dart`（含本地 WebSocket 服务器端到端回放录制）。
- 真实接口：2026-09-30 匿名直连 266609、9263298 各 120 s，立即就绪、聊天和 57 条礼物都解出；2026-10-01 同时加入 200 个直播间 6 分钟录到 1 个下播包和 114 条醒目留言（E01.2 记录）。
- 真机：没有单独的真机记录；[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条（斗鱼热门直播间、断网重连）和第 4 条（机器弹幕过滤）还没逐条填结果。

## 留下的问题

- 进房时补上还在显示的醒目留言（附录 C-5）：没找到网页的列表接口，醒目留言仍只从弹幕来；记在 E01.2 记录的候选。
- 加入一个已下播或轮播的房间时服务端会不会立刻发 `ss@=0` 的 `rss` 没验证；如果会，轮播房间的弹幕会马上结束，要在真机上留意。
- 平台通知 `hpsc`、`blab`、`spbc` 不显示，贵宾数 `oun`/`oni` 不上报（口径不是在线人数），都是决定不做（E01.2 记录 D-2、D-3）。
