# D01.18 弹幕（新增）：LiveMe（受阻）

- 日期：2026-09-29
- 结论：**受阻，不接入。** LiveMe 直播间的聊天走平台自己的 IM（socket.io + protobuf），要先用登录账号的 uid 和登录令牌登录 IM，才能进聊天室。官网网页端只在登录以后才建 IM 连接、才进聊天室，没有游客通道。本项目不支持 LiveMe 登录（E03.8 规格 §8），也不绕过平台的限制，所以没有写连接代码、没有样本和测试，也没有加弹幕参数类。LiveMe 仍然不在弹幕平台表里，界面照 v3（`EmptyDanmaku`）只提示一次“未接入”（见“登记方式”）。
- 原定目标：`packages/live_danmaku/lib/src/sites/liveme.dart`（没有创建，`live_danmaku.dart` 没有加导出）。
- 参数：平台层已经有本场直播 id `LiveMeRoomData.videoId`，它就是聊天室 id（直播信息的 `TCRoomId`，E03.8 实测相等；本次精选第 1 页 20 场也全部相等）。没有加 `LiveMeDanmakuArgs`：只有直播 id 进不了聊天室，还缺账号的 uid、令牌和设备号，参数类没有用处。
- 升级条目：21-9“LiveMe 弹幕”。v3 没有 LiveMe 弹幕（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 参考：
  - v3：`legacy/lib/core/site/liveme/liveme_site.dart` 的 `getDanmaku()` 返回 `EmptyDanmaku`，公告 `liveme_chat_notice`；
  - 归档 v4（`archive/v4`，6ba709135）：没有 LiveMe 弹幕（`packages/live_danmaku/lib/src/sites/` 下没有这个平台）；规格 `spec/sites/liveme.md` §7 只写了“`chatSystem = "3"`、`TCRoomId`，聊天走私有 IM SDK，匿名实时通道待确认”，§12 第 2 条待确认；
  - pure_live_TV `e1cca224`：`lib/platforms/liveme/liveme_site.dart:38` 仍是 `EmptyDanmaku`，没有可参考的实现；
  - 没有录下的弹幕样本（`fixtures/liveme/` 只有 E03.8 的接口样本）；
  - 官网网页脚本（2026-09-29 北京时间 05:50 下载，下面提到的函数名都是压缩后的名字，官网更新后会变）：
    - 入口 `www.liveme.com/static/CLaEtC7T.js`（1.9 MB）：环境配置（`imUrls`）、IM 客户端类（日志前缀 `IMKit`）、protobuf 消息定义、`app-im-kit` 状态（何时建 IM 连接）；
    - 直播间 `www.liveme.com/static/CYslo3Yc.js`：进房流程、何时进聊天室、消息分发；
    - `www.liveme.com/app/spa/js/im.js`：直播间页面同时加载的旧版 IM SDK（全局 `cmim`），当前的页面脚本都不调用它；
  - 公开接口：精选目录第 1 页（2026-09-28 21:50 UTC），20 场直播的 `chatSystem` 都是 `"3"`，`TCRoomId` 都等于 `vid`。

## 做法

1. 读官网网页脚本，找出直播间聊天的通道、参数和进聊天室的条件（见“查明的协议”“受阻的原因”）。
2. 查有没有不经 IM 的公开通道：直播信息里的消息文件 `msgfile`、IM 的 HTTP 接口、分享页和手机版网页、旧版 SDK（见“其他路子”）。
3. 结论是要登录，按任务规则不硬做：没有用空的 uid 和令牌去试 IM 服务器收不收（官网客户端从不这样连，这就是绕过平台“登录后才能进聊天室”的限制），没有注册或登录账号，没有抓 App 的包。整个过程只下载了公开的网页和脚本、请求了一次精选目录和一个在播直播的消息文件，没有连过 IM 服务器（只做了 DNS 解析，`webim1`、`webim2.fusionv.com` 都还在，指向阿里云美东的负载均衡）。

