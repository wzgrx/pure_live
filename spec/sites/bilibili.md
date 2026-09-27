# 平台规格：bilibili（哔哩哔哩直播）

- 阶段：第 1 阶段草案（从旧代码反推；2026-09-27 用录制样本复核了一部分，样本编号写作 `S06-live` 这样的目录名，见第 11 节）。
- 证据基线：`master@c28c17fb`。行号都指这个提交。
- 缩写：`S` = `lib/core/site/bilibili/bilibili_site.dart`，`D` = `lib/core/danmaku/bilibili_danmaku.dart`，`WS` = `lib/core/common/web_socket_util.dart`，`P` = `tool/interface_probe.py`。其它文件写全路径。
- 规则：本文只写行为和外部契约。“旧代码”指 v3 的现状；标“v4 规则”的是新实现必须遵守的约定；拿不准的写 [待确认]，统一汇总在第 12 节。
- 能力：目录（分类、分区房间、推荐）、搜索（房间）、详情、取流、弹幕、登录（二维码 / 网页）、醒目留言快照。没有发送弹幕、关注同步（`lib/` 中无相关接口）。旧代码里的 `searchAnchors`（S:766-797）和 `getLiveStatus`（S:799-807）没有调用方（docs/rewrite/diagnosis/01-sites.md ③-8），v4 不实现。

---

## 1. 房间身份与链接

### 1.1 房间号

| 形式 | 说明 | 证据 |
|---|---|---|
| 长号 `room_id` | 平台内部的真实房间号，详情接口 `data.room_info.room_id` 返回。弹幕凭据和弹幕认证必须用它 | S:634-635、S:641、S:581、D:187 |
| 短号 | 部分房间有较短的号码，例如分享链接 `live.bilibili.com/6`。详情里是 `room_info.short_id`，没有短号时为 0。6 对应长号 7734200：`getInfoByRoom?room_id=6` 返回 `room_id: 7734200, short_id: 6`，与用长号请求的结果相同（S06-short-id、S06-short-id-long） | test/shared_media_intake_test.dart:303；docs/ISSUE_872_BILIBILI_LOGGED_IN_DANMAKU_AUDIT_2026_09_19.md（公开房间 7734200）；P:730、P:753（用 `id=6` 请求弹幕凭据） |

- 旧代码：房间身份就是用户输入的字符串，短号和长号都有可能。卡片、链接、收藏、取流和醒目留言都用输入值（S:661、S:699-713、S:157、S:812），只有弹幕换成长号。所以同一房间的短号和长号会成为两个身份。[待确认：旧版收藏里是否真的出现过这种重复]
- 详情和取流接口都接受短号：`getInfoByRoom?room_id=6`（S06-short-id）和 `getRoomPlayInfo?room_id=6`（S07-short-id）都正常返回，响应里的 `room_id` 是长号 7734200。`SuperChat/getMessageList` 是否接受短号 [待确认]。
- 身份比较：平台 id 不区分大小写，房间号去掉首尾空白（test/live_room_error_fallback_test.dart:6-10）。
- **v4 规则**：规范身份是十进制的长号（`room_info.room_id`）。输入的短号先经详情解析，并保存为别名，用于链接回显和迁移旧数据。之后的取流、醒目留言、弹幕和 Referer 一律用长号（bilibili_parse.dart:125-137）。旧版用短号 6 作房间身份和链接，只有弹幕换成长号（DIAGNOSIS.md:100）。

### 1.2 链接格式与归一

| 输入 | 结果 | 证据 |
|---|---|---|
| `https://live.bilibili.com/{数字}`，可带路径尾、查询或片段；主机名不区分大小写 | 第一段路径就是房间号；查询和片段忽略 | lib/modules/search/web_search_room_parser.dart:153-155；test/live_url_tool_parser_test.dart:9-10；test/web_search_room_parser_test.dart:14 |
| `*.bilibili.com/{数字}`，例如 `www.bilibili.com/123` | 旧别名，也当作房间号 | lib/common/utils/live_url_tool.dart:138-140、:305-308；test/live_url_tool_parser_test.dart:23 |
| `https://b23.tv/{code}` 短链 | 只跟随重定向，不请求最终页面；重定向目标再按本表解析 | live_url_tool.dart:134、:278-292 |
| 分享文案里夹带的链接（带中文引号或句号） | 取第一个能识别的链接 | test/live_url_tool_parser_test.dart:28-30；test/shared_media_intake_test.dart:303-342 |

- b23 短链的边界（796cbcbc；test/live_short_link_test.dart:9-145）：
  - 只接受 301、302、303、307、308。
  - 相对 Location 按当前 URL 解析。
  - 跳回同一 URL，或只有片段不同，都算循环，立即停止。
  - 同一次解析最多请求 8 次。
  - 有多个 Location 时视为歧义，放弃。
  - 超时 1–12 秒，不自动跟随重定向。
- 拒绝以下输入（test/live_url_tool_parser_test.dart:39-61；test/web_search_room_parser_test.dart:39）：
  - 仿冒域名，例如 `notbilibili.com`；带 userinfo 的地址；`ftp` 协议。
  - 空路径、`%FF`、`123%2F456`。
  - `/p/eden/area-tags` 这类非数字首段，以及保留字首段（web_search_room_parser.dart:40-50、:178-185）。
  - `www.bilibili.com/video/BV…`。
- 不支持：`live.bilibili.com/h5/{id}`、`/blanc/{id}`，以及输入 `bilibili://` 深链接。[待确认：v4 是否要支持]
- 外部打开：网页用 `https://live.bilibili.com/{id}`，App 用 `bilibili://live/{id}`（lib/modules/live_play/services/room_external_opener.dart:150-151）。

---

## 2. 目录

请求头统一用 §6.3 的“接口头”。

### 2.1 分类

- `GET https://api.live.bilibili.com/room/v1/Area/getList?need_entrance=1&parent_id=0`，不签名（S:64-93）。
- 响应 `data[]` 是一级分区：`id`、`name`、`list[]`。二级分区字段：
  - `id`：分区 id。
  - `name`：名称。
  - `parent_id`：一级分区 id，后面请求分区房间时要带上。
  - `parent_name`：一级分区名称。
  - `pic`：图片，拼上 `@100w.png`。
- 一次请求返回全部分类，不分页；传入的页码和条数都被忽略。
- `need_entrance=1` 的含义 [待确认]。
- 已有探针：P:1406-1408。

### 2.2 分区房间

- `GET https://api.live.bilibili.com/xlive/web-interface/v1/second/getList`，需要 WBI 签名（§6.4）（S:95-129）。
- 参数：
  - `platform=web`
  - `parent_area_id={一级 id}`、`area_id={二级 id}`
  - `sort_type=online`（fb93afc2）
  - `page`：从 1 开始
  - `w_webid`：来自 `https://live.bilibili.com/lol` 页面 HTML 里的 `"access_id":"…"`，去掉反斜杠后使用（S:853-867；38ad5b42）
  - 另加 WBI 的 `wts`、`w_rid`。
- 没有条数参数，每页条数由服务端决定。[待确认：每页条数]
- **游客拿不到数据**：带齐 WBI 签名、buvid3/buvid4 Cookie 和 `w_webid`，第 1 页仍返回 HTTP 200、`{"code":-352,"message":"-352"}`，响应头带 `x-bili-gaia-vvoucher: voucher_…` 和 `bili-status-code: -352`（S02-signed-risk352）；不签名时同样如此（S02-risk352）。DIAGNOSIS.md:99 记录第 1–3 页都是这样。是否要先做 buvid 激活才能拿到数据，是未解决的问题（§8.1、第 12 节第 18 条）。
- 卡片字段来自 `data.list[]`（S:108-124）：
  - `roomid`、`title`
  - `cover`：拼上 `@400w.jpg`
  - `uname`、`face`
  - `online`：热度，见 §4.3
  - `area_name`
  - 列表里的房间都视为在播。
- 本页内按热度降序重排，热度相同时按房间身份排，保证顺序稳定（S:125、S:388-395）。
- 结束判断：
  - 旧代码只在 `code == -352` 时明确抛错（S:104），不读 `has_more`；翻页靠通用控制器判断：空页即结束，结果去重，最多请求 20 次，连续 2 次没有新增就停（lib/common/base/server_remote_page_controller.dart:200-241）。
  - 旧版曾读取 `data.has_more == 1`（e7c9f284 上下文、c7d0c04b 删除）。**v4 规则**：以 `has_more` 判断结束，空页作兜底。[待确认：线上是否仍返回 `has_more`]

### 2.3 推荐（热门）

- 主接口：`GET https://api.live.bilibili.com/room/v1/Area/getListByAreaID?areaId=0&parent_area_id=0&sort=online&pageSize={1..30}&page={n}`。
  - 不签名。
  - 最多试 2 次，间隔 180 ms（S:305-330）。
