# 平台规格：百度直播（baidulive）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`baidulive`，显示名“百度直播”。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/baidulive/`（A = baidu_live_api.dart，S = baidu_live_site.dart，L = baidu_live_link.dart）。样本编号见 §11。
- 状态：**保留**。2026-09-27 本机默认出口实测（2026-09-28 查明本机默认出口经系统层隧道在境外，不是中国大陆直连）：签名的频道推荐流、房间命令接口和各档 FLV/HLS 都能匿名访问。不满足 ADR 0003 的任何下线条件。
- 能力：目录（频道 → 推荐流，无限翻页）、推荐、详情、取流（原画 + 720p/480p，FLV 两个 CDN + HLS，AVC）、链接解析。
- 不提供：搜索（没有匿名搜索接口，旧版只接受房间号，S:190-206）；弹幕（本阶段未做，协议见 §7）；登录。

---

## 1. 房间身份与链接

**规范身份**：房间号 `room_id`，6–20 位数字（L:2）。百度的房间号**每场直播一个**：同一主播再开播是新房间号（流名 `stream_bduid_<主播>_<房间号>` 里两段分开）。收藏跟踪的是这一场，结束后为未开播。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯房间号 | `11560887291` | 直接使用 | L:14-15 |
| 房间页 | `https://live.baidu.com/m/room/<房间号>` | 路径三段 | L:25-27 |
| PC 播放页 | `https://live.baidu.com/m/media/pclive/pchome/live.html?room_id=<房间号>` | 取 `room_id` | L:31 |
| 分享页 | `https://live.baidu.com/m/media/multipage/liveshow/index/<短码>?room_id=<房间号>` | 取 `room_id`（房间命令的 `share_url` 就是这种形式） | L:32-36 |
| 分享文本 | 链接前后有文字 | 抽出第一个 URL | — |

- 旧版只接受 `https`（L:17-19）；v4 同时接受 `http`，因为主机和路径已经足够判定。
- 外部打开：`https://live.baidu.com/m/room/<房间号>`（L:4）。

## 2. 目录

### 2.1 频道

- 频道来自推荐流第一页响应的 `data.tab.items[]`：`type`、`name`、`channel_id`（S01-feed-rec-p1）。录到：推荐 `rec`/570、购物 574、财经 611、健康 612、教育 613、新闻 575、休闲 616（与旧版的写死列表一致，A:143-151）。
- v4：`categories()` 请求推荐流第一页，取出频道；`rec` 作为推荐，不作分区。只有一个一级分类（id `baidu`，名称“频道”）。
- 分区 id 写成 `<type>:<channel_id>`（如 `shopping:574`），请求时拆开；形状不对 → NotFound。

### 2.2 推荐流（推荐与分区共用）

- `POST https://tiebac.baidu.com/livefeed/feed`，表单：`appname=pclive`、`sid=`、`ua=320_480_pc_1.0_0`、`uid=<设备 id>`、`timestamp=<秒>`、`source=pclive`、`resource`（第一页 `banner,tab,feed`，之后 `feed`）、`scene=pc_channel`、`session_id`（第一页空）、`refresh_type`（第一页 0，之后 1）、`refresh_index`（第一页 1，之后上一页的值 + 1）、`tab`、`channel_id`、`sign`（A:254-274）。
- 签名：除 `sign` 外的字段按键名排序，拼成 `k=v&k=v`，后接 `&` 和网页常量 `CtmXzYPtdE58nCCcvqM0ectyqW3N5rfY`，取 md5（A:319-324）。
- 设备 id：`pc-` + 随机字母数字，每个适配器实例一个；旧版每次请求都新造（A:282）。
- 响应 `{errno: 0, data: {feed: {inner_errno: 0, session_id, refresh_index, items: [...]}, tab: {...}}}`（S01-feed-rec-p1）。`errno`/`inner_errno` 非 0 → ApiChanged。
- 翻页：推荐流是个性化的无限流。游标 = `<session_id>:<refresh_index>`；本页非空就给下一页游标（S01-feed-rec-p2：同一 `session_id`，`refresh_index` 为 2）。旧版“条数 ≥ 10”才继续（A:303）并在客户端去重（S:110）；v4 不做跨页去重，由界面层处理。
- 卡片：房间号 `room_id`；标题 `title`；昵称 `host.name`；头像 `host.avatar`；封面 `cover`；分区 `live_tag`，缺时 `left_label.text`；在线人数 `audience_count`（仅直播中）；状态 `live_status`：1 直播，0/2/3 未开播，其它跳过。

## 3. 搜索

不提供。

## 4. 房间详情

- `GET https://mbd.baidu.com/searchbox?cmd=371&action=star&service=bdbox&osname=pc&data=<JSON>&ua=360_740_ANDROID_0&bd_vid=&uid=<设备 id>&_=<毫秒>`；`data` 为 `{"data":{"room_id":"<房间号>","device_id":"<设备 id>","source_type":0},"replay_slice":0,"nid":"","schemeParams":{…,"shareTaskInfo":"{\"room_id\":\"<房间号>\"}",…}}`（A:276-316）。
- 响应 `{errno: "0", data: {"371": {...}}}`（S02-room-live）。`data.371 == null` → NotFound（S02-room-notfound）；`error_code` 1/4 → NotFound，其它非 0 → ApiChanged（A:344-347）。
- 状态 `status`：0 → 直播；-1、1（预告）→ 未开播；2、20 → 未开播；3（已结束，有 `replay_list`）→ 未开播（房间号就是这一场，结束了就不是“回放中的房间”，S02-room-ended）；其它 → ApiChanged。
- 字段：标题 `video.title`；昵称 `host.nick_name`（缺时 `host.name`）；头像 `host.image.image_33`；封面 `video.cover.cover_100`（缺时 `vertical_cover`）；分区 `category`；简介 `video.description`；在线人数 `online_users`（仅直播中）。
- 受限：`has_pay_service > 0` → 取流 NeedsLogin；`is_forbidden_url > 0` 或 `ban_status > 0` → 取流 StreamUnavailable（A:531-538）。
- 弹幕参数：`danmakuKeys = {roomId}`。

