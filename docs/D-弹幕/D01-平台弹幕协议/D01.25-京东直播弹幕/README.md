# D01.25 京东直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 28-6“聊天（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x、归档 v4、pure_live_TV 都没有京东直播的聊天，这是新增功能
- 旧编号：M5.24、T06a.25
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、新加的 `JdLiveDanmakuArgs` 和公告 [E02.9 记录](../../../E-直播平台/E02-其他国内平台/E02.9-京东直播/record.md)；详细记录 [record.md](record.md)

## 目标

京东直播（带货直播）直播间能看到观众和主播的聊天、正在观看和累计观看人数，直播结束时弹幕连接跟着结束（不再半小时里反复重连）。规格来自官网直播页脚本和录下的真实帧：游客令牌是网页自己的匿名入口，不要 h5st 签名，也不要登录。

## 协议要点

| 项 | 内容 |
|---|---|
| 令牌 | 每次握手前 `POST https://api.m.jd.com/api`，表单 `loginType=2`、`appid=h5-live`、`functionId=liveauth`、`body={"appId":"jd.mall","content":"<Base64>"}`、`t`；`content` 是 `{"appId","secretKey","groupId":<场次号>,"clientType":"m","timestamp","origin":-100,"encryptPin":true,"random"}` 用 AES-128-CBC 加密（密钥 `RYm2dMPMWD9AxYFk`、IV `0102030405060708`，网页脚本里写死）；回答 `liveUrl`（`wss://live-ws4.jd.com`）和只能用一次的 `token` |
| socket | `<liveUrl>?token=<token>`，请求头 `Origin: https://lives.jd.com` 和平台层的 UA；默认 `dart:io` 握手；按平台 `jdlive` 走代理；名义地址交给 `LiveSocket`，本平台的握手函数每次先取令牌 |
| 加入 | 打开即就绪，socket 上什么都不发（网页会发 `join_live_broadcast` 让房间出现假的“用户xxxxxxx来了”，不发也收到全部推送） |
| 心跳 | 不发；检测节拍 20 s，无消息 200 s 换 socket（服务端自己对 180 s 没有推送的 socket 断开） |
| 消息 | 文本 JSON（网页也处理按 `msgMaskKey` 异或的二进制帧，游客没有掩码）；`viewer_send_message` → 聊天（`nickName`、`content`、`from.pinmd5`、`id`、`datetime`）；`anchor_send_message` → 聊天，名字“主播”；`get_statistics_result` 的 `current_viewer` → 在线、`total_viwer` → 累计；`stop_live_broadcast` → 以 `connectionFailed`（`Broadcast ended`）结束；`groupid` 不是本场次的丢；进房、点赞、购买、商品、自动回复等不报 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `JdLiveSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/jdlive/jd_live_site.dart:41`），提示一次“尚未接入” | `JdLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/jdlive.dart:384`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:232` | 有聊天和人数（已做） |
| 协议 | 无 | `JdLiveDanmakuProtocol`（:61）：加密常量（:66～79）、主播名（:83）、服务端空闲 180 s 和无消息 200 s（:93～99）；`JdLiveChatAuth`（:16） | 与网页脚本的读法逐帧一致 |
| 参数 | 无 | `live_core` 新加 `JdLiveDanmakuArgs(liveId)`：进房和录制详情里直播中、不是仅限 App 的场次才有 | — |
| 人数 | 列表只有累计观看 | `audience.dart` 的京东直播改为 `roomRealtime`；公告改成“列表里的人数是累计观看；直播中连上弹幕后，显示的是正在观看的人数。” | 进房后有正在观看人数 |

## 结果

- **提交**：20deb4695（2026-09-30，M5.24）。之后没有改动。
- **期望值**：没有可对照的实现，`fixtures/jdlive/danmaku/web_expected.mjs` 把网页的加密、`liveauth` 回答处理、消息处理和聊天区筛选逐个改写成 Node 函数（引了压缩后的原文）。S06-live（场次 48399381）的 `liveauth` 表单和密文与网页相同，44 帧逐帧一致；S07-ended（场次 48431089）的 22 帧一致，结束帧上结束连接、之后不再上报也不重连。
- **实测**（匿名直连，socket 上什么都不发）：游客直接给令牌，场次号 `0`、`abc` 也给；用过一次的令牌再握手回 HTTP 200 不升级；早上 8 个房间 45 分钟、晚上 40 个房间 40 分钟共约 7.3 万帧，观众发言只有 4 条、主播消息 53 条；4 场在录制中结束，服务端在 19～180 s 后断开；有的直播间完全不推统计，推送最长间隔 119 s（所以无消息检测定为 200 s）。本实现 434 ms 就绪，120 s 收到 34 次统计（正在观看 1、累计 738）。
- **样本**：`fixtures/jdlive/danmaku/` 的 S06-live、S07-ended（账号摘要、昵称、令牌里的游客编号都脱敏）。
- **测试**：`packages/live_danmaku/test/sites/jdlive_test.dart` 33 个（协议 12、录制 6、连接 15，含本地服务器端到端）；`live_core` 的 `jdlive_api_test.dart` +2，`jdlive_site_test.dart` 加参数断言。

## 验证

- 自动测试：`jdlive_test.dart`。
- 真实接口：见上面的实测。
- 真机：没有单独的真机记录；京东直播不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节里。真机上要看：进一个在播的京东直播间，人数显示正在观看；主播下播时弹幕区显示连接结束、不再反复重连。

## 留下的问题

- 京东直播的观众发言非常少，大多数时候聊天区只有主播的自动消息。
- 仅限 App 的场次（`secret` 为 1）能不能连没有样本核实，不给参数。
- 正在观看人数（弹幕）和公告说的累计观看口径不同，直播间显示时要分清（公告已改成两者都说明）。
- 进房、购买提示（网页的飘条）和主播公告不显示；发言要登录，不做。
