# 平台规格：Twitch（twitch）

- 平台 id：`twitch`（legacy/lib/core/sites.dart:50）；显示名“Twitch”（legacy/lib/core/site/twitch/twitch_site.dart:23）。
- 阶段：第二批（docs/adr/0003-platform-batches.md），第 7 阶段前段迁移。
- **去留：保留。** 2026-09-28 实测不满足 ADR 0003 任何一条下线标准：匿名取流成功（`live_cli probe twitch zarbex` 直连、`probe twitch shroud --proxy 127.0.0.1:7897` 经代理，都读到 HLS），不需要登录，公开目录完整（40 个类型标签）。**限制**：列表只有第一页（§2.4），翻页要浏览器里生成的完整性令牌（§8），v4 用纯 Dart 做不到，不伪造。
- 能力：两级目录（“热门”加 40 个类型标签）、分区房间（第一页，最多 100 个）、推荐（全站前 30）、频道搜索（含未开播，可翻页）、详情、取流（HLS，每个画质一条变体地址，不需要续期）、弹幕（匿名 IRC）、可选的用户令牌（只用于播放令牌）。
- 不提供：列表翻页（§2.4、§8）、广告过滤（§6.4）、登录后发弹幕。
- 网络：海外平台。本机 WSL 的出口在美国，直连和经 Clash 代理（127.0.0.1:7897）都可用；国内网络需要应用的平台代理。所有样本和弹幕帧都经 `dart:io` + 代理录制。
- 证据口径：旧代码写成 `legacy/…:行号`；“实测”指 2026-09-27/28 在本机发出的匿名请求；样本编号见 §11（`fixtures/twitch/`）。
- 路径简写：`site` = legacy/lib/core/site/twitch/twitch_site.dart，`dm` = legacy/lib/core/danmaku/twitch_danmaku.dart，`wi` = legacy/lib/core/utils/twitch/twitch_web_integrity.dart，`reo` = legacy/lib/modules/live_play/services/room_external_opener.dart，`wsp` = legacy/lib/modules/search/web_search_room_parser.dart。

---

## 1. 房间身份与链接

**规范身份**：频道登录名 `login`，1～25 个字母、数字或下划线，统一小写。

- 频道的数字 id（`user.id`，如 `403594122`）不作身份，放进弹幕参数（§4）。

**可接受的输入**（都不联网）

| 形式 | 例 | 处理 | 证据 |
|---|---|---|---|
| 登录名 | `Shroud` | 小写后作为 login（不含 `.`） | — |
| 频道页 | `https://www.twitch.tv/shroud?sr=a`、`https://m.twitch.tv/zarbex/home`、`twitch.tv/zarbex` | 第一段 | wsp:156-157 |
| 弹出聊天 | `https://www.twitch.tv/popout/zarbex/chat` | `popout` 后一段 | — |
| 嵌入播放器 | `https://player.twitch.tv/?channel=zarbex&parent=x` | 查询参数 `channel` | — |
| 分享文本 | 链接前后夹文字 | 先抽出 URL 再按上表处理 | — |

- `directory`、`videos`、`search`、`settings`、`p`、`downloads`、`drops`、`inventory`、`wallet`、`subscriptions`、`turbo`、`prime`、`store`、`jobs`、`login`、`signup`、`messages`、`friends`、`following`、`moderator`、`payments` 不是频道。

**外部打开**：`https://www.twitch.tv/<login>`（reo:181-182）。

---

## 2. 目录

### 2.0 GraphQL

