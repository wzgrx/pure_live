# 平台规格：快手直播（kuaishou）

- 平台 id：`kuaishou`（lib/core/sites.dart:47）；显示名“快手直播”（site:24）。
- 阶段：第 1 阶段平台规格，首批重写平台（docs/adr/0003-platform-batches.md:14）。
- 能力：推荐、两级分类目录、主播搜索（含未开播，可翻页）、房间详情、取流（FLV，AVC）、弹幕（HTTP 轮询）、可选手动 Cookie、录制。无醒目留言。
- 证据口径：`文件:行号` 取自 2026-09-27 的工作树；提交哈希取自 docs/ 里的审计记录。标“实测”的结论来自 2026-09-27 编写本规格时在本机 WSL 发出的少量匿名请求（未带 Cookie），**只有一次观察**。同日录制了样本（`fixtures/kuaishou/`，见第 11 节），能用样本核对的结论改写为样本编号，例如 `S09-room-live`。旧代码只作参考，本文只写行为和外部契约。
- 路径简写：`site` = lib/core/site/kuaishou/kuaishou_site.dart，`dm` = lib/core/danmaku/kuaishou_danmaku.dart，`ua` = lib/plugins/fake_useragent.dart，`phr` = lib/player/core/playback_header_resolver.dart，`url_tool` = lib/common/utils/live_url_tool.dart，`wsp` = lib/modules/search/web_search_room_parser.dart。

## 1. 房间身份与链接

### ID

| ID | 形态 | 生命周期 | 用途 | 证据 |
|---|---|---|---|---|
| 主播 id（`author.id`） | 两种：系统生成的 `3x` 开头 15 位小写字母数字（实测如 `3xgw4a6r5eiu4nu`）；用户自定义快手号（字母、数字、`_`、`-`，实测如 `tianci666`、`ATM-Heros`） | 跟随主播，长期稳定 | **唯一可持久化的房间身份**：收藏、历史、录制任务、房间页 `https://live.kuaishou.com/u/{id}` | site:445,467,570；wsp:146-149 |
| `liveStreamId` | 实测为 11 位 base64url 字符（如 `_fcZDnQGscI`） | **每场直播一个新值** | 弹幕 feed、App 深链；不得作为房间主键 | site:147,284,461；dm:233 |
| `originUserId` | 纯数字 uid | 稳定 | 旧代码未使用；能否用于 `/u/` 路径 [待确认] | 实测（列表、搜索均返回） |

主播 id 校验：`^[a-zA-Z0-9_-]+$`，且不能是保留导航词（`search`、`category`、`game`、`user`、`login` 等，wsp:40-58,178-179）。大小写是否敏感 [待确认]；旧代码原样保留。

### 可识别的链接

| 输入 | 结果 | 证据 |
|---|---|---|
| `https://live.kuaishou.com/u/{id}[/…][?…][#…]` | 取 `/u/` 后第一段为主播 id | wsp:146-149；test/live_url_tool_parser_test.dart:14；test/web_search_room_parser_test.dart:12 |
| `https://live.kuaishou.cn/u/{id}[/]` | 同上（旧工具保留的别名） | url_tool:135-136,318-320；test/live_url_tool_parser_test.dart:15 |
| `https://live.kuaishou.com/u/` | 不是房间 | test/live_url_tool_parser_test.dart:50 |
| `https://live.kuaishou.com/search?keyword=…` 等导航页 | 不是房间 | test/web_search_room_parser_test.dart:38；test/toolbox_link_detection_test.dart:49；docs/TOOLBOX_ROOM_LINK_PREFILTER_AUDIT_2026_09_23.md:5 |
| 非 http(s) 协议、子域伪装（`live.kuaishou.com.evil…`） | 不是房间；主机必须精确等于 `live.kuaishou.com` / `live.kuaishou.cn` | wsp:69-70,146 |
| 分享短链 `https://v.kuaishou.com/{code}` | **旧版不支持**（短链跳转只处理 b23.tv、v.douyin.com、TikTok，url_tool:134,262-293） | [待确认] 跳转目标格式 |
| 移动页 `https://m.gifshow.com/fw/live/{id}` | **旧版不支持**；房间页 `liveStream.url` 就是这个格式（实测） | [待确认] 是否需要支持 |
| `https://www.kuaishou.com/profile/{…}` | 旧版不支持 | [待确认] |

分享文本中可能有多个链接：按文本顺序取第一个能解析的，无关链接不能挡住后面的房间链接（docs/LIVE_LINK_PARSER_AUDIT_2026_09_07.md:15,23）。

### 归一

1. 去掉首尾空白和结尾标点，只接受 http(s)。
2. 主机精确匹配后取 `/u/` 后第一段；丢弃查询串、片段和后续路径段。旧版曾因查询串、`_`、`-` 得到空 ID（docs/LIVE_LINK_PARSER_AUDIT_2026_09_07.md:15）。
3. 规范页面 URL：`https://live.kuaishou.com/u/{id}`（site:445,570）。
4. 短链：在样本确认前，LinkResolver 对 `v.kuaishou.com` 和 `m.gifshow.com` 返回“不支持的链接”，不能返回 NotFound。

### 外部打开

- 网页：`https://live.kuaishou.com/u/{id}`。
- 快手 App：`kwai://liveaggregatesquare?liveStreamId={L}&recoStreamId={L}&recoLiveStreamId={L}&liveSquareSource=28&path=/rest/n/live/feed/sharePage/slide/more&mt_product=H5_OUTSIDE_CLIENT_SHARE`，`{L}` 是**当前场次**的 liveStreamId，逐字段做查询编码；没有 liveStreamId 时只提供网页（lib/modules/live_play/services/room_external_opener.dart:193-201；test/room_external_opener_test.dart:284,298-299；docs/ROOM_EXTERNAL_OPEN_AUDIT_2026_09_08.md:28）。

## 2. 目录

所有目录接口都是匿名 GET，请求头用第 6 节的“通用网页头”，不带 Cookie（site:105-109,140-144,272-275）。

### 分类（两级）

- 一级固定 8 个：`1` 热门、`2` 网游、`3` 单机、`4` 手游、`5` 棋牌、`6` 娱乐、`7` 综合、`8` 文化（site:54-63）。是否仍与官网一致 [待确认]。
- 二级：`GET https://live.kuaishou.com/live_api/category/data?type={1..8}&page={n}&size={s}`（site:104-125）。
  - 响应 `data.list[]`：`id`、`name`、`poster`，另有 `iconUrl`、`categoryAbbr`、`categoryName`、`description`、`roomCount`；`data.hasMore`（S01）。
  - `size` 被服务端忽略：请求 30，满页是 50 条（S01 各类第 1 页）。
  - `hasMore`：类型 1～5 的第 1 页为 true；类型 5 第 2 页（6 条）、类型 6（7 条）、7（13 条）、8（2 条）为 false（S01-category-type5-p2、S01-category-type6-p1 等）。
  - 分区 id：游戏类是不超过 5 位的数字（如 `1001`、`22008`），非游戏类是 7 位 `1000xxx`（如 `1000004` 才艺）（S01）。
- 翻页：旧版“本页条数 ≥ size 就继续”，出错时静默返回已取到的部分（site:84-102）。v4 按 `hasMore` 翻页（kuaishou_parse.dart:96-120）；任何一页失败都传播 SiteFailure，不能把部分结果当完整目录。
- 跨一级分类有重复，而且是有意的：类型 1“热门”的两页 100 个分区，全都也出现在它们自己的分类里（例如 `1001` 王者荣耀同时在热门和手游；手游第 1 页 50 个里有 48 个在热门里）（S01；kuaishou_parse_test.dart:184-197）。所以**只在同一个一级分类内部按 `id` 去重**，不能跨分类去重，否则其它分类会丢分区。

### 分区房间

- 接口按分区 id 选择：id 长度 < 7 用 `GET https://live.kuaishou.com/live_api/gameboard/list`，否则用 `GET https://live.kuaishou.com/live_api/non-gameboard/list`；参数 `filterType=0`、`pageSize=20`、`gameId={分区 id}`、`page={n}`（site:136-144）。按长度区分是经验规则，与实测的 id 分布一致 [待确认 官方依据]。
- 响应 `data.list[]` 为房间卡片，`data.hasMore`；非游戏类另有 `data.cursor`（如 `610_950484466`）和 `data.labelList`（S03）。
- **非游戏类翻页必须回传 cursor**：第 2 页的请求要带 `cursor={上一页的 data.cursor}`，参数名就是 `cursor`，`page` 照常加 1。
  - 不带 cursor 请求 `page=2`，返回的 20 个房间和第 1 页完全相同，`data.cursor` 也不变（S03-non-gameboard-p2 对照 S03-non-gameboard-p1）；
  - 带上 cursor，得到与第 1 页不重叠的 20 个房间和新的 `cursor`（`257_1252287100`）（S03-non-gameboard-p2-cursor）。
  - 这就是 REG-KUAISHOU-022 里“第 2 页和第 1 页一样”的原因。
