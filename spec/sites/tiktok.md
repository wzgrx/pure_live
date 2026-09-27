# 平台规格：TikTok LIVE（tiktok）

ADR 0003 的**候选下线**平台，第 7 阶段评估。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`tiktok`，显示名 `TikTok`。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/tiktok/`（A = tiktok_api.dart，L = tiktok_link.dart）。样本编号见 §11。

## 0. 去留评估（ADR 0003 下线标准）

2026-09-28 实测（Clash 代理出口；本机默认出口也经系统层隧道在境外，中国大陆真实直连没有测，按常识需要给 `tiktok` 配代理）：

| 标准 | 结论 | 证据 |
|---|---|---|
| 1. 取流成功率 < 50% | **不满足**：在播用户（`@qvc`）的匿名回答里有 FLV 和 HLS 地址；ffmpeg 播放 10 秒：FLV 经代理、经默认出口各一次成功，HLS 经代理成功；`live_cli probe` 成功 | S01-user-live |
| 2. 需要应用不支持的登录 | **不满足**：公开直播匿名可看；订阅者专享、付费直播报 NeedsLogin | S01-user-live |
| 3. 没有公开目录**且**链接不稳定 | **不满足**：确实没有匿名目录（下方实测），但链接是 `@用户名`，长期稳定 | 实测 |

匿名目录实测（均经代理，不带签名）：
- `webcast.tiktok.com/webcast/feed/?…`、`webcast.us.tiktok.com/webcast/feed/?…`：200，空正文；
- `www.tiktok.com/api/live/discover/get/?…`：`status_msg: url doesn't match`（缺 X-Bogus 等签名）；
- `webcast.tiktok.com/webcast/room/recommend/?…`：`Url does not match`；
- `www.tiktok.com/api/search/live/full/?…`：`Please login your account first`；
- `www.tiktok.com/live` 页面的 SSR 数据里没有房间（由前端带签名请求加载）。

**结论：保留，按“仅链接”实现**（和小红书一样）：详情、取流、链接解析。不做目录和搜索（需要逆向签名或登录，维护成本不值）；弹幕见 §7。旧版诊断以“0 测试、没有公开目录、只能靠链接导入”建议下线（docs/rewrite/diagnosis/01-sites.md），第 3 条标准要求“没有目录**且**链接不稳定”两者同时成立，TikTok 只占前一半。

---

## 1. 房间身份与链接

- 房间 id = 用户名（`uniqueId`，小写），形状 `^[a-z0-9_](?:[a-z0-9._]{0,22}[a-z0-9_])?$`（L:49-52）。直播间号（`roomId`，15–25 位数字）每场直播都变，只用于分享链接的解析，不当房间 id。

| 输入 | 处理 | 证据 |
|---|---|---|
| `@用户名` | 直接使用（转小写）；不带 `@` 的单词不认（会和别的平台冲突；旧版会认，L:35-41） | L:35-41 |
| `https://www.tiktok.com/@<用户名>`、`/@<用户名>/live`（也收 `tiktok.com`、`m.tiktok.com`） | 取用户名；`/@<用户名>/video/…` 不是直播链接，不认 | L:20-27 |
| `https://www.tiktok.com/share/live/<直播间号>` | `GET https://webcast.tiktok.com/webcast/room/info/?aid=1988&room_id=<号>` → `data.owner.display_id`（S02-room-live） | L:28-31；A:287 |
| `https://vm.tiktok.com/<码>/`、`https://vt.tiktok.com/<码>/`、`https://www.tiktok.com/t/<码>` | 不跟随重定向请求一次，取 `Location`，目标必须还在 tiktok.com，再按上面解析（[待确认] 没有录到真实短链样本，测试用桩） | L:65-68；legacy/lib/common/utils/live_url_tool.dart:264-277 |
| 分享文本 | 抽出第一个 URL | — |

- 外部打开：`https://www.tiktok.com/@<用户名>/live`。

## 2. 目录

不提供（§0）。

## 3. 搜索

不提供（需要登录，§0）。

## 4. 房间详情

