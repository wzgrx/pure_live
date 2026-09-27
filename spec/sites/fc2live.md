# 平台规格：FC2 ライブ（fc2live）

ADR 0003 的**候选下线**平台，第 7 阶段评估。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`fc2live`，显示名 `FC2ライブ`。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/fc2live/`（A = fc2_api.dart，C = fc2_control_session.dart，L = fc2_link.dart）。样本编号见 §11。

## 0. 去留评估（ADR 0003 下线标准）

2026-09-28 从中国大陆直连实测（不需要代理）：

| 标准 | 结论 | 证据 |
|---|---|---|
| 1. 取流成功率 < 50% | **不满足**：匿名拿到控制授权，控制连接打开期间 HLS 列表 200、分片可取；ffmpeg 连续播放高、低延迟两个变体各 30 秒成功；`live_cli probe` 成功 | S03-control；S04-control；§6 实测 |
| 2. 需要应用不支持的登录 | **不满足**：公开房间匿名可看；付费、登录限定、门票房间（目录 63 个里 7 个）报 NeedsLogin | S01-directory |
| 3. 没有公开目录且链接不稳定 | **不满足**：`allchannellist.php` 列出全部在播房间，网页的分类筛选就是在它上面过滤；`live.fc2.com/<频道号>/` 链接稳定 | S01-directory |

**结论：保留**，实现目录（按网页分类筛选）、详情、取流（控制连接租约）、链接、弹幕。旧版诊断以“分片签名绑定出口 IP、付费/登录房受限、需要自有输入”建议下线（docs/rewrite/diagnosis/01-sites.md）：付费房受限只影响少数房间；“自有输入”其实是控制连接要保持打开，v4 用租约表达（§6.3），不需要改写 HLS；IP 绑定见 §5。

- 能力：分类（一个分类、五个网页筛选分区）、推荐（全部在播房间，按在线人数排序，一页）、详情、取流（HLS，高/标准/低三档）、链接解析、弹幕（控制连接上的评论和人数）。
- 不提供：搜索（网页没有搜索接口，[待确认]）；成人区（`is_adult` 目录，需要年龄确认 Cookie，不做）；登录。

---

## 1. 房间身份与链接

- 房间 id = 频道号，`^[1-9]\d{0,11}$`（L:2）。

| 输入 | 处理 | 证据 |
|---|---|---|
| 纯频道号 | 直接使用 | L:15-17 |
| `https://live.fc2.com/<频道号>/` | 取频道号 | L:30 |
| `https://live.fc2.com/<语言>/<频道号>/`（语言：en es de fr id ja ko pt ru th tw vi zh） | 取频道号 | L:3,31-33 |
| 分享文本 | 抽出第一个 URL | — |

- 外部打开：`https://live.fc2.com/<频道号>/`。

## 2. 目录

- `POST https://live.fc2.com/contents/allchannellist.php`，空表单，请求头 `Origin`/`Referer: https://live.fc2.com/`、`X-Requested-With: XMLHttpRequest`（A:182-185）。
- 响应 `{"link":…,"is_adult":0,"time":<秒>,"channel":[…]}`；没有 `channel` 列表或 `time` → ApiChanged。
- 行：`type == 1`（公开房间；其它是聊天室、私密两人房）且 `pay == 0`、`login == 0`、`tid == 0`（不收费、不限登录、不要门票）才保留（A:219-232）。按 `id` 去重。
- 卡片：房间 id = `id`；主播 `name`；标题 `title`（空时用主播名）；封面 `image`；在线 `count`；累计 `total`；分区名由 `category` 查 §2 的表。
- 分类：一个分类“FC2ライブ”，分区即网页首页的筛选（首页脚本 `category_set: ['0','1','2,3','4','5','9']`，标签见页面）：

| 分区 id | 名称 | 保留的 `category` |
|---|---|---|
| `1` | 雑談 | 1 |
| `2,3` | ゲーム/作業 | 2、3 |
| `4` | 動画 | 4 |
| `9` | 音声 | 9 |
| `5` | その他 | 5 |

- 推荐 = 全部保留的行，分区 = 按 `category` 过滤；都按在线人数降序，只有一页（目录一次给全）。

## 3. 搜索

不提供（[待确认] 网页只有前端筛选）。

## 4. 房间详情

