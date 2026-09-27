# 平台规格：missevan（猫耳 FM 直播）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`missevan`（legacy/lib/core/sites.dart:56），显示名“猫耳 FM”（legacy/assets/translations/zh.json `site_missevan`）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/missevan/`（A = missevan_api.dart，S = missevan_site.dart），其它旧代码写全路径（相对 `legacy/`）。样本编号见 §11。
- 状态：**保留**。2026-09-27 实测：接口、媒体（B 站 CDN `*.bilivideo.com`）、弹幕都能在中国大陆直连匿名使用；有公开目录。不满足 ADR 0003 的下线条件。
- 能力：目录（分区、标签、团播列表 → 房间，另有全站推荐）、搜索（房间号精确查找 + 关键词，含未开播）、详情、取流（FLV 和 HLS，一个画质）、弹幕（WebSocket，匿名游客会话，Brotli 压缩）。
- 不提供：登录；画质选择（平台只给一路原画）；醒目留言（猫耳的“提问”付费功能没有观察到消息格式，§12）。
- 这是音频直播平台：视频轨通常是 16×16 的 H.264 占位画面，音频 AAC（§6.4）。播放器按实际轨道处理，不要把房间判成“纯音频”（A:338-339）。

---

## 1. 房间身份与链接

**规范身份**：数字房间号 `room_id`（1～18 位，不以 0 开头；A:125-129）。主播 id（`creator_id`）不作为房间身份。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯数字 | `453091860` | 直接作为房间号 | A:125-129 |
| 直播间 | `https://fm.missevan.com/live/453091860`（可带末尾斜杠） | 主机必须是 `fm.missevan.com`，路径恰好是 `live/<数字>` | A:131-147 |
| 分享文本 | 链接前后夹有文字 | 抽出第一个 URL 再按上一行处理 | legacy/lib/modules/search/web_search_room_parser.dart:80-83 |

- `www.missevan.com`、`m.missevan.com` 的链接不认（旧版也不认）[待确认 App 分享链接的真实形式]。
- 房间不存在：详情接口返回 HTTP 404、`{"code":500030004,"info":"无法找到该聊天室"}`（S04-notfound；A:111-113）→ NotFound。
- 外部打开：`https://fm.missevan.com/live/<room_id>`。

---

## 2. 目录

接口都在 `https://fm.missevan.com/api/v2/`，响应顶层是 `{code, info}`，`code == 0` 才算成功（A:79-116）。请求头见 §6.3。

### 2.1 分类

- 请求：GET `meta/data`，取 `info.tabs[]`（A:158-183；S01-meta）。
- 每个 tab 有 `type`、`name`、`icon_url`，以及按类型不同的 id：

| `type` | id 字段 | 查询参数 | 例 |
|---|---|---|---|
| `catalog` | `catalog_id` | `catalog_id=<id>` | 配音 105、音乐 104、情感 116、放松 115、古风 122 |
| `tag` | `tag_id` | `tag_id=<id>` | 新星 1 |
| `list` | `list_type` | `type=<list_type>` | 团播 4 |

- **`list` 是新出现的类型**（2026-09-27 的 S01-meta 里有“团播”）。旧版遇到 catalog、tag 以外的类型会让整个分类失败（A:168-170），v4 支持 `list`，其它未知类型跳过。`type=4` 列出的全是 `status.open_mode == 1` 的团播房间（S02-list-team），查询参数由此推断 [待确认：网页端代码里没有找到拼接这个参数的位置]。
- **命名空间**：同一个数字在不同类型下是不同的分区（catalog 104 和 tag 104 不是同一个），所以分区身份是（类型, id）。v4 `Area.id` 是数字 id，`Area.categoryId` 是类型（`catalog`/`tag`/`list`），也就是 live_store 关注分区的 `namespace`（legacy/lib/common/models/live_area.dart:38；spec/modules/store.md §2）。
- v4 `Category`：按类型分组，`catalog` 叫“分区”、`list` 叫“团播”、`tag` 叫“标签”；组的顺序和组内顺序都按 tab 首次出现的顺序。
- `info.catalogs[]` 还有每个分区的子分区（音乐 → 流行、说唱……），旧版不用，v4 暂不展开。

### 2.2 分区房间与推荐

- 请求：GET `chatroom/open/list?p=<页>`，分区加 §2.1 的查询参数；不加任何参数就是推荐（全站）列表（A:188-227）。
- `info.pagination`：`p`、`pagesize`（恒为 20）、`maxpage`、`count`；房间在 `info.Datas[]`（注意大写 D）。
- 一页可能**多于** `pagesize`：S02-list-p1 的 `pagesize` 是 20，`Datas` 有 22 条（推广位）。旧版照单全收，按页号翻页（A:219-221），v4 相同。
- 结束判断：页号达到 `maxpage`（S02-list-last：第 29 页 5 条），或本页为空（S02-list-beyond：第 30 页 `Datas: []`，`count` 已经变了）。
- 列表只保留 `status.open == 1` 的房间，按 `room_id` 去重（A:222-225）。
- 条目字段（A:275-302）：

