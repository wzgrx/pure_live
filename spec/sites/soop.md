# 平台规格：SOOP（soop，原 AfreecaTV）

- 平台 id：`soop`（legacy/lib/core/sites.dart:51）；显示名“SOOP”（旧版“SOOP直播”，legacy/lib/core/site/soop/soop_site.dart:19）。
- 阶段：第二批（docs/adr/0003-platform-batches.md），第 7 阶段前段迁移。
- **去留：保留。** 2026-09-27 实测不满足下线标准：匿名取流成功（`live_cli probe soop khm11903` 直连和经 Clash 代理都读到 HLS 播放列表），公开目录完整（544 个分类，全站在播约 2100 个）。**19 禁（成人）直播需要登录**（`RESULT -6`，§4），只占一小部分（实测推荐前 60 个里 3 个），不构成“需要应用不支持的登录才能观看”的整体下线条件；这类直播 v4 报 NeedsLogin，用户存了 Cookie 时照常取流。
- 能力：单层分类目录（544 个分类）、推荐（全站按人数）、直播搜索、详情、取流（HLS，一条线路，不需要续期）、弹幕（需要保留大小写的握手和 `chat` 子协议）、可选 Cookie。
- 网络：接口在国内直连可用（出口 IP 在美国，接口按 `geo_cc: US` 正常应答）；海外平台，应用应允许走代理。弹幕的 TLS 端口在本机网络不可达，走明文端口（§7.1）。
- 证据口径：旧代码写成 `legacy/…:行号`；“实测”指 2026-09-27 在本机发出的匿名请求；样本编号见 §11（`fixtures/soop/`）。
- 路径简写：`site` = legacy/lib/core/site/soop/soop_site.dart，`dm` = legacy/lib/core/danmaku/soop_danmaku.dart，`ws` = legacy/lib/core/utils/yy/yy_web_socket_channel.dart，`reo` = legacy/lib/modules/live_play/services/room_external_opener.dart，`wsp` = legacy/lib/modules/search/web_search_room_parser.dart，`url_tool` = legacy/lib/common/utils/live_url_tool.dart，`phr` = legacy/lib/player/core/playback_header_resolver.dart。

---

## 1. 房间身份与链接

**规范身份**：主播 id（BJ id，`user_id` / `BJID`），小写字母、数字和下划线，以字符串保存。

- 一次直播有直播号 `broad_no`（`BNO`），每次开播都变，不作身份，放进弹幕参数。
- 聊天里的观众 id 可能带 `(2)` 这样的后缀（同一账号的第几个会话），主播 id 不带。

**可接受的输入**（都不联网）

| 形式 | 例 | 处理 | 证据 |
|---|---|---|---|
| 主播 id | `khm11903` | 直接作为 id（统一小写） | — |
| 播放页 | `https://play.sooplive.co.kr/khm11903/297314125` | 取第一段 | wsp:159；url_tool:146, 334 |
| 频道页 | `https://ch.sooplive.co.kr/khm11903`、`https://www.sooplive.co.kr/station/khm11903` | 第一段，或 `station` 后一段 | — |
| 旧域名 | `https://play.afreecatv.com/khm11903`、`*.sooplive.com` | 同上 | 旧版只认 `sooplive.co.kr`（wsp）或 `sooplive.com`（url_tool），两处不一致 |

- `search`、`directory`、`category`、`login`、`live`、`vod` 等不是主播。

**外部打开**：`https://play.sooplive.co.kr/<id>`（reo:184）。

---

## 2. 目录

### 2.1 分类

- GET `https://sch.sooplive.co.kr/api.php?m=categoryList&szKeyword=&szOrder=view_cnt&nPageNo=<p>&nListCnt=120&nOffset=0&szPlatform=pc`（site:144-174）。
- 响应 `data.list[]`：`category_no`（分区 id）、`category_name`（韩文名）、`cate_img`（图标）、`view_cnt`（当前人数）；`data.is_more` 表示还有下一页。按人数从多到少。
- 平台只有一层分类。v4 把全部分区放在一个一级分类下，沿用旧版的 id `1` 和名字“热门”（site:44-58），旧版收藏的分区不会换归属。
- 实测 544 个分区、5 页（120、120、120、120、64），第 5 页 `is_more == false`（S01-category-p1～p5）。v4 逐页取到 `is_more` 为假，最多 20 页。旧版以“满 120 条”判断还有下一页（site:122-142），v4 用 `is_more`。
- 第 1 页之后绝大多数分区当前 0 人，照样列出。

