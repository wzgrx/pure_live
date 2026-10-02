# T02c.16 Kick（恢复）

- 日期：2026-10-01
- 目标：`packages/live_core/lib/src/sites/kick/`（`kick_api.dart` 纯解析，`kick_site.dart` 请求编排）
- 升级条目：UPGRADES X-1“恢复 Kick”（先在 Android 恢复，Windows 等 WinHTTP 通道）。
- 参考：
  - pure_live_TV `lib/platforms/kick/`（e1cca224 加回，本地副本到 b9d2f73）：`KickApi`（接口、身份校验、图片和媒体主机白名单）、`KickHls`（主播放列表）、`KickLink`（链接和保留路径）、`KickSite`（目录分页、详情、恢复）；
  - v3 在 3.2.11 下线了 Kick（Cloudflare 拦 dart:io），3.x 源码里只剩 `SiteIds.retired` 和平台版本表的第 17 版（`kick`），没有可运行的适配器，也没有 `expected.json`；
  - v3 的审计记录 `legacy/docs/KICK_PUBLIC_CHAT_AUDIT_2026_09_23.md`（聊天房间 id 与频道 id 不同、只读 Pusher）。
- 样本：`fixtures/kick`，18 个接口样本 + 2 段弹幕录制（T06a.31），2026-10-01 匿名只读录制。

## 实测（2026-10-01，联网合计约 8 分钟）

| 请求 | dart:io | curl / 浏览器 | 说明 |
|---|---|---|---|
| `kick.com/api/v2/channels/<slug>`、`/api/v1/*`、`/api/search`、`/stream/livestreams/*` | **403** `{"error": "Request blocked by security policy."}` | 200 | Cloudflare 按 TLS 指纹拦 dart:io，带浏览器请求头也一样；`web.kick.com` 同样被拦 |
| IVS 主播放列表 `*.playback.live-video.net/...m3u8?token=…` | 200 | 200 | 不在 Kick 的 Cloudflare 后面，带令牌即可 |
| 图片 `files.kick.com`、`images.kick.com`、`stream.kick.com` | 200 | 200 | 播放器、图片加载不受影响 |
| Pusher `wss://ws-us2.pusher.com/app/32cbd69e4b950bf97679` | 101 | — | 聊天走 dart:io 正常（T06a.31） |

所以：**Android 上 kick.com 的请求走系统 TLS（`AndroidNativeHttp`），主播放列表和图片走 dart:io；Windows 没有可用通道，暂不登记 Kick**（等 WinHTTP，X-1 余项）。

能用（Android）：推荐、分区（6 个大类 × 各自观看最多的 32 个小分类）、分区房间、搜索、详情、画质和线路、恢复、链接识别、聊天。受限：没有。没有验证：主播放列表令牌过期后变体地址还能用多久（录制时 xQc 很快下播）；Kicks 打赏的事件形状（T06a.31）。

## 做法

照 T02a.1 哔哩哔哩：解析写成纯函数，请求编排单独一层。没有 v3 输出可对照，用录制样本逐项断言。

