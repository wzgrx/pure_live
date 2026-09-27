# 平台规格：AcFun（acfun）

- 平台 id：`acfun`（legacy/lib/core/sites.dart:53）；显示名“AcFun”（旧版“AcFun 直播”，legacy/lib/core/site/acfun/acfun_site.dart:32）。
- 阶段：第二批（docs/adr/0003-platform-batches.md），第 7 阶段前段迁移。
- **去留：保留。** 2026-09-27/28 实测不满足 ADR 0003 任何一条下线标准：匿名取流成功（`live_cli probe acfun 40740702` 读到 FLV），不需要登录，有公开目录。平台体量很小：全站在播 19 个（2026-09-28 01:44 北京时间）、15 个（02:20），最热的房间在线约 100 人；第 7 阶段的每日探针继续观察。
- 能力：一级分类（四个分区）、推荐（全站在播）、主播搜索（含未开播）、详情、取流（HTTP-FLV，按 CDN 分线路，签名 30 天有效，租期不断开已建立的连接）、弹幕（**v4 新增**：旧版没有接，legacy/lib/core/site/acfun/acfun_site.dart:14-15, 34）。
- 不提供：登录（§8）。
- 证据口径：旧代码写成 `legacy/…:行号`；“实测”指 2026-09-27/28 编写本规格时在本机发出的匿名请求（WSL，出口 IP 在美国，直连）；能用样本核对的结论写样本编号（`fixtures/acfun/`，见 §11）；弹幕协议来自网页直播页的脚本（`live.acfun.cn` 的 `4.*.js`，2026-09-27 下载），再由实测连接核对。
- 路径简写：`site` = legacy/lib/core/site/acfun/acfun_site.dart，`api` = legacy/lib/core/site/acfun/acfun_api.dart，`search` = legacy/lib/core/site/acfun/acfun_search.dart，`dir` = legacy/lib/core/site/acfun/acfun_directory.dart，`reo` = legacy/lib/modules/live_play/services/room_external_opener.dart，`wsp` = legacy/lib/modules/search/web_search_room_parser.dart，`phr` = legacy/lib/player/core/playback_header_resolver.dart。

---

## 1. 房间身份与链接

**规范身份**：主播的用户 id `authorId`，十进制正整数（1～20 位），以字符串保存（api:153-159）。

- 一次直播有 `liveId`（如 `29RchpoKMpA`），每次开播都变，不作身份，放进弹幕参数（§4）。

**可接受的输入**（全部不联网即可解析）

| 形式 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯数字 | `40740702` | 直接作为 authorId | — |
| 直播页 | `https://live.acfun.cn/live/40740702` | 取 `live/` 后一段 | wsp:165-166 |
| 手机直播页 | `https://m.acfun.cn/live/detail/40740702` | 取 `live/detail/` 后一段 | 实测 |
| 个人主页 | `https://www.acfun.cn/u/40740702` | 取 `u/` 后一段（旧版不认） | 实测 |
| 分享文本 | 链接前后夹中文 | 先抽出 URL 再按上表处理 | — |

**外部打开**：`https://live.acfun.cn/live/<authorId>`（reo:191-192）。

---

## 2. 目录

### 2.1 分类（一级）

- 分区来自房间列表接口的 `channelFilters`，旧版也是这样（site:61-83；api:187-209）。只要分区时请求 `count=1`，不影响列表分页（site:63-64；S01-list-filters）。
- `channelFilters.liveChannelDisplayFilters[].displayFilters[]`：`filterType`、`filterId`、`name`、`cover`。`filterId == 0`（全部）不作分区。
- 实测四个分区，全部是 `filterType == 1`：虚拟偶像（4）、游戏（1）、娱乐（3）、其他（2），按服务端顺序（S01-list-all）。
- v4 把同一 `filterType` 的分区放进一个分类（id 为 `filterType`，名为“直播分类”）；平台只有这一层。

### 2.2 分区房间