- 游戏类（gameboard）响应没有 `cursor`，只靠 `page` 翻页；第 1、2 页之间只有 1 个房间重复（列表在变动）（S02-gameboard-p1、S02-gameboard-p2）。
- 旧版忽略 `hasMore` 和 `cursor`，界面只取第 1 页再本地分页（lib/modules/area_rooms/area_rooms_binding.dart:27-29；lib/modules/area_rooms/area_rooms_controller.dart:14-17；lib/common/base/server_all_page_controller.dart:84-110）。v4 返回不透明游标 `{page, cursor?}`，`hasMore=false` 时结束（kuaishou_parse.dart:64-80, 121-129）。
- 卡片字段映射（site:146-167，实测补全）：

| 目标 | 来源 | 说明 |
|---|---|---|
| 房间 id | `author.id` | |
| 标题 | `caption` | |
| 封面 | `poster` | 房间截图，URL 无扩展名，原样使用，不补 `.jpg`（补与不补拿到的是同一份 JPEG，kuaishou_parse_test.dart:45-47）；缺失时为空，不能让整页失败（REG-KUAISHOU-020） |
| 昵称、头像 | `author.name`、`author.avatar` | |
| 分区名 | `gameInfo.name` | |
| 在线人数 | `watchingCount` | 字符串，可能带单位，如 `1.0万`、`38` |
| liveStreamId | `id` | 弹幕参数 |
| 预带的流 | `playUrls` | 描述符列表，见第 5 节 |
| 状态 | 列表来源即“直播中”；`caption` 以 `【回放】` 开头时是**回放** | 卡片的 `living`、`author.living` 对在播房间实测也是 `false`，**不能用**。回放判定见第 4 节“回放卡片” |

  其它实测字段：`statrtTime`（原文拼写）、`likeCount`、`landscape`、`quality`、`qualityLabel`、`type`（`live`）、`expTag`、`hasRedPack`、`hasBet`、`followed`、`hotIcon`；`gameInfo.id` 在列表里是数字，在房间页是字符串。

### 推荐

- `GET https://live.kuaishou.com/live_api/home/list`，无分页参数（site:270-276）。
- 结构：`data.list[]` 为分组 `{labelId, labelName, labelIcon, labelStyleType, gameLiveInfo[]}`，每组 `gameLiveInfo[] = {subLabelId, subLabelName, liveInfo[]}`，`liveInfo[]` 为房间卡片（字段同上）。录到 4 组（热推直播、端游直播、手游直播、主机直播），只有 `subLabelId=0`“直播中”带卡片（各 12 张），其余子标签为空；48 张卡片里有 1 个主播（`mnxfsj666888`）重复出现（S04-home-list）。
- 旧版把所有分组展平，不去重（site:279-309）；界面一次取全后本地分页（lib/modules/popular/popular_controller.dart:61-63）。
- 旧版映射有误：封面取 `gameInfo.poster`（分区海报），标题取 `author.description`（主播简介）（site:286,292）。v4 与分区房间卡片用同一映射（封面 `poster`、标题 `caption`），按主播 id 去重并保持服务端顺序。
- 只有一页。排序由界面层做：`watchingCount` 按在线人数稳定降序，服务端顺序不保证降序（docs/STAGE_UPDATE_2_9_7.md:18）。
- 空列表不是错误，但探针把“没有卡片”判为失败（tool/interface_probe.py:1297-1311）。

## 3. 搜索

### 不用的接口

- `GET /live_api/search/liveStream`：匿名返回 `{"data":{"result":10,"error_msg":"服务器繁忙，请稍后再试。",…}}`（docs/ISSUE_TRIAGE_LEDGER_3_2_0.md:12；S08-search-livestream-busy）。
- `GET /live_api/search/overview`：匿名返回 authors 0、liveStreams 0（docs/ISSUE_TRIAGE_LEDGER_3_2_0.md:12）。
- 官网搜索页只显示“相关游戏”，没有主播和直播间，因此旧版网页搜索一直转圈（上游 #881，同上）。

### 主播搜索

- `GET https://live.kuaishou.com/live_api/search/author?keyword={kw}&page={n}&lssid={s}`；请求头 = 通用网页头 + `Referer: https://live.kuaishou.com/search?keyword={查询编码后的 kw}`（site:529-540；提交 2753a910）。
- 响应 `data`：`type`（`authors`）、`result`、`ussid`、`list[]`。`list[]` 字段：`id`、`name`、`avatar`、`description`、`living`、`counts{fan, follow, photo, playback, open}`、`bannedStatus{banned, socialBanned, isolate, defriend}`、`originUserId`、`verifiedStatus`、`sex`、`cityName` 等（实测；test/kuaishou_author_search_test.dart:7-48）。
- 映射（site:543-580）：
  - 房间 id = 用户 id = `id`，空 id 跳过；
  - 昵称和标题 = `name`；头像和封面 = `avatar`；简介 = `description`；
  - 粉丝数 = `counts.fan` 原样字符串（如 `2960.4w`）。旧版缺失时填 `'0'`，v4 缺失时为空；
  - 状态：`bannedStatus.banned == true` → 封禁；否则 `living == true` → 直播；否则 → 未开播；
  - 在线人数为空（显示“待刷新”），**不是 0**（site:565-567；test/kuaishou_author_search_test.dart:44）；
  - 页面链接 = `https://live.kuaishou.com/u/{id}`。
- 搜索里的 `living` 是否可靠 [待确认]：列表接口的 `living` 对在播房间是 `false`（第 2 节）。v4 进房时一律以房间页为准。
- 能力登记：覆盖在播和未开播，支持翻页（lib/modules/search/search_capability.dart:125；test/search_ranking_test.dart:120-121）；界面保留快手网页搜索入口（lib/modules/search/search_controller.dart:119-120；README.md:131）。

### 翻页与结束

- 旧版 `page` 递增，`lssid` 一直是空串（site:536），再把结果截到 pageSize（site:539）；界面遇到空页就停（lib/modules/search/search_controller.dart:341-355）。
- 实测每页只有 1–3 条。不带 `lssid` 时第 4 页为空（`result=1`），第 5 页又有 1 条，所以“空页 = 结束”会漏结果 [待确认 是否稳定复现]。
- 每页响应带 `ussid`（base64，解码后含时间戳和关键词）；它是不是下一页应回传的 `lssid` [待确认]。
- v4 游标 = `{page, lssid}`。结束条件在样本确认前沿用“`result=1` 且列表为空即结束”，样本确认后再改。

### result 取值

| result | 含义 | v4 | 证据 |
|---|---|---|---|
| 1 | 成功（列表可能为空） | 正常 | 实测 |
| 2 + `error_msg`“操作太快了，请稍微休息一下” | 限流 | `RateLimited`；停止翻页，稍后重试 | S06-search-author-ratelimited；实测：约 1 分钟内第 12 次左右请求开始出现 |
| 10 + “服务器繁忙，请稍后再试。” | 匿名门禁（liveStream 接口） | `RiskControl` | docs/ISSUE_TRIAGE_LEDGER_3_2_0.md:12；S08-search-livestream-busy |
| 其它 / 没有 `data.list` | 未知 | `ApiChanged` | — |

- 这张表适用于所有 `live_api` 接口，不只是搜索：`data.result` 存在且不为 1 时，2 → RateLimited，10 → RiskControl，其它 → ApiChanged。列表类接口正常时不带 `result`（kuaishou_parse.dart:380-393）。
- 限流按接口计算：`search/author` 已经返回 `result 2`（10:20:40），7 秒后 `search/liveStream` 仍然照常返回它的 `result 10`，不是 2（S06、S08）。所以一个接口被限流，不代表其它接口也要停。
- 被限流和门禁的响应里还有 `data.host-name`（内部主机名，样本里已替换）。

旧版对任何没有列表的响应都返回空列表（site:544-546；test/kuaishou_author_search_test.dart:50-65），会把限流当成“没有结果”或“已到底”（REG-KUAISHOU-015）。

## 4. 房间详情

### 获取

