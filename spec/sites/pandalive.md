# 平台规格：pandalive（PandaTV）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`pandalive`（legacy/lib/core/sites.dart:66），显示名 `PandaTV`（legacy/assets/translations/zh.json `site_pandalive`）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/pandalive/`（A = pandalive_api.dart，L = pandalive_link.dart，S = pandalive_site.dart），其它旧代码写全路径（相对 `legacy/`）。样本编号见 §11。
- 状态：**保留**。2026-09-27 实测：接口、媒体、弹幕都能匿名使用（经 Clash 出口，服务端看到的是美国地址）；有公开目录（约 120～130 个非成人直播）。成人（19+）和粉丝专属直播需要登录和实名认证（§9），但公开直播占目录全部，不满足 ADR 0003 的下线条件。
- 能力：目录（全部直播按人气、新人主播，原生分页）、搜索（直播标题/主播 + 主播资料，含未开播）、详情、取流（Amazon IVS HLS，按变体给画质）、弹幕（Centrifugo WebSocket，匿名令牌）。
- 不提供：登录；成人和粉丝专属直播（NeedsLogin）；密码房（StreamUnavailable）；WebRTC（`whip`）线路。

---

## 1. 房间身份与链接

**规范身份**：主播登录 id `userId`（L:32-38），如 `daisy00`；社交账号注册的 id 带后缀，如 `1506087545@ka`、`korea7655@todisk`。格式 `^[A-Za-z0-9_]{1,64}(@[A-Za-z0-9_]{2,16})?$`。数字 `userIdx` 是聊天频道号（§7），不作为房间号。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 直播页 | `https://www.pandalive.co.kr/play/<id>`、`https://m.pandalive.co.kr/play/<id>` | id | 2026-09-27 实测（旧地址 `/live/play/<id>` 307 跳到 `/play/<id>`） |
| 旧直播页 | `https://www.pandalive.co.kr/live/play/<id>` | id | L:18-20 |
| 频道页 | `https://www.pandalive.co.kr/channel/<id>`、`/channel/<id>/home/...` | id | L:21-26 |
| 分享文本 | 链接前后夹有文字 | 抽出第一个 URL | — |

- 主机：`pandalive.co.kr`、`www.pandalive.co.kr`、`m.pandalive.co.kr`（L:4）。
- 链接解析不发请求；主播是否存在由详情判断（§4）。
- 外部打开：`https://www.pandalive.co.kr/play/<id>`。

---

## 2. 目录

### 2.1 分类

- 平台没有分类筛选（网页的列表参数只有 `offset`、`limit`、`orderBy`、`onlyNewBj` 等；条目的 `category` 是 `ind`、`game`、`music`、`etc` 之类的代码，没有名称接口）。
- v4：一个 `Category`（id `live`，名称 `PandaTV`），两个 `Area`：`hot`（全部直播，按人气）、`newbj`（新人主播，`onlyNewBj=Y`）。旧版只有一个“公开直播”（S:87-103）。

### 2.2 列表

- POST `https://api.pandalive.co.kr/v1/live/index`，表单 `offset`、`limit`（30）、`orderBy=hot`，新人主播再加 `onlyNewBj=Y`（A:285-299；S01、S02）。
- `orderBy`：`hot` 人气，`user` 观众数，其它值（`new`）按开播时间。
- 返回 `page {offset, limit, total, page, lastPage}` 和 `list[]`。`page.offset` 必须等于请求的 offset，否则 ApiChanged（A:357-372）。下一页 offset = 本页 offset + 行数，达到 `total` 为最后一页（S01-index-hot-last）。
- 游客只能看到非成人直播：成人直播不出现在列表里，只能通过搜索或链接找到（§9）。
- 推荐 = `hot` 第一页起。

### 2.3 条目

