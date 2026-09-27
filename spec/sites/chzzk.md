# 平台规格：chzzk（CHZZK，韩国 NAVER）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`chzzk`（legacy/lib/core/sites.dart:61），显示名 `CHZZK`（legacy/assets/translations/zh.json `site_chzzk`）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/chzzk/`（简写 A = chzzk_api.dart，S = chzzk_site.dart，L = chzzk_link.dart），其它旧代码写全路径（相对 `legacy/`）。样本编号见 §11。
- 状态：**保留**。2026-09-27 实测：接口直连（中国大陆）和经代理都能访问，媒体走 `livecloud.akamaized.net`，直连可拉；公开目录、搜索、详情、取流、弹幕都不需要登录。不满足 ADR 0003 的任何下线条件。
- 能力：目录（分类 → 分区房间，另有全站热门作推荐）、搜索（频道，含未开播）、详情、取流（HLS，按主播档位选变体）、弹幕（WebSocket，匿名只读）。
- 不提供：登录（成人直播需要登录并完成成人认证，v4 不做，报 NeedsLogin）；时光机（回看）；付费直播（`paidLive`）。

---

## 1. 房间身份与链接

**规范身份**：频道 id `channelId`，32 位小写十六进制（L:13-15；A:409-413）。一个主播一个频道，直播 id（`liveId`）每场都变，不作为身份。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯 id | `af3323d30e11ae42c39d7203c7e07fa2` | 忽略大小写，转小写 | L:14 |
| 直播页 | `https://chzzk.naver.com/live/<id>` | 主机必须是 `chzzk.naver.com`，路径两段且第一段是 `live` | L:4-16 |
| 频道页 | `https://chzzk.naver.com/<id>` | 路径只有一段 32 位十六进制 id 时接受。旧版不接受，v4 新增（频道页就是分享主播时的常见链接） | — |
| 分享文本 | 链接前后夹有文字 | 抽出第一个 URL 再按上两行处理 | legacy/lib/common/utils/live_url_tool.dart:113 |

- 其它主机（`m.chzzk.naver.com`、`game.naver.com`）不认，返回“不是本平台”。
- 频道不存在：`/service/v1/channels/<id>` 仍返回 HTTP 200，`content.channelId` 为 null、`channelName` 为 `(알 수 없음)`（S05-channel-notfound），映射为 NotFound。
- 外部打开：`https://chzzk.naver.com/live/<id>`（L:18-22；legacy/lib/modules/live_play/services/room_external_opener.dart:85-89）。

---

## 2. 目录

所有接口在 `https://api.chzzk.naver.com`，响应顶层是 `{code, message, content}`，`code == 200` 才算成功（A:182-194）。请求头见 §6.3。

### 2.1 分类

- 旧版只有一个写死的“公开目录”分区，内容就是全站热门（S:114-131）。v4 改为平台真实的分类。
- 请求：GET `/service/v1/categories/live?size=50`；翻页把上一页的 `content.page.next`（`concurrentUserCount`、`openLiveCount`、`categoryId` 三个字段）原样作为查询参数（S01-categories-p1～p4）。`next` 为 null 时结束。
- 列表按“正在直播的观众数”降序，2026-09-27 共 9 页约 430 个分区，后几页每个分区只有 1 场直播。v4 最多取 **4 页（200 个分区）**，覆盖所有有一定观众的分区，也把一次打开发现页的请求数限制在 4 个。
- 字段：`categoryType`（`GAME`、`ENTERTAINMENT`、`SPORTS`、`ETC` 等）、`categoryId`（如 `League_of_Legends`）、`categoryValue`（显示名，韩文）、`posterImageUrl`、`openLiveCount`、`concurrentUserCount`。
- 映射：`categoryType` 是一级分类（v4 `Category`，名称用固定对照：`GAME` 游戏、`ENTERTAINMENT` 娱乐、`SPORTS` 体育、`ETC` 其它，未知类型原样显示），`categoryId` 是分区（`Area`，`categoryId` 字段存 `categoryType`）。一级分类按首次出现的顺序，分区保持接口顺序。

