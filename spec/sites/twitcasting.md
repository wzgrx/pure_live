# 平台规格：twitcasting（ツイキャス / TwitCasting）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`twitcasting`（legacy/lib/core/sites.dart:55），显示名 `TwitCasting`（legacy/lib/core/sites.dart:229）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/twitcasting/`（A = twitcasting_api.dart，S = twitcasting_site.dart），其它旧代码写全路径（相对 `legacy/`）。样本编号见 §11。
- 状态：**保留**。2026-09-27 实测：页面、接口、媒体、评论在中国大陆直连和经代理都能匿名使用；有公开目录（首页分类，每类最多 60 个直播）。不满足 ADR 0003 的下线条件。
- 能力：目录（首页的分类标签 → 该类的直播窗口；推荐 = 全部）、搜索（网页文字搜索的“直播”部分；频道链接精确查找）、详情、取流（HLS fMP4，高、中、低三档）、弹幕（评论推送 WebSocket）。
- 不提供：登录；密码直播（“秘密の合言葉”，§9）；付费直播（Premier Live）；回放（`dvr`、录像）；低延迟 fMP4/WebRTC 线路（`llfmp4`、`webrtc`，播放器不支持 WebSocket 媒体）。

---

## 1. 房间身份与链接

**规范身份**：频道 id（用户 screen id），小写：`[a-z0-9_]{1,64}`，可带 `c:`（Twitcasting 账号）、`g:`（Google）、`f:`（Facebook）、`ig:`（Instagram）前缀（A:129-150）。直播（movie）id 每场都变，不作为身份。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 频道 id | `nabo66game`、`c:abzou_sub`、`g:115956781845998461844` | 转小写 | A:130 |
| 频道页 | `https://twitcasting.tv/<id>` | 路径恰好一段 | A:152-170 |
| 录像链接 | `https://twitcasting.tv/<id>/movie/<movie>` | **不认**：指向某一场旧直播，不能当频道当前的直播（A:162-163） | — |
| 分享文本 | 链接前后夹有文字 | 抽出第一个 URL | — |

- 保留路径：`search`、`help`、`login`、`logout`、`settings`、`signup`、`register`、`terms`、`privacy`、`about`、`index`、`show`、`categories`（A:132-146）。
- 频道不存在：频道页 302 到首页（S04-page-notfound），`streamserver.php` 返回 `{}`（S05-stream-notfound）→ NotFound。
- 外部打开：`https://twitcasting.tv/<id>`。

---

## 2. 目录

### 2.1 分类

- 首页 `https://twitcasting.tv/` 的顶部标签：`<a class="… tw-top-tab-item" href="/?genre=<key>" data-channel="<key>">名称</a>`（A:172-193；S01-home）。没有 `data-channel` 的“For You”跳过。
- 2026-09-27 有 17 个：Popular（`_system_channel_popular`）、KawaVo、Music、Ikebo、Girls、Guys、Game（`_system_channel_12`）、Recent、Debut、With live captions、On Collabo、Soothing Vo. … 名称按请求头 `Accept-Language: en` 取英文。
- v4：一个 `Category`（id `genre`，名称 `TwitCasting`），每个标签一个 `Area`（id = `data-channel`），保持页面顺序。首页还有一个很长的二级分类菜单，旧版不用，v4 也不用。

### 2.2 分区房间与推荐

- GET `https://frontendapi.twitcasting.tv/top/category?id=<key>&count=60`；推荐用 `id=` 空（A:195-258；S02-top-all、S02-top-game）。
- `movies[]` 字段：`user_id`（频道）、`user_name`、`user_icon_url`、`id`（本场 movie）、`title`（默认是 “`<id>'s Live`”）、`telop`（主播设的标题，可能为空）、`thumbnail_url`（`//` 开头）、`current_viewer_count`（在线）、`elapsed_time`（已播秒数）、`is_live`、`is_locked`、`is_group`、`is_deleted`。
- 只保留 `is_live` 且未加锁、非群组、未删除的条目，按频道去重（A:215-223）。标题优先 `telop`，为空时 `title`（A:244）。开播时间 = 当前时间 − `elapsed_time`。
- 只有一个窗口（最多 60 条），没有翻页（A:203-206）。旧版把它切成界面大小的几页，v4 一次返回整窗、没有下一页。

---

## 3. 搜索