| 字段 | 含义 |
|---|---|
| `room_id` | 房间号 |
| `name` | 标题 |
| `creator_username`、`creator_iconurl` | 主播名、头像 |
| `cover_url` | 封面；`//` 开头的补 `https:`（A:149-156） |
| `catalog_name` | 分区名 |
| `announcement` | 公告 |
| `status.open` | 1 直播中，0 未开播；其它取值 ApiChanged（A:277-278） |
| `statistics.score` | **热度**（官方界面叫“热度”），不是在线人数（A:294-298）。`statistics.online` 恒为 0，`accumulation` 含义不明，都不用 |

---

## 3. 搜索

- 输入是房间号或直播间链接时，直接查详情，结果只有这一个房间（未开播也返回），只有一页；房间不存在就是空结果（S:53-87）。
- 其它输入：GET `chatroom/search?s=<kw>&p=<页>&page_size=20`（A:231-273；S03-search）。
  - 结果在 `info.data[]`（小写），字段同 §2.2 的子集：`room_id`、`name`、`creator_username`、`creator_iconurl`、`cover_url`、`catalog_name`、`status.open`、`statistics.score`。
  - 未开播的房间也返回（S03-search 里前 5 条直播中，后 15 条未开播）；能力是“直播与未开播”（legacy/lib/modules/search/search_capability.dart:136-140）。
  - 结束：页号达到 `pagination.maxpage`，或本页为空（S03-search-empty：`maxpage: 0`）。
  - 响应里的 `info.ops_request_misc` 是搜索埋点，不用。
- 关键词去掉首尾空白，超过 100 个字符截断；含控制字符时视为无结果（A:237-246）。

---

## 4. 房间详情

- 请求：GET `live/<room_id>`（A:304-342；S04-live）。
- `info.room`：同 §2.2 的字段，另有 `channel`（取流地址，§5）、`statistics.attention_count`（关注数）、`status.open_time`（开播时刻，毫秒）；**没有** `catalog_name`，所以详情里没有分区名。
- `info.creator`：`user_id`（必须等于 `room.creator_id`，否则 ApiChanged；A:310-315）、`username`、`iconurl`、`introduction`。
- `info.websocket[]`：弹幕地址（§7）。
- 直播状态：`room.status.open` 1 直播中、0 未开播；没有回放状态。
- 人数：`statistics.score` 作为热度。
- 简介用 `creator.introduction`，公告用 `room.announcement`。
- 开播时间：直播中时取 `status.open_time`（毫秒）。
- 未开播的房间也带 `channel` 地址（S04-offline，指向很久以前的推流），**不能用**（A:318-321）。

---

## 5. 画质与线路

- 平台只有一路：`channel.flv_pull_url` 和 `channel.hls_pull_url`，查询串里 `qn=10000`（原画）。v4 给一个画质“原画”（id `10000`），两条线路：
  - `flv`：HTTP-FLV（`d1-missevan04.bilivideo.com`）；
  - `hls`：HLS 媒体播放列表（不是主列表，`d1-missevan104.bilivideo.com`，TS 分片，1 秒一片）。
- 顺序：FLV 在前、HLS 在后（接口字段顺序）。旧版把 HLS 排在前面，作为两个“画质”（A:322-336）；v4 改为同一画质下的两条线路，线路身份就是 `flv`/`hls`。
- 两个地址都没有时 ApiChanged（A:337）；只有一个时只给一条线路。
- 地址是 `http://`，改成 `https://`（官方网页也这样做，两个 CDN 都已验证 https；A:360-362）。主机必须以 `.bilivideo.com` 结尾，否则 ApiChanged（A:352）。
- 服务端不降档：确认画质 = 请求画质。

---

## 6. 取流

### 6.1 流程

每次取流都重新请求详情（地址带签名和过期时间，不复用详情里缓存的地址；S:126-136）。未开播 → StreamUnavailable。

### 6.2 租期

- `expires=<Unix 秒>`：约为签发后 2 小时（S04-live：录制于 16:40，`expires` 是 18:40）。
- 旧版：`expires` 是失效时刻，提前 1 分钟刷新（S:138-155）。
- v4：`expiresAt = expires`；`refreshAt` = 到期前 min(10 分钟, 寿命的 1/4)；FLV `cutsConnection = false`（同 B 站 CDN，已建立的连接不因签名到期断开 [待确认，同 bilibili.md §6.5]），HLS `cutsConnection = true`（播放列表要反复请求，到期后刷新列表会失败）。

