# 平台规格：网易 CC（cc）

- 平台 id：`cc`（legacy/lib/core/sites.dart:48）；显示名“网易CC”（旧版“网易CC直播”，legacy/lib/core/site/cc/cc_site.dart:24）。
- 阶段：第二批（docs/adr/0003-platform-batches.md），第 7 阶段前段迁移。
- **去留：保留。** 2026-09-27 实测不满足 ADR 0003 任何一条下线标准：匿名取流成功（`live_cli probe cc 341438909` 读到 FLV），不需要登录，有公开目录（112 个在播房间，分四个一级分类）。平台体量明显变小（全站在播约 112 个，其中 34 个是官方“【重播】”频道），第 7 阶段的每日探针继续观察。
- 能力：两级目录、推荐（全站在播）、主播搜索（含未开播）、详情、取流（HTTP-FLV，两条 CDN，租期不断开已建立的连接）。
- 不提供：弹幕（见 §7，协议已查明一半，匿名加入房间没有回应，v4 暂不接）、登录（见 §8）。
- 证据口径：旧代码写成 `legacy/…:行号`；“实测”指 2026-09-27 编写本规格时在本机发出的匿名请求（WSL，出口 IP 在美国，直连）；能用样本核对的结论写样本编号（`fixtures/cc/`，见 §11）。
- 路径简写：`site` = legacy/lib/core/site/cc/cc_site.dart，`catalog` = legacy/lib/core/site/cc/cc_catalog.dart，`phr` = legacy/lib/player/core/playback_header_resolver.dart，`reo` = legacy/lib/modules/live_play/services/room_external_opener.dart，`wsp` = legacy/lib/modules/search/web_search_room_parser.dart，`url_tool` = legacy/lib/common/utils/live_url_tool.dart。

---

## 1. 房间身份与链接

**规范身份**：主播的 CC 号 `ccid`（接口里也叫 `cuteid`），十进制正整数，以字符串保存。

- 频道号 `channel_id`（= `cid` = `subcid`）和房间号 `room_id` 是直播时的附属信息，会随开播变化，不作身份，只放进弹幕参数（§4）。
- 旧版收藏、外部打开都用 ccid（reo:175-180；wsp:150）。

**可接受的输入**（全部不联网即可解析）

| 形式 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯数字 | `732923115` | 直接作为 ccid | — |
| 房间页 | `https://cc.163.com/732923115/?from=search` | 主机 `cc.163.com`，取路径第一段数字；`n`、`category`、`search`、`live`、`user` 等保留段不是房间 | wsp:150；url_tool:143, 331 |
| 手机分享页 | `https://h5.cc.163.com/cc/732923115` | 取 `cc/` 后一段。实测它 302 到 `https://cc.163.com/732923115` | 实测 |
| 大神（Dashen）播放页 | `https://ds.163.com/glive/?ccid=732923115` | 取查询参数 `ccid`。实测 `cc.163.com/<ccid>/` 不带参数时 301 到这个地址 | 实测 |
| 分享文本 | 链接前后夹中文 | 先抽出 URL 再按上表处理 | — |

**外部打开**：网页 `https://cc.163.com/<ccid>/`；旧版另有 App 链接 `cc://join-room/<ccid>/<uid>/`（reo:175-180），v4 由应用层决定是否保留。

---

## 2. 目录

### 2.1 分类（两级）

旧版（catalog:22-82；site:32-53）从大神的配置接口拼出分类，只有 24 个“直播入口”，入口里还混着“官方房间/专题”。v4 改用 CC 移动端的公开接口，拿到全部游戏分区：

- 一级：GET `https://api.cc.163.com/v1/wapcc/gamecategory?catetype=0`，`data.category_info.cate_list[]` 的 `cate_type`、`name`，按服务端顺序：1 网游、2 手游、4 竞技、5 综艺（S01-cate-all）。`cate_type == 0`（全部）不作分类。
- 二级：对每个一级分类 GET 同一接口 `catetype=<cate_type>`，取 `game_list[]`：`gametype`（分区 id）、`name`、`cover`（图标，http 地址，原样保存）（S01-cate-online 33 个、S01-cate-mobile 63 个、S01-cate-esports 8 个、S01-cate-show 2 个）。
- 顶层 `code != 0` 为 ApiChanged。没有分区的一级分类不显示。
- 缺口：全站在播房间里有 4 个 `gametype` 不在任何分类里（9079 风华正茂 23 个房间、9050 明日之后、9013 星际争霸、9165 遗忘之海；实测 2026-09-27）。这些房间只能从推荐（§2.3）和搜索进入 [待确认：是否有别的分类接口]。

