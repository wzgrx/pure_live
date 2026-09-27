# 平台规格：showroom（SHOWROOM）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`showroom`（legacy/lib/core/sites.dart:60），显示名 `SHOWROOM`（legacy/assets/translations/zh.json `site_showroom`）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/showroom/`（A = showroom_api.dart，L = showroom_link.dart，S = showroom_site.dart），其它旧代码写全路径（相对 `legacy/`）。样本编号见 §11。
- 状态：**保留**。2026-09-27 实测：接口、媒体、弹幕在中国大陆直连和经代理都能匿名使用；有公开目录（一次返回全部在播房间，约 60～70 个，按类型分组）。不满足 ADR 0003 的下线条件。
- 能力：目录（类型 → 在播房间，推荐 = Popularity）、搜索（在全量快照里按房间号、房间键、名字、字幕、类型过滤；房间链接精确查找）、详情、取流（HLS：原画、中、低，加自适应主列表）、弹幕（评论广播 WebSocket）。
- 不提供：登录；付费直播（`premium_room_type != 0`）；WebRTC 线路（`webrtc://`，播放器不支持）；礼物名称（只有礼物 id，§7.3）。

---

## 1. 房间身份与链接

**规范身份**：数字房间号 `room_id`（L:36-40）。公开的房间键 `room_url_key`（如 `0c1c310117354`、`48_Seina_Fukuoka`）通过 `api/room/status` 换成房间号（A:266-275）。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 房间号 | `577362` | 直接作为房间号 | A:268-269 |
| 房间页 | `https://www.showroom-live.com/r/<键>`、`https://www.showroom-live.com/<键>` | 房间键 → `room/status` | L:31-32 |
| 资料页 | `https://www.showroom-live.com/room/profile?room_id=<号>` | 房间号 | L:27-30 |
| 分享文本 | 链接前后夹有文字 | 抽出第一个 URL | — |

- 主机是 `showroom-live.com` 或其子域（L:42）。保留路径：`api`、`room`、`event`、`ranking`、`search`、`login`、`register`、`mypage`、`premium_live`（L:4-14），v4 另加 `r`、`onlive`、`campaign`、`about`、`lottery`。
- 不存在：`room/profile`、`room/status`、`live/live_info` 都返回 HTTP 404、`{"errors":[{"code":1002,"message":"Not Found"}]}`（S02-status-notfound、S03-profile-notfound）→ NotFound。
- 外部打开：有房间键时 `https://www.showroom-live.com/r/<键>`，否则资料页。

---

## 2. 目录

### 2.1 快照

- GET `https://www.showroom-live.com/api/live/onlives`：**一次返回所有在播房间**（S01-onlives，约 170 KB）。顶层还有 `bcsvr_host`、`bcsvr_port`（弹幕服务器）。旧版把它当不可变快照，30 s 内复用（S:48-71）。
- `onlives[]` 每组：`genre_id`、`genre_name`（英文，如 Popularity、Music、Idol、Streamer）、`lives[]`。
- 没有人在播的类型给一个“消息格子”（`cell_type 7`，没有 `room_id`），跳过（A:252-257）。

### 2.2 分类、分区房间、推荐

- v4：一个 `Category`（id `genre`，名称 `SHOWROOM`），每组一个 `Area`（id = `genre_id`，名称 = `genre_name`）。
- 分区房间 = 该组的 `lives`，一页。推荐 = `genre_id == 0`（Popularity）那组（S:146-151）。
- 条目字段：`room_id`、`room_url_key`、`main_name`（主播名）、`telop`（字幕，可能为空）、`image`/`image_square`、`genre_name`、`view_num`、`follower_num`、`started_at`（Unix 秒）、`streaming_url_list`（旧版也读，v4 不用，取流另外请求）。
- 标题：`telop` 非空用它，否则 `main_name`（S:179）。
- 人数：`view_num` 是本场的访问人次（官方未说明是同时在线），作为**累计**（legacy/lib/common/models/live_room.dart 中 showroom 的注释；A:290-292）。
- 图片只接受 `showroom-live.com`、`showroom-txlive.com` 的 https 地址（A:431-443）。

