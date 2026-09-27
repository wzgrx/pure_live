# 平台规格：Steam 直播（steambroadcast）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`steambroadcast`，显示名“Steam 直播”。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/steambroadcast/`（A = steam_broadcast_api.dart，S = steam_broadcast_site.dart，L = steam_broadcast_link.dart）。样本编号见 §11。
- 状态：**保留**。2026-09-27 直连（中国大陆）实测：热门直播页、广播信息、迷你资料、HLS 主播放列表和分片、聊天日志都能匿名访问。不满足 ADR 0003 的任何下线条件。
- 能力：推荐（热门直播，分页）、详情、取流（HLS 主播放列表，AVC）、弹幕（聊天日志 HTTP 轮询，只读）、链接解析。
- 不提供：分类（按游戏的直播在各游戏社区页，匿名接口未确认，[待确认]）；搜索（没有匿名直播搜索）；发送弹幕、登录。

---

## 1. 房间身份与链接

**规范身份**：主播的 64 位 Steam id（`7656119` 开头的 17 位数字，L:2）。一个主播一个房间，直播 id（`broadcastid`）每场变化，不作身份。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯 id | `76561199485215572` | 直接使用 | L:15-16 |
| 直播页 | `https://steamcommunity.com/broadcast/watch/<id>` | 主机必须是 `steamcommunity.com`，路径三段 | L:17-31 |
| 个人资料页 | `https://steamcommunity.com/profiles/<id>` | 取 id（v4 新增：分享主播时常用资料页） | — |
| 分享文本 | 链接前后有文字 | 抽出第一个 URL | — |

- 自定义地址 `steamcommunity.com/id/<名字>` 需要额外请求才能换成 id，v4 暂不支持，返回“不是本平台的房间”[待确认是否需要]。
- 外部打开：`https://steamcommunity.com/broadcast/watch/<id>`（L:4）。

## 2. 目录

### 2.1 分类

没有。`categories()` 返回空列表。

### 2.2 推荐（热门直播）

- `GET https://steamcommunity.com/apps/allcontenthome?l=english&browsefilter=trend&appHubSubSection=13&forceanon=1&p=<n>&broadcastsoffset=<(n-1)*10>&numperpage=10`，请求头 `X-Requested-With: XMLHttpRequest`、`Referer: https://steamcommunity.com/?subsection=broadcasts`（A:188-203）。
- 响应是 HTML 片段，每个直播一个 `Broadcast_Card`（S01-directory-p1、-p2，各 10 张）。v4 不引入 HTML 解析库，按下列标记用正则取值：

| 目标 | 标记 |
|---|---|
| 房间 id | `href="https://steamcommunity.com/broadcast/watch/<id>"` |
| 标题 | `apphub_CardContentType` 的文本，去掉结尾的 `: Broadcast`（即游戏名；列表没有直播标题） |
| 分区 | `apphub_CardContentTitle` 的文本（游戏名） |
| 在线人数 | `apphub_CardContentViewers` 的 `4,927 viewers` |
| 封面 | `apphub_CardContentPreviewImage` 的 `src`（`steambroadcast.akamaized.net/.../thumbnail/`） |
| 主播名 | `apphub_CardContentAuthorName` 里的文本 |
| 头像 | `appHubIconHolder` 里 `img` 的 `src` |

- 状态：列表只有直播中。
- 翻页：页尾隐藏表单的 `p == n+1` 且 `broadcastsoffset == n*10`，并且本页有卡片时还有下一页（A:250-257）。
- 旧版只接受 `avatars.akamai.steamstatic.com` 的头像（A:436-446）；现在头像在 `avatars.fastly.steamstatic.com`，旧版因此丢了所有头像。v4 不做主机白名单。

## 3. 搜索

不提供。

## 4. 房间详情

两个 JSON 接口，都带 `Referer: <直播页>`：

### 4.1 广播信息

- `GET https://steamcommunity.com/broadcast/getbroadcastinfo/?steamid=<id>&broadcastid=0&location=5`（v4 新用；旧版读直播页 HTML 再调 `getbroadcastmpd`，A:205-230）。
- 在播：`{success: 1, appid, app_title, title, viewer_count, thumbnail_url, is_online: true, is_replay: 0, ...}`（S02-info-live）。
- 不在播：`{success: 42}`（S02-info-offline）。
- 映射：`success == 42` 或 `is_online != true` → 未开播；`is_replay == 1` → 回放；否则直播。`success` 为其它值 → ApiChanged。
- 标题 `title`，为空时用 `app_title`（录到的直播标题都是空的）；分区 `app_title`；封面 `thumbnail_url`；在线人数 `viewer_count`（未开播为空）。

### 4.2 迷你资料

- `GET https://steamcommunity.com/miniprofile/<账号 id>/json`，账号 id = Steam id − 76561197960265728（S03-profile）。
- `persona_name` → 主播名，`avatar_url` → 头像。
- 不带 `Referer` 时曾被 Akamai 返回 403 拒绝页（2026-09-27 实测一次），所以带上直播页 Referer；403 报 RiskControl。

- 弹幕参数：`danmakuKeys = {steamid}`；直播 id 由弹幕连接自己取（§7），换场不失效。

## 5. 画质与线路

- 只有一档 `auto`“自动”：交给播放器的 HLS 主播放列表。主列表里有 720p（6 Mbps）、480p、360p 三个变体，音频单独一路（2026-09-27 实测，CODECS `avc1`、`mp4a`）。
- 线路：一条，id `steamcontent`；主机按调度变化（`cache8-lax1`、`cache15-lax2`），不作为线路身份。
- 编码：AVC。
- 不按变体拆画质 [待确认]：需要多一次请求主列表；在确认用户需要前交给播放器自适应。

