# E02.1 YY 直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 6-1～6-8）、国内平台完善（2026-10-01）和附录 C 落地（C-18～C-21）都记在 [record.md](record.md)；真机问题修复（[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/README.md)，2026-10-01）补了一项预置分区名
- 旧编号：M4.06、M4.U.6、T02b.1
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕 [D01.7](../../../D-弹幕/D01-平台弹幕协议/D01.7-YY直播弹幕/README.md)；应用打开 FLV 优先在 [E06.3](../../E06-平台层升级/E06.3-YY优先用FLV/README.md)；FLV 续签和线路切换在 G 组（G01.1、G02.1）；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/yy/`（`yy_api.dart` 965 行解析，`yy_site.dart` 520 行请求编排）；样本 `fixtures/yy/`（ls 共 36 项：34 组接口录制，另有 `legacy_expected.dart`（3.x 解析部分的逐行转写，用来生成冻结输出）和弹幕样本目录 `danmaku/`）；应用在 `apps/pure_live/lib/app/platforms.dart:160` 建 `YySite(http, cookies: cookies)`

## 目标

把 3.x 的 YY 适配器（`lib/core/site/yy/yy_site.dart` 792 行）重构进 `live_core`，分类、分区、推荐、搜索、详情、清晰度和线路、链接都和 3.x 用户实际看到的一样（默认仍是匿名移动 HLS 两档“高清 · 720p”“流畅 · 360p”）。修掉 3.x 的 14 个问题，其中最重要的是 stream-manager 请求从来没成功过（正文被 Dio 表单编码，服务器一律 HTTP 500），修好后作为 FLV 兜底，也为以后的“FLV 优先”（6-1）准备好平台层。

## 平台接口要点

| 功能 | 接口（`www.yy.com` 除非另写；带 3.x 的浏览器请求头，存了 Cookie 就带上） | 位置 |
|---|---|---|
| 分类 | `/yyweb/module/data/header` + 3 个 `/c/yycom/category/getCategory.action?parentId=`，共 4 个请求（3.x 22 个）；不列短视频页 `/sv/`（C-19，`YyApi.isShortVideoPage`） | `yy_site.dart:109`、`:127`；`yy_api.dart:207` |
| 分区房间 | `/more/page.action`（`biz`、`subBiz`、`moduleId` 来自分区页 `pageInfo`，打开分区时读一次；3.x 存下的 `shortName` 直接用）；`moduleId: 0` 的服务端渲染分区第 1 页读分区页里的 `li[data-sid]` 卡片（`YyApi.pageRooms`），第 2 页起为空 | `yy_site.dart:165`、`:196`；`yy_api.dart:453` |
| 推荐 | `/more/page.action`（`biz=other`）；分区名先用分区页学到的，再查预置表 `YyApi.bizAreaNames`（10 项），都没有就留空 | `yy_site.dart:219`；`yy_api.dart:120` |
| 搜索 | `/apiSearch/doSearch.json?q=&t=&n=`（房间 `t=120`，每页 16 个，只有在播的；主播 `t=1`，直播状态取 `liveOn`）；空关键词不请求 | `yy_site.dart:235`、`:242`、`:247` |
| 详情 | `/api/liveInfoDetail/<sid>/<sid>/0`；不在播（`data: null`）时读房间页 `/<id>`：区分不存在（404 页 → `NotFound`）、短号（`asid` 换成规范频道号，房间号不变）、补未开播房间的主播名、头像、弹幕参数；占位名 `YY用户` 和默认头像不填（`YyApi.placeholderName`）；进房每次都读房间页，关注刷新、录制、开播状态每个房间号只读一次（最多记 4096 个） | `yy_site.dart:269`、`:286`、`:291`、`:300-315`；`yy_api.dart:141` |
| 清晰度和线路 | 默认先走移动 HLS `interface.yy.com/hls/new/get/<sid>/<ssid>/<1200 或 4000>`（两档并发）；没有流时问 `stream-manager.yy.com/v3/channel/streams`（POST，正文是 JSON 文本，类型 `text/plain`，匿名 `uid=0`）；`flvFirst` 打开时顺序反过来。FLV 每档按 `stream_line_list` 再请求其他 CDN 线路（`YyApi.otherLines`，实测 10 `tx-flv-web`、14 `ks-flv-web`），带 10 分钟租期（`YyApi.lease`，提前 1 分钟续期） | `yy_site.dart:334`、`:368`、`:378`、`:388`、`:403`、`:465`；`yy_api.dart:714`、`:772` |
| 画质 id 换算 | `YyApi.flvQualityId`：打开 `flvFirst` 后把存下的移动 HLS 画质 id 换成同档 FLV 的 id（4000 是 gear 2 高清，1200 是 gear 1 流畅） | `yy_api.dart:756` |
| 链接 | `www.yy.com/<sid>`、`www.yy.com/<sid>/<ssid>`、手机页 `wap.yy.com/mobileweb/<sid>/<ssid>`；`0` 和前导零不是房间，`/music/` 这类页面不是房间 | `yy_site.dart:511` |

弹幕（应用 103 的 `3139586` 上报房间热度，和列表、详情的 `users` 同一口径）归 [D01.7](../../../D-弹幕/D01-平台弹幕协议/D01.7-YY直播弹幕/README.md)，本任务只给 `YyDanmakuArgs`（`topSid`、`subSid`）。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/yy/yy_site.dart`） | 现在（`packages/live_core/lib/src/sites/yy/`） | 说明 |
|---|---|---|---|
| 分类 | `getCategores` `:135-158`、`getSubCategores` `:180-217`：一级分类并发，18 个分区页逐个读；一个分区页失败，整个一级分类的分区都没了 | `yy_site.dart:109` | 4 个请求，分区打开时再读分区页（6-5）；3.x 存下的 `shortName` 照旧直接用；“小视频”不再列出（C-19） |
| 分区 | `getCategoryRooms` `:221`，没有参数的分区打开就 HTTP 400 | `yy_site.dart:196` | 打开时读分区页；服务端渲染的分区读卡片（2026-10-01 修，手机直播 18 个、综合 2 个；英雄联盟页面里没有卡片，仍为空） |
| 推荐和详情的分区 | `getRecommendRooms` `:570`、`_fetchRoomDetail` `:694`：显示原始 `biz`（推荐全是 `other`） | `yy_api.dart:120` | 学到的名字或预置表（`sing` 音乐、`dance` 舞蹈等 9 个，C-21；S02.1 又补 `zonghe` 综合，共 10 个），否则为空（6-3） |
| 标题 | 默认标题带“ 正在直播” | 去掉后缀（`YyApi.liveSuffix`） | 6-2 |
| 详情 | `getRoomDetail` `:635`、`_fetchRoomDetail` `:665`：`:677-680` `data` 不是对象就当未开播，不存在的房间和短号永远显示未开播 | `yy_site.dart:269`、`:300` | 进房和关注刷新都区分不存在、短号（6-8）；未开播也给弹幕参数（6-7）；占位主播名不填（2026-10-01 D3） |
| 取流 | `getPlayQualites` `:437`、`getPlayUrls` `:503`；`getLiveStreamObj` `:286-357` 的 stream-manager 正文被表单编码，从未成功；`parsePlayQualities` `:451-500` 列出网页播不了的“超清” | `yy_site.dart:403`、`:465` | 移动 HLS 照旧优先；stream-manager 修好并只列有 `stream_key` 的档，按应答报告实际档位，补第二条 CDN 线路（6-4） |
| 搜索 | `searchRooms` `:708`，搜索卡片的分区读不存在的 `biz` | `yy_site.dart:235` | 用结果里的 `category` |
| 主播搜索 | `searchAnchors` `:754`，直播状态取 `liveOn` | `yy_site.dart:242` | 6-6 核实后保留 `liveOn`（共用频道里主播本人没播时为 false 是对的） |
| 弹幕 | `getDanmaku()` `:27` | `packages/live_danmaku/lib/src/sites/yy.dart`、`sites/yy/`（D01.7） | 应用 103 的 `3139586` 上报热度（2026-10-01 D4） |

