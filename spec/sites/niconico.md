# 平台规格：niconico 生放送（niconico）

会话型平台（docs/adr/0003-platform-batches.md：`live_media` 完成后迁移，会话输入经本地中继）。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`niconico`，显示名 `niconico`。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/niconico/`（W = niconico_watch.dart，SS = niconico_session.dart，ST = niconico_stream.dart，D = niconico_directory.dart，Q = niconico_quality_catalog.dart，L = niconico_link.dart）。样本编号见 §11。
- 状态：**保留**。2026-09-27 本机默认出口实测（2026-09-28 查明本机默认出口经系统层隧道在境外，不是中国大陆直连；中国大陆直连是否需要代理 [待确认]）：最近节目列表、搜索、观看页、观看座位 WebSocket、HLS（LL-HLS、fMP4、AES-128）都能匿名使用。
- 能力：目录（7 个标签页 → 在播节目，分页）、推荐（“一般”标签页）、搜索（在播节目）、详情、取流（HLS 主列表 + 座位租期）、链接解析、弹幕（评论服务器 NDGR，§7）。
- 不提供：时移回放；登录（会员限定、付费节目报 NeedsLogin）。
- **按路径的 Cookie**（§6.3）：HLS 的 Cookie 按路径区分，`StreamLine.headers` 只能带一组；线路带中继配方，由 `live_media` 的 HLS 中继按路径发送（ADR 0033），待真机验证。

---

## 1. 房间身份与链接

节目 id（`lv…`）每场都变，旧版因此只能收藏“这一场”（zh.json `niconico_program_scope`）。v4 用稳定的主播身份：

| 房间 id | 含义 | 观看页 | 证据 |
|---|---|---|---|
| `user/<用户 id>` | 用户（原社区）主播 | `https://live.nicovideo.jp/watch/user/<id>` 返回该用户**最新的节目**：在播时是当前节目，否则是最近结束的节目（HTTP 200，不跳转） | S03-watch-user-live、S03-watch-user-ended |
| `ch<频道号>` | 频道 | `https://live.nicovideo.jp/watch/ch<号>` 同理 | S03-watch-channel |
| `lv<号>` | 没有主播身份的节目（官方节目） | `https://live.nicovideo.jp/watch/lv<号>` | S03-watch-program-live |

- 房间 id 就是观看页路径 `watch/` 之后的部分，所以链接、外部打开都是 `https://live.nicovideo.jp/watch/<房间 id>`。
- 列表和搜索按 `providerType` 换算：`community`（用户节目）→ `user/<programProvider.id 或 supplier.programProviderId>`；`channel` → `socialGroup.id`（`ch…`）；其它 → 节目 id。

| 输入 | 处理 |
|---|---|
| `user/<id>`、`ch<号>`、`lv<号>` | 直接使用；`lv` 再按下行规范化 |
| `https://live.nicovideo.jp/watch/lv<号>`（也收 `sp.live.nicovideo.jp`、`nico.ms/lv<号>`） | 请求观看页，按 `program.supplier.supplierType`（`user`/`channel`）换成 `user/<programProviderId>` 或 `socialGroup.id`；官方节目保留 `lv` |
| `https://live.nicovideo.jp/watch/user/<id>`、`…/watch/ch<号>` | 直接取 |
| 分享文本 | 抽出第一个 URL |

- 旧版只认 `https://live.nicovideo.jp/watch/lv…`（L:4-15；W:57-66）。
- 不存在：观看页 HTTP 404（S03-watch-notfound，`lv1`）→ NotFound。

## 2. 目录

### 2.1 标签页

`GET https://live.nicovideo.jp/front/api/pages/recent/v1/programs?tab=<tab>&offset=<页-1>&sortOrder=recentDesc`（D:26-36）。标签页固定 7 个（D:12）：`common` 一般、`try` やってみた、`live` ゲーム（不是“全部直播”）、`req` 動画紹介、`face` 顔出し、`totu` 凸待ち、`vtuber` VTuber。其它值（如 `official`）服务端当作 `common`。v4 一级分类 `nicolive`，推荐 = `common`。

