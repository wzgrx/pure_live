# 平台规格：kilakila（克拉克拉，红人说 / 红豆 Live）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`kilakila`（legacy/lib/core/sites.dart:58），显示名“克拉克拉”（legacy/assets/translations/zh.json `site_kilakila`）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/kilakila/`（A = kilakila_api.dart，L = kilakila_link.dart，S = kilakila_site.dart），其它旧代码写全路径（相对 `legacy/`）。样本编号见 §11。
- 状态：**保留**。2026-09-27 实测：接口、媒体、弹幕都能在中国大陆直连匿名使用；有公开目录（热门、萌星两个时间线）。不满足 ADR 0003 的下线条件。
- 能力：目录（两个时间线；推荐 = 热门）、搜索（主播，网页结果页；uid 精确查找）、详情、取流（FLV 和 HLS，一个画质）、链接（含加密的分享链接）、弹幕（Socket.IO 游客房间）。
- 不提供：登录；付费房（`goldPrice > 0`）的播放；回放（结束的直播有 `videoUrl` 录像，v4 不做）。
- 这是语音直播平台：视频轨是 320×240 左右的 H.264 背景画面（§6.4）。

---

## 1. 房间身份与链接

**规范身份**：**主播 uid**（13 位左右的数字），不是直播 id。每场直播有一个新的 `roomIdStr`（19 位），只在当场有效；关注、历史都按 uid 存（S:179, 202-223）。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯数字 | `3674092253247` | 当作 uid | S:295-297 |
| 主播主页 | `https://live.kilakila.cn/zhubo/<uid>` | uid | L:49-51 |
| 主播主页（红人说） | `https://live.hongrenshuo.com.cn/index/roomuser/uid/<uid 或加密串>` | uid | L:40, 51；A:302-322 |
| 直播间 | `https://live.kilakila.cn/room/<直播 id 或加密串>`、`https://www.hongdoufm.com/room/…` | 直播 id → 查 `getRoomInfo` 得 uid | L:39-63；A:277-300 |
| 详情页 | `https://live.kilakila.cn/PcLive/index/detail?id=<直播 id>` 或 `?_specific_parameter=<加密串>` | 同上 | L:53, 64-72 |
| 分享文本 | 链接前后夹有文字 | 抽出第一个 URL | — |

- 2026-09-27：打开 `/room/<直播 id>` 会 302 到 `PcLive/index/detail?_specific_parameter=<加密串>`（S06-room-redirect），所以用户复制到的多半是加密链接，必须能解密。
- `/room/<数字>` 带 `id` 或 `_specific_parameter` 查询参数时不认；`/zhubo/` 只接受数字（L:58-63）。

**加密链接**（官网脚本 `download.hongrenshuo.com.cn/h5/assets/oss/uxin-security-url-crypto-v2.min.js`，SHA-256 `2a031560…4607e2`；L:18-23）：

- 载荷是“URL 安全”的 base64（`-` → `+`、`_` → `/`），AES-128-CBC、PKCS#7。IV 是 ASCII `93x0ue23c2c9h8km`；密钥先试 `7cdyGRc6Sa93ilPt`，再试 `c98be79a4347bc97`（脚本里的公开常量，不是账号凭据）。
- 明文两种形式：路径链接 `<id>?k=v&…&sign=<md5>`（值是 URL 编码）；详情页 `id=<id>&…&sign=<md5>`（值原样）。
- 签名 `sign = md5("pR@Wv%Wju@Pl&bKc$GyUrPeO" + base + canonical)`：
  - 路径链接只有 id 和 sign 时：`base` = `<scheme>://<host><路径前缀>`，`canonical` = id；
  - 其它情况：`canonical` = 除 `sign`（路径链接还除 `id`）外的参数按名字排序后的 `k=v&…`；路径链接的 `base` 再接上 `<id>?`，详情页的 `base` = 原始路径加 `?`。
  - 签名绑定主机：同一个载荷换到另一个主机就不通过（S09 的 wrong-signature 用例）。
