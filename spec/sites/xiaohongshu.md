# 平台规格：小红书（xiaohongshu）

第 7 阶段，**仅链接**（docs/adr/0003-platform-batches.md：保留分享链接打开，不做目录）。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`xiaohongshu`，显示名“小红书”。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/xiaohongshu/`（A = xiaohongshu_api.dart，S = xiaohongshu_site.dart，L = xiaohongshu_link.dart，H = xiaohongshu_share.dart）。样本编号见 §11。
- 状态：**仅链接，保留**。2026-09-27 本机默认出口实测（2026-09-28 查明本机默认出口经系统层隧道在境外，不是中国大陆直连）：直播分享页 `www.xiaohongshu.com/livestream/<房间号>` 匿名可读，页面状态里有拉流配置，FLV/HLS 匿名可播。网页直播列表 `www.xiaohongshu.com/livelist` 是客户端渲染，接口要网页签名（`x-s`），匿名拿不到目录——这正是“仅链接”的原因。
- 能力：链接解析（房间号、分享页、`xhslink.com` 短链、App 深链、分享文本）、详情、取流（原画，FLV 三个 CDN + HLS，AVC）。
- 不提供：目录、搜索、弹幕、登录。

---

## 1. 房间身份与链接

**规范身份**：直播间号 `roomId`（1–20 位数字，H:66-70）。**每场直播一个新号**，收藏跟踪这一场（zh.json `xiaohongshu_room_scope`）。主播的 `host_id`（深链里有）不作身份。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯房间号 | `570459564696889177` | 直接使用 | L:55-56 |
| 分享页 | `https://www.xiaohongshu.com/livestream/<号>`（主机也可以是 `xiaohongshu.com`） | 取最后一段；忽略 `share_id` 等查询参数 | L:62-63 |
| 动态路由 | `…/livestream/dynpath<8 位字母数字>/<号>` | 分享跳转的中间形式 | L:64-66 |
| 旧路由 | `…/hina/livestream/<号>[/<别名>]` | 别名不是第二个房间号 | L:67-70 |
| App 深链 | `xhsdiscover://live_audience?room_id=<号>&…` | 取 `room_id`。旧版还要求有 `source` 参数（L:11-31）；分享页里的深链确实带 `source=share_out_of_app`，但 v4 不以它为条件 | S01-room-live |
| 短链 | `https://xhslink.com/<码>`、`/m/<码>` | 不自动跟随，逐跳读 `Location`（最多 5 跳，只在 `xhslink.com` 内继续）；落到分享页或深链就取房间号；落到别处（笔记、主页、首页）→ UnsupportedLink | L:73-110 |
| 分享文本 | “【小红书】…的直播 https://… 复制本条信息” | 抽出所有链接，第一个能给出房间号的获胜；都不是房间再看短链 | L:98-110 |

- 失效或非直播的短链：`https://xhslink.com/m/18ox3lAz` 302 到 `https://www.xiaohongshu.com` 首页（S02-shortlink-expired）→ UnsupportedLink。能跳到直播页的短链没有录到样本 [待确认]。
- 外部打开：`https://www.xiaohongshu.com/livestream/<号>`（L:112-113）。

## 2. 目录

不提供（仅链接）。`live_core` 适配器不实现目录接口。

## 3. 搜索

不提供。

## 4. 房间详情

- `GET https://www.xiaohongshu.com/livestream/<号>`，UA 用安卓 Chrome，`Referer: https://www.xiaohongshu.com/`（A:17-21,89）。**不跟随重定向**：必须是请求的这一页（旧版同样要求，H:73-74）。非 200 → ApiChanged。
- 页面状态：`window.__INITIAL_STATE__=<JSON>`，其中裸的 `undefined` 要在字符串之外换成 `null` 才能按 JSON 解析（H:76-130）。状态在 `liveStream` 下（2026-09 结构；旧版在顶层找 `pageStatus`，H:143，已失效）。
- `liveStream.pageStatus`：`"error"`（`errorMessage`“未找到直播间，请稍后再试”）→ NotFound（S01-room-notfound）；`"success"` 继续；其它 → ApiChanged。旧版把 error 当成无法判断（H:141-142）；v4 按提示文字判为不存在。
- `liveStream.roomData.roomInfo`（S01-room-live）：
  - **所有值都是字符串**：`status: "2"`、`monetizeType: "0"`、`joinLimitTypes: "[0]"`（JSON 数组的字符串）、`pullConfig`（JSON 字符串）、`isSportsEvent: "False"`。旧版要求 `status` 是整数（H:150），现在每个页面都判为格式错误。
  - `roomId`：在播页有，结束页没有（S01-room-ended）；有时必须等于请求的号。
  - `status` 与 `liveStatus`：`"2"` + `"success"` → 直播；`"3"` + `"end"` → 未开播；其它组合 → ApiChanged（H:152-162）。
  - `roomTitle` 标题；`roomCover` 封面；`displayViewerCount`（“300万+”，展示文字，不作为人数，zh.json `xiaohongshu_display_viewers`）。
