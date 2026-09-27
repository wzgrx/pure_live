# 平台规格：YY 直播（yy）

- 平台 id：`yy`（legacy/lib/core/sites.dart:52）；显示名“YY直播”（旧版“YY 直播”，legacy/lib/core/site/yy/yy_site.dart:24）。
- 阶段：第二批（docs/adr/0003-platform-batches.md），第 7 阶段前段迁移。
- **去留：保留。** 2026-09-27 实测不满足任何下线标准：匿名取流成功（`live_cli probe yy 22490906`、`probe yy 54880976` 都读到 FLV），不需要登录，有公开目录（14 个有列表的分区，舞蹈分区 136 个在播房间）。
- 能力：两级目录、推荐、直播间搜索、详情、取流（HTTP-FLV，两条线路，租期不断开已建立的连接；移动 HLS 兜底）、弹幕（匿名，需要保留大小写的握手）。
- 不提供：未开播主播的搜索（§3）、礼物和进场消息（§7.4）。
- 证据口径：旧代码写成 `legacy/…:行号`；“实测”指 2026-09-27 在本机发出的匿名请求（WSL 直连）；样本编号见 §11（`fixtures/yy/`、`fixtures/yy/danmaku/`）。
- 路径简写：`site` = legacy/lib/core/site/yy/yy_site.dart，`proto` = legacy/lib/core/utils/yy/yy_protocol.dart，`ws` = legacy/lib/core/utils/yy/yy_web_socket_channel.dart，`dm` = legacy/lib/core/danmaku/yy_danmaku.dart，`reo` = legacy/lib/modules/live_play/services/room_external_opener.dart，`wsp` = legacy/lib/modules/search/web_search_room_parser.dart，`phr` = legacy/lib/player/core/playback_header_resolver.dart。

---

## 1. 房间身份与链接

**规范身份**：频道号 `sid`（顶级频道，十进制），以字符串保存。

- 子频道 `ssid`：实测 314 个在播房间全部 `ssid == sid`（14 个分区各取 60 条，2026-09-27）。v4 仍从详情读取 `ssid`，只放进弹幕参数和取流参数。
- 短号 `asid`（`pageInfo.shortSid`，搜索结果里的 `asid`）是别名：`www.yy.com/2149` 与 `www.yy.com/35340121` 是同一个房间，页面 `pageInfo.sid` 给出规范号（S05-page-asid）。详情接口不认短号（`liveInfoDetail/2149/2149/0` 返回 `data: null`，实测），所以短号必须先经房间页换成 `sid`（§4）。

**可接受的输入**

| 形式 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯数字 | `22490906` | 直接作为 sid；如果其实是短号，详情时由房间页换成规范号 | — |
| 房间页 | `https://www.yy.com/22490906/22490906?tempId=16777217`、`https://www.yy.com/22490906` | 主机是 `yy.com` 或其子域，取路径第一段数字 | wsp:162；列表的 `liveUrl` 字段 |
| 手机页 | `https://wap.yy.com/mobileweb/54880976/54880976` | 第一段是 `mobileweb` 时取第二段 | 移动 HLS 的 Referer（site:384） |
| 分类页 | `https://www.yy.com/music/` | 不是房间 | — |

**外部打开**：`https://www.yy.com/<sid>`（reo:149）。

---

## 2. 目录

### 2.1 分类（两级）

- GET `https://www.yy.com/yyweb/module/data/header`（site:134-158）：`categoryTabs[]` 是一级分类（`id`、`title`：1 娱乐、2 游戏、3 其他），每项的 `navs[]` 是分区（`id`、`title`、`url`：分区页地址）（S01-header）。
- 分区图标：GET `https://www.yy.com/c/yycom/category/getCategory.action?parentId=<一级 id>`，`data[].cover`（S01-category-ent 等）。响应 `content-type` 是 `text/html`，正文是 JSON。
- 地址一律改成 https（`http://`、`//` 开头的都改，site:72-86）。
- 旧版在取分类时就逐个请求 17 个分区页来拿列表参数（site:180-214）；v4 改为打开分区时再请求（§2.2），取分类只需 1 + 3 个请求。

### 2.2 分区房间