### 2.2 分区房间

- 请求：GET `/service/v2/categories/<categoryType>/<categoryId>/lives?size=30`；下一页把 `content.page.next`（`concurrentUserCount`、`liveId`）作为查询参数（S02-category-lives-p1、S02-category-lives-p2）。
- `next` 为 null，或本页 `data` 为空，即最后一页。不存在的分区返回 `data: []`、`next: null`（S02-category-lives-empty）。
- 条目字段同 §2.3。列表条目一律视为直播中。

### 2.3 推荐（全站热门）

- 请求：GET `/service/v1/lives?size=30`，翻页同 §2.2（S03-lives-p1、S03-lives-p2；A:198-221）。
- 旧版认为游标“包含边界”：翻页时多取 1 条再去掉与上一页末尾相同的 `liveId`（A:201-211）。2026-09-27 复核：`next` 就是本页最后一条的 `concurrentUserCount` 和 `liveId`，服务端从它之后开始，不含它（S03-lives-p1 末条 `liveId` 21334270 等于 `next.liveId`，S03-lives-p2 首条是 21332867）。v4 不多取；保险起见仍丢掉 `liveId` 等于游标 `liveId` 的条目，同一页里重复的频道只留第一个（S:152-157）。
- 条目字段：

| 字段 | 含义 |
|---|---|
| `channel.channelId` | 房间 id |
| `channel.channelName` | 主播名 |
| `channel.channelImageUrl` | 头像 |
| `liveTitle` | 标题 |
| `liveImageUrl` | 封面模板，含 `{type}`，替换成 `480`（A:351-359）；为 null 时用 `defaultThumbnailImageUrl`，都没有则无封面（成人直播和部分直播两者都是 null） |
| `liveCategoryValue` | 分区显示名；为空字符串时没有分区 |
| `concurrentUserCount` | 同时在线人数，**只有 `cvExposure == true` 时才显示**（A:346-349；legacy/lib/common/models/live_room.dart:117-122） |
| `adult` | 成人直播。列表照常显示，进房取流报 NeedsLogin（§9） |
| `blindType` | `ABROAD` 表示海外不可看，进房取流报 RegionBlocked（§9） |
| `openDate` | 开播时间，`yyyy-MM-dd HH:mm:ss`，首尔时间（UTC+9） |

---

## 3. 搜索

- 请求：GET `/service/v1/search/channels?keyword=<kw>&offset=<n>&size=20`（A:223-240）。
- 结果 `content.data[].channel`：`channelId`、`channelName`、`channelImageUrl`、`channelDescription`、`followerCount`、`openLive`。
- 卡片：标题用频道名（频道搜索没有直播标题），封面用头像，状态按 `openLive`（true 直播中，否则未开播）。能力是“直播与未开播”（legacy/lib/modules/search/search_capability.dart:44-48）。
- 分页：`offset` 从 0 开始、每页 20；`content.page` 为 null（S04-search-empty）或本页为空时结束；有 `page.next` 时下一页 `offset` 取 `next.offset`（S04-search-channels：20 条，`next.offset == 20`）。结果不足 20 条时服务端也可能给 `next`（关键词“배틀그라운드”6 条仍给 `next.offset: 20`），下一页返回空，靠空页结束。
- 旧版对超过 100 个字符的关键词直接报错（A:230）。v4 截断到 100 个字符再请求。
- `/service/v1/search/lives` 也存在（只返回直播），v4 不用：频道搜索能找到未开播的主播，关注场景更需要。

---

## 4. 房间详情

两次请求（A:242-295）：

1. GET `/service/v1/channels/<id>`：主播名、头像、简介 `channelDescription`、粉丝数 `followerCount`、是否在播 `openLive`。`channelId` 为 null 即 NotFound（S05-channel-notfound）。
2. GET `/service/v3.1/channels/<id>/live-detail`：最近一场直播。