### 2.2 列表

- 响应 `{meta: {statusCode: 200, errorCode: "OK", totalCount}, data: [...]}`（S01-recent-common-p1）；每页最多 70 条。`meta` 不是 200/OK → ApiChanged。
- 翻页：`offset` 是页号减 1；`页码 × 70 < totalCount` 且本页非空时还有下一页（D:77；S01-recent-req-p1 只有 10 条，末页）。
- 卡片：房间 id 按 §1 换算；标题 `title`；主播 `programProvider.name`（缺时 `socialGroup.name`）；头像 `programProvider.icon`（缺时 `socialGroup.thumbnailUrl`）；封面 `listingThumbnail`；开播 `beginAt`（毫秒）；人数：`statistics.watchCount` 是**累计来场数**，不是在线人数（zh.json `audience_niconico_detail`），v4 放在累计口径。只收 `liveCycle == "ON_AIR"` 的行。
- 同一主播在一页里只出现一次（按房间 id 去重）。

## 3. 搜索

- `GET https://live.nicovideo.jp/front/api/pages/search/v1/programs?keyword=<kw>&column=main&status=onair&page=<n>&disableGrouping=true`（D:40-50）。
- 响应 `data.programs[]`、`data.totalCount`；每页最多 40 条；`页码 × 40 < totalCount` 时有下一页（S02-search）。
- 行字段：`nicoliveProgramId`、`title`、`providerType`、`supplier{name, programProviderId, icons.uri150x150}`、`listingThumbnail`、`beginTime`（秒）、`statistics.watchCount`、`status`。只收 `ON_AIR`。

## 4. 房间详情（观看页）

- `GET https://live.nicovideo.jp/watch/<房间 id>`；页面里 `<script id="embedded-data" data-props="…">` 是 HTML 转义的 JSON（W:74-88）。没有它 → ApiChanged；HTTP 404 → NotFound。
- `program`：`nicoliveProgramId`、`title`、`status`（`ON_AIR` → 直播；`ENDED`、`RELEASED`（预约中）→ 未开播；其它 → ApiChanged）、`supplier{name, supplierType, programProviderId, icons.uri150x150}`、`screenshot.urlSet`（在播截图）、`thumbnail`、`beginTime`、`description`（HTML）、`statistics.watchCount`（累计）。
- 请求的是 `lv` 房间时，返回的节目 id 必须相同。
- 可看性：`userProgramWatch.isCountryRestrictionTarget` → RegionBlocked；`programWatch.condition.needLogin` → NeedsLogin；`userProgramWatch.canWatch != true` → NeedsLogin（W:120-130）。付费频道节目在匿名下可能 `canWatch: true`（试看，`payment: "Ticket"`，S03-watch-channel）。
- 座位地址：`site.relive.webSocketUrl`（`wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/<数字>?audience_token=<匿名令牌>`）加 `frontend_id=<site.frontendId>`（W:140-162）。只在直播时使用。
- 详情字段：封面优先截图（`middle`，缺时 `large`），否则缩略图；简介去掉 HTML 标签；弹幕参数 `danmakuKeys = {programId}`。

## 5. 画质与线路

- 座位请求 `quality: "abr"`，返回多码率主列表（S04-seat；实测 480p 1.5 Mbps、288p 480 kbps 两个视频变体，单独的 192 kbps 音频，`CODECS=avc1…,mp4a…`）。`availableQualities` 还有 `1.5Mbps480p30fps`、`480kbps288p30fps`、`audio_high`、`audio_only`。
- v4 只提供一档 `abr`“自动”，交给播放器自适应；按档切换需要在座位上发 `changeStream`，[待确认]是否需要。
- 线路一条，id `dlive`（`livedelivery.dlive.nicovideo.jp`）。

## 6. 取流

### 6.1 流程

1. 读观看页（§4）；不在播 → StreamUnavailable；不可看 → 对应错误。
2. 打开座位（§6.2），等到 `seat` 和 `stream` 两条消息（20 秒内，否则 NetworkFailure）。
3. 返回一条 HLS 线路：地址 = `stream.uri`（主列表）；请求头带主列表路径的 Cookie、`Origin`/`Referer`；租期见 §6.4。

