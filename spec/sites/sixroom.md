# 平台规格：六间房（sixroom）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`sixroom`，显示名“六间房”。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/sixroom/`（A = sixroom_api.dart，S = sixroom_site.dart，L = sixroom_link.dart）。样本编号见 §11。
- 状态：**保留**。2026-09-27 直连（中国大陆）实测：移动端列表接口、搜索页、房间页和 FLV 媒体都能匿名访问。不满足 ADR 0003 的任何下线条件。
- 能力：目录（4 个分区 + 推荐，分页）、搜索（主播，含未开播，一页）、详情、取流（HTTP-FLV，AVC）、链接解析。
- 不提供：弹幕（旧版未接入；聊天走私有 WebSocket，见 §7）；画质选择；登录。

---

## 1. 房间身份与链接

**规范身份**：房间号（`rid` / `roomid`，2–12 位数字，L:2）。

- 注意命名混乱：列表接口的 `rid` 是**房间号**，`uid` 是用户 id；房间页脚本里的 `rid: '…'` 却是**用户 id**，房间号在 `roomid`（S03-room-live：`rid: '53007895'`、`roomid: 16066`）。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯房间号 | `16066` | 直接使用 | L:15-16 |
| 房间页 | `https://v.6.cn/<房间号>`、`https://m.6.cn/<房间号>` | 路径只有一段 | L:17-29 |
| 资料页 | `https://v.6.cn/profile/<房间号>` | 搜索结果对未开播主播给的就是这种链接（S02-search） | L:30-32 |
| 分享文本 | 链接前后有文字 | 抽出第一个 URL | — |

- 外部打开：`https://v.6.cn/<房间号>`（L:4）。

## 2. 目录

### 2.1 分区

- 旧版下载 76 万字节的首页，在内嵌的 `typeList` 里按 `anchor_area` 本地筛选（A:239-258,340-376）。v4 改用移动端列表接口，按类型分页，不再下载首页。
- 类型和分区名（名称取自列表里的 `anchor_area`，2026-09-27 实测）：

| 类型 | 分区 |
|---|---|
| `u0` | 歌区 |
| `u1` | 舞区 |
| `u2` | 脱口秀 |
| `u8` | 派对 |

  `u10`（星颜）在 `roomListCount` 里有数，但请求返回 `content: []`，不提供 [待确认]。`male`、`new`、`mlive` 等是跨分区的专题，不作分区。
- v4 只有一个一级分类（id `v6`，名称“分区”）。

### 2.2 分区房间与推荐

- `GET https://v.6.cn/coop/mobile/index.php?padapi=coop-mobile-getlivelistnew.php&av=3.1&encpass=&logiuid=&isnew=1&size=20&p=<n>&type=<类型>`，UA 用 iOS 客户端 `ios/7.830 (ios 17.0; ; iPhone 15 (A2846/A3089/A3090/A3092))`（A:121,136-141）。响应的 Content-Type 是 `text/html`，正文是 JSON。
- 响应 `{flag: "001", content: {<类型>: [...], roomListCount: {<类型>: 总数, ...}, tagInfo, ...}}`（S01-list-u0-p1）；类型没有房间时 `content` 是空数组。`flag` 不是 `001` → ApiChanged。
- 推荐：类型 `special`（跨分区的热门，S01-list-special-p1）。
- 翻页：本页非空且 `页码 × 20 < roomListCount[类型]` 时还有下一页（S01-list-u0-p3 为 59 条里的最后 19 条，S01-list-u0-p4 为空）。
- 卡片：房间 id `rid`；昵称 `username`；标题 `livetitle`，空时 `userMood`（签名），再空用昵称；封面 `pic`（缺时 `pospic`）；头像 `picuser`；分区 `anchor_area`；在线人数 `count`。列表只有直播中。

## 3. 搜索

- `GET https://v.6.cn/search.php?type=use&key=<kw>`（A:268-274），HTML。
- 结果在 `page-search-user` 区块，每人一个 `<li data-uid="<用户 id>">`：链接 `/<房间号>` 或 `/profile/<房间号>`、`rid-num` 房间号、`alias` 昵称、`data-src` 头像；直播中带 `<i class="live" title="直播中">`（S02-search）。只有一页。
- 没有结果：仍有 `page-search-user` 区块，里面没有 `li`（S02-search-empty）。
- 关键词过长：返回“六间房提示您”页，`rcontent` 为“输入内容过长”，没有结果区块 → 空结果。其它提示页 → ApiChanged（带提示文字）。旧版把所有提示页当“无权访问”（A:380-382）。
- 卡片：标题和昵称都用 `alias`；没有封面和人数。

## 4. 房间详情