- **必须用 v3.1**。v2 对海外受限的直播直接返回 HTTP 500、`code 9004`（해외 시청 불가능한 컨텐츠 입니다），整页失败；v3.1 返回完整字段并置 `krOnlyViewing`（A:254-258；legacy/test/chzzk_live_detail_test.dart；01-sites.md ⑤ CHZZK 行，提交 5a33808b）。
- 不存在的频道：v3.1 返回 HTTP 404、`{"code":404,"message":"채널이 존재하지 않습니다."}`（S06-live-detail-notfound）→ NotFound。
- `content` 为 null（从没直播过的频道）→ 未开播，卡片只用频道信息（S:258-259）。

**直播状态**（A:261-265）

| `status` | 状态 |
|---|---|
| `OPEN` | 直播中（S06-live-detail-live、-region、-adult） |
| `CLOSE`（旧版也接受 `CLOSED`） | 未开播（S06-live-detail-offline） |
| 其它 | ApiChanged（ADR 0010 修订：未知状态不当作未开播） |

CHZZK 没有回放轮播，不产生 replay。

**字段**

| v4 | 来源 |
|---|---|
| 标题 | `liveTitle`；空时用主播名（A:279） |
| 主播名、头像 | live-detail 的 `channel`，缺失时用频道接口 |
| 封面 | 同 §2.3 |
| 分区 | `liveCategoryValue`，空时 `liveCategory` |
| 人数 | `concurrentUserCount` 作为在线人数，仅 `cvExposure == true`；`accumulateCount` 是累计观看，大于 0 时作为累计（未开播的最近一场也有，S06-live-detail-offline 为 161） |
| 开播时间 | `openDate`，首尔时间 |
| 简介 | 频道接口的 `channelDescription` |
| 原站链接 | `https://chzzk.naver.com/live/<id>` |
| 弹幕参数 | `chatChannelId`（直播中才有；受限、成人直播为 null） |

**附加信息**（v4 在详情里记录，取流时用来报错，§9）：`adult`、`krOnlyViewing`、`blindType`、`userAdultStatus`（匿名为 `NOT_LOGIN_USER`）、`livePlaybackJson`（取流数据，JSON 字符串）。

---

## 5. 画质与线路

### 5.1 数据来源

- `livePlaybackJson` 是 JSON 字符串，`media[]` 每项有 `mediaId`、`protocol`、`path`（HLS 主播放列表地址）和 `encodingTrack[]`（S06-live-detail-live）。
- 只用 `protocol == HLS` 且 `mediaId` 是 `HLS` 或 `LLHLS` 的两项（A:324-344）。`HLS` 是普通延迟，`LLHLS` 是低延迟（`latency: lowLatency`）。
- 画质以主播放列表为准，不以 `encodingTrack` 为准：变体地址带路径令牌，只有主列表里有（S07-master-hls）。所以取流要再请求 1～2 次主列表（S:214-253）。

### 5.2 画质

- 每个 `#EXT-X-STREAM-INF` 是一个变体：`BANDWIDTH`、`RESOLUTION`、`FRAME-RATE`、`CODECS`。
- 画质 id 是 `<高>p`，帧率 ≥ 50 时加 `60`：`1080p60`、`720p60`、`480p`、`360p`、`144p`（S:223-236）。标签同 id。
- 排序：高度优先、带宽其次，降序（S:233、S:250）。没有分辨率的变体（纯音频）丢弃。
- 两个主列表的同名画质合并为一个画质（S:231-235）。
- 样本：1080p60（8192 kbps，`avoidReencoding` 即原画透传）、720p60、480p、360p、144p；编码全是 `avc1`（H.264），音频 AAC（S07-master-hls、S07-master-llhls）。

### 5.3 线路

- 一个画质有两条线路：`HLS` 在前，`LLHLS` 在后（`livePlaybackJson` 的顺序）。线路身份是 `mediaId`。
- 格式 HLS；编码取变体的 `CODECS`（`avc1` → avc，`hvc1`/`hev1` → hevc）。
- 服务端不会降档：选中的变体就是实际画质，确认画质 = 请求画质。