## 结果

- 首次重构（2026-09-28，提交 `df90a0156`，当天 `784ca749e` 改回 3.x 的移动 HLS 优先和刷新请求数）：3.x 已经不能构建，补写了 `fixtures/yy/legacy_expected.dart` 生成冻结输出；14 个 3.x 问题、12 条有意差异见 record.md。保留 3.x 的移动 HLS 优先、媒体请求带用户 Cookie、主播搜索用 `liveOn`。
- 升级落地（2026-09-29，`4a825d7da`）：6-1 `YySite(flvFirst:)`（默认关，画质 id 换算用 `YyApi.flvQualityId`）；6-2 去掉“正在直播”；6-3 分区留空；6-4 FLV 第二条线路；6-5 分类 4 个请求；6-6 核实后保留 `liveOn`；6-7 未开播给弹幕参数；6-8 关注刷新区分不存在和短号；开播时间取 `startTime`（`YyApi.startedAt`）。
- 国内平台完善（2026-10-01，`c991163f0`）：修了服务端渲染分区为空（D1）、小视频报错（D2）、占位主播名“YY用户”（D3）、弹幕不更新人数（D4）。附录 C（`393de73fc`）：去掉小视频（C-19）、预置分区名（C-21）；C-18、C-20 没做（见“留下的问题”）。真机问题修复（2026-10-01，`dfcb14000`，S02.1）预置表补上 `zonghe` → 综合。
- 测试：`packages/live_core/test/sites/yy_api_test.dart` 38 个 `test(` 写法、`yy_site_test.dart` 39 个（record.md 按实际用例统计 90 个，含循环生成的）；弹幕 `packages/live_danmaku/test/sites/yy_test.dart` 31 个 `test(` 写法（record.md 统计 68 个用例）。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出，6-2、6-3、6-5、6-7、C-19、C-21 的变化用 `changed:` 列出；stream-manager 请求正文能按 JSON 解析（REG-YY-003）；只列有 `stream_key` 的档、按应答报告实际档位（REG-YY-004）；短号、不存在、请求数都有断言；`flvFirst` 打开和关闭两种顺序、每种失败时的兜底。
- 真实接口：2026-09-28 实测表单正文 4 次 HTTP 500、JSON 正文 200；2026-09-30 20:35 UTC（直连、匿名）跑了推荐、分类、全部分区、搜索、3 个在播和 1 个未开播房间、两种取流（`flvFirst` 下 3 个房间每档都有两条 FLV 线路）、两个房间各 2 分钟弹幕；2026-10-01 在官网直播间核对热度（C-18），读了 18 个分区页和 298 个在播详情核对预置表（C-21）。都是直连，不用代理。
- 真机：播放在 K90 上看过（2026-10-01 两轮真机测试，[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节 YY 一行“播放：完成，K90 看过”；弹幕只写“完成”，没在 K90 上专门看）；`flvFirst` 应用还没打开，FLV 播放和续签没在真机看过。

## 留下的问题

- 6-1 FLV 优先只做完平台层：应用在 `app/platforms.dart:160` 建 `YySite` 时没传 `flvFirst`，存下的 YY 画质 id 也还没用 `YyApi.flvQualityId` 换算 → [E06.3](../../E06-平台层升级/E06.3-YY优先用FLV/README.md)（先在 K90 上看 FLV 续签）。
- C-18（UPGRADES 附录 C）：弹幕 `3165186` 的小计数（2050 对热度 146 万）是不是在线人数核对不了，官网直播间只显示热度 → 受阻，未排，没有任务管。
- C-20（UPGRADES 附录 C）：礼物在应用 15012，是新的二进制格式，样本还带设备信息要逐字段脱敏 → 受阻，未排，没有任务管（做时归 D01.7）。
- `chicken` 被和平精英、天天吃鸡、综合游戏、无畏契约 4 个分区共用，详情里没有 `subBiz`，这类房间直接进房时分区仍为空；英雄联盟分区页现在没有房间卡片，列表为空：没有任务管。
- 受限类型：YY 没有相关字段，`restriction` 一律不填；不需要处理。