## 6. 取流

- `GET https://steamcommunity.com/broadcast/getbroadcastmpd/?broadcastid=0&steamid=<id>&viewertoken=0&sessionid=`（A:210-212）。
- `success`：`ready` → 取 `hls_url`，有 `cdn_auth_url_parameters` 时去掉开头的 `&`/`?` 接到查询串后（A:387-411）；`unavailable`、`offline`、`not_live`、`no_broadcast`、`waiting`、`waiting_to_start` → StreamUnavailable；`user_restricted` → NeedsLogin；其它 → ApiChanged。
- 响应里的 `viewertoken` 是本次观看的令牌，播放不需要带（S04-mpd-live）。
- 心跳：响应给出 `heartbeat_interval: 30`，网页播放器会上报心跳。实测不发心跳，同一个主列表在 6 分钟后仍能拉到新分片（2026-09-27），所以 v4 不发心跳，也不设租期。
- 媒体请求头：UA、`Origin: https://steamcommunity.com`、`Referer: <直播页>`（A:111-115）；实测不带也能拉。

## 7. 弹幕

旧版未接入。v4 按网页 `broadcast_chat.js` 的读法做只读弹幕（HTTP 轮询，不需要登录）：

1. `getbroadcastmpd` 取当前 `broadcastid`（不在播就结束，状态 `closed offline`）。
2. `GET https://steamcommunity.com/broadcast/getchatinfo/?steamid=<id>&broadcastid=<bid>&viewertoken=0&sessionid=` → `view_url_template`，形如 `https://steambroadcastchat.akamaized.net/chat/<chat_id>/messages/{0}?chat_origin=...`。`broadcastid=0` 返回 HTTP 500 `{"success":2}`，必须用真实 id。
3. 请求 `{0} = 0`：返回最近 50 条历史、`next_request`（聊天日志的时刻，毫秒）和 `initial_delay`（毫秒）。**历史不发出**（旧消息没有时间戳，放到屏幕上会误导），只用来对时。
4. 之后按日志时钟读下一个时间窗：第一窗在收到后 `initial_delay` 时请求；之后每窗的请求时刻 = 第一窗时刻 + (`next_request` − 第一窗的 `next_request`)，大约每 0.5 秒一次。每次响应给出本窗的 `messages` 和下一窗的 `next_request`。响应再带 `initial_delay` 时重新对时。
   - 早期实现按固定 3 秒请求下一窗，日志时间每次只前进约 0.5 秒，越读越落后，约 70 秒后旧窗过期、返回 404（S07-live 录制前的实测）。
5. 失败：等 500 ms 重试，每次失败把时刻往后推 10 ms；连续 4 次失败从第 3 步重新对时；连续 12 次失败进入终态。都来自网页脚本的常量（`s_MessageRetryMax = 4`、`s_MessageRetryDelay = 500`、`s_MessageNudgeDelayMS = 10`），终态次数是 v4 的约定。

消息字段：`steamid`、`persona_name`、`instance_id`、`in_game`、`flair`、`msg`。只解 `msg` 非空的聊天行；消息没有 id 和时间戳，v4 的 id = `steambroadcast:<窗口时刻>:<窗口内序号>`。表情是 `ː名字ː` 文本，原样保留。`joined`、`left`、`muted`、`remove_msgs` 不解。

Steam 直播的聊天很少：2026-09-27 对热门页前 10 个直播各观察 60 秒，只有一个直播出现 3 条新消息。

## 8. 登录与 Cookie

不支持。`user_restricted` 报 NeedsLogin。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403（Akamai 拒绝页） | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| 广播信息 `success` 不是 1/42 | JSON | ApiChanged |
| `getbroadcastmpd` 未知 `success` | JSON | ApiChanged |
| 不在播 | `success` 42 / `unavailable` 等 | 房间 offline；取流 StreamUnavailable |
| 受限 | `user_restricted` | 取流 NeedsLogin |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 目录没有头像 | 头像换到 fastly 主机，旧版白名单只认 akamai | 不做主机白名单 | A:436-446；S01-directory-p1 |
| 聊天越读越落后，最后 404 | 按固定间隔请求，没有跟着日志时钟 | 照网页脚本按 `next_request` 对时 | §7 |

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/steambroadcast.dart）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/steambroadcast_test.dart 和 packages/live_danmaku/test/steambroadcast_test.dart 直接对照正文。

| # | 样本 | 请求 | 覆盖 |
|---|---|---|---|
| S01 | `S01-directory-p1`、`-p2` | 热门直播 HTML | 卡片、人数、翻页表单 |
| S02 | `S02-info-live`、`-offline` | `getbroadcastinfo` | 在播、`success: 42` |
| S03 | `S03-profile` | 迷你资料 | 主播名、头像 |
| S04 | `S04-mpd-live`、`-offline` | `getbroadcastmpd` | `hls_url`、`unavailable` |
| S07 | `danmaku/S07-live` | 聊天：manifest → chat info → 窗口 0（50 条历史）→ 约 140 个时间窗 | 对时、窗口衔接；录制期间没有新消息，解码由单元测试覆盖 |

**需要脱敏的字段**：`getbroadcastmpd` 的 `viewertoken`（本次观看的令牌）；弹幕帧里观众的 `steamid`、`persona_name`、`instance_id` 和版主 id（`moderators_steamid`）换成同形合成值，聊天文本保留。主播公开信息保留。

## 12. 待确认

1. 按游戏浏览直播的匿名接口（可作为分类）。
2. `steamcommunity.com/id/<名字>` 自定义地址是否需要支持。
3. 是否按主列表变体提供可选画质。
4. 聊天有新消息时的完整样本（录制期间聊天为空）。
5. `is_replay == 1` 的真实样本。
