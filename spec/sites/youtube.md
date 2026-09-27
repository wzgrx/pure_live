# 平台规格：YouTube 直播（youtube）

ADR 0003 的**候选下线**平台，第 7 阶段评估。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`youtube`，显示名 `YouTube`。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/youtube/`（A = youtube_api.dart，L = youtube_link.dart，S = youtube_site.dart）。样本编号见 §11。

## 0. 去留评估（ADR 0003 下线标准）

2026-09-27 经代理（Clash，美国出口）实测：

| 标准 | 结论 | 证据 |
|---|---|---|
| 1. 取流成功率 < 50% | **不满足**：ANDROID 客户端的 `player` 接口匿名返回 `hlsManifestUrl`，主列表、变体列表、分片都 200。WEB 客户端返回 `UNPLAYABLE`，TVHTML5 要求登录——只能用 ANDROID 客户端 | 实测；S04-player-live |
| 2. 需要应用不支持的登录 | **不满足**：公开直播匿名可看；年龄限制等报 NeedsLogin | 实测 |
| 3. 没有公开目录且链接不稳定 | **不满足**：“直播”频道页（`UC4R8DWoMoI7CAwX8_LjQHig`）是公开目录；搜索可按“直播”过滤；频道和 `@handle` 链接长期稳定 | S01-browse-live；S02-search-p1 |

**结论：保留**，实现目录（直播频道页一页）、搜索、详情、取流、链接。旧版诊断以“0 测试、只能链接导入”建议下线（docs/rewrite/diagnosis/01-sites.md ④），那是旧实现的状态，不是平台的限制。

限制：中国大陆直连不可用，必须给 `youtube` 配代理（应用的按平台代理，ADR 0011 第 3 条）；媒体地址绑定请求方 IP（§5），播放器的媒体代理必须与接口走同一出口。

- 能力：推荐（直播频道页，一页）、搜索（直播，续页令牌分页）、详情、取流（HLS 变体主列表，AVC）、链接解析（视频、频道、`@handle`）、弹幕（直播聊天轮询，§7）。
- 不提供：分类；登录。

---

## 1. 房间身份与链接

两种房间 id：

| id | 形状 | 用途 |
|---|---|---|
| 频道 | `UC` + 22 位（`UCSJ4gkVC6NrvII8umztf0Ow`） | 稳定的主播身份；详情和取流先查频道的直播页当前指向哪个视频 |
| 视频 | 11 位（`nI725iVsyoQ`） | 一场直播；目录和搜索卡片用它（同一频道可能同时有几场直播，卡片要打开的是那一场） |

| 输入 | 处理 | 证据 |
|---|---|---|
| 纯视频 id / 频道 id | 直接使用 | L:58-66 |
| `https://www.youtube.com/watch?v=<id>`、`/live/<id>`、`/embed/<id>`、`/v/<id>`、`https://youtu.be/<id>`（也收 `m.youtube.com`） | 视频 | L:22-42 |
| `https://www.youtube.com/embed/live_stream?channel=<UC…>` | 频道 | L:31-37 |
| `https://www.youtube.com/channel/<UC…>[/live]` | 频道 | L:85-101 |
| `https://www.youtube.com/@<handle>[/…]`、`/c/<名>`、`/user/<名>`、纯 `@<handle>` | `navigation/resolve_url` 换成频道 id（`browseEndpoint.browseId`，S03-resolve-handle） | A:171-189 改写 |
| 分享文本 | 抽出第一个 URL | — |

- 外部打开：视频 `https://www.youtube.com/watch?v=<id>`，频道 `https://www.youtube.com/channel/<id>/live`。

## 2. 目录

- 没有分类。推荐 = “直播”频道页：`POST https://www.youtube.com/youtubei/v1/browse?prettyPrint=false`，正文 `{"context":{"client":{"clientName":"WEB","clientVersion":"2.20260925.01.00","hl":"en","gl":"US"}},"browseId":"UC4R8DWoMoI7CAwX8_LjQHig"}`，请求头 `Content-Type: application/json`、`Origin: https://www.youtube.com`、`Cookie: SOCS=CAI`（同意页 Cookie，旧版同样带，A:107）。
- 响应里所有 `videoRenderer`（S01-browse-live 共 49 个，混着已结束的直播）。只保留正在直播的：`badges[].metadataBadgeRenderer.style == BADGE_STYLE_TYPE_LIVE_NOW`，或 `thumbnailOverlays[].thumbnailOverlayTimeStatusRenderer.style == LIVE`，或 `viewCountText` 是“N watching”。
- 卡片：房间 id = `videoId`；标题 `title`；主播 `ownerText`（缺时 `longBylineText`）；封面 `thumbnail.thumbnails` 最后一张；头像 `channelThumbnailSupportedRenderers.channelThumbnailWithLinkRenderer.thumbnail`；在线人数 = `viewCountText` 的“N watching”。
- 只有一页（频道页没有续页令牌）。

