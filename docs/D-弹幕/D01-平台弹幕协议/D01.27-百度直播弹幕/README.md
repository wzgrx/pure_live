# D01.27 百度直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 30-3“百度弹幕（轮询消息列表）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x、归档 v4、pure_live_TV 都没有百度弹幕，这是新增功能
- 旧编号：M5.26、T06a.27
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、房间命令和新加的 `BaiduLiveDanmakuArgs` [E02.11 记录](../../../E-直播平台/E02-其他国内平台/E02.11-百度直播/record.md)；附录 B-18～B-20（不做）；详细记录 [record.md](record.md)

## 目标

百度直播间能看到聊天、在线人数和礼物。百度网页优先用闭源的 IM SDK（`pim.baidu.com`），不支持时退回轮询房间命令给的消息列表；本实现只用后者（公开的签名地址，匿名可读），不跑平台的 SDK。直播结束（102）时弹幕连接跟着结束。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | 进房时房间命令 371 已有 `chat_msg_hls_url`、`reliable_msg_hls_url`、`host_msg_hls_url` 和 `msg_hls_pull_internal_in_second`，放进 `BaiduLiveDanmakuArgs`，不多发请求；地址只收 `liveshowstatic.baidu.com` 的 `.m3u8`，http 换成 https（网页同样） |
| 签名 | 列表地址带 `authorization=bce-auth-v1/…`，签 182.5 天；分片签 7 天，过期回 403 `RequestExpired`；开始时已过期（或运行中 403 且已过期）以 `credentialsUnavailable`（`Chat list signature expired at …`）结束 |
| 列表 | m3u8：每个分片一行 `/v1/liveshowstatic/<mcast_id>_<纳秒时间>.ts?authorization=…`；列表总留最后 3 个分片（可能是几十小时前的）；`EXT-X-MEDIA-SEQUENCE` 恒为 0，按分片路径去重（每个列表记最近 256 个） |
| 节奏 | 第一次聊天列表回答即加入，已列出的分片是历史不取；之后每隔 `pullInterval`（5 s，限 1～10 s）依次拉聊天列表、它的新分片、reliable 列表、它的新分片、host 列表 |
| 分片 | gzip 的 JSON（看魔数 `1f 8b`，最多解两层）：`list[].messages[]` 里 `type` 0 的外层消息，`content.text` 再解一层是载荷 |
| 消息 | 载荷 0 → 聊天（按 `message_type` 取文字，语音不报；`name`、`uid`、外层 `msgid`、`create_time`；`room_id` 不同就丢）；101 → `onlineusercnt` 在线人数；107/10024 → 礼物（`BaiduLiveGift`）；本房间的 102 → `connectionFailed`（`Broadcast ended`）；`mix_room_close`（说的是别的房间）和其他 107 不报 |
| 失败 | 加入合计 3 次（间隔 2 s）；之后聊天列表失败第 1 次报重连，等 1、2、4、8、8… s，第 9 次 `reconnectsExhausted`；聊天列表 404（还没有消息）不算失败；reliable、host 列表失败按轮跳过（host 列表一直 404）；分片 4xx 跳过、5xx 重试共 3 次 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `BaiduLiveSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/baidulive/baidu_live_site.dart:45`），公告说看不到聊天 | `BaiduLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/baidulive.dart:399`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:234`（只传 `LiveHttp`） | 有聊天、人数、礼物（已做） |
| 协议 | 无 | `BaiduLiveDanmakuProtocol`（:96）：请求 10 s、加入 3 次、退避上限 8、跳过上限 12 轮、分片 3 次、记 256 个分片、结束说明（:98～120）；`BaiduLivePlaylist`（:52）、`BaiduLiveSegment`（:66）、`BaiduLiveGift`（:15） | 与网页脚本的读法逐个一致 |
| 平台层 | 无 | `live_core` 新加 `BaiduLiveDanmakuArgs`、`BaiduLiveApi.danmakuArgs`、`messageList`、`signatureExpiry`；`chatNotice` 只说明人数，3.x 原文留成 `legacyChatNotice` | — |

## 结果

- **提交**：cdb9504e3（2026-09-30，M5.26）。之后没有改动。
- **期望值**：没有可对照的实现，`fixtures/baidulive/danmaku/web_expected.py` 按网页脚本 `pchome.live.fcb2dc0e.js` 的类 `Se`、`Te` 和归档规格 §7 用 Python 独立重写。S03-live-chat（教育直播 11548522172）17 条聊天、6 次人数；S04-live-online 105 次人数；S05-live-gift 3 条聊天、3 个礼物；S06-ended 的 `mix_room_close` 不报；S07-synthetic 43 个分片、8 个列表一致。
- **实测**（2026-09-30 匿名直连）：三场各 7 分钟，聊天 20 条（多是主播的欢迎机器人或 AI 机器人），人数 118 次；host 列表 293 次都是 404；没见到 102。本实现进教育直播 1.2 s 加入、90 s 4 条聊天，新闻直播 0.9 s 加入、28 次人数。
- **样本**：`fixtures/baidulive/S02-room-chat`，`fixtures/baidulive/danmaku/` 的 S03～S07（观众、签名的密钥和签名、响应头回显的出口地址都脱敏，签名时间和有效期保留用来测过期）。
- **测试**：`packages/live_danmaku/test/sites/baidulive_test.dart` 86 个（协议 5、录制对照 5、合成对照 53、虚拟时钟回放 3、连接 20）；`live_core` 的百度测试 +9。

## 验证

- 自动测试：`baidulive_test.dart`（本地 HTTP 服务器端到端：带头和不带头的 gzip、404 的 host 列表）。
- 真实接口：见上面的实测。没验证到的：102 直播停止（按网页脚本，合成帧测）、回复、图片、语音消息。
- 真机：没有单独的真机记录；百度不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节里。

## 留下的问题

- 延迟最多一个间隔（5 s）加分片生成的时间；接百度 IM 能更快（附录 B-18，决定不做：要运行平台不公开的 SDK）。
- 进场、点赞、升级通知不显示（B-19，不做）；在线人数不改用 `real_onlineusercnt_str`（B-20，不做）。
- 如果平台其实不发 102，下播后连接只是每 5 s 拉一次空列表，不打转、不报错，界面按房间状态处理。
- 签名过期后要直播间重新取房间详情再连（半年后才过期，实际很少遇到）。