### 2.2 分区房间

- GET `api.php?m=categoryContentsList&szType=live&nPageNo=<p>&nListCnt=60&szPlatform=pc&szOrder=view_cnt_desc&szCateNo=<category_no>`（site:198-234）。
- 响应 `data.list[]`、`data.is_more`。字段：`user_id`、`user_nick`、`broad_title`、`thumbnail`（封面）、`user_profile_img`（头像）、`view_cnt`（**在线人数**）、`broad_start`（韩国时间 `2026-09-22 19:59:31.0`，v4 按 UTC+9 解析）、`grade`（19 为成人）、`is_password`。
- 结束：列表为空或 `is_more == false`（S02-area-p1 60 条且有下一页；S02-area-short 34 条、`is_more == false`）。

### 2.3 推荐

- GET `https://live.sooplive.co.kr/api/main_broad_list_api.php?selectType=action&selectValue=all&orderType=view_cnt&pageNo=<p>&lang=ko_KR`（site:310-345）。
- 响应 `total_cnt`、`cnt`、`broad[]`，每页 60 条；实测共约 2120 条，第 36 页 20 条，第 37 页空（S03-main-p1、S03-main-p36、S03-main-p37）。以空页结束。
- 字段：`user_id`、`user_nick`、`broad_title`、`broad_thumb`（`//` 开头，补 https）、`category_name`、`broad_start`、`broad_grade`、`is_password`、`total_view_cnt`（= `pc_view_cnt` + `mobile_view_cnt`）。

### 2.4 人数

- 列表的 `view_cnt`、推荐的 `total_view_cnt`、搜索的 `total_view_cnt`、主页的 `current_sum_viewer` 都是**在线人数**（PC + 手机）。`current_view_cnt` 只是 PC 端，不能单独用（site:67-108；DEPENDENCY_AUDIT.md:91）。

---

## 3. 搜索

- GET `api.php?l=DF&m=liveSearch&c=UTF-8&w=webk&isMobile=0&onlyParent=1&szType=json&szOrder=score&szKeyword=<kw>&nPageNo=<p>&nListCnt=30&tab=live&location=total_search&isHashSearch=0&v=2.0`（site:629-676）。
- 结果 `REAL_BROAD[]`：只有在播直播。字段同 §2.3，封面是 `broad_img`，分区是 `broad_cate_name`。
- **结束只看空页**：无结果时 `HAS_MORE_LIST` 仍为 `true`、`TOTAL_CNT` 也不为 0（S04-search-empty：`true`、116、0 条），这两个字段不可信。
- 空关键词不请求。

---

## 4. 房间详情

1. POST `https://live.sooplive.co.kr/afreeca/player_live_api.php?bjid=<id>`，表单 `bid=<id>&bno=&type=live&pwd=&player_type=html5&stream_type=common&quality=HD&mode=landing&from_api=0&is_revive=false`，请求头 `referer: https://play.sooplive.co.kr/<id>`、`origin`（site:542-560）。结果在 `CHANNEL.RESULT`（site:433 注释“1 成功，-6 需要登录，0 无直播，-2 屏蔽”）：

| RESULT | 含义 | 证据 |
|---|---|---|
| 1 | 在播：`BJID`、`BJNICK`、`TITLE`、`CATEGORY_TAGS[0]`（分区）、`BNO`、`VIEWPRESET`、`CDN`、`RMD`、`CHATNO`、`CHDOMAIN`、`CHIP`、`CHPT`、`BPWD`（`Y` 有密码）、`GRADE` | S05-live-live |
| 0 | 未开播**或主播不存在**，两者响应相同 | S05-live-offline、S05-live-missing |
| -6 | 需要登录（19 禁），另给 `TITLE`、`CATE` | S05-live-adult |
| -2 | 屏蔽（旧版注释，没有样本） | site:433 |