- 输入是 `http(s)://` 链接时：是频道页就精确查找（未开播也返回），其它链接无结果（A:268-281）。
- 关键词：GET `https://search.twitcasting.tv/search/text/<kw>?hl=en`，只取 `#tw-search-result-live` 这一段（到 `#tw-search-result-movie` 之前；另外还有用户、Premier、录像三段，A:260-261）。
- 每个 `tw-search-result-row`：带 `data-status="live"` 的徽标才算直播；频道取 `.usertext` 里的 `<a href="/<id>">`，标题 `.tw-movie-thumbnail-title`，主播名 `.username`，封面 `.tw-movie-thumbnail2-image`，头像 `.userimage32 img`（A:295-337）。
- 一页（网页最多 50 条），没有翻页（A:260-261）。

---

## 4. 房间详情

两次请求：

1. 频道页 GET `https://twitcasting.tv/<id>`（不跟随跳转；302 即不存在）：
   - 页面含 `Enter the secret word to access` → 密码直播，NeedsLogin（A:345）。
   - `meta[name=twitter:creator]` 必须等于 id（A:347-350）。
   - 标题：`twitter:description`（本场标题，telop）非空时用它，否则 `twitter:title`（默认 “Live #<movie>”）。旧版只用 `twitter:title`（A:370）。
   - 主播名 `.tw-user-nav2-name`，头像 `.tw-user-nav2-icon img`，封面 `og:image`（A:371-373）。
2. `https://twitcasting.tv/streamserver.php?target=<id>&mode=client&player=pc_web`（A:355-363）：`movie.id`、`movie.live`（唯一可信的开播状态）。
   - `{}` → NotFound。
   - **未开播时也带着另一场直播的旧地址**（S05-stream-offline：`movie.id` 841421279，流地址却是 841532464），必须忽略（A:378-383）。

- 状态：`movie.live` true 直播中，false 未开播。
- 人数：详情没有在线人数（频道页只有累计的“total”展示，v4 不用）；列表有 `current_viewer_count`。
- 弹幕参数：直播中时 `movieId`。

---

## 5. 画质与线路

- `streamserver.php` 的 `tc-hls.streams`：`high`、`medium`、`low` 三个地址，`https://<节点>.twitcasting.tv/tc.livehls/v1/streams/<movie>/hls/<档位>/media.m3u8`（S05-stream-live；A:384-411）。
- 每个键一个画质（高、中、低，顺序即优劣），一条线路（身份 = 节点主机名）。地址的主机不是 `twitcasting.tv` 的子域，或路径不属于本场 movie 的，丢弃。
- 选中的就是实际的：确认画质 = 请求画质。
- 其它：`llfmp4`、`llfmp4.h265`（WebSocket 上的 fMP4，含 H.265）、`webrtc`、`dvr.hls`（回看）都不用。

---

## 6. 取流

### 6.1 流程

每次取流重新请求 `streamserver.php`；`movie.live` 为 false → StreamUnavailable。

### 6.2 会话 Cookie（播放器必须支持）

- 媒体列表的响应带 `Set-Cookie: lvhls_ssid_<movie>=…; Path=/tc.livehls/v1/streams/<movie>/hls/; Max-Age=600`（S06-media）。
- **分片（`init.*.mp4`、`media.*.mp4`）不带这个 Cookie 会 401**（2026-09-27 实测：不带 401，带上 200）。
- FFmpeg 的 HLS 解复用器会把列表响应的 Cookie 带到分片请求，mpv 直接播放没问题；本地中继或录制如果自己拉分片，必须同样保存并回传这个 Cookie（旧版诊断记为“需回放 HLS 会话 Cookie”）。`StreamLine.headers` 表达不了“由服务器下发的 Cookie”，这一点记为 live_media 的待办。

### 6.3 租期

- 地址不带签名和到期时间；会话 Cookie 10 分钟，每次刷新列表都会续。没有租期。

### 6.4 请求头

- `Referer: https://twitcasting.tv/`、UA、`Accept-Language: en`（A:33）。

### 6.5 媒体实况（2026-09-27）

- HLS 版本 6，fMP4：`#EXT-X-MAP` 初始化段 + 2 秒分片；初始化段里是 `avcC`（H.264）和 `mp4a`（AAC）。没有 FLV，也就没有 codec 12（HEVC）问题；H.265 只出现在不用的 `llfmp4.h265`。
- `live_cli probe twitcasting https://twitcasting.tv/nabo66game`：解析 → 详情 → 取流（高、中、低）→ 读到 HLS 列表，通过（2026-09-27，直连）。

---

## 7. 弹幕

旧版没有 TwitCasting 评论（S:21-22）。以下来自 2026-09-27 实测。

### 7.1 连接

- POST `https://twitcasting.tv/eventpubsuburl.php`，表单 `movie_id=<movie>` → `{"url":"wss://<节点>.twitcasting.tv/event.pubsub/v1/streams/<movie>/events?token=<签名>&n=<随机>"}`（S07-pubsub）。匿名即可。
- 连接这个地址即加入；握手请求头 `Origin: https://twitcasting.tv`、UA。客户端不发任何消息。