## 3. 搜索

- `POST …/youtubei/v1/search`，正文 `{"context":<WEB>,"query":"<kw>","params":"EgJAAQ%3D%3D"}`（“直播”过滤器）。续页：`{"context":<WEB>,"continuation":"<令牌>"}`，令牌取响应里最后一个 `continuationItemRenderer.continuationEndpoint.continuationCommand.token`（S02-search-p1、-p2，两页不重叠）。
- 卡片同 §2；本页没有直播卡片时不再给续页。

## 4. 房间详情

### 4.1 频道

`POST …/youtubei/v1/navigation/resolve_url`，正文 `{"context":<WEB>,"url":"https://www.youtube.com/channel/<id>/live"}`：
- 在播：`endpoint.watchEndpoint.videoId`（S03-resolve-channel-live）→ 按 §4.2 取该视频，房间 id 仍是频道。
- 不在播：`endpoint.browseEndpoint`（S03-resolve-channel-offline）→ 未开播；名称取频道 RSS `GET https://www.youtube.com/feeds/videos.xml?channel_id=<id>` 的 `<title>`（S05-feed-offline）。
- 旧版下载 120 万字节的频道 HTML 找 `ytInitialPlayerResponse`（A:171-189）；v4 用这个 1 KB 的接口。

### 4.2 视频

`POST …/youtubei/v1/player`，正文 `{"context":{"client":{"clientName":"ANDROID","clientVersion":"21.08.266","hl":"en","gl":"US"}},"videoId":"<id>","contentCheckOk":true,"racyCheckOk":true}`（A:201-225）。
- `playabilityStatus.status`：`OK`、`LIVE_STREAM_OFFLINE`（预告）继续；`LOGIN_REQUIRED`、`AGE_CHECK_REQUIRED`、`CONTENT_CHECK_REQUIRED` → NeedsLogin；`ERROR` 且没有 `videoDetails` → NotFound（S04-player-missing，“This video is unavailable”）；`UNPLAYABLE`、其它 `ERROR` → StreamUnavailable；其它 → ApiChanged。
- `videoDetails`：`videoId`（请求的是视频时必须相同）、`title`、`author`、`channelId`、`isLive`、`isLiveContent`、`thumbnail`、`viewCount`（累计观看，放累计口径）、`shortDescription`（简介）。
- 状态：`isLive == true` 且 `OK` → 直播；否则未开播（包括普通视频、预告、已结束的直播）。
- 在线人数：`player` 不给并发人数，为空（旧版从观看页 `ytInitialData` 取，A:257）。
- 弹幕参数：`danmakuKeys = {videoId, channelId}`。

## 5. 画质与线路

- `streamingData.hlsManifestUrl`：HLS 变体主列表（`manifest.googlevideo.com/api/manifest/hls_variant/…/file/index.m3u8`），含 144p–1080p 各档（CODECS `avc1`/`mp4a`）。v4 只提供一档 `hls`“自动”，交给播放器；旧版把变体拆成画质（A:311-345）[待确认是否需要]。
- 地址路径里有 `/expire/<秒>/`（签发后约 6 小时）、`/ip/<请求方 IP>/`、`/sig/<签名>/`。
  - 租期：`expiresAt = expire`，提前 30 分钟刷新，`cutsConnection = false`（过期后播放器刷新变体列表失败，恢复链会用预取的新地址）。
  - **IP 绑定**：地址只对请求 `player` 的那个出口 IP 有效，播放器必须走同一代理出口（ADR 0011 说媒体代理不归 `live_net` 管，这里需要应用把 YouTube 的媒体代理设成与接口相同）。
- 线路一条，id `googlevideo`。编码 AVC。

## 6. 取流

- 频道房间：重新 `resolve_url`（§4.1），不在播 → StreamUnavailable；视频房间：直接 `player`。
- 不是直播或没有 `hlsManifestUrl` → StreamUnavailable。
- 媒体请求头只带 UA。

## 7. 弹幕

匿名可用（2026-09-28 经代理实测，S06-live）。请求头同 §2（WEB 上下文、`SOCS=CAI`），走 `youtube` 的平台路由。

