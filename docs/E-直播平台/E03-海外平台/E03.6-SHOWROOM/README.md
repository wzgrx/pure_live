# E03.6 SHOWROOM

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 19-1～19-5）记在 [record.md](record.md)；评论由 D01.16 接上
- 旧编号：M4.19、M4.U.19、T02c.6
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；评论 [D01.16](../../../D-弹幕/D01-平台弹幕协议/D01.16-SHOWROOM弹幕/README.md)（用 `ShowroomDanmakuArgs`）；翻页共用快照接到推荐页 I02.1、分区页 I03.1、搜索页 I05.1；画质偏好的按比例选档在 G 组；决定 D-001、D-017
- 代码：`packages/live_core/lib/src/sites/showroom/`（`showroom_api.dart` 761 行纯解析，`showroom_site.dart` 434 行请求编排）；应用在 `apps/pure_live/lib/app/platforms.dart:170` 建适配器；样本 `fixtures/showroom/`（10 组接口录制，另有评论帧 `danmaku/S06-live` 和生成 3.x 冻结输出的 `legacy_expected.dart`）

## 目标

把 3.x 的 SHOWROOM 适配器（`lib/core/site/showroom/` 三个文件共 797 行，自带一套流式读取的传输层，媒体请求头写在播放层）重构进 `live_core`：分类、目录、推荐、搜索都来自同一份“此刻全部在播房间”的快照，房间、画质、链接、恢复都和 3.x 一样；修掉 3.x 的 14 个问题（纯数字房间键打开错误的房间、取不到线路时整个房间打不开、快照里一行线路不对整个目录失败等）。升级落地后翻页共用同一份快照、原画排第一、给出评论参数、未开播不显示人数。

## 平台接口要点