### 2.2 分区房间

- GET `https://cc.163.com/api/category/<gametype>/?format=json&tag_id=0&start=<offset>&size=30`（site:56-125）。
- 响应 `{videos, lives, name, gametype}`；只取 `lives[]`，`videos` 是点播，不是房间（site:122-123）。
- 回显的 `gametype` 必须等于请求的分区，否则 ApiChanged（site:81）。
- 每页 30 条，`start = (页号 − 1) × 30`。
- **结束**：`lives` 为空即最后一页。接口不给总数，v4 不按条数判断（ADR 0010）；旧版以“不足 30 条”判断结束（site:421-422），v4 不沿用，代价是每个分区多一次空请求（S02-area-page1 13 条 → S02-area-beyond 空）。
- 没有房间的分区返回空 `lives`（S02-area-empty，65005 娱乐）。

**卡片字段**（site:86-120）

| 字段 | 含义 |
|---|---|
| `cuteid`（= `ccid`） | 规范 ccid |
| `title` | 标题；以 `【重播】` 开头的是官方重播频道，状态为回放（§4） |
| `nickname` | 主播名 |
| `cover`（缺时 `poster`） | 封面 |
| `gamename` | 分区名 |
| `purl` | 头像 |
| `startat` | 开播时间，北京时间、不带时区（`2026-09-14 14:53:45`），v4 按 UTC+8 解析 |
| `status` | 1 为在播；列表里全部是 1 |
| `hot_score`、`webcc_visitor`、`visitor`、`total_visitor` | 同一个**热度**值的别名（RELEASE_NOTES.md:1286, 1335；site:330-343） |
| `vision_visitor`（缺时 `online_num`） | **在线人数** |

两个口径同时给出：`Audience(popularity: hot_score, online: vision_visitor)`（S02-area-page1 第一条：在线 716、热度 298945）。旧版曾把热度当在线显示（RELEASE_NOTES.md:1335）。

### 2.3 推荐

- GET `https://cc.163.com/api/category/live/?format=json&start=<offset>&size=30`（site:226-259），就是全站在播房间，按热度排。
- 字段与 §2.2 相同；分页与结束同 §2.2。实测全站 112 个房间：30、30、30、22，之后为空（S03-live-page1、S03-live-last 是第 4 页的 16 条、S03-live-beyond）。
- 列表里有 24 小时循环的动画频道（“梦幻西游动画片”，在线 0～1），平台照样标 `status == 1`，v4 原样显示（S03-live-last）。

---

## 3. 搜索

- GET `https://cc.163.com/search/anchor/?query=<kw>&size=20&page=<p>`（site:354-380）。**路径必须带结尾斜杠**：不带斜杠时 301 到带斜杠的地址（实测）。
- 响应 `webcc_anchor.count`（总数）、`webcc_anchor.result[]`（主播，含未开播）。
- 字段：`cuteid`、`nickname`、`title`、`game_name`、`portrait`/`portraiturl`（头像）、`status`（1 在播；未开播为 `null` 或 0）、`cover`（只有在播时有）、`hot_score`（在播时的热度，未开播为 0）、`visitor`、`follower_num`。
- 映射：在播时状态、封面、热度照 §2.2；未开播时没有封面、不给人数（`Audience.none`）。`visitor` 在搜索里接近在线人数（在播房间 41 对列表的 `vision_visitor` 38），但未开播主播也有非零值，含义不清，v4 不用 [待确认]。旧版用粉丝数当“观看”（site:372-373），v4 不用。
- 分页：页号从 1 开始；本页为空，或 `页号 × 20 ≥ count` 即结束（S04-search-page1：共 22946 条，本页 4 个在播；S04-search-beyond：第 2000 页空）。
- 空结果：`{"count": 0, "result": []}`（S04-search-empty）。空关键词不请求。

---

## 4. 房间详情