### 6.3 请求头

- API 和媒体：`Referer: https://fm.missevan.com/`、`Origin: https://fm.missevan.com`、`User-Agent`（A:31；legacy/lib/player/core/playback_header_resolver.dart:156-158）。
- 不需要 Cookie。

### 6.4 媒体实况（2026-09-27）

- FLV：脚本数据 `width 16`、`height 16`、`videocodecid 7`（AVC）、`audiocodecid 10`（AAC）；视频 tag codec id 7，没有 codec 12（HEVC）。旧版中继的 HEVC 改写对猫耳不需要。
- HLS：`#EXT-X-VERSION:3`，TS 分片，分片地址是相对路径，只带 `txspiseq`，不带签名。

---

## 7. 弹幕

旧版没有猫耳弹幕（`getDanmaku()` 返回 EmptyDanmaku，S:37-38；S:14-15 注释“等协议核实后再做”）。以下来自 2026-09-27 实测和网页端脚本（`s1.hdslb.com/bfs/static/maoer-static/assets/fm/js/bundle.*.js`）。

### 7.1 游客会话

- 弹幕服务器要求会话 Cookie `FM_SESS`：不带时握手返回 HTTP 403、`{"code":501010005,"info":"获取连接身份失败"}`；只带 `Origin` 或别的 Cookie 也不行（实测）。
- 游客会话：GET `https://fm.missevan.com/api/user/info`，响应 `Set-Cookie: FM_SESS=<日期>|<随机串>; max-age=259200`（3 天），正文 `{"info":{"user":null,"guest":{"user_id":0},"websocket":["wss://im.missevan.com/ws"]}}`（S05-user-info）。只带 `FM_SESS` 即可，不需要 `FM_SESS.sig`。
- 用户如果配置了猫耳 Cookie（含 `FM_SESS`），优先用用户的 [v4 暂不提供猫耳登录，这条只是预留]。

### 7.2 连接

- 地址：详情 `info.websocket[]`（`wss://im.missevan.com/ws?room_id=<room_id>`）；没有时用这个固定格式。
- 握手请求头：`Cookie: FM_SESS=…`、`Origin: https://fm.missevan.com`、UA。
- 加入：发 `{"action":"join","uuid":<随机 UUID>,"type":"room","room_id":<数字>}`。回 `{"type":"room","event":"join","code":0,…}` 即加入成功；`code != 0` 视为被拒（重新取游客会话）。
- 客户端发文本或二进制帧（内容相同）服务端都接受（实测）。

### 7.3 帧格式

- 服务端的业务消息都是**二进制帧**：第 1 字节是 1 表示 Brotli 压缩，第 2～4 字节是解压后的 UTF-8 字节数（小端 24 位），第 5 字节起是 Brotli 数据；解压后是一个 JSON 对象或 JSON 数组（网页脚本 onMessage）。第 1 字节不是 1 的帧丢弃。
- 心跳回应是文本帧 `❤️`。
- 解压后的长度要和头里的字节数一致，不一致丢弃该帧。
- Brotli 用 `package:brotli`（纯 Dart，MIT）解码；dart:io 只有 zlib/gzip。

### 7.4 心跳

- 客户端每 30 s 发 `❤️`（网页端 `IMHeartbeat = 3e4`），服务端回 `❤️`。

### 7.5 消息

| `type`/`event` | 处理 |
|---|---|
| `message`/`new` | 聊天：`message` 文本，`user.user_id`、`user.username`，`msg_id` 作为消息 id（`missevan:<msg_id>`）；`titles[]` 里 `type == level` 的 `level` 是用户等级，`type == medal` 的 `name`/`level` 是粉丝牌 |
| `message`/`danmaku` | 付费弹幕，按聊天处理 |
| `gift`/`send` | 礼物：`gift.name`、`gift.gift_id`、`gift.num`，送礼人 `user`。`gift.price` 的单位是钻石，换算成元的比例 [待确认]，不填元 |
| `gift`/`cross_send` | 团播里送给**另一个**房间的礼物（`room.room_id` 不是本房间），丢弃 |
| `room`/`statistics` | `statistics.score` 是热度，`statistics.online` 是此刻在房间里的听众数（S06-live：`score 105019`、`online 22`；网页端据此更新热度和在线）。两个都上报。详情接口的 `statistics.online` 恒为 0，只有弹幕里的是真实值 |
| `room`/`join` | 加入回应（§7.2） |
| 其它（`member`、`creator`、`team_live`、`lucky_bag`、`fans_box`、`notify` …） | 忽略 |