- `GET https://live.kuaishou.com/u/{id}`，请求头用第 6 节的“房间页请求头”（site:444-447）。
- 从 HTML 里找 `window.__INITIAL_STATE__=`，取后面的 JSON 对象，把 `undefined` 换成 `null` 后解析（site:448-450）。JSON 后面紧跟 `;(function(){var s;…`（S09、S11、S12 都是）。旧版用非贪婪正则截到第一个 `;`，JSON 字符串里一旦出现 `;` 就会截断；v4 必须按 JSON 结构截取（REG-KUAISHOU-018）。
- 只替换**字符串外面**的裸 `undefined`。字符串里的 `undefined` 是正文，要原样保留：下播页的 `liveStream.url` 就是字面的 `https://m.gifshow.com/fw/live/undefined`，旧版整串替换后变成了 `…/live/null`（S11-room-offline；kuaishou_parse.dart:186-200）。
- 取 `liveroom.playList[0]`；缺失、为空或不是对象 → 旧版抛格式错误（site:451-454）。
- 实测 `liveroom` 还有 `websocketUrls`（匿名为 `[]`）、`token`（匿名为空串）、`noticeList`、`activeIndex`。

### playList[0] 字段（实测）

| 字段 | 在播 | 下播 | 主播不存在 |
|---|---|---|---|
| `isLiving` | `true` | `false` | `false` |
| `liveStream` | `id`、`poster`、`playUrls{h264,hevc}`、`hlsPlayUrl`、`url`、`type`、`privateLive`、`liveGuess`、`expTag`、`location`、`dynamicLayoutEnable` | 只有 `playUrls{h264,hevc}`、`url`（字面是 `…/fw/live/undefined`）、`type`、`location`、`liveGuess`、`expTag`；**没有 `id` 和 `poster`** | `{}` |
| `author` | `id`、`name`、`avatar`、`description`、`living`（实测为 `false`）、`counts{fan,follow,liked}`、`bannedStatus`… | 同左 | `{}`（空对象，不是各字段为 null） |
| `gameInfo` | `id`、`name`、`poster`、`description`、`categoryAbbr`、`categoryName`、`watchingCount`、`roomCount`；`watchingCount` 是分区统计，如 `"1万+"` | `{}` | `{}` |
| `status` | `{forbiddenState: 1}` | `{forbiddenState: 671}` | 无 |
| `errorType` | 无 | 无 | `{type: 22, title: "错误代码22", content: "浏览其他内容", url: "/"}` |
| 其它 | `authToken`（`null`）、`config{needLoginToWatchHD, canSendGift, …}`、`websocketInfo`（`{}`） | 同左 | 无 |

以上三列分别是 S09-room-live、S11-room-offline、S12-room-notfound。`forbiddenState` 的含义 [待确认]。房间页没有 `caption`（三个样本里都没有）。`config.needLoginToWatchHD` 在录到的页面里都是 false。

### 映射（site:455-482）

| 目标 | 来源 | 说明 |
|---|---|---|
| 房间 id | `author.id`，缺失时用请求的 id | |
| 昵称、头像 | `author.name`、`author.avatar` | |
| 标题 | 旧版用 `author.description`，换行替换为空格 | 房间页没有直播标题；v4 优先保留进房前卡片的 `caption`，没有时才用简介。房间页是否有其它标题字段 [待确认] |
| 简介、公告 | `author.description` | |
| 封面 | `liveStream.poster` | 截图地址没有扩展名（如 `…/screenshot/XT8F1KPOf0c~1790504381694~1`），原样使用。旧版补 `.jpg`（site:127-133,463），不必要：补与不补拿到的是同一份 JPEG（2026-09-27 核对，kuaishou_parse_test.dart:45-47） |
| 分区名 | `gameInfo.name` | |
| liveStreamId | `liveStream.id` | 弹幕参数；下播时没有 |
| 粉丝数 | `author.counts.fan` | 旧版未用 |
| 流描述 | `liveStream.playUrls` | 只在完整深度保留 |

### 直播状态

- `isLiving` 是唯一依据；兼容 `true`、`1`、`"true"`（不区分大小写）（site:458-459；docs/RECORDING_AUDIT_3_0_13.md:46）。列表、搜索的 `living` 和 `author.living` 都不能用。
- 状态判定：
  - 有 `errorType` → 不是房间状态，按第 9 节映射（实测 `type=22` 对应主播不存在）；
  - `isLiving` 为真 → 直播；进房前的卡片标题以 `【回放】` 开头时是回放（见下文“回放卡片”）；
  - `isLiving` 为假 → 未开播；
  - 房间页的封禁表示 [待确认]。搜索结果用 `bannedStatus.banned` 判封禁（site:571-572）。
- 旧版对下播页和不存在页会出错：`liveStream.poster` 缺失时，封面判断收到 `null` 并抛出 `type 'Null' is not a subtype of type 'String'`（site:463，已用 Dart 复现），于是下播房间在进房时显示“状态未知”（site:402-406），在收藏刷新和录制时报错（REG-KUAISHOU-020）。

### 人数

- 快手只有当前在线人数这一种口径，没有热度和累计观看（lib/common/models/live_room.dart:66-70,628；assets/translations/zh.json:1594）。
- 可靠来源：列表卡片的 `watchingCount`，以及弹幕 feed 的 `currentWatchingCount`（第 7 节）。解析时支持 `万/亿/千/k/w/m` 和千分位（lib/common/models/live_room.dart:774-788）。
- 房间页 `gameInfo.watchingCount` 和 `roomCount` 是**分区**的统计，不是本房间的人数：王者荣耀分区的两个房间都是 `watchingCount: "1万+"`，`roomCount` 分别是 `"1000"` 和 `"997"`（S09-room-live、S09-room-live-replay）。旧版把它当成房间在线人数（site:464-465）；v4 详情里的在线人数一律为空（待刷新），由弹幕 feed 或卡片补上（REG-KUAISHOU-016；kuaishou_parse.dart:198-205）。
- 下播时在线人数为空，不填 0。

### 回放卡片

- 旧版：房间页说未开播，但**当前播放器里、平台和房间号都匹配**的那张卡片还带着可解析的流时，把它当作录播进入（`isRecord`）（site:394-400,433-441；docs/ISSUE_AUDIT_2026_08_24.md:56-60；RELEASE_NOTES.md:945）。
- 样本里的回放是**直播中的轮播房间**，不是下播后的旧卡片：
  - 游戏分区列表里的 KPL 卡片，`caption` 是 `【回放】2026KPL夏季赛精彩赛事集锦`（S02-gameboard-p1，主播 `KPL704668133`）；
  - 同一主播的房间页 `isLiving` 为 true，有 `liveStream.id` 和完整的 `playUrls`，和普通直播间没有区别（S09-room-live-replay）；
  - 房间页没有 `caption`，所以**只能从卡片标题看出是回放**。
- v4 规则（kuaishou_parse.dart:206-247, 441-462）：
  - 列表卡片的 `caption` 以 `【回放】` 开头 → 状态为回放，其它列表卡片为直播；
  - 进房时房间页 `isLiving` 为真，并且进房前的卡片标题以 `【回放】` 开头 → 回放；没有卡片标题时只能按直播处理；
  - `isLiving` 为假 → 未开播，不看卡片。
- 不是回放信号的东西：
  - `【预告】` 开头的标题（S04-home-list 的 `【预告】28日CF鱼跃鹏程杯`，在“直播中”列表里）；
  - 流名里的 `kwai_actL_ksle_…`：回放卡片有，预告卡片和普通赛事卡片（“CODM大师杯”“暗区突围精彩赛事”）也有（S04-home-list、S02-gameboard-p1）。
- 旧版“房间页下播、卡片带流”的回退：适配器不读播放器状态（旧版通过 GetX 读取，site:409-414），详情如实返回“未开播”；要不要用卡片自带的流进入，由仓库层决定，条件是卡片身份与房间一致且流可以解析。这种“下播后卡片还带流”的情况样本里没有遇到。

### 深度

| 深度 | 用途 | 行为 | 证据 |
|---|---|---|---|
| 轻量 | 收藏刷新 | 不要流；先不建会话直接请求，失败再建会话重试一次 | site:416-426；docs/FAVORITE_REFRESH_DESIGN.md:61；RELEASE_NOTES.md:1632（v2.5.2） |
| 完整 | 进房 | 先确保会话，保留 `playUrls` | site:389-392 |
| 严格 | 录制 | 同完整；错误一律传播，只有 `isLiving` 为假才算下播 | site:428-442；lib/core/interface/live_site.dart:314-331；docs/rewrite/diagnosis/04-recorder.md:54 |

v4 只有一个 `detail(ref, depth)`，任何深度都不吞错；旧版进房路径出错时返回“状态未知”的房间（site:402-406）是反例。

## 5. 画质与线路

### 两种形状