| 功能 | 接口（`www.showroom-live.com`；请求头 Chrome 140 UA、`Accept: application/json, text/plain, */*`、`Referer`；不跟随跳转；匿名，不注入 Cookie；以 `showroom` 的名义发出，走代理） | 位置 |
|---|---|---|
| 请求 | `_get`：`Uri.https` + 3.x 的请求头，`followRedirects: false`；401/403 `RiskControl`、404 `NotFound`、429 `RateLimited`、其他 `NetworkFailure` | `showroom_site.dart:76-85`；请求头 `showroom_api.dart:182-198` |
| 快照 | `api/live/onlives`，一次给出全部在播房间（约 170 KB），按类型分组；共用 30 秒（`snapshotLifetime`），第 1 页（下拉刷新）总是重新请求，第 2 页起和取分类、推荐、分区切片都用这份 | `showroom_site.dart:50`、`:104-105`、`:122-146`；解析 `showroom_api.dart:256-293` |
| 分类和分区 | 一个分类 `SHOWROOM`，每个类型一个分区（`areaType: genre`，id 是 `genre_id`），没人在播的类型也列出 | `showroom_site.dart:186`；`showroom_api.dart:331` |
| 目录和推荐 | 原生目录每页 30 个；推荐是 Popularity（`genre_id` 0），没有这一组时取全部房间各一次；切片按 3.x：页码或条数小于 1、条数超过 100 给空；目录说明键 `showroom_directory_scope` | `showroom_site.dart:198`、`:210`、`:220`、`:68`；`showroom_api.dart:375-396` |
| 搜索 | 没有平台接口：在快照里按房间号、房间键（相等，忽略大小写）和名字、字幕（telop）、类型名（包含）过滤 | `showroom_site.dart:235-253`；`showroom_api.dart:402` |
| 卡片 | 标题是 telop，没有时是名字；封面、头像用 `image_square`（只收 SHOWROOM 主机的 https 地址）；`view_num` 是累计观看；开播时间 `started_at`；受限类型看 `premium_room_type` | `showroom_api.dart:293-306`、`:352-358` |
| 房间键 | `api/room/status?room_url_key=`：把房间键换成数字 `room_id` | `showroom_site.dart:275-280`；`showroom_api.dart:427` |
| 详情 | `api/room/profile` 和 `api/live/live_info` 同时请求；`live_status` 2 在播，0、1 未开播，其他是 `ApiChanged`；进房和录制的在播房间再请求 `api/live/streaming_url?abr_available=1`，失败也照常进房 | `showroom_site.dart:290-325`；`showroom_api.dart:434-468`、`:493` |
| 开播状态 | 只请求 `live_info` | `showroom_site.dart:330-332` |
| 画质 | `hls` 按 `quality`：1000 以上“原画”、200 以上“中画质”、其余“低画质”，自适应主列表 `hls_all` 是“自动”排最后（`autoSort` -1）；id `类型:id:quality`（`hls:2:1000`）；WebRTC 跳过；最多 64 行 | `showroom_site.dart:353-362`；`showroom_api.dart:240`、`:529-594` |
| 取流和恢复 | 每档一条 HLS 线路，带 3.x 的媒体请求头（UA、`Referer`），线路编号是节点主机名，没有租期；恢复只请求一次 `streaming_url` | `showroom_site.dart:363-380`；`showroom_api.dart:603` |
| 评论参数 | `live_info` 的 `bcsvr_host`、`bcsvr_key` → `ShowroomDanmakuArgs(roomId, host, key)`，只在进房和录制的在播房间给，主机必须是 `showroom-live.com` 的子域 | `showroom_api.dart:43`、`:479`；`showroom_site.dart:309` |
| 链接 | `showroom-live.com` 及子域；`room/profile?room_id=<号>` 得到房间号，`/r/<键>`、`/<键>` 得到房间键；站点页面（`reservedPaths`）不认；纯数字的键在解析链接时经 `room/status` 换成房间号 | `showroom_site.dart:396-423`；`showroom_api.dart:221-235`、`:618-643` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/showroom/`） | 现在 | 说明 |
|---|---|---|---|
| 纯数字房间键 | `showroom_link.dart:31-32` 原样返回，`showroom_api.dart:268` `int.tryParse` 成功就当房间号，打开错误的房间 | 解析链接时请求一次 `room/status`（`showroom_site.dart:419-423`） | 3.x 问题 1；样本 S01 的 64 个热门房间里有 3 个这样的键 |
| 取不到线路 | `showroom_api.dart:333-340` 进房时就取流，列表为空整个房间打不开 | 房间照常打开，取流时报 `StreamUnavailable` 或 `ApiChanged` | 3.x 问题 2 |
| 快照里的线路 | 一行线路不对，分类、目录、推荐、搜索全部失败 | 快照不读线路；坏行、坏类型只跳过自己 | 3.x 问题 3、升级的容错 |
| 翻页 | `showroom_site.dart:49` 带取消令牌就绕过缓存，每页重新下载快照 | 第 1 页刷新，之后 30 秒内共用同一份 | 19-1 |
| 并发请求 | `showroom_site.dart:52-59` 回答到达前每个调用各发一次 | 共用进行中的请求 | 3.x 问题 5 |
| 画质顺序 | `showroom_site.dart:230` “自动”的 `sort` 是 2000，排第一 | `autoSort` -1，原画排第一；名称和 id 不变 | 19-2，存下的画质偏好不用迁移 |
| 未开播取画质 | `showroom_site.dart:259` 返回空列表 | `StreamUnavailable`，不发请求 | 3.x 问题 6 |
| 没有详情数据的房间 | `showroom_site.dart:260-262` 报 `mediaUnavailable` | 请求一次 `streaming_url` | 3.x 问题 7 |
| 恢复、开播状态 | `showroom_site.dart:275-285` 重读整个房间（3 个请求）；`:252-254` 开播状态 2 个请求 | 各 1 个请求 | 3.x 问题 8、9 |
| 站点页面链接 | `showroom_link.dart:4-14` 保留路径不全，`/onlive`、`/r` 当房间键 | 加上归档 v4 找到的 `r`、`onlive`、`campaign`、`about`、`lottery` | 3.x 问题 12 |
| 错误 | `showroom_api.dart:22` 平台自己的 `ShowroomException` | 类型化的 `SiteError`；调用方传错页码或分区是 `ArgumentError`，不发请求 | 3.x 问题 10、11 |
| 传输层 | `showroom_api.dart:166-210` 全局 `HttpClient`、3 MiB 和 20 秒自己实现 | 注入 `LiveHttp` | 3.x 问题 13 |
| 未开播人数 | 写 `view_num`（未开播是 0，显示“0 人看过”） | 未开播时人数留空 | 19-4 |
| 开播时间、受限类型 | 没有 | 卡片 `started_at`，详情 `current_live_started_at`（只在播时填）；`premium_room_type` 0 填 `none`，其他值留空 | E05.2 统一原则；19-5 受阻 |
| 评论 | `showroom_site.dart:46` `EmptyDanmaku` | 平台层给 `ShowroomDanmakuArgs`，连接在 `live_danmaku/lib/src/sites/showroom.dart`（D01.16） | 19-3 |

## 结果

- 首次重构（2026-09-28，提交 `eaca04cc0`）：14 个 3.x 问题、10 条有意差异见 record.md；画质名称、分类 id `showroom`、分区 `areaType` `genre`、卡片标题 telop 优先、房间带媒体请求头都保持 3.x；归档 v4 的“原画排第一”“评论”等做法当时列为升级候选。
- 升级落地（2026-09-29）：19-1～19-4 完成（19-1 的界面部分由 I02.1、I03.1、I05.1 接上；19-3 平台层给参数，连接由 D01.16 完成；19-4 卡片只在直播中显示人数由 A09.1 接上）；19-5 受阻。按统一原则补了开播时间、受限类型、容错（坏行、坏类型、坏画质行只跳过自己，全坏仍报 `ApiChanged`）。
- 测试：`packages/live_core/test/sites/showroom_api_test.dart` 32 个 `test(` 写法、`showroom_site_test.dart` 28 个（record.md 写的是 33 个和 28 个）；评论 `packages/live_danmaku/test/sites/showroom_test.dart` 归 D01.16。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（`fixtures/showroom/legacy_expected.dart` 把 3.x 的适配器原样搬进脚本生成）：S01 的分类、推荐 4 页、18 个类型各两页、8 种推荐切片、8 个关键词搜索；S02～S05 按房间号和房间键的进房、刷新、录制、画质、每档地址、恢复；20 个链接。升级后另测快照共用（第 1 页刷新、29 秒复用、30 秒重新请求、取消和失败不留快照、时钟倒退不复用）、评论参数的检查、开播时间取值范围、容错。
- 真实接口：2026-09-28 18:40～19:00 UTC 直连、匿名跑过：快照 109 行（49 个房间），推荐第 1 页 30 个、第 2 页 11 个不重复且第 2 页不再请求；进房带评论参数（`online.showroom-live.com`）；画质顺序原画、中画质、低画质、自动。只有声音的直播（`live_type` 4）也有 HLS 地址，照常处理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只记“完成”）；要用户开着代理。

## 留下的问题

- 19-5 付费直播标“付费”：受阻，没有付费直播进行中的样本。未开播时 `premium_room_type` 都是 0，付费时写什么值、`streaming_url` 是空列表还是报错都不知道；付费直播列表接口是 `api/premium_live/search`。录到样本后把 `restrictionOf` 的非 0 值改成 `paid`，卡片标“付费”。没有任务管（登记在 UPGRADES 19-5）。
- `live_info` 的 `age_verification_status`、`is_under_18`、`is_under_16` 在样本和实测里都是 0，含义不明，没有用；没有任务管。
- 目录说明 `showroom_directory_scope` 仍是开发说明式的文字，record.md 给了建议的中英文；属于文字清理，没有单独的任务。
- 画质偏好按比例选档时会选到排最后的“自动”，应跳过它（G 组；没有单独登记任务）。
- 关注列表里刚下播的房间合并时会保留上次的人数（E05.2 空值不覆盖），要靠界面按是否在播决定显示，已由 A09.1 的卡片做到。