- 所有接口都是 POST `https://gql.twitch.tv/gql`，正文是 JSON（一个操作，或一个数组做批量）。
- 请求头：`Client-ID: kimne78kx3ncx6brgo4mv6wki5h1ko`（网页客户端，site:45）、`Device-Id`（32 位十六进制，每个适配器实例一个，site:52-60、86-90）、浏览器 `User-Agent`、`Origin`/`Referer: https://www.twitch.tv/`、`Content-Type: text/plain;charset=UTF-8`、`Accept-Language: zh-CN,…`。
- **`Accept-Language` 决定名称语言**：带 `zh-CN` 时类型标签和分区名是中文（“冒险游戏”“谈天说地”），英文名在 `name` 里（实测）。
- 旧版用的持久化查询（`persistedQuery.sha256Hash`，site:92-100）2026-09 仍然有效；v4 沿用它们，另用两个原始查询（`query` 文本，§2.3、§4）。未知的哈希报 `PersistedQueryNotFound` → ApiChanged。
- **批量上限 35 个操作**，超过报 `BATCH_LIMIT_EXCEEDED`（实测 40 个）。
- 响应里常有局部错误（如搜索结果的 `latestVideo` 报 `service error`），只要 `data` 在就照常解析；`errors` 里有 `integrity` 或 `extensions.challenge` → RiskControl（§8）。

### 2.1 分类（两级）

- 一级：`SearchCategoryTags`（`userQuery: ""`, `limit: 100`，site:416-452）→ 41 个类型标签，按服务端顺序；`localizedName`（缺时 `tagName`）作名称，两者都空的标签不要（实测 `zh-CN` 下有一个空名标签）（S01-tags：40 个）。
- v4 在最前面加一个“热门”分类（id `top`）：`BrowsePage_AllDirectories`（`tags: []`、按人数、`limit: 100`）。
- 每个标签的分区：`BrowsePage_AllDirectories`（`tags: [<标签 id>]`、`limit: 30`，site:454-528）。
- 全部 41 个操作分两批发（35 + 6，S01-dirs-1、S01-dirs-2），两次请求共约 1 MB。
- 分区：`id` = `slug`（`DirectoryPage_Game` 要用它），名称 `displayName`，图标 `avatarURL`。旧版把图片改走 `i2.wp.com` 代理（site:514、853、856、914、917），v4 保留原地址，图片是否走代理由应用决定。
- 旧版对每个标签递归翻页（site:454-475）；现在第二页起需要完整性令牌（§2.4），旧版实际上也只拿到每个标签的前 30 个。

### 2.2 分区房间

- `DirectoryPage_Game`（`slug`、按人数、`limit: 100`，site:778-877），批量格式（数组）发送。
- 响应 `game.streams.edges[].node`：`broadcaster.login`、`broadcaster.displayName`、`broadcaster.profileImageURL`、`title`、`viewersCount`（**在线人数**）、`previewImageURL`（440×248）、`game.displayName`、`type`（`live`；`rerun` 为回放）。
- `game == null` → NotFound（S02-game-missing）。
- 旧版只看中文和韩语直播（`broadcasterLanguages: ["ZH","KO"]`，site:798），v4 不过滤：第一页只有 100 个，过滤后常常所剩无几；语言筛选以后由应用做。
- **只有第一页**（§2.4）：实测“谈天说地”一页 87 个（S02-game），`hasNextPage` 为真也不翻。

### 2.3 推荐

- 旧版是 Just Chatting 分区的前 30 个（site:684-690）。
- v4 用原始查询 `streams(first: 30)`：全站人数最多的 30 个直播，带 `createdAt`（开播时间）（S03-streams）。`first` 最大 30（实测 `argument 'first' value must be between 1 and 30.`）。
- 同样只有第一页。

### 2.4 翻页与完整性

- 带 `cursor` 的列表请求（`DirectoryPage_Game`、`BrowsePage_AllDirectories`、原始 `streams`）都返回 `failed integrity check`，`extensions.challenge.type == "integrity"`（S02-game-cursor；实测三种都一样）。
- 所以 v4 的分区、推荐、分类都在第一页结束（`next == null`；收到游标时返回空页）。原因和补救见 §8。
- 搜索不受影响（§3）。

---

## 3. 搜索

- `SearchResultsPage_SearchResults`（site:879-934）。
- 第一页 `options.targets: null`：10 个频道和游标 `channels.cursor`（实测 `MTA=`，即 base64 的“10”）（S04-search-p1）。
- 下一页 `options.targets: [{index: "CHANNEL", cursor: <游标>}]`：实测再给 15 个、游标 `MjU=`（S04-search-p2）。**不需要完整性令牌**。
- 旧版把游标放在顶层变量 `cursor`（site:895），服务端不认，第二页和第一页完全一样（实测），翻页只会重复。
- 结束：游标为空或本页没有频道（S04-search-empty：`cursor: ""`、`totalMatches: 0`）。
- 字段：`login`、`displayName`、`profileImageURL`、`broadcastSettings.title`；`stream` 不为空即在播：`templatePreviewImageURL`（换成 440×248）、`viewersCount`、`game.displayName`。未开播没有封面和人数。
- 旧版的“主播搜索”返回空（site:936-938）；v4 的频道搜索就是主播搜索。空关键词不请求。