| 来源 | `playUrls` 形状 | 证据 |
|---|---|---|
| 房间页 | 对象 `{h264: 描述符, hevc: 描述符}`；实测 `hevc` 是 `{}` | site:181-185；docs/ISSUE_AUDIT_2026_08_24.md:56 |
| 列表、推荐卡片 | 数组 `[描述符, …]`；实测每张卡片只有 1 个描述符 | site:183-185；docs/ISSUE_AUDIT_2026_08_24.md:57 |

- 描述符：`{hideAuto, autoDefaultSelect, cdnFeature, businessType, freeTrafficCdn, version, type, adaptationSet{gopDuration, representation[]}}`（实测）；也兼容 `representation` 直接挂在描述符上（site:246-252）。
- `representation[]`：`id`、`name`、`shortName`、`qualityType`、`level`、`bitrate`、`url`、`hidden`、`enableAdaptive`、`defaultSelect`（实测）。录到的档位（S02、S03、S04 的卡片和 S09 的房间页）：

| `qualityType` | `level` | `bitrate`（kbps） | `name` |
|---|---|---|---|
| `STANDARD` | 30 | 1000 | 高清 |
| `HIGH` | 50 | 2000 | 超清 |
| `SUPER` | 70 | 4000 | 蓝光、蓝光 4M |
| `BLUE_RAY` | 130 | 8000 | 蓝光Plus、蓝光 质臻、蓝光 8M |
| `WQHD_2K` | 250 | 16000 | 2K |

  同一 `qualityType` 在不同房间名称不同，显示时用平台给的 `name`（空白合并成一个）；只有 `qualityType` 没有名称时，才按上表第一个名称显示（kuaishou_parse.dart:589-601）。2K 档目前只在个别房间出现（S02-gameboard-p1 的 `tingan666`，共 5 档：2K、蓝光 质臻、蓝光 4M、超清、高清）。

### 规则（site:186-244；test/kuaishou_playback_parser_test.dart）

1. 编码：每个描述符依次看 `h264`、`avc`、`hevc`、`h265`，用**第一个**有 representation 的；都没有时把描述符本身当 adaptationSet 容器。H.264 优先，HEVC 只在没有 H.264 时回退，不并列出两套画质（site:194-202；docs/RECORDING_AND_QUALITY_AUDIT_3_0_12.md:27）。
2. 过滤：`url` 必须是 `http://` 或 `https://` 开头的绝对地址，否则丢弃（site:206-209）。
3. 排序键 `sort = level ?? bitrate ?? 0`；名称依次取 `name`、`shortName`、`qualityType`，都为空时用 `清晰度 {sort}`（site:210-217）。
4. 画质身份 = `(名称, sort)`，旧版 id 为 `名称\u0000sort`（site:218,234-236）；显示名经通用标签归一（lib/core/utils/live_quality_label.dart:21）。
5. 线路：同一画质身份下的多个 URL 按出现顺序合并成线路 1、2…，去重（site:219-224）。实测通常只有线路 1（docs/ANDROID_RUNTIME_AUDIT_3_1_8_K90PRO.md:109；docs/ACCEPTANCE_MATRIX_3_1_0.md:97）。
6. 画质按 `sort` 降序（site:242）。
7. 一档都没有 → `StreamUnavailable`（旧版抛“no playable live or replay stream”，site:173-178）。

### 编码与封装

- 实测所有画质都是 AVC FLV（docs/PLATFORM_PROBE_2026_09_25.md:87）。流名的写法（S02、S03、S04）：
  - `{liveStreamId}_GameAvc{Sd|Hd|Fhd}L{n}.flv`，也有带 `Lto` 后缀或 `-AuditAvcOriginL3` 后缀的；
  - `{liveStreamId}_ShowAvc{Sd|Hd}L{n}.flv`（非游戏分区）；
  - `{liveStreamId}_EcAvc{Sd|Hd|Fhd}L{n}Mate.flv`（非游戏分区，S03-non-gameboard-p1）；
  - 活动流 `kwai_actL_ksle_{时间}_{…}_strL_GameAvc…flv`；
  - `{liveStreamId}_ma1500.flv` 和 `…_ma1500-AuditAvcOriginL3.flv`：名字里没有编码。
  - 卡片的描述符没有 `h264`/`hevc` 键，编码只能从流名最后一个 `_` 之后读：以字母开头、含 `Avc`/`H264` 的记为 AVC，含 `Hevc`/`H265` 的记为 HEVC；`ma1500` 这类记为未知（kuaishou_parse.dart:603-616）。
- 如果出现 HEVC FLV，是否用传统 codec id 12（需要中继转写）[待确认]。

### CDN 标识

- 实测主机：`tx-origin.pull.yximgs.com`、`ws-origin.pull.yximgs.com`、`hw-origin.pull.yximgs.com`、`ty-origin.pull.yximgs.com`；样本里另有 `bd-origin.pull.yximgs.com` 和 `ali-origin.pull.yximgs.com`，`hw-origin` 没有出现（S02、S03、S04 共 343 个地址：tx 260、ws 72、ty 5、bd 5、ali 1）。旧版没有 cdnId；v4 用主机名作为线路 id，同一画质在同一主机上有两个地址时加序号（kuaishou_parse.dart:628-632）。主机名是否稳定 [待确认]。

### 画质确认

- 旧版没有确认步骤，所选即实际（lib/core/interface/live_site.dart:20-25 的默认行为）。每档是独立的 URL，是否还要用首帧分辨率核对 [待确认]。

### 旧版未使用的字段 [待确认]

- `representation.hidden`、`defaultSelect`（实测“超清”为 true）、`enableAdaptive`；
- `config.needLoginToWatchHD`：是否表示某些档位需要登录；
- `liveStream.hlsPlayUrl`：HLS 地址（实测在 `ws-origin.hlspull.yximgs.com`），能否作为 HLS 备用线路。实测该值末尾是 `…sidc=201165tsc=origin`，拼接有缺陷，使用前需清洗。

## 6. 取流

### 地址来源

- 没有单独的取流接口。播放地址已经在房间页的 `liveStream.playUrls` 或列表卡片的 `playUrls` 里（site:173-179,259-267,481）。
- `streams()` 就是按完整深度重新请求房间页并解析；续期和恢复都必须重新请求房间页，不能复用卡片或缓存里的旧地址（通用规则见 lib/core/interface/live_site.dart:164-169）。
- 录制：一次响应给出所有线路，没有“只签当前线路”的游标（RELEASE_NOTES.md:877）。

### 匿名会话

- 用户配置了 Cookie 时不建匿名会话（site:506）。
- 否则会话有效 30 分钟（site:30,508）；并发的建会话请求合并成一次（site:509-525）。
- 建会话：用带 CookieJar 的独立客户端 GET 房间页，把收到的 Cookie 拼成 `name=value;…`（site:370-386）。实测匿名房间页下发 `did=web_{32 位十六进制}`、`clientid=3`、`client_key`、`kpn=GAME_ZONE`（均一年有效、httponly）和会话 Cookie `kuaishou.live.bfb1s`。
- 然后尽力上报设备，失败忽略（site:517-521）：`POST https://log-sdk.ksapisrv.com/rest/wd/common/log/collect/misc2?v=3.9.49&kpn=KS_GAME_LIVE_PC`，JSON 体中 `identity_package.device_id = did`，其余是写死的值：`product_name=KS_GAME_LIVE_PC`、`platform=10`、`container=WEB`、固定的 `session_id` 和页面 `identity`、Windows 7 + Chrome 86 的 UA、分辨率 1600×900、页面 `GAME_DETAL_PAGE`（site:316-368）。这一步是否必要 [待确认]。
- 旧版建会话的请求没带任何请求头、不走应用代理、没有超时和取消（site:371-374）（REG-KUAISHOU-021）。
- 实测不带任何 Cookie 也能拿到完整房间页和播放地址；会话只在被拒时才需要（site:419-421 注释）。什么情况下会被拒 [待确认]。

### 请求头

**通用网页头**（目录、推荐、搜索，site:72-82）：

```
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Safari/537.36
accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3
connection: keep-alive
sec-ch-ua: Google Chrome;v=107, Chromium;v=107, Not=A?Brand;v=24
sec-ch-ua-platform: macOS
Sec-Fetch-Dest: document / Sec-Fetch-Mode: navigate / Sec-Fetch-Site: same-origin / Sec-Fetch-User: ?1
```

**房间页请求头**（site:485-498）：在通用头上改为