### 7.2 消息

- 服务端推 JSON 数组；空数组 `[]` 是保活。
- `{"type":"comment","id":…,"message":…,"createdAt":<毫秒>,"author":{"id","name","screenName","profileImage","grade"},"isAnonymous":…,"numComments":…}` → 聊天，id `twitcasting:<id>`。匿名评论的作者是 `c:tw<n>`、名字 “匿名コメント#…”。
- `type == "gift"`：礼物，取 `item.name`、`item.id` 和 `sender`（字段按网页脚本推断，录制时没有出现 [待确认]）。
- 其它类型忽略。

### 7.3 静默判断与重连

- 没有客户端心跳；看门狗 3 × 30 s 没有任何消息（含 `[]`）判定断线。重连时重新请求签名地址。
- 每场直播 movie 都变：主播重新开播后要重新取详情再开评论（同 live_danmaku 已知缺口）。

---

## 8. 登录与 Cookie

- 不支持登录。接口会下发设备 Cookie `did`、语言 Cookie `hl`，匿名请求不需要带回（HLS 会话 Cookie 见 §6.2）。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | A:86-94 | NetworkFailure |
| HTTP 429 / 401、403 / 404 | 同上 | RateLimited / RiskControl / NotFound |
| 频道页 302、`streamserver.php` 为 `{}` | S04-page-notfound、S05-stream-notfound | NotFound |
| 频道页要求口令 | A:345 | NeedsLogin |
| `twitter:creator` 与频道不符、没有 `movie.live` | A:347-363 | ApiChanged |
| 未开播时取流；没有可用的 `tc-hls` 地址 | §6.1 | StreamUnavailable |
| 搜索页没有“直播”段 | A:289-290 | ApiChanged |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-TWITCASTING-001 | 未开播的频道播出了别的内容 | `streamserver.php` 未开播时仍给另一场直播的地址 | 只看 `movie.live`，为假时忽略所有地址 | A:378-383 |
| REG-TWITCASTING-002 | 录制或中继分片 401 | 分片需要媒体列表下发的会话 Cookie | 保存并回传 `lvhls_ssid_<movie>` | §6.2 |
| REG-TWITCASTING-003 | 录像链接打开的是另一场直播 | 把 `/movie/<id>` 当成频道 | 录像链接不认 | A:162-163 |
| REG-TWITCASTING-004 | 标题全是 “Live #数字” | 只读 `twitter:title` | 优先 telop（`twitter:description`） | §4 |

---

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/twitcasting.dart）。旧应用不能再运行（ADR 0016），没有 `expected.json`；v4 测试 packages/live_core/test/sites/twitcasting_test.dart 直接对照样本。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | 首页 | `S01-home`（分类标签） |
| S02 | `top/category` | `S02-top-all`、`S02-top-game` |
| S03 | 文字搜索 | `S03-search`（关键词 game） |
| S04 | 频道页 | `S04-page-live`、`S04-page-offline`、`S04-page-notfound`（302） |
| S05 | `streamserver.php` | `S05-stream-live`、`S05-stream-offline`（带旧地址）、`S05-stream-notfound`（`{}`） |
| S06 | HLS 媒体列表 | `S06-media`（`Set-Cookie: lvhls_ssid_…`，已脱敏） |
| S07 | 评论地址 | `S07-pubsub` |
| S08 | 评论帧 | `fixtures/twitcasting/danmaku/S08-live`（`live_cli danmaku twitcasting --recommended --seconds 45 --record`：14 帧，12 条评论，含 `[]` 保活） |

**缺**：密码直播页；礼物消息；付费直播。

**需要脱敏的字段**
- 页面里访客的 CSRF 令牌（`data-csrf-token`、`data-token`、JSON 里的 `csrf_token`）和 `web-authorize-session-id`。
- 评论地址的 `token`、`n`（接口响应和握手地址）。
- Cookie：`did`、`hl`、`lvhls_ssid_<movie>`（Set-Cookie）。
- 评论作者的 `id`、`name`、`screenName`、`profileImage`。
- 频道、直播的公开信息保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 礼物、置顶等评论推送的类型和字段 | 录更长的评论样本 |
| 2 | 密码直播、群组直播（`is_group`）的表现 | 找对应直播 |
| 3 | live_player 实机播放时 Cookie 回传是否生效（FFmpeg 的 `cookies` 传递） | 第 5 阶段真机播放 |
| 4 | `top/category` 能否取到 60 条以后的直播 | 对比网页 |