---

## 4. 房间详情

- 旧版批量查 `ChannelShell` + `StreamMetadata`（site:705-775），而 `StreamMetadata` 的 `viewersCount` 已经恒为 0（site:729-731 注释）。
- v4 用一个原始查询：`user(login:) { id login displayName description profileImageURL stream { id title type viewersCount createdAt previewImageURL game } lastBroadcast { title game } }`。
- `user == null` → NotFound（S05-user-missing）；回显的 login 不一致 → ApiChanged。
- 状态：`stream` 不为空且 `type == "live"` 为直播中，`rerun` 为回放，为空是未开播（S05-user-live、S05-user-offline）。
- 标题：直播中用 `stream.title`，否则 `lastBroadcast.title`；分区同理。公告用 `description`。
- **弹幕参数**：`danmakuKeys = {login, channelId}`。
- **原站链接**：`https://www.twitch.tv/<login>`。
- 查询失败必须作为失败返回；旧版曾把失败当“未开播”（site:693-696 注释说明已改）。

---

## 5. 画质与线路

来源是 usher 的主播放列表（§6.2）。

- `#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="720p60",NAME="720p50"` 给名称；`#EXT-X-STREAM-INF:BANDWIDTH=…,RESOLUTION=…,CODECS=…,VIDEO="720p60",FRAME-RATE=…` 后一行是变体地址（S06-usher-live）。
- **画质**：`Quality.id` 是 `VIDEO` 组 id，标签是对应的 `NAME`（“1080p50 (source)”“720p50”“480p”…）。`chunked` 是主播的原始流，排第一；其余按 `BANDWIDTH` 从高到低（原始流的平均码率可能低于转码，旧版也这样排，site:622-625）。
- 每个 `STREAM-INF` 和它后一行一起解析；旧版曾把地址和码率分成两个数组，错位后标签对不上（site:583-590 注释）。
- 不请求 `allow_audio_only`，纯音频不列。
- **编码**：请求 `supported_codecs=avc1`，全部是 H.264（`CODECS="avc1…"` → `avc`）。HEVC/AV1 增强广播没有请求 [待确认：播放器支持情况]。
- **线路**：每个画质一条，就是它的变体地址；线路 id 是地址主机（如 `use23.playlist.ttvnw.net`）。
- 选定画质不在列表里时用第一个（原始流）。

---

## 6. 取流

### 6.1 播放令牌

- `PlaybackAccessToken`（`isLive: true`、`login`、`playerType: "site"`、`platform: "site"`，site:540-556）→ `streamPlaybackAccessToken {value, signature}`。
- `value` 是 JSON 字符串：`channel`、`expires`（签发后 **20 分钟**，实测）、`authorization {forbidden, reason}`、`user_ip`、`server_ads`、`show_ads`、`subscriber`、`turbo` 等（S06-pat-live）。
- `streamPlaybackAccessToken == null` → NotFound（S06-pat-missing）。
- `authorization.forbidden == true`：原因含 `geo` → RegionBlocked，其它 → NeedsLogin（订阅专属等）。
- 用户存了 Cookie 且其中有 `auth-token` 时，这一个请求带 `Authorization: OAuth <token>`（旧版对所有请求都带，site:52-72）；返回 401（令牌过期）时改为匿名再请求一次（旧版用 `_bypassStoredSessionForIntegrity` 绕过过期 Cookie，site:142-171）。

### 6.2 usher 主播放列表

