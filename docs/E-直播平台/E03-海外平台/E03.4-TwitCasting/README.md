# E03.4 TwitCasting

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 12-1～12-5）记在 [record.md](record.md)；评论由 D01.12 接上
- 旧编号：M4.12、M4.U.12、T02c.4
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)（频道名不分大小写）；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；评论 D01.12（用 `TwitcastingDanmakuArgs`）；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/twitcasting/`（`twitcasting_api.dart` 841 行解析和私有 HTML 读取器 `_Html`，`twitcasting_site.dart` 335 行请求编排）；样本 `fixtures/twitcasting/`（19 组，含评论帧 `danmaku/S08-live`）

## 目标

把 3.x 的 TwitCasting 适配器（`lib/core/site/twitcasting/` 两个文件共 508 行，用 `package:html`）重构进 `live_core`：分类、推荐和分区（60 条窗口）、搜索、频道页加 `streamserver.php` 的详情、HLS 取流、链接都和 3.x 一样（全部匿名）。修掉 3.x 的 11 个问题（搜索遇到私密直播整页失败、不存在的频道报“结构变化”、详情标题是 “Live #841525457”、档位地址不对整个详情失败、恢复时重读约 110 KB 的频道页、房间号被改成小写等）。

## 平台接口要点

| 功能 | 接口（全部带 3.x 的 `playHeaders`：`Referer: https://twitcasting.tv/`、`Origin`、UA `Mozilla/5.0`；以 `twitcasting` 的名义发出） | 位置 |
|---|---|---|
| 分类 | 首页 `a.tw-top-tab-item[data-channel]`，只有第 1 页 | `twitcasting_site.dart:113` |
| 推荐、分区 | `frontendapi.twitcasting.tv/top/category?id=&count=60`：站点只给一个 60 条的窗口，第 1 页请求、之后 30 秒内从同一份回答里切；开播时间是回答到达时刻减 `elapsed_time` | `:122-152` |
| 搜索 | `search.twitcasting.tv/search/text/<关键词>?hl=en` 的直播段（最多 50 条），第 1 页请求、30 秒内翻页用快照（12-4）；私密直播标直播中 + `private`（12-5）；频道链接直接查频道 | `:165-179` |
| 详情 | 先频道页（不跟随跳转：不存在的频道 302 到首页 → `NotFound`），再 `twitcasting.tv/streamserver.php`；未开播只看 `movie.live`（未开播的回答里带着另一场的地址，一律丢弃）；标题取频道页的副标题（telop，12-1）；关注刷新和开播状态只请求 `streamserver.php`（约 1 KB，12-2） | `:242-271` |
| 画质和线路 | `tc-hls.streams` 每档一个画质：`HLS high`、`HLS medium`、`HLS low`；档位在取流时才校验；恢复只请求 `streamserver.php`；线路带 3.x 播放层的请求头，HLS 媒体列表要会话 Cookie（REG-TWITCASTING-002） | `:284-303` |
| 弹幕参数 | 在播房间的 `TwitcastingDanmakuArgs`（频道、本场 `movieId`），评论地址 `eventpubsuburl.php` | |
| 链接 | `twitcasting.tv/<频道>` 等，房间号保持请求时的写法，请求用小写 | `:331` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/twitcasting/`） | 现在 | 说明 |
|---|---|---|---|
| 搜索遇到私密直播 | `twitcasting_api.dart:299-312` 整页失败 | 私密直播标 `private`，其余照常 | 3.x 问题 1；12-5 |
| 不存在的频道 | `:36-50` dio 跟随 302 到首页，报“结构变化” | `NotFound`，链接搜索为空 | 3.x 问题 2 |
| 详情标题 | `:370` 只读 `twitter:title`（“Live #841525457”），列表显示 telop，进房后标题变 | 副标题（telop） | 12-1（REG-TWITCASTING-004） |
| 档位校验 | `:384-411` 在详情里校验，地址不对时进房、刷新、录制都失败 | 取流时才校验 | 3.x 问题 4 |
| 关注刷新 | 频道页（约 110 KB）+ `streamserver.php` | 只 `streamserver.php`（昵称、头像要进房才更新） | 12-2 |
| 恢复 | `twitcasting_site.dart:84-93` 重读整个房间 | 只 `streamserver.php` | 3.x 问题 7 |
| 房间号 | `:130`、`:343` 改成小写 | 保持请求时的写法，比较不分大小写 | 3.x 问题 8 |
| 推荐翻页、搜索翻页 | 每页都重新请求同一个窗口或网页 | 30 秒快照 | 12-4 |
| 口令直播 | 频道页就报 `NeedsLogin` | 再请求 `streamserver.php`，在播就是直播中 + `password` | 统一原则 |
| 页面解析 | `package:html` | 私有的 `_Html` 读取器（不加依赖） | |
| 评论 | `EmptyDanmaku` | `live_danmaku/lib/src/sites/twitcasting.dart`（D01.12） | 12-3 |

## 结果

- 首次重构（2026-09-28，提交 `2badf4756`）：11 个 3.x 问题、11 条有意差异见 record.md。
- 升级落地（2026-09-29，`cbff9fd76`）：12-1～12-5 完成（12-3 平台层给参数，评论在 D01.12）；开播时间三处都有（推荐卡片按 `elapsed_time`、搜索、详情），不多发请求；受限类型 `password`、`private`、`unplayable`；列表和搜索的坏行只跳过这一行。
- 测试：`packages/live_core/test/sites/twitcasting_api_test.dart` 41 个 `test(` 写法、`twitcasting_site_test.dart` 38 个；评论 `packages/live_danmaku/test/sites/twitcasting_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出；私密直播、不存在的频道、telop、未开播丢弃别场地址、刷新只一个请求、快照、口令直播。
- 真实接口：2026-09-28（UTC）直连读了首页的 22 个分类窗口（837 行）、约 70 个关键词的搜索页、20 多个频道页和 `streamserver.php`。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）；海外平台要用户开着代理。

## 留下的问题

- 口令（合言葉）直播没有样本（837 行列表的 `is_locked` 全是 false）；`is_group` 含义不清，照 3.x 跳过。
- 搜索页的 Premier（付费）段 3.x 不读，这次也没接（表外的新内容）。
- 关注刷新不再更新昵称、头像、标题，要进一次房间才更新（12-2 的代价）。
- `_Html` 和 `live_core/lib/src/html.dart` 的 `HtmlElement`、克拉克拉的 `_Html` 是三套 HTML 读取器，可以合并（Z 组的维护任务）。