| 字段 | 含义 | v4 |
|---|---|---|
| `userId`、`userIdx` | 主播 id、数字号 | 房间号 = `userId` |
| `userNick` | 主播名 | 主播名 |
| `title` | 直播标题 | 标题（空则主播名） |
| `thumbUrl`、`ivsThumbnail` | 截图 | 封面 |
| `userImg` | 头像 | 头像 |
| `user` | 当前观众数 | `online` |
| `playCnt` | 本场进入次数 | `cumulative` |
| `startTime` | 开播时间，**韩国时间**（UTC+9）无时区，`0000-00-00 00:00:00` 表示没有 | 开播时间 |
| `isLive`、`isAdult`、`isPw`、`type`（`free`、`fan`） | 状态、成人、密码、粉丝专属 | 只收 `isLive == true` 的行 |

- 图片只接受 `pandalive.co.kr` 及子域的 https 地址（A:697-706）。
- 同一主播在一页里重复只保留第一条（S:169-174）。

---

## 3. 搜索

- 第一页：先查直播（POST `v1/live/index`，`orderBy=user`、`searchVal=<关键词>`、`limit=20`，Referer `/search/live`；S03-search-live），匹配直播标题和主播；再查主播（POST `v1/live/bj_list`，`searchVal`、`limit=20`，Referer `/search/bj`；S03-search-bj），匹配主播 id 和昵称，含未开播。直播结果在前，按 id 去重。
- 之后的页只翻主播搜索（`offset` 递增）。
- 主播行：`userId`、`userNick`、`thumbUrl`（头像）；在播时带 `media`（与 §2.3 同形），据此给出在播状态和观众数；`blockService == true` 的行跳过（A:336）。
- 直播搜索失败时只返回主播搜索的结果（旧版同样容忍其中一个失败，S:228-253）。
- 两个请求**依次**发出：旧版记录过网关会卡住同主机的并发 POST（S:228-229）。
- 关键词超过 100 字截断。输入是链接：按 §1 精确查找（未开播也返回）。

---

## 4. 房间详情

- POST `v1/member/bj`，表单 `userId`、`info=media`（旧版 `info=media fanGrade`，粉丝等级 v4 不用；A:379）。Referer `/play/<id>`。
- `bjInfo`：`id`（必须等于请求的 id，不区分大小写）、`idx`、`nick`、`thumbUrl`（头像）、`channelTitle`、`channelDesc`（简介）、`channelBannerUrl`、`fanCnt`。
- `media`：在播时是 §2.3 的对象（`userId` 必须一致，否则 ApiChanged；A:609-614），未开播时为 `null`（S04-member-offline）。
- 状态：`media.isLive == true` 为直播中，否则未开播。
- 标题：直播中用 `media.title`，未开播用 `channelTitle`（再退到昵称）。
- 不存在的 id：**HTTP 400**，`{"result":false,"message":"유저 정보가 없습니다."}`（S04-member-notfound）→ NotFound。
- 弹幕参数（直播中）：`userId`、`channel`（= `idx`）。
- 成人、密码、粉丝专属只在取流时才知道（§9）；详情照常显示直播中。

---

## 5. 画质与线路

- 取流先调 `live/play`（§6.1），再读 IVS 主列表（§6.2）。每个视频变体一个画质：id `<高>p`（帧率 ≥ 50 时 `<高>p60`），源画质（`VIDEO="chunked"`）标“原画”；按分辨率、码率降序；只带音频的变体跳过（S06-master：1080p 原画、720p、480p、360p、160p，都是 `avc1` + `mp4a`）。
- 每个画质一条线路（身份 `ivs`），地址是变体播放列表；确认画质 = 请求。没有“自动”：主列表只能读一次（§6.2）。
- 默认选最高画质。

---

## 6. 取流

### 6.1 `live/play`

- POST `v1/live/play`，表单 `action=watch`、`userId`、`password=`（空）、`shareLinkType=`（空），Referer `/play/<id>`（A:400-405；S05-play-live）。网页每次进入直播间也这样调用（返回“시청이 시작되었습니다”，计入观看）。
- 成功：`media`（同 §2.3，`userId` 必须一致，`isLive` 必须为真）、`PlayList.hls3`/`hls2`/`hls`（各一个 `{name:"자동", url}`，地址相同；按此顺序取第一个，A:616-626）、`PlayList.whip`（WebRTC，不用）、`channel`、`token`（聊天令牌，§7）、`chatServer`、`fanList`、`ispInfo`、`loginInfo`。
- 地址必须是 `https://*.live-video.net/…m3u8`（A:628-643）。
- 拒绝：**HTTP 400**，`errorData.code`（§9）。