- GET `https://usher.ttvnw.net/api/channel/hls/<login>.m3u8`，参数 `allow_source=true`、`fast_bread=true`、`p=<随机数>`、`platform=web`、`player_backend=mediaplayer`、`playlist_include_framerate=true`、`reassignments_supported=true`、`supported_codecs=avc1`、`cdm=wv`、`sig`、`token`（site:558-580）。旧版的 `acmb`、固定的 `play_session_id`、`player_version`、`transcode_mode` 实测不需要。
- 200 → §5。
- 404（`[{"error":"Can not find channel"}]`，频道没在播）→ StreamUnavailable（S06-pat-offline + S06-usher-offline）。
- 403：`error_code` 含 `geo` → RegionBlocked，其它（如 `unauthorized_entitlements`）→ NeedsLogin。5xx → NetworkFailure。
- 主播放列表的 `EXT-X-TWITCH-INFO` 里有 `USER-IP`、`USER-COUNTRY`、会话 id，不解析。

### 6.3 租期

- **不设租期**。令牌 20 分钟过期，但它只用于请求主播放列表；变体地址实测每 2 分钟刷新一次、连续 39 分钟都是 200 并有新分片（2026-09-27）。断开后重新取流即可。

### 6.4 请求头与广告

- 媒体请求只带 `User-Agent`。
- 匿名观看时令牌里 `server_ads: true`：Twitch 在服务端把广告拼进 HLS 流，播放器会照常播放广告。旧版也一样，v4 不做过滤。

---

## 7. 弹幕

旧版有 Twitch 弹幕（dm:1-176），v4 按同一协议重写。

### 7.1 连接

- `wss://irc-ws.chat.twitch.tv:443`（旧版不带端口，dm:29），文本帧，每帧一行或多行（`\r\n` 分隔）。握手带 `Origin: https://www.twitch.tv`。

### 7.2 登录与加入

- 连上后依次发：`CAP REQ :twitch.tv/tags twitch.tv/commands`、`PASS SCHMOOPIIE`、`NICK justinfan<数字>`、`JOIN #<login>`（dm:76-88）。旧版还请求 `twitch.tv/membership`（观众进出），v4 不要。
- 旧版在用户存了 `auth-token` 时用它登录聊天（dm:77-84）；只收弹幕不需要登录，v4 一律匿名。
- 服务端回 `CAP * ACK`、`001`～`376` 欢迎、自己的 `JOIN`、`ROOMSTATE #<login>`、`353`/`366`（S07-live）。收到该频道的 `ROOMSTATE` 或自己的 `JOIN` 即加入成功；10 秒内没有则重连。
- 实测发出登录行到收到 `ROOMSTATE` 约 200 毫秒。

### 7.3 消息

- `PRIVMSG #<login> :<文本>` 是聊天（dm:126-168）。标签：`display-name`（空时用前缀里的 nick）、`user-id`、`id`（消息 id，作 `twitch:<id>`）、`color`（`#RRGGBB`，空为白色）、`tmi-sent-ts`（毫秒）。标签值要反转义（`\s` 空格、`\:` 分号、`\\`、`\r`、`\n`，dm:170-175）。
- `/me` 消息的文本包在 `\x01ACTION …\x01` 里，去掉包装。
- 别的频道的 `PRIVMSG` 丢弃（CONN-5）。
- 不解码：`USERNOTICE`（订阅、突袭）、`bits` 标签（打赏，文本里的 Cheer 表情照常显示）、`CLEARCHAT`/`CLEARMSG`（管理员删除消息）、表情图片（文本保留表情名）。
- 实测 zarbex（约 2 万人在看）40 秒 18 条聊天（S07-live）。

### 7.4 心跳与重连

- 服务端 `PING :tmi.twitch.tv` → 立即回 `PONG :tmi.twitch.tv`（dm:112-115）。
- 客户端每 60 秒发 `PING :tmi.twitch.tv`（旧版 40 秒，dm:27）；无消息超时 180 秒（3 × 心跳）。
- `RECONNECT` → 重连；加入前收到含 `auth` 的 `NOTICE`（登录失败）→ 重连。

---

## 8. 登录、完整性与平台限制

**完整性令牌（列表翻页的缺口）**