- 备用接口：主接口两次都失败后，请求 `GET https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getMoreRecList?platform=web&page={n}`（S:332-343）。
  - 它是个性化推荐，`online` 本身没有排序，所以只作可用性兜底（S:309-311；#786，docs/ISSUE_AUDIT_2026_08_25.md:22）。
- 两个接口共用一个解析（S:348-382）：
  - 列表：备用接口取 `data.recommend_room_list`，主接口取 `data` 本身。
  - 房间号取 `roomid` 或 `room_id`；空房间号丢弃。
  - 封面取 `cover` 或 `user_cover`，补全协议后拼 `@400w.jpg`。
  - 分区名依次取 `area_v2_name`、`area_name`、`areaName`。
  - 头像 `face`：以 `//` 开头的补成 `https:`。
  - 热度取 `online`。
  - 最后按热度稳定降序排列。
- `code != 0` 时报平台拒绝，不能变成空列表（test/bilibili_recommend_test.dart:58-60）。
- 结束判断：没有明确的结束字段，旧代码靠空页结束（bilibili_parse.dart:77-91）。
  - `getListByAreaID`：越界页（page=10000）返回 `code 0`、`data: []`（S03-out-of-range）；第 1 页 30 条（S03-page1，`pageSize=30`）。
  - `getMoreRecList`：只录了第 1 页，`data` 里只有 `recommend_room_list`（12 条）和 `top_room_id`，没有结束字段（S04-page1）。末页形态 [待确认]。
- 已有探针：P:773-797。

---

## 3. 搜索

- `GET https://api.bilibili.com/x/web-interface/search/type?context=&search_type=live&cover_type=user_cover`，不签名（S:721-764）。
- 其余参数：`order=`、`keyword`、`category_id=`、`__refresh__=`、`_extra=`、`highlight=0`、`single_column=0`、`page`（从 1 开始）、`page_size`（限制在 1–50，应用传 20）（S:723；4047cfba；lib/modules/search/search_controller.dart:380）。
- 请求头用 §6.3 的接口头，会带上 buvid 的 Cookie。不带 Cookie（没有 buvid3）也返回 `code 0`，结果与带 Cookie 时相同，不是 -412（S05-no-buvid3 对照 S05-live-results）。
- 结果分两组（S05-live-results，关键词“哔哩哔哩直播”）：
  - `data.result.live_room[]`：**只有在播的房间**，14 条的 `live_status` 全是 1。
  - `data.result.live_user[]`：名字命中的主播，**未开播和轮播的主播只在这里**（6 条的 `live_status` 是 2、2、0、0、0、0）。
  - 旧代码只读 `live_room`（S:741），未开播和轮播的主播永远搜不到（DIAGNOSIS.md:95）。
- `live_room[]` 的字段：
  - `roomid`
  - `title`：去掉 `<em class="keyword">` 高亮标签（S:745），再解码 HTML 实体（样本里没有出现实体，v4 仍然解码）
  - `user_cover`：**房间封面**。`cover` 是直播关键帧截图（`/bfs/live-key-frame/keyframe…`），不是封面；旧代码用了 `cover`（S:749；DIAGNOSIS.md:96）。v4 取 `user_cover`，没有时才退回 `cover`。都是协议相对地址，补 `https:` 后拼 `@400w.jpg`
  - `uname`
  - `uface`：头像，处理同封面
  - `online`：热度
  - `attentions`：粉丝数（S:753）
  - `live_status`：见下
  - `cate_name`：分区
- `live_user[]` 的字段：`roomid`、`uname`（带高亮标签）、`uface`、`live_status`、`cate_name`、`live_time` 等，**没有**标题、封面和热度。v4 把它们转成卡片，排在 `live_room` 之后，房间已经在 `live_room` 里的跳过；标题留空，不显示封面和热度（bilibili_parse.dart:93-123, 417-427）。
- `live_status`：1 在播，2 轮播（按 §4.3 记为回放），其它为未开播（bilibili_parse.dart:429-434）。
- 在播和未开播房间都会返回（lib/modules/search/search_capability.dart:121；docs/PLATFORM_COMPATIBILITY.md:42）。
- 分页（bilibili_parse.dart:120-122）：
  - 房间的总页数是 `data.pageinfo.live_room.numPages`（S05-live-results 共 14 条，为 1）。顶层的 `data.numPages`（50）和 `numResults`（1000）是全部类型的汇总，不能用。
  - 第 2 页的 `live_room` 为空，`live_user` 原样重复第 1 页的 6 条（S05-out-of-range）。所以 `live_user` 只取第 1 页的。
  - 结束条件：页号达到 `numPages`，或 `live_room` 为空。无结果时两组都为空、`numPages` 为 0（S05-no-results）。
- 旧代码没有检查 `code`：`code != 0` 时直接访问 `data` 会抛类型错误。v4 按 §9 处理。

---

## 4. 房间详情

### 4.1 请求

- `GET https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom?room_id={id}`，需要 WBI 签名（S:397-419）。
- 重试：最多 2 次。第 2 次先强制刷新 WBI 密钥，并间隔 180 ms。签名密钥和 buvid 的准备并行进行（S:400-410；8a57bbb2、d6c3d8df）。
- 必须签名：不签名的请求返回 `code -352`，响应头带 `x-bili-gaia-vvoucher`（S06-risk352）；签名后正常（S06-live）。
- 房间不存在：HTTP 200，`{"code":19002000,"message":"获取初始化数据失败","data":null}`，映射为 NotFound（S06-not-found，房间 999999999；bilibili_parse.dart:130）。旧代码抛 StateError。
- 响应校验（S:421-431；test/bilibili_recommend_test.dart:76-99）：
  - `code` 不为 0：报拒绝（19002000 除外，见上）。
  - `data.room_info` 或 `data.anchor_info` 不是对象：报结构错误。
  - 必须先校验再取字段。

### 4.2 字段（S:699-719）

| 输出 | 来源 |
|---|---|
| 标题 | `room_info.title` |
| 封面 | `room_info.cover`（不加尺寸后缀） |
| 主播名 | `anchor_info.base_info.uname` |
| 头像 | `anchor_info.base_info.face` + `@100w.jpg` |
| 分区 | `room_info.area_name` |
| 简介 | `room_info.description`。可能含 HTML，例如 `<p>凡人线下嘉年华</p>`（S06-replay），要转成纯文本：`<br>` 和段落结束换行，其余标签去掉，再解码实体（bilibili_parse.dart:472-484）。旧代码保留了标签 |
| 热度 | `room_info.online` |
| 网页链接 | `https://live.bilibili.com/{房间号}`，旧代码用输入值，v4 用长号 |
| 长号 | `room_info.room_id`（S:635）；短号在 `room_info.short_id`，没有时为 0 |

### 4.3 直播状态

| 状态 | 判定 | 证据 |
|---|---|---|
| 在播 | `room_info.live_status` 等于 1；数字和字符串都接受 | S:700；233d858d |
| 未开播 | `live_status` 为 0 | S:700、S:712 |
| 轮播 / 回放 | `live_status` 为 2，是轮播：房间 5440 的标题是活动预告，`online` 为 0（S06-replay）。旧代码当作未开播。**v4 规则**：记为回放（ADR 0010 的 replay），不可按直播播放。游客取流时 `playurl_info` 为 `null`，映射为 StreamUnavailable（S07-replay；§9） | S:700；bilibili_parse.dart:139-144, 169-182 |
| 其它取值 | ApiChanged。ADR 0010 没有“未知”状态 | bilibili_parse.dart:143 |
| 封禁 / 锁定 | 旧代码不识别。`room_info` 里有 `lock_status`、`lock_time`，录到的房间都是 0。[待确认：封禁时用这两个字段，还是专用错误码] | — |
| 请求失败 | 不是房间状态，按 §9 报失败 | 1f7ac128 |

- 旧代码进房时会吞掉所有错误，返回“当前房间的错误快照”或空房间（S:662-671）。收藏刷新和录制走严格路径，会把错误抛出去（S:683-697；233d858d）。**v4 规则**：详情永不吞错；下播、轮播、封禁是状态，不是失败。
- 进房时只尝试取一次弹幕凭据，失败也不影响详情（S:636-660）。刷新和录制路径不取弹幕凭据（S:686-688、S:693-695）。

### 4.4 人数的含义

| 数值 | 含义 | 证据 |
|---|---|---|
| 列表、搜索、详情里的 `online` | **热度**，不是同时在线人数 | lib/common/models/live_room.dart:41-47；docs/PLATFORM_COMPATIBILITY.md:101 |
| 弹幕 op=3 心跳回复里的 4 字节整数 | **热度** | D:315-327；test/bilibili_danmaku_protocol_test.dart:29-50 |
| 弹幕 `WATCHED_CHANGE` 的 `data.num` | **本场累计看过** | D:398-410；test/bilibili_danmaku_protocol_test.dart:107-121 |
| 同时在线人数 | 公开接口里没有；能力标为“不支持” | live_room.dart:43-47 |
| 详情 `watched_show`（`switch` 为 true 时的“N人看过”） | **本场累计看过**；未开播时不用 | S06-live；bilibili_parse.dart（v4 记为累计人数） |