- 列表接口需要分区页里的 `pageInfo`：GET 分区页（`navs[].url`），用正则读出 `moduleId`、`biz`、`subBiz`（site:107-120；S02-area-page-dance：`313`、`dance`、`idx`）。每个分区只取一次，适配器内缓存。
- **3 个分区没有列表模块**：页面是服务端渲染，`pageInfo` 为 `moduleId: 0, biz: 'null', subBiz: 'null'`（英雄联盟、综合、手机直播；S02-area-page-lol）。这些分区返回空列表。旧版对它们发出不带参数的请求，得到空列表（site:226-240）。
- GET `https://www.yy.com/more/page.action?page=<p>&pageSize=30&biz=<biz>&subBiz=<subBiz>&moduleId=<moduleId>`（site:220-271）。
- 响应 `resultCode`（0 成功）、`data.totalCount`、`data.data[]`。
- **结束**：`data.data` 为空，或 `页号 × 30 ≥ totalCount`（S02-dance-p1：共 136 条；S02-dance-p5 第 5 页 16 条后结束；S02-dance-p6 空）。`totalCount` 是服务端给的总数，属于平台信号，不是按条数猜测。

**卡片字段**

| 字段 | 含义 |
|---|---|
| `sid` | 规范 sid（`ssid` 相同） |
| `desc` | 标题 |
| `name` | 主播名 |
| `thumb2`（缺时 `thumb`） | 封面 |
| `avatar` | 头像 |
| `users` | **热度**，不是在线人数（RELEASE_NOTES.md:1284；DEPENDENCY_AUDIT.md:91） |
| `startTime` | 开播时间，Unix 秒 |
| `biz` | 分区键；推荐列表里全是 `other` |

列表里的房间都是直播中。

### 2.3 推荐

- 同一接口，`biz=other&subBiz=idx&moduleId=-1`（site:552-590）。实测共 38 个房间：30 + 8（S03-recommend-p1、S03-recommend-p2；S03-recommend-p3 空）。
- 卡片的分区名：只有在对应分区打开过（学到 `biz` → 分区名）时才有；推荐的 `biz` 是 `other`，没有对应分区，分区名为空。旧版在推荐时先拉全部分类来填分区名（site:599-629），v4 不这样做。

---

## 3. 搜索

- GET `https://www.yy.com/apiSearch/doSearch.json?q=<kw>&t=120&n=<页号>`（site:708-747）。
- `t=120` 是“直播间”：结果在 `data.searchResult.response["120"].docs[]`，每页 16 条，`data.totalPage` 是总页数（S04-search-p1：共 135 条、9 页）。
- 字段：`sid`、`name`（主播）、`channelName`（`"<主播> 正在直播"`，v4 去掉后缀 ` 正在直播` 作标题）、`liveOn`（`"1"`）、`users`（热度）、`posterurl`（封面）、`headurl`（头像）。
- **只有在播房间**：实测 `t=120` 的结果全部 `liveOn == "1"`。`t=1`（主播）会返回未开播的主播，但它的 `liveOn` 不可靠：`22490906` 当时在播，`t=1` 却给 `"0"`（S04-search-anchors，实测）。v4 只用 `t=120`，未开播的主播搜不到 [待确认：有没有可靠的主播搜索]。
- 结束：`docs` 为空，或页号达到 `totalPage`（S04-search-p50、S04-search-empty）。空关键词不请求。

---

## 4. 房间详情

1. GET `https://www.yy.com/api/liveInfoDetail/<sid>/<sid>/0`（site:665-701）：
   - `resultCode != 0` → ApiChanged。
   - `data` 是对象 → 直播中（S05-detail-live）。字段同 §2.2，`ssid` 放进弹幕参数。
   - `data: null` → **未开播、不存在和短号都是这样**（S05-detail-offline、S05-detail-missing），进入第 2 步。旧版把 `null` 一律当未开播（site:677-679），不存在的房间也显示成“未开播”。