- `User-Agent`：每次随机，从 Mac Chrome、Mac Safari、Windows Chrome、Windows Edge、Linux Chrome 中选一个，Chrome 版本 88–110（ua:5-59,62-86）；
- `sec-ch-ua`：总是写成 `Google Chrome;v={主版本}, Chromium;v={主版本}, Not=A?Brand;v=24`；`sec-ch-ua-platform` 取随机 UA 的平台；
- `sec-fetch-*` 同上，`accept` 末尾加 `;q=0.9`；
- `cookie`：用户 Cookie 优先，否则用匿名会话 Cookie（site:496,500-503）。

旧版随机 UA 有缺陷：Mac UA 的系统版本号被整体替换成连字符（ua:13,15，正则 `.` 匹配了所有字符）；Safari、Edge、Linux 的 UA 与写死的 `Google Chrome` sec-ch-ua 不一致（REG-KUAISHOU-019）。v4 的 UA 与 `sec-ch-*` 必须成套且使用当前版本；是否还需要随机 [待确认]。

**播放请求头**（随每条 StreamLine 下发，phr:38-41,96-105）：

```
user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36
origin: https://live.kuaishou.com
referer: https://live.kuaishou.com/u/{编码后的主播 id}   （没有 id 时为 https://live.kuaishou.com/）
cookie: {用户 Cookie}                                   （只有用户配置时才带；匿名会话 Cookie 不发给 CDN）
```

头名全小写、值里去掉换行（test/playback_header_resolver_test.dart:50-71）。CDN 是否真的校验这些头 [待确认]。

### 租期

- 旧版不提供租期：没有实现租期元数据接口（site:19），断流后走错误驱动的重新获取。
- 签名参数（按 CDN 不同）：

| 主机前缀 | 签名 | 过期时间 | 编码 | 证据 |
|---|---|---|---|---|
| `tx-origin` | `txSecret` | `txTime` | 十六进制 Unix 秒 | S02、S03、S04、S09 全部 |
| `ws-origin` | `wsSecret` | `wsTime` | 十六进制 Unix 秒 | S02、S03、S04、S09-room-live |
| `hw-origin` | `hwSecret` | `hwTime` | 十六进制 Unix 秒 | 编写规格时实测；样本里没有 |
| `ty-origin` | `ty_Secret` | `ty_Time` | **十进制** Unix 秒 | S03-non-gameboard-p1、S04-home-list |
| `bd-origin` | `wsSecret` | `wsTime` | **十进制** Unix 秒（10 位），与 ws-origin 的十六进制不同 | S02-gameboard-p2、S03-non-gameboard-p2-cursor、S09-room-live-replay |
| `ali-origin` | `auth_key` | `auth_key` 的第一段 | `auth_key=<到期 Unix 秒>-<rand>-<uid>-<md5>`（阿里云 A 型鉴权；录制时 rand、uid 都是 0） | S03-non-gameboard-p2-cursor；tools/live_cli/lib/src/fixture/rules/kuaishou.dart:30-32 |

  另有 `stat`、`tsc`、`oidc`、`sidc`、`ss`、`no_script`、`tfc_buyer`、`srcStrm` 等参数。tx、ws、ty、bd 四种过期时间在样本里都是“签发时刻 + 24 小时”（kuaishou_parse_test.dart:79-90）；`auth_key` 在样本里整体替换过，其中的到期时间是合成的，ali-origin 是否也是 24 小时没法用样本核对 [待确认]。

- v4 的 Lease（kuaishou_parse.dart:318-335, 634-644）：
  - `issuedAt` = 收到房间页或列表响应的时刻；
  - `invalidAt` = 上表的过期时间：8 位十六进制或 10 位十进制都接受；`auth_key` 取第一段；没有可识别的参数，或已经过期时为空，走错误驱动；
  - `refreshAt` = `invalidAt` − 10 分钟；寿命不到 40 分钟时改为 − 寿命的 1/4；
  - `cutsConnection` [待确认]：旧版没有连续播放或录制超过 24 小时的证据（已有录制样本约 60 秒，docs/ACCEPTANCE_MATRIX_3_1_0.md:110）。在确认前按 `false` 处理（到期只预取，已建立的连接不主动重开），并在长时录制探针中验证。
- 列表卡片预带的地址也有签名，过期时间从列表响应时刻算起；进房时仍以房间页重新取到的地址为准。

## 7. 弹幕

### 为什么不用 WebSocket

- 桌面端 WebSocket 的引导请求需要浏览器签名（dm:38-44）。实测匿名房间页里 `liveroom.websocketUrls` 为 `[]`、`token` 为空串。
- 3.1.8 之前快手没有弹幕：适配器直接返回空实现，直播页、画中画、多画面也把快手排除在外（docs/ANDROID_RUNTIME_AUDIT_3_1_8_K90PRO.md:96）。改用移动端 feed 后，真机看到 11 条真实评论（同文件:98；构建基线提交 4d0e3202，同文件:97）。

### 请求

- `GET https://livev.m.chenzhongtech.com/wap/live/feed?liveStreamId={L}[&cursor={c}]`；失败时换 `https://m.gifshow.com/wap/live/feed`，参数相同（dm:49-52,217-246）。每一轮都先试主端点。
- 请求头（dm:218-225）：

```
User-Agent: Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0 Mobile Safari/537.36
Accept: application/json, text/plain, */*
Referer: https://livev.m.chenzhongtech.com/
cookie: {Cookie}   （有才带）
```

- 实测匿名、不带 Cookie 可以拿到数据。
- `liveStreamId` 必填，缺失时启动直接失败（dm:95-97）。第一轮不带 `cursor`；之后带上一轮返回的 `cursor`，返回空 cursor 时沿用旧值（dm:138,233-235）。
- 弹幕参数（liveStreamId + 当时生效的 Cookie）在取详情时生成（site:162-164,301-303,478-480）。换场后 liveStreamId 会变，需要重新取详情；下播后 feed 返回什么 [待确认]。

### 响应

- 响应体可能是被 JSON 编码了 1–3 层的字符串（实测为 1 层），也可能外面包一层 `data`（dm:249-253；test/kuaishou_danmaku_test.dart:10-44）。
- 字段：`result`、`cursor`、`pullCycleSeconds`、`currentWatchingCount`、`liveStreamFeeds[]`（实测）。
- `result != 1` → 这一轮失败，不能显示为已连接（dm:256-259；test/kuaishou_danmaku_test.dart:46-48）。各非 1 取值的含义 [待确认]。

### 消息类型

| feed | 事件 | 规则 | 证据 |
|---|---|---|---|
| `type == "comment"`（不区分大小写） | 聊天 | 内容 = `content` 去首尾空白，空则丢弃；昵称 = `author.userName`，空则“快手用户”；用户 id = `author.userId`；时间 = `time`（毫秒）；消息 id = `kuaishou:{id}`，没有 id 时用 `sha1(time \0 userId \0 content)` | dm:268-289 |
| 其它 type（礼物等） | 丢弃 | 其它 type 的取值和字段 [待确认] | dm:269；test/kuaishou_danmaku_test.dart:24-28 |
| `currentWatchingCount` 非空 | 在线人数 | 每轮成功都发一次，口径是在线人数 | dm:145-156,262-263 |
| — | 醒目留言 | 不支持 | site:593-597 |

### 轮询与退避

- 启动：第一轮最多试 3 次，间隔 0.6 秒、1.4 秒；都失败则启动失败（dm:111-125）。第一轮成功才标记“已连接”并发出就绪（dm:141-143）。
- 间隔：用服务端的 `pullCycleSeconds`，缺省 3 秒，限制在 1–10 秒，且不低于最小间隔 1 秒（dm:46,193,261）。
- 串行：上一轮结束后才安排下一轮，同时只有一个定时器，请求不重叠（dm:43-44,190-198）。
- 失败退避：等待 1、2、4、8、8… 秒；第 1 次失败时发“正在重连”；连续第 9 次失败时（超过 8 次上限）关闭并报告失败；任意一次成功就清零（dm:53,139,175-188）。
- 取消：停止或切房时作废当前代号、取消在途请求，迟到的响应直接丢弃（dm:99-107,130-136,162-172,200-215；test/kuaishou_danmaku_test.dart:92-110）。
- 调用方的启动超时为 20 秒（lib/modules/live_play/controllers/danmaku_controller.dart:22；lib/modules/multiview/danmaku/multiview_danmaku_session.dart:29）。

## 8. 登录与 Cookie

