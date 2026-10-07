# E02.1 YY 直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 6-1～6-8）、国内平台完善（2026-10-01）和附录 C 落地（C-18～C-21）都记在 [record.md](record.md)
- 旧编号：M4.06、M4.U.6、T02b.1
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；弹幕 D01.7；FLV 续签和线路切换在 G 组；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/yy/`（`yy_api.dart` 965 行解析，`yy_site.dart` 520 行请求编排）；样本 `fixtures/yy/`（36 组，含 `legacy_expected.dart` 补出的 3.x 冻结输出和弹幕样本）

## 目标

把 3.x 的 YY 适配器（`lib/core/site/yy/yy_site.dart` 792 行）重构进 `live_core`，分类、分区、推荐、搜索、详情、清晰度和线路、链接都和 3.x 用户实际看到的一样（默认仍是匿名移动 HLS 两档“高清 · 720p”“流畅 · 360p”）。修掉 3.x 的 14 个问题，其中最重要的是 stream-manager 请求从来没成功过（正文被 Dio 表单编码，服务器一律 HTTP 500），修好后作为 FLV 兜底和以后的“FLV 优先”。

## 平台接口要点

| 功能 | 接口（`www.yy.com` 除非另写） | 位置 |
|---|---|---|
| 分类 | `/yyweb/module/data/header` + 3 个 `/c/yycom/category/getCategory.action?parentId=`，共 4 个请求（3.x 22 个）；不列短视频页 `/sv/`（C-19） | `yy_site.dart:109-128` |
| 分区房间 | `/more/page.action`（`biz`、`subBiz`、`moduleId` 来自分区页 `pageInfo`，打开时读一次）；`moduleId: 0` 的服务端渲染分区第 1 页读分区页里的 `li[data-sid]` 卡片 | `:196-221` |
| 推荐 | `/more/page.action` | `:219` |
| 搜索 | `/apiSearch/doSearch.json?q=&t=&n=`（房间 `t=120`，主播 `t=1`，主播的直播状态取 `liveOn`）；空关键词不请求 | `:235-251` |
| 详情 | `/api/liveInfoDetail/<sid>/<sid>/0`；进房时再读房间页 `/<id>`：区分不存在（404 页 → `NotFound`）、短号（`asid` 换成规范频道号，房间号不变）、补未开播房间的主播名、头像、弹幕参数；关注刷新遇到 `data: null` 时每个房间号读一次房间页（最多记 4096 个） | `:276`、`:287`、`:300-315` |
| 清晰度和线路 | 默认先走移动 HLS `interface.yy.com/hls/new/get/<sid>/<ssid>/<1200 或 4000>`；`flvFirst` 打开时先问 `stream-manager.yy.com/v3/channel/streams`（POST，正文是 JSON 文本，类型 `text/plain`），FLV 每档按 `stream_line_list` 再请求第二条 CDN 线路，带 10 分钟租期（提前 1 分钟续期，不断开） | `:344`、`:391`、`:403-465` |
| 链接 | `www.yy.com/<id>`、手机页 `wap.yy.com/mobileweb/<sid>/<ssid>`；`0` 和前导零不是房间 | `:511` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/yy/yy_site.dart`） | 现在 | 说明 |
|---|---|---|---|
| 分类 | `getCategores` `:135`，17 个分区页串行，一个失败整个一级分类的分区都没了 | `yy_site.dart:109` | 4 个请求，分区打开时再读分区页（6-5）；3.x 存下的 `shortName` 照旧直接用 |
| 分区 | `:221`，没有参数的分区打开就 HTTP 400 | `:196` | 打开时读分区页；服务端渲染的分区读卡片（2026-10-01 修，手机直播 18 个、综合 2 个） |
| 推荐和详情的分区 | 显示原始 `biz`（推荐全是 `other`） | 学到的名字或预置表（`sing` 音乐、`dance` 舞蹈等 9 个，C-21），否则为空 | 6-3、C-21 |
| 标题 | 默认标题带“ 正在直播” | 去掉后缀 | 6-2 |
| 详情 | `:635`，`:676-679` 不存在显示未开播；`:668` 短号永远未开播 | `:300` | 进房和关注刷新都区分不存在、短号（6-8）；未开播也给弹幕参数（6-7） |
| 取流 | `getPlayQualites` `:437`、`getPlayUrls` `:503`；`:290-353` stream-manager 正文被表单编码从未成功；`:451-497` 列出网页播不了的“超清” | `:403-465` | 移动 HLS 照旧优先；stream-manager 修好并只列有 `stream_key` 的档，按应答报告实际档位 |
| 搜索 | `:708`，搜索卡片分区读不存在的 `biz` | `:235` | 用结果里的 `category` |
| 弹幕 | `getDanmaku()` `:27` | `live_danmaku/lib/src/sites/yy.dart`、`sites/yy/`（D01.7） | 应用 103 的 `3139586` 上报热度（2026-10-01） |