2. GET 房间页 `https://www.yy.com/<sid>`：
   - 页面引用 `yycom_404` 资源（754 字节的 404 页）→ NotFound（S05-page-missing）。
   - 否则解析 `var pageInfo = {…};`：`sid`、`ssid`、`nick`（主播名）、`logo`（头像）、`roomName`（`decodeURIComponent("…")`，房间名）、`owInfo.stringBiz`（分区名，如“段子手”）（S05-page-offline）。
   - `pageInfo.sid` 与请求的号不同（短号）时，用规范 sid 再查一次第 1 步；在播就返回在播详情，否则返回未开播（S05-page-asid）。
3. 未开播：标题取 `roomName`，没有封面和人数。

- `v_type`（在播 1、未开播 0）也在房间页里，但在播时第 1 步已经给出结果，v4 不依赖它。
- **原站链接**：`https://www.yy.com/<sid>`。**弹幕参数**：`{sid, ssid}`。
- 详情失败作为失败返回；旧版 `getRoomDetail` 把失败换成“错误房间”（site:635-649）。

---

## 5. 画质与线路

### 5.1 画质

来自 stream-manager 应答的 `channel_stream_info.streams[]`（§6.1）：

- 每项的 `json` 是一段 JSON 字符串，其中 `gear_info` = `{gear, name, seq}`（例如 `{2, 高清, 200}`），`rate` 是码率（kbps）。
- **只有带 `stream_key` 的视频流网页能播**。没有 `stream_key` 的项（`mix == 1`，例如 22490906 的 `gear 3 超清`）请求时会被换成别的档：请求 `gear 3` 得到 `gear 2` 的流（S06-streams-g3）。旧版把这类档位列进画质（site:451-497），选了也拿不到，v4 不列。
- 同一 `gear` 只保留第一项；按 `seq` 从高到低排（蓝光 400 > 超清 300 > 高清 200 > 流畅 100）。
- `Quality.id` = `gear`（请求码），标签 = `gear_info.name`。

### 5.2 线路

- `avp_info_res.stream_line_addr` 只有一项：键是实际给出的 `stream_key`，值里有 `line_seq` 和 `cdn_info.url`。
- `avp_info_res.stream_line_list[<stream_key>].line_infos[]` 列出这个流可用的线路号（实测 `10`、`14`，名称“线路10”“线路14”）。
- 每条其它线路以 `line_seq=<号>` 再请求一次（S06-streams-g2-l10：线路 10 是 `tx-flv-web.yy.com`，线路 14 是 `ks-flv-web.yy.com`）。补充请求用**服务端实际给出的 gear**，不用请求的 gear（请求一个不存在的档，服务端只会再给同样的替代档）。
- 线路身份 = `line_seq`。

### 5.3 服务端确认的画质

应答的 `stream_key` 对应的 `gear` 就是实际档位。默认先以 `gear=1` 请求一次拿到画质列表（旧版同样做法，site:436-448），再以最高档请求。

### 5.4 每条线路（StreamLine）

| 数据 | 值 |
|---|---|
| 地址 | `cdn_info.url`（`https://{ks,tx}-flv-web.yy.com/live/<视频流>-<音频流>-…flv?…`） |
| 格式 | FLV（路径 `.flv`） |
| 请求头 | `user-agent`、`referer: https://www.yy.com/`（phr:134-139）；不带用户 Cookie |
| 线路身份 | `line_seq` |
| 请求档位 / 确认档位 | 请求的 `gear` / 应答 `stream_key` 的 `gear` |
| 租期 | §6.3 |

---

## 6. 取流

### 6.1 stream-manager

POST `https://stream-manager.yy.com/v3/channel/streams?uid=0&cid=<sid>&sid=<ssid>&appid=0&sequence=<毫秒>&encode=json`（site:286-356）

- 正文是 JSON，但 **`content-type: text/plain;charset=UTF-8`**：网页 SDK 这样发，部分频道对 `application/json` 直接拒绝（site:346-349；RELEASE_NOTES.md:1251，上游 #798）。
- 请求头：`referer: https://www.yy.com/<sid>/<ssid>`、`origin: https://www.yy.com`。
- 正文：`head`（`seq` = 毫秒时间、`bidstr: "121"`、`cidstr`、`sidstr`、`client_type: 108`、SDK 版本 `5.23.0-beta.2`、`app: "yylive_web"`）、`client_attribute`（网页、Chrome）、`avp_parameter`（`gear`、`line_seq`（-1 由服务端选）、`ssl: 1`、`send_time` = 秒）。
- 匿名（`uid=0`）。未开播：应答只有 `g_<sid>_0_1` 一项，没有 `avp_info_res`（S06-streams-offline）。