### 6.2 座位 WebSocket

- 连接座位地址，请求头 `Origin: https://live.nicovideo.jp`（SS:130-135）。**只收文本帧**：二进制帧会被以 1003“This WebSocket only supports text frames”关闭（2026-09-27 实测）。
- 发送 `{"type":"startWatching","data":{"stream":{"quality":"abr","protocol":"hls","latency":"high","chasePlay":false},"room":{"protocol":"webSocket","commentable":false},"reconnect":false}}`（SS:147-155）。
- 服务端依次发：`serverTime`、`seat{keepIntervalSec: 30}`、`stream{uri, syncUri, quality, availableQualities, protocol: "hls", cookies[]}`、`schedule`、`messageServer{viewUri, vposBaseTime}`、`akashicMessageServer`、`statistics{viewers, comments, adPoints, giftPoints}`（S04-seat）。
- 保活：每 `keepIntervalSec` 秒发 `{"type":"keepSeat"}`；收到 `{"type":"ping"}` 回 `{"type":"pong"}` 并补一次 `keepSeat`（SS:186-199,224-226）。实测 ping 约每 30 秒一次。
- 结束：`disconnect{reason}`（如节目结束 `END_PROGRAM`）或 `error{code}`；`error` 的 `NO_PERMISSION`/`NOT_PLAYABLE`/`TICKET_REQUIRED` → NeedsLogin，`TOO_MANY_CONNECTIONS`/`CONNECT_ERROR` → RateLimited，其它 → StreamUnavailable。
- 再次收到 `stream` 时替换授权（旧版同样处理，SS:207-212）。

### 6.3 按路径区分的 Cookie（播放层缺口）

- `stream.cookies[]` 每项 `{name, value, domain: "nicovideo.jp", path, secure, expires?}`：`session`（`/hls/keys/<id>`）、以及三组同名的 `CloudFront-Policy`/`CloudFront-Signature`/`CloudFront-Key-Pair-Id`，路径分别是 `/hls/playlists/<id>/<流>`、`/hls/segments/<id>/video`、`/hls/segments/<id>/audio`、`/hls/keys/<id>/<流>`（S04-seat）。
- **每个请求只能带路径匹配的那一组**：把所有 Cookie 合成一个请求头时主列表返回 403；只带主列表路径的那组时 200（2026-09-27 实测）。分片和密钥各要自己的那组。
- 媒体是 LL-HLS（`EXT-X-PART`）、fMP4（`.cmfv`，`EXT-X-MAP`）、AES-128 加密（`EXT-X-KEY` 指向 `/hls/keys/…`）。
- v4：线路的 `cookie` 请求头只能放主列表那组（探针用它拿主列表）。完整的 Cookie 由适配器按线路提供：`cookieFile(line)` 给出 Netscape Cookie 文件内容（每行 `.nicovideo.jp TRUE <path> TRUE <expires> <name> <value>`），`grantFor(line)` 给出结构化的授权。播放层需要其一：
  1. mpv 设 `cookies=yes`、`cookies-file=<临时文件>`（FFmpeg 的 HLS 读取器按路径匹配 Cookie 存储）；或
  2. `live_media` 的 HLS 中继按请求路径加 Cookie（PLAN 的 SRC-2 第 3 项，尚未实现）。
  v4 选第 2 种（ADR 0033）：线路带 `hlsRelay: HlsRelayRecipe(cookies: …)`，读座位当前的授权，中继给每个请求只带路径匹配的那组。实际播放待真实网络和真机验证。

### 6.4 座位租期（用现有的 `Lease` 表达保活）

- 座位关闭后，密钥服务器在一分钟内拒发新密钥（关闭 60 秒后新密钥 403，已开始的播放列表和分片仍能取到，2026-09-27 实测），所以播放期间座位必须一直开着。
- v4 的做法：适配器按节目持有座位。`streams` 返回的线路 `Lease(refreshAt = 现在 + 60 秒, expiresAt = 现在 + 150 秒, cutsConnection = false)`。
  - 播放层对 `cutsConnection = false` 的线路在 `refreshAt` 预取（重新调用 `streams`，playback.md SRC-6），预取每 60 秒一次；
  - 适配器收到同一节目的 `streams` 调用时复用已开的座位，并把关闭时刻推迟到 150 秒后；
  - 播放停止后不再预取，座位在 150 秒内自动关闭。录制同理（共用同一个座位）。