旧版先查 `activitylives` 拿频道号，再查 `live/channel`（site:290-328），**未开播的主播必然失败**：`activitylives` 对未开播主播只返回 `{"is_black": 0}`，没有 `channel_id`，旧版拿 `null` 去查频道，得到“当前无正在直播的主播”（S05-lives-offline；实测 `channelids=1`）。不存在的 ccid 也是同样的响应（S05-lives-missing），两者无法区分。v4 的流程：

1. GET `https://api.cc.163.com/v1/activitylives/anchor/lives?anchor_ccid=<ccid>`：
   - `code != "OK"` → ApiChanged；非数字 ccid 返回 HTTP 400 `BAD_REQUEST` → NotFound（实测 `abc`）。
   - `data[<ccid>].channel_id` 有值 → 在播，进入第 2 步（S05-lives-live、S05-lives-replay）。
   - 没有 → 第 3 步。
2. GET `https://cc.163.com/live/channel/?channelids=<channel_id>`，取 `data[0]`：
   - 回显的 `ccid` 必须等于请求的 ccid，否则 ApiChanged。
   - `nolive == 1`（两次请求之间下播）→ 第 3 步。
   - 字段同 §2.2，另有 `personal_label`（主播签名，作公告；空串视为没有）、`room_id`、`channel_id`、`gametype`（S05-channel-live、S05-channel-replay）。
3. GET 房间页 `https://cc.163.com/<ccid>/?open=blizzardtv&from=8382&platform=ds`（这组参数是大神页面内嵌 CC 播放器用的，带上才返回 CC 自己的 Next.js 页面，不带时 301 到大神），解析 `<script id="__NEXT_DATA__">` 的 `props.pageProps.roomInfoInitData`：
   - `code == 404`、`reason == "no ccid"` → NotFound（S05-page-missing）。
   - 否则为未开播：主播名 `micfirst.nickname`，头像 `micfirst.portraiturl` 或 `purl`，标题 `live_title`（如“路人7758的直播”），分区 `gamename`，公告 `announcement`（S05-page-offline）。
   - 房间页约 110 KB，只在未开播时请求；在播的主播两次小请求就够。

**直播状态**

| 条件 | 状态 |
|---|---|
| `status == 1` 且标题以 `【重播】` 开头 | 回放（官方频道重播赛事录像；平台没有别的字段区分，实测 112 个在播房间里 34 个是这种，`capture_type`、`mode` 等字段与真直播无差别） |
| `status == 1` | 直播中 |
| 其它，或只能从房间页得到 | 未开播 |

- 标题里的 `【重播】` 是主播自设的，属于约定而非协议字段；斗鱼对 `【回放】` 也是同样处理（spec/sites/douyu.md §4）。
- 回放房间照样有流（§6），能否播放由应用决定（ADR 0010：回放不作直播录制）。

**弹幕参数**：`danmakuKeys = {ccid, channelId, roomId, gametype}`（未开播时只有能拿到的几项）。

**原站链接**：`https://cc.163.com/<ccid>/`。

**失败**：详情请求失败必须作为失败返回。旧版 `getRoomDetail` 把任何失败换成“错误房间”（site:262-275），v4 不这样做。

---

## 5. 画质与线路

来源是网页播放器用的 `video_play_url`（§6）。旧版从列表的 `stream_list` 或 `quickplay` 拼地址（site:128-223），这条路已经失效：

- `stream_list.<画质>.CDN_FMT` 现在只剩 `fws`（有时加 `ali`）一段签名查询串，旧版把它拼到详情的 `m3u8` 地址后面（site:201-211）；
- `m3u8` 是一个重定向地址 `http://cgi.v.cc.163.com/redirect/video/<ccid>.m3u8?secret=…`，实测不管拼上哪个画质的签名，都 302 到同一个 `…tc2.m3u8`（“medium”档），所以旧版的画质选择实际不起作用，而且重定向后的地址 300 秒过期（实测 `auth_key` = 签发时刻 + 300）。

### 5.1 画质列表

- `vbrname_list[]`：画质代号，**服务端顺序就是从高到低**（`original`、`ultra`、`high`、`standard`；有的房间还有 `blueray_5M_avc`、`blueray_3M_avc_lowfps`）。
- 标签取 `vbrname_mapping[代号]`（原画、超清、高清、标清、蓝光5M…），缺时用代号。
- 代号是不透明的请求码，`Quality.id` 就是代号；`rank` 按顺序给。
- 列表为空时用 `vbrname_sel` 生成一项。

