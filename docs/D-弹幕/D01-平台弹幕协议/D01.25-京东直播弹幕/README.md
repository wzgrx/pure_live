# D01.25 京东直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 28-6“聊天（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x、归档 v4、pure_live_TV 都没有京东直播的聊天，这是新增功能，规格来自官网直播页脚本和录下的真实帧
- 旧编号：M5.24、T06a.25
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、新加的 `JdLiveDanmakuArgs` 和公告 [E02.9](../../../E-直播平台/E02-其他国内平台/E02.9-京东直播/README.md)（弹幕参数见它的 [record.md](../../../E-直播平台/E02-其他国内平台/E02.9-京东直播/record.md)）；下播后重连 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)（B-24）；3.x 存下的旧公告由 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md) 导入时清掉；详细记录 [record.md](record.md)

## 目标

京东直播（带货直播）直播间能看到观众和主播的聊天、正在观看和累计观看人数，直播结束时弹幕连接跟着结束（不在下播后反复重连）。游客令牌是网页自己的匿名入口，不要 h5st 签名，也不要登录。

## 协议要点

| 项 | 内容 |
|---|---|
| 令牌 | 每次握手前（第一次和每次重连）`POST https://api.m.jd.com/api`，表单 `loginType=2`、`appid=h5-live`、`functionId=liveauth`、`body={"appId":"jd.mall","content":"<Base64>"}`、`t`；`content` 是 `{"appId","secretKey","groupId":<场次号>,"clientType":"m","timestamp","origin":-100,"encryptPin":true,"random"}`（`random` 6 位数字）用 AES-128-CBC 加密（密钥 `RYm2dMPMWD9AxYFk`、IV `0102030405060708`，网页脚本里写死）；回答 `code` 0 时 `data.liveUrl`（只收 `wss` 和 `jd.com` 的主机，不带查询）、只能用一次的 `token`，可能带 `msgMaskKey`；不跟随跳转 |
| socket | `<liveUrl>?token=<token>`，请求头 `Origin: https://lives.jd.com` 和平台层的 UA；默认 `dart:io` 握手；按平台 `jdlive` 走代理；交给 `LiveSocket` 的是名义地址（`liveauth` 加场次号，`JdLiveDanmakuProtocol.endpoint`），本平台的握手函数（`_Resolver.connect`）每次先取令牌再连；失败详情里的令牌换成 `token=…` |
| 加入 | 打开即就绪，socket 上什么都不发（网页会发 `join_live_broadcast` 让房间出现假的“用户xxxxxxx来了”，不发也收到全部推送） |
| 心跳 | 不发；节拍 20 s 只用来检查无消息，无消息 200 s 换 socket（服务端自己对 180 s 没有推送的 socket 断开；大多数在播房间约每 3.5 s 推一次统计） |
| 失败 | 取令牌失败或被拒（网络、非 2xx、`code` 不是 0、回答里没有可用的 socket）、socket 握手失败（用过的令牌回 HTTP 200 不升级）都算一次握手失败，下次握手重新取令牌，按框架退避最多 8 次后 `reconnectsExhausted`；场次号不合规：`connectionFailed`（`No broadcast`），不发请求 |
| 消息 | 文本 JSON；二进制帧按 `msgMaskKey` 异或后按 UTF-8 解（网页同样，游客的回答没有掩码，没遇到过）；`body.groupid` 不是本场次的丢（没有 `groupid` 的算本场次）；`chat_group_message` 里 `viewer_send_message` → 聊天（`nickName`、`content`、`from.pinmd5` 当用户 id、`id`、`datetime`），`anchor_send_message` → 聊天，名字“主播”；白色；`get_statistics_result` 的 `current_viewer` → 在线、`total_viwer`（原文拼写）→ 累计；`stop_live_broadcast` → 以 `connectionFailed`（`Broadcast ended`）结束；进房、点赞、购买、商品、自动回复等不报 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `JdLiveSite.getDanmaku() => EmptyDanmaku()`（`core/site/jdlive/jd_live_site.dart:41`）；进房时弹幕区一条状态“此平台的远端弹幕尚未接入……”（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `JdLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/jdlive.dart:384`）：时序 `defaultPolicy`（:407，节拍 20 s、无消息 200 s，没有加入计时）、`target`（:417）、`onOpen`（:432）即就绪、`onData`（:436）上报并在结束帧时关闭；握手 `_Resolver`（:455，`connect` :477、`_auth` :498）；应用登记在 `apps/pure_live/lib/app/platforms.dart:232` | 有聊天和人数（已做） |
| 协议 | 无 | `JdLiveDanmakuProtocol`（:61）：加密常量（:66～79）、主播名（:83）、统计间隔 3.5 s（:89）、服务端空闲 180 s（:93）、无消息 200 s（:99）、`content`（:118）、`encrypt`（:131）、`request`（:140）、`auth`（:175）、`decode`（:237）、掩码 `_text`（:265）、`audience`（:292）、`chat`（:320）；`JdLiveChatAuth`（:16） | 与网页脚本的读法逐帧一致 |
| 参数 | 无 | `live_core` 新加 `JdLiveDanmakuArgs(liveId)`（`packages/live_core/lib/src/sites/jdlive/jdlive_api.dart:179`）：进房和录制详情里直播中、不是仅限 App 的场次才有 | — |
| 人数 | 列表只有累计观看（`pv`） | `audience.dart:228` 改为 `roomRealtime`（有累计）；进房后弹幕报正在观看 | 进房后有正在观看人数 |
| 公告 | `jdlive_chat_notice`“京东远端聊天尚待接入；公开目录的 pv 字段按累计观看展示……”（`jd_live_site.dart:95`，`assets/translations/zh.json:1930`） | `JdLiveApi.chatNotice`（`jdlive_api.dart:270`）：“列表里的人数是累计观看；直播中连上弹幕后，显示的是正在观看的人数。” | 3.x 存下的旧公告导入时清掉（J02.1） |