- 座位先结束（节目结束、服务端断开）时适配器丢弃它；下一次 `streams` 读观看页，节目已结束则报 StreamUnavailable。
- 旧版把座位交给播放器和录制器各自持有（SS:14-20；Q:95-143）；v4 由适配器持有，播放层不接触 WebSocket 和 Cookie 之外的会话细节（playback.md SRC-9）。

### 6.5 播放层还需要确认的

1. 预取失败（网络）时座位是否会在 150 秒内关闭——预取 10 秒后重试（SRC-6），不会超过租期。
2. 同一节目的播放和录制共用座位，两者的预取都会续期。录制层（`live_record`）当前只处理 FLV；HLS 录制加上 Cookie 需求是另一个缺口。
3. 座位下发新的 `stream`（换地址）时，正在播放的旧地址怎么办 [待确认，未观察到]。

## 7. 弹幕

评论服务器（NDGR）走 HTTP，但它的地址只在座位上给出（S04-seat 的 `messageServer`）。

### 7.1 座位

弹幕连接器在后台 isolate，自己开一个座位：先取观看页（§4）的 `webSocketUrl`（`NiconicoSite.seatSocket`；不在播 → 结束，原因 `offline`；会员限定等 → `credentials`），再按 §6.2 开座位、应答 `ping`、定时 `keepSeat`。座位服务器**只收文本帧**（发二进制帧会被断开：`1003 This WebSocket only supports text frames`，2026-09-28 实测），`live_danmaku` 的 `DanmakuSocket.send` 只发二进制帧，所以座位用 `live_core` 的实现，经 `dart:io` 走 `niconico` 的平台路由（`IoDanmakuTransport.proxy`）。座位给出 `messageServer.viewUri` 后开始读评论，最多等 10 秒。

### 7.2 评论服务器

全部是长度前缀（varint）的 protobuf 序列（S07-live）：

1. `GET <viewUri>?at=now` → 一条 `{4: next{1: at}}`。
2. `GET <viewUri>?at=<at>`（长轮询，实测 12–30 秒才回答）→ 若干条目：`1: segment{1: from, 2: until, 3: uri}`（进行中和下一个 16 秒窗口）、`3: previous{…}`（已结束的窗口）、`2: backward{until, backward_uri, snapshot_uri}`（历史，不用）、`4: next{at}`。时间是 `{1: 秒, 2: 纳秒}`。
3. `GET <segment.uri>`：窗口进行中时，回答一直持续到窗口结束（`until`）；内容是 `ChunkedMessage` 序列：`1: meta{1: id, 2: at, 3: origin}`，以及 `2: message{1: chat{1: content, 2: name, 3: vpos, 5: raw_user_id, 6: hashed_user_id, 7: modifier, 8: no}, 23: 系统通知, …}` 或 `4: state{1: statistics{1: viewers, 2: comments, 3: adPoints, 4: giftPoints}}`。
4. 以 `next.at` 回到第 2 步。

### 7.3 解码

- `chat` → 聊天行：消息 id = `niconico:<meta.id>`；时间 `meta.at`；用户 id = `hashed_user_id`（匿名用户 `a:…`），没有时用 `raw_user_id`；昵称 `name`（匿名为空）。颜色、位置（`modifier`）本阶段不用，[待确认] 颜色表。
- `statistics.viewers` → 在线人数。
- 系统通知（如“「アニメ」が好きな1人が来場しました”）、礼物、广告、信号不解码。

### 7.4 读取与节奏