- 签名不对、解不开、参数不合法都视为“不是本平台链接”。
- v4 自己实现 AES-128 解密（live_core `Aes128Cbc`，用 SP 800-38A 向量和 S09 的全部分享向量验证），不引入依赖。

**外部打开**：`https://live.hongrenshuo.com.cn/index/roomuser/uid/<uid>`（S:200）。

---

## 2. 目录

### 2.1 分类

- 平台没有分区接口。旧版给一个分类、两个“时间线”：`0` 热门、`107` 新人（S:272-289）。响应里的 `linkTagName` 是“萌星”，v4 用这个名字。
- v4：一个 `Category`（id `timeline`，名称“直播”），两个 `Area`（`0` 热门、`107` 萌星）。

### 2.2 时间线

- 请求：GET `https://live.kilakila.cn/pcLive/timeline?tag=0&type=<0|107>&genderType=0&pageNo=<页>&pageSize=10`（A:409-428）。
- 响应套了两层：`{code:200, data:{body:{h:{code, success}, b:{pageNo, pageSize, data[], isLastPage}}}}`（S01-timeline-hot-p1）。
- 条目：`dataType == 8`（热门）或 `2`（萌星）的行，`roomResq` 是直播、`userResp` 是主播（A:393-407）。其它 `dataType` 跳过。
- 字段：

| 字段 | 含义 |
|---|---|
| `roomResq.uid` | 主播 uid（房间身份） |
| `roomResq.roomIdStr` | 本场直播 id |
| `roomResq.title` | 标题 |
| `roomResq.status` | 4 直播中（列表里只有 4） |
| `roomResq.backPic`，缺失时 `defaultBackgroundPicUrl` | 封面（A:377-384） |
| `roomResq.watchNumber` | **累计收听人数**：2026-09-27 对 6 个直播每分钟取一次，连续 4 次全部只增不减（1099→1106→1112→1117 等）。网页在房间里显示为“收听 N”。旧版语义未定，不显示（S:211-216）；v4 标为累计 |
| `roomResq.goldPrice` | 付费房价格；非 0 不能匿名播放（§9） |
| `roomResq.pushFlow` | **主播的 RTMP 推流地址和推流密钥**，不用，样本里整值脱敏 |
| `userResp.nickname`、`headPortraitUrl` | 主播名、头像 |

- 结束：`isLastPage == true`，或本页为空。**时间线会循环**：热门在 2026-09-27 走到第 55 页才 `isLastPage`，中间多页重复；萌星到第 300 页仍有数据。v4 另设上限 100 页。同一页内按 uid 去重。
- `pcLive/recommend` 成功时经常没有 `b`（S02-recommend；A:430-435），v4 不用，推荐直接用热门时间线。

---

## 3. 搜索

- 输入是 uid 或本平台链接时，精确查找（§1、§4），只有一页（S:295-335）。其它 `http(s)://` 输入不搜索。
- 其它关键词：网页搜索结果页 GET `https://live.kilakila.cn/aboutus/serach/kw/<kw>`，第 n 页（n > 1）加 `/p/<n>`（A:190-234；路径里的 `serach` 就是这么拼的）。
- 解析 HTML：每个 `<a href="/zhubo/<uid>">` 块里取 `.anchor-name` 文本和 `.anchorHeaderImg img` 的地址（S03-search：10 个主播）。
- 结果页没有开播状态和直播标题。v4 对每个主播再请求一次主页（§4）拿状态和当前标题，房间不存在的跳过。旧版不查，状态一律“未知”（S:225-237），v4 没有“未知”状态。
- 下一页：页面里有指向 `/p/<n+1>` 的链接就还有下一页（S03-search 有 `/p/2`；S03-search-p2 有 `/p/3`）；没有结果即结束（S03-search-empty）。