## 查明的协议

只作记录，供以后支持 LiveMe 登录时参考；没有实测，没有样本。

| 项目 | 官网网页端的做法 | 出处（入口脚本） |
|---|---|---|
| 服务器 | `webim1.fusionv.com`、`webim2.fusionv.com`，配置写端口 80，https 页面改用 443；一个连不上换下一个 | 环境配置 `online.imUrls`；`IMKit.createConnection`、`reconnectConnection` |
| 传输 | socket.io-client 2（Socket.IO 协议 4、Engine.IO 3），只用 WebSocket；路径 `/live.me`，查询 `cmcm=3`，也就是 `wss://webim1.fusionv.com/live.me/?cmcm=3&EIO=3&transport=websocket`；最多重连 5 次，间隔 3 s，都失败后换服务器 | `IMKit.createConnection` |
| 事件 | 客户端发 `LOGIN`、`LIVE`、`PULL`、`LOGOUT`；服务端发 `SESSIONID`、`LOGIN`、`LIVE`、`CHAT`、`GATEWAY`、`PULL`。除 `SESSIONID` 和 `LOGOUT` 外，载荷是二进制 protobuf（Socket.IO 的二进制事件），服务端发来的是 `{cmd, body}` | 同上 |
| 登录 | 连上后发 `LOGIN`，protobuf `User`：`userid` 是登录用户的 uid，`token` 是账号的登录令牌，`appid` 是 `liveme`，`logintype` 1，`devicetype` 1（WEB），`deviceid` 是 `eb000001-<设备号>`，`sequence`、`cmsgid` 是毫秒时间。服务端回 `LOGIN {cmd: 2}`，`Ack.type` 为 1 且 `statecode` 为 0 才算登录成功 | `IMKit.loginIMKit`、`onWsLogin`；`createIM` |
| 会话号 | 服务端发 `SESSIONID`；收到的消息里 `deviceid` 等于它的是自己发的，丢掉 | `onWsSessionId`、`emitRecvMsg` |
| 进聊天室 | 发 `LIVE`，protobuf `IMMessage`：`type` 20（ROOM）、`subtype` 61（ROOM_LOGIN）、`to` 是本场直播 id（`vid`）、`from` 是 uid、`devicetype` 1、`deviceid`。**登录没成功时客户端自己不发**（日志“sendRoomEvent: 未登录，无法进行房间操作”）。服务端回 `LIVE {cmd: 2}`，`Ack.type` 6 是进了聊天室，7 是退出 | `IMKit.sendRoomEvent`、`joinRoom`、`onWsLive` |
| 消息 | `LIVE {cmd: 20}`（一条 `IMMessage`）、`LIVE {cmd: 50}`（`MessageList`）、`GATEWAY {cmd: 60}`。`type` 20、`subtype` 80（ROOM_DIY）的消息：`content` 是 JSON 文字，`extend1` 是消息名，如 `app:whitelvmsgcontent`、`app:lowlvmsgcontent`、`app:livestatmsgcontent`、`app:livevideostopmsgcontent`（各消息名的含义和字段没有样本核对） | `onWsLive`、`emitRecvMsg`；消息名枚举 |
| 保活 | 服务端发 `PULL {cmd: -100}`，客户端回 `PULL`（`IMMessage.type` 为 -100）；另有 Engine.IO 的 ping | `onWsPull` |
| 退出 | 发 `LOGOUT {id: uid}` 后断开 | `logoutIMKit` |

## 受阻的原因