- 第二页起的列表请求要带 `Client-Integrity` 令牌（§2.4）。
- 直接 POST `https://gql.twitch.tv/integrity`（带 `X-Device-Id`，旧版的纯 HTTP 办法，site:286-300）**能拿到令牌**（响应头 `X-Kpsdk-Ct`），但带上它的翻页请求仍然 `failed integrity check`（实测）：服务端据令牌判定这是自动化客户端。
- 可用的令牌要在浏览器里运行 Kasada 的 KPSDK 脚本（`https://k.twitchcdn.net/…/p.js`）后由它改造过的 `fetch` 请求 `/integrity`。旧版为此用无界面 WebView（`TwitchWebIntegrityProvider`，wi:16-60，只支持 Android、iOS、macOS），最后甚至把 GraphQL 请求整个放进 Chromium 里发（site:173-210）。
- v4 的 `live_core` 是纯 Dart，没有 WebView，**不实现翻页，也不伪造令牌**。要恢复翻页，需要应用层提供一个“完整性令牌来源”（WebView 里跑 KPSDK），适配器在有令牌时带 `Client-Integrity` 请求下一页；这需要真机验证，本阶段不做。

**Android 的 TLS 问题**

- 旧版记录：某些 Android 代理路径在 CONNECT 之后会重置 `dart:io` 的 TLS 连接，而同一代理在 Chrome 里正常（site:122-126、173-176）；旧版先改用 Android 系统 HTTP 栈（只允许 `gql.twitch.tv`），再退到 Chromium。
- 本机（Linux，`dart:io`，Clash 代理）所有请求和弹幕都正常，这个问题无法在这里复现。v4 的 `live_core` 只通过 `LiveHttp` 发请求；如果在 Android 上复现，修复应放在应用的 `LiveHttp` 实现里（为 `twitch` 提供平台 HTTP 栈），不在适配器里 [待确认：真机]。

**用户令牌**

- 旧版有 Twitch Cookie 设置页（legacy/lib/modules/account/twitch/）。v4 从 `CookieVault` 取 `twitch` 的 Cookie，只用其中的 `auth-token`，只用于播放令牌（§6.1）：订阅专属直播、Turbo 或订阅者免广告。目录、搜索、详情一律匿名，避免过期令牌影响浏览（旧版 site:142-171）。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | — | NetworkFailure |
| GraphQL HTTP 429 | — | RateLimited |
| GraphQL HTTP 401 | — | NeedsLogin（播放令牌时先改匿名重试） |
| GraphQL 其它非 200、非 JSON、`data` 为空且有错误 | — | ApiChanged |
| `PersistedQueryNotFound` | — | ApiChanged |
| `failed integrity check` / `extensions.challenge` | S02-game-cursor | RiskControl（`integrity`） |
| `game == null` | S02-game-missing | NotFound |
| `user == null`、非法 login | S05-user-missing | NotFound |
| `streamPlaybackAccessToken == null` | S06-pat-missing | NotFound |
| 令牌 `forbidden`（地区 / 其它） | — | RegionBlocked / NeedsLogin |
| usher 404 | S06-usher-offline | StreamUnavailable |
| usher 403（地区 / 其它） | — | RegionBlocked / NeedsLogin |
| 主播放列表没有视频变体 | — | StreamUnavailable |
| 弹幕：登录名不合法 | — | 终态 `noRoom` |
| 弹幕：`RECONNECT`、登录失败 | — | 重连 |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-TWITCH-001 | 分区、分类第二页起报错或空白 | 翻页要浏览器完整性令牌 | 第一页取满（100），不翻页 | S02-game-cursor；实测 |
| REG-TWITCH-002 | 搜索翻页一直重复第一页 | 游标放在顶层变量，服务端不认 | 放进 `options.targets[{index: CHANNEL, cursor}]` | site:895；实测 |
| REG-TWITCH-003 | 详情在线人数为 0 | `StreamMetadata.viewersCount` 已停用 | 原始 `user` 查询取 `stream.viewersCount` | site:729-731 |
| REG-TWITCH-004 | 画质标签和地址错位 | 地址与码率分两个数组收集 | 每个 `STREAM-INF` 与后一行一起解析 | site:583-590 |
| REG-TWITCH-005 | 原画排在转码后面 | 原始流平均码率可能更低 | `chunked` 固定排第一 | site:622-625 |
| REG-TWITCH-006 | 过期 Cookie 让所有浏览失败 | 所有请求都带用户令牌 | 只在播放令牌时带，401 改匿名 | site:142-171 |
| REG-TWITCH-007 | 频道查询失败显示“未开播” | 失败被当成离线 | 失败抛错 | site:693-696 |
| REG-TWITCH-008 | 分页信息缺失时整页失败 | 假定 `pageInfo` 一定存在 | 不依赖 `pageInfo`（v4 只取第一页） | site:377-385 |
| REG-TWITCH-009 | 推荐请求报参数错误 | 原始 `streams` 的 `first` 最大 30 | 用 30 | 实测 |
| REG-TWITCH-010 | 一次取分类报 `BATCH_LIMIT_EXCEEDED` | 批量上限 35 | 分批 | 实测 |