- **两个传输**：`KickSite(http, apiHttp: …)`。kick.com 的接口走 `apiHttp`（应用在 Android 传入 `AndroidNativeHttp`），主播放列表走 `http`。上游在 `KickApi._defaultRequest` 里按主机切换原生通道，这里由应用注入，平台层不依赖 Flutter。
- **请求头**：照上游，桌面 Chrome 140 UA、`accept: application/json, text/plain, */*`、`accept-language: en-US`、`origin`/`referer` 为 kick.com。媒体请求头 `mediaHeaders(slug)`：UA、`origin: https://kick.com`、`referer: https://kick.com/<slug>/`（IVS 令牌的 `aws:access-control-allow-origin` 列的是 kick.com），放进线路和房间的 `httpHeaders`。
- **房间身份**：频道 slug，小写（上游 `KickLink.normalize`）。Kick 的页面和接口不分大小写，`SiteIds.caseInsensitiveRoomIds` 加上 `kick`，3.x 存的关注不论大小写都能对上。保留路径（`categories`、`search`、`browse`……）不是房间。
- **分类**（比上游多）：上游只有一个“公开直播目录”。这里先取 `api/v1/categories`（游戏、生活、音乐、博彩、创作、其他，中文名），再同时取每个大类观看最多的 32 个小分类（`api/v1/subcategories?category=<slug>&limit=32`，接口一页最多 32），共 7 个请求；某个大类失败就略过，全部失败才报错。小分类是 `areaType: subcategory`，`areaId` 是 slug，图是分类横幅。
- **列表**：`stream/livestreams/en?page=&limit=30&sort=desc[&subcategory=<slug>]`。`sort=desc` 按观看人数排（上游没带，结果是无序的，第一个可能是 0 人的直播）；路径里的 `en` 不过滤语言。Kick 不认识的小分类会被忽略、返回全站列表（实测），所以只留属于该小分类的行，一行都不属于时报 `NotFound`。
- **搜索**：`api/search?searched_word=`，只有一页。先列频道（按粉丝数，开播和未开播都有，Kick 自己的排序），再补标签命中、频道不在前面的直播。关键词截到 50 字（上游）。
- **详情**：`api/v2/channels/<slug>`。开播时取 `playback_url`（带 JWT 令牌的 IVS 主播放列表），进房再请求它得到画质；关注刷新只读频道一次。404 是 `NotFound`；回答的 slug 和请求的不同是 `ApiChanged`（上游的身份校验）。封禁是 `LiveStatus.banned`。
- **画质**：解析主播放列表，名称用视频渲染组的 `NAME`（`1080p60`、`720p60`、`480p`、`360p`、`160p`，和 Kick 播放器一致；源画质的组叫 `chunked`，名字仍是 `1080p60`），没有时用“高度 + 帧率”。id 就是名称，恢复时新的主播放列表按名称找回同一档；找不到用最高档。线路是变体地址，HLS，编码取 `CODECS`。
- **租期**：主播放列表的令牌约 5～10 分钟过期（JWT `exp`，记在 `KickRoomData.tokenExpiresAt`），变体地址不带它，照 Twitch 的做法不设租期；断流恢复时重新读频道和主播放列表。
- **聊天参数**：进房时从频道回答取 `KickDanmakuArgs(chatroomId, channelId, slug)`，不多发请求（上游在弹幕连接里再请求一次频道）。聊天房间 id 和频道 id 不同（`xqcisoffline`：频道 101691、聊天 101689），没有就不给，不猜。
- **人数**：列表和详情的 `viewer_count` 是在线人数（`audience.dart` 加 `kick: roomList`）；主播关了人数显示（`show_view_count: false`）时留空，照网页和上游。
- **成人内容**：Kick 标了 `is_mature` 的直播匿名也能看，不设 `restriction`（设成 `adult` 会在发现页默认隐藏），房间公告写“该直播已被 Kick 标记为成人内容（18+）。”（上游的 `kick_mature_notice`）。
- **错误**：403 是 `RiskControl`（Cloudflare 的拒绝写明“需要 Android 系统 TLS”），404 `NotFound`，429 `RateLimited`，5xx 和传输失败 `NetworkFailure`，主播放列表 403/404 是 `StreamUnavailable`（下播或令牌过期），其余 `ApiChanged`。

## 与上游 pure_live_TV 的差异

| 项 | 上游 | 这里 | 原因 |
|---|---|---|---|
| 分类 | 一个“公开直播目录” | 6 个大类和各自的热门小分类 | Kick 有公开的分类接口；只有一个目录时分区页没有意义 |
| 列表排序 | 不带 `sort` | `sort=desc` | 不带时顺序随机（实测第一条 0 人） |
| 搜索顺序 | 先标签命中的直播，再频道 | 先频道，再标签直播 | 搜“xqc”应先出 xQc 本人；标签命中的是别的频道 |
| 不认识的小分类 | — | 过滤 + `NotFound` | Kick 会返回全站列表 |
| 聊天参数 | 弹幕连接自己再请求频道 | 进房时一起给 | 少一个请求，平台层不在弹幕里发请求 |
| 详情封面 | 只认 `files/images/static.kick.com` | 也认 `stream.kick.com` | 直播中的截图在这个主机（上游拿不到封面） |
| 画质名称 | `<高度>p[60] · HLS` | 渲染组名（`1080p60`、`480p`） | 和 Kick 播放器一致 |
| 错误 | `KickException` 枚举 | `SiteError` 各类型 | v4 的统一错误 |
| 传输 | 全局 Dio + 原生通道，读全局设置 | 注入的 `LiveHttp` | 平台层不依赖 Flutter |

保持上游的：请求头、身份校验（回答的 slug 必须是请求的）、聊天房间 id 不猜、人数隐藏时不显示、成人公告、链接规则（一段路径、保留路径）、恢复时重新取流、4 MiB 回答上限。

## 3.x 数据和身份