- 搜索 `live_room[].live_time` 是开播时间（北京时间字符串），v4 记为开播时刻（S05-live-results）。
- 详情偶尔会返回热度 `1`。如果已有热度不小于 1000，新值不大于 1，并且小于已有值的 1%，就保留已有值；之后合理的新值照常接受（live_room.dart:739-755；1a2c4fa2；test/live_room_audience_metric_test.dart:221-250）。

---

## 5. 画质与线路

### 5.1 列表来源与顺序

- 画质列表来自一次 `qn=0` 的取流请求（§6.1）（S:131-135）。
- 选项是所有 `stream[].format[].codec[]` 的 `accept_qn` 与 `current_qn` 的并集，只保留正数，按 qn 从高到低排列（S:176-208）。
- 不能用全局的 `g_qn_desc` 当选项。它会列出不可用的档位，这些按钮永远取不到流（cafdf384；test/bilibili_play_quality_test.dart:6-11）。
- 名称优先查固定表：30000 杜比、20000 4K、10000 原画、400 蓝光、250 超清、150 高清、80 流畅。表里没有的，用 `g_qn_desc[].desc`；再没有，就显示“清晰度 {qn}”（lib/core/utils/live_quality_label.dart:37-49；test/live_quality_label_test.dart:26-28）。
- 现在的 `g_qn_desc` 多了 15000 `2K`（S07 全部样本：30000 杜比、20000 4K、15000 2K、10000 原画、400 蓝光、250 超清、150 高清、80 流畅）。15000 不在固定表里，名称取 `g_qn_desc` 的 `2K`。

### 5.2 服务端降档与确认

- 请求时带 `qn={所选}`。每个 codec 条目都有自己的 `current_qn`，这是服务端实际给出的档位（S:214-265）。
- 候选线路排序规则（S:240-252）：
  1. `current_qn` 等于请求 qn 的排前面；
  2. 协议：`http_stream` 在前，`http_hls` 在后；
  3. 格式：`flv` < `ts` < `fmp4` < 其它；
  4. 编码：`avc` 在前；
  5. 主机含 `mcdn` 的排后面；
  6. 最后按 URL 字典序。
- 实际画质取排序后第一条的 `current_qn`。只保留这个档位的 URL，并去重（S:257-264）。
- 游客可能在请求 10000 时拿到 250。这时界面和录制都必须显示 250，不能假装切换成功（S:210-213；test/bilibili_play_quality_test.dart:13-22；docs/RECORDING_AND_QUALITY_AUDIT_3_0_12.md:13）。
- 游客实测（2026-09-27）：
  - `accept_qn` 是 `[10000, 400, 250]`（房间 42062），有的房间多一个 150（7734200 是 `[10000, 400, 250, 150]`）；
  - `qn=0` 和 `qn=10000` 的 `current_qn` 都是 250（S07-guest-qn0、S07-guest-qn10000），也就是游客最高只能拿到超清；
  - 带 `codec=0,1` 时，250 档同时给出 AVC 和 HEVC，FLV、TS、fMP4 三种格式都有（S07-hevc-qn10000）。v4 只保留排第一的编码（AVC），同一组线路不混用 AVC 和 HEVC（bilibili_parse.dart:203-213）。
- **v4 规则**：每条线路都记录请求档位、实际档位（`current_qn`）和“是否已确认”。
- 登录后哪些 qn 能拿到、哪些需要大会员 [待确认]（没有登录样本）。

### 5.3 线路（CDN）标识

- 一条线路 = `url_info[i].host` + `codec.base_url` + `url_info[i].extra`。不以 `http` 开头的丢弃（S:224-237）。
- 旧代码把线路当成 URL 列表，按下标选择。只在排序时用 `mcdn` 子串识别 P2P / 边缘节点。
- **v4 规则**：线路标识 = 主机名 + 协议名 + 格式名 + 编码名。刷新后按这个标识找回同一条线路，不按下标。
- 历史上屏蔽过 `gotcha104` 主机，也把 `mcdn` 改写到代理，后来都撤销了（d4b0080d、1688cf7d、023de604）。[待确认：这两类主机现在是否仍然不稳定]

---

## 6. 取流

### 6.1 请求

- `GET https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo`，不签名（S:153-171）。
- 参数：
  - `room_id`：旧代码用输入值，v4 用长号
  - `protocol=0,1`：0 是 http_stream，1 是 http_hls
  - `format=0,1,2`：分别是 flv、ts、fmp4
  - `codec=0`：只要 AVC
  - `qn`：列画质时为 0，取地址时为所选档位
  - `platform=web`（原来是 `html5`，cafdf384 改掉）
  - `ptype=8`、`dolby=5`、`panorama=1`、`mask=0`、`no_playurl=0`
- 结构：`data.playurl_info.playurl` 下有：
  - `g_qn_desc[]`：`qn`、`desc`
  - `stream[]`：`protocol_name`、`format[]`
  - `format[]`：`format_name`、`codec[]`
  - `codec[]`：`codec_name`、`current_qn`、`accept_qn[]`、`base_url`、`url_info[]`
  - `url_info[]`：`host`、`extra`
  - 取值逻辑见 S:267-293。
- `code != 0` 报拒绝；`playurl` 缺失报结构错误（S:267-277）。
- 未开播（`live_status` 0）和轮播（`live_status` 2）的房间返回 `code 0`，但 `playurl_info` 是 `null`（S07-offline、S07-replay）。这是 StreamUnavailable，不是结构错误（bilibili_parse.dart:169-182）。旧代码抛 FormatException，游客无法播放轮播（DIAGNOSIS.md:97）。
- 在播房间也可能短时间没有播放描述，探针因此会轮询多个房间（P:810-813）。
- 旧代码不请求 HEVC（`codec=1`）。探针普查显示 B 站各档 FLV 都是 AVC（docs/PLATFORM_PROBE_2026_09_25.md:87）。游客请求 `codec=0,1` 时 250 档 AVC、HEVC 都有（S07-hevc-qn10000）。[待确认：4K、杜比等档位是否只有 HEVC；游客的 `accept_qn` 里没有这些档位，需要登录样本]

### 6.2 格式

| `protocol_name` / `format_name` | 格式 | 旧代码排位 |
|---|---|---|
| `http_stream` / `flv` | FLV | 第一 |
| `http_hls` / `ts` | HLS（TS 分片） | 第二 |
| `http_hls` / `fmp4` | HLS（fMP4 分片） | 第三；录制诊断把“B 站 fMP4 HLS”列为需要的样本（docs/rewrite/diagnosis/04-recorder.md:139） |

### 6.3 请求头

| 用途 | 头 | 证据 |
|---|---|---|
| 接口请求（api.live / api / live 域名） | `user-agent`：桌面 Chrome 138；`referer: https://live.bilibili.com/`；`cookie`：登录 Cookie（缺 buvid3 时补上），或游客的 `buvid3=…;buvid4=…;` | S:28-30、S:37-62 |
| 媒体请求（播放、录制、多画面共用） | `user-agent`：同上；`origin: https://live.bilibili.com`；`referer: https://live.bilibili.com/{房间号}`；`cookie`：登录 Cookie，否则游客 buvid。**不能**带 `authority` 或浏览器导航类头 | lib/player/core/playback_header_resolver.dart:53-66；842fe3a3；test/playback_header_resolver_test.dart:49-71 |
| 图片（`hdslb.com` 及子域） | `Referer: https://live.bilibili.com/`；浏览器 UA | lib/common/utils/network_image_url.dart:29-40；e576266e；test/network_image_url_test.dart:27-30 |
| 弹幕 WebSocket | 见 §7.2 | S:621-626 |
| 账号校验 | 只带 `Cookie` | lib/common/services/settings/bilibili_account_service.dart:191-198 |

- 媒体 CDN 实际必需哪些头（Referer、Origin、Cookie 缺一个会怎样）[待确认]。旧代码四个都发。
- **v4 规则**：请求头写进每条线路，播放层不再按平台分支拼头（01-sites ③-3）。

### 6.4 WBI 签名

- 需要签名的接口：分区房间、房间详情、弹幕凭据。
- 不签名的接口：取流、分类、推荐、搜索、醒目留言、spi、nav、二维码、账号（S:102、S:408、S:581）。
- 密钥：
  - 从 `GET https://api.bilibili.com/x/web-interface/nav` 的 `data.wbi_img.img_url` 和 `sub_url` 中，取文件名去掉扩展名，分别得到 imgKey 和 subKey（S:524-541）。
  - 未登录时 nav 返回 `code -101`（`账号未登录`），但 `data.wbi_img.img_url`、`sub_url` 照样给出，`data.isLogin` 为 false（S11-guest）。所以取密钥时不能因为 `code != 0` 就放弃；旧代码不检查 `code`，结果是对的。
  - 缓存 6 小时，并发请求合并（S:503-522；bbc69d58、d6c3d8df）。
