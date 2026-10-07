# D01.6 快手 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：模块重构（M5 的第 5 个平台）：把 3.x 的 `lib/core/danmaku/kuaishou_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一，也是唯一用 HTTP 轮询的
- 旧编号：M5.5、T06a.6
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（为本平台留了 `run.delay`、`run.ended`）；平台本身和弹幕参数 [E01.5 记录](../../../E-直播平台/E01-国内五大平台/E01.5-快手/record.md)；评论表情 [S02.1 记录](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md)；详细记录 [record.md](record.md)

## 目标

快手直播间的评论和在线人数照 3.x 用移动端网页的评论 feed 轮询拿到（桌面端 WebSocket 要浏览器签名，匿名拿不到），请求、解析、重试、退避和 3.x 完全一样；修掉 3.x 一条评论时间超出范围让整个回答失败、cursor 不前进、约 47 s 后弹幕彻底断开的潜在问题。

## 协议要点

| 项 | 内容 |
|---|---|
| 传输 | HTTP 轮询，不用 WebSocket 运行时，直接继承 `DanmakuConnectionBase` |
| 地址 | `GET https://livev.m.chenzhongtech.com/wap/live/feed?liveStreamId=…[&cursor=…]`；主地址没回答、非 2xx、正文不是 JSON 时换 `https://m.gifshow.com/wap/live/feed`；每次都先试主地址 |
| 请求头 | Android 16 Chrome 139 的 UA、`Accept: application/json, text/plain, */*`、`Referer: https://livev.m.chenzhongtech.com/`；`KuaishouDanmakuArgs` 的 Cookie 非空才带 |
| 参数 | `liveStreamId` 是本场直播的编号（每次开播都换）；第一次不带 `cursor`，之后带上一次回答的 |
| 解析 | 正文最多解 3 层 JSON（feed 发的是“装着 JSON 的 JSON 字符串”），外面有 `data` 取里面；`result` 不是 1 是 `KuaishouFeedRejected`；`pullCycleSeconds` 限制在 1～10 s，缺省 3 s；`currentWatchingCount`（`5.6w`、`1.2万`）→ `onlineViewers`；`liveStreamFeeds` 里 `type` 为 `comment` 的是聊天，id `kuaishou:<id>`，没有 id 时 `sha1(time \0 userId \0 content)`；没名字的写“快手用户” |
| 节奏 | 开始时拉取最多 3 次（间隔 0.6、1.4 s），都失败把最后一次的错误抛给调用方；之后按服务端间隔轮询，同一时间只有一个请求；失败后等 1、2、4、8、8… s，第 1 次失败报重连，第 9 次失败 `reconnectsExhausted`；没有心跳 |
| 表情 | S02.1 起 `KuaishouDanmakuArgs.emotes`（房间页的表情表 `[笑哭]` → 图片）给评论里的表情码配图片 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/kuaishou_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/kuaishou.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `KuaishouDanmaku`（:45），`KuaishowSite.getDanmaku()`（`core/site/kuaishou/kuaishou_site.dart:50`） | `KuaishouDanmakuConnection`（:213）；应用登记在 `apps/pure_live/lib/app/platforms.dart:211`，传应用的 `LiveHttp` | 一致；请求走注入的 `LiveHttp`（平台 id `kuaishou` 的代理和限流） |
| 地址和请求头 | :50～51、:223 | `KuaishouDanmakuProtocol`（:57），地址 :61～62，请求头 :87 | 一致；录制的 10 次请求地址逐字相同 |
| 开始重试 | :113 的 600、1400 ms，`Future.delayed` 停不下来 | `startRetryDelays`（:71），用 `run.delay`，`close` 立即结束 | 一致；关闭更快 |
| 退避和放弃 | `_maxReconnectAttempts = 8`（:53），:179 | `maxFailures`（:75）、`backoff`（:100） | 一致 |
| 解析 | `parseFeedPayload`（:248），间隔 :261，sha1 id :277，“快手用户” :281 | `parse`（:123），`_comment`（:153），`anonymousUserName`（:81） | 一致 |
| 坏时间 | 一条评论的时间超出范围让整个回答失败、cursor 不前进 | 只跳过这一条 | 修好（3.x 问题 1） |
| 开始失败的错误 | 一律 `CoreError` 等 | 有类型：`TransportFailure`、`HttpStatusFailure`、`FormatException`、`KuaishouFeedRejected`（:15） | 直播间只记日志不提示，同 3.x |
| 表情 | 3.x 打包了 `assets/emo/json/kuaishou.json` 但没读 | 房间页表情表加本地表（S02.1，:120～176） | 列表和飞行弹幕里显示表情图 |

## 结果

- **提交**：60e8e0278（2026-09-29，M5.5）；之后 fffd28b31（2026-10-01，S02.1 的评论表情）。
- **和 3.x 的对照**：`fixtures/kuaishou/danmaku/legacy_expected.dart` 把 3.x 整个类搬成独立程序，在记录计时器的 zone 里跑。S16-live（主播 `Kslala666`，10 次回答）42 条评论、10 次人数逐字段一致，整段会话的 11 次请求、10 次 3 s 等待、事件顺序一致；S17-synthetic 38 个回答（2 个按坏时间的差异变换）和 15 段会话一致。
- **有意差异**：record.md 8 条（事件代替回调、坏条目只跳过、错误有类型、2xx 但不是 JSON 一律换备用地址、关闭原因统一、不写日志、去掉 3.x 测试用的构造参数、开始阶段的等待可取消）。
- **没采用归档 v4 的做法**：被拒不换备用地址、开始失败仍抛给调用方、每次请求 20 s、时间不大于 0 仍按 1970 年。
- **依赖**：`packages/live_danmaku/pubspec.yaml` 加 `crypto: ^3.0.7`（和 `live_core` 同一版本）。
- **测试**：`packages/live_danmaku/test/kuaishou_test.dart` 70 个（协议 5、录制对照 2、合成回答 39、合成会话 16、连接 8，含本地 HTTP 服务器端到端）；S02.1 另加表情用例。

## 验证

- 自动测试：`kuaishou_test.dart`。
- 真实接口：E01.5 的“国内平台完善”匿名跑了两个直播间各 2 分钟：就绪 0.2 s，聊天 14 和 37 条、人数 40 和 39 次，没有重连；feed 只有 `comment` 一种条目。
- 真机：[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md) 在 K90 上修过快手标题和评论的 U+FFFC 和表情；[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1、7 条（快手热门直播间、带表情的弹幕）还没逐条填结果。

## 留下的问题

- 主地址超时（而不是拒绝）时，每次请求最多等 20 s，和直播间的启动超时 20 s 相同，备用地址来不及起作用（3.x 问题 2，保持 3.x）；改超时要和直播间的启动超时一起定，归 [C01](../../../C-直播间/C01-进房和房间逻辑/README.md) 的房间控制器。
- 礼物、醒目留言：移动端 feed 没有，桌面端 WebSocket 要签名，不做（附录 C-16）。
- 进房的合规公告不显示（附录 C-15，不做）。