### 5.2 线路

- `cdn_list[]`：可用 CDN 代码，例如 `["hs", "ali"]`。
- 一次应答给两条地址：`videourl` 在 `cdn_sel` 上，`bakvideourl` 在 `bakcdn_sel` 上（S06-play-default：hs + ali）。
- 线路身份是 CDN 代码。同一代码只保留第一条。
- `cdn_list` 里还没覆盖到的 CDN，再以 `cdn=<代码>` 请求一次。服务端不一定照办：`high` 档请求 `cdn=hs` 仍返回 ali 的地址（S06-play-high-hs），这时就只有 ali 一条线路，v4 不编造。

### 5.3 服务端确认的画质

- 应答的 `vbrname_sel` 是服务端实际给出的档位，`vbr_sel` 是码率（kbps）。
- 请求 `vbrname=high` 确认 `high`（S06-play-high）；不带 `vbrname` 时服务端给 `vbrname_sel`（S06-play-default 是 `original`，与列表第一项相同）。
- v4 不带画质请求时，如果服务端给的不是列表第一项，就再以第一项请求一次，保证“最好的画质”名副其实。

### 5.4 每条线路（StreamLine）

| 数据 | 值 |
|---|---|
| 地址 | `videourl` / `bakvideourl` |
| 格式 | 路径以 `.flv` 结尾为 FLV（实测全部是），`.m3u8` 为 HLS |
| 请求头 | `user-agent`（桌面 Chrome）、`referer: https://cc.163.com/`（phr:108-113；探针不带请求头也能拉流） |
| 线路身份 | CDN 代码 |
| 请求档位 / 确认档位 | 请求的代号 / `vbrname_sel` |
| 编码 | 不写（接口不给；代号里偶有 `avc`） |
| 租期 | 见 §6.3 |

---

## 6. 取流

### 6.1 请求

GET `https://vapi.cc.163.com/video_play_url/<ccid>?src=webcc_h5&vbrmode=1&use_new_vbrmap=1&secure=1[&vbrname=<代号>][&cdn=<代码>]`

- 来自网页播放器 h5player 0.39.x（`//vapi.cc.163.com` + `/video_play_url/`，参数 `src=webcc_h5`、`vbrmode=1`、`use_new_vbrmap=1`、`secure=1`；实测 2026-09-27）。
- 网页还会带 `sid`（访客 id，来自 `vapi.cc.163.com/sid?src=webcc`）、`t` 等，实测不带也正常，v4 不带。
- `secure=1` 让地址是 https。

### 6.2 应答

- 在播：HTTP 200 JSON（S06-*）。
- 未开播：**HTTP 410** `{"code": "Gone", "data": "no live"}` → StreamUnavailable（S06-play-offline）。
- 非数字 ccid：HTTP 404 HTML → StreamUnavailable（详情阶段已经挡住）。

### 6.3 租期

- 地址里的 `auth_key = <到期 Unix 秒>-<随机>-<uid>-<md5>`（阿里 A 型鉴权），到期 = 签发 + 300 秒（S06-play-default：签发 1790526620，`auth_key` 1790526920）。hs 线路另有 `volcTime`（30 天）、`relaySecret` 以签发时刻开头，都不决定租期。
- **到期不断开已建立的连接**：实测 hs、ali 两条线路各持续读 420 秒，越过 300 秒的到期点后照常出数据（每 30 秒约 30 MB，2026-09-27）。所以 `cutsConnection = false`：到期只影响新连接，续期只需要预取，不必像斗鱼那样拼接。
- `Lease`：`expiresAt` = `auth_key` 的时间；`refreshAt` = `expiresAt − min(60 s, 寿命/4)`；没有 `auth_key` 或已过期则没有租期。
- 断线重连、恢复播放时必须重新请求 §6.1，不能复用旧地址。

---

## 7. 弹幕

旧版没有 CC 弹幕（site:27 返回 `EmptyDanmaku`）。v4 查明了协议的大部分，但匿名加入房间没有得到回应，**暂不提供弹幕**，应用显示“不支持”（spec/modules/danmaku.md REG-DANMAKU-021）。

