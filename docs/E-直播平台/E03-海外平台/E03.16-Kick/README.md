# E03.16 Kick（恢复，仅 Android）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：不是 3.x 平台的逐个重构：3.x 在 v3.2.11 下线了 Kick，v4 按 UPGRADES X-1“恢复 Kick”（先在 Android 和电视版恢复，Windows 等 WinHTTP 通道）重新接入，参考 pure_live_TV 的 `lib/platforms/kick/`；2026-10-01 平台层和聊天（D01.31）一起完成，记在 [record.md](record.md)
- 旧编号：M4.34、T02c.16
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（`SiteIds.caseInsensitiveRoomIds` 加 `kick`，封禁）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；聊天 [D01.31](../../../D-弹幕/D01-平台弹幕协议/D01.31-Kick弹幕/README.md)（Pusher，用 `KickDanmakuArgs`）；Android 原生 HTTP 通道在 I01.1；Windows 的 WinHTTP 通道 [X01.2](../../../X-多端客户端/X01-Windows/X01.2-Windows专属功能/README.md)；真机验证 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)；3.x 版本表第 17 版的迁移 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md)；决定 D-017、D-018
- 代码：`packages/live_core/lib/src/sites/kick/`（`kick_api.dart` 654 行解析、画质、链接，`kick_site.dart` 281 行请求编排）；应用侧 `apps/pure_live/lib/platform/native_http.dart:23` 和 `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/AppChannelsPlugin.kt:196` 的原生通道白名单含 `kick.com`，`apps/pure_live/lib/app/bootstrap.dart:179` 把 `AndroidNativeHttp` 作 `kickApi` 传入，`apps/pure_live/lib/app/platforms.dart:172` 只在有 `kickApi` 时登记 Kick、`:225` 建聊天连接；样本 `fixtures/kick/`（18 组，另有聊天录制 `danmaku/`）

## 目标

在 v4 里把 3.x 已经下线的 Kick 恢复成可用平台，范围只限 Android。kick.com 的全部接口（`/api/v1`、`/api/v2`、`/api/search`、`/stream/livestreams`，连 `web.kick.com`）都由 Cloudflare 按 TLS 指纹拦截：`dart:io` 不管带什么请求头都是 403 `Request blocked by security policy.`，curl 和浏览器是 200。IVS 主播放列表（`*.playback.live-video.net`）、图片（`files/images/stream.kick.com`）和 Pusher 聊天不在 Kick 的 Cloudflare 后面，`dart:io` 能用。所以 kick.com 的请求走 Android 的系统 TLS（`AndroidNativeHttp`，与 Twitch 的 GraphQL 共用这条通道），其余走普通的 `dart:io`；Windows 没有可用通道（WinHTTP 还没做），所以不登记 Kick。平台层要做到：分类和小分类、推荐、分区房间、搜索、详情、画质和线路、恢复、链接、聊天参数都可用，3.x 存下的 Kick 关注和历史在 Android 上不再显示“已下线”。

## 平台接口要点

