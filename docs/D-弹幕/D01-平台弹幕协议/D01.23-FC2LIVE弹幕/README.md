# D01.23 FC2 LIVE 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 26-3“评论（弹幕），并用它更新人数”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 FC2 评论，这是新增功能
- 旧编号：M5.22、T06a.23
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、授权 `Fc2LiveSite.controlGrant` 和控制连接 `Fc2LiveControl.connect` [E03.13 记录](../../../E-直播平台/E03-海外平台/E03.13-FC2LIVE/record.md)；FC2 接手的余项在 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/README.md)；详细记录 [record.md](record.md)

## 目标

FC2 LIVE（日本个人直播）直播间能看到评论，在线和累计人数随评论流更新；照网页的屏蔽表（NG 表）隐藏广告和骚扰评论；修掉归档 v4 实现把发送者的 `hash` 当消息 id（同一个人 10 分钟内只显示第一条）、用户 id 每条都变等问题。3.x 普通房间的公告“FC2 远端聊天尚待接入……”同时去掉。

## 协议要点

| 项 | 内容 |
|---|---|
| 授权 | 每次握手前取新授权（约一分钟失效、只能用一次）：`POST https://live.fc2.com/api/memberApi.php`，在播才再 `POST /api/getControlServer.php`（逐项同 3.x），得到 `url`、`control_token`、`orz_raw`；交给 `LiveSocket` 的是名义地址，本平台的握手函数每次先取授权再连；第一个授权在开始时取，第一次握手直接用 |
| socket | `wss://<节点>.live.fc2.com/control/channels/<频道号>?control_token=…`，请求头 `Origin: https://live.fc2.com`、Chrome 140 UA、`Cookie: l_ortkn=<orz_raw>`；默认握手 `Fc2LiveControl.connect`（`dart:io`，每 15 s WebSocket ping）；按平台 `fc2live` 和授权的地址选代理 |
| 加入和心跳 | 收到 `connect_complete` 就绪（每个 socket 一次）；加入超时 8 s；从打开起每 30 s 发文本帧 `{"name":"heartbeat","arguments":{},"id":<n>}`（编号在一次连接里递增）；无消息 90 s |
| 评论 | `comment` 的 `comments[]`：丢掉 `history: 1`（加入时重推的 30 条）、系统评论（打赏、礼物、进出场）和屏蔽表命中的；文字、名字按网页去 HTML 标签并解码字符引用；`anonymous` 或空名写 `[anonymous]`；用户 id 照网页 `decryptUserId` 解成稳定的用户键；颜色按网页评论列表的 8 色；没有消息 id（`hash` 是发送者的） |
| 人数 | `user_count` 只带变化的字段，保留上次的值：`pc_user_count + mobile_user_count` → 在线，`pc_total_count + mobile_total_count` → 累计，变了才报 |
| 屏蔽表 | 加入时服务端推 `ng_comment`（实测 340 条）：屏蔽词和屏蔽用户，`admin_ng`、`shared_ng_level` 决定用哪几张表；主播自己的评论只查 `keyword` |
| 换连接 | `control_disconnection`（4500 授权失效、1000 直播结束等）换新授权重连并提示；`move_server` 立刻无提示地换；服务端要求的重连连环超过 8 次（中间没有心跳回答）以 `reconnectsExhausted` 结束 |
| 开始失败 | 授权请求抛出不可重试的错误（不存在、没在播、受限、看不懂、风控）以 `connectionFailed` 结束，只发了 `memberApi`；网络、限流按握手失败重试 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 评论 | `Fc2Site.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/fc2live/fc2_site.dart:42`），公告“FC2 远端聊天尚待接入；媒体控制 WebSocket 由播放或录制独占……” | `Fc2LiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/fc2live.dart:431`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:230`（传 `LiveHttp` 和代理，不传 `connector`） | 有评论和人数（已做） |
| 协议 | 无 | `Fc2LiveDanmakuProtocol`（:30）：心跳 30 s、加入超时 8 s（:33～37）、匿名名（:42）、颜色（:46）；`Fc2LiveNgList`（:215）；`Fc2LiveAudience`（:358） | 与归档 v4 对照，有意差异 12 条 |
| 公告 | 普通房间显示上面的开发说明 | `Fc2LiveApi.notice` 对普通房间返回 null；3.x 原文留成 `legacyChatNotice` 给对照和迁移 | 不再显示 |
| 人数 | 目录、详情的 `count`、`total`（`audience.dart` 是 `roomList`） | 评论流是同一对数，进房后实时更新 | — |

## 结果

- **提交**：ecfea58fb（2026-09-30，M5.22）。之后没有改动。
- **和归档 v4 的对照**：`fixtures/fc2live/danmaku/v4_expected.dart` 把 v4 的解码搬成独立程序。S06-live（频道 29745829，114 s）47 个服务端帧逐帧一致：30 条历史评论不报，20 条聊天，27 个人数；授权回答得到的地址就是录下的握手地址；4 个心跳与录制文字相同。
- **实测**（2026-09-29 匿名直连）：本实现进推荐里人最多的房间（144 人）1.2～1.3 s 就绪，95 s 收到 7 条聊天、14 个人数（在线 144 与详情相同），心跳都有回答；屏蔽表挡下的正是服务端标了 `ng_comment_keyword` 的那条；12 个发送者里 3～4 个的 `encrypted_user_id` 每条都变，解码后每人一个键。
- **样本**：只用归档的 `fixtures/fc2live/danmaku/S06-live`，新加冻结输出 `expected.json`。
- **测试**：`packages/live_danmaku/test/sites/fc2live_test.dart` 34 个（协议 13、录制 4、连接 17，含本地服务器端到端）；`live_core` 的 FC2 测试改了公告断言（76 个不变）。

## 验证

- 自动测试：`fc2live_test.dart`。
- 真实接口：见上面的实测。没录到的：`move_server`（给的 `url` 是否带令牌不明，所以改为重取授权）。
- 真机：没有；海外平台要代理。

## 留下的问题

- 3.x 存下的关注里的旧公告 `legacyChatNotice` 合并时不会被空公告覆盖，要在 3.x 数据迁移时清掉（J 组）；界面不要直接显示存下的 FC2 公告。
- 匿名名字是平台给的 `[anonymous]`，没有换成界面语言的“匿名”。
- 用户 id 只用来区分发送者，可能是解码出的 FC2 账号编号，界面不要显示它。
- 打赏（`tip`）、礼物（`gift`）不显示；礼物名要查 `memberApi` 的 `gift_list`。
- 历史评论不报（网页放进评论列表），刚进房时看不到之前的评论。
