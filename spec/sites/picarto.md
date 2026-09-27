# 平台规格：picarto（Picarto.TV）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`picarto`（legacy/lib/core/sites.dart:54），显示名 `Picarto`（legacy/lib/core/sites.dart:228）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/picarto/`（A = picarto_api.dart，H = picarto_hls.dart，S = picarto_site.dart），其它旧代码写全路径（相对 `legacy/`）。样本编号见 §11。
- 状态：**保留**。2026-09-27 实测：接口、媒体、弹幕在中国大陆直连和经代理都能匿名使用；有公开目录（约 60 个非成人直播，26 个分类）。不满足 ADR 0003 的下线条件。
- 能力：目录（分类 → 频道，推荐 = 全部直播按观众数）、搜索（频道资料，含未开播）、详情、取流（HLS，按主列表的变体给画质）、弹幕（匿名 JWT + JSON WebSocket）。
- 不提供：登录；私密频道（`private == true`，§9）；录像（`videos`）。
- 成人频道（`adult == true`）：目录和推荐按平台参数排除（A:262），直接通过链接或关注进入时照常播放（匿名可以播放，§6.4）。

---

## 1. 房间身份与链接

**规范身份**：频道名 `name`（字母、数字、下划线，1～50 字符；A:124-143）。大小写不敏感地查找，以接口返回的写法为准（`channel/detail/thebaker` 返回 `TheBaker`）。频道数字 id 只用于匹配多人同播里的自己那一路（§4）。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 频道名 | `allatir` | 直接作为名字 | — |
| 频道页 | `https://picarto.tv/allatir`、`https://www.picarto.tv/allatir/` | 路径恰好一段 | A:145-162 |
| 分享文本 | 链接前后夹有文字 | 抽出第一个 URL | — |

- 保留路径不是频道：`explore`、`search`、`settings`、`login`、`signup`、`register`、`password`、`terms`、`privacy`、`help`、`about`（A:127-139），v4 另加 `videos`、`communities`、`subscriptions`、`following`、`shop`、`commissions`。
- 频道不存在：`channel/detail` 返回 HTTP 200、`{"channel": null, …}`（S04-detail-notfound）→ NotFound。
- 外部打开：`https://picarto.tv/<name>`。

---

## 2. 目录

接口在 `https://ptvintern.picarto.tv/api/`。请求头见 §6.3。

### 2.1 分类

- GET `api/languages-categories`：`categories[]` 每项 `id`、`label`、`online_channels`（S01-categories：26 个，Furry、Creative、Adult …）；还有 `languages[]`，v4 不用。
- v4：一个 `Category`（id `category`，名称 `Picarto`），每个分类一个 `Area`，保持响应顺序（A:164-185）。旧版另有一个“公开目录”分区（S:124-142），v4 就是“推荐”。

### 2.2 分区房间与推荐

- GET `api/explore?first=30&page=<页>&filter_params[adult]=false&order_by[field]=viewers&order_by[order]=DESC&type=stream`；分区另加 `filter_params[languages]=` 和 `filter_params[categories]=<id>: true`（值就是“`8: true`”这样的字符串；A:258-270；S02-explore-category）。
- 分页（Laravel 风格）：`current_page`、`last_page`、`per_page`、`total`、`data[]`（S02-explore-p1：共 62 个、3 页）。页号达到 `last_page` 或本页为空即结束（S02-explore-last、S02-explore-beyond）。
- 条目：`name`、`title`、`online`、`viewers`（在线人数）、`adult`、`avatar`、`image_thumbnail`（封面）、`categories[]`（名称用 “ / ” 连接）、`stream_name`、`origin`（推流源的 IP，不用，样本里脱敏）。
- 只保留 `online == true`、`adult != true` 的条目，按名字（不区分大小写）去重（A:285-300）。

---

## 3. 搜索

- GET `api/search?first=20&page=<页>&q=<kw>&type=searchProfiles&tag_search=false`（A:187-236；S03-search）。
- `searchProfiles.data[]`：`id`、`name`、`avatar`、`online`、`follower_count`、`bio`。没有直播标题，标题用频道名。未开播也返回。
- `searchProfiles.count` 在各页不一致（A:187-188），不用；本页满 20 条就可能还有下一页，不满即结束（S03-search-empty：`count 0`、`data []`）。