---

## 3. 搜索

- 平台没有公开的搜索接口。关键词在快照里过滤：房间号相等、房间键相等（不区分大小写），或主播名、字幕、类型名包含关键词（S:124-144）。一页。
- 输入是 `http(s)://` 链接：按 §1 精确查找（未开播也返回）。

---

## 4. 房间详情

两次请求（A:333-341）：

1. GET `api/room/profile?room_id=<号>`：`room_id`、`room_url_key`、`main_name`/`room_name`、`image_square`、`genre_name`、`follower_num`、`view_num`、`description`、`is_onlive`、`current_live_started_at`。
2. GET `api/live/live_info?room_id=<号>`：`live_status`（2 直播中，1 未开播，0 也按未开播）、`room_name`、`bcsvr_host`、`bcsvr_port`、`bcsvr_key`、`is_under_18`、`age_verification_status`、`premium_room_type`。

- `live_info.room_id` 必须等于请求的房间号（A:300-302）。`live_status` 不是 0、1、2 → ApiChanged（A:303-304）。
- 标题 `live_info.room_name`，主播名 `profile.main_name`，简介 `profile.description`。
- 弹幕参数（直播中时）：`bcsvrKey`、`bcsvrHost`。

---

## 5. 画质与线路

- GET `api/live/streaming_url?room_id=<号>&abr_available=1`（A:308-331；S05-streaming-live）：`streaming_url_list[]` 每项 `type`、`quality`、`label`、`url`、`is_default`。
  - `hls`：`quality` 1000（original）、200（medium）、100（low），地址 `https://shardNNN-cdn.showroom-txlive.com/live/<流名>_ss|mm|ll.m3u8`；
  - `hls_all`：自适应主列表（`…_abr202510.m3u8`，三个变体 1920×1080、640×360、256×144）；
  - `webrtc`：`webrtc://…`，不用。
- v4 画质：`hls` 按 `quality` 降序（原画、中、低），`hls_all` 作为“自动”排最后；默认选原画（旧版把“自动”排第一，S:220-233）。每个画质一条线路（身份 = 主机名）。固定档位的确认画质 = 请求；“自动”由播放器选变体，不确认。
- 未开播时列表为空（S05-streaming-offline）→ StreamUnavailable。

---

## 6. 取流

### 6.1 流程

每次取流重新请求 `streaming_url`。

### 6.2 租期

- 地址不带签名和到期时间，流名在同一场直播里不变。没有租期。

### 6.3 请求头

- API：UA、`Accept: application/json, text/plain, */*`、`Referer: https://www.showroom-live.com/`；媒体：UA、Referer（A:154-162）。

### 6.4 媒体实况（2026-09-27）

- HLS 3，约 1 秒的 TS 分片（`…_ss-<序号>.ts?txspiseq=…`）。没有 FLV，也就没有 codec 12（HEVC）问题。
- `live_cli probe showroom https://www.showroom-live.com/r/0c1c310117354`：解析（房间键 → 577362）→ 详情 → 取流（原画、中、低、自动）→ 读到 HLS 列表，通过（2026-09-27，直连）。

---

## 7. 弹幕

旧版没有 SHOWROOM 评论（S:45-46）。以下来自 2026-09-27 实测。

### 7.1 连接

- `wss://<bcsvr_host>/`（`online.showroom-live.com`，端口用 443；`bcsvr_port 8080` 是旧的明文端口）。握手请求头 `Origin: https://www.showroom-live.com`、UA。
- 连上后发**文本帧** `SUB\t<bcsvr_key>`（`bcsvr_key` 形如 `6e6c…:23483509`，每场直播一个，所有观众相同）。不需要令牌。
- `bcsvr_host` 必须是 `*.showroom-live.com`，否则不连。

### 7.2 心跳

- 每 60 s 发 `PING\tshowroom`，服务端回 `ACK\tshowroom`。