2. GET 主页接口 `https://chapi.sooplive.co.kr/api/<id>/station`，Referer `https://ch.sooplive.co.kr/`：`station.user_nick`、`station.station_title`（作简介）、`profile_image`、`broad`（在播时有 `broad_no`、`broad_title`、`current_sum_viewer`；未开播为 `null`）。
   - 不存在的主播：**HTTP 515**，`{"code": 9000, "message": "The channel does not exist."}` → NotFound（S05-station-missing）。实测这个接口偶尔返回 502，按网络错误处理。
3. 组合：
   - RESULT 1：以第 1 步为准，第 2 步补人数、头像、简介（失败时不补）。
   - RESULT 0：看第 2 步，`broad` 为空则未开播，有则在播（两次请求之间开播）；不存在则 NotFound。旧版把 RESULT 0 一律当未开播（site:383-386），不存在的主播也显示成未开播。
   - RESULT -6：看第 2 步，按在播显示（S05-station-adult：`broad_grade 19`），取流时报 NeedsLogin。
- 封面：`https://liveimg.sooplive.co.kr/m/<BNO>`（site:458-459）；头像：`https://stimg.sooplive.co.kr/LOGO/<id 前两位>/<id>/<id>.jpg`（site:678-684）。
- **弹幕参数**：`{bj, bno, chatNo, chatHost, chatPort}`；`chatHost` 优先 `CHDOMAIN`，没有时由 `CHIP` 的四段十六进制拼出 `chat-<HEX>.sooplive.com`（site:590-627）。
- 旧版在详情失败时换成“错误房间”（site:348-371），v4 返回失败。

---

## 5. 画质与线路

- 画质来自 `VIEWPRESET[]`：`name`（请求码：`sd`、`hd`、`hd4k`、`original`）、`label`（`360p`…`1080p`）、`bps`、`label_resolution`。去掉 `auto`（“자동”），按 `bps` 从高到低（S05-live-live）。`Quality.id` = `name`。
- 线路只有一条：`CDN`（例如 `gcp_cdn`）。线路身份 = CDN 代码。
- 服务端不回报实际画质，`confirmed` 为空（未确认）；流名里含画质名（`…-common-original-hls_…`），可以作为旁证。

---

## 6. 取流

### 6.1 前提

- 再请求一次 §4 第 1 步（取流时的新鲜状态）：RESULT -6 → NeedsLogin；0 → StreamUnavailable；`BPWD == Y`（密码房）→ StreamUnavailable（v4 不支持输入密码 [待确认]）。

### 6.2 分配播放地址

- GET `<RMD>/broad_stream_assign.html?return_type=<类型>&broad_key=<BNO>-common-<画质>-hls`（site:489-514）。`RMD` 实测为 `https://livestream-manager.sooplive.com`。
- `return_type`：`CDN` 含 `gs_cdn` 用 `gs_cdn_pc_web`，含 `lg_cdn` 用 `lg_cdn_pc_web`，否则原样（实测 `gcp_cdn`）。
- 应答 `{"result": "1", "view_url": "https://live-global-cdn-v02.sooplive.com/live-stmc-28/auth_playlist.m3u8", "stream_status": …}`（S06-assign-original）。

### 6.3 播放密钥

- POST 同一个 player API，`type=aid`、`bno=<BNO>`、`quality=<画质>`（site:516-540）→ `CHANNEL.AID`（S06-aid-original）。19 禁直播匿名时 RESULT -6（S06-aid-adult）。
- 地址 = `view_url` + `?aid=<AID>`。

### 6.4 线路

| 数据 | 值 |
|---|---|
| 格式 | HLS（媒体播放列表，2 秒分片，CloudFront） |
| 请求头 | `user-agent`、`referer: https://play.sooplive.co.kr/`、`origin: https://play.sooplive.co.kr`（phr:125-131） |
| 编码 | AVC（`VIEWPRESET[].vcodec == h264`） |
| 租期 | **没有**：同一个带 `aid` 的播放列表每 2 分钟刷新一次、持续 40 分钟都正常，分片也都能取到（实测 2026-09-27） |

- 旧版把分配地址和密钥放在取播放地址时逐个画质请求（site:285-307），v4 只为选中的画质请求一次。

---