`GET https://www.tiktok.com/api-live/user/room/?aid=1988&sourceType=54&staleTime=600000&uniqueId=<用户名>`，请求头 `Referer: https://www.tiktok.com/@<用户名>/live`、`Origin`、UA（A:223-224）。
- `statusCode`：`0` 正常；`19881007`（`user_not_found`）→ NotFound（S01-user-missing）；其它 → ApiChanged。
- `data.user.uniqueId` 必须等于请求的用户名（不区分大小写），否则 ApiChanged。
- 状态：`data.liveRoom.status`（数字）：`2` 直播，`4` 未开播（S01-user-offline），其它 → ApiChanged（[待确认] 是否有“暂停”等值）。
- 字段：主播 `user.nickname`；标题 `liveRoom.title`（未开播时是上一场的标题，照实显示）；封面 `liveRoom.coverUrl`；头像 `user.avatarLarger`；简介 `user.signature`；在线 `liveRoom.liveRoomStats.userCount`、累计进入 `enterCount`（只在直播时）。
- 受限：`liveRoom.liveSubOnly == 1`（订阅者专享）或 `paidEvent.paid_type != 0`（付费）→ 取流 NeedsLogin。
- 弹幕参数：`danmakuKeys = {roomId, uniqueId}`。

## 5. 画质与线路

- `liveRoom.streamData.pull_data.stream_data` 是**字符串里的 JSON**：`{"common":…,"data":{"<sdk_key>":{"main":{"flv":…,"hls":…,"sdk_params":"<JSON 字符串>"}}}}`。`sdk_key` 实测有 `hd`、`ao`（只有声音）；[待确认] 其它直播间的 `origin`/`uhd`/`sd`/`ld`。
- 画质：`pull_data.options.qualities[]` 的 `name`（`720p`）和 `level` 给名称和排序；`ao` 不提供；没列在 options 里的键用键名、按 origin > uhd > hd > sd > ld > md 排。
- 线路：每档两条，先 FLV（`lineId = flv`）后 HLS（`lineId = hls`）。编码取 `sdk_params.VCodec`：`h264` → AVC，`h265`/`bytevc1` → HEVC。`hevcStreamData` 另有一套 HEVC 地址，本阶段不用。
- 租约：地址带 `expire=<秒>`（签发后约 14 天）和 `sign`；`expiresAt = expire`，提前 1 小时刷新，`cutsConnection = false`。
- 媒体请求头：`Referer: https://www.tiktok.com/@<用户名>/live`、UA（ffmpeg 只带 UA 也能播）。

## 6. 取流

每次重新请求 §4；未开播 → StreamUnavailable；受限 → NeedsLogin；没有画质或地址 → StreamUnavailable。

## 7. 弹幕

本阶段未做（缺口）。网页评论走 `webcast/im/fetch` 轮询（protobuf）和 WebSocket，两者都要求 X-Bogus 等签名参数和 `msToken`，与目录同样的签名问题；[待确认] 有无免签名的匿名入口。

## 8. 登录与 Cookie

不支持账号，不带 Cookie。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| 用户不存在 | `statusCode 19881007` | NotFound |
| 分享链接的直播间不存在 | `room/info` 没有 `data` 或 `status_code != 0` | NotFound |
| 未开播 | `status 4` | 详情照实；取流 StreamUnavailable |
| 订阅者专享、付费 | §4 | 取流 NeedsLogin |
| 形状不符 | JSON | ApiChanged |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 评估时找不到在播房间 | 没有匿名目录；新闻、体育账号大多不在播 | 用常驻直播的账号（购物频道 `@qvc`）实测 | 实测 |
| 取流字段解析失败 | `stream_data` 和 `sdk_params` 是字符串里的 JSON | 两层解码 | S01-user-live |

## 11. 样本清单

2026-09-28 经代理录制（规则 tools/live_cli/lib/src/fixture/rules/tiktok.dart；录制脚本另外把 `stream_data` 字符串里的 `sign=` 换成同形值并记入 meta.json）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/tiktok_test.dart 直接对照正文。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-user-live`、`-offline`、`-missing` | 在播（`@qvc`）、未开播（`@cnn`）、不存在（`@nasa`） |
| S02 | `S02-room-live` | 直播间号 → 主播（分享链接） |

**需要脱敏的字段**：媒体地址的 `sign`（含 `stream_data` 字符串内）、图片地址的 `x-signature`、`push_urls`/`complete_push_urls`（主播推流地址，实测为空，防御性脱敏）、Set-Cookie。用户和直播间的公开信息保留。

## 12. 待确认

1. `status` 的其它取值。
2. 其它 `sdk_key` 与 HEVC 线路。
3. 短链接的真实重定向形状。
4. 免签名的评论入口。
5. 中国大陆直连是否完全不可用（估计需要代理）。
