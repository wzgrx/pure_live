# 平台规格：inke（映客直播）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`inke`（legacy/lib/core/sites.dart:57），显示名“映客”（legacy/assets/translations/zh.json `site_inke`）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/inke/`（A = inke_api.dart，S = inke_site.dart），其它旧代码写全路径（相对 `legacy/`）。样本编号见 §11。
- 状态：**保留**。2026-09-27 实测：网页接口、App 公开接口、媒体都能在中国大陆直连匿名使用。
  - 旧版只能播放“正好出现在官网展示位里”的直播：网页房间接口匿名不给拉流地址，旧版只能到首页展示位里找同一场直播的地址，找不到就报“媒体不可用”（A:277-299）。官网房间页匿名打开也只显示“下载手机APP查看”（`liveroom.www.*.chunk.js`：`hasPlayableStream` 为假时渲染下载入口）。照旧版的做法，关注的主播多半播不了，接近 ADR 0003 下线条件 1。
  - v4 改用 App 的公开接口 `service.inke.cn/api/live/now_publish?id=<uid>`：任何在播主播都能匿名拿到签名的拉流地址（§5）。所以不下线。
- 能力：目录（官网 6 个频道展示位；推荐 = App 热门列表）、搜索（uid 精确查找；关键词只在公开展示位里按昵称过滤，没有服务端搜索）、详情、取流（H.264 的 FLV，一条线路）。
- 不提供：弹幕（匿名拿不到连接地址，§7）；登录；回放（`records` 里的录像，v4 不做）；Zego 线路（HEVC，§6.4）。

---

## 1. 房间身份与链接

**规范身份**：主播 uid（`inke_id`、`live_uid`、`creator`，1～18 位数字；A:131-136）。每场直播有一个新的 `liveid`（16 位），不作为身份（A:29-31）。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯数字 | `771067357` | uid | A:132-136 |
| 网页房间 | `https://www.inke.cn/liveroom/index.html?uid=<uid>&id=<liveid>`（主机也可以是 `inke.cn`、`inke.com`、`www.inke.com`） | 取 `uid` | A:138-154 |
| App 分享 | `https://mlive2.inke.cn/app/hot/live?uid=<uid>&liveid=<liveid>&ctime=…`（接口的 `share_addr`） | 取 `uid`；主机 `mlive<n>.inke.cn`、路径以 `/app/` 开头。旧版不认，v4 新增 | S04-publish-live |
| 分享文本 | 链接前后夹有文字 | 抽出第一个 URL | — |

- 不存在的 uid 与“没有在播”的回答一样（`live_share_pc` 都是 `1099999920 当前用户无直播`，`now_publish` 都是 `live: null`），无法区分，按未开播处理。
- 外部打开：在播时 `https://www.inke.cn/liveroom/index.html?uid=<uid>&id=<liveid>`；没有 `liveid` 时去掉 `id`（旧版此时打开官网首页，S:26-39）。

---

## 2. 目录

两套接口：
- 网页：`https://webapi.busi.inke.cn/web/<名字>`，`{error_code, message, data}`，`error_code == 0` 成功（A:83-118）。响应的 Content-Type 是 `text/html`，正文是 JSON。
- App：`https://service.inke.cn/api/live/<名字>`，`{dm_error, error_msg, …}`，`dm_error == 0` 成功。

### 2.1 分类

- GET `web/Live_channel_pc`：`data.list[]` 每组 `tab_key`、`channel_name`、`list[]`（A:208-232；S01-channels：音乐、舞蹈、新颜、校园、男神、派对，每组 7～8 个直播）。
- v4：一个 `Category`（id `channel`，名称“频道”），每组一个 `Area`（id = `tab_key`）。

### 2.2 频道房间

- 同一个接口里该组的 `list[]`，只有一页（A:254-275）。条目：`uid`、`live_id`、`nick`、`portrait`、`stream_addr`、`stream_multi_addr`；没有标题，标题用昵称（A:186-206）。全部在播。
- `web/Live_top_pc`：首页 8 个推荐位，字段同上（S01-top）。只用于搜索（§3）。

### 2.3 推荐