## 7. 弹幕

### 7.1 连接

- 地址：`<CHDOMAIN>`，路径 `/Websocket/<主播 id>`。网页在 https 下用 `CHPT + 1` 的 TLS 端口，在 http 下用 `CHPT` 的明文端口（网页播放器 LivePlayer.js 的 `nChatPort`；site:586-627）。
- **本机网络下 TLS 端口不可达**：`chat-*.sooplive.com:9001` 在 ClientHello 之后直接断开（openssl、Python、Dart 直连和经代理都一样，换 SNI 也一样；实测 2026-09-27），明文端口 9000 正常升级。v4 依次尝试 `wss://…:<CHPT+1>` 和 `ws://…:<CHPT>`。明文连接只传公开的房间号和公开的聊天，不带任何凭据。
- 握手：子协议 `chat`；**必须保留大小写**（旧版改用自写的 WebSocket，dart:io 的小写升级头会被挂起，ws:10-40）；`Origin: https://play.sooplive.co.kr`（dm:70-74）。
- 匿名。

### 7.2 包格式

- `ESC TAB`（`1B 09`）、4 位十进制服务号、6 位十进制正文字节数、`00`、正文；正文字段以换页符 `0x0C` 分隔（dm:115-193）。
- 一个帧可以含多个包，按长度切分。

### 7.3 加入

1. 发服务 1（登录）：正文 `\f\f\f16\f`（dm:117）。
2. 收到服务 1 的应答后发服务 2（加入）：正文 `\f<CHATNO>\f\f\f\f\f`（dm:121-122）。旧版在登录后固定等 200 毫秒再加入，v4 改为等登录应答。
3. 收到服务 2 且字段 1 等于 `CHATNO` 即加入成功（S07-live：`\f4172\fkhm11903\f0\f30\f\f1\f16|16384\f`）。
- 帧用二进制发送（实测和文本帧一样被接受）。

### 7.4 消息

- 聊天是服务 5：字段 1 正文、字段 2 发送者 id（可能带 `(n)`）、字段 6 昵称（dm:180-193；S07-live）。字段 10、11 像是昵称颜色（`B26C03`），v4 不用。
- 其它服务（实测 20 秒内：服务 4 约 1200 个观众名单包、127 约 1000 个观众标记包，还有 12、18、19、21、54、90、94、110）不解码。其中 18 可能是星气球（礼物）[待确认]。
- 实测聊天量大：khm11903（3.5 万人）20 秒约 140 条。

### 7.5 心跳

- 每 20 秒发服务 0：正文 `\f`（dm:43, 131-134）。

---

## 8. 登录与 Cookie

- 旧版有 SOOP Cookie 设置，拼进所有请求（site:184-195）。
- v4：用户存了 Cookie 时只随 player API 发送（§4、§6.3），用于 19 禁直播；目录、搜索不带。登录后的具体表现 [待确认：没有账号可测]。
- 服务端对匿名请求也会下发 `AbroadChk`、`AbroadVod`、`_au*` 等 Cookie（样本的 Set-Cookie，已脱敏），v4 不保存、不回传。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx（515 除外） | 实测主页接口偶发 502 | NetworkFailure |
| player API 没有 `CHANNEL.RESULT`；分配地址 `result != "1"`；RESULT 为 1/0/-6 以外 | — | ApiChanged |
| 主页接口 515 + `code 9000` | S05-station-missing | NotFound |
| RESULT -6（详情时） | S05-live-adult | 在播，取流时 NeedsLogin |
| RESULT -6（取流、`type=aid`） | S06-aid-adult | NeedsLogin |
| RESULT 0（取流时） | S05-live-offline | StreamUnavailable |
| 密码房 `BPWD == Y` | 没有样本 | StreamUnavailable |
| 弹幕 TLS 端口不通 | 实测 | 换明文端口 |
| 详情里没有聊天服务器 | — | 弹幕终态 `credentials` |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-SOOP-001 | 弹幕连不上 | dart:io 小写升级头被挂起 | 保留大小写的握手 | ws:10-40 |
| REG-SOOP-002 | 弹幕 WSS 握手卡在 TLS | 连了 `CHPT` 本身（明文端口） | https 用 `CHPT + 1`；本机 TLS 端口不通时退回明文 | site:586-589；实测 |
| REG-SOOP-003 | 在线人数只有一半 | 用了只算 PC 的 `current_view_cnt` | 用 `total_view_cnt` 或 PC + 手机 | site:67-108 |
| REG-SOOP-004 | 原画排到最后 | 源流缺码率时按码率排序 | 按 `bps` 排，`auto` 不列 | site:267-282 |
| REG-SOOP-005 | 不存在的主播显示“未开播” | RESULT 0 两种情况相同 | 查主页接口区分 | S05-live-missing、S05-station-missing |
| REG-SOOP-006 | 19 禁直播显示“状态未知” | RESULT -6 被当成失败 | 详情按在播，取流报需要登录 | site:432-444；S05-live-adult |
| REG-SOOP-007 | 搜索永远“加载更多” | `HAS_MORE_LIST` 在空页也为真 | 只以空页结束 | S04-search-empty |
| REG-SOOP-008 | 播放地址过期、续播失败 | （预期的问题，实测不存在） | 带 `aid` 的播放列表 40 分钟有效，不设租期；断开后重新取流 | 实测 |