- GET `https://live.acfun.cn/api/channel/list?count=30&pcursor=<游标>&filters=[{"filterType":1,"filterId":1}]`（api:161-168；site:97-106）。
- 响应 `channelListData`：`result`（0 为成功，否则 ApiChanged）、`pcursor`（下一页游标）、`liveList[]`。
- **分页**：`pcursor` 是不透明字符串，原样作为下一页的 `PageCursor`；`no_more` 或空串即最后一页。旧版把应用的页号映射到游标，还要处理游标过期（dir:1-67）；v4 的游标分页（ADR 0010）直接携带游标，不需要这层。
- 游戏分区 8 个房间，一页结束（S02-list-game）。

**卡片字段**（site:36-58）

| 字段 | 含义 |
|---|---|
| `authorId` | 规范 authorId |
| `title` | 标题 |
| `user.name`、`user.headUrl` | 主播名、头像 |
| `coverUrls[0]` | 封面 |
| `type.name` | 分区名 |
| `onlineCount` | **在线人数**（旧版同样当在线显示，site:51-53） |
| `createTime` | 开播时间，毫秒 |
| `liveId` | 有值即在播；列表里全部在播 |

### 2.3 推荐

- 同 §2.2，不带 `filters`：全站在播房间，按热度排。实测 19 个房间一页放完，`pcursor == "no_more"`（S01-list-all）。

---

## 3. 搜索

- GET `https://www.acfun.cn/search?keyword=<kw>&type=user&pCursor=<页>&quickViewId=up-list&reqID=1&ajaxpipe=1`，`Referer: https://www.acfun.cn/search`（search:46-58）。没有 User-Agent 时 403（实测）。
- 响应是 BigPipe：一段 JSON（`{"html": "…", …}`），后面接 `/*<!-- fetch-stream -->*/`。只解析 `html` 里的片段，不执行任何脚本（search:28-29）。
- 片段里每个主播是一个 `<div class="search-up" data-up-exposure-log='{…}'>`：
  - `data-up-exposure-log`（HTML 实体转义的 JSON）：`up_id`（authorId）、`is_on_live`（有值即在播）；
  - `up__main__name` 下的 `<a href="/u/<id>">名字</a>`；`up__avatar` 的 `src`（头像）；`up__main__intro`（简介，v4 作标题）。
- 总数 `data-total`；每页 30 个。
- **结束**：本页为空，或 `页号 × 30 ≥ data-total`。旧版记录过“一页只有 29 条但 `data-total` 仍是 100”（search:111-113），所以不按条数判断。
- 实测“游戏”：共 100 条，第 1 页 30 条（S04-search-p1），第 4 页是最后一页（S04-search-p4）。
- 没有意义的关键词也会模糊匹配出主播（`zzqqxxkkyyww` 得 8 个，S04-search-fuzzy）；真正没有结果时片段里是 `empty-page`（S04-search-none）。
- 搜索结果没有封面和人数。空关键词不请求。

---

## 4. 房间详情

- GET `https://live.acfun.cn/api/live/info?authorId=<id>`（api:211-230）。
- **不存在的主播**：`user.id` 为 `"0"`、`user` 为空或没有名字 → NotFound（S05-info-missing，authorId 99999999999）。
- `result != 0` → ApiChanged；回显的 `user.id` 与请求不一致 → ApiChanged（api:223）。
- **状态**：有 `liveId` 为直播中（S05-info-live），没有为未开播（S05-info-offline，authorId 1 “admin”）。旧版要求 `liveId` 与 `streamName` 同时有或同时无（api:226-229），v4 只看 `liveId`。
- 字段同 §2.2 的卡片；另有 `user.signature`（签名，作公告，解 HTML 实体）。
- **弹幕参数**：`danmakuKeys = {author, liveId}`（未开播时只有 `author`）。
- **原站链接**：`https://live.acfun.cn/live/<authorId>`。

---

## 5. 画质与线路

来源是 `startPlay` 的 `videoPlayRes`（§6.2），它是一个 JSON **字符串**，要再解析一次（api:284-288, 290-340）。