1. **IM 连接只在登录后建立**：`app-im-kit` 状态监听登录状态（立即执行一次）：登录了才调 `createIM`，没登录就销毁 IM。`createIM` 还要求用户信息里有设备号，没有就显示登录错误，不连接。
2. **直播间只在登录后进聊天室**：直播间脚本的进房流程（出错日志里叫 `updateChannel`）在没登录时走 `anonymous-user` 播放路径，只放流，然后直接返回，走不到进聊天室的那一步（`chatSystem` 为 `"3"` 时 `joinRoom(vid)`，只在登录分支的末尾调用）。即使调用了，没有 IM 实例时 `joinRoom` 只打印“加入房间失败，不存在IM”。
3. **IM 登录用的是账号凭据**：`LOGIN` 里的 uid 和令牌来自账号登录后的用户信息（`userInfo.user.uid`、`userInfo.token`），IM 客户端在收到登录成功的应答前不发进聊天室的包。网页端没有给游客发 IM 令牌的接口。

所以：进 LiveMe 聊天室需要登录账号。本项目没有 LiveMe 登录，也不做绕过，21-9 记为受阻。

## 其他路子

| 路子 | 结果 |
|---|---|
| 直播信息里的 `msgfile`、`gzip_msgfile`（`sz.esxscloud.com/message/…/<vid>.json`） | 回放用的消息文件，在播时不存在：2026-09-28 21:51 UTC 请求一场在播直播的文件，阿里云 OSS 回 404 `NoSuchKey`（E03.8 规格 §7 也说它“只是回放用的消息文件”） |
| IM 的 HTTP 接口 `imapi.liveme.com` | 脚本里只有私信用的 `/api/rest/getuploadtoken`、`/chat/rest/getunreadmsgs`、`/chat/rest/ackUnreadMsgs`，都要账号的 `cmimToken` 加签名，没有直播间消息的接口 |
| 分享页 `/m/v/<vid>/index.html?live=1`、手机版 `/m/` | 跳到（或就是）同一个单页应用，入口脚本相同，逻辑同上 |
| 旧版 SDK `/app/spa/js/im.js`（`cmim`） | 没有用户时 `userid` 留空，但仍要传 `token`（没有地方给游客令牌）；路径是默认的 `/socket.io/`；当前的页面脚本都不调用它，是残留 |
| 其他聊天系统 | 在播直播的 `chatSystem` 全是 `"3"`（自有 IM）；`TCRoomId` 只是字段名，等于 `vid`，脚本里没有腾讯云 IM 的 SDK |
| App 端 | 要抓包和 App 的签名，按任务规则不做 |

## 与归档 v4、上游的差异

没有差异：v3、归档 v4 和 pure_live_TV 都没有 LiveMe 弹幕，本模块也不接入。归档规格 §7、§12 第 2 条的“匿名实时通道待确认”现在有了答案：没有匿名通道（见“受阻的原因”）。

## 登记方式

不登记。应用（I01.1）建平台表时不加 `liveme`：`DanmakuRegistry.connectionFor('liveme')` 返回 `EmptyDanmakuConnection`，`supports('liveme')` 为假，界面照 v3 不连接、只提示一次 `remote_danmaku_not_integrated`（D01.1“平台表”）。E03.8 改过的直播间公告 `liveme_chat_notice`（“这里暂时看不到 LiveMe 直播间的聊天……”）仍然符合实际，不用改。

在线人数不变：`audience.dart` 里 LiveMe 那一项没有改，人数仍来自详情和列表（热度、正在观看、累计观看）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 平台表不登记 LiveMe | I01.1 |
| “未接入”提示和 LiveMe 公告照 v3 显示 | M13 |
| 将来如果支持 LiveMe 登录（目前不在计划里）：按“查明的协议”接入，参数除 `LiveMeRoomData.videoId` 外还要账号的 uid、令牌和设备号，那时再在平台层加 `LiveMeDanmakuArgs` | 待定 |

## 新增的通用能力、依赖

没有。没有改代码、没有新依赖、没有新样本。只改了三个文档：本记录、`docs/specs/UPGRADES.md` 的 21-9 行、`docs/PLAN.md` 第 6 节的 T06a.x 行。

## 测试

没有新增测试（没有代码）。在 worktree 根目录跑 `bash tools/gate/gate.sh --all`，输出 `gate: passed`。