- `hostInfo`：`nickName` 昵称、`avatar` 头像。
- 受限：`monetizeType != 0` 或 `joinLimitTypes` 有非 0 项 → 取流 NeedsLogin（H:164-176）。
- **`nextRoomInfo` 不用**：结束页会推荐另一个正在直播的房间，带它自己的 `pullConfig`（S01-room-ended）；它不是这个房间，也不能证明这个房间在播（H:177-179）。
- 人数：三个口径为空。

## 5. 画质与线路

- `pullConfig` = `{h264: [...], h265: [...], width, height}`，每项 `master_url`、`quality_type`（录到 `HD`）、`quality_type_name`（“原画”）（S01-room-live）。
- 画质：按出现顺序、按 `quality_type` 去重；id 用 `quality_type`，名称用 `quality_type_name`。
- 线路：该画质下的所有地址，按地址去重；FLV 在前、HLS 在后，H.264 在前、H.265 在后，其余保持平台顺序。录到 1 条 HLS（`live-source-play`）和 3 条 FLV（`live-source-play`、`-bak-tx`、`-hw`）。线路 id = `<格式>:<主机第一段>`。
- 编码：`h264` → `avc`，`h265` → `hevc`。
- 地址是 `http`，没有签名和过期参数，`lease` 为空。旧版只接受路径 `/live/<房间号>.(m3u8|flv)`、主机 `*.xhscdn.com`（H:224-233）；v4 只要求 http(s) 地址。

## 6. 取流

取流时重新读分享页（§4）；不在播 → StreamUnavailable；受限 → NeedsLogin；没有地址 → StreamUnavailable。请求头 UA、`Referer`；实测不带也能拉。

## 7. 弹幕

不做（仅链接）。分享页 `liveStream.comments` 在匿名状态下为空。

## 8. 登录与 Cookie

不支持。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| 分享页非 200（含重定向） | 状态码 | ApiChanged |
| 没有页面状态、结构不符、房间号不符、状态组合未知 | HTML/JSON | ApiChanged |
| 不存在 | `pageStatus == "error"` | NotFound |
| 短链不指向直播 | 跳转目标 | UnsupportedLink |
| 付费、限制观看 | `monetizeType`、`joinLimitTypes` | 取流 NeedsLogin |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 所有分享页解析失败 | 状态移到 `liveStream` 下，数字字段变成字符串 | 按新位置取，数字和列表都兼容字符串 | H:143-176；S01-room-live |
| 结束的直播间显示成别的直播 | 结束页带 `nextRoomInfo` 推荐 | 只看 `roomInfo`，不用 `nextRoomInfo` | S01-room-ended |

## 11. 样本清单

2026-09-27 本机默认出口录制（规则 tools/live_cli/lib/src/fixture/rules/xiaohongshu.dart）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/xiaohongshu_test.dart 直接对照正文。直播间号取自网页搜索到的公开分享页及其 `nextRoomInfo`。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-room-live` | 在播分享页（字符串字段、`pullConfig`、深链） |
| S01 | `S01-room-ended` | 结束页（无 `roomId`，带 `nextRoomInfo`） |
| S01 | `S01-room-notfound` | `pageStatus: "error"` |
| S02 | `S02-shortlink-expired` | 短链 302 到首页 |

**需要脱敏的字段**：分享页只有主播公开信息；页面状态里出现观众评论时替换 `userId`、`userName`、`nickname`（录到的 `comments` 为空）；匿名 Cookie 由工具统一替换。

## 12. 待确认

1. 指向直播间的有效短链样本及其跳转链（经过 `dynpath` 的中间页）。
2. 付费、限制观看直播的页面样本。
3. H.265 和多档画质的 `pullConfig` 样本。
4. 是否能按主播 `host_id` 找到其当前直播（从而跟随主播）。