- `liveAdaptiveManifest[]`：每项是一个 CDN 的自适应清单；`adaptationSet.representation[]` 是各画质：`id`、`url`、`bitrate`、`qualityType`、`name`、`level`、`hidden`。
- **画质**：以 `qualityType`（缺时 `id`）为身份，`name` 作标签（“蓝光 8M”“蓝光 4M”“超清”“高清”），按 `level` 从高到低；`hidden == true` 的不列（api:299）。实测 BLUE_RAY、SUPER、HIGH、STANDARD（S06-startplay-live）。
- `level` 和 `bitrate` 是两种刻度，不能混排（api:318-323）；v4 只在没有 `level` 时用 `bitrate`。
- **线路**：同一画质在每个清单里各有一个地址；线路身份是地址的主机（CDN），同一主机只留第一条。实测只有一个清单（`ali-acfun-adaptive.pull.etoote.com`）。
- 选定画质在返回的清单里不存在时报 StreamUnavailable。

---

## 6. 取流

### 6.1 访客会话

- POST `https://id.app.acfun.cn/rest/app/visitor/login`，表单 `sid=acfun.api.visitor`，Cookie `_did=web_<16 个字母或数字>`（api:243-260）。
- 响应 `result == 0`：`userId`（访客 id）、`acfun.api.visitor_st`（服务令牌）、`acSecurity`（base64 的 16 字节密钥，弹幕用，§7）（S06-visitor）。`result != 0` → RiskControl；字段不全 → ApiChanged。
- 会话在内存里复用 5 分钟（api:257），并发调用共用一次登录。

### 6.2 startPlay

- POST `https://api.kuaishouzt.com/rest/zt/live/web/startPlay?subBiz=mainApp&kpn=ACFUN_APP&kpf=PC_WEB&userId=<访客>&did=<_did>&acfun.api.visitor_st=<令牌>`，表单 `authorId=<id>&pullStreamType=FLV`（api:262-277）。
- `result == 1`：`data.liveId`、`data.availableTickets`（弹幕票据）、`data.enterRoomAttach`、`data.videoPlayRes`（§5）（S06-startplay-live）。
- `result == 129004`（`直播已关播`）→ StreamUnavailable（S06-startplay-offline）。
- 其它 `result` → RiskControl；**换一个新访客会话重试一次**（旧版在失败时丢掉会话，api:278-283，下一次才用新会话）。

### 6.3 租期

- FLV 地址带 `auth_key=<过期时刻>-<随机>-0-<签名>`，第一段是 Unix 秒。实测签发后 30 天过期。
- `Lease(refreshAt = 过期 − min(有效期/4, 10 分钟), expiresAt = 过期, cutsConnection = false)`：已建立的连接没有被切断的证据（30 天等不到，[待确认]），租期只用于新连接。
- 地址里没有 `auth_key` 或已过期时不设租期。

### 6.4 格式与请求头

- 路径以 `.flv` 结尾为 FLV，`.m3u8` 为 HLS（实测只见到 FLV）。
- 播放请求头：`User-Agent`（桌面 Chrome）和 `Referer: https://live.acfun.cn/`（api:81-83；phr:168）。

---

## 7. 弹幕

旧版没有接 AcFun 弹幕（`getDanmaku() => EmptyDanmaku()`，site:34；site:14-15 “Remote chat is not integrated”）。v4 按网页直播页的实现接入；协议是快手中台（`kuaishou.zt.live.interactive`）的长连接，帧加密。

### 7.1 开始前的 HTTP 请求

1. 访客会话（§6.1），每次开始都新建（新的 `_did`）。
2. `startPlay`（§6.2）：取 `liveId`、`availableTickets`、`enterRoomAttach`。`129004` → 终态 `noRoom`（房间没在播就没有票据）。其它失败换会话重试一次，仍失败为终态 `credentials`。
3. 礼物表：POST `https://api.kuaishouzt.com/rest/zt/live/web/gift/list?<与 startPlay 相同的查询参数>`，表单 `visitorId=<访客>&liveId=<liveId>`。`data.giftList[]`：`giftId`、`giftName`、`webpPicList[0].url`/`pngPicList[0].url`（实测 48 种，1 是“香蕉”）。失败不影响连接，只是礼物没有名字就不显示。

### 7.2 连接与帧