- 旧版用 `Live_top_pc` 的 8 个（S:69-73）。v4 用 App 热门 GET `api/live/simpleall`（S02-simpleall：约 20 个，每次请求的内容会变），字段完整：
  - `creator.id`（uid）、`creator.nick`、`creator.portrait`；`name`（标题）、`cover`、`city`、`start_time`（Unix 秒）。
  - 人数：`numbers.real` 是 App 显示为“N人在看”的数（`real_number_text: "12#人在看"`，S04-publish-live），作为**在线**；`online_users` 是更大的展示数（S02 第一条 2993 对 `real` 1586），作为**热度**。旧版不显示人数（A:203-204）。
- 只有一页；`offset`、`count` 参数的作用不稳定（带 `offset=20` 返回 14 条不同的直播），v4 不翻页。

---

## 3. 搜索

- 输入是 uid 或本平台链接：精确查找（§4），一页（S:88-110 同义）。其它 `http(s)://` 输入不搜索。
- 映客没有匿名的服务端搜索（`api/user/search` 返回 `499 请求参数错误`）。关键词在 `Live_top_pc`、`Live_channel_pc` 全部频道和 `simpleall` 里按昵称（不区分大小写）过滤，按 uid 去重，只有一页（A:234-252 只查前两个）。

---

## 4. 房间详情

两次请求：

1. GET `web/live_share_pc?uid=<uid>`（A:301-340）：`media_info`（`nick`、`portrait`、`description`、`area`）、`live_uid`、`liveid`、`live_name`、`status`；`records[]` 是旧录像。没有在播：`error_code 1099999920`、`data: null`（S03-share-offline）。
2. GET `api/live/now_publish?id=<uid>`：当前直播 `live`（`id`、`creator`（uid，整数）、`name`、`cover`、`status`、`start_time`、`numbers.real`、`online_users`、`stream_addr` …）；没有在播：`live: null`（S04-publish-offline）。

- `now_publish.live.creator` 必须等于 uid，`live_share_pc.live_uid` 也必须等于 uid，否则 ApiChanged（A:317-322）。
- 状态：`live.status == 1` 直播中，其它（含 `live: null`）未开播。映客没有回放状态。
- 标题：`live.name`，缺失时 `live_name`，再缺失用昵称。封面 `live.cover`，缺失用头像。开播时间 `start_time`。
- 人数同 §2.3。

---

## 5. 画质与线路

- `now_publish.live` 两个地址：
  - `stream_addr`：`https://live-pull-ws.ikstatic.cn/live/<liveid>_t.flv?stream_id=<liveid>_t&wsSecret=<md5>&wsABStime=<hex 秒>`（网宿，转码后的 **H.264**，720×1280，15 fps）；
  - `stream_multi_addr`：`http://live-pull-zego.ikstatic.cn/inkemain/<liveid>_0_en.flv?…&codecInfo=8192&…`（即构，原始推流，**FLV codec id 12 = HEVC**，432×786）。S02 的 12 个直播全是这样。
- v4 只给网宿线路（线路身份 `ws`），画质“原画”一个。旧版只认网宿地址（A:164-179）。即构线路要等 live_media 实现旧版中继的 codec 12 → 增强 FLV 改写后才能用（§6.4）。
- 网宿地址不带签名直接请求会失败；必须用接口给的 `wsSecret`。

---

## 6. 取流

### 6.1 流程

每次取流重新请求 `now_publish`（签名会过期）。`live: null` 或 `status != 1` → StreamUnavailable；没有网宿地址 → StreamUnavailable。

### 6.2 租期

- `wsABStime` 是十六进制的到期时刻：网宿地址约签发后 2 小时（S04-publish-live），即构约 24 小时。
- v4：`expiresAt = wsABStime`；`refreshAt` = 到期前 min(10 分钟, 寿命的 1/4)；`cutsConnection = false`（网宿在建立连接时校验）[待确认]。

### 6.3 请求头

- `Referer: https://www.inke.cn/`、`Origin: https://www.inke.cn`、UA（A:37）。媒体不需要 Cookie。

### 6.4 媒体实况与 HEVC 缺口（2026-09-27）