## 结果

- **提交**：20deb4695（2026-09-30，本任务的代码）。之后只有 docs v1 改编号时动过一行注释（c613b73f9），行为没有变。
- **期望值**：没有可对照的实现，`fixtures/jdlive/danmaku/web_expected.mjs` 把网页的加密、`liveauth` 回答处理、消息处理和聊天区筛选逐个改写成 Node 函数（引了压缩后的原文）。S06-live（场次 48399381）的 `liveauth` 表单和密文与网页相同，44 帧逐帧一致；S07-ended（场次 48431089）的 22 帧一致，结束帧上结束连接、之后不再上报也不重连。
- **实测**（匿名直连，socket 上什么都不发）：游客直接给令牌，场次号 `0`、`abc` 也给；用过一次的令牌再握手回 HTTP 200 不升级；早上 8 个房间 45 分钟、晚上 40 个房间 40 分钟共约 7.3 万帧，观众发言只有 4 条、主播消息 53 条；4 场在录制中结束，服务端在 19～180 s 后断开；有的直播间完全不推统计，推送最长间隔 119 s（所以无消息检测定为 200 s）。本实现 434 ms 就绪，120 s 收到 34 次统计（正在观看 1、累计 738）。
- **样本**：`fixtures/jdlive/danmaku/` 的 S06-live、S07-ended（账号摘要、昵称、令牌里的游客编号都脱敏）。
- **测试**：`packages/live_danmaku/test/sites/jdlive_test.dart` 现在 33 个（和做完时一样；文件里 32 处 `test(`，第 584 行的“逐帧与网页的读法一致”在 S06、S07 两个样本上各跑一次）：协议 12、录制 6、连接 15（含本地服务器端到端）；`live_core` 的 `jdlive_api_test.dart` +2，`jdlive_site_test.dart` 加参数断言。

## 验证

- 自动测试：`jdlive_test.dart` 覆盖 `content` 的明文和加密（用 `Aes128Cbc` 解回）、请求的方法和表单顺序、回答的各种拒绝和坏地址、令牌去除、观众和主播消息、人数、帧（其他 14 种消息、别的群组、掩码、非 UTF-8、结束帧）；两份录制逐帧与网页读法一致、用连接重放；连接的令牌每次重取、打开即就绪、不发任何帧、`liveauth` 失败重试、无消息检测、结束帧结束连接、关闭时取消请求、本地服务器端到端。
- 真实接口：2026-09-29～30 匿名直连跑过（见上面的实测）。
- 真机：没有单独的真机记录；S02.2、S02.3 的记录里没有京东直播，E02.9 也写“没有在 K90 上专门看过”。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列国内五大平台，没有京东直播弹幕的条目。真机上要看：进一个在播的京东直播间，人数显示正在观看；主播下播时弹幕区显示连接结束、不再反复重连。

## 留下的问题

- 京东直播的观众发言非常少，大多数时候聊天区只有主播的消息：平台特点，没有任务。
- 仅限 App 的场次（`secret` 为 1）能不能连没有样本核实，不给参数：没有任务，见到这种场次时再核实，能连就在 `JdLiveApi.room` 里放开。
- 正在观看人数（弹幕）和列表的累计观看口径不同：没有任务，公告已经把两者都说明。
- 进房、购买提示（网页的飘条）和主播公告不显示：没有任务（其他平台也不显示进场类消息，同 B-19 的理由）；发言要登录，不做。
- 3.x 存下的旧公告：已由 J02.1 处理，真机核对在 [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)。
- 没有真机结果：没有任务；真机清单没有本平台弹幕的条目（见“验证”）。
