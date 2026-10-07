# D01.16 SHOWROOM 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 19-3“评论（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 SHOWROOM 评论，这是新增功能
- 旧编号：M5.15、T06a.16
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和弹幕参数（`bcsvr_host`、`bcsvr_key`）[E03.6 记录](../../../E-直播平台/E03-海外平台/E03.6-SHOWROOM/record.md)；详细记录 [record.md](record.md)

## 目标

SHOWROOM（日本偶像直播）直播间能看到观众评论（带“Class”等级）；比归档 v4 多做了参数检查（防止带制表符的键拼出别的命令），不再自己拼消息 id。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | `wss://<bcsvr_host>/`（443；`live_info` 给的 8080 端口实测握手超时，不用）；请求头 `Origin: https://www.showroom-live.com` 和平台层的 Chrome 140 UA（服务端其实不看）；默认 `dart:io` 握手；按平台 `showroom` 走代理 |
| 参数检查 | 连接再用平台层的 `ShowroomApi.danmakuArgs` 检查一次：主机是 `showroom-live.com` 或子域、键不超过 256 字、不含空白和控制字符；不合格以 `connectionFailed`（`No usable comment server or key`）结束，不握手 |
| 订阅 | 打开后发 `SUB\t<bcsvr_key>`（每场直播一个、所有观众相同），随即就绪；服务端不确认，键不对只是收不到消息 |
| 心跳 | 每 60 s 发 `PING\tshowroom`（打开后第一次在 60 s 时），服务端回 `ACK\tshowroom`；网页不发心跳，但没人说话的房间 90 s 里只有 `ACK`，靠它喂无消息检测（180 s） |
| 下行 | 文本帧 `MSG\t<key>\t<JSON>`，键必须等于本次订阅的键；`t` 1 是评论：`cm` 文字（整数照写成数字，观众常数数）、`ac` 名字、`u` 用户 id、`cl` 等级（大于 0 时填 `userLevel`）、`created_at`（秒）；白色，没有消息 id |
| 不报 | `t` 2、11、17 礼物，5 应援点数，8、9 字幕，18 系统通知，101、104 下播开播，100 等；评论流里没有观看人数 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 评论 | `ShowroomSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/showroom/showroom_site.dart:46`），提示一次“尚未接入” | `ShowroomDanmakuConnection`（`packages/live_danmaku/lib/src/sites/showroom.dart:132`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:222` | 有评论（已做） |
| 协议 | 无 | `ShowroomDanmakuProtocol`（:20）：心跳 60 s（:22）、`PING`/`ACK`（:25～28）、地址（:41）、订阅（:44）、参数检查 `checked`（:50）、`decode`（:59）、`comment`（:90） | 与归档 v4 对照，有意差异 5 条 |
| 人数 | `audience.dart` 里 SHOWROOM 是累计观看、没有在线 | 不变（评论流里没有人数，`t` 5 是应援点数） | — |

## 结果

- **提交**：a30d7aedd（2026-09-29，M5.15）。之后没有改动。
- **和归档 v4 的对照**：`fixtures/showroom/danmaku/v4_expected.dart` 把 v4 的协议搬成独立程序。地址、请求头、订阅帧、心跳帧和间隔与 v4、录制相同；S06-live（房间 577362，71 s）23 个收到的帧逐帧一致，18 条聊天；差别只有消息 id（v4 自拼 `showroom:<u>:<created_at>:<哈希>`，现在留空交给去重闸门的无 id 规则）。
- **和归档 v4 的差异**：不报礼物（v4 报，但礼物名只有编号）、id 留空、读等级 `cl`、文字和名字只收字符串和整数、参数检查更严。
- **实测**（2026-09-28 匿名直连，自写小程序）：握手约 1.3 s；6 个房间 90 s 收到 47 条评论，`cl` 都大于 0；一个房间 90 s 里只有 `ACK`。本实现本身没有接真实服务器跑，用本地服务器测试，协议与实测逐项对照过。
- **样本**：只用归档的 `fixtures/showroom/danmaku/S06-live`，新加冻结输出 `expected.json`。
- **测试**：`packages/live_danmaku/test/sites/showroom_test.dart` 17 个（协议 5、录制 4、连接 8，含本地服务器端到端）。

## 验证

- 自动测试：`showroom_test.dart`。
- 真实接口：只有协议探测，本实现没有直接连过真实服务器（record.md“实测”最后一条）；真机或真实接口跑一遍时要看评论能否出现。
- 真机：没有；海外平台要代理。

## 留下的问题

- 本实现没有在真实服务器上跑过，是 D01 里少数只靠录制回放和本地服务器验证的平台。
- 主播重新开播后键会变，旧连接不会自己结束（只剩 `ACK`），没被 B-24 的“结束后重连”覆盖。
- 下播（`t` 101）、开播（`t` 104）不报；要用时在协议层加事件。
- 礼物不显示：要解 `t` 2、11、17 并另查礼物表。