| 功能 | 接口（kick.com 的请求经 `apiHttp`；桌面 Chrome UA、`accept: application/json, text/plain, */*`、`accept-language: en-US`、`origin`/`referer` 为 kick.com；以 `kick` 的名义发出） | 位置 |
|---|---|---|
| 两个传输 | `KickSite(http, apiHttp: …)`：kick.com 走 `apiHttp`（应用在 Android 传入 `AndroidNativeHttp`），主播放列表走 `http`；平台层不依赖 Flutter | `kick_site.dart:41`、`:57-67` |
| 请求头 | API `KickApi.headers`；媒体 `mediaHeaders(slug)`：UA、`origin: https://kick.com`、`referer: https://kick.com/<slug>/`（IVS 令牌的 `aws:access-control-allow-origin` 列的是 kick.com） | `kick_api.dart:122`、`:132` |
| 分类 | `GET /api/v1/categories` 得到 6 个大类（游戏、生活、音乐、博彩、创作、其他，中文名），再同时取每个大类观看最多的 32 个小分类 `GET /api/v1/subcategories?category=<slug>&limit=32&page=1`，共 7 个请求；某个大类失败就略过，全部失败才报错；小分类 `areaType: subcategory`，图是分类横幅 | `kick_site.dart:75-108`；`kick_api.dart:152`、`:185`、`:202` |
| 推荐、分区房间 | `GET /stream/livestreams/en?page=&limit=30&sort=desc[&subcategory=<slug>]`，`sort=desc` 按观看人数排（不带时顺序随机）；Kick 不认识的小分类会返回全站列表，所以只留属于该小分类的行，一行都不属于时 `NotFound` | `kick_site.dart:113-162`；`kick_api.dart:236` |
| 搜索 | `GET /api/search?searched_word=`，只有一页；先列频道（开播和未开播都有，按 Kick 的排序），再补标签命中、频道不在前面的直播；关键词截到 50 字 | `kick_site.dart:173-185`；`kick_api.dart:146`、`:270` |
| 详情、关注刷新 | `GET /api/v2/channels/<slug>`：回答的 slug 必须是请求的（否则 `ApiChanged`），404 是 `NotFound`，封禁是 `LiveStatus.banned`；`viewer_count` 是在线人数，主播关了人数显示（`show_view_count: false`）时留空；`is_mature` 只写公告“该直播已被 Kick 标记为成人内容（18+）。”，不设受限类型；关注刷新只读这一个请求 | `kick_site.dart:188-222`；`kick_api.dart:162`、`:303` |
| 画质 | 开播时请求频道回答里的 `playback_url`（带 JWT 令牌的 IVS 主播放列表），名称用视频渲染组的 `NAME`（`1080p60`、`720p60`、`480p`、`360p`、`160p`，源画质的组叫 `chunked`，名字仍是 `1080p60`），没有时用“高度 + 帧率”；id 就是名称 | `kick_site.dart:197-207`；`kick_api.dart:392-400` |
| 取流 | 线路是变体地址：HLS、编码取 `CODECS`、带媒体请求头；主播放列表令牌约 5～10 分钟过期（JWT `exp`，记在 `KickRoomData.tokenExpiresAt`），变体地址不带它，照 Twitch 的做法不设租期；恢复重新读频道和主播放列表，按名称找回同一档，找不到用最高档 | `kick_site.dart:230-271`；`kick_api.dart:370`、`:470` |
| 聊天参数 | 进房时从频道回答取 `KickDanmakuArgs(chatroomId, channelId, slug)`，不多发请求；聊天房间 id 和频道 id 不同（`xqcisoffline`：频道 101691、聊天 101689），没有就不给，不猜 | `kick_api.dart:22`、`:359` |
| 链接 | `kick.com/<slug>`（一段路径，slug 小写），保留路径（`categories`、`search`、`browse`……）不是房间 | `kick_api.dart:165-180`、`:492`；`kick_site.dart:277` |
| 错误 | 403 `RiskControl`（Cloudflare 的拒绝写明需要 Android 系统 TLS），404 `NotFound`，429 `RateLimited`，5xx 和传输失败 `NetworkFailure`，主播放列表 403/404 是 `StreamUnavailable`（下播或令牌过期），其余 `ApiChanged` | `kick_api.dart` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref`，即 v3.2.11） | 现在 | 说明 |
|---|---|---|---|
| 适配器 | 没有：v3.2.0 加入 Kick（`README.md:75`），v3.2.11 下线时删掉了 `lib/core/site/kick/` 整个目录，`lib/core/site/` 下没有 Kick | `packages/live_core/lib/src/sites/kick/` 两个文件 | 没有 3.x 代码可对照，也没有 `expected.json`；照 pure_live_TV（e1cca224 加回，本地副本到 b9d2f73）重写 |
| 下线的理由 | `RELEASE_NOTES.md:16`：kick.com 的全部接口被 Cloudflare 按 TLS 指纹拦截，只能靠 Android 和 Windows 的系统 TLS 通道绕过，Linux、macOS、iOS 用不了；`docs/PLATFORM_COMPATIBILITY.md:6` 同样写明 | Android 走系统 TLS 恢复；Windows 不登记 | UPGRADES X-1 |
| 平台登记 | `lib/core/sites.dart:115-131` 把 `kick` 放进 `retiredSiteIds`，`:154` 把 `kick.com` 放进 `_retiredHosts`：关注打开时提示“该平台已下线”，分享的 kick.com 链接同样提示 | `SiteIds.kick` 是支持的平台（`packages/live_core/lib/src/sites.dart:66`、`:135`），不分大小写（`:233`）；Android 上照常显示、刷新、进房 | 3.x 的 Kick 关注、历史（房间号是 slug）都能对上 |
| 版本表 | `lib/common/services/settings/favorite_room_controller.dart:73` 第 17 版仍是 `'kick'`（“retired in 3.2.11; keeps later versions aligned”） | `packages/live_store/lib/src/legacy/legacy_rules.dart:77` 照写；3.x 平台列表版本低于 17 的用户迁移时补上 Kick | 3.2.11 之后已把它从列表删掉的用户要在设置里自己打开；新装的默认列表里有 |
| 聊天 | 3.x 下线前有只读 Pusher 聊天（`docs/KICK_PUBLIC_CHAT_AUDIT_2026_09_23.md`：聊天房间 id 与频道 id 不同，弹幕会话启动时再查一次频道） | 进房时一起给聊天参数，弹幕连接不再请求频道（D01.31） | |
| 人数 | `docs/PLATFORM_COMPATIBILITY.md:65` `show_view_count=false` 时保持未知 | 同样留空；`packages/live_core/lib/src/audience.dart:154` 的 `kick` 一行是在线人数 | |

## 与上游 pure_live_TV 的差异

| 项 | 上游 | 现在 | 原因 |
|---|---|---|---|
| 分类 | 一个“公开直播目录” | 6 个大类和各自的热门小分类 | Kick 有公开的分类接口 |
| 列表排序 | 不带 `sort` | `sort=desc` | 不带时顺序随机（实测第一条 0 人） |
| 搜索顺序 | 先标签命中的直播，再频道 | 先频道，再标签直播 | 搜“xqc”应先出 xQc 本人 |
| 不认识的小分类 | 照收全站列表 | 过滤，没有就 `NotFound` | |
| 聊天参数 | 弹幕连接自己再请求频道 | 进房时一起给 | 少一个请求 |
| 详情封面 | 只认 `files/images/static.kick.com` | 也认 `stream.kick.com` | 直播中的截图在这个主机 |
| 画质名称 | `<高度>p[60] · HLS` | 渲染组名 | 与 Kick 播放器一致 |
| 传输 | 全局 Dio，按主机切原生通道 | 注入的 `LiveHttp` | 平台层不依赖 Flutter |

## 结果

- 完成（2026-10-01，提交 `6c68f0010`）：平台层和聊天（D01.31）一起做；Android 原生通道白名单加 `kick.com`，`PlatformDeps.kickApi` 有值才登记 Kick；平台显示顺序放在 CHZZK 之后（3.x 版本表里 Kick 紧跟 CHZZK），图标用 pure_live_TV 的 `assets/images/kick.png`。
- 样本 18 组，2026-10-01 用 curl 匿名只读录制（`dart:io` 被拦）；JWT 签名、主播放列表的 `USER-IP`、会话编号、分片令牌已换成同形值，门禁 `fixture privacy` 通过。
- 测试：`packages/live_core/test/sites/kick_api_test.dart` 20 个 `test(` 写法、`kick_site_test.dart` 17 个；改了 `sites_links_test`（支持 35 个、Kick 不再下线）、`live_room_upgrades_test`、`live_room_test`；聊天 `packages/live_danmaku/test/sites/kick_test.dart`。

## 验证

- 自动测试：样本逐项断言（没有 3.x 输出可对照）：大类、小分类、坏行；推荐卡片各字段、隐藏人数、成人公告、小分类过滤和不存在、列表结束；搜索顺序；在播、未开播、不存在、封禁的详情，令牌过期时间，聊天参数；画质名称、顺序、编码、线路；进房的请求分到两个传输、关注刷新只一个请求；恢复换新主播放列表和退回最高档；Cloudflare 403。
- 真实接口：2026-10-01 联网约 8 分钟，按上表核对了 `dart:io` 和 curl 对各主机的结果；主播放列表令牌过期后变体地址还能用多久没有验证（录制时 xQc 很快下播）。
- 真机：没有在 K90 上看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节写“新增，只在 Android（原生 HTTP），没验证 → S02.4”）；国内要开代理。

## 留下的问题

- Android 真机上走系统 TLS 的推荐、搜索、进房、播放和聊天都没有验证：归 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)（“Twitch 和 Kick”一项）。
- Windows 不登记 Kick，3.x 的 Kick 关注只显示存的信息、刷新记为失败：WinHTTP 通道归 [X01.2](../../../X-多端客户端/X01-Windows/X01.2-Windows专属功能/README.md)（UPGRADES X-1 余项，功能清点 F-WIN-12）；电视版归 X03。
- 主播放列表令牌过期（5～10 分钟）后变体地址能用多久没验证，现在不设租期、断流再恢复：要真机长时间播放验证，归 G 组。
- Cloudflare 的指纹规则随时可能变，系统 TLS 通道也可能失效（3.x 下线时就这样写）：没有任务管，失败时报 `RiskControl`。
- 3.2.11 之后的 3.x 用户平台列表里没有 Kick，迁移后要在设置里自己打开：J02.1 的迁移规则，不再改。