- `GET https://v.6.cn/<房间号>`（HTML，约 65 KB）。旧版先读房间页取用户 id，再 POST 移动端 `coop-mobile-inroom.php`（约 18 万字节，含观众列表和聊天记录，A:276-293）。房间页脚本已经包含详情和取流需要的全部字段，v4 只读房间页。
- 房间页脚本 `Object.assign(page, {...})` 里的字段（S03-room-live）：

| 字段 | 用途 |
|---|---|
| `rid: '<用户 id>'`、`roomid: <房间号>` | 身份；`roomid` 必须等于请求的房间号，否则 ApiChanged |
| `masterName: '<昵称>'` | 昵称 |
| `privNotic: "<签名>"` | 标题（可能含 `<a>` 链接，去掉标签）；空时用昵称 |
| `posterPic`、`picuser` | 封面、头像 |
| `liveid: '<场次>'` | `0` 表示未开播 |
| `usertype: 'u0'` | 分区（按 §2.1 的表） |
| `flvTitle: {"1": {"flvtitle": "v<用户 id>-<场次>", "streamInfo": {…: {"videoCodec": "AVC", "resolution": …}}}}` | 流名和编码 |

- 状态：`liveid != 0` 且 `flvTitle` 里有合法流名 → 直播；`liveid == 0` → 未开播（S03-room-offline，`flvTitle` 只剩礼物统计）；`liveid != 0` 却没有流名 → ApiChanged。
- 不存在：HTTP 404“页面未找到”（S03-room-notfound）→ NotFound。
- 旧版的房间页正则要求 `rid: '…', roomid: '…'` 都带引号且在同一行（A:399），现在 `roomid` 不带引号、分在两行，旧版因此所有房间都打不开详情。
- 人数：房间页没有在线人数，三个口径为空。

## 5. 画质与线路

- 一档 `source`“原画”，一条线路 `wlive`。
- 编码：取 `streamInfo[流名].videoCodec`（AVC → `avc`，HEVC → `hevc`）；`isPlayWithH265: '0'`。2026-09-27 读取 FLV 头：video codec id 7。
- 服务端确认的画质：无。

## 6. 取流

- 取流时重新读房间页（§4），不复用详情。
- 地址：`https://wlive.6rooms.com/httpflv/<流名>.flv`（A:520-537），没有签名和过期参数，`lease` 为空。请求会 302 到网宿的调度地址。
- 请求头：UA、`Origin: https://v.6.cn`、`Referer: <房间页>`（A:143-147）。

## 7. 弹幕

不做。旧版未接入；房间页的聊天走 6.cn 私有 WebSocket（需要 `encpass` 等会话参数），匿名接入方式 [待确认]。

## 8. 登录与 Cookie

不支持。私密房间（旧版 `isPriveRoom`、`blackScreenInfo`，A:431-434）在房间页上的表现 [待确认]。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| 房间页 404 | 状态码 | NotFound |
| 列表 `flag != "001"` | JSON | ApiChanged |
| 房间页缺字段、房间号不符 | HTML | ApiChanged |
| 搜索提示页（不是“输入内容过长”） | HTML | ApiChanged |
| 未开播 | `liveid == 0` | 房间 offline；取流 StreamUnavailable |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 所有房间详情失败 | 房间页脚本格式变了，旧正则要求带引号的 `roomid` | 分别匹配 `rid: '…'` 和 `roomid: …` | A:399；S03-room-live |
| 目录慢、流量大 | 每次下载 76 万字节的首页再本地筛选 | 移动端列表接口按类型分页 | A:239-258 |
| 详情请求大 | 取详情走 18 万字节的 inroom 接口 | 房间页脚本就够 | §4 |

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/sixroom.dart）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/sixroom_test.dart 直接对照正文。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-list-u0-p1`、`-p3`、`-p4` | 歌区第 1 页、末页（59 条）、越界空页 |
| S01 | `S01-list-special-p1`、`S01-list-u8-p1` | 推荐、派对 |
| S02 | `S02-search`、`S02-search-empty` | 搜索结果（含直播标记）、无结果 |
| S03 | `S03-room-live`、`-offline`、`-notfound` | 房间页三种情况 |

**需要脱敏的字段**：房间页 `flvTitle` 里推流服务器的内网 `ip`、`uploadip2`，以及出现时的观众排行（`fansList`、`rankList`）。主播公开信息保留；推流端报告（`banlvInfo`，含主播局域网内的 ping 输出和 CPU 型号）属于主播公开页面上的数据，原样保留。

## 12. 待确认

1. 星颜（`u10`）等空类型的正确参数。
2. 私密房间、黑屏房间在房间页上的字段。
3. 聊天 WebSocket 的匿名接入。
4. 搜索是否能翻页。