## 结果

- 首次重构（2026-09-28，提交 `df90a0156`，当天 `784ca749e` 改回 3.x 的移动 HLS 优先和刷新请求数）：3.x 已经不能构建，补写了 `fixtures/yy/legacy_expected.dart`（3.x 解析部分的逐行转写）生成冻结输出；14 个 3.x 问题、12 条有意差异见 record.md。保留 3.x 的移动 HLS 优先、媒体请求带用户 Cookie、主播搜索用 `liveOn`。
- 升级落地（2026-09-29，`4a825d7da`）：6-1 `YySite(flvFirst:)`（默认关，G 能按租期续签后再开，画质 id 换算用 `YyApi.flvQualityId`）；6-2 去掉“正在直播”；6-3 分区留空；6-4 FLV 第二条线路；6-5 分类 4 个请求；6-6 核实后保留 `liveOn`（共用频道里主播本人没播）；6-7 未开播给弹幕参数；6-8 关注刷新区分不存在和短号；开播时间取 `startTime`。
- 国内平台完善（2026-10-01，`c991163f0`）：修了服务端渲染分区为空（D1）、小视频报错（D2）、占位主播名“YY用户”（D3）、弹幕不更新人数（D4）。附录 C（`393de73fc`）：去掉小视频（C-19）、预置分区名（C-21）；C-18 小计数是不是在线人数核对不了，C-20 礼物来自另一个服务（应用 15012），没做。真机问题修复时（2026-10-01，`dfcb14000`，S02.1）预置表补上 `zonghe` → 综合。
- 测试：`packages/live_core/test/sites/yy_api_test.dart` 38 个 `test(` 写法、`yy_site_test.dart` 39 个（record.md 统计 90 个用例）；弹幕 `packages/live_danmaku/test/sites/yy_test.dart` 68 个。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出，6-2、6-3、C-19、C-21 的变化用 `changed:` 列出；stream-manager 请求正文能按 JSON 解析（REG-YY-003）；短号、不存在、请求数都有断言。
- 真实接口：2026-09-28 实测表单正文 4 次 HTTP 500、JSON 正文 200；2026-09-30 跑了推荐、分类、全部分区、搜索、3 个在播和 1 个未开播房间、两种取流、两个房间各 2 分钟弹幕；2026-10-01 在官网直播间核对热度（record.md）。
- 真机：播放 K90 看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）；`flvFirst` 还没打开，不用看。

## 留下的问题

- `flvFirst` 默认关：等 G 组播放器能按 `PlayLease` 续签 FLV、真机验证后再打开（6-1）。
- 弹幕 `3165186` 的小计数是不是在线人数核对不了（C-18）；礼物在应用 15012、格式未知（C-20）。
- `chicken` 被 4 个分区共用，详情里没有 `subBiz`，这类房间的分区仍为空。
- 受限类型：YY 没有相关字段，`restriction` 一律不填。