---

## 6. 取流

### 6.1 流程

1. 从详情（或重新请求 live-detail）拿 `livePlaybackJson`；没有时按 §9 报错。
2. 对 `HLS`、`LLHLS` 两个主列表各请求一次（请求头 §6.3），解析变体。
3. 按请求画质取两条线路；请求的画质不存在时用最高画质。

### 6.2 令牌与租期

- 主列表地址带 Akamai 令牌 `hdnts=st=<签发>~exp=<到期>~acl=…~hmac=…`；变体地址的路径里带 `hdntl=exp=<到期>~acl=…~data=hdntl~hmac=…`（S07-master-hls）。
- 实测寿命约 17 小时（`exp − st` = 61210 s，S06-live-detail-live；变体 `exp` 晚十几秒）。
- 租期（v4）：`expiresAt` = 变体路径 `hdntl` 的 `exp`（没有时用主列表的 `exp`）；`refreshAt` = 到期前 10 分钟；`cutsConnection = true`：HLS 每个分片都是新请求，令牌过期后新分片会被拒绝 [待确认：没有超过 17 小时的连续播放记录]。
- 旧版没有租期和续期，只在失败后重新取详情（S:310-320）。

### 6.3 请求头

- API：`User-Agent`（桌面 Chrome）、`Accept: application/json, text/plain, */*`、`Origin: https://chzzk.naver.com`、`Referer: https://chzzk.naver.com/`（A:98-106）。2026-09-27 复核：不带 UA 也能取到（接口不校验），但保持浏览器请求头。
- 媒体：`User-Agent` 和 `Referer: https://chzzk.naver.com/`（A:107；legacy/lib/player/core/playback_header_resolver.dart:174-176）。
- 地区：API 和媒体从中国大陆直连都能用（2026-09-27）；`krOnlyViewing` 的直播无论出口都不给播放数据（§9）。

### 6.4 媒体实况（2026-09-27）

- 视频 H.264（`avc1.640028` 等），音频 AAC。HLS 分片是 fMP4：`#EXT-X-MAP` 初始化段（`.m4s`）加 2 秒的 `.m4v` 分片，文件名是相对地址，令牌随变体路径里的 `hdntl` 段继承；低延迟列表另有 `#EXT-X-PART-INF`、`CAN-BLOCK-RELOAD`（2026-09-27 实测）。
- 没有 FLV，也就没有旧版中继要处理的 FLV codec 12（HEVC）问题。
- `live_cli probe chzzk <直播页>`：解析 → 详情 → 取流（5 个画质、2 条线路）→ 读到 HLS 播放列表，通过（2026-09-27，直连）。

---

## 7. 弹幕

旧版没有 CHZZK 弹幕（`getDanmaku()` 返回 EmptyDanmaku，S:80-81）。以下协议来自 2026-09-27 实测（fixtures/chzzk/danmaku/S09-live）。

### 7.1 凭据

- GET `https://comm-api.game.naver.com/nng_main/v1/chats/access-token?channelId=<chatChannelId>&chatType=STREAMING`，匿名即可，返回 `content.accessToken`、`content.extraToken`（S08-chat-token）。
- `chatChannelId` 来自 live-detail（§4）；为 null 时（未开播、受限、成人）不连接，报 `credentials`。

### 7.2 连接

- 地址：`wss://kr-ss<n>.chat.naver.com/chat`，`n = (chatChannelId 各字符码之和 % 9) + 1`（网页端的算法；实测 `N2lpu9` → `kr-ss1`）。只有这一个地址。
- 握手请求头：`Origin: https://chzzk.naver.com`、桌面 UA。
- 消息是 JSON 文本。客户端发二进制帧（内容是 UTF-8 JSON）服务端也接受（实测），服务端回文本帧。
- 加入：发 `{"ver":"3","cmd":100,"svcid":"game","cid":<chatChannelId>,"bdy":{"uid":null,"devType":2001,"accTkn":<accessToken>,"auth":"READ"},"tid":1}`。回 `cmd 10100`、`retCode 0` 即加入成功，`bdy.sid` 是会话 id。`retCode != 0` 视为被拒。
- 加入后发一次 `{"ver":"3","cmd":5101,"svcid":"game","cid":…,"sid":…,"bdy":{"recentMessageCount":50},"tid":2}` 拉最近的聊天，回 `cmd 15101`。