### 6.2 移动 HLS 兜底

- 旧版记录部分官方频道对 stream-manager 返回 `ErrAuthNotPass` 或空结果，这时匿名移动 HLS 仍能播（site:436-447；RELEASE_NOTES.md:965, 1251）。v4 在 stream-manager 没有任何可播线路时请求：GET `https://interface.yy.com/hls/new/get/<sid>/<ssid>/1200?source=wapyy&callback=`，Referer `https://wap.yy.com/mobileweb/<sid>/<ssid>`（site:377-391）。
- 应答形如 `({"code":0,…,"hls":"https://sslproxy.yy.com:4443/livesystem/….m3u8?org=yyweb&uuid=…&t=…&tk=…"})`（S07-mobile-hls）；未开播时 `code 0` 但没有 `hls`（S07-mobile-hls-offline）→ StreamUnavailable。
- 兜底只给一个画质（“流畅”，1200）一条 HLS 线路；旧版另请求 4000 档后去重，v4 没有能复现 `ErrAuthNotPass` 的频道 [待确认]，只保留一档。

### 6.3 租期

- FLV 地址的 `t` 是签名到期的 Unix 秒，等于签发 + 600 秒（S06-streams-g2：签发时刻 + 600）；`secret`、`rts_tk` 是签名。
- **到期不断开已建立的连接**：实测 `ks` 线路持续读 780 秒，越过 600 秒到期点照常出数据（每 30 秒约 12 MB，2026-09-27）。`cutsConnection = false`。
- `Lease`：`expiresAt` = `t`；`refreshAt` = `expiresAt − min(60 s, 寿命/4)`。
- 恢复播放时重新请求 §6.1。

---

## 7. 弹幕

### 7.1 连接

- 地址：`wss://h5-sinchl.yy.com/websocket?appid=yymwebh5&version=3.2.10&uuid=<随机 UUID>`（proto:4-15）。
- **握手必须保留大小写**：`dart:io` 把 `Connection`、`Upgrade` 改成小写后，服务器不应答，握手永远挂起（实测 12 秒超时；ws:10-40）。v4 用 live_danmaku 的 `ExactWebSocket`（`SocketPlan.exactHeaders`）。
- 握手头：`User-Agent`（桌面 Chrome）、`Origin: https://www.yy.com`（dm:81-87）。
- 匿名，不需要账号。

### 7.2 包格式

- 小端序。包头 10 字节：`u32 总长`、`u32 uri`、`u16 200`（proto:127-196）。一个 WebSocket 帧可以含多个包，按总长切分；坏包只丢这一个。
- 字符串：`u16 长度` + Latin-1/UTF-8 字节；UCS-2 字符串：`u32 字节数` + UTF-16LE。

### 7.3 握手顺序（proto:198-466）

1. 发 `778244` 匿名 UDB 登录（设备号 `B8-97-5A-17-AD-4D`、`yymwebh5`）→ 收 `778500`：`realUri == 20078` 且结果 0/200 时，读出匿名 uid、用户名、密码、Cookie。
2. 发 `775684` AP 登录（应用 259）→ 收 `775940`：结果码 200。
3. 发路由包 `513035` 包着 `2048258` 加入频道（服务名 `channelAuther`，频道属性 `2, 2, "0", 3, "1"`：缺了它们路由器会静默丢弃加入请求，proto:536-540），同时发 `538456` 订阅应用 31、101、102、103、17 → 收路由应答 `512011`，其中 `realUri 2048514`、`loginStatus == 4` 且频道号一致即加入成功。
4. 发两个 `537944` 订阅用户组（频道组和子频道组）。
- 实测三次加入都在 0.4～0.8 秒内完成（22490906、54880976、1414787097）。

### 7.4 消息