---

## 11. 样本清单

2026-09-28 经代理（127.0.0.1:7897）录制，共 18 个 HTTP 样本（`fixtures/twitch/`，规则 `tools/live_cli/lib/src/fixture/rules/twitch.dart`）和 1 个弹幕样本。期望值写在 `packages/live_core/test/sites/twitch_*_test.dart`、`packages/live_danmaku/test/twitch_test.dart`。GraphQL 样本按 JSON 正文匹配。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | 分类 | `S01-tags`（41 个标签）、`S01-dirs-1`（热门 100 个 + 34 个标签，每个至多 30 个）、`S01-dirs-2`（6 个标签） |
| S02 | 分区房间 | `S02-game`（谈天说地，87 个）、`S02-game-missing`、`S02-game-cursor`（第二页，完整性错误） |
| S03 | 推荐 | `S03-streams`（全站前 30） |
| S04 | 搜索 | `S04-search-p1`（“minecraft”，10 个）、`S04-search-p2`（15 个）、`S04-search-empty` |
| S05 | 详情 | `S05-user-live`（zarbex）、`S05-user-offline`（minecraft）、`S05-user-missing` |
| S06 | 取流 | `S06-pat-live`、`S06-pat-offline`、`S06-pat-missing`、`S06-usher-live`（5 个画质，含原始流）、`S06-usher-offline`（404） |
| S07 | 弹幕帧 | `danmaku/S07-live`（zarbex，40 秒，27 帧，18 条聊天） |
| — | 地区限制、订阅专属、回放（`rerun`）、登录后的令牌 | **缺** |

**需要脱敏的字段**

- 播放令牌：`signature`；`value` 里的 `user_ip`（`value` 是 JSON 字符串，按 JSON 脱敏）。`device_id` 是录制时随机生成的 `Device-Id`，和请求头一样保留。
- usher 地址：`sig`、`token`（回放时不参与匹配），`play_session_id`。
- 主播放列表：`USER-IP`、`SERVING-ID`、`VIDEO-SESSION-ID`、`C`/`E`（base64 的带签名分片地址）、变体地址里 `/v1/playlist/<令牌>.m3u8` 的令牌。
- Set-Cookie（工具统一脱敏）。
- 弹幕：聊天发送者的 `display-name`、前缀里的 login、`user-id`、回复对象的名字和 id 换成假名，`client-nonce` 换成假值，聊天文本里提到这些名字的地方（`@名字`）一并替换；`USERNOTICE` 等其它观众的通知整行丢弃；匿名 nick、频道和 `ROOMSTATE` 保留。
- 频道公开信息（login、id、名字、头像、标题、预览、人数）保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | Android 上 `dart:io` 经代理访问 `gql.twitch.tv` 是否仍被重置 | 真机，经应用代理 |
| 2 | WebView 里的 KPSDK 令牌能否让 v4 翻页（接口设计见 §8） | 真机 WebView 原型 |
| 3 | 地区限制、订阅专属直播的令牌和 usher 应答形态 | 找对应频道或换地区 |
| 4 | `rerun`（回放）是否还存在 | 找重播频道 |
| 5 | HEVC/AV1 增强广播是否值得请求 | 播放器支持情况 |
| 6 | 管理员删除消息（`CLEARMSG`）是否要从弹幕列表撤回 | 设计弹幕列表时决定 |