---

## 11. 样本清单

2026-09-27 直连录制，共 25 个 HTTP 样本（`fixtures/soop/`，规则 `tools/live_cli/lib/src/fixture/rules/soop.dart`）和 1 个弹幕样本。期望值写在 `packages/live_core/test/sites/soop_*_test.dart`、`packages/live_danmaku/test/soop_test.dart`。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | 分类 | `S01-category-p1`～`S01-category-p5`（544 个，第 5 页结束） |
| S02 | 分区房间 | `S02-area-p1`（토크/캠방，60 条、有下一页）、`S02-area-short`（FC 온라인，34 条、结束） |
| S03 | 推荐 | `S03-main-p1`、`S03-main-p36`（20 条）、`S03-main-p37`（空） |
| S04 | 搜索 | `S04-search-p1`（“게임”，30 条）、`S04-search-empty` |
| S05 | 详情 | `S05-live-live` + `S05-station-live`、`S05-live-offline` + `S05-station-offline`、`S05-live-missing` + `S05-station-missing`、`S05-live-adult` + `S05-station-adult` |
| S06 | 取流 | `S06-assign-original`、`S06-aid-original`、`S06-assign-hd`、`S06-aid-hd`、`S06-aid-adult` |
| S07 | 弹幕帧 | `danmaku/S07-live`（khm11903，20 秒，3589 帧，约 140 条聊天；先连 TLS 端口失败再连明文端口，两个握手都记在 meta.json） |
| — | 密码房、`RESULT -2`、登录后的请求 | **缺** |

**需要脱敏的字段**

- `AID`、`AID_H`（播放密钥）、`COLONY_CONTENT`；player API 的 `TS`、`TS_SNAPSHOT` 地址里的 `data`；地址里的 `aid`。
- Set-Cookie（`AbroadChk`、`AbroadVod`、`_au`、`_au3rd`、`_ausa`、`_ausb`，工具统一脱敏）。
- 弹幕：聊天发送者 id 和昵称换成假名（保留 `(n)` 后缀）；服务 4、127 等观众名单和其它没有解码的服务清空正文。
- 主播公开信息（id、昵称、直播号、标题、封面、聊天服务器）保留。`geo_cc`、`geo_rc` 是按出口 IP 判断的国家和地区，只到国家一级，保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 弹幕 TLS 端口在别的网络（韩国、国内直连）是否可达 | 换网络测 `chat-*.sooplive.com:<CHPT+1>` |
| 2 | 密码房的表现和密码提交方式 | 找真实密码房 |
| 3 | `RESULT -2`（屏蔽）的样子 | 找被屏蔽的直播 |
| 4 | 登录后 19 禁直播的完整流程（Cookie 字段、`AID` 是否不同） | 维护者账号 |
| 5 | 服务 18 等是否是礼物，字段含义 | 录更多帧对照网页 |
| 6 | `CDN` 为 `gs_cdn`、`lg_cdn` 时的地址形态（本次只见到 `gcp_cdn`） | 国内/韩国网络复测 |