### 7.3 心跳

- 客户端每 20 s 发 `{"ver":"3","cmd":0}`，服务端回 `{"ver":"2","cmd":10000}`（实测）。
- 服务端发 `cmd 0` 时客户端回 `{"ver":"3","cmd":10000}`。

### 7.4 消息

| cmd | 含义 | 处理 |
|---|---|---|
| 93101 | 聊天，`bdy` 是数组 | 每项：`msg` 文本，`profile`（JSON 字符串）的 `nickname`，`uid`，`msgTime`（毫秒），`msgTypeCode`（1 文本），`msgStatusType`（`NORMAL`；`HIDDEN`/`BLIND` 丢弃），`mbrCnt` 同时在线人数（作为在线人数上报，每帧取最后一个） |
| 15101 | 最近聊天，`bdy.messageList` | 字段名不同：`content`、`userId`、`messageTime`、`memberCount`、`messageTypeCode`、`messageStatusType`，其余同上。只用来补齐进房前的聊天 |
| 93102 | 捐赠（치즈） | `extras`（JSON 字符串）的 `payAmount` 是治즈数量（1 치즈 = 1 韩元）。上报为礼物“치즈”×数量（价值单位不是人民币，不填元），有文本时另报一条聊天。匿名 `extras.isAnonymous == true` 时昵称为“匿名” |
| 10000 | 心跳回应 | 忽略 |
| 其它（93006 事件、94008 屏蔽等） | — | 忽略 |

- 消息 id：`chzzk:<uid>:<msgTime>`（平台不给单独的消息 id）。
- 昵称颜色 `streamingProperty.nicknameColor.colorCode` 是平台色板码（`CC000` 等），不是 RGB，v4 不用；文字一律白色。
- 表情以 `{:name:}` 形式留在文本里，`extras.emojis` 给出图片地址；v4 暂不渲染（与其它平台一致）。

### 7.5 重连

- 共用 SocketConnector 的规则（spec/modules/danmaku.md CONN-3）。被拒（`retCode != 0`）后重新取 accessToken。

---

## 8. 登录与 Cookie

- v4 不支持 CHZZK 登录。成人直播（`adult == true`，匿名 `userAdultStatus == NOT_LOGIN_USER`，`livePlaybackJson` 为 null）报 NeedsLogin。
- 以后若支持：网页 Cookie `NID_AUT`、`NID_SES`，并且账号要完成成人认证 [待确认]。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | A:168-176 | NetworkFailure |
| HTTP 429 | A:173 | RateLimited |
| HTTP 401/403（接口） | A:171 | RiskControl |
| 频道接口 `channelId` 为 null；live-detail HTTP 404 | S05-channel-notfound、S06-live-detail-notfound | NotFound |
| 顶层 `code != 200`（HTTP 200） | A:189 | ApiChanged |
| 结构不符（缺 `content`、`status` 取值未知、`livePlaybackJson` 不是 JSON） | A:261-265, 324-332 | ApiChanged |
| 直播中，`krOnlyViewing == true` 或 `blindType == ABROAD`，没有播放数据 | S06-live-detail-region；S:264-265 | 详情照常返回（直播中）；取流报 **RegionBlocked** |
| 直播中，`adult == true` 且没有播放数据 | S06-live-detail-adult；S:266-267 | 取流报 **NeedsLogin** |
| 直播中，没有播放数据，也不是上两种（付费直播等） | — | StreamUnavailable |
| 未开播时取流 | — | StreamUnavailable |
| 主列表请求失败（403/404） | — | 该线路跳过；两条都失败时 StreamUnavailable（403 为 RiskControl） |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-CHZZK-001 | 海外受限的直播整页失败 | v2 live-detail 对这类直播返回 500/9004 | 用 v3.1，按 `krOnlyViewing` 报地区限制 | A:254-258；5a33808b；legacy/test/chzzk_live_detail_test.dart |
| REG-CHZZK-002 | 在线人数显示了平台要求隐藏的值 | 没看 `cvExposure` | 只有 `cvExposure == true` 才用 `concurrentUserCount` | A:346-349 |
| REG-CHZZK-003 | 封面是模板地址，图片加载失败 | `liveImageUrl` 含 `{type}` | 替换成 480 | A:351-359 |
| REG-CHZZK-004 | 发现页只有一个“公开目录” | 旧版没接分类接口 | 用 `categories/live` 和 `v2/categories/.../lives` | S:114-131；§2 |