---

## 4. 房间详情

- GET `api/channel/detail/<name>`（A:340-358）：
  - `channel`：`id`、`name`、`title`、`online`、`private`、`adult`、`avatar`、`viewers`、`total_views`（累计观看）、`categories[]`、`descriptions[]`（简介面板，`body` 含 HTML 实体）、`followers_count`。`null` → NotFound。
  - `getLoadBalancerUrl.origin`：负载均衡选的边缘节点，如 `edge1-eu-west`、`edge1-us-miami`（每次请求可能不同）。
  - `getMultiStreams.streams[]`：多人同播时一组频道各自的 `channelId`、`stream_name`（`golive+<name>`）、`online`、`adult`、`webrtc`。取 `channelId == channel.id` 的那一路（A:349-353）。
- 状态：`online == true` 直播中，否则未开播。
- 人数：`viewers` 在线（直播中时），`total_views` 累计。
- 简介：各面板 `body` 解码 HTML 实体后用空行连接。
- 弹幕参数：`channelName`、`channelId`。

---

## 5. 画质与线路

- 主列表：`https://<origin>.picarto.tv/stream/hls/<stream_name>/index.m3u8`（A:357）。`origin` 必须是小写字母数字加连字符，`stream_name` 只含 `[A-Za-z0-9_+-]`，否则 ApiChanged（A:346-355）。
- 2026-09-27 的主列表只有一个变体（S05-master：`1280x720`、60 fps、`avc1.640020`；成人频道 Rezenfurd 是 `1920x1080`、59.94 fps）。每个变体一个画质，标签 `<高>p <帧率>fps`，没有分辨率时 `HLS <码率> Mbps`（H:62-65）；按高度、带宽降序。
- 线路只有一条（选中画质的变体地址），线路身份是边缘节点主机名。确认画质 = 请求画质。
- 主列表没有变体（直接是媒体列表）时，画质“自动”，线路就是主列表地址（H:74-80 的“HLS Auto”）。
- 没有令牌，不需要租期；每次取流重新请求详情（边缘节点会变）。

---

## 6. 取流

### 6.1 流程

详情 → 未开播 StreamUnavailable → 主列表（404 → StreamUnavailable）→ 选变体。

### 6.2 租期

无（地址不带签名，没有到期时间）。

### 6.3 请求头

- `Referer: https://picarto.tv/`、`Origin: https://picarto.tv`、UA（A:31；legacy/lib/player/core/playback_header_resolver.dart 的 picarto 分支另加桌面 UA）。

### 6.4 媒体实况（2026-09-27）

- HLS 3，2 秒 TS 分片（`<开始>_<结束>.ts`），H.264 + AAC。没有 FLV，也就没有 codec 12（HEVC）问题。
- 成人频道的主列表匿名可取（Rezenfurd）。
- `live_cli probe picarto https://picarto.tv/allatir`：解析 → 详情（在线 48、累计 61071）→ 取流（720p 60fps）→ 读到 HLS 列表，通过（2026-09-27，直连）。

---

## 7. 弹幕

旧版没有 Picarto 弹幕（S:121-122）。以下来自官网脚本（`picarto.tv/static/js/main.*.js`）和 2026-09-27 实测。

### 7.1 连接

- 令牌：POST `https://ptvintern.picarto.tv/ptvapi`（GraphQL），`{"query":"query ($name: String) { generateJwtToken(channel_name: $name) { key } }","variables":{"name":"<频道>"}}`。匿名返回一个 JWT（载荷 `userId 0`、`channelId`、`channelName`），S06-chat-token。
- 连接：`wss://chat.picarto.tv/chat/token=<JWT>`（令牌在路径里）。握手请求头 `Origin: https://picarto.tv`、UA。不需要加入消息，连上即加入。
- 客户端**什么也不发**（网页只在私信时发消息），服务端靠 WebSocket 协议层的 ping 保活（dart:io 自动回应）。v4 不发应用层心跳。

### 7.2 消息（JSON 文本帧）

