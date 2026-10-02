# D01.19 弹幕（新增）：TikTok（受阻）

- 日期：2026-09-29
- 结论：**受阻，不接入。** TikTok 网页直播间的评论只从平台的 IM 拿：先请求一次 `webcast/im/fetch/`，成功后再连 WebSocket（`webcast/im/ws_proxy/ws_reuse_supplement/`）。这两步都要网页安全 SDK（`webmssdk` 2.0.0.561）现场生成的签名。按任务要求先核对了仓库里抖音的纯 Dart 签名（`DouyinSigner`）：TikTok 用的不是同一套算法。把仓库的 X-Bogus 风格签名、a_bogus 加上去，服务端的回应和完全不签名时一模一样，都被拒绝（见“实测”）。要拿到有效签名，只能在浏览器或 JS 引擎里跑 TikTok 的混淆 SDK，或者用要 API 密钥的第三方签名服务。这两条路任务规则都不允许，属于绕过平台的访问限制，所以没有写连接代码，没有样本和测试，也没有加弹幕参数类。TikTok 仍然不在弹幕平台表里，界面照 v3（`EmptyDanmaku`）只提示一次“未接入”（见“登记方式”）。
- 原定目标：`packages/live_danmaku/lib/src/sites/tiktok.dart`。这个文件没有创建，`live_danmaku.dart` 也没有加导出。
- 参数：平台层已经有本场的直播间号 `TikTokRoomData.liveRoomId`（`user.roomId`，E03.9），这就是 IM 用的 `room_id`。没有加 `TikTokDanmakuArgs`：只有直播间号连不上，还缺签名；访客 Cookie `ttwid` 平台层也没有拿（E03.9 不带 Cookie）。有了签名以后再加才有用。
- 升级条目：22-7“TikTok 评论弹幕”。v3 没有 TikTok 弹幕（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 参考：
  - v3：`legacy/lib/core/site/tiktok/tiktok_site.dart` 的 `getDanmaku()` 返回 `EmptyDanmaku`，公告 `tiktok_chat_notice`；
  - 归档 v4（`archive/v4`，6ba709135）：没有 TikTok 弹幕（`packages/live_danmaku/lib/src/sites/` 下没有这个平台）。规格 `spec/sites/tiktok.md` §7 写着“网页评论走 `webcast/im/fetch` 轮询（protobuf）和 WebSocket，两者都要求 X-Bogus 等签名参数和 `msToken`”，§12 第 4 条“免签名的评论入口”待确认；
  - pure_live_TV `e1cca224`：`lib/platforms/tiktok/tiktok_site.dart:38` 仍是 `EmptyDanmaku`，没有可参考的实现；
  - 没有录下的弹幕样本（`fixtures/tiktok/` 只有 E03.9 的接口样本）；
  - 仓库：`packages/live_core/lib/src/sites/douyin/douyin_sign.dart`（`DouyinSigner`：`msToken`、`aBogus`、`xBogus`、`danmakuSignature`），D01.5 的 `packages/live_danmaku/lib/src/sites/douyin.dart`、`codec/protobuf.dart`；
  - 官网网页脚本（2026-09-29 北京时间 06:02～06:10 经代理下载；下面的模块号、函数名是打包后的名字，官网更新后会变）：
    - 直播间页面 `www.tiktok.com/@<用户名>/live`：脚本清单 `script-manager` 把 `acrawler` 指向 `webmssdk/2.0.0.561/webmssdk.js`（245 KB，字节码虚拟机，对外只有 `frontierSign`、`registerWsSigner` 等几个入口）；
    - `live_new/static/js/main.bdcac0d4.js`：`acrawler` 的初始化配置（`aid: 1988`、`intercept: true`、`enablePathList`）；
    - 直播间的路由块 `async/main___live-container/(anchorName).live/page.5f08d010.js`：IM 的配置和启动；
    - IM SDK 块 `async/40231.7dba9d62.js`：拉取、WebSocket、帧和 `Response` 的 protobuf 定义；
  - 第三方项目的公开说明（只读了说明，没有用它们的代码或服务）：Euler Stream 的签名服务（TikTok-Live-Connector 等库默认把签名交给它，用量按 API 密钥和配额算），all-chat PR #886（2026-09-15 在无头 Chromium 里跑 TikTok 的 SDK 签 `im/fetch`），tiktok-signer（在嵌入式 JS 引擎里跑 `webmssdk`，给连接地址签 `X-Gnarly`）。

## 做法