1. `POST …/youtubei/v1/next`，正文 `{"context":<WEB>,"videoId":"<在播视频>"}` → `contents.twoColumnWatchNextResults.conversationBar.liveChatRenderer.continuations[0].reloadContinuationData.continuation`。没有 `liveChatRenderer`（不在播、关闭了聊天）→ 结束，原因 `offline`。视频 id 取 `danmakuKeys.videoId`（频道房间在播时由 §4.1 给出；不在播时没有，直接结束）。
2. `POST …/youtubei/v1/live_chat/get_live_chat`，正文 `{"context":<WEB>,"continuation":"<上一次的>"}` → `continuationContents.liveChatContinuation`：
   - `actions[].addChatItemAction.item.liveChatTextMessageRenderer`：`message.runs[]`（`text`，或 `emoji.shortcuts[0]`）、`authorName.simpleText`、`authorExternalChannelId`、`id`、`timestampUsec`（微秒）。消息 id = `youtube:<id>`。
   - `liveChatPaidMessageRenderer`（付费留言）：按聊天行发出，正文前加 `purchaseAmountText`（如 `$5.00`）。不做醒目留言：金额是各国货币，醒目留言模型的价格是人民币元，[待确认] 是否换算。
   - 其它（删除、置顶、会员、互动提示）不解码。
   - `continuations[0]`：`invalidationContinuationData` 或 `timedContinuationData`，带下一次的 `continuation` 和 `timeoutMs`；没有续页 → 聊天结束（`offline`）。
3. 第一次回答是最近的历史（S06-live 77 个动作，73 条聊天），不发出；之后每次回答都发出。
4. 间隔：按 `timeoutMs`，但不超过 5 秒、不少于 1 秒。网页客户端拿到的是 `invalidationContinuationData`（10 秒）配合推送通知；v4 不接推送，缩短轮询间隔来接近网页的延迟（S06-live：45 秒 8 次轮询，之后每次 1–5 条）。
5. 失败重试间隔 2 秒，连续 8 次失败结束。

## 8. 登录与 Cookie

不支持账号。请求带同意页 Cookie `SOCS=CAI`，避免欧盟出口被重定向到同意页。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| 视频不存在 | `ERROR` 且无 `videoDetails` | NotFound |
| 需要登录、年龄验证 | `LOGIN_REQUIRED` 等 | NeedsLogin |
| 不可播 | `UNPLAYABLE`、`ERROR` | StreamUnavailable |
| 形状不符、id 不符 | JSON | ApiChanged |
| `@handle` 找不到频道 | `resolve_url` 没有 `browseEndpoint` | NotFound |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| WEB 客户端“视频不可用” | WEB `player` 需要 PO Token 等浏览器证明 | 用 ANDROID 客户端 | 实测 |
| 换代理节点后无法播放 | 媒体地址绑定出口 IP | 接口和媒体走同一出口 | §5 |
| 频道页下载慢 | 旧版解析整页 HTML | 用 `resolve_url` + `player` | §4 |

## 11. 样本清单

2026-09-27 经代理录制（规则 tools/live_cli/lib/src/fixture/rules/youtube.dart；录制脚本额外把清单地址路径里的 `/ip/…/`、`/sig/…/` 换成 `203.0.113.7` 和同形合成值，并在 meta.json 记录）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/youtube_test.dart 直接对照正文。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-browse-live` | 直播频道页（49 个视频渲染器，含已结束的） |
| S02 | `S02-search-p1`、`-p2` | 直播搜索与续页 |
| S03 | `S03-resolve-channel-live`、`-offline`、`S03-resolve-handle` | 频道直播页指向视频/频道；handle → 频道 |
| S04 | `S04-player-live`、`-missing` | ANDROID 播放器：直播；不存在 |
| S05 | `S05-feed-offline` | 频道 RSS（名称） |
| S06 | `danmaku/S06-live` | 直播聊天：`next`（只保留 `conversationBar`）+ 8 次 `get_live_chat`（只保留续页和动作；作者名、频道号换成化名，头像、追踪参数删去），45 秒 21 条新消息（`live_cli danmaku youtube xd_fJRWZuVI --proxy 127.0.0.1:7897 --seconds 45 --record S06-live`） |

普通视频（非直播）的 `player` 样本没有录下：录制工具的防泄漏检查拒绝写入（有一个被替换的值出现在 meta.json 里，没能定位），测试用直播样本改 `isLive` 覆盖“未直播”。

**需要脱敏的字段**：`visitorData`、`heartbeatServerData`、`serializedExperimentFlags`、`botguardData`、`playerAttestationRenderer`；地址参数 `vm`、`cpn`、`plid`、`ei`、`of`、`sig`、`ip`；清单路径里的 IP 和签名。频道、视频的公开信息保留。

## 12. 待确认

1. 付费留言是否换算成醒目留言（§7）。
2. 是否按 HLS 变体提供可选画质。
3. ANDROID 客户端将来是否也要求 PO Token；届时需要备用客户端。
4. 同一频道多场同时直播时，频道房间取哪一场（现在取频道 `/live` 指向的那场）。