---

## 4. 房间详情

- 请求：GET `https://live.hongrenshuo.com.cn/Tg/personalH5?uid=<uid>`（A:453-489）。
- `code == 1013`（`用户不存在`）→ NotFound（S04-owner-notfound）；`code != 200` → ApiChanged。
- `data.userResp`：`nickname`、`headPortraitUrl`、`introduction`（没有 uid 字段）。
- `data.liveCard`：
  - 只有 `roomSourceType`、`recommendSource` 两个路由字段：**当前没有直播 → 未开播**（S04-owner-offline；10 个搜索结果主播都是这样）。旧版把它当“未知”（A:471-476），v4 按平台明确的“无当前直播”处理为未开播。
  - 有 `roomIdStr`：当前直播。`uid` 必须等于请求的 uid，否则 ApiChanged（A:478-480）。字段：`title`、`status`、`backPic`、`watchNumber`（累计）、`onlineNumber`（**在线人数**，193，只有这个接口有）、`actualTime`（实际开播时刻，毫秒）、`liveStartTime`、`goldPrice`（S04-owner-live）。
- 直播状态（`status`）：4 直播中；10 已结束（有录像，`liveStartStr` 为“回放”，S05-room-replay）→ replay；其它取值 ApiChanged（ADR 0010 修订）[待确认其它取值]。
- 开播时间：`actualTime`，没有时 `liveStartTime`。
- 弹幕参数：`roomId` = 本场 `roomIdStr`。

---

## 5. 画质与线路

- 取流用 GET `https://live.kilakila.cn/LiveRoom/getRoomInfo?roomId=<roomIdStr>`（A:437-451），`{h, b}` 信封：`h.code == 200 && h.success`；`h.code == 5201`（`直播间不存在`）→ NotFound（S05-room-notfound）；旧版把 5966 当“历史回放”（A:239），录制时没遇到。
- `b`：`flvPlayUrl`、`hlsPlayUrl`、`rtmpPlayUrl`（不用）、`status`、`goldPrice`、`uid`。
- 一个画质“原画”，两条线路：`flv`（`https://pull.live.hongrenshuo.com.cn/hrs/<roomIdStr>.flv?auth_key=…`）、`hls`（同主机 `.m3u8`）。地址不符合这个形状的丢弃（A:332-353）。
- 取流时重新请求主页和 `getRoomInfo`：`getRoomInfo.uid` 必须等于房间 uid。

---

## 6. 取流

### 6.1 流程

主页 → 当前直播 id → `getRoomInfo`。当前没有直播 → StreamUnavailable；`status != 4` → StreamUnavailable；`goldPrice != 0` → NeedsLogin（A:369-370）。

### 6.2 租期

- 阿里云式 `auth_key=<到期 Unix 秒>-0-0-<md5>`，签发后 **30 天**到期（S05-room-live：录制于 2026-09-27，到期 2026-10-27）。
- v4：`expiresAt` = `auth_key` 第一段；`refreshAt` = 到期前 min(10 分钟, 寿命的 1/4)；FLV `cutsConnection = false`，HLS `true`（分片地址各带自己的 `auth_key`，列表过期后刷新会失败）[待确认]。

### 6.3 请求头

- API 和媒体：`Referer: https://live.kilakila.cn/`、UA（A:92；legacy/lib/player/core/playback_header_resolver.dart 中 kilakila 分支）。

### 6.4 媒体实况（2026-09-27）

- FLV：`videocodecid 7`（AVC，320×240，15 fps）、`audiocodecid 10`（AAC）；没有 codec 12（HEVC），不需要旧版中继的 HEVC 改写。
- HLS：`#EXT-X-VERSION:3`，3 秒 TS 分片，分片地址带自己的 `auth_key`。
- `live_cli probe kilakila <加密分享链接>`：解析 → 详情（在线 194、累计 1162）→ 取流 → 读到 FLV 文件头，通过（2026-09-27，直连）。