- mixinKey：按固定的 64 项置换表重排 imgKey + subKey，取前 32 个字符（S:437-502、S:543-546；P:746-752 有一份独立实现）。
- 签名步骤（S:548-572）：
  1. 加 `wts` = 当前 Unix 秒；
  2. 参数按 key 排序；
  3. 从值中删去 `!'()*` 这几个字符；
  4. 拼成 `k=v&…`，值做百分号编码；
  5. `w_rid = md5(query + mixinKey)`。
- 空格编码：旧代码用 `Uri.encodeQueryComponent`（空格变 `+`），P:755 用 `urlencode`（也是 `+`）。现有签名参数都不含空格，所以没踩到。[待确认：v4 用 `%20` 还是 `+`]
- 签名失败（-352）的处理：强制刷新密钥，再重试一次（§9）。

### 6.5 租期

- 旧代码没有给 B 站实现租期和恢复接口：`S:17` 没有实现 `LivePlayLeaseMetadata` 或 `LivePlayRecoveryResolver`（lib/core/interface/live_site.dart:163-193）。线路按“长期有效”处理；出错后重新取流（录制遇 403、404、EIO 会重新解析：docs/ISSUE_AUDIT_2026_08_25.md:19）。
- 样本（S07 的 5 个在播响应）：
  - 每条 `url_info[].extra` 都有 `expires=<Unix 秒>`，等于签发时刻 + 3600 秒（例如 S07-guest-qn0 在 09:53:23 录制，`expires=1790506404` 是 10:53:24）；
  - 部分 FLV 线路另有 `deadline=`，值与 `expires` 相同（S07-guest-qn10000、S07-hevc-qn10000）；
  - `url_info[].stream_ttl` 恒为 0，没有意义。
- **v4 规则**（bilibili_parse.dart:292-313）：

| Lease 字段 | 取值 |
|---|---|
| `issuedAt` | 取流响应的时刻 |
| `invalidAt` | `extra` 里的 `expires`（Unix 秒）。没有 `expires`，或已经过期，就没有租期 |
| `refreshAt` | `invalidAt` − 60 秒；寿命不到 4 分钟时改为 `invalidAt` − 寿命的 1/4 |
| `cutsConnection` | false：到期只预取新地址，不重开正在播放的连接。到期后已建立的连接会不会被断开 [待确认]：旧代码按 false 处理；仓库里没有超过 10 分钟的 B 站连续播放或录制证据（docs/PERFORMANCE.md:113 为 6.5 分钟），需要样本 #8 的长连接记录 |

- 恢复（`recover`）必须重新请求详情和取流，不能复用缓存的 URL（live_site.dart:163-169）。

---

## 7. 弹幕

### 7.1 凭据

- `GET https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo?id={长号}&type=0`，需要 WBI 签名，请求头同接口头（S:574-596）。
- 成功条件：`code == 0` 且 `data.token` 非空。
- 重试：
  - 最多 4 次；第 2 次和第 4 次前强制刷新 WBI；间隔 180、360、540 ms。
  - 进房时只试 1 次；失败时 token 留空，交给连接层补取（S:641、S:643-659）。
- 端点列表（S:598-609）：
  1. 固定先放通用网关 `wss://broadcastlv.chat.bilibili.com/sub`；
  2. 再按 `data.host_list[]` 生成 `wss://{host}[:{wss_port}]/sub`：端口 443 时省略，缺省按 443，去重。
  - 实测 `host_list` 的 `wss_port` 都是 2245（`port` 2243、`ws_port` 2244），6 项里也包括 `broadcastlv.chat.bilibili.com`；所以生成的是 `wss://…:2245/sub`（S09-guest）。游客的 `getDanmuInfo` 也返回 `code 0` 和非空 `token`。
  - 原因：部分运营商和移动网络的 DNS 解析不到区域节点（docs/ISSUE_AUDIT_2026_08_16.md:9）。

### 7.2 连接与认证

- WebSocket 头：`user-agent`、`origin: https://live.bilibili.com`、`referer: https://live.bilibili.com/{长号}`、`cookie`（与接口头同一份）（S:621-626）。连接超时 10 秒（WS:170）。
- 开始连接时 token 为空：先补取凭据，最多 3 次，间隔 500 ms、1000 ms；仍为空就以“连接信息仍在更新”结束（D:105-122）。
- socket 打开后立即发认证包（op=7）（D:137-138、D:179-197）：

| 字段 | 值 |
|---|---|
| `uid` | §8.2 的 uid；游客为 0 |
| `roomid` | 长号 |
| `protover` | 2（v4，2026-09-27 实测服务端回 zlib 包；旧版为 3 即 brotli，v4 不引入 brotli 包，见 docs/adr/0019-danmaku-layer.md） |
| `buvid` | 当前 buvid3 |
| `support_ack` | true |
| `queue_uuid` | 每次认证新生成的 8 位小写十六进制随机数 |
| `scene` | `"room"` |
| `platform` | `"web"` |
| `type` | 2 |
| `key` | token |

  依据：52db99fb、9b4eb33b；test/bilibili_danmaku_protocol_test.dart:123-155。
- 认证回复（op=8）（D:341-357）：
  - 正文为空，或 `code == 0`：连接可用，立即发一次心跳。
  - `code != 0`：重新取凭据并重连；每次开始连接后最多 3 次（D:161-177）。
- socket 打开后 8 秒内没有收到认证成功，就重连（D:139-142）。

### 7.3 帧格式

- 头 16 字节，大端（D:232-258、D:276-312；bbc69d58 改为无符号读取）：

| 偏移 | 长度 | 含义 |
|---|---|---|
| 0 | 4 | 包总长 |
| 4 | 2 | 头长，固定 16 |
| 6 | 2 | protover：0 为 JSON，1 为 int32，2 为 zlib，3 为 brotli |
| 8 | 4 | op |
| 12 | 4 | seq，发送时固定 1 |

- 客户端发出的包 protover 为 0（D:246）。
- 一条 WebSocket 消息里可能拼接多个包。压缩包（protover 2 或 3）解压后是**另一段完整的包序列**，要递归按 16 字节头拆分，不能按控制字符切 JSON（D:271-275、D:330-334）。
- op 一览：

| op | 方向 | 内容 |
|---|---|---|
| 2 | 发送 | 心跳，正文为空 |
| 3 | 接收 | 心跳回复，4 字节热度 |
| 5 | 接收 | 通知（JSON 或压缩包） |
| 7 | 发送 | 认证 |
| 8 | 接收 | 认证回复 |
| 24 | 发送 | ACK |

  证据：D:213-216、D:315-357、D:439-447。
- 硬上限（6458d541；test/bilibili_danmaku_protocol_test.dart:52-84）：
  - 单条消息不超过 8 MiB；
  - 解压后不超过 16 MiB，边解压边检查；
  - 单条消息不超过 4096 个包；
  - 压缩最多嵌套 2 层；
  - 帧长为 0、截断、头长小于 16：只丢弃这条消息剩下的部分，连接和后续消息照常。

### 7.4 消息解码

| cmd | 输出 | 字段 |
|---|---|---|
| 包含 `DANMU_MSG`，例如 `DANMU_MSG:4:0:2:2:2:0` | 聊天 | 文本取 `info[1]`；颜色取 `info[0][3]`，0 为白色；用户 id 取 `info[2][0]`；时间取 `info[0][4]`，大于 1e11 按毫秒、否则按秒；消息 id 为 `bilibili:` + `info[0][5]`（D:374-397） |
| `WATCHED_CHANGE` | 本场累计看过 | `data.num`，不小于 0 才用（D:398-410） |
| `SUPER_CHAT_MESSAGE` | 醒目留言 | `data.message`、`price`、`start_time` 和 `end_time`（秒）、`background_color`、`background_bottom_color`、`user_info.uname`、`user_info.face` + `@200w.jpg`（D:411-433） |
| 其它 | 忽略 | 礼物、进场、开播、下播、封禁等都不处理。[待确认：v4 需要哪些] |

- 用户名的取法（D:449-492；879813f5；测试 86-105）：
  1. 候选依次为：`info[0][15]`（可能是 JSON 字符串）的 `user.base.name` 或 `origin_info.name`、顶层 `uinfo`、`data.uinfo`、`info[2][1]`；
  2. 选第一个不含 `**` 或 `＊＊` 的；
  3. 全部被打码时用第一个候选。
- 游客会话下，平台会把旧用户名、rich user 名称和 uid 一起打码，这是平台返回的数据，不是客户端问题（RELEASE_NOTES.md:2012；docs/PLATFORM_COMPATIBILITY.md:202）。