### 6.2 IVS 主列表只能用一次

- 主列表地址带 `token`（ES384 JWT：`aws:single-use-uuid`、`exp = 签发 + 600 s`、`aws:access-control-allow-origin: https://*.pandalive.co.kr`、`aws:strict-origin-enforcement: true`）。
- **同一地址第二次请求返回 403 `playback_auth_error`**（2026-09-27 实测）。所以适配器自己读一次主列表，把**变体地址**交给播放器；每次取流都重新调用 `live/play`。旧版也是先读主列表再给变体（A:420-425）。
- 变体地址（`https://<id>.<区>.playlist.live-video.net/v1/playlist/<不透明令牌>.m3u8`）可重复读取，主列表令牌过期后仍可用，但**有有效期**：同一个变体地址签发 34 分钟后仍能取到列表和分片，87 分钟后返回 403 `Forbidden`（2026-09-27 实测；直播间仍在播）。过期后列表不再更新，播放停住。
- 租期：签发（调用 `live/play` 的时刻）后 30 分钟刷新，`cutsConnection = true`；没有可读的到期时间（令牌不透明），`expiresAt` 不填 [待确认准确有效期]。

### 6.3 请求头

- API：UA、`Accept: application/json, text/plain, */*`、`Origin: https://www.pandalive.co.kr`、Referer（页面地址）、表单 Content-Type（A:157-163）。
- 媒体：**主列表、变体列表和分片都要 `Origin: https://www.pandalive.co.kr`**，没有时 403（分片返回 `origin required`；只带 Referer 也是 403）。v4 线路请求头：UA、Origin、`Referer: https://www.pandalive.co.kr/`（A:165-169）。

### 6.4 媒体实况（2026-09-27）

- HLS 3，2 秒 TS 分片（`*.cloudfront.hls.live-video.net/v1/segment/…ts`），H.264（`avc1.640028` 源画质、`avc1.4D401F` 转码）+ AAC。没有 FLV，也就没有 codec 12（HEVC）问题。
- `live_cli probe pandalive https://www.pandalive.co.kr/play/bakrup0210`：解析 → 详情（直播中，在线 58）→ 取流（1080p 原画、720p、480p、360p、160p）→ 读到 HLS 列表，通过（2026-09-27）。
- 主列表的会话数据里有观众地址（`USER-IP`）、国家、会话号；不影响播放。

---

## 7. 弹幕

旧版没有 PandaTV 聊天（S:84；legacy/assets/translations/zh.json `pandalive_chat_notice`）。以下来自网页脚本（centrifuge-js 2.x）和 2026-09-27 实测。

### 7.1 连接

- 令牌：`live/play` 的 `token`（HS256 JWT，`sub` 是游客会话，`exp = 签发 + 1800 s`）和 `channel`（主播 `userIdx`）。每次连接都重新调用 `live/play`（令牌 30 分钟过期；网页也在过期前调用 `v1/chat/refresh_token`，v4 用重连代替）。
- 地址：`wss://chat-ws.neolive.kr/connection/websocket`（网页配置 `PANDA_CHAT_SOCKET`；另有 `chat-ws.pandalive.co.kr` 等开发和日本站地址，不用）。握手请求头 `Origin: https://www.pandalive.co.kr`、UA。
- 服务端：Centrifugo 3.1.1，JSON 协议（每个命令带 `id`；一帧可以有多行，每行一个 JSON）。
- 连上后发：
  1. `{"params":{"token":"<令牌>","name":"js"},"id":1}` → 回 `{"id":1,"result":{"client":…,"version":"3.1.1","expires":true,"ttl":1798,"subs":{"_person:#<游客>":{}}}}`（服务端自动订阅游客的个人频道，v4 不处理）；
  2. `{"method":1,"params":{"channel":"<channel>"},"id":2}` → 回 `{"id":2,"result":{}}`，收到即加入成功。
