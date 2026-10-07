# E03.13 FC2 LIVE

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 26-1～26-9，26-2 另有主会话补充决定：频道有 40、50 两档时一并列出）记在 [record.md](record.md)；画质探测交出控制连接在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md)（c10）；评论由 D01.23 接上
- 旧编号：M4.26、M4.U.26、T02c.13
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（受限类型、开播时间、占位不覆盖）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；评论 [D01.23](../../../D-弹幕/D01-平台弹幕协议/D01.23-FC2LIVE弹幕/README.md)（用 `Fc2LiveDanmakuArgs`，自己开一条控制连接）；控制连接接手（`probeControl` / `Fc2RecipeOpener.adopt`）接到应用在 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/README.md) 阶段“FC2”；按配方播放和录制在 G、H 组（`live_media` 的 `Fc2RecipeOpener`）；英文界面里的分区名 [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/fc2live/`（`fc2live_api.dart` 1051 行解析、画质和链接，`fc2live_control.dart` 268 行媒体控制 WebSocket，`fc2live_site.dart` 498 行请求编排）；`live_net` 的 `connectIoSocket` 为它加了可选的 `pingInterval`；应用里在 `apps/pure_live/lib/app/platforms.dart:178` 建适配器、`:230` 建评论连接，录制在 `apps/pure_live/lib/app/recording.dart:34` 注册 `Fc2RecipeOpener`；样本 `fixtures/fc2live/`（8 组，另有控制连接对话 `control/S04-control`、`control/S07-control-hd` 和评论 `danmaku/S06-live`）

## 目标

把 3.x 的 FC2 LIVE（日本）适配器（`lib/core/site/fc2live/` 五个文件共 1016 行）重构进 `live_core`：在播快照目录、本地分页和搜索、`memberApi` 详情、控制授权、媒体控制 WebSocket、配方取流、链接都和 3.x 一样，匿名、不带 Cookie。FC2 的 HLS 由一条媒体控制 WebSocket 授权：连接一关，变体列表就 403，所以取流照 3.x 给“配方”而不是线路，播放和录制各自开连接、播放期间一直持有。重点修掉 3.x 最大的毛病：每个未开播的频道都回 `version: ''`，3.x 却要求它非空，关注的 FC2 频道下播后永远刷新失败、显示不出“未开播”。升级落地后改为按频道列出分档画质（高清、标清、流畅，部分频道还有超清 2M、超清 3M（β））、翻页共用同一份快照、受限直播显示直播中并标受限类型。

## 平台接口要点

| 功能 | 接口（`live.fc2.com`，全部表单 POST；3.x 的请求头含 `Origin`、`Referer: https://live.fc2.com/`、`X-Requested-With`；不跟随跳转、不带 Cookie；以 `fc2live` 的名义发出，走代理） | 位置 |
|---|---|---|
| 请求头 | API 请求头 `Fc2LiveApi.headers`；媒体请求头 `mediaHeaders`（`Referer` 是频道页） | `fc2live_api.dart:249`、`:260` |
| 分类 | 不请求：一个分类 `FC2 Live`，六个分区 `all` 全部、`1` 闲聊、`2` 游戏 / 作业（含 3）、`4` 视频、`9` 音频、`5` 其他；目录说明键 `fc2live_directory_scope` | `fc2live_api.dart:287`、`:400`；`fc2live_site.dart:108`、`:215` |
| 目录、推荐、分区房间 | `/contents/allchannellist.php` 一次给出全部在播频道（快照），只收 `type` 为 1 的公开房间，本地每页 20 个；第 1 页（下拉刷新）总是重新请求，之后的页、推荐、分区切片用 20 秒内的同一份快照（26-1）；坏行只跳过自己（26-7） | `fc2live_site.dart:147-208`、`:227`；`fc2live_api.dart:466`、`:586` |
| 搜索 | 频道号或频道链接：一次 `memberApi`（只有第 1 页，未开播也能找到）；其他关键词在快照里按频道号、名字、标题、分区名（中文和 3.x 的英文）过滤 | `fc2live_site.dart:277-308`；`fc2live_api.dart:597` |
| 详情、关注刷新、开播状态 | `/api/memberApi.php`（`channel=1&profile=1&user=1&streamid=<频道号>`），各 1 个请求；`is_publish` 为 1 是直播中；`profile_data.userid` 为空是不存在；头像用 `profile_data.icon`、`image`（26-5）；标题、名字、简介解码 HTML 字符（26-4）；开播时间取 `channel_data.start`（Unix 毫秒） | `fc2live_site.dart:317-352`；`fc2live_api.dart:632`、`:699`、`:1006` |
| 受限类型 | 目录 `pay`、`tid` → `paid`，`login` 1/2 → `needsLogin`；详情 `is_limited` → `unplayable`，`fee`、`ticketid`、`ticket_only` → `paid`，`login_only` → `needsLogin`；受限的直播显示直播中，取流按类型拒绝（26-9） | `fc2live_api.dart:523`、`:536`、`:553` |
| 控制授权 | `memberApi` 后 `/api/getControlServer.php`（`channel_version`、`client_version=2.1.0\n [1]` 等与 3.x 逐项相同）；未开播、受限只发第一个请求 | `fc2live_site.dart:364-382`；`fc2live_api.dart:751` |
| 控制连接 | `wss://…/control/channels/<频道号>?control_token=…`，握手带 `Cookie: l_ortkn=<orz_raw>`、UA、`Origin`；`connect_complete` 后发一次 `get_hls_information`；每 15 秒 ping；从握手到拿到列表最多 20 秒；`control_disconnection`（授权约一分钟后 4500）、断开、坏帧都结束连接，不用旧授权重连 | `fc2live_control.dart:39`、`:90`、`:96`、`:193-211` |
| 画质 | 取画质要开一次控制连接读 HLS 回答（`memberApi`、`getControlServer` 和连接），按频道列出 `50` 超清 3M（β）、`40` 超清 2M、`30` 高清、`20` 标清、`10` 流畅，最后是 3.x 的 `auto` 自适应 HLS；读完关闭，或交给 `probeControl`（E06.1 c10） | `fc2live_site.dart:444-461`；`fc2live_api.dart:327-345`、`:849` |
| 取流 | `LivePlayUrlResolution.owned(Fc2LiveInputRecipe(频道号, quality))`，不发请求；打开时一档优先播高延迟单变体（mode + 1），没有就退档，`auto` 播 v3 的低延迟主列表 | `fc2live_site.dart:473-493`、`:392`；`fc2live_api.dart:206`、`:870` |
| 评论参数 | `Fc2LiveDanmakuArgs(频道号)`，进房和录制详情带，刷新、卡片不带（26-3） | `fc2live_api.dart:146` |
| 链接 | `live.fc2.com/<频道号>/`，可带语言前缀（`/ja/`、`/zh/` 等 13 种）和查询；纯数字不算链接 | `fc2live_api.dart:350`、`:369`、`:395` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/fc2live/`） | 现在 | 说明 |
|---|---|---|---|
| 未开播的频道 | `fc2_api.dart:265` 用 `_boundedToken` → `_text`（`:391-395`）要求 `version` 非空，未开播一律“结构变化” | 显示未开播；只在取授权时要求 `version` | 3.x 问题 1；用户能看到的变化 |
| 不存在的频道 | `fc2_site.dart:183-192` 想返回空，但 `status` 仍是 1，落到问题 1 | `profile_data.userid` 为空是 `NotFound`，搜索得到空 | 3.x 问题 2 |
| 快照 | `fc2_site.dart:44-56` 带取消令牌的调用（目录页、搜索页总是带）每次重新下载全部在播频道 | 第 1 页刷新，之后的页 20 秒内共用 | 3.x 问题 9；26-1 |
| 画质 | `fc2_site.dart:244-249` 只有 `auto` 一档 | 按频道列出五档 + `auto`；取画质多 2 个请求和一条打开即关的连接 | 26-2；默认第一档，`auto` 排最后 |
| 取画质的范围 | `fc2_site.dart:247` 只有进房得到的房间能取，刷新得到的、卡片报 `schema` | 任何在播且不受限的房间都能取 | 3.x 问题 6 |
| 控制连接启动 | `fc2_control_session.dart:116`、`:120`、`:124` 三段各 20 秒，最坏 60 秒才报错 | 握手到拿到列表一共 20 秒 | 3.x 问题 10；出错即关闭并给出原因（问题 11） |
| 控制连接的网络 | `fc2_control_session.dart:150` 直接用 `dart:io` 和调用方传的全局代理 | 经 `live_net` 的 `SocketConnector` 按 `fc2live` 路由，与 HTTP 同一出口 | 3.x 问题 12；REG-NET-005 |
| 头像 | `fc2_site.dart:124` 用封面（直播截图） | 详情用主播头像，目录卡片仍用封面 | 26-5 |
| 分区名 | 卡片英文（`fc2_api.dart:310` `Idle Chat` 等），详情日文 `category_name`（`:274`） | 都是目录分区的中文名（`Fc2LiveApi.areaName`） | 26-6；英文界面 → Z05.2 |
| 受限房间 | 状态“未知”，取流 `access` | 直播中 + 受限类型，按类型拒绝 | 26-9 |
| HTML 字符 | 原样显示 `&amp;` | 解码 | 26-4 |
| 简介 | `fc2_api.dart:271` 解析了却没传给房间 | 详情带简介 | 3.x 问题 16 |
| 未开播的人数 | 写回答里的 0 | 留空 | 26-8 |
| 占位名字 | 没有名字时写频道号 | 留空，界面显示平台名 | 统一原则；J02.1 迁移时清理 |
| 媒体请求头 | `fc2_site.dart:138` 写进每个房间的 `httpHeaders`，没人读 | 在控制连接上（`Fc2LiveControl.mediaHeaders`），值相同 | 3.x 问题 7 |
| 评论 | `fc2_site.dart:42` `EmptyDanmaku` | `live_danmaku/lib/src/sites/fc2live.dart`（D01.23） | 26-3 |

## 结果

- 首次重构（2026-09-28，提交 `eb7cd2497`）：19 个 3.x 问题、11 条有意差异见 record.md；`live_net` 的 `connectIoSocket` 加了可选 `pingInterval`（另 2 个测试）。3.x 没有 FC2 的冻结输出，本任务用 `fixtures/fc2live/legacy_expected.dart` 把 3.x 的 `Fc2Api`、`Fc2Link`、`Fc2Site` 和控制连接的消息解析器原样搬进脚本生成。
- 升级落地（2026-09-29）：26-1～26-9 平台层都完成（26-2 的播放由 G01.1 的 `Fc2RecipeOpener` 接上，录制由 H01.1、H02.1 接上）；新样本 `S02-member-points`（仅限持有积分）、`control/S07-control-hd`（1080p 频道，有 40、50 两档）。画质 id 没有变化（v3 的 `auto` 照旧），不需要对照表。
- E06.1 c10：`Fc2LiveSite(probeControl:)` 把画质探测开的控制连接交出去，没给时照旧关掉；应用还没有传（`platforms.dart:178`）。
- 测试：`packages/live_core/test/sites/fc2live_api_test.dart` 30 个 `test(` 写法、`fc2live_site_test.dart` 47 个；评论 `packages/live_danmaku/test/sites/fc2live_test.dart`。

## 验证

- 自动测试：7 组样本逐键对照 3.x 冻结输出（`changed:` 写条目号，新键 `added:` 单独断言）；快照的共用、过期、时钟倒退、失败不留；目录 10 种坏行、HLS 回答 17 种坏列表；受限标记的先后和拒绝类型；控制连接用录下的对话回放（握手地址、令牌、请求头、代理路由、请求帧逐字相同、6 种结束方式、取消、启动超时、两个拥有者各一条连接）；退档；时间放后 30 天、1 年、5 年都通过。
- 真实接口：归档样本 2026-09-27 直连录制；2026-09-28 补录未开播、受限频道；2026-09-28 19:50～20:10 UTC 直连、匿名用新适配器走了一遍（目录 56 个公开房间只发 1 个请求、5 个受限房间都是 `login` 1/2、两个频道进房并打开控制连接，`30` 播 `/31/playlist`、`auto` 播 `/0/master_playlist`），20:47 UTC 录下 1080p 频道的控制连接。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只写“完成（三档）”）；国内要开代理。

## 留下的问题

- 画质探测的控制连接交给播放（开播前少一次授权和连接）：平台层已有 `probeControl`，应用没传；`live_media` 的 `Fc2RecipeOpener.adopt` 按“频道:画质”配对，而探测的连接是按 `auto` 开的，选了别的档就配不上、接手后没用上的连接也没人关，要改成按频道接手并用 `Fc2LiveApi.playlistFor` 取那一档：归 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/README.md) 阶段“FC2”。
- 3.x 的全局画质偏好按名字选档，对不上时按比例选下标，应跳过排在最后的“自适应 HLS”：归 G 组。
- 英文界面里分区名、公告仍是平台层给的中文：归 [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)（UPGRADES 26-6）。
- 付费、门票（`pay`、`tid`、`fee`、`ticketid`、`ticket_only`）和 `is_limited` 的在播频道只有合成用例，没有实测它们的控制授权会回答什么：没有任务管。
- 受限直播的开播状态现在是真，录制开始时取流会报 `NeedsLogin` 或 `StreamUnavailable`，要当作“不能录”、不反复重试：归 H 组。
- 同一频道的播放和录制各开一条控制连接（REG-LEASE-017 不变）；要共享连接由 G 组决定，注意同时打开时只能开一条。