### 7.5 ACK

- 通知 JSON 里 `p_is_ack == true`，且 `msg_id`、`cmd`、`p_msg_type` 都存在（`p_msg_type` 为整数）时，回一个 op=24 包，正文为 `{"msg_id","cmd","p_msg_type"}`（D:439-447）。
- 字段不全就不回 ACK，但这条聊天照常输出（test/bilibili_danmaku_protocol_test.dart:157-205）。

### 7.6 心跳与重连

- 认证成功后立即发心跳，之后每 30 秒一次（D:63、D:350；WS:239-250）。
- 超过 max(3 × 心跳间隔, 90 秒) 没收到任何消息，就重连（WS:253-259）。
- 重连规则（WS:124、WS:267-292）：
  - 换下一个端点；
  - 最多 8 次；
  - 等待时间 = 1 秒 × (已轮完的整轮数 + 1)，最多 6 倍；
  - 收到任何消息后计数清零。
- 重连后沿用原 token；只有认证被拒才换 token（D:137-138、D:352-356）。token 有多长有效期 [待确认]。
- 事件区分：暂时断开发“重连中”；超过最大次数才发“最终关闭”（80c87c0e）。

### 7.7 醒目留言快照（HTTP）

- `GET https://api.live.bilibili.com/av/v1/SuperChat/getMessageList?room_id={id}`，取 `data.list[]`，字段同 §7.4（S:809-831）。
- 调用时机：直播状态确认之后才请求；同房间刷新时不清空已有留言（lib/modules/live_play/controllers/live_play_controller.dart:315-326；docs/ROOM_DETAIL_ERROR_STATUS_AUDIT_2026_09_24.md“同房重试期间的付费消息”）。
- 旧代码用输入的房间号。[待确认：短号是否可用]

---

## 8. 登录与 Cookie

### 8.1 匿名（游客）

- buvid 的获取（S:45-54、S:833-851）：
  - 请求 `GET https://api.bilibili.com/x/frontend/finger/spi`，请求头为 UA、Referer，以及已存的 Cookie；
  - 取 `data.b_3` 作 buvid3，`data.b_4` 作 buvid4；
  - 同时进行的请求合并为一个。
  - 失败时得到空值，下次请求再取。
- 已存的 Cookie 里有 `buvid3` 时直接用它（S:38-44）。
- 游客能做的：
  - 公开弹幕（uid=0，已实连验证：docs/ISSUE_AUDIT_2026_08_16.md:35）；
  - 目录、搜索、详情、取流。
- 游客受到的限制：昵称和 uid 被打码；画质可能被降档。
- 未做 buvid 激活（ExClimbWuzhi 接口）和 `b_nut`、`_uuid` 等字段。游客请求分区房间时，带齐 WBI、buvid3/buvid4 和 `w_webid` 仍然 -352（S02-signed-risk352，§2.2）。[待确认：buvid 激活能否让游客拿到分区房间]

### 8.2 登录凭据

- 旧代码存两项，都是明文（lib/common/services/settings/cookie_settings_controller.dart:10-11；docs/rewrite/diagnosis/05-app-shell-data.md:54）：
  - `bilibiliCookie`：整串 Cookie；
  - `bilibiliUid`：整数。
- Cookie 规范化：去掉控制字符和首尾空白（lib/common/services/settings/cookie_value.dart:1-6）。
- 旧代码会读取的字段：
  - `DedeUserID`：uid，严格匹配 `DedeUserID=数字`，不区分大小写（S:674-681）；
  - `buvid3`、`buvid4`（S:38-44）。
- 其余字段（`SESSDATA`、`bili_jct` 等）原样转发，旧代码不解析。[待确认：必需字段的最小集合]
- **uid 来源的优先级**（52db99fb；test/bilibili_danmaku_protocol_test.dart:207-218）：
  1. Cookie 为空时为 0；
  2. 否则用同一份 Cookie 里的 `DedeUserID`；
  3. 否则用已校验过的 uid（大于 0 时）；
  4. 否则为 0。
- 校验：`GET https://api.bilibili.com/x/member/web/account`，只带 Cookie（bilibili_account_service.dart:97-130、:191-198）：

| 响应 | 处理 |
|---|---|
| `code == 0` 且 `data.uname` 非空 | 已登录；`data.mid` 存为 uid |
| `code != 0` | 登录失效：清空 Cookie 和 uid，并清空 WebView 里的 Cookie（:163-180） |
| 网络错误 | 只提示，不登出 |

- 较旧的校验结果不能覆盖较新 Cookie 的状态（test/account_identity_lifecycle_test.dart:43-156）。
- **v4 规则**：
  - 凭据加密保存（宪法原则 8）；
  - 适配器只通过只读的 CredentialStore 取凭据，不直接读设置（01-sites ②）；
  - uid 必须和 Cookie 来自同一份凭据。
  - 校验结果按类型处理（2026-09-28，F-ACC-01）：只有 `code -101`（NeedsLogin）算登录失效，清空 Cookie 和 uid；用户退出登录时同时清空内置浏览器的 Cookie。-352（RiskControl）、-412（RateLimited）、网络错误和其它 `code != 0`（ApiChanged）只提示“校验失败”，不登出——旧版遇到任何 `code != 0` 都登出，风控时会把有效的登录清掉。
  - 账号页进入时自动校验一次；未校验前只显示同一份 Cookie 里的 `DedeUserID`。界面和日志都不显示 Cookie。

### 8.3 二维码登录（lib/modules/account/bilibili/qr_login_controller.dart）

- 生成：`GET https://passport.bilibili.com/x/passport-login/web/qrcode/generate`，取 `data.qrcode_key` 和 `data.url`。地址必须是 HTTPS（:10-19、:272-283）。
- 轮询：`GET …/qrcode/poll?qrcode_key=`，上一次完成后再等 3 秒发下一次（:42、:242-256、:285-302）。

| `data.code` | 状态 |
|---|---|
| 0 | 成功：从响应的 `Set-Cookie` 里取各个 `name=value`，用 `;` 拼接，再去校验（§8.2） |
| 86101 | 未扫码 |
| 86090 | 已扫码，等待确认 |
| 86038 | 已过期 |
| 其它 | 失败 |

  代码位置：:161-177、:184-210。
- 外层 `code != 0` 或网络错误时退避，间隔分别为 2、3、4 倍；连续 3 次失败后停止（:212-220）。
- 刷新二维码会作废旧二维码的轮询结果（:80-99；test/bilibili_login_lifecycle_test.dart:51-82）。
- **v4**（apps/pure_live/lib/features/accounts/bilibili_qr_login.dart）：按失败类型区分。没有得到答复的轮询——网络错误、RateLimited（-412、HTTP 412）、RiskControl（-352）——退避 2 倍、3 倍，第 3 次连续失败停止（4 倍用不到）；ApiChanged（未知的 `data.code`，或其它外层 `code != 0`）立即失败，不再重试。确认后先校验（§8.2）再保存；校验不通过不保存。

### 8.4 网页登录（lib/modules/account/bilibili/web_login_controller.dart）

- 在 WebView 中打开 `https://passport.bilibili.com/login`（:331）。
- 导航到 HTTPS 的 `m.bilibili.com` 或 `www.bilibili.com` 时，读取 WebView 中该地址的 Cookie，拼接后去校验（:374-388、:498-504）。
- **v4**（apps/pure_live/lib/features/accounts/web_login.dart；网页组件见 docs/adr/0032-webview.md）：取消这次导航，读该地址的全部 Cookie（含 HttpOnly 的 `SESSDATA`），拼成 `name=value; …`，校验通过才保存；失败回到网页并提示。Android 用 webview_flutter，Windows 用 WebView2（缺运行时时提示安装），其它平台不显示网页登录。

---

## 9. 错误与风控

旧代码的情况：
- 大多数错误被包成 `Exception(e.toString())`（S:91、S:127、S:149）；
- 进房失败被吞掉（S:662-671）；
- -352 是界面层用字符串匹配出来的，并且被当成“需要登录”（lib/modules/area_rooms/area_rooms_controller.dart:25-26、:60、:87）；
- 没有取消（cancel）机制；
- 412 没有任何专门处理，HTTP 非 2xx 由 dio 直接抛出（lib/core/common/http_client.dart:41-50）。

**v4 映射**（D 表示弹幕连接状态，不是请求失败）：