- 回复带 `error`（令牌无效、过期）→ 拒绝，重新取令牌再连。
- `live/play` 被拒（成人、粉丝专属、已下播，§9）时不连接。

### 7.2 心跳

- 每 25 s 发 `{"method":7,"id":<递增>}`，服务端回 `{"id":<同>}`。服务端不主动发心跳。
- 令牌到期（约 30 分钟）服务端断开，共用的 SocketConnector 重连并重新取令牌 [待确认断开时的关闭码]。

### 7.3 消息

- 频道推送：`{"result":{"channel":"<channel>","data":{"data":{…},"offset":<序号>}}}`；频道不等于当前主播的丢弃；带 `result.type` 的是其它推送类型（加入、离开、断开），忽略。
- `offset` 在频道内递增，v4 用 `pandalive:<channel>:<offset>` 作消息 id。
- `data.type`：

| type | 含义 | 处理 |
|---|---|---|
| `bj`、`chatter`、`manager`、`support` | 普通聊天（网页 `isNormalChatMessage`）：`message` 文本、`emoticon`（表情，`{<样式>: {name, img, anim}}`）、`id` 登录 id、`nk` 昵称、`idx`、`created_at`（秒）、`lev` 粉丝等级等 | 聊天；只有表情时显示 `[<表情名>]` |
| `SponCoin` | 送心（`message` 是 JSON 字符串：`nick`、`id`、`idx`、`coin` 数量；带 `heart` 时是签名心） | 礼物：`하트` / `시그니처하트` × `coin` |
| `ItemCoin` | 特别心（同上） | 礼物：`스페셜하트` × `coin` |
| `MediaUpdate` | 点赞、收藏、积分 | 忽略 |
| `Recommend`、`Info`、`FanUp`、`FanIn`、`KingFanIn`、`ManagerIn` 等 | 推荐、等级变化、入场（带观众名） | 忽略 |
| `RoomEnd`、`CastPause`、`ModifyRoom` 等 | 房间状态 | 忽略 |

- 没有在线人数推送（网页另外轮询 `cache-api` 的 `channel_user_count`），v4 用详情的 `user`。

---

## 8. 登录与 Cookie

- 不支持登录。接口下发 `sessKey`、`partner` 和一个随机名的 Cookie，匿名请求不需要带回。

---

## 9. 错误与风控

PandaTV 把拒绝放在 **HTTP 400** 的 JSON 里（`result: false`、`message`、`errorData.code`）。

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | A:231-246 | NetworkFailure |
| HTTP 429 / 401、403 | A:262-264 | RateLimited / RiskControl |
| `member/bj` 400 `유저 정보가 없습니다.` | S04-member-notfound；A:380-383 | NotFound |
| `live/play` `castEnd`（已下播） | S05-play-castend；A:409 | StreamUnavailable |
| `live/play` `needAdult`（本人认证，成人直播）、`needLogin`（粉丝专属等） | S05-play-needlogin；2026-09-27 实测 | NeedsLogin |
| `live/play` `needPassword`、`password`（密码房） | A:412 | StreamUnavailable |
| 其它 `errorData.code` | A:413 | StreamUnavailable（带代码） |
| 无 `errorData` 的其它拒绝、非 JSON、`page.offset` 不符、`bjInfo`/`media` 不属于请求的主播 | A:357-372、A:387-389 | ApiChanged |
| IVS 主列表 403 | §6.2 | RiskControl |