- 第一次 `view` 回答里已结束的窗口（`previous`）是历史，不读；之后每个新出现的进行中窗口各读一次（并发，窗口读取的超时 = 距 `until` 的时间 + 20 秒；`view` 超时 60 秒）。
- 窗口的回答在窗口结束时才完整（`LiveHttp` 不流式读取），所以评论晚一个窗口（约 16 秒）到达；连接器按每条的 `meta.at` 相对窗口开始的偏移依次发出，保持原来的节奏，整体延迟约 16 秒（与 `latency: high` 的 HLS 延迟相近）。
- 失败：`view` 连续失败 6 次或座位断开 → 重开座位（连续 6 次失败结束）；座位断开原因含 `END_PROGRAM` → 结束，原因 `offline`。

## 8. 登录与 Cookie

不支持账号登录。座位和取流全部匿名；会员限定、付费节目按 §4 报错。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| 观看页 404 | 状态码 | NotFound |
| 列表 `meta` 不是 200/OK、观看页没有 embedded-data、未知 `status` | JSON | ApiChanged |
| 地区限制 | `isCountryRestrictionTarget` | RegionBlocked |
| 需要登录、不能看 | `needLogin`、`canWatch` | NeedsLogin |
| 座位 20 秒内没有 `seat`/`stream` | 超时 | NetworkFailure |
| 座位 `error`/`disconnect` | 消息 | 见 §6.2 |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 收藏的节目下一场就失效 | 用节目 id 当身份 | 用 `watch/user/<id>`、`watch/ch<号>` 的主播身份 | §1 |
| 主列表 403 | 把所有路径的 Cookie 合进一个请求头 | 按路径发 Cookie | §6.3 |
| 播着播着解不了密 | 座位关了，密钥服务器拒发新密钥 | 按租期续座位 | §6.4 |
| 座位立刻被关 | 发了二进制帧 | 只发文本帧 | §6.2 |

## 11. 样本清单

2026-09-27 本机默认出口录制（规则 tools/live_cli/lib/src/fixture/rules/niconico.dart）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/niconico_test.dart 直接对照正文。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-recent-common-p1`、`-req-p1`、`-face-p1` | 标签页列表、`totalCount` 翻页、频道节目 |
| S02 | `S02-search` | 在播搜索 |
| S03 | `S03-watch-user-live`、`-program-live`、`-user-ended`、`-channel`、`-notfound` | 观看页：用户在播、同一节目按 `lv` 访问、用户最近节目已结束、频道（付费试看）、404 |
| S04 | `seat/S04-seat`（`frames.jsonl`，与弹幕帧同格式） | 座位会话：`startWatching`、`seat`、`stream`（Cookie）、`messageServer`、`statistics`、`ping`/`pong`/`keepSeat`，约 65 秒 |
| S07 | `danmaku/S07-live` | 评论服务器（`live_cli danmaku niconico lv351482215 --seconds 75 --record S07-live`）：3 次 `view`、4 个进行中窗口，15 条评论和在线人数；观看页帧删去，座位不经 `DanmakuTransport`、没有录入（测试用 S04-seat 回放座位） |

`seat/S04-seat` 不是 `live_cli fixture` 录的（该工具只录 HTTP），由本次迁移时的录制脚本写成与 `live_cli danmaku --record` 相同的帧格式，脚本在写入前检查原值已全部消失。

**需要脱敏的字段**：观看页的匿名 `audience_token`（座位地址里和 `audienceToken`）、`csrfToken`、`nicosid`；列表里的广告赞助人 `nicoad.userName`/`userIcon`；座位帧里 `stream.cookies[].value`、`messageServer`/`akashicMessageServer` 的 `viewUri` 令牌、握手地址的 `audience_token`；评论服务器路径里的令牌（`/api/view/v4/…`、`/data/{segment,backward,snapshot}/v4/…`，地址和 protobuf 回答里都有，换成等长同形值）、评论作者 `name`、`raw_user_id`、`hashed_user_id`（重建 protobuf）。主播公开信息保留。

## 12. 待确认

1. 播放层按路径发 Cookie 的实现方式（§6.3）。
2. 评论颜色、位置（`modifier`）和礼物（§7.3）。
3. `changeStream` 按档切换画质。
4. 付费频道试看的时长和结束时的座位消息。
5. 座位中途换 `stream` 地址时播放器的处理。