`POST https://live.fc2.com/api/memberApi.php`，表单 `channel=1&profile=1&user=1&streamid=<频道号>`（A:213-214）。
- `status != 1` → ApiChanged；`channel_data.channelid` 不等于请求的频道 → ApiChanged。
- **不存在的频道**也回 `status: 1`，但 `profile_data.userid` 为空字符串（S02-member-missing）→ NotFound。
- `channel_data.is_publish`：1 直播，0 未开播，其它 → ApiChanged（A:257）。
- 字段：主播 `profile_data.name`（缺时 `tname`）；标题 `channel_data.title`（空时用主播名）；封面 `image`；头像 `profile_data.image`/`icon`；简介 `info`；在线 `count`、累计 `total`（只在直播时）；`version` 留给 §6.1。
- 受限：`fee`、`login_only`、`ticketid`、`ticket_only`、`is_limited` 任一非 0（A:258-262）→ 详情照实，取流报 NeedsLogin。
- 弹幕参数：`danmakuKeys = {channelId}`。

## 5. 画质与线路

- 控制连接回答里的列表（§6.2）：`playlists`（低延迟，0.5 秒分片）、`playlists_middle_latency`、`playlists_high_latency`，每个有主列表（mode 0/2/1）和各档：10 低、20 标准、30 高、90（只在 `targets` 里出现，主列表不列）。高延迟一族 = 低延迟 mode + 1（11、21、31）。
- v4 提供三档：`30` 高画質、`20` 標準、`10` 低画質（id 用低延迟 mode）；每档取高延迟一族的列表（mode + 1），没有时退回低延迟。不提供主列表：ffmpeg 打开主列表会同时拉全部变体，实测 150 秒内播不出 30 秒；单个变体正常。
- 线路一条，id = 媒体主机（`us-west-1-media.live.fc2.com`）；编码 AVC（主列表 `CODECS="avc1…,mp4a.40.2"`）。
- 媒体请求头不是必须的（ffmpeg 不带任何头也能播）；v4 带 `Origin`/`Referer`/UA 与网页一致。
- 旧版诊断说分片签名绑定出口 IP（分片地址带 `time`、`hash`）。实测没有观察到：授权和控制连接走代理（美国出口），再分别用代理和直连（中国出口）取变体列表和全部分片，结果一样——列表 200，分片 200 与 403 交替（逐个顺序请求时，窗口两端的分片尚未生成或已过期，两种出口都如此）。v4 仍让接口、控制连接、媒体走同一平台路由（平台代理设置同时用于三者），避免依赖这个结论。

## 6. 取流

### 6.1 控制授权

`POST https://live.fc2.com/api/getControlServer.php`，表单 `channel_id=<频道号>&mode=play&orz=&channel_version=<§4 version>&client_version=2.1.0\n [1]&client_type=pc&client_app=browser_hls&ipv6=`（A:200-209）。
- `status != 0` → StreamUnavailable。
- `url`：`wss://<节点>.live.fc2.com/control/channels/<频道号>`（路径必须对应该频道，A:296-306）；`control_token`（JWT）；`orz_raw`（Cookie 值）。
- 先查 §4：未开播 → StreamUnavailable；受限 → NeedsLogin。

### 6.2 控制连接

- 连接 `<url>?control_token=<control_token>`，请求头 `Origin: https://live.fc2.com`、`Cookie: l_ortkn=<orz_raw>`（C:60-64）。
- 服务器先发 `initial_connect`、`connect_complete`；收到 `connect_complete` 后发 `{"name":"get_hls_information","arguments":{},"id":1}`；回答 `{"name":"_response_","id":1,"arguments":{"status":0,"playlists":[{mode,status,url}…],…}}`（C:88-97，S04-control）。`arguments.status != 0` → StreamUnavailable；列表里 `status != 0` 的项跳过；一个都没有 → ApiChanged。
- 其它消息：`connect_data`、`user_count`（在线/累计，增量更新，只带变化的字段）、`video_information`、`point_information`、`ng_comment`、`comment`（§7）。`control_disconnection`（`code: 4500` = 授权过期）→ 连接结束。
- 授权可在一分钟内重复连接；约 60 秒后再用同一个 `control_token` 连接，服务器只回 `control_disconnection` 4500（实测）。
- 保活：WebSocket ping 每 15 秒（C:150）；`heartbeat` 命令（§7.2）服务器也回应，取流不依赖它（实测保持 120 秒只有 ping 不断开）。

### 6.3 控制连接租约（播放器/中继需要知道的）

实测（2026-09-28，频道 62996200）：
- 控制连接打开时第一次请求变体列表 → 200；**连接在第一次请求前就关闭** → 变体列表一直 403（关闭后 40 秒内每 5 秒一次都是 403）。主列表不受影响。
- 连接打开期间第一次请求过的列表，连接关闭后 133 秒内仍然 200（没测更久）。

所以 v4 让控制连接在播放期间一直打开：`streams` 打开连接并返回带租约的线路（`refreshAt` = 60 秒后，`expiresAt` = 150 秒后，`cutsConnection = false`）；同一频道再次 `streams`（播放会话在 `refreshAt` 预取）复用已打开的连接并把保持时间延长到 150 秒；租约没续上就关闭连接。与 niconico 的座位租约相同（spec/sites/niconico.md §6.4）。播放器和中继不需要做别的：不改写 HLS，不需要特殊 Cookie，只要按租约预取。