- 没有扫码或网页登录，只能手动粘贴浏览器里的 Cookie（lib/modules/account/kuaishou/kuaishou_cookie_controller.dart:13-17；提示文案 assets/translations/zh.json:329）。
- 保存前去掉控制字符并去首尾空白（lib/common/services/settings/cookie_value.dart:4-6）。旧版明文保存在 `kuaishouCookie`（lib/common/services/settings/cookie_settings_controller.dart:32；docs/rewrite/diagnosis/05-app-shell-data.md:54）；v4 加密保存（spec/constitution.md 原则 8）。
- “已登录”只看 Cookie 是否非空，不做校验（lib/modules/account/account_page.dart:100-113）。
- 使用范围：房间页请求（site:496）、跳过匿名会话（site:506）、弹幕 feed（dm:225）、播放请求头（phr:97-104）。目录、推荐、搜索不带 Cookie（site:108,143,274,537）。
- 过期 Cookie 会触发风控：上游 #782 中三台设备用旧 Cookie 全部无法播放，重新获取后恢复（docs/ISSUE_AUDIT_2026_08_24.md:12,60；RELEASE_NOTES.md:1400）。v4：带用户 Cookie 的请求被判风控时报 `RiskControl`，提示更新 Cookie；是否自动改用匿名重试一次 [待确认]。
- 登录能带来什么（更高档位？`hidden` 档？）[待确认]。

## 9. 错误与风控 → SiteFailure

| 情况 | 识别方式 | v4 | 证据 |
|---|---|---|---|
| 连接失败、超时、HTTP 5xx | 传输层 / 状态码 | `Network` | lib/core/common/http_client.dart:11-13（旧版超时 20 秒）；kuaishou_parse.dart:370-378 |
| HTTP 429 | 状态码 | `RateLimited` | kuaishou_parse.dart:370-378 |
| HTTP 401、403 | 状态码 | `RiskControl`；带用户 Cookie 时标明 Cookie 可疑 | kuaishou_parse.dart:370-378 |
| 其它非 2xx | 状态码 | `ApiChanged` | 同上 |
| 调用方取消 | 取消令牌 | `Cancelled` | dm:163 |
| 任何 `live_api` 接口被限流 | `data.result=2`，`error_msg` 含“操作太快” | `RateLimited`。限流按接口计，不影响其它接口（第 3 节） | S06-search-author-ratelimited |
| 任何 `live_api` 接口返回门禁 | `data.result=10`“服务器繁忙” | `RiskControl`（v4 不调用直播搜索接口） | docs/ISSUE_TRIAGE_LEDGER_3_2_0.md:12；S08-search-livestream-busy |
| `live_api` 的 `data.result` 为其它非 1 值 | — | `ApiChanged` | kuaishou_parse.dart:380-393 |
| 主播不存在 | 房间页 HTTP 200，`playList[0].errorType` 为 `{type: 22, title: "错误代码22", …}`，`author` 为 `{}` | `NotFound` | S12-room-notfound |
| 房间页其它 `errorType` | `errorType.type` 为其它值 | [待确认]；在确认前按 `RiskControl` 处理，并记录 type 和 title | — |
| 房间页没有 `__INITIAL_STATE__` | HTML 里找不到标记 | 验证码或拦截页 → `RiskControl`；否则 `ApiChanged`；如何区分 [待确认] | site:449 |
| `playList` 缺失、为空或形状不符 | JSON 结构 | `ApiChanged` | site:451-454 |
| 用户 Cookie 导致风控 | 带 Cookie 请求失败，去掉 Cookie 后正常 | `RiskControl`（提示更新 Cookie） | docs/ISSUE_AUDIT_2026_08_24.md:60 |
| `isLiving` 为假 | — | 不是失败；房间状态为“未开播” | site:458-459,475 |
| 在播但没有可用画质 | 解析结果为空 | `StreamUnavailable` | site:174-177 |
| 需要登录才能看的档位 | `needLoginToWatchHD` / `hidden` [待确认] | `NeedLogin`（只影响该档位） | — |
| 私密直播 | `liveStream.privateLive == true` [待确认] | `AgeOrPaid` 或 `NeedLogin` [待确认] | 实测字段存在，值为 false |
| 目录接口 `data` 为空或结构不符 | JSON 结构 | `ApiChanged`；风控时的响应形状 [待确认] | 旧版界面把 `NoSuchMethodError '[]'` 当“需要登录”（lib/modules/area_rooms/area_rooms_controller.dart:24-29） |
| 弹幕 `result != 1` 或请求失败 | — | 弹幕连接状态（重连中 / 已断开），不是房间失败 | dm:175-188 |
| 地区限制 | 未见 | 不使用 `RegionRestricted` | — |