- 丢弃 `room_id` 与当前房间不同的 `message`（弹幕串房保护，同 REG-DOUYU-020 的思路）。

### 7.6 重连

- 共用 SocketConnector 的规则（spec/modules/danmaku.md CONN-3）。被拒后重新取游客会话。

---

## 8. 登录与 Cookie

- 不支持登录。游客会话 Cookie 只用于弹幕，由弹幕连接自己获取，不存进 CookieVault。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | A:95 | NetworkFailure |
| HTTP 429 | A:94 | RateLimited |
| HTTP 401/403 | A:92 | RiskControl |
| `code == 500030004`（HTTP 404） | S04-notfound；A:111-113 | NotFound |
| HTTP 404 其它 | A:93 | NotFound |
| `code != 0`（其它） | A:114 | ApiChanged（旧版不把未知错误当作下播，v4 相同） |
| 不是 JSON、缺 `info`、`status.open` 不是 0/1 | A:102-110, 277-278 | ApiChanged |
| 直播中但两个地址都没有，或地址主机不是 `*.bilivideo.com` | A:337, 352 | ApiChanged |
| 未开播时取流 | S:111 | StreamUnavailable |
| 弹幕握手 403（`501010005`） | §7.1 | 弹幕连接报 `credentials`，重新取游客会话 |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-MISSEVAN-001 | 一页多出推广位，翻页算错 | 按 `pagesize` 算偏移 | 按页号翻页，保留全部条目，按 `maxpage` 或空页结束 | A:219-221 |
| REG-MISSEVAN-002 | 热度被当成在线人数 | `score` 是热度，`online` 恒为 0 | `score` 标为热度 | A:294-298 |
| REG-MISSEVAN-003 | 同一个数字的分区和标签混在一起 | 分区身份只用了 id | 身份是（类型, id） | A:171-172；live_area.dart:38 |
| REG-MISSEVAN-004 | 未开播的房间拿到能“播放”的旧地址 | 详情对未开播房间也返回 `channel` | 未开播不取流 | A:318-321 |
| REG-MISSEVAN-005 | 分类页整页失败 | 平台新增 `list` 类型的 tab（团播），旧版遇到未知类型抛错 | 支持 `list`，其它未知类型跳过 | S01-meta；A:168-170 |

---

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/missevan.dart）。旧应用不能再运行（ADR 0016），没有 `expected.json`；v4 测试 packages/live_core/test/sites/missevan_test.dart 直接对照样本正文。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | `meta/data` | `S01-meta`（catalog 5 个、list 1 个、tag 1 个） |
| S02 | `chatroom/open/list` | `S02-list-p1`（22 条）、`S02-list-last`（第 29 页）、`S02-list-beyond`（第 30 页，空）、`S02-list-catalog`（音乐 104）、`S02-list-tag`（新星 1）、`S02-list-team`（`type=4`） |
| S03 | `chatroom/search` | `S03-search`、`S03-search-p2`（关键词“配音”）、`S03-search-empty` |
| S04 | `live/<id>` | `S04-live`、`S04-offline`（带过期的旧地址）、`S04-notfound`（404） |
| S05 | 游客会话 | `S05-user-info`（Set-Cookie 已脱敏） |
| S06 | 弹幕帧 | `fixtures/missevan/danmaku/S06-live`（`live_cli danmaku missevan --recommended --seconds 60 --record`，房间 246709466，14 帧：游客会话、加入、聊天、`room/statistics`、心跳；Brotli 帧脱敏后按不压缩的 Brotli 块重新封装，仍由真实解码器读取） |

**缺**：付费提问；`gift/send`（S06-live 没有出现礼物，由单元测试按 §7.5 构造）。

**需要脱敏的字段**
- 取流地址：`oi`（请求者 IP 的整数形式）、`sign`、`sk`、`trid`；保留 `expires`。
- 游客会话 Cookie `FM_SESS`（Set-Cookie 和弹幕握手）。
- 弹幕帧里观众的 `user_id`、`username`、`iconurl`，加入消息的 `uuid`。
- 搜索响应的 `ops_request_misc`（含请求 id）。
- 房间和主播的公开信息保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | `list` 类型 tab 的查询参数是不是 `type=<list_type>` | 找网页端团播页的请求 |
| 2 | 礼物 `price` 的单位（钻石）和元的换算 | 对照网页礼物面板 |
| 3 | 付费提问的消息格式；`gift/send` 的真实样本 | 录更长的弹幕样本 |
| 4 | App 分享链接的形式 | 收集真实分享文本 |
| 5 | FLV 签名到期后已建立的连接是否断开 | 连续播放超过 2 小时 |