| 触发条件 | SiteFailure | 处理 | 证据 |
|---|---|---|---|
| DNS、TLS、连接或读超时（20 秒）、5xx | Network | 可重试 | http_client.dart:11-13 |
| 签名接口返回 JSON `code == -352`（HTTP 200，响应头带 `x-bili-gaia-vvoucher` 和 `bili-status-code: -352`） | 先强制刷新 WBI（和 buvid），重试 1 次；仍为 -352 就是 **RiskControl** | 界面不能再显示“需要登录”。旧代码把它包成两层异常（`Exception: Exception: …`），界面拿不到类型（DIAGNOSIS.md:98） | S:104；S:405-417；area_rooms_controller.dart:25；test/bilibili_recommend_test.dart:58-60、:90-99；RELEASE_NOTES.md:1875；S02-risk352、S02-signed-risk352、S06-risk352 |
| HTTP 412，或 JSON `code == -412` | **RateLimited**：退避，不立即重试，不刷新签名 | [待确认：412 是频率风控还是设备风控] | 旧代码无处理 |
| `code == -101`（未登录），或账号校验 `code != 0` | **NeedLogin**；如果已存有 Cookie，视为登录失效并清除凭据。例外：nav 的 -101 仍带 `wbi_img`，取密钥时照常使用（§6.4） | | bilibili_account_service.dart:105-108；S16-no-cookie；S11-guest |
| 详情显示房间不存在：HTTP 200，`code 19002000`，`message` 为 `获取初始化数据失败`，`data` 为 null | **NotFound** | 60004 和 -404 在详情接口上也按 NotFound 处理，但没有样本 [待确认] | S06-not-found；bilibili_parse.dart:125-130 |
| 房间封禁或锁定 | 不是失败：房间状态“封禁” | [待确认：判定字段] | 01-sites ⑥ |
| 付费直播、大航海专属 | **AgeOrPaid** | [待确认：B 站是否有这类房间以及如何识别] | — |
| 港澳台或海外限制 | **RegionRestricted** | [待确认：返回形态] | — |
| 在播，但 `playurl_info` 为空或没有线路；轮播（`live_status` 2）的 `playurl_info` 为 null | **StreamUnavailable**，可稍后重试 | | S:254-256、S:275；P:810-813；S07-replay |
| 未开播时取流 | 不是失败：先看详情状态，不去取流 | | S:700 |
| `current_qn` 低于请求 qn | 不是失败：记为画质降档 | | S:210-213 |
| 媒体 403、404、连接提前结束 | 重新取流一次后仍失败：**StreamUnavailable** | | docs/ISSUE_AUDIT_2026_08_25.md:19 |
| 响应不是 JSON，或缺少 `room_info`、`anchor_info`、`playurl`、列表等关键结构 | **ApiChanged** | | S:268、S:275、S:356、S:423-429 |
| 其它 `code != 0`，例如 -400 | **ApiChanged**，附带原始 code 和 message | [待确认：是否有需要单独归类的码] | S:270、S:351 |
| 用户取消、离开页面 | **Cancelled**：只取消自己的请求 | | 01-sites ⑤（a482e576） |
| D：弹幕凭据取不到 | 不影响详情；连接状态为“凭据未就绪”，由连接层补取 | | S:637-660；D:105-122 |
| D：认证回复 `code != 0`，换 3 次 token 仍被拒 | 连接终止，原因为 RiskControl | [待确认：认证失败码的含义] | D:161-177、D:352-356 |
| D：重连 8 次都失败 | 连接终止，原因为 Network | | WS:276-280 |

- 二维码登录的 86038、86090、86101 是流程状态，不是 SiteFailure。

---

## 10. 踩过的坑

编号是 v4 回归测试的 id。

**REG-BILIBILI-001 选了高画质却没生效**
- 现象：选“原画”，实际播的是超清，界面仍显示原画。
- 根因：游客请求被服务端降档。旧逻辑以为请求的 qn 一定生效。
- 正确做法：按 `current_qn` 回写实际档位，线路只保留这一档（§5.2）。
- 证据：cafdf384；S:210-265；test/bilibili_play_quality_test.dart:13-22；docs/RECORDING_AND_QUALITY_AUDIT_3_0_12.md:13。

**REG-BILIBILI-002 出现取不到流的画质按钮**
- 现象：点某些画质按钮没有任何反应。
- 根因：用全局 `g_qn_desc`，或只用第一个 codec 的 `accept_qn` 生成选项。
- 正确做法：选项取所有 codec 的 `accept_qn` 与 `current_qn` 的并集，从高到低排列。
- 证据：cafdf384；S:173-208；test/bilibili_play_quality_test.dart:6-11。

**REG-BILIBILI-003 热门页一直 -352**
- 现象：热门列表加载失败。
- 根因：旧的签名接口 `second/getListByArea` 持续触发风控。
- 正确做法：换用匿名接口，有界重试，并保留另一个匿名接口作回退。
- 证据：e576266e；RELEASE_NOTES.md:1875。

**REG-BILIBILI-004 热门不是按热度排的**（#786）
- 现象：“热门”页的热度数字忽高忽低，不成排行。
- 根因：`webMain/getMoreRecList` 是个性化推荐，`online` 没有排序。
- 正确做法：主接口改用 `getListByAreaID?sort=online`，推荐流只作回退，拿到结果后再做本地稳定降序。
- 证据：fb93afc2；S:305-395；docs/ISSUE_AUDIT_2026_08_25.md:22；test/bilibili_recommend_test.dart:6-37、:62-73。

**REG-BILIBILI-005 分区打不开或列表为空**
- 现象：分类页报错或为空。
- 根因：分区接口要求 WBI 签名、buvid3/buvid4 Cookie，以及 `w_webid`。
- 正确做法：三者都要带（§2.2）。
- 证据：a035ebd6、e7c9f284、38ad5b42。
- 注意：2026-09-27 游客三者都带仍然返回 -352（S02-signed-risk352），这条回归目前只能在登录态或解决 buvid 激活之后验证（第 12 节第 18 条）。

**REG-BILIBILI-006 风控被显示成“未登录”**
- 现象：分区页出现 -352 后提示登录，登录后照样不行。
- 根因：界面层用 `toString().contains("-352")`，以及 NoSuchMethodError 的字符串，来判断“需要登录”；其它 `code != 0` 还会在取 `data["list"]` 时崩溃。
- 正确做法：适配器先校验 `code`，再抛出有类型的 RiskControl 或 ApiChanged。
- 证据：lib/modules/area_rooms/area_rooms_controller.dart:25-26；S:104-108。

**REG-BILIBILI-007 房间信息间歇性被拒**
- 现象：详情偶尔被拒，接着就在取 `null` 的字段时崩溃。
- 根因：WBI 密钥过期；响应没校验就直接取字段。
- 正确做法：密钥缓存 6 小时；被拒时强制刷新再重试 1 次；先校验 `code` 和结构。
- 证据：bbc69d58、8a57bbb2；S:397-431；test/bilibili_recommend_test.dart:76-99。

**REG-BILIBILI-008 弹幕显示“已连接”但没有消息**
- 现象：认证成功，但 `DANMU_MSG` 被丢掉。
- 根因：解压后按控制字符切 JSON，包头字节混进了文本；一条消息里的多个包、嵌套压缩包没有拆开；长度字段按有符号数读取。
- 正确做法：按 16 字节头递归拆包，用无符号读取（§7.3）。
- 证据：bbc69d58；D:271-312；test/bilibili_danmaku_protocol_test.dart:12-50。

**REG-BILIBILI-009 畸形帧导致死循环或内存暴涨**
- 现象：帧长为 0 时解析死循环；高压缩比的包把内存撑爆。
- 根因：没有对帧长、包数、解压输出和嵌套层数设上限。
- 正确做法：按 §7.3 的硬上限处理，出错只丢弃当前这条消息。
- 证据：6458d541；D:56-60、D:360-367；test/bilibili_danmaku_protocol_test.dart:52-84。

**REG-BILIBILI-010 弹幕连接不稳定**（#681、#687、#689、#700）
- 现象：换过 WBI 或 token 后弹幕不来；部分移动网络连不上；弹幕拖慢进房。
- 根因：
  - 认证失败后一直沿用旧凭据；
  - 取弹幕凭据和加载房间串行执行；
  - 部分 DNS 解析不到区域节点；
  - socket 打开后没有认证超时。
- 正确做法：
  - 先播放，弹幕凭据后台补取；
  - 通用网关排在最前，再轮换区域节点；
  - 认证被拒就换 token；
  - 8 秒内没有认证回复就重连。
- 证据：842fe3a3；docs/ISSUE_AUDIT_2026_08_16.md:9；S:598-609；D:139-142、D:161-177。

**REG-BILIBILI-011 登录后没有弹幕**（#872）
- 现象：显示“已连接”，但没有聊天消息。
- 根因：认证包缺 `support_ack`、`queue_uuid`、`scene`；没有回 op=24 ACK；uid 与当前 Cookie 不一致。
- 正确做法：按 §7.2 和 §7.5 发送，uid 按 §8.2 的优先级取。
- 证据：52db99fb、9b4eb33b；docs/ISSUE_872_BILIBILI_LOGGED_IN_DANMAKU_AUDIT_2026_09_19.md。
- 注意：修复只在游客会话上实连验证过，登录态在真机上的复现仍 [待确认]。