旧版的反例：推荐失败时 `throw Exception(e.toString())`（site:311-313）；分类子请求失败被吞掉（site:99-101）；进房失败返回“状态未知”的房间（site:402-406）。v4 一律返回带类型的 SiteFailure，界面只按类型显示文案。

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-KUAISHOU-001 | 多数房间无法播放（上游 #782） | 房间页的 `playUrls` 是 `{h264,hevc}` 对象，列表和回放卡片是描述符数组；旧逻辑只读 `data["h264"]` | 两种形状用同一套解析 | site:181-252；docs/ISSUE_AUDIT_2026_08_24.md:12,52-60；RELEASE_NOTES.md:1397（v2.9.4）；test/kuaishou_playback_parser_test.dart:15-30 |
| REG-KUAISHOU-002 | H.264 和 H.265 两套画质按钮重复 | 两种编码都被展开 | H.264 优先，只在没有 H.264 时回退 HEVC | site:194-202；docs/RECORDING_AND_QUALITY_AUDIT_3_0_12.md:27；test/kuaishou_playback_parser_test.dart:31-36 |
| REG-KUAISHOU-003 | 同一画质重复出现 | 多个描述符代表不同 CDN | 按 (名称, 等级) 合并为线路并去重 | site:219-224；docs/STAGE_UPDATE_2_9_5.md:41；test/kuaishou_playback_parser_test.dart:23-30 |
| REG-KUAISHOU-004 | 列表里的房间全显示“直播中”，进房才发现已下播 | 旧逻辑把列表卡片预先标为直播；卡片的 `living` 字段对在播房间也是 false，同样不可信 | 列表只表示“来自直播列表”；房间页 `isLiving` 是唯一依据 | docs/ISSUE_AUDIT_2026_08_24.md:58-60；site:158-159,297-298；实测 |
| REG-KUAISHOU-005 | 旧卡片被当成回放，打开后没有画面 | 回退条件太宽 | 只有平台和房间号都匹配、且卡片确有可解析的流时才进入回放；v4 由仓库层决定 | site:394-400,433-441；RELEASE_NOTES.md:945（v3.0.13）；docs/RECORDING_AUDIT_3_0_13.md:46 |
| REG-KUAISHOU-006 | 录制被误停 | 详情请求失败被当成“已下播” | 严格详情：错误一律传播，只有 `isLiving` 为假才算下播 | site:428-442；lib/core/interface/live_site.dart:314-331；docs/rewrite/diagnosis/04-recorder.md:54 |
| REG-KUAISHOU-007 | 在播房间被判下播 | `isLiving` 有时是数字或字符串 | 兼容 `true`、`1`、`"true"` | site:458-459；docs/RECORDING_AUDIT_3_0_13.md:46 |
| REG-KUAISHOU-008 | 所有房间都无法播放，更新 Cookie 后恢复 | 过期的用户 Cookie 触发平台风控 | 报 `RiskControl` 并提示更新 Cookie，不能当成解析错误 | docs/ISSUE_AUDIT_2026_08_24.md:12,60；RELEASE_NOTES.md:1400 |
| REG-KUAISHOU-009 | 搜索一直转圈、没有房间（上游 #881） | 匿名直播搜索返回“服务器繁忙”，overview 返回 0 条 | 改用公开的主播搜索，含未开播主播，可翻页 | 提交 2753a910；docs/ISSUE_TRIAGE_LEDGER_3_2_0.md:12；site:529-540；test/kuaishou_author_search_test.dart |
| REG-KUAISHOU-010 | 搜索卡片显示“0 人在线” | 主播搜索没有人数 | 人数为空，显示“待刷新” | site:565-567；test/kuaishou_author_search_test.dart:44 |
| REG-KUAISHOU-011 | 能播能录，但一直没有弹幕 | 桌面 WebSocket 需要签名，旧版直接返回空弹幕 | 改用移动端 feed 串行轮询 | dm:38-44；docs/ANDROID_RUNTIME_AUDIT_3_1_8_K90PRO.md:96-98 |
| REG-KUAISHOU-012 | feed 解析失败 | 响应体是被 JSON 编码过的字符串，有时外包 `data` | 最多解 3 层字符串，再拆 `data` | dm:249-253；test/kuaishou_danmaku_test.dart:10-44 |
| REG-KUAISHOU-013 | 显示“已连接”但没有弹幕 | `result != 1` 被当成成功 | `result != 1` 视为失败，进入重试 | dm:256-259；test/kuaishou_danmaku_test.dart:46-48 |
| REG-KUAISHOU-014 | （设计约束）切房后旧房间的弹幕混进来、后台 CPU 持续升高 | 定时器重叠，迟到的响应没有丢弃 | 串行轮询、单定时器、代号加取消令牌 | dm:43-44,99-107,190-198；test/kuaishou_danmaku_test.dart:92-110 |
| REG-KUAISHOU-015 | 搜索翻几页后“没有更多了”或直接空白 | 服务端限流返回 `result=2`，旧版把所有没有列表的响应都当成空结果 | 区分 `result`：限流报 `RateLimited` 并停止翻页，空结果才是“没有结果” | site:544-546；test/kuaishou_author_search_test.dart:50-65（v4 不继承这一期望）；实测 |
| REG-KUAISHOU-016 | 进房后在线人数变成 0 或分区数字 | 房间页 `gameInfo.watchingCount` 是分区统计 | 详情人数为空，由卡片 `watchingCount` 或 feed `currentWatchingCount` 提供 | site:464-465；S09-room-live（`gameInfo.watchingCount` 为分区的 `"1万+"`） |
| REG-KUAISHOU-017 | 推荐页封面都是游戏海报、标题是主播简介；同一主播出现两次 | 推荐映射取了 `gameInfo.poster` 和 `author.description`；多个分组里有同一主播 | 封面用卡片 `poster`，标题用 `caption`，按主播 id 去重 | site:286,292,279-309；实测 |
| REG-KUAISHOU-018 | （潜在）房间页解析偶发失败 | 用非贪婪正则截到第一个 `;`，JSON 字符串里的 `;` 会截断 | 从标记后按 JSON 结构解析 | site:448；实测 JSON 后紧跟 `;(function…` |
| REG-KUAISHOU-019 | （潜在）房间页被识别为异常客户端 | 随机 UA 中 Mac 版本号全变成 `-`；sec-ch-ua 与 Safari、Edge、Linux UA 不一致；Chrome 版本过旧 | UA 与 `sec-ch-*` 成套、使用当前版本 | ua:13,15；site:487-490 |
| REG-KUAISHOU-020 | 未开播主播进房显示“状态未知”，收藏刷新和录制报错；不存在的主播也一样 | 下播页和不存在页的 `liveStream` 没有 `poster`，旧版把 `null` 传给要求字符串的封面判断，抛出类型错误；列表卡片缺 `poster` 时整页也会失败 | 缺失字段按“空”处理；`errorType` 映射为 NotFound 等，`isLiving` 为假映射为未开播 | site:127-133,151,463；已用 Dart 复现类型错误；S11-room-offline、S12-room-notfound |
| REG-KUAISHOU-021 | （潜在）配置了代理仍直连，会话请求卡住 | 建会话用了不带请求头、不走应用代理、没有超时和取消的独立客户端 | 所有请求走注入的网络传输，带请求头、超时和取消 | site:371-374；对照 lib/core/common/http_client.dart:28-45 |
| REG-KUAISHOU-022 | 分区只显示第一页，后面的房间看不到；分类请求多、慢 | 旧版忽略 `hasMore`/`cursor`，界面只取第 1 页；二级分类的 `size` 被服务端忽略 | 用服务端的 `hasMore`/`cursor` 做不透明游标；非游戏类第 2 页起带 `cursor` 参数 | site:93,137-144；lib/modules/area_rooms/area_rooms_binding.dart:27-29；S03-non-gameboard-p2 对照 S03-non-gameboard-p2-cursor |
| REG-KUAISHOU-023 | （潜在）从搜索结果“在快手 App 中打开”时，深链里的 liveStreamId 是一个网页地址 | 同一个字段有时存 liveStreamId（列表、详情），有时存页面 URL（搜索） | liveStreamId 与页面 URL 分成两个字段 | site:161,300,477 对比 site:570；lib/modules/live_play/services/room_external_opener.dart:193-201 |
| REG-KUAISHOU-024 | 深链被注入额外参数 | liveStreamId 里的 `&path=` 覆盖了已有字段 | 逐字段查询编码；没有 liveStreamId 时只给网页 | docs/ROOM_EXTERNAL_OPEN_AUDIT_2026_09_08.md:28；test/room_external_opener_test.dart:298-299 |
| REG-KUAISHOU-025 | 带查询串或含 `_`、`-` 的分享链接解析出空 ID；搜索页被当成房间 | 旧解析用整串末尾锚点；预检只看根域名 | 按主机和路径段解析，排除导航页 | docs/LIVE_LINK_PARSER_AUDIT_2026_09_07.md:15,23；docs/TOOLBOX_ROOM_LINK_PREFILTER_AUDIT_2026_09_23.md:5 |
| REG-KUAISHOU-026 | 首页收藏刷新慢 | 刷新时也去取播放地址、签名和弹幕参数 | 轻量深度只取状态、标题、封面、人数；先不建会话直接请求 | site:416-426；docs/FAVORITE_REFRESH_DESIGN.md:61；RELEASE_NOTES.md:1632 |

## 11. 样本清单

存放在 `fixtures/kuaishou/`。每个样本附来源说明：URL、时间、DIRECT 还是经 Clash、原始响应的 SHA-256、脱敏了哪些字段（docs/rewrite/diagnosis/06-tests.md:157-160）。媒体不入库，只记录 FLV 头里的视频 codec id 和首个视频帧的编码。

2026-09-27 直连录制，匿名、不带 Cookie，共 22 个目录。实际格式按 ADR 0009：每个样本一个目录 `S<编号>-<情况>`，里面是 `body.json` 或 `body.html`、`meta.json` 和旧版期望值 `expected.json`，不再是下表原来设想的单个文件名；房间页也没有另存提取出的 state JSON。v4 解析器的测试是 packages/live_core/test/sites/kuaishou_parse_test.dart。

| # | 样本 | 请求 | 要覆盖的情况 | 期望值来源 | 已录制 |
|---|---|---|---|---|---|
| S01 | `category-type{1..8}-p1.json`、`category-type1-p2.json`、末页 | `category/data` | `hasMore` 为 true 和 false；`size` 被忽略 | 手写 | `S01-category-type1-p1` … `S01-category-type8-p1`、`S01-category-type1-p2`、`S01-category-type5-p2`（末页，`hasMore` false） |
| S02 | `gameboard-p1.json`、`gameboard-p2.json` | `gameboard/list`（游戏类分区） | 卡片映射；`hasMore` | 卡片流：旧版 `parsePlayQualities(item.playUrls)`；其它字段手写 | `S02-gameboard-p1`、`S02-gameboard-p2`（gameId 1001；p1 含 KPL 的 `【回放】` 卡片和 2K 档） |
| S03 | `non-gameboard-p1.json`、`-p2.json` | `non-gameboard/list`（`1000xxx`） | `cursor`、`labelList` | 同 S02 | `S03-non-gameboard-p1`、`S03-non-gameboard-p2`（旧版请求，不带 cursor，重复第 1 页）、`S03-non-gameboard-p2-cursor`（带 cursor 的真正第 2 页）（gameId 1000004） |
| S04 | `home-list.json` | `home/list` | 分组展平、重复主播、空子标签 | 同 S02；封面和标题按 v4 规则手写（与旧版有意不同） | `S04-home-list` |
| S05 | `search-author-{kw}-p1..pN.json` | `search/author` 同一关键词连续翻页，记录每页 `ussid` | 空页后仍有结果；在播、未开播、封禁 | 旧版 `parseAuthorSearch`；粉丝缺失的处理按 v4 手写 | **缺**：录制时 `search/author` 第 1 页就返回 `result 2`（S06），没能录到正常的搜索页 |
| S06 | `search-author-ratelimited.json` | 连续请求触发 | `result=2` | 手写：`RateLimited`（旧版返回空，不能用旧版生成） | `S06-search-author-ratelimited` |
| S07 | `search-author-noresult.json` | 不存在的关键词 | 无结果时的 `result` 值 [待确认] | 手写 | **缺**：同 S05，接口处于限流 |
| S08 | `search-livestream-busy.json` | `search/liveStream` | `result=10` 门禁 | 只作记录 | `S08-search-livestream-busy` |
| S09 | `room-live.html` + 提取出的 `room-live.state.json` | `/u/{id}` 在播 | `{h264, hevc:{}}`；JSON 后紧跟 `;(function` | 旧版 `parsePlayQualities(state.liveroom.playList[0].liveStream.playUrls)`；详情字段手写 | `S09-room-live`（`baixi9999999999`）；另录了 `S09-room-live-replay`（`KPL704668133`，`【回放】` 轮播房间的房间页） |
| S10 | `room-live-hevc.html` | 有 HEVC 描述符的房间 | HEVC 回退 | 同 S09 [待确认 能否找到] | **缺**：录到的房间页 `hevc` 都是 `{}`，卡片里也没有 HEVC 流名，没有找到 |
| S11 | `room-offline.html` | 下播主播 | 没有 `liveStream.id/poster`、`forbiddenState=671` | 手写：未开播（旧版会抛错） | `S11-room-offline`（`tianci666`） |
| S12 | `room-notfound.html` | 不存在的 id | `errorType.type=22` | 手写：`NotFound` | `S12-room-notfound`（`purelive_fixture_404`） |
| S13 | `room-replay.html` + 对应的 `home-list` 卡片 | 卡片带流但房间页下播 | 回放判定 | 手写 | 录到的回放是另一种情况：卡片标题 `【回放】`、房间页在播（S02-gameboard-p1 + S09-room-live-replay，第 4 节）。**缺**“房间页下播、卡片还带流”的情况：没有遇到 |
| S14 | `room-riskcontrol.html` | 风控或验证码页 | 风控识别 | 手写 [待确认 能否复现] | **缺**：录制时没有遇到风控或验证码页 |
| S15 | `room-set-cookie.txt` | 房间页响应头 | 匿名会话下发的 Cookie 名称和属性 | 手写 | 不单独录：S09、S11、S12 的 `meta.json` 响应头里有完整的 `set-cookie`（名称和属性原样，值已替换） |
| S16 | `feed-first.json`、`feed-next.json`、`feed-comments.json`、`feed-rejected.json`、`feed-offline.json` | `wap/live/feed` | 首轮无 cursor、带 cursor、评论和其它 type、`result≠1`、下播后 | 旧版 `parseFeedPayload` | **缺**：未录，录制时没有记下原因 |
| S17 | `media-codec.json` | 每档 FLV 前若干字节 | 视频 codec id、首帧编码、分辨率 | 探针输出（docs/PLATFORM_PROBE_2026_09_25.md:87 的做法） | **缺**：还没有媒体首部的录制方式（docs/rewrite/STATUS.md:37） |