## 5. 画质与线路

| 画质 | 来源 | 说明 |
|---|---|---|
| `origin`“原画” | `video.avc_url`（缺时 `play_url`），不带 `-L` 后缀的流名 | 主播推流原样 |
| `720p`、`480p` | `video.url_list[]` 的 `resolution` | 每项 `urls[]` 是两个 CDN（`flv`/`flv2`、`hls`/`hls2`） |

- 顺序：原画在前，其余按分辨率从高到低。
- 每档线路：先 FLV（每个 CDN 一条），再 HLS；线路 id = `<格式>:<主机第一段>`（如 `flv:flv2`）。
- 地址都是 `http`：这些主机的 https 证书校验失败（2026-09-27 实测 `flv.liveshow.lss-user.baidubce.com` 证书链不完整），所以保留平台给的 `http`。
- 旧版只接受 `hls-live.bdstatic.com`、`flv-live.bdstatic.com` 和 `*.liveshow.bdstatic.com`（A:540-541），并且只从 `url_clarity_list` 取 `avc_flv`；现在 `url_clarity_list` 为空，地址都在 `lss-user.baidubce.com`，而 `live_flv_url`（`hls-live.bdstatic.com`）返回 403。旧版因此取不到可用地址。
- 编码：AVC（读取 FLV 头：video codec id 7）。服务端确认的画质：无。

## 6. 取流

- 取流时重新请求房间命令（§4），按 §4 的状态和受限规则报错，然后按 §5 组线路。
- 地址没有签名和过期参数，`lease` 为空。
- 请求头：UA、`Origin`/`Referer: https://live.baidu.com/`；实测不带也能拉。

## 7. 弹幕

本阶段未做（v4 缺口）。协议已查明，可以按 HTTP 轮询实现：

- 房间命令给出 `chat_msg_hls_url`（`http://liveshowstatic.baidu.com/v1/liveshowstatic/live_<房间号>.m3u8?authorization=bce-auth-v1/…`），另有 `host_msg_hls_url`、`reliable_msg_hls_url`；轮询间隔 `msg_hls_pull_internal_in_second`（5 秒）。
- 列表是 HLS 格式，每个分片是一个 JSON 文件（有时 gzip 压缩但不带 `Content-Encoding`）：`{list: [{messages: [{content: "{\"text\":\"<再编码的 JSON>\"}", ...}]}]}`。
- 内层 JSON：`message_type == "0"` 是聊天（`name`、`content`、`bd_uk`、`portrait`）；`type == 107` 是系统通知（如 `mix_room_close`）。
- 2026-09-27 观察 90 秒只有 1 条聊天（主播发的），量很小。

## 8. 登录与 Cookie

不支持。付费直播报 NeedsLogin。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| `errno`/`inner_errno` 非 0 | JSON | ApiChanged |
| 房间不存在 | `data.371 == null`，或 `error_code` 1/4 | NotFound |
| 未知 `status` | JSON | ApiChanged |
| 未开播、已结束 | `status` 非 0 | 房间 offline；取流 StreamUnavailable |
| 付费 | `has_pay_service > 0` | 取流 NeedsLogin |
| 封禁、禁止播放 | `ban_status`、`is_forbidden_url` | 取流 StreamUnavailable |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 在播房间没有可用地址 | 地址换到 `lss-user.baidubce.com`、`url_clarity_list` 为空，旧版主机白名单全部拒绝 | 用 `avc_url` 和 `url_list`，不做主机白名单 | A:540-541；S02-room-live |
| 已结束的房间仍给出地址 | `url_list` 在结束后仍保留旧地址 | 先看 `status`，不在播不组线路 | S02-room-ended |
| 推荐只翻一页 | 旧版按条数判断结束 | 推荐流非空就继续 | A:303 |

## 11. 样本清单

2026-09-27 本机默认出口录制（规则 tools/live_cli/lib/src/fixture/rules/baidulive.dart）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/baidulive_test.dart 直接对照正文。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-feed-rec-p1`、`-p2` | 推荐第 1 页（含频道列表）、同一会话第 2 页 |
| S01 | `S01-feed-shopping-p1` | 分区（购物） |
| S02 | `S02-room-live`、`-ended`、`-notfound` | 直播（原画/720p/480p）、已结束（`status 3`，残留地址）、不存在 |

**需要脱敏的字段**：房间命令的 `online_user_list`（观众的 uid、昵称、头像）换成假名；聊天列表地址的 BCE 签名 `authorization` 换成合成值。签名表单的 `sign` 由公开常量和时间戳算出，原样保留；设备 id 是录制脚本自造的。

## 12. 待确认

1. 弹幕实现（§7）及三种消息列表的区别。
2. 付费、封禁房间的真实样本。
3. `status` -1/1（预告）的样本。
4. 推荐流翻页的上限。