1. 读官网网页脚本，找出直播间评论的通道、参数和签名方式（见“查明的协议”）。
2. 按任务要求核对仓库里抖音的签名能不能用在 TikTok 上：先对比两边的算法入口，再用仓库的 `DouyinSigner` 真的签一次，只读地发出去，看服务端收不收（见“与抖音签名的核对”“实测”）。
3. 找有没有不要签名的公开通道：预览拉取、另一个接口主机、连接时不签名只带访客 Cookie（见“其他路子”）。
4. 结论是签名对不上、也拿不到，按任务规则不硬做：没有在浏览器或 JS 引擎里运行 TikTok 的 SDK，没有用第三方签名服务，没有逆向虚拟机字节码写新的签名算法，没有登录，没有发言。全程只下载了公开的网页和脚本，按网页端的参数发了几次只读的 GET 和 WebSocket 握手，每次都被拒绝，没有收到任何评论数据。

## 查明的协议

只作记录，以后签名问题解决了可以参考。没有实测成功过，也没有样本。

| 项目 | 官网网页端的做法 | 出处 |
|---|---|---|
| 顺序 | IM 实例 `config` 里有 `fetchBeforeWsSuccess: "1"`、`wsDirect: "1"`：先 HTTP 拉取一次，成功后按回答里的 `push_server`、`route_params`、`heartbeat_duration` 建 WebSocket；拉取失败时每 1 s 重试一次 | 路由块 `imInstance.config`；IM 块的 `fetchConfig`、`createClient` |
| 拉取 | `GET <webcast 主机>/webcast/im/fetch/`（预览是 `/webcast/im/fetch/preview/`，历史评论是 `/webcast/im/fetch/history/`），XHR 带 Cookie，超时 10 s，回答是 protobuf `webcast.im.Response`。第一次的参数是 `cursor=0`、`internal_ext=0`、`last_rtt=-1`，另有 `aid=1988`、`app_name=tiktok_web`、`live_id=12`、`version_code`（SDK 的 `180800`，另有配置里的 `270000`）、`update_version_code=2.0.0`、`sup_ws_ds_opt=1`、`resp_content_type=protobuf`、`did_rule=3`、`room_id`、`webcast_language`，以及浏览器信息（`browser_*`、`screen_*`、`tz_name` 等） | IM 块的 `k()`、`D()`、`B()`、`deserializeFetch` |
| 拉取的签名 | IM 块自己不签，由 `webmssdk` 拦截 XHR 时加：`acrawler` 配置 `intercept: true`，`enablePathList` 里有 `/webcast.*`，所以 `im/fetch` 会带上 `msToken` 和 SDK 算出的签名参数 | `main.bdcac0d4.js` 的 `acrawler` 配置 |
| WebSocket 地址 | `wss://webcast-ws.us.tiktok.com`（美区，本机代理出口的页面是 `us-ttp`）、`wss://webcast-ws.eu.tiktok.com`（欧区）或 `wss://webcast-ws.tiktok.com`，路径 `/webcast/im/ws_proxy/ws_reuse_supplement/`。查询参数同拉取，加上拉取回答里的 `route_params`、`cursor`、`internal_ext`、`compress=gzip`、`heartbeat_duration` | IM 块的 `createClient` |
| WebSocket 的签名 | 地址末尾加 `&X-Bogus=<acrawler.frontierSign({"X-MS-PAYLOAD": ""})["X-Bogus"]>`；`webmssdk` 还有 `registerWsSigner`（tiktok-signer 的说明是它给连接地址加 `X-Gnarly`）。握手要带访客 Cookie `ttwid`（页面的 `Set-Cookie` 会给） | IM 块的 `createClient`；`webmssdk.js` 导出的方法 |
| 帧 | protobuf `webcast.im.PushFrame`：`SeqID 1`、`LogID 2`、`service 3`、`method 4`、`headers 5`（`PushHeader{key 1, value 2}`）、`payload_encoding 6`、`payload_type 7`、`payload 8`。**字段号与抖音（D01.5）相同** | IM 块的帧定义 |
| 回答 | `Response`：`messages 1`、`cursor 2`、`fetch_interval 3`、`now 4`、`internal_ext 5`、`fetch_type 6`、`route_params 7`（map）、`heartbeat_duration 8`、`need_ack 9`、`push_server 10`、`is_first 11`、`history_comment_cursor 12`、`history_no_more 13`；`Message`：`method 1`、`payload 2`、`msg_id 3`、`msg_type 4`、`offset 5`、`is_history 6`、…。`Response` 的 1～10 号字段与 v3 `douyin.proto` 的 `Response` 相同（11 号以后不同），`Message` 的前 3 个字段也相同 | 同上 |
| 加入 | 连上后发 `payload_type = "im_enter_room"` 的帧，负载 `EnterRoom{room_id 1, room_tag 2, live_region 3, live_id 4, identity 5, cursor 6, account_type 7, …, filter_welcome_msg 9 = "0"}`，`payload_encoding = "pb"`（抖音只发一个空的 `hb` 帧） | IM 块的 `enterRoom` |
| 心跳 | `payload_type = "hb"`，负载 `HeartBeat{room_id 1}`（抖音的心跳没有负载）；间隔取 `heartbeat_duration`，最少 10 s | IM 块的 `ping` |
| ACK | `need_ack` 为真时回 `payload_type = "ack"`，负载是 `internal_ext` 的 UTF-8，`LogID` 同原帧（与抖音相同） | IM 块的消息处理 |
| 关闭码 | 4001（服务端主动断开）、4003（出错） | IM 块的枚举 |
| 消息 | 按 `method` 分发，名字是 `Webcast<类型>`（`WebcastChatMessage`、`WebcastRoomUserSeqMessage` 等，个别有别名）；`common.room_id` 与本场不同的丢掉（`filterByRoomId`）；同一个 `room_id + msg_id` 只处理一次 | IM 块的 `emit`、`runCallbackByMethod` |