**脱敏字段**

- 身份：`author.id`、`name`、`avatar`、`description`、`originUserId`；feed 的 `author.userName`、`userId`、`content`（换成合成文本，保持长度和字符类别）；liveStreamId 换成同格式的 11 位合成值，并在同一组样本里保持一致。
- 播放地址：`txSecret`、`wsSecret`、`hwSecret`、`ty_Secret`、`stat` 换成合成值；`auth_key` 整值替换（其中的到期时间因此是合成的）。原计划把 `txTime`、`wsTime`、`hwTime`、`ty_Time` 换成合成时间；实际录制**保留了真实值**，签发时刻就是 meta.json 的 `capturedAt`，供租期测试使用（tools/live_cli/lib/src/fixture/rules/kuaishou.dart:27-33）。
- Cookie：`did`、`client_key`、`kuaishou.live.bfb1s` 的值。
- 搜索 `ussid`（内含时间戳和关键词）：换成合成值并保持 base64 形态。
- 图片 URL 里的用户哈希（`uhead/…`）。
- 响应头 `x-ksclient-ip`：`live.kuaishou.com` 的**每个**响应都带调用方的公网 IP（22 个样本全有），整值替换（tools/live_cli/lib/src/fixture/rules/kuaishou.dart:36-39）。日志也不能记录这个头。
- 删除内部主机名 `host-name`；房间页里与房间无关的 store（`user`、`qrLoginInfo`、`emoji`、`giftSendStore` 等）可以裁掉，但保留 `liveroom` 全部内容和 HTML 中 JSON 前后各一段原文。

**旧版静态解析入口**

- `KuaishowSite.parsePlayQualities(raw)`（site:186）：房间页和列表的 `playUrls`，得到画质、排序、每档线路列表。
- `KuaishowSite.parseAuthorSearch(json)`（site:543）：主播搜索。
- `KuaishouDanmaku.parseFeedPayload(raw)`（dm:248）：feed 的 cursor、间隔、在线人数、评论。
- docs/rewrite/diagnosis/06-tests.md:161 记快手有 2 个静态入口，可能漏算了 feed 解析 [待确认]。
- 房间页解析、目录和推荐映射在旧版是私有的联网方法，没有静态入口，期望值手写。旧版在这些路径上有已知错误（REG-KUAISHOU-015、016、017、020），期望值写 v4 的正确结果，并在来源说明里列出“与旧版有意不同”的字段。
- 交叉核对：tool/interface_probe.py 的 `kuaishou.categories`、`kuaishou.home`、`kuaishou.playback`（tool/interface_probe.py:481-537,1297-1311,1428-1436）；全站探针 tool/probes/all_sites_playback_probe_test.dart。`live_cli probe kuaishou` 按“推荐 → 房间页 → 画质 → FLV 字节 → feed 一轮”走一遍，并输出租期。

## 12. 待确认

1. 分享短链 `v.kuaishou.com/{code}` 和移动页 `m.gifshow.com/fw/live/{id}` 的跳转目标格式，是否纳入 LinkResolver；`www.kuaishou.com/profile/…` 是否需要支持。
2. 主播 id 是否大小写敏感；`originUserId` 能否用于 `/u/` 路径。
3. 一级分类 1–8 是否仍与官网一致；按 id 长度选择 gameboard / non-gameboard 的官方依据。~~跨一级分类的二级分区是否重复~~：重复，“热门”的分区全都也在各自的分类里，只在分类内部去重（S01，第 2 节）。
4. ~~non-gameboard 翻页要不要回传 `cursor`、参数名~~：要，参数名 `cursor`，值是上一页的 `data.cursor`，不带就重复第 1 页（S03）。~~gameboard 只靠 `page` 是否足够~~：响应没有 cursor，两页只有 1 个重复房间（S02）。
5. 主播搜索：`ussid` 是否就是下一页的 `lssid`；“空页之后还有结果”是否稳定出现；正确的结束条件；无结果时的 `result`；限流的阈值和持续时间。已知限流按接口计（S06、S08）。录制时搜索接口一直处于限流，这几项都没能用样本回答（第 11 节 S05、S07）。
6. 搜索结果和列表里的 `living` 是否可靠。
7. 房间页 `status.forbiddenState` 的含义（在播为 1、下播为 671）；房间页的封禁表示；`errorType` 除 22 之外的取值；风控或验证码页的形状和识别方法。
8. 房间页是否有直播标题字段（三个房间页样本里都没有 `caption`）。~~封面 URL 补 `.jpg` 是否必要~~：不必要（第 4 节）。
9. ~~回放卡片是真正的回放或轮播，还是签名未过期的旧卡片~~：录到的 `【回放】` 卡片是在播的轮播房间，房间页 `isLiving` 为 true，只能靠卡片标题识别（S02-gameboard-p1、S09-room-live-replay，第 4 节）。仍待确认：“房间页下播、卡片还带流”的旧卡片是否存在。
10. `representation.hidden`、`defaultSelect`、`config.needLoginToWatchHD` 的含义，以及登录能解锁什么；`liveStream.privateLive` 为真时的表现和映射。
11. `liveStream.hlsPlayUrl` 能否作为 HLS 备用线路（实测值拼接有缺陷）。
12. HEVC FLV 是否使用传统 codec id 12。
13. CDN 主机名能否作为稳定的 cdnId；是否要用首帧分辨率核对画质。
14. 租期：签名过期后已建立的连接是否会被断开（`cutsConnection`）。~~`refreshAt` 的余量~~：v4 取 10 分钟（第 6 节）。~~过期时间是否总是签发后 24 小时~~：tx、ws、ty、bd 都是；ali-origin 的 `auth_key` 在样本里被替换，没法核对；hw-origin 样本里没有出现。
15. 播放 CDN 是否校验 Referer、Origin、UA 和 Cookie。
16. 匿名会话：什么情况下房间页会拒绝无 Cookie 请求；设备上报（misc2）是否必要；UA 是否需要随机。
17. 用户 Cookie 触发风控时是否自动改用匿名重试一次。
18. feed：`result` 各非 1 取值的含义；其它消息 type 的取值和字段；下播后 feed 的返回。
19. 静态入口数量：06-tests.md 记为 2 个，本文列出 3 个。
20. 本文“实测”结论都只观察了一次（2026-09-27，本机 WSL，未带 Cookie；是否经过 Clash TUN 未记录）。同日直连录制的样本已复核了目录、列表、推荐、房间页和租期的结论（已在正文改写为样本编号）；搜索和弹幕 feed 的结论还没有样本。规格中与 REG 条目相关的修复提交哈希，需要在第 1 阶段收尾时用 git log 补齐。