- 地址 `wss://link.xiatou.com/`；握手带 `User-Agent` 和 `Origin: https://live.acfun.cn`。
- **帧**：`[u16 0xABCD][u16 1][u32 头长度][u32 负载长度]`（大端），接 `PacketHeader`（protobuf）和负载。三段长度之和必须等于帧长。
- **加密**：负载 = 16 字节随机 IV + AES-128-CBC（PKCS#7）密文。
  - 模式 1（服务令牌）：密钥是 base64 解码后的 `acSecurity`；头里带 `tokenInfo {1: 1, 2: 令牌的字节}`。只用于注册和它的应答。
  - 模式 2（会话密钥）：密钥是注册应答的 `sessKey`。其它所有帧。
  - v4 自带 AES 实现（`packages/live_danmaku/lib/src/codec/aes.dart`，按 FIPS-197 和 SP 800-38A 的向量测试），不增加依赖。
- `PacketHeader`：1 `appId`（13）、2 `uid`（访客 id）、3 `instanceId`（注册应答给出，之前为 0）、7 `decodedPayloadLen`（明文长度）、8 `encryptionMode`、9 `tokenInfo`、10 `seqId`、12 `kpn`（`ACFUN_APP`）。
- 上行 `UpstreamPayload`：1 `command`、2 `seqId`、3 `retryCount`（1）、4 `payloadData`、9 `subBiz`（`mainApp`）。
- 下行 `DownstreamPayload`：1 `command`、2 `seqId`、3 `errorCode`、4 `payloadData`、5 `errorMsg`、7 `subBiz`。
- `seqId` 每个连接从 1 开始，每发一帧加一（推送确认除外，见下）。

### 7.3 流程与心跳

1. 连上后发 `Basic.Register`（模式 1）：`RegisterRequest {1 appInfo {1 "link-sdk", 4 "1.2.1"}, 2 deviceInfo {1 platformType 6（H5）, 3 "h5", 5 _did}, 4 presenceStatus 1, 5 appActiveStatus 1, 8 instanceId 0, 11 ztCommonInfo {1 kpn, 2 kpf "PC_WEB", 4 uid, 5 did}}`。
2. 应答（模式 1）`RegisterResponse {2 sessKey, 3 instanceId}`；`errorCode != 0` → 重新开始（§7.1）。
3. 立即发 `Basic.KeepAlive {1: 1, 2: 1}` 和进房命令 `Global.ZtLiveInteractive.CsCmd`：`ZtLiveCsCmd {1 cmdType "ZtLiveCsEnterRoom", 2 payload ZtLiveCsEnterRoom {1 isAuthor false, 2 reconnectCount, 4 enterRoomAttach, 5 clientLiveSdkVersion "kwai-acfun-live-link"}, 3 ticket（availableTickets[0]）, 4 liveId}`。
4. 应答 `ZtLiveCsCmdAck {1 cmdAckType "ZtLiveCsEnterRoomAck", 2 errorCode, 4 payload {1 heartbeatIntervalMs}}`；`errorCode == 0` 即加入成功，实测心跳间隔 10000 毫秒。
- **房间心跳**：每 `heartbeatIntervalMs` 发 `CsCmd`，`cmdType "ZtLiveCsHeartbeat"`，payload `{1 clientTimestampMs, 2 sequence}`（`sequence` 从 0 起）。应答 `ZtLiveCsHeartbeatAck`。
- **保活**：每 50 秒一次 `Basic.KeepAlive`（网页 `heartBeatInterval: 5e4`）。v4 在心跳应答时检查，距上次满 45 秒（50 秒减半个心跳）就发，间隔仍是 50 秒；只按满 50 秒判断会拖到下一个心跳，变成 60 秒。
- **推送确认**：每个 `Push.*` 都回一帧：同一 `command`、没有 `payloadData`，头里的 `seqId` 用推送自己的，上行 `seqId` 不递增（网页 `sendPushAck`）。
- **错误码**（网页 `handleAck`）：1 直播已结束；2、3、4、7 票据失效（网页换下一张票据）；8 重新开播。v4 对任何非 0 都重新开始：重新请求 §7.1，房间已下播则终态 `noRoom`。
- 实测（S07-live）：发注册到收到进房应答约 80 毫秒；心跳 10 秒；5 分钟里服务端没有断开，所有应答 `errorCode == 0`。