所以，签名问题解决后，解码部分可以复用 D01.5 的思路和 `codec/protobuf.dart`（帧、`Response` 用到的字段、`Message`、ACK 的字段号都一样）。要改的是：连接前的拉取、`im_enter_room` 加入帧、带负载的心跳，还有 TikTok 自己的聊天、人数消息字段（这次没有核对）。

## 与抖音签名的核对

| 项目 | 抖音（仓库已有，E01.4、D01.5） | TikTok 网页（2026-09-29） |
|---|---|---|
| 安全 SDK | 抖音网页的 `webmssdk`；仓库是 3.x 逆向后写死常数的纯 Dart 移植 | `webmssdk/2.0.0.561`，签名逻辑在字节码虚拟机里，脚本里看不到算法 |
| 弹幕连接的签名 | 查询参数 `signature` = `frontierSign({"X-MS-STUB": md5(13 个固定参数)})` 的 16 字符 X-Bogus（`DouyinSigner.danmakuSignature`、`xBogus`）；不用先拉取 | 连接地址追加 `X-Bogus` = `frontierSign({"X-MS-PAYLOAD": ""})`，入口的键就不同；另有 `registerWsSigner`；而且必须先有一次签名成功的 `im/fetch` |
| HTTP 签名 | `a_bogus`（`DouyinSigner.aBogus`，SM3，数据里写死抖音的 aid 6383） | `im/fetch` 由 SDK 拦截 XHR 签名，不用 `a_bogus` 这个参数 |
| msToken | 本地随机 184 个字符，抖音接受（3.x 的 `getMSToken`） | 服务端在响应头 `x-ms-token` 里下发（这次拿到的是 124 个字符），被拒绝的请求也会给，所以卡住的不是 msToken |
| 结论 | — | **算法对不上**：仓库的 `xBogus` 负载里的常数和入口是抖音那一版的，`aBogus` 是另一个参数、另一个 aid。实测加上它们和不签名的结果完全一样（下表） |

## 实测

2026-09-29 北京时间 06:01～06:15，经本机代理（出口在美国），只读，不登录：

| # | 请求 | 结果 |
|---|---|---|
| 1 | `api-live/user/room` 查了 80 多个公开账号（`@qvc`、`@hsn`、新闻、体育、购物、电台等） | 都没在播（`status 4` 或账号不存在）。为了测握手，从一个公开的直播存档站找了一个正在播的普通用户的直播间（81 人在线），只把它的直播间号当握手目标，账号和内容都不记录 |
| 2 | `webcast.us.tiktok.com/webcast/im/fetch/`，网页端的参数，不签名，带或不带页面给的 `ttwid` | HTTP 403，正文为空；响应头里有 `x-ms-token` |
| 3 | 同上，主机换成 `webcast.tiktok.com` | HTTP 200，`content-type: application/json`，正文为空（和 E06 平台层升级 测目录时 `webcast/feed` 空正文的拒绝方式一样） |
| 4 | 2、3 再加上第 2 步下发的 `msToken`、`ttwid`，以及仓库算出的 `X-Bogus`（`DouyinSigner.xBogus(md5(查询串))`）或 `a_bogus`（`DouyinSigner.aBogus(查询串)`） | 与不签名时相同：美区 403 空正文，另一个主机 200 空正文 |
| 5 | `webcast.us.tiktok.com/webcast/im/fetch/preview/`，不签名 | HTTP 403，正文为空 |
| 6 | WebSocket 握手 `wss://webcast-ws.us.tiktok.com/webcast/im/ws_proxy/ws_reuse_supplement/?…`（也试了 `webcast-ws.tiktok.com`），不带 Cookie | 不升级，HTTP 200，`Handshake-Status: 417`，`Handshake-Msg: http: named cookie not present` |
| 7 | 同上，带 `ttwid` | `Handshake-Status: 417`，`Handshake-Msg: illegal secret key` |
| 8 | 同上，带 `ttwid`，再加仓库算出的 `X-Bogus`（`xBogus(md5(""))`，对应 `X-MS-PAYLOAD` 为空；或 `xBogus(md5(查询串))`） | 同第 7 条：`illegal secret key` |