---

## 11. 样本清单

2026-09-27 直连录制（`live_cli fixture capture`，规则 tools/live_cli/lib/src/fixture/rules/chzzk.dart）。旧应用已归档、不能再运行（ADR 0016），所以没有旧版期望值 `expected.json`；v4 测试（packages/live_core/test/sites/chzzk_test.dart）直接对照样本正文的字段断言。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | `categories/live` | `S01-categories-p1`～`S01-categories-p4`（按 `next` 连续翻 4 页） |
| S02 | `v2/categories/<type>/<id>/lives` | `S02-category-lives-p1`、`S02-category-lives-p2`（英雄联盟）、`S02-category-lives-empty`（不存在的分区） |
| S03 | `v1/lives` | `S03-lives-p1`、`S03-lives-p2` |
| S04 | `search/channels` | `S04-search-channels`（含直播中和未开播）、`S04-search-empty` |
| S05 | `v1/channels/<id>` | `S05-channel-live`、`S05-channel-offline`、`S05-channel-notfound` |
| S06 | `v3.1/.../live-detail` | `S06-live-detail-live`、`-offline`、`-region`（`krOnlyViewing`、`blindType: ABROAD`）、`-adult`（`NOT_LOGIN_USER`）、`-notfound`（404） |
| S07 | HLS 主列表 | `S07-master-hls`、`S07-master-llhls`（与 S06-live-detail-live 同一场直播，另一次签发） |
| S08 | 弹幕 accessToken | `S08-chat-token` |
| S09 | 弹幕帧 | `fixtures/chzzk/danmaku/S09-live`（`live_cli danmaku --record`） |

**缺**：从未直播过的频道（live-detail `content: null`）；付费直播；捐赠消息 93102（录制时没有出现，由单元测试按 §7.4 构造）。

**需要脱敏的字段**
- 媒体地址：Akamai 令牌里的 `hmac`（主列表查询串 `hdnts` 和变体路径 `hdntl` 两处，用文本规则 `hmac=<hex>`），保留 `st`、`exp`；查询参数 `vp`。
- 弹幕凭据：`accessToken`、`extraToken`；弹幕帧里观众的 `uid`/`userId`、`profile.userIdHash`、`nickname`，`extras.extraToken`。
- 频道、直播的公开信息（id、名称、头像、标题、`videoId`）保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | HLS 令牌到期（约 17 小时）后，正在播放的列表是否立即失效 | 连续播放超过 17 小时，或录制对照 |
| 2 | 捐赠 93102 的完整字段（`payAmount`、`isAnonymous`、视频捐赠） | 在热门直播录更长的弹幕样本 |
| 3 | 成人认证账号能否取到 `livePlaybackJson`，需要哪些 Cookie | 有账号后对照 |
| 4 | 弹幕服务器编号算法（字符码之和 % 9 + 1）是否会变；是否有备用地址 | 对比网页端脚本 |
| 5 | `blindType` 除 `ABROAD` 以外的取值 | 观察更多直播 |