### 7.4 消息

`Push.ZtLiveInteractive.Message` 的负载是 `ZtLiveScMessage {1 messageType, 2 compressionType（1 不压缩，2 GZIP）, 3 payload, 4 liveId, 5 ticket, 6 serverTimestampMs}`。

| messageType | 结构 | v4 |
|---|---|---|
| `ZtLiveScActionSignal` | `{1 repeated item {1 signalType, 2 repeated payload}}` | 见下表 |
| `ZtLiveScStateSignal` | `{1 repeated item {1 signalType, 2 payload}}` | 见下表 |
| `ZtLiveScNotifySignal` | 同上 | 不解码（踢出、房管状态等） |
| `ZtLiveScStatusChanged` | `{1 type}`：1 下播、2 重新开播、3 需要新地址、4 封禁 | 1 → 重新开始 |
| `ZtLiveScTicketInvalid` | 空 | 重新开始 |

| signalType | 字段 | v4 |
|---|---|---|
| `CommonActionSignalComment` | 1 `content`、2 `sendTimeMs`、3 `userInfo {1 userId, 2 nickname, 3 avatar, 5 userIdentity}` | 聊天 |
| `CommonActionSignalGift` | 1 `userInfo`、2 `sendTimeMs`、3 `giftId`、4 `batchSize`、5 `comboCount`… | 礼物，名字和图标查礼物表（§7.1），表里没有的丢弃 |
| `AcfunActionSignalThrowBanana` | 1 `visitor {1 userId, 2 name}`、2 `count`、3 `sendTimeMs` | 礼物“香蕉” |
| `CommonStateSignalDisplayInfo` | 1 `watchingCount`（字符串，可能带“万”）、2 `likeCount`、3 `likeDelta` | 在线人数 |
| `CommonActionSignalLike`、`…UserEnterRoom`、`…UserFollowAuthor`、`…RichText`、`AcfunActionSignalJoinClub` | — | 不显示 |
| `CommonStateSignalTopUsers`、`…RecentComment`（进房时的最近聊天）、`…CurrentRedpackList`、`…ArLiveTreasureBoxState`、`AcfunStateSignalDisplayInfo`（香蕉总数） | — | 不解码 |

- 实测：状态信号约每 0.8 秒一条；`watchingCount` 与 `live/info` 的 `onlineCount` 一致（录制结束时 70～71 对接口的 71），作在线人数。
- 平台聊天很少（凌晨 2 点，在线约 70）：S07-live 5 分钟 784 帧里只有 1 条聊天，另有点赞 15、进房 3、状态信号约 730 项；另一次 75 秒得到 1 条聊天和 2 次“香蕉 x5”（`CommonActionSignalGift`，`giftId` 1）。

---

## 8. 登录与 Cookie

- 看直播、弹幕都不需要登录，全部匿名；旧版也没有 AcFun Cookie 设置。
- 访客会话只在内存里，不保存；`_did` 每次随机。
- 发送弹幕需要登录，不在 v4 范围。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | — | NetworkFailure |
| 非 JSON、缺字段、`result` 不是约定值（列表、详情） | — | ApiChanged |
| `live/info` 的 `user.id == "0"` 或 `user` 为空 | S05-info-missing | NotFound |
| 非数字 authorId | — | NotFound（不发请求） |
| `visitor/login` 的 `result != 0` | — | RiskControl |
| `startPlay` 的 `129004` | S06-startplay-offline | StreamUnavailable |
| `startPlay` 的其它 `result` | — | 换会话重试一次，仍失败 RiskControl |
| 弹幕：房间没在播 | — | 终态 `noRoom` |
| 弹幕：HTTP 开始两次都失败 | — | 终态 `credentials` |
| 弹幕：注册或进房被拒、票据失效、下播 | — | 重新开始（§7.3） |
| 弹幕：帧解不开（密钥不对、长度不符） | — | 丢弃这一帧 |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-ACFUN-001 | AcFun 没有弹幕 | 旧版没有接 | 按网页协议接入（§7） | site:14-15, 34 |
| REG-ACFUN-002 | 搜索翻页提前结束或空转 | 一页可能少于 30 条而总数不变 | 只以空页或页号 × 30 ≥ 总数结束 | search:111-113 |
| REG-ACFUN-003 | 取流偶发失败，下一次才好 | 被拒的访客会话要等下一次请求才换 | 当次换会话重试一次 | api:278-283 |
| REG-ACFUN-004 | 翻页报“分页过期” | 应用页号和不透明游标之间的映射过期 | 游标直接作为 `PageCursor` | dir:21-43 |
| REG-ACFUN-005 | 画质顺序错乱 | `level` 与 `bitrate` 刻度不同 | 按 `level` 排，缺时才用 `bitrate` | api:318-323 |
| REG-ACFUN-006 | 搜索请求 403 | 没有浏览器 User-Agent | 带 UA 和 Referer | 实测 |
| REG-ACFUN-007 | 礼物只有编号 | 推送里只有 `giftId` | 开始时取礼物表 | §7.1；实测 |