- 聊天：用户组消息 `533080`（或包在路由应答里）或 `28760`，应用号 31，内层 `3104600`：`u32 uid`、`u32 顶级频道`、`u32 子频道`、`u16 聊天块长度`、聊天块（`u32 特效`、UCS-2 字体名、`u32 颜色`、`u32 字号`、UCS-2 正文、`u32 屏幕模式`）、两个字符串、UTF-8 昵称、`u32 附加项数` 和附加项（`u16 键` + 字符串）（proto:429-466）。
- **频道号与本房间不同的聊天丢弃**（CONN-5）。
- **正文可能是 XML**：`<?xml version="1.0"?><msg>…<txt data="我听到这歌就看到金碟豹/{tx"/>…</msg>`（实测）。v4 取 `txt` 的 `data` 属性并解码 XML 实体；`/{tx` 这类是表情代码，原样保留。旧版把整段 XML 当正文显示（dm:174-183）。
- 昵称取包里的 UTF-8 昵称：已登录观众是真实昵称（`◆ Mr：炜丶`），未登录观众被平台打码（`193******72`）。附加项 100、101 也是昵称样的字符串，但和发送者对不上（已登录的 `◆ Mr：炜丶` 附加项 100 是 `♡♥.闽南ＮＩ﹏情 伤【Ａｉ❤妮歌】`），含义 [待确认]，v4 不用。
- 颜色字段实测多为 0，也有 `0x690053`、`0x5fbdbfef` 这样看不出含义的值，v4 不用，统一白色。
- 应用 103 的 `3139586`、`3165186` 每秒约 4 条（礼物、进场之类），格式未知，v4 不解码 [待确认]。
- 实测聊天量很小：54880976（热度 114 万）90 秒内约 4 条。

### 7.5 心跳与重连

- 心跳：每 5 秒发 `794116`（AP ping，`u32 0`），服务端回 `794372`（dm:27, 195-198）。
- 15 秒内没有加入就断开重连（dm:139-146）；匿名登录、AP 登录或加入失败都换一个 UUID 重连（最多 3 次，之后终态）。
- 其余按 live_danmaku 的 CONN-3。

---

## 8. 登录与 Cookie

- 旧版有“YY Cookie”设置，把 Cookie 拼进所有 API 请求头（site:33-48），没有别的用途：stream-manager 的正文里 `uid64` 固定为 0。
- v4：用户存了 Cookie 时照旧放进 API 请求；**媒体请求不带 Cookie**。登录能否解锁更高档位 [待确认：没有账号可测]。
- 弹幕只用匿名登录。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | — | NetworkFailure |
| `page.action`、`liveInfoDetail` 的 `resultCode != 0`；房间页没有 `pageInfo` 或 `sid`；stream-manager 非 200 | — | ApiChanged |
| 非数字 sid | — | NotFound |
| 房间页是 404 页 | S05-page-missing | NotFound |
| stream-manager 没有可播线路且移动 HLS 也没有地址 | S06-streams-offline、S07-mobile-hls-offline | StreamUnavailable |
| 补充线路请求失败 | — | 跳过这条线路 |
| 分区没有列表模块 | S02-area-page-lol | 空列表，不是错误 |
| 弹幕匿名登录、AP 登录或加入被拒 | proto:336-392 | 连接状态 `rejected`，重连 |

没有观察到签名校验、验证码或地区限制。

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-YY-001 | 弹幕连不上，没有任何报错 | `dart:io` 把升级头改成小写，YY 边缘节点不应答 | 保留大小写的握手（`ExactWebSocket`） | ws:10-40；实测 |
| REG-YY-002 | 加入频道后收不到消息 | 加入包缺两个匿名频道属性，路由器静默丢弃 | 按 §7.3 带上属性 | proto:536-540 |
| REG-YY-003 | 部分频道 stream-manager 拒绝 | 正文以 `application/json` 发送 | `text/plain;charset=UTF-8` | site:346-349；RELEASE_NOTES.md:1251 |
| REG-YY-004 | 选了“超清”实际是高清 | 列出了网页不能播的档位（没有 `stream_key`） | 只列带 `stream_key` 的档；确认档位按应答的流 | S06-streams-g3；site:451-497 |
| REG-YY-005 | 画质按钮重复 | 同一档位有多项 | 按 `gear` 去重 | site:476-495 |
| REG-YY-006 | 热度显示成在线人数 | `users` 是热度 | 标注热度 | RELEASE_NOTES.md:1284 |
| REG-YY-007 | 不存在的房间显示“未开播” | `liveInfoDetail` 对两者都返回 `null` | 用房间页区分 | S05-detail-missing、S05-page-missing；site:677-679 |
| REG-YY-008 | 短号链接打开是“未开播” | 详情接口不认短号 | 经房间页换成规范 sid | S05-page-asid |
| REG-YY-009 | 弹幕显示成一整段 XML | 正文是 XML 包装 | 取 `txt data` | 实测 |
| REG-YY-010 | 其它频道的弹幕混进来 | 没有核对频道号 | 丢弃频道号不同的聊天 | proto:433 |