### 7.3 消息

- 格式：`MSG\t<bcsvr_key>\t<JSON>`；键不等于当前直播的丢弃。

| `t` | 含义 | 处理 |
|---|---|---|
| 1 | 评论：`cm` 文本、`u` 用户 id、`ac` 名字、`created_at`（秒）、`av` 头像 id | 聊天 |
| 2 | 礼物：`g` 礼物 id、`n` 数量、`u`、`ac` | 礼物；名称用 `#<g>`（礼物表需要另外的接口，v4 不查） |
| 8 | 字幕（telop）更新 | 忽略 |
| 18 | 系统通知（初次访问等，文本里带观众名） | 忽略 |
| 其它 | — | 忽略 |

- 平台不给消息 id；v4 用 `showroom:<u>:<created_at>:<文本哈希>` 帮助去重。
- 纯数字评论（“1”“2”…）是 SHOWROOM 的数数习惯，照常显示。

### 7.4 重连

- 共用 SocketConnector；每场直播的 `bcsvr_key` 不同，重新开播后要重新取详情。

---

## 8. 登录与 Cookie

- 不支持登录。接口会下发 `sr_id`、`f` Cookie，匿名请求不需要带回。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | A:225-233 | NetworkFailure |
| HTTP 404（`code 1002 Not Found`） | S02-status-notfound、S03-profile-notfound | NotFound |
| HTTP 429 / 401、403 | A:227-229 | RateLimited / RiskControl |
| `live_status` 取值未知；`live_info` 不属于该房间 | A:300-304 | ApiChanged |
| 未开播；列表里没有可用的 HLS | S05-streaming-offline；A:339 | StreamUnavailable |
| 付费直播 | — | 旧版没有处理。v4 取到空列表即 StreamUnavailable [待确认付费房的 `streaming_url` 表现] |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-SHOWROOM-001 | 类型页整页失败 | 没人在播的类型给的是消息格子 | 跳过没有 `room_id` 的格子 | A:252-257 |
| REG-SHOWROOM-002 | 人数被当成在线 | `view_num` 是访问人次 | 标为累计 | A:290-292 |
| REG-SHOWROOM-003 | 链接打不开 | 分享的是房间键不是房间号 | 房间键先查 `room/status` | A:266-275 |

---

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/showroom.dart）。旧应用不能再运行（ADR 0016），没有 `expected.json`；v4 测试 packages/live_core/test/sites/showroom_test.dart 直接对照样本。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | `live/onlives` | `S01-onlives`（18 个类型，含没人在播的消息格子） |
| S02 | `room/status` | `S02-status-key`、`S02-status-notfound`（404） |
| S03 | `room/profile` | `S03-profile-live`、`S03-profile-offline`、`S03-profile-notfound`（404） |
| S04 | `live/live_info` | `S04-live-info-live`、`S04-live-info-offline`（`live_status 1`） |
| S05 | `live/streaming_url` | `S05-streaming-live`（hls、hls_all、webrtc）、`S05-streaming-offline`（空） |
| S06 | 评论帧 | `fixtures/showroom/danmaku/S06-live`（`live_cli danmaku showroom 577362 --seconds 70 --record`：25 帧，订阅、18 条评论、字幕更新、PING） |

**缺**：付费直播；礼物消息（录制时没有出现，由单元测试构造）。

**需要脱敏的字段**
- HTTP 样本只含公开信息（房间、主播、共享的拉流地址和评论键）；会话 Cookie（Set-Cookie）由工具统一脱敏。
- 评论帧：评论和礼物的 `u`、`ac`，只保留 `t`、`cm`、`g`、`n`、`created_at`；其它类型（带观众名的通知）只保留 `t`。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 付费直播（`premium_room_type`）和年龄验证（`age_verification_status`）的取流表现 | 找对应房间 |
| 2 | 礼物 id → 名称的接口 | 看网页礼物面板请求 |
| 3 | `live_status 0` 的含义 | 观察更多房间 |