- 3.x 版本表第 17 版是 `kick`（`LegacyRules.catalogAdditions` 里写的是字面量 `'kick'`）。现在 `kick` 是支持的平台，3.x 平台列表版本低于 17 的用户迁移时会补上 Kick；3.2.11 之后的 3.x 已经把它从列表里删了，这些用户要在设置里自己打开（新装用户的默认列表 `SiteIds.supported` 里有）。
- 3.x 的 Kick 关注、历史（房间号是 slug）不再算“已下线”：Android 上照常显示、刷新、进房；身份不分大小写。Windows 上 Kick 没有登记，关注只显示存的信息，刷新记为失败（等 WinHTTP）。
- 平台显示顺序：放在 CHZZK 之后（3.x 版本表里 Kick 紧跟 CHZZK）。图标用 pure_live_TV 的 `assets/images/kick.png`（与现有平台图标同源）。

## 放到其他模块的部分

| 模块 | 内容 |
|---|---|
| T06a | 聊天（T06a.31，本次一起做） |
| T07a.1 | Android：`AndroidNativeHttp` 白名单加 `kick.com`（Kotlin `ALLOWED_HOSTS` 和 Dart `allowedHosts`），`PlatformDeps.kickApi`，有它才登记 Kick；Windows：WinHTTP 通道（X-1 余项） |
| M13 | 分区页的 Kick 大类、搜索能力（`search_capability.dart` 已加一行：开播和未开播、不翻页） |
| T04 | 线路不设租期；令牌过期后变体地址的寿命要真机长时间播放验证 |

## 样本

| 样本 | 请求 | 用途 |
|---|---|---|
| `S01-categories` | `api/v1/categories` | 6 个大类 |
| `S01-subcategories-<大类>`（6 个） | `api/v1/subcategories?category=…&limit=32&page=1` | 各大类的热门小分类（游戏 32、生活 32、音乐 6、博彩 18、创作 16、其他 9） |
| `S02-category-p1` | `stream/livestreams/en?…&subcategory=just-chatting&sort=desc` | 小分类第 1 页 |
| `S02-category-last` | chess 第 2 页 | 列表结束（空页、`next_page_url: null`） |
| `S02-category-missing` | 不存在的小分类 | Kick 返回全站列表 → `NotFound` |
| `S03-recommend-p1`、`-p2` | `stream/livestreams/en?…&sort=desc` | 推荐，按人数，含隐藏人数和成人直播 |
| `S04-search`、`S04-search-empty` | `api/search?searched_word=xqc` 等 | 搜索 |
| `S05-channel-live`、`-offline`、`-missing` | `api/v2/channels/xqc` 等 | 详情、聊天房间 id、404 |
| `S06-master` | xQc 的主播放列表 | 画质、编码、令牌过期时间 |

- 用 curl 录（dart:io 被拦），`meta.json` 照 schema 1，工具写在 `tool` 字段。
- 脱敏：JWT 令牌的签名部分换成同形值（头和载荷保留，`exp` 要用）；主播放列表的 `USER-IP`（出口地址）换成 `203.0.113.7`，`SERVING-ID`、`VIDEO-SESSION-ID`、`C`/`E`（Base64 的分片地址令牌）和 5 个变体地址的令牌换成同形值；响应头的 Cloudflare Cookie 删掉。门禁 `fixture privacy` 通过。频道资料是公开数据。

## 测试

新增 37 个：`kick_api_test.dart` 20 个（大类、小分类、坏行、状态映射；推荐卡片各字段、隐藏人数、成人公告、小分类过滤和不存在、列表结束、坏行；搜索顺序；在播/未开播/不存在/封禁详情、令牌过期时间、聊天参数；画质名称和顺序、编码、线路、主播放列表的错误、没有渲染组名；链接、slug），`kick_site_test.dart` 17 个（身份和 `SiteIds`；分类 7 个请求、部分失败、全部失败、Cloudflare；推荐翻页和查询参数、小分类、不存在和外平台分区；搜索一页；进房的请求分到两个传输、关注刷新只一个请求、未开播不取流、不存在；卡片先进房、恢复换新主播放列表和退回最高档、下播时的主播放列表；传输失败和取消；链接）。

改了的旧测试：`sites_links_test`（支持 35 个、Kick 在 CHZZK 之后、不再下线；下线示例换成花椒、Rumble）、`live_room_upgrades_test`（不分大小写的平台加 Kick；3.x 样本覆盖检查除去 Kick：它没有 3.x 输出）、`live_room_test`。`live_core` 共 3623 个，全部通过。