- 同一直播间会在直播中途切换成人状态（2026-09-27：`daisy00` 先是公开，后 `isAdult` 变真，`live/play` 返回 `needAdult`，稍后又回到公开列表）。
- `api.pandalive.co.kr` 的 TLS 握手偶尔超时（2026-09-27 约四分之一的请求，重试即好）；由通用的请求超时和重试处理。

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-PANDALIVE-001 | 不存在的主播、已下播、成人房都报“格式错误” | 旧版把非 200 的响应体丢掉，400 一律当格式错误，读不到 `errorData.code` 和 `message` | 400 照常解析 JSON，按 §9 映射 | A:197-200、A:261 |
| REG-PANDALIVE-002 | 播放器打不开主列表 | IVS 主列表令牌只能用一次 | 适配器读一次，交出变体地址 | §6.2 |
| REG-PANDALIVE-003 | 列表、分片 403 | IVS 强制检查 Origin | 所有媒体请求带 Origin | §6.3 |
| REG-PANDALIVE-005 | 看一个多小时后画面停住 | 变体地址会过期 | 30 分钟租期，到期重新取流 | §6.2 |
| REG-PANDALIVE-004 | 开播时间差 9 小时 | `startTime` 是韩国时间且不带时区 | 按 UTC+9 换算 | §2.3 |

---

## 11. 样本清单

2026-09-27 录制（规则 tools/live_cli/lib/src/fixture/rules/pandalive.dart）。旧应用不能再运行（ADR 0016），没有 `expected.json`；v4 测试 packages/live_core/test/sites/pandalive_test.dart 直接对照样本。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | `live/index` 人气 | `S01-index-hot`（第一页 30 条）、`S01-index-hot-last`（offset 120，最后一页） |
| S02 | `live/index` 新人主播 | `S02-index-newbj` |
| S03 | 搜索 | `S03-search-live`（直播，关键词 데이지）、`S03-search-bj`（主播，含未开播） |
| S04 | `member/bj` | `S04-member-live`、`S04-member-offline`（`media: null`）、`S04-member-notfound`（400） |
| S05 | `live/play` | `S05-play-live`、`S05-play-castend`（400）、`S05-play-needlogin`（400 `needAdult`） |
| S06 | IVS 主列表 | `S06-master`（1080p 原画、720p、480p、360p、160p） |
| S07 | 弹幕帧 | `fixtures/pandalive/danmaku/S07-live`（`live_cli danmaku pandalive https://www.pandalive.co.kr/play/daisy00 --seconds 150 --record`：36 帧，`live/play`、连接、订阅、18 条聊天、心跳） |

**缺**：密码房（没找到）、粉丝专属房的 `needLogin` 样本（实测见过，录制时已变化）、送心和特别心的帧（录制时没有出现，单元测试按实测的结构构造）。

**需要脱敏的字段**
- 每个响应的 `userIp`（观众地址）。
- `live/play`：`token`（聊天令牌）、`PlayList.*.url` 的 `token` 查询参数（IVS 播放令牌）、`PlayList.whip[].token`、`chatServer.token`、`roomInfo`、`loginInfo.sessKey`、`ispInfo`（观众网络：国家、ISP、组织）、`fanList[]`（观众：id、数字号、昵称、头像）。
- 主列表：会话数据 `USER-IP`、`USER-COUNTRY`、`SERVING-ID`、`VIDEO-SESSION-ID`、`C`/`E`，变体路径里的会话令牌。
- 弹幕帧：`live/play` 响应只保留 `result`、`message`、`channel`、`token`（替换）、`media.userId/userIdx/isLive`；连接命令的 `token`；连接回复的 `client` 和个人频道名；聊天只保留 `type`、`message`、`emoticon`、`filtered`、`created_at`，替换 `id`、`idx`、`nk`，丢掉 `ip`（观众地址的哈希）、设备、等级、语言；送心保留 `coin`，替换 `nick`、`id`、`idx`；其它推送只保留 `type` 和时间。
- 主播的 id、数字号、昵称、标题、图片是公开信息，保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 变体地址的准确有效期（34～87 分钟之间） | 每 5 分钟轮询同一变体 |
| 2 | 密码房的 `errorData.code` 和带密码的 `live/play` | 找密码房 |
| 3 | 聊天令牌过期时服务端的断开方式（关闭码、`reconnect`） | 连满 30 分钟 |
| 4 | `category` 代码的名称 | 网页分类筛选（目前没有） |