---

## 7. 弹幕

旧版没有克拉克拉弹幕（S:197-198）。以下来自官网直播页脚本（`/static/pclive/js/chunk-82396490.*.js`）和 2026-09-27 实测。

### 7.1 连接

- 游客房间是 **Socket.IO 2（Engine.IO 3）**：`wss://wim.hongrenshuo.com.cn/socket.io/?roomId=<roomIdStr>&appId=111&clientType=1&EIO=3&transport=websocket`。网页脚本里写的是 `wss://wim.hongrenshuo.com.cn/live_chat_room_guest?roomId=…&appId=111&clientType=1`，这是 Socket.IO 的“地址 + 命名空间”写法；直接当 WebSocket 地址连会返回 HTTP 400（实测）。`appId=666` 是日文版 pika 的配置。
- 握手请求头：`Origin: https://live.kilakila.cn`、UA。不需要 Cookie。
- 服务端先发 `0{"sid":…,"pingInterval":25000,"pingTimeout":60000}`、`40`、`41`。
- 加入：客户端发**文本帧** `40/live_chat_room_guest?roomId=<roomIdStr>&appId=111&clientType=1,`。服务端回 `42/live_chat_room_guest,["connect_error","{\"code\":0,\"message\":\"join success\"}"]`（事件名是 `connect_error`，但 `code 0` 表示成功）和 `40/live_chat_room_guest`，两者任一即加入；`code != 0` 视为被拒。
- **必须是文本帧**：Engine.IO 把二进制帧当二进制消息，不会当成 ping 或命名空间连接。live_danmaku 的 `TextFrame` 让连接发文本帧。

### 7.2 心跳

- 客户端每 25 s 发文本 `2`（Engine.IO ping），服务端回 `3`。超过 `pingTimeout`（60 s）没有 ping 服务端会断开。

### 7.3 消息

- `42/live_chat_room_guest,["text_message","<JSON>"]`；JSON 的 `body.response`：`room_id`、`mid`（消息 id）、`created_at`（毫秒）、`sender_info`、`content`（又一层 JSON 字符串，短字段名）。

| `content.t` | 含义 | 处理 |
|---|---|---|
| 200 | 聊天：`c` 文本、`u` uid、`n` 昵称、`l` 等级、`a` 头像 | 聊天，id `kilakila:<mid>` |
| 220 | 礼物：`c.name`、`c.id`、`c.doubleCount`（连击数）、`c.price`（单位不明，红豆？）、`n`、`u` | 礼物，不填元 |
| 101、603 | 进场 | 忽略 |
| 211 | 点赞（“点亮”） | 忽略 |
| 103 | 直播结束 | 忽略（由详情刷新） |
| 其它（635 榜单、636、637、661、662、663 …） | 活动和榜单，`c` 是 URL 编码的 JSON | 忽略 |

- 丢弃 `room_id` 与当前直播不同的消息。
- 没有在线人数消息；在线人数只在详情的 `onlineNumber`。

### 7.4 重连

- 共用 SocketConnector 的规则。每次开播直播 id 都变：主播重新开播后要重新取详情再开弹幕（同 live_danmaku README 里抖音的已知缺口）。

---

## 8. 登录与 Cookie