**REG-BILIBILI-012 认证包里的 uid 写错**
- 现象：弹幕身份错乱；部分房间里，游客的连接被网关断开。
- 根因：
  - 曾把某个固定 uid（22836336）写死在代码里（0cbd3938 引入，9a5bdac7 修复）；
  - 游客认证时带了残留的旧 uid（842fe3a3 的注释）。
- 正确做法：游客 uid=0；登录用户的 uid 取自同一份 Cookie。
- 证据：S:674-681。

**REG-BILIBILI-013 游客看到的昵称带星号**
- 现象：弹幕昵称是 `***`。
- 根因：游客会话下平台对昵称打码。
- 正确做法：优先使用未打码的 rich user 名称；全部被打码时如实显示，并提示登录可看完整昵称。
- 证据：879813f5；D:449-492；RELEASE_NOTES.md:2012-2014。

**REG-BILIBILI-014 热度被当成在线人数**
- 现象：几百万热度被显示成同时在线人数。
- 根因：没有区分热度、累计看过和在线三种口径。
- 正确做法：按 §4.4 分字段保存和显示。
- 证据：879813f5；lib/common/models/live_room.dart:41-47；docs/PLATFORM_COMPATIBILITY.md:101。

**REG-BILIBILI-015 热度瞬间掉到 1**
- 现象：进房后，热度从几十万跳到 1。
- 根因：详情接口偶尔返回值为 1 的哨兵热度。
- 正确做法：按 §4.4 的规则保留列表里的热度。
- 证据：1a2c4fa2；live_room.dart:739-755；test/live_room_audience_metric_test.dart:221-250。

**REG-BILIBILI-016 CDN 请求头错误；录制能不能播和播放器不一致**（#791）
- 现象：录制报输入 I/O 错误，播放器却能播。
- 根因：媒体请求带了 `authority: api.bilibili.com` 和浏览器导航类头；录制器自己另有一套请求头。
- 正确做法：媒体头只用 §6.3 那几个；播放、录制和多画面共用同一套。
- 证据：842fe3a3；docs/ISSUE_AUDIT_2026_08_25.md:19、:31-32；lib/player/core/playback_header_resolver.dart:53-66。

**REG-BILIBILI-017 封面和头像加载失败**（Windows）
- 现象：B 站图片加载不出来。
- 根因：`hdslb.com` 校验 Referer；接口返回协议相对地址（`//…`）。
- 正确做法：给图片请求加 Referer 和 UA，并把地址补全成 https。
- 证据：e576266e；lib/common/utils/network_image_url.dart:6-40；test/network_image_url_test.dart:27。

**REG-BILIBILI-018 请求失败被显示成下播，或显示成别的房间**
- 现象：网络一抖，房间就被标成下播，或者显示了正在播放的另一个房间的信息。
- 根因：进房失败时返回“当前播放房间”的错误快照，而且状态写成 offline。
- 正确做法：失败就报失败；只有平台明确返回的状态才改变房间状态。
- 证据：ee1e285c、1f7ac128、233d858d；docs/ROOM_DETAIL_ERROR_STATUS_AUDIT_2026_09_24.md。

**REG-BILIBILI-019 在播房间被判成未开播**
- 现象：在播房间显示未开播。
- 根因：`live_status` 只按整数解析，字符串 `"1"` 被当成未开播。
- 正确做法：数字和数字字符串都接受。
- 证据：233d858d；S:700、S:755。

**REG-BILIBILI-020 收藏刷新很慢**
- 现象：收藏刷新耗时长、请求多。
- 根因：刷新每张卡片都去取弹幕凭据等短期凭据。
- 正确做法：刷新和录制只取元数据；进房时才取弹幕凭据。
- 证据：d6c3d8df；S:683-697；docs/PERFORMANCE.md:35；RELEASE_NOTES.md:1632。

**REG-BILIBILI-021 冷启动时重复请求 buvid 和 WBI**
- 现象：冷启动后同时发出多份 spi 和 nav 请求。
- 根因：每个实例单独缓存，没有合并正在进行的请求。
- 正确做法：进程内共享，同时进行的请求合并为一个。v4 放进 SiteContext，不用静态变量（01-sites ③-7）。
- 证据：d6c3d8df；S:32-54、S:503-522。

**REG-BILIBILI-022 暂时断线被当成最终关闭**
- 现象：一次暂时断线，界面就显示为连接已关闭。
- 根因：重连时触发的是 close 回调。
- 正确做法：“重连中”和“最终关闭”分开发送（§7.6）。
- 证据：80c87c0e；docs/ISSUE_860_REFRESH_DANMAKU_AUDIT_2026_09_11.md:96。

**REG-BILIBILI-023 个别线路不稳定**
- 现象：`gotcha104`、`mcdn` 主机上的线路不稳定。
- 根因：[待确认]。旧代码试过屏蔽和代理改写，后来都撤销了。
- 正确做法：目前只把 `mcdn` 线路排在最后，不删除，也不改写。
- 证据：d4b0080d、1688cf7d、023de604；S:249。

**REG-BILIBILI-024 搜索每页条数不对**
- 现象：设置的每页条数不起作用。
- 根因：没有发送 `page_size`。
- 正确做法：发送 `page_size`，并限制在 1–50。
- 证据：4047cfba；S:723、S:735。

**REG-BILIBILI-025 b23 短链可能被滥用**
- 现象：可能出现无限重定向，或把非直播页误识别成房间。
- 根因：没有限制跳转次数和目标。
- 正确做法：按 §1.2 的边界处理。
- 证据：796cbcbc；test/live_short_link_test.dart:9-145。

---

## 11. 样本清单

- 录制条件：直连（DIRECT）的中国大陆网络，游客身份。2026-09-27 录制，每个样本的 meta.json 里 `route` 都是 `direct`，nav 返回 `ip_region: CN`（S11-guest）。没有登录账号，注明“登录”的样本都没有录。
- 样本放在 `fixtures/bilibili/`，目录名 `S<编号>-<情况>`，编号就是下表的 #。共 32 个目录，每个都有旧版期望值 `expected.json`；v4 解析器的测试是 packages/live_core/test/sites/bilibili_parse_test.dart。
- 每个样本附带：来源 URL、时间、路由、原始 SHA-256、脱敏字段列表（docs/rewrite/diagnosis/06-tests.md ⑥-1）。
- 所有样本的请求侧都要去掉：`Cookie`、`w_rid`、`wts`、`w_webid`。