已查明的部分（CC 网页 `cclink` 2.3.4 的 worker，`https://cc.163.com/act/webcc/cclink/worker.js`；房间核心模块 `room_core` 1.131.1；公屏插件 `chat_screen` 1.80.2；实测 2026-09-27）：

- 连接：`wss://weblink.cc.163.com/`，二进制帧。
- 帧：`u16 LE sid`、`u16 LE cid`、`u32 LE 压缩标志`；标志为 0 时后面直接是 msgpack；不为 0 时 `u32` 长度加 zlib 压缩的 msgpack。
- 握手：`{6144, 32}` 取访客设备令牌（应答 `data.token = "<uuid>@web.cc.163.com"`）→ `{6144, 2}` 注册设备（应答 `result 0`）→ 每 30 秒 `{6144, 5}` 心跳（应答带服务器时间）。这三步匿名都成功。
- 加入房间：`{512, 1, roomId, cid, gametype, hall_version: 1, motive: "join", account_id, recom_token, client_type: 4000, client_source: 4000, room_sessid}`。**匿名发送后 35 秒内没有任何应答**，蛋仔派对在线 700 多人的房间也是如此。
- 聊天消息是 `{515, 32785}`，`msg[]` 里数字键 `4` 是正文、`197`/`97` 是昵称（公屏插件）。
- 另一条 SockJS 通道 `wss://wslink.cc.163.com/conn/websocket`（JSON 文本：`{"cmd":"sub","data":{"groups":["roomchat_<cid>"]}}`、`{"cmd":"heartbeat"}`）订阅成功，但 40 秒内同一房间没有推送；它只用于“重复打开的房间”（room_core 里的 `mgshub`），不是主通道。

[待确认] 加入房间需要的条件（可能要先调用 `https://cc.163.com/token/` 取访客票据并 `{2, 2}` 登录）。查明后按 live_danmaku 的连接器写法接入。

---

## 8. 登录与 Cookie

- 旧版没有 CC 账号功能，所有请求匿名（site 全文没有 Cookie）。
- 服务端会下发 `VISITOR`、`CCTOKEN` Cookie（S02-area-beyond 等样本的 Set-Cookie，已脱敏），v4 不保存、不回传：所有接口不带 Cookie 都正常。
- v4 不提供 CC 登录。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | — | NetworkFailure |
| HTTP 429 | 没有见过 | RateLimited |
| 分类接口 `code != 0`；列表回显的 `gametype` 不对；`activitylives` 的 `code != "OK"`；频道回显的 ccid 不对；房间页没有 `__NEXT_DATA__` 或主播名 | — | ApiChanged |
| 非数字 ccid（`activitylives` HTTP 400） | 实测 | NotFound |
| 房间页 `code == 404`（`no ccid`） | S05-page-missing | NotFound |
| `video_play_url` HTTP 410 `Gone` | S06-play-offline | StreamUnavailable |
| 某个 CDN 的补充请求失败 | — | 跳过这条线路；全部失败才报错 |
| 取流应答没有任何地址 | — | ApiChanged |
| 调用方取消 | — | 取消只影响本次请求 |

没有观察到签名、验证码或地区限制；实测出口在美国也能正常取流。

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-CC-001 | 分类页加载失败 | 旧分类 JSON 地址改为 301 到大神 HTML 页 | 分类改用 `api.cc.163.com/v1/wapcc/gamecategory` | RELEASE_NOTES.md:543-547；实测 `cc.163.com/category/` → `ds.163.com/glive/` |
| REG-CC-002 | 热度显示成在线人数 | `webcc_visitor`、`hot_score`、`visitor` 是同一个热度值 | 热度与 `vision_visitor` 分开 | RELEASE_NOTES.md:1286, 1335；site:330-343 |
| REG-CC-003 | 未开播的主播详情失败、收藏里显示“状态未知” | `activitylives` 对未开播主播不给 `channel_id` | 没有频道号时查房间页，区分未开播和不存在 | S05-lives-offline；site:290-299 |
| REG-CC-004 | 选任何画质都是同一路“medium” | 旧地址是一个重定向，签名参数被忽略 | 改用 `video_play_url` 按 `vbrname` 取流 | 实测 302 到 `…tc2.m3u8`；site:201-211 |
| REG-CC-005 | 播放约 5 分钟后 HLS 刷新失败 | 重定向后的 HLS 地址 `auth_key` 300 秒过期，播放列表刷新时失效 | 用 FLV；租期到期只影响新连接，恢复时重新取流 | 实测；§6.3 |
| REG-CC-006 | 分区列表提前结束或多出一页 | 以“不足 30 条”判断结束 | 只以空页结束 | site:421-422；ADR 0010 |
| REG-CC-007 | 搜索无结果 | 路径缺结尾斜杠，301 后客户端未跟随 | 使用 `/search/anchor/` | 实测 |
| REG-CC-008 | 详情失败被当成下播 | `getRoomDetail` 吞掉错误 | 详情失败作为失败返回 | site:262-275 |