- 不支持登录。接口会下发 `HDSESSION`、`HRSSESSION` 会话 Cookie，匿名请求不需要带回。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | A:167-175 | NetworkFailure |
| HTTP 429 / 401、403 / 404 | A:169-171 | RateLimited / RiskControl / NotFound |
| 主页 `code == 1013` | S04-owner-notfound；A:459-461 | NotFound |
| `getRoomInfo` `h.code == 5201` | S05-room-notfound | NotFound |
| 信封 `code != 200` 或 `success != true`（其它） | A:147-153, 236-241 | ApiChanged |
| 直播 `status` 不是 4、10 | A:370 | ApiChanged |
| 当前没有直播，或直播已结束时取流 | §6.1 | StreamUnavailable |
| `goldPrice != 0` 的付费房 | A:369 | NeedsLogin |
| 两个拉流地址都不符合形状 | A:375 | StreamUnavailable |
| 加密链接签名不对 | §1 | 不是本平台链接（resolve 返回 null） |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-KILAKILA-001 | 关注的房间下次打不开 | 按一场直播的 id 保存 | 身份是主播 uid，每次重新取当前直播 | S:179；A:491-498 |
| REG-KILAKILA-002 | 复制的直播间链接认不出 | 分享链接是 AES 加密的 `_specific_parameter` | 按官网脚本解密并校验签名 | L:25-122；S06-room-redirect |
| REG-KILAKILA-003 | 在线人数不可信 | `watchNumber` 是累计收听 | 累计标为累计，在线用主页的 `onlineNumber` | §2.2 实测 |
| REG-KILAKILA-004 | 样本泄露主播推流密钥 | 每个房间对象都带 `pushFlow` | 不读，样本整值脱敏 | S01、S04、S05 |
| REG-KILAKILA-005 | 无限翻页 | 时间线循环、很晚才 `isLastPage` | 空页、`isLastPage` 或 100 页结束 | §2.2 |

---

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/kilakila.dart）。旧应用不能再运行（ADR 0016），没有 `expected.json`；v4 测试 packages/live_core/test/sites/kilakila_test.dart、kilakila_link_test.dart 直接对照样本。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | `pcLive/timeline` | `S01-timeline-hot-p1`、`-hot-p2`、`-hot-last`（第 55 页，`isLastPage`）、`-new-p1`（萌星，`dataType 2`） |
| S02 | `pcLive/recommend` | `S02-recommend`（没有 `b`） |
| S03 | 网页搜索 | `S03-search`、`S03-search-p2`（关键词“小”）、`S03-search-empty` |
| S04 | `Tg/personalH5` | `S04-owner-live`、`S04-owner-offline`、`S04-owner-notfound`（1013） |
| S05 | `LiveRoom/getRoomInfo` | `S05-room-live`、`S05-room-replay`（`status 10`）、`S05-room-notfound`（5201） |
| S06 | `/room/<id>` | `S06-room-redirect`（302 到加密详情页） |
| S07 | 弹幕帧 | `fixtures/kilakila/danmaku/S07-live`（`live_cli danmaku kilakila <uid> --record`，40 s，59 帧：加入、聊天、礼物、ping/pong） |
| S09 | 分享链接向量 | `S09-share-vectors/vectors.json`：旧版测试集里的 28 个 .NET 独立向量（两把密钥、两个主机、主播路径、错签名、多余参数、畸形明文）加 2026-09-27 网站实际下发的一个加密链接 |

**需要脱敏的字段**
- `pushFlow`（主播推流地址和密钥）：整值替换。
- 拉流地址 `auth_key` 的 md5 段（保留到期时间段）。
- 会话 Cookie `HDSESSION`、`HRSSESSION`（Set-Cookie）。
- 弹幕：聊天、礼物消息发送者的 `u`、`n`、`a`、`sender_info`；丢掉 `ui`、`uc` 装饰字段；其它类型的消息只保留 `t`。
- 主播和直播的公开信息（uid、直播 id、名字、头像、标题、简介、靓号）保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 直播 `status` 除 4、10 外的取值（预约、暂停？） | 观察更多主播主页 |
| 2 | 礼物 `price` 的单位 | 对照网页礼物面板 |
| 3 | FLV 在 `auth_key` 到期后是否断开（30 天，实际不会遇到） | — |
| 4 | 时间线循环的规律，能否按 uid 跨页去重 | 连续翻页对比 |
| 5 | 付费房的匿名表现（`goldPrice` 非 0 时拉流地址是否仍下发） | 找付费房 |