## 7. 弹幕

走同一种控制连接，但弹幕连接器自己取授权、自己保持连接（与取流的连接无关）。

### 7.1 连接

每次开始和每次“授权过期”后重新走 §6.1（`controlGrant`）；握手同 §6.2。收到 `connect_complete` 算加入。加入前后收到 `control_disconnection` 都当作授权失效，重新取授权。开始时未开播 → 结束，原因 `offline`；频道不存在 → `noRoom`；受限 → `credentials`。

### 7.2 心跳

`{"name":"heartbeat","arguments":{},"id":<递增>}`，每 30 秒一次；服务器回 `{"name":"_response_","id":<同>,"arguments":{"status":0}}`（S06-live）。服务器也接受**二进制帧**里的同样 JSON（实测），所以连接器用现有的二进制发送接口。

### 7.3 消息

- `comment`：`arguments.comments[]`，每条 `user_name`（匿名是 `[anonymous]`）、`comment`、`color`（颜色名）、`size`、`timestamp`（毫秒）、`encrypted_user_id`、`hash`、`history`。加入时服务器先推最近 30 条，`history: 1`，不发出（避免旧弹幕刷屏）。消息 id = `fc2live:<hash>`；用户 id = `encrypted_user_id`；发送时间 = `timestamp`。颜色：`black`（网页默认）按弹幕默认色，`red`、`blue` 等按常规 RGB，[待确认] 网页的完整颜色表。
- `user_count`：`pc_user_count + mobile_user_count` 是在线，`pc_total_count + mobile_total_count` 是累计；消息只带变化的字段，要保留上一次的值再相加。
- 不解码：`ng_comment`（管理员屏蔽词表）、`point_information`、`video_information`、礼物（[待确认] 礼物消息名）。

## 8. 登录与 Cookie

不支持账号。`l_ortkn` Cookie 由授权给出，只用于控制连接。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| 频道不存在 | `profile_data.userid` 为空 | NotFound |
| 未开播 | `is_publish == 0` | 详情照实；取流 StreamUnavailable |
| 付费、登录限定、门票 | §4 受限字段 | 取流 NeedsLogin |
| 授权失败 | `status != 0` | StreamUnavailable |
| 控制连接没在 20 秒内给出列表 / 断开 | — | NetworkFailure |
| 形状不符 | JSON | ApiChanged |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 拿到主列表但变体 403 | 控制连接在第一次请求变体前就关了 | 播放期间保持控制连接（§6.3） | 实测 |
| 重连后立即被断开 | 授权约 60 秒后失效（4500） | 重连前重新取授权 | 实测 |
| ffmpeg 播主列表卡住 | 同时拉全部变体 | 按档提供变体列表 | 实测 |
| 旧弹幕刷屏 | 加入时推送 30 条历史 | 丢弃 `history: 1` | S06-live |

## 11. 样本清单

2026-09-28 直连录制（规则 tools/live_cli/lib/src/fixture/rules/fc2live.dart；控制连接帧由迁移会话的录制脚本写出，格式与 `live_cli danmaku --record` 相同；弹幕用 `live_cli danmaku fc2live --recommended --pick 1 --seconds 120 --record S06-live`，录下后把用例名从 S06-live-b 改回 S06-live）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/fc2live_test.dart、packages/live_danmaku/test/fc2live_test.dart 直接对照正文。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-directory` | 全部在播房间（63 个，7 个受限） |
| S02 | `S02-member-live`、`S02-member-missing` | 在播频道；不存在的频道 |
| S03 | `S03-control` | 控制授权 |
| S04 | `control/S04-control` | 控制连接：加入、列表回答、人数、评论历史（截到 3 条，屏蔽词表帧删去） |
| S05 | `S05-master` | 低延迟主列表（三个变体） |
| S06 | `danmaku/S06-live` | 弹幕连接（频道 29745829，120 秒）：授权、4 次心跳、30 条历史评论（丢弃）、20 条新评论、人数 |

**需要脱敏的字段**：`control_token`、`orz`、`orz_raw`（授权和握手 Cookie）、媒体地址的 `c`、`d`、分片的 `hash`；评论的 `encrypted_user_id`、`orz_token`、`hash`、非匿名的 `user_name`。频道的公开信息保留。

## 12. 待确认

1. 分片签名在更长时间、换节点后是否绑定出口 IP（§5，单次实测未绑定）。
2. 网页评论颜色表和礼物消息。
3. 成人区是否要支持。
4. 控制连接关闭后已开始的播放能维持多久（实测 133 秒内正常）。