---

## 11. 样本清单

2026-09-27 直连录制（`live_cli fixture capture`，规则 `tools/live_cli/lib/src/fixture/rules/cc.dart`），共 27 个，放在 `fixtures/cc/`。旧版解析器已不能运行（ADR 0016），没有 `expected.json`；期望值直接写在 `packages/live_core/test/sites/cc_parse_test.dart`、`cc_site_test.dart`。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | `gamecategory?catetype=0/1/2/4/5` | `S01-cate-all`、`S01-cate-online`、`S01-cate-mobile`、`S01-cate-esports`、`S01-cate-show` |
| S02 | `api/category/<gametype>/` | `S02-area-page1`（蛋仔派对 13 条，含【重播】）、`S02-area-beyond`（空）、`S02-area-empty`（娱乐分区无房间） |
| S03 | `api/category/live/` | `S03-live-page1`（30 条）、`S03-live-last`（第 4 页 16 条）、`S03-live-beyond`（空） |
| S04 | `search/anchor/` | `S04-search-page1`（“梦幻”，20 条，4 个在播）、`S04-search-beyond`、`S04-search-empty` |
| S05 | 详情三步 | `S05-lives-live` + `S05-channel-live`（直播中）、`S05-lives-replay` + `S05-channel-replay`（【重播】）、`S05-lives-offline` + `S05-page-offline`（未开播）、`S05-lives-missing` + `S05-page-missing`（不存在） |
| S06 | `video_play_url` | `S06-play-default`（原画，hs + ali）、`S06-play-high`（高清，两条都是 ali）、`S06-play-high-hs`（请求 hs 仍给 ali）、`S06-play-ali`（`cdn=ali`）、`S06-play-offline`（410） |
| S07 | 弹幕帧 | **缺**：匿名加入房间没有应答（§7） |
| S08 | 登录后的请求 | **缺**：v4 不提供 CC 登录 |

**需要脱敏的字段**

- CDN 签名：`wsSecret`（列表 `stream_list.*.CDN_FMT`）、重定向 `m3u8` 的 `secret`、`volcSecret`；`auth_key`、`relaySecret` 以时间开头，保留开头的时间、替换其余部分（新增的 `expiryPrefixed` 规则），租期测试靠它离线复算。
- `sid`（网页播放器的访客 id；v4 不发送）。
- Set-Cookie 里的 `VISITOR`、`CCTOKEN`（工具统一脱敏）。
- 主播公开信息（ccid、uid、昵称、头像、标题、封面、流名、频道号）保留（ADR 0009 第 4 条）。
- 响应头 `x-app-server-addr`、`x-route-server-addr` 是 CC 内网地址，不含观众信息，保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 不在 `gamecategory` 里的分区（风华正茂等 4 个）有没有别的分类入口 | 看 CC App 的分类接口 |
| 2 | 匿名加入房间收不到弹幕的原因（§7） | 在浏览器里抓未登录访问房间页时 weblink 的完整帧序列 |
| 3 | 搜索结果里 `visitor` 的含义（未开播也有值） | 对照同一主播在播时的列表 `vision_visitor` |
| 4 | `high` 档为什么只有 ali 一条线路；`cdn_list` 里的 CDN 是否对每个画质都可用 | 对多个房间逐档逐 CDN 请求 |
| 5 | 已建立的连接最长能持续多久（实测只到 420 秒） | 长时间录制 |
| 6 | 官方【重播】频道要不要作为可播放的“回放”在应用里放出（应用层决定） | 产品决定 |