| 形式 | 含义 | 处理 |
|---|---|---|
| `{"t":"c","m":[…]}` | 聊天：每项 `c`（发言所在频道 id）、`u`（用户 id）、`n`（名字）、`m`（文本）、`id`（UUID）、`d`（毫秒）、`k`（名字颜色，十六进制）、`rn`（房间名）、`i`（头像路径） | 聊天，id `picarto:<id>`，颜色用 `k` |
| `{"type":"stream","messages":{…,"viewers":N,…}}` | 频道状态，约每 25～60 s 一次，多人同播时一次来几条 | 在线人数 |
| `{"t":"un",…}`、`{"t":"ur",…}` | 用户进入、离开 | 忽略 |

- 多人同播（multistream）时，同组各频道的聊天是同一个房间，`c` 可能是组里别的频道；网页也一起显示，v4 同样全部显示。
- 表情以 `:name:` 留在文本里。

### 7.3 静默判断与重连

- 共用 SocketConnector；没有心跳，只有静默看门狗：`stream` 更新间隔最长约 60 s，所以看门狗是 3 × 60 s = 180 s 没有任何消息才判定断线。重连时重新取 JWT。

---

## 8. 登录与 Cookie

- 不支持登录。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时、HTTP 5xx | A:84-91 | NetworkFailure |
| HTTP 429 / 401、403 / 404 | 同上 | RateLimited / RiskControl / NotFound |
| `channel: null` | S04-detail-notfound | NotFound |
| 直播中但没有负载均衡节点或自己的 `stream_name` | A:345-355 | ApiChanged |
| 私密频道 `private == true` | A:314 | 旧版报“无权访问”。v4 详情照常返回，取流时主列表若被拒则 RiskControl [待确认：没有找到私密频道样本] |
| 未开播时取流；主列表 404 | §6.1 | StreamUnavailable |
| 弹幕令牌取不到 | §7.1 | 弹幕报 `credentials` |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-PICARTO-001 | 多人同播时播成了别人的画面 | `getMultiStreams` 里有一组频道 | 按 `channelId == channel.id` 选自己那一路 | A:349-353 |
| REG-PICARTO-002 | 搜索翻页提前结束或空转 | `count` 不可靠 | 满页才继续 | A:187-188 |
| REG-PICARTO-003 | 播放地址过时 | 边缘节点由负载均衡按请求分配 | 每次取流重新请求详情 | §5 |

---

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/picarto.dart）。旧应用不能再运行（ADR 0016），没有 `expected.json`；v4 测试 packages/live_core/test/sites/picarto_test.dart 直接对照样本。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | `languages-categories` | `S01-categories` |
| S02 | `explore` | `S02-explore-p1`、`-last`（第 3 页）、`-beyond`（第 4 页，空）、`-category`（Furry） |
| S03 | `search` | `S03-search`（关键词 art，直播中和未开播）、`S03-search-empty` |
| S04 | `channel/detail` | `S04-detail-live`（多人同播）、`-offline`、`-notfound` |
| S05 | HLS 主列表 | `S05-master`（S04-detail-live 给的边缘节点） |
| S06 | 弹幕 JWT | `S06-chat-token` |
| S07 | 弹幕帧 | `fixtures/picarto/danmaku/S07-live`（`live_cli danmaku picarto --recommended --seconds 120 --record`：令牌、进入、状态更新、一条聊天） |

**缺**：私密频道；有多个变体的主列表。

**需要脱敏的字段**
- 目录条目的 `origin`（推流源 IP；按 JSON 路径 `$.data[*].origin`，保留详情里负载均衡的 `origin`）。
- 弹幕 JWT（令牌响应和握手路径）；弹幕里观众的 `u`、`n`、`i`。
- 频道公开信息（名字、标题、头像、简介、社交链接）保留。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 私密频道和 WebRTC 推流（`webrtc: true`）频道的播放表现 | 找对应频道 |
| 2 | 多变体主列表（转码档位）是否存在 | 观察高级账号频道 |
| 3 | 聊天服务器是否会因客户端不发消息而断开（实测 170 s 没断） | 更长的录制 |