## 受阻的原因

1. **评论只有 IM 一条路，入口要签名**：网页端先签名拉取、成功后才连 WebSocket（`fetchBeforeWsSuccess`）。不签名时拉取被拒（403 或空正文），WebSocket 握手报 `illegal secret key`。
2. **仓库的抖音签名对不上**：入口（`X-MS-STUB` 对 `X-MS-PAYLOAD`）、SDK 版本和参数都不同。实测加上仓库的签名和不签名的结果完全一样，说明服务端不认。
3. **有效签名只能靠运行 TikTok 自己的 SDK 或第三方服务**：`webmssdk` 2.0.0.561 的签名在字节码虚拟机里，脚本里没有可以照着写的算法。公开的做法有两种：在无头浏览器或 JS 引擎里跑这个 SDK（all-chat、tiktok-signer），或者用 Euler Stream 这类签名服务（要 API 密钥）。前者是冒充浏览器来绕过平台的访问限制，后者是第三方 SDK 密钥，都是任务规则不允许的。逆向虚拟机写一套新的签名也不属于“复用”，而且平台还在改：all-chat 记录 2026-09-15 加上 `X-Gnarly` 反而 403，维护成本高。

所以 22-7 记为受阻。

## 其他路子

| 路子 | 结果 |
|---|---|
| 预览拉取 `im/fetch/preview/`、历史评论 `im/fetch/history/` | 同属 `/webcast.*`，由 SDK 签名；预览不签名时 403（实测第 5 条），历史接口要先有拉取给的游标 |
| 另一个接口主机 `webcast.tiktok.com` | 200 空正文，同样是拒绝（实测第 3 条） |
| 不拉取，直接连 WebSocket | 带访客 Cookie 也报 `illegal secret key`（实测第 7、8 条） |
| 进房接口 `api-live/user/room`、`webcast/room/info` | 不要签名，但只有房间信息和人数（E03.9 已用），没有评论 |
| 登录 | 不解决签名问题；本项目也不支持 TikTok 登录（E03.9） |
| App 端 | 另有一套签名（抓包加逆向），按任务规则不做 |

## 与归档 v4、上游的差异

没有差异：v3、归档 v4 和 pure_live_TV 都没有 TikTok 弹幕，本模块也不接入。归档规格 §7、§12 第 4 条“免签名的评论入口”现在有了答案：没有。拉取和 WebSocket 都要 SDK 现场生成的签名，仓库里抖音的签名不能代替（见“实测”）。

## 登记方式

不登记。应用（I01.1）建平台表时不加 `tiktok`：`DanmakuRegistry.connectionFor('tiktok')` 返回 `EmptyDanmakuConnection`，`supports('tiktok')` 为假，界面照 v3 不连接，只提示一次 `remote_danmaku_not_integrated`（D01.1“平台表”）。E03.9 改过的直播间公告 `tiktok_chat_notice`（“TikTok 直播的评论暂时不能在这里显示……”）仍然符合实际，不用改；E03.9“留给其他模块”里“接上后去掉公告第一句”也就不用做。

在线人数不变：`audience.dart` 里 TikTok 那一项没有改，人数仍来自进房和刷新（`liveRoomStats.userCount` 在线、`enterCount` 累计）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 平台表不登记 TikTok | I01.1 |
| “未接入”提示和 TikTok 公告照现状显示 | M13 |
| 将来如果有了合规的签名来源（比如平台开放了免签名的入口）：按“查明的协议”接入，参数除 `TikTokRoomData.liveRoomId` 外还要访客 Cookie `ttwid`，那时再在平台层加 `TikTokDanmakuArgs`；解码复用 D01.5 的思路和 `codec/protobuf.dart` | 待定 |

## 新增的通用能力、依赖

没有。没有改代码，没有移动 `douyin_sign.dart`（签名对不上，没有可共用的部分），没有新依赖，没有新样本。只改了三个文档：本记录、`docs/specs/UPGRADES.md` 的 22-7 行、`docs/PLAN.md` 第 6 节的 D01 各平台 行。

## 测试

没有新增测试（没有代码）。在 worktree 根目录跑 `bash tools/gate/gate.sh --all`，输出 `gate: passed`。