---

## 11. 样本清单

2026-09-27 直连录制，共 31 个 HTTP 样本（`fixtures/yy/`，规则 `tools/live_cli/lib/src/fixture/rules/yy.dart`）和 1 个弹幕样本（`fixtures/yy/danmaku/`，`live_cli danmaku yy --record`）。旧版解析器已不能运行，期望值写在 `packages/live_core/test/sites/yy_*_test.dart`、`packages/live_danmaku/test/yy_test.dart`。stream-manager 的正文含时间（`seq`、`send_time`），回放时和 URL 的 `sequence` 一起不参与匹配。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | 分类 | `S01-header`、`S01-category-ent`、`S01-category-game`、`S01-category-other` |
| S02 | 分区页与分区房间 | `S02-area-page-dance`（有模块）、`S02-area-page-lol`（没有模块）、`S02-dance-p1`、`S02-dance-p5`（最后一页 16 条）、`S02-dance-p6`（空） |
| S03 | 推荐 | `S03-recommend-p1`、`S03-recommend-p2`、`S03-recommend-p3` |
| S04 | 搜索 | `S04-search-p1`、`S04-search-p50`（越界）、`S04-search-empty`、`S04-search-anchors`（`t=1` 对照） |
| S05 | 详情 | `S05-detail-live`、`S05-detail-offline` + `S05-page-offline`、`S05-detail-missing` + `S05-page-missing`、`S05-page-asid`、`S05-page-live` |
| S06 | stream-manager | `S06-streams-g1`、`S06-streams-g2`、`S06-streams-g2-l10`、`S06-streams-g2-l14`、`S06-streams-g3`（不可播档位）、`S06-streams-offline` |
| S07 | 移动 HLS | `S07-mobile-hls`、`S07-mobile-hls-offline` |
| S08 | 弹幕帧 | `danmaku/S08-live`（2026-09-27，房间 54880976，120 秒，594 帧：完整握手序列、2 条聊天、约 280 个应用 103 包（负载已清空）、心跳） |
| — | `ErrAuthNotPass` 频道 | **缺**：没找到能复现的频道 |

**需要脱敏的字段**

- FLV 签名 `rts_tk`、`secret`；移动 HLS 的 `tk`、`uuid`。`t` 保留（租期）。
- 弹幕：匿名登录应答里的 uid、用户名、密码、Cookie；AP 登录、加入频道、订阅包里的同一组值和连接 UUID；聊天的发送者 uid 和昵称、附加项（头像地址含 uid、昵称、贵族信息）；应用 103 的未解码消息只保留包头、清空负载。
- 主播公开信息（sid、主播名、头像、封面、流名）保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 3 个服务端渲染的分区（英雄联盟、综合、手机直播）有没有 JSON 列表 | 抓分区页“加载更多”的请求 |
| 2 | 可靠的主播搜索（`t=1` 的 `liveOn` 不准） | 对照多个在播主播 |
| 3 | `ErrAuthNotPass` 频道的 stream-manager 应答，以及移动 HLS 4000 档是否需要 | 找上游 #798 的房间 |
| 4 | 聊天附加项 100、101 的含义（和发送者昵称对不上） | 浏览器对照 |
| 5 | 应用 103 消息（礼物、进场）的格式 | 录更多帧，对照网页 |
| 6 | 登录后能否拿到更高档位 | 用维护者账号 |
| 7 | 已建立连接的最长持续时间（实测到 780 秒） | 长时间录制 |