---

## 11. 样本清单

2026-09-27/28 直连录制，共 13 个 HTTP 样本（`fixtures/acfun/`，规则 `tools/live_cli/lib/src/fixture/rules/acfun.dart`）和 1 个弹幕样本。期望值写在 `packages/live_core/test/sites/acfun_*_test.dart`、`packages/live_danmaku/test/acfun_test.dart`。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | 推荐、分区 | `S01-list-all`（19 个房间，一页结束）、`S01-list-filters`（`count=1`） |
| S02 | 分区房间 | `S02-list-game`（游戏，8 个） |
| S03 | — | 推荐与 S01 是同一接口，不单独录 |
| S04 | 搜索 | `S04-search-p1`（“游戏”，30 条）、`S04-search-p4`（最后一页）、`S04-search-fuzzy`、`S04-search-none` |
| S05 | 详情 | `S05-info-live`、`S05-info-offline`、`S05-info-missing` |
| S06 | 取流 | `S06-visitor`、`S06-startplay-live`、`S06-startplay-offline` |
| S07 | 弹幕帧 | `danmaku/S07-live`（41254970，5 分钟，784 帧，1 条聊天；开始时的三个 HTTP 请求也记在里面） |
| — | HLS 表示、多个 CDN 清单、`startPlay` 风控码 | **缺** |

**需要脱敏的字段**

- 访客会话：`acfun.api.visitor_st`、`acSecurity`、`userId`（访客 id），查询参数 `userId`、`did`、`acfun.api.visitor_st`；Cookie `_did`（工具统一脱敏）。
- `startPlay`：`availableTickets`、`enterRoomAttach`；FLV 地址的 `auth_key` 只换签名部分，保留开头的过期时刻（租期测试要用）。
- 接口回显的内部服务器名 `host`、`host-name`。
- 弹幕：HTTP 部分同上，`startPlay` 只留 `liveId`、票据和 `enterRoomAttach`（换成假值；地址在 HTTP 样本里）；链路帧用真密钥解开，令牌、票据、`did`、访客 id、会话密钥换成假值后用假密钥重新加密；聊天、礼物发送者的 id 和昵称换成假名，头像等其它字段丢弃；没有解码的信号保留类型、清空内容；接入点地址（`KeepAlive` 应答的 IP 列表）丢弃。
- 主播公开信息（authorId、名字、头像、签名、`liveId`、标题、封面、人数）保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | FLV 签名到期（30 天）时已建立的连接是否被切断 | 长时间挂流，或找到更短期限的地址 |
| 2 | `startPlay` 除 129004 以外的风控码（频率限制、地区） | 高频请求、换网络 |
| 3 | 是否会出现 HLS 表示或多个 CDN 清单 | 白天高峰复测 |
| 4 | 白天的在播规模 | 第 7 阶段每日探针 |
| 5 | `CommonActionSignalGift` 的 `comboCount` 与 `batchSize` 如何合计 | 录到连击礼物后对照网页 |