| # | 接口 | 条件 | 需脱敏 | 生成期望值的旧版入口 | 已录制 |
|---|---|---|---|---|---|
| 1 | `room/v1/Area/getList` | 游客 | 无 | 没有静态入口；在 HTTP 替身下调用 `getCategores`（S:65） | `S01-guest`（12 个一级、462 个二级分区） |
| 2 | `second/getList` | 热门分区第 1 页；末页（`has_more=0` 或空页）；-352 响应 | 主播 uid 可保留 | 没有静态入口；在 HTTP 替身下调用 `getCategoryRooms`（S:96） | `S02-risk352`（不签名）、`S02-signed-risk352`（带齐 WBI、buvid、`w_webid`）。**缺**第 1 页和末页：游客一律 -352（§2.2），要等登录或 buvid 激活 |
| 3 | `getListByAreaID` | 第 1 页；越界页 | 无 | `BiliBiliSite.parseRecommendRooms`（S:348） | `S03-page1`、`S03-out-of-range`（page=10000，`data: []`） |
| 4 | `webMain/getMoreRecList` | 第 1 页 | 无 | 同上 | `S04-page1` |
| 5 | `search/type?search_type=live` | 有在播和未开播结果的关键词；无结果；越界页；不带 buvid3 | 无 | 没有静态入口；在 HTTP 替身下调用 `searchRooms`（S:722） | `S05-live-results`、`S05-no-results`、`S05-out-of-range`（第 2 页）、`S05-no-buvid3` |
| 6 | `getInfoByRoom` | 在播；未开播；`live_status=2`；用短号请求；不存在的房间；封禁房间；-352 | 无 | `parseRoomInfoResponse`（S:422，只做校验）；字段映射在私有的 `_buildRoom`（S:699），需要在替身下调用 `getRoomDetailForRefresh`（S:684） | `S06-live`（42062）、`S06-offline`（22647871）、`S06-replay`（5440）、`S06-short-id`（6）、`S06-short-id-long`（7734200）、`S06-not-found`（999999999）、`S06-risk352`（不签名）。**缺**封禁房间：没有找到 |
| 7 | `getRoomPlayInfo` | 游客 `qn=0`；游客 `qn=10000`（降档）；登录 `qn=10000`；未开播；`codec=0,1`（HEVC 对照） | `url_info[].extra` 中的签名、客户端 IP、uid 等参数：实际是 `sign`、`upsig`、`sk`、`flvsk`、`trid`、`oi`（十进制的客户端 IP）、`pv`、`rg`、`isp`、`zoneid_l`、`ld`、`site`、`mid`（tools/live_cli/lib/src/fixture/rules/bilibili.dart:58-69）；保留 `expires`、`deadline`、`stream_ttl`，供分析租期 | `parsePlayQualities`（S:176）、`parsePlayUrlResolution`（S:214）、`LiveQualityLabel.normalize`（live_quality_label.dart） | `S07-guest-qn0`、`S07-guest-qn10000`、`S07-hevc-qn10000`、`S07-offline`、`S07-replay`、`S07-short-id`、`S07-short-id-long`。**缺**登录 `qn=10000`：没有登录账号 |
| 8 | 媒体首部 | 每种格式各一条：FLV 前 64 KiB、HLS 播放列表（TS 和 fMP4 各一份）；另录一段超过 60 分钟的连接，观察是否会被断开 | 同上 | 没有入口；用于确定 §6.5 的租期 | **缺**：还没有媒体首部和长连接的录制方式（docs/rewrite/STATUS.md:37） |
| 9 | `getDanmuInfo` | 游客；登录 | `token` | 无（凭据字段） | `S09-guest`。**缺**登录：没有登录账号 |
| 10 | `finger/spi` | 游客 | `b_3`、`b_4` | 无 | `S10-guest` |
| 11 | `x/web-interface/nav` | 未登录（-101，带 `wbi_img`） | 无（密钥公开；如需固定测试向量，改用合成值） | `getMixinKey`（S:543）；签名向量用 P:737-757 的独立实现固定 `wts` 生成，两份实现结果必须一致 | `S11-guest` |
| 12 | `live.bilibili.com/lol` | 游客 | `access_id` | 无 | `S12-guest` |
| 13 | 弹幕二进制帧 | op=8 认证回复；op=3；**brotli**（protover 3）打包的 `DANMU_MSG`，游客打码和登录完整各一份；`WATCHED_CHANGE`；`SUPER_CHAT_MESSAGE`；带 `p_is_ack` 的消息；一条消息含多个包 | 观众 uid、昵称、头像、粉丝牌和 rich user 对象；发出的认证包里的 token 和 buvid | `BiliBiliDanmaku.decodeMessage`，通过 `onMessage` 收集输出（D:260）；ACK 用 `BiliBiliDanmaku(packetSender:)` 捕获（D:51）；认证包用 `buildJoinPayload(args, queueUuid:)`（D:184）。现有测试只构造了 zlib，brotli 路径缺覆盖（06-tests.md ⑤-4） | `fixtures/bilibili/danmaku/S13-live`（2026-09-27，`live_cli danmaku --record`，游客，房间 5050，60 s）：op 8、op 3、protover 2 的 zlib 包、44 条打码的 `DANMU_MSG`、`WATCHED_CHANGE`、醒目留言快照（空）。v4 改用 protover 2，所以没有 brotli 包。**缺**：登录的完整昵称、`SUPER_CHAT_MESSAGE`、`p_is_ack`（录制时没有出现） |
| 14 | `SuperChat/getMessageList` | 有留言的房间 | 用户昵称、头像 | 没有静态入口 | **缺**：未录，录制时没有记下原因；需要找一个正有醒目留言的房间 |
| 15 | 二维码 `generate` 和 `poll` | 86101、86090、86038、0 | `qrcode_key`、`url`；`Set-Cookie` 中的所有值；`refresh_token` | 没有静态入口（解析为私有，:272-302） | `S15-generate`、`S15-poll-86101`、`S15-poll-86038`。**缺** 86090 和 0：需要用手机登录账号扫码、确认 |
| 16 | `x/member/web/account` | 登录；失效（-101） | `mid`、`uname`、`userid`、`birthday`、`sign` 等全部个人字段 | `BiliBiliUserInfoModel.fromJson`（lib/common/models/bilibili_user_info_page.dart:22） | `S16-no-cookie`（不带 Cookie，-101）。**缺**登录：没有登录账号 |
| 17 | `b23.tv` 重定向 | 直播间短链；视频短链 | 无 | `LiveUrlTool.parseLiveUrl`，可沿用 test/live_short_link_test.dart 的替身写法 | **缺**：未录，录制时没有记下原因（工具能录 302，见斗鱼 S05-alias-redirect） |

其它可直接复用的旧版纯函数：
- `resolveDanmakuUid`（S:675）
- `sortRoomsByPopularity`（S:388）
- `LiveRoom.withAudienceFallbackFrom`（live_room.dart:744）
- `WebSearchRoomParser.parse`、`LiveUrlTool.containsSupportedLink`

---

## 12. 待确认

1. 短号：~~`getInfoByRoom`、`getRoomPlayInfo` 是否接受短号；短号字段名；6→7734200~~ 已查明：两个接口都接受，字段是 `room_info.short_id`，6 → 7734200（S06-short-id、S07-short-id）。仍待确认：`SuperChat/getMessageList` 是否接受短号（§1.1）。
2. 旧收藏里是否同时存在同一房间的短号和长号；v4 迁移时如何合并（§1.1）。
3. 是否支持 `live.bilibili.com/h5/{id}`、`/blanc/{id}`，以及输入 `bilibili://live/{id}` 深链接（§1.2）。
4. `Area/getList` 的 `need_entrance=1` 的含义（§2.1）。
5. `second/getList` 每页的条数，以及是否仍返回 `has_more`（§2.2）。游客请求都是 -352，样本没能回答（见第 18 条）。
6. ~~`getListByAreaID` 末页的形态~~：越界页 `data: []`，没有结束字段（S03-out-of-range）。仍待确认：`getMoreRecList` 的末页形态（§2.3）。
7. ~~搜索：总页数字段；不带 buvid3 是否返回 -412~~ 已查明：房间页数是 `data.pageinfo.live_room.numPages`；不带 buvid3 仍返回 0（S05）。`title` 的 HTML 实体：样本里没有出现，v4 照样解码（§3）。
8. ~~`live_status=2` 的含义和能否取流；`description` 是否含 HTML~~ 已查明：2 是轮播，游客取流 `playurl_info` 为 null（S06-replay、S07-replay）；`description` 会含 `<p>` 等标签（S06-replay）。仍待确认：封禁 / 锁定的判定字段（`lock_status`、`lock_time` 在录到的房间里都是 0）（§4）。
9. 游客部分已查明：`accept_qn` 是 10000、400、250（有的房间加 150），`qn` 0 和 10000 实际都给 250（S07）。仍待确认：登录后哪些 qn 可用、哪些需要大会员；4K、杜比是否只提供 HEVC（§5.2、§6.1）。
10. `gotcha104`、`mcdn` 线路现在是否仍不稳定（§5.3、REG-023）。
11. 媒体 CDN 实际需要哪些请求头（§6.3）。
12. WBI：~~未登录时 nav 的 `code` 值~~：-101，仍带 `wbi_img`（S11-guest）。仍待确认：签名值里的空格编码成 `%20` 还是 `+`（§6.4）。
13. 租期：~~`extra` 里的 `expires`、`stream_ttl` 是否存在及其含义~~：`expires`（有时还有同值的 `deadline`）是签发 + 3600 秒，`stream_ttl` 恒为 0（S07）。仍待确认：到期是否断开已建立的连接（`cutsConnection`）；需要样本 #8 的长连接记录（§6.5）。
14. 弹幕 token 的有效期；认证回复 `code != 0` 时各个码的含义（§7.6、§9）。
15. v4 需要解码哪些弹幕 cmd：礼物、进场、开播 / 下播、房间封禁等（§7.4）。
16. 是否继续声明 `protover: 3`（brotli），还是改为 2（zlib）以去掉 brotli 依赖（docs/rewrite/diagnosis/07-dependencies.md:14），服务端是否仍支持 2（§7.3）。
17. 登录 Cookie 的最小必需字段；二维码轮询实际返回的 `Set-Cookie` 字段（§8.2、§8.3）。
18. buvid 激活和补齐 `b_nut`、`_uuid` 等字段，能否降低 -352。现状：游客分区页带齐 WBI、buvid 和 `w_webid` 仍是 -352，并带 `x-bili-gaia-vvoucher`（S02-signed-risk352），游客的分区页现在取不到数据（§2.2、§8.1）。
19. 错误码：~~房间不存在~~：HTTP 200、`code 19002000`（S06-not-found）。仍待确认：-404、60004、付费房、地区限制各自的返回形态；HTTP 412 应归 RateLimited 还是 RiskControl（§9）。
20. #872 登录态弹幕修复是否已在真机上复现通过（REG-011）。
21. ~~`getRoomPlayInfo` 返回的 `extra` 中签名、IP、uid 相关参数的实际名称~~ 已查明，见 §11 #7。
22. 样本的录制网络环境：~~国内直连~~ 已按国内直连录制（S11-guest 的 `ip_region` 为 CN）。仍待确认：是否需要海外对照（§11）。