- 网宿 `_t.flv`：`videocodecid 7`（AVC）、AAC，v4 直接播放。
- 即构 `_0_en.flv`：视频 tag 的 codec id 是 **12**（国内 CDN 的非标准 FLV HEVC），`codecInfo=8192` 标记。3.x 的本地中继会把它改写成增强 FLV（`hvc1`），live_media 还没有实现这一步，mpv/FFmpeg 读不了 codec 12。**缺口**：要提供映客原画 HEVC 线路，需要 live_media 实现 codec 12 改写；在此之前 v4 只用 H.264 转码线路。
- `live_cli probe inke <网页房间链接>`：解析 → 详情（在线 13）→ 取流（网宿 FLV）→ 读到 FLV 文件头，通过（2026-09-27，直连）。

---

## 7. 弹幕

- 旧版没有映客弹幕（S:49-50）。
- 官网房间页从 `live_share_pc` 的 `sio_url` 连 Socket.IO（`liveroom.www.*.chunk.js`），但匿名请求的响应里没有 `sio_url`，也没有 `live_addr`（S03-share-live 的字段只有 `media_info`、`records`、`status`、`portrait`、`liveid`、`live_uid`、`is_follow`、`live_type`、`sub_live_type`、`live_name`）。App 接口里也没有连接地址。
- 结论：匿名没有弹幕连接，v4 不做映客弹幕连接器 [待确认：登录后的 `sio_url` 形式]。

---

## 8. 登录与 Cookie

- 不支持登录。接口会下发 `PHPSESSID`、`_csrfToken`、`INKE_UUID`，匿名请求不需要带回。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | A:94-101 | NetworkFailure |
| HTTP 429 / 401、403 / 404 | 同上 | RateLimited / RiskControl / NotFound |
| `error_code 1099999920`（网页房间接口） | S03-share-offline；A:110-112 | 未开播（不是错误） |
| `now_publish` 的 `live: null` | S04-publish-offline | 未开播 |
| 其它 `error_code != 0`、`dm_error != 0` | A:113 | ApiChanged |
| 接口给的主播与请求的 uid 不同 | A:317-322 | ApiChanged |
| 未开播时取流；没有网宿地址 | §6.1 | StreamUnavailable |
| 未知频道 | A:265-266 | NotFound |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-INKE-001 | 关注的主播大多播不了 | 只在官网展示位里找拉流地址 | 用 App 的 `now_publish` | A:277-299；§5 |
| REG-INKE-002 | 选了“原画”线路黑屏 | 即构线路是 FLV codec 12 的 HEVC | 只用网宿 H.264 线路，缺口见 §6.4 | §6.4 |
| REG-INKE-003 | 在线人数虚高 | `online_users` 是展示数 | 在线用 `numbers.real`，展示数标为热度 | §2.3 |
| REG-INKE-004 | 样本泄露主播定位 | App 接口带 `gps_position` 和生日等资料 | 这些字段一律脱敏 | §11 |

---

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/inke.dart）。旧应用不能再运行（ADR 0016），没有 `expected.json`；v4 测试 packages/live_core/test/sites/inke_test.dart 直接对照样本。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | 网页展示位 | `S01-channels`（6 个频道）、`S01-top`（8 个推荐位） |
| S02 | App 热门 | `S02-simpleall` |
| S03 | `web/live_share_pc` | `S03-share-live`、`S03-share-offline`（`1099999920`） |
| S04 | `api/live/now_publish` | `S04-publish-live`、`S04-publish-offline`（`live: null`） |

**缺**：弹幕（匿名没有）。

**需要脱敏的字段**
- 拉流地址的 `wsSecret`（保留 `wsABStime`）。
- App 接口的 `gps_position`（主播精确定位）、`token`，主播资料里的 `birth`、`verified_birthday`、`ip_location`、`real_name`、`user_last_pay_date`。
- 会话 Cookie（Set-Cookie）。
- uid、直播 id、昵称、头像、标题、城市保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 网宿地址到期（约 2 小时）后已建立的 FLV 连接是否断开 | 连续播放超过 2 小时 |
| 2 | 即构线路是否全部是 codec 12；live_media 实现改写后能否作为原画线路 | 实现中继改写后对照 |
| 3 | 登录后 `live_share_pc` 是否给 `sio_url`、`live_addr` | 有账号后对照 |
| 4 | `simpleall` 的 `offset`/`count` 语义 | 多次请求对比 |
