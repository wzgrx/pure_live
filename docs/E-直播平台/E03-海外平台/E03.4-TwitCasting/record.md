# E03.4 TwitCasting

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/twitcasting/`（`twitcasting_api.dart` 纯解析，`twitcasting_site.dart` 请求编排）
- 样本：`fixtures/twitcasting`，12 个真实接口录制和 1 组评论帧，全部来自归档（2026-09-27 直连录制）：
  - 首页 `S01-home`、目录 `S02-top-all`/`S02-top-game`、搜索 `S03-search`；
  - 频道页 `S04-page-*` 与 `streamserver.php` 的 `S05-stream-*`，各有在播、未开播、不存在三种；
  - HLS 媒体列表 `S06-media`（带会话 Cookie）、评论地址 `S07-pubsub`、评论帧 `danmaku/S08-live`（D01 用）。
- 参考：
  - 归档 v4 的 TwitCasting 适配器和规格（`spec/sites/twitcasting.md`，回归条目 REG-TWITCASTING-001～004）；
  - pure_live_TV `fbbe6521`：与 v3 相同，只是去掉可空标注、平台名多语言化、`room.data =` 改成 `copyWith`（对照笔记 `small_diffs.txt`、`sub_C.md`），没有行为修复。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。

## 做法

- **接口和输出沿用 v3**：`LiveSite`、`LiveRoom` 等模型和 3.x 的 JSON 不变。v3 实现过的可选能力全部保留：刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、恢复（`LivePlayRecoveryResolver`）、可取消的搜索（`LiveCancellableSearch`）。另加 `LivePlayUrlResolver`（线路要带请求头）和 `LiveSiteLinks`。v3 没有目录分页接口（它的页面自己切窗口），这里也不加。
- **请求照 v3**：
  - 所有请求（包括媒体）都带 v3 的 `playHeaders`：`Referer: https://twitcasting.tv/`、`Origin`、`User-Agent: Mozilla/5.0`，不带 `Accept-Language`。2026-09-28 用这组请求头实测首页，分类名与样本（录制时带 `Accept-Language: en`）完全相同，都是英文；
  - 分类：首页 `a.tw-top-tab-item[data-channel]`，只有第 1 页；
  - 推荐、分区：`frontendapi.twitcasting.tv/top/category?id=…&count=60`，站点只给这一个 60 条的窗口。每次都取整个窗口，再按 `page`、`pageSize`（1～60）切出一页；窗口之后的页直接返回空，不发请求。v3 的热门页、分区页只要第 1 页、每页 60 条，再在页面里切（M13）；
  - 搜索：`search.twitcasting.tv/search/text/{关键词}?hl=en` 的直播段，最多 50 条，每页（1～50）都重新请求一次，同 v3。输入是频道链接时直接查这个频道（未开播也返回），其他 TwitCasting 链接返回空；
  - 详情：先请求频道页，再请求 `streamserver.php`，顺序同 v3（频道页不对就不再请求第二个）。频道页**不跟随跳转**：站点把不存在的频道 302 到首页。
- **所有请求都以 `twitcasting` 的名义发出**，代理路由由应用按平台注入（live_net 的 `ProxyPolicy`），适配器不读设置。v3 的 TwitCasting 全部匿名，没有 Cookie、没有登录，所以不注入 `CookieVault`。
- **画质和线路照 v3**：`streamserver.php` 的 `tc-hls.streams` 每档一个画质，名称 `HLS high`、`HLS medium`、`HLS low`，排序 3、2、1；每档一条 HLS 线路，线路编号是节点主机名，带上面的媒体请求头。地址没有签名和有效期，所以没有 `PlayLease`。
- **档位在取流时才检查**：详情只记下 `movie.live`、`movie.id` 和原样的 `tc-hls.streams`（`TwitcastingRoomData`），`getPlayQualities` 时再按 v3 的规则校验（https、`*.twitcasting.tv`、路径属于本场直播）。v3 在详情里就校验，档位不对连房间页都打不开，关注刷新也跟着失败。
- **未开播只看 `movie.live`**：未开播的回答里带着另一场直播的地址（S05-stream-offline：`movie.id` 841421279，地址却是 841532464），一律丢弃（REG-TWITCASTING-001）。
- **房间号保持请求时的号码**，请求用小写的频道名；`userId` 和 `link` 用小写频道名。v3 把房间号改成小写。
- **没有弹幕参数**：v3 的 TwitCasting 没有评论（`EmptyDanmaku`）。本场直播的 `movie.id` 在 `TwitcastingRoomData` 里，将来做评论（升级候选）时可以直接用。
- **页面解析不引入新依赖**：v3 用 package:html 解析首页、搜索页和频道页。`live_core` 没有这个依赖，这里写了一个只够用的私有读取器（`_Html`：标签、class、属性、后代，先把脚本、样式和注释抹成空白，换行按 HTML 的规则归一），按 v3 的选择器逐个取值。和 v3 的输出逐键对照一致（见下）。

## 审查发现的 v3 问题

位置简写：`api` = `legacy/lib/core/site/twitcasting/twitcasting_api.dart`，`site` = 同目录的 `twitcasting_site.dart`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 关键词匹配到私密直播时，整页搜索失败（样本 S03：搜 `game`，15 行里第 3 行是私密直播） | api:299-312 | 站点把私密直播也放在“Live”段里，徽标是 “Private”、`data-status=""`、`data-can-play="false"`；v3 把没有 LIVE 徽标或不能播放的行都当成结构变化，抛出 schema | 跳过不能播放的行，其余照常显示（只在 v3 失败的地方兜底）；链接不对的直播行仍是 `ApiChanged` |
| 2 | 不存在（已删除）的频道报“结构变化”，不是“不存在”；用频道链接搜索这类频道时报错，而不是没有结果 | api:36-50, 275-280, 344-350, 362 | dio 默认跟随跳转，频道页 302 到首页，首页的 `twitter:creator` 是 `@twitcastinglive`，`channelName` 抛 schema；`streamserver.php` 回答 `{}`，`object(null)` 也是 schema。链接搜索只把 `notFound` 当成没有结果 | 频道页不跟随跳转，3xx 是 `NotFound`；`{}` 是 `NotFound`；链接搜索得到空结果（v3 的本意，它的测试就是 404 → 空） |
| 3 | 房间标题是 “Live #841525457”，主播设的副标题（telop）不显示；同一个房间在列表里显示 telop，进房和关注刷新后又变成 “Live #…” | api:370（详情）、api:244（列表） | 详情只读 `twitter:title`，列表先读 `telop` | 按规则保持 v3（用户看到的标题）：只在 `twitter:title` 为空时用 `twitter:description`（telop）。改成 telop 优先列为升级候选 1（REG-TWITCASTING-004） |
| 4 | 档位地址不对时整个详情失败：房间页打不开，关注刷新、录制详情也失败 | api:384-411；site:58-63 | 详情里就校验档位；刷新和录制都用完整详情 | 详情不校验档位，取流时再校验（`ApiChanged`）；刷新只要状态和资料 |
| 5 | 未开播的房间取画质得到空列表，播放器拿不到原因 | site:70 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 6 | 没有详情数据的房间（列表卡片）取画质报 schema | site:71 | 只从 `detail.data` 读 | 请求一次 `streamserver.php` |
| 7 | 恢复时重新读整个房间：频道页约 110 KB，再加 `streamserver.php` | site:84-93 | 用 `getRoomDetail` 取新地址 | 只请求 `streamserver.php`，少一个请求；保持“不悄悄降档”：新直播没有原来的档位就 `StreamUnavailable` |
| 8 | 房间号被改成小写，用大写号码关注的房间刷新后身份对不上 | api:130, 343；site:53-56 | 以规范化后的频道名为房间号 | 保持请求时的号码，请求用小写频道名 |
| 9 | 调用方传错页码、每页条数、分区或超长关键词，报的是“结构变化” | api:196-202, 264-266；site:31-36, 54, 69 | 所有校验失败都用 schema | 调用方错误是 `ArgumentError`，同 v3 一样不发请求 |
| 10 | 状态码分类粗：3xx 等都算传输错误；401/403 和口令直播共用一个 `access` | api:86-94, 345 | — | 401/403 `RiskControl`，404 `NotFound`，429 `RateLimited`，其他 `NetworkFailure`；口令直播 `NeedsLogin`；取消仍是取消 |
| 11 | 平台层依赖全局 `HttpClient`，自己实现流式读取（1 MiB 上限、20 秒总时限）；媒体请求头在播放层按平台写 | api:36-73；`player/core/playback_header_resolver.dart:153-154` | 结构问题 | 注入 `LiveHttp`（20 秒总时限由 live_net 负责）；线路自带请求头 |

## 样本与 v3 的冻结输出

归档没有 TwitCasting 的 `expected.json`：归档的旧版对照工具只做了前五个平台，v3 应用现在也构建不了（规格 §11 也写明没有）。本模块用 `fixtures/twitcasting/legacy_expected.dart` 生成，做法同网易 CC：

- 把 v3 的 `twitcasting_api.dart`、`twitcasting_site.dart` 原样搬进一个 Dart 脚本，只把网络换成按主机、路径和 `target` 读样本，并像 dio 一样跟随录下的跳转（最多 5 次）；没有样本的请求抛 StateError；
- v3 `LiveRoom`、`LivePlayQuality` 用到的部分（构造默认值、`toJson`）一并搬入；输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`）；
- v3 用 package:html 解析页面，工作区不依赖它，所以脚本用临时的包配置运行，命令写在脚本开头：建一个只依赖 `html: 0.15.6` 的临时目录，`dart pub get` 后用 `dart --packages=… fixtures/twitcasting/legacy_expected.dart` 运行。这个依赖只用于生成期望值，不进任何包。

7 个样本有 `expected.json`：

| 样本 | 内容 |
|---|---|
| `S01-home` | 分类（第 1、2 页） |
| `S02-top-all` | 热门页的请求（第 1 页、每页 60）、第 2 页、每页 20 的切片 |
| `S02-top-game` | “Game” 分区页的请求（第 1、2 页，每页 60） |
| `S03-search` | 每页 20 的第 1～4 页；另有 `withoutPrivateRow`：去掉那一行私密直播后 v3 的结果，作为其余各行的逐字段参照 |
| `S04-page-live`、`S04-page-offline`、`S04-page-notfound` | 与对应的 `S05-stream-*` 一起：进房、刷新、频道链接搜索、画质和每档地址 |

`S05-stream-*`、`S06-media`、`S07-pubsub` 没有单独的 `expected.json`：前者随 `S04-page-*` 一起回放，后两个 v3 不请求（`S06` 是 REG-TWITCASTING-002 的依据，`S07`、`S08` 留给 D01）。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序和每档地址。

| 样本 | 结果 |
|---|---|
| S01 分类 | 一致：1 个分类 “TwitCasting”，18 个分区（Popular、KawaVo、Music…Twitcast Games），顺序、id、名称都一致。v3 的 `shortName`、`areaPic` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S02 推荐（45 条）、分区（56 条） | 一致，包括标题（telop 优先）、在线人数、封面补 `https:`；第 2 页（60 条之后）都是空；每页 20 的切片 20、20、5、0 条一致 |
| S03 搜索 | v3 第 1 页整页失败（问题 1），新代码给出 14 条，与 `withoutPrivateRow` 逐字段一致；第 2～4 页都是空，一致 |
| S04/S05 在播 | 进房、刷新、频道链接搜索三处都一致，标题是 “Live #841525457”；3 档画质的名称、id、排序、地址一致 |
| S04/S05 未开播 | 房间一致；v3 取画质得到空列表，新代码是 `StreamUnavailable`（问题 5） |
| S04/S05 不存在 | v3 进房、刷新、链接搜索都是 schema 错误；新代码进房和刷新是 `NotFound`，链接搜索是空结果（问题 2） |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 搜索跳过不能播放的直播行（私密直播），其余照常显示 | 问题 1。v3 在这里整页失败，没有给出内容 |
| 2 | 不存在的频道是 `NotFound`；频道链接搜索这类频道得到空结果 | 问题 2 |
| 3 | 档位在取流时才校验；关注刷新和进房不因档位失败 | 问题 4。房间资料和状态与 v3 相同，只是失败的位置变了 |
| 4 | 未开播取画质报 `StreamUnavailable`；没有详情数据的房间取画质先请求 `streamserver.php` | 问题 5、6 |
| 5 | 恢复只请求 `streamserver.php`（1 个请求，v3 是 2 个） | 问题 7。新直播没有原档位时仍报错，不悄悄降档（同 v3） |
| 6 | 房间号保持请求时的号码 | 问题 8 |
| 7 | 调用方错误是 `ArgumentError`，其他错误是类型化的 `SiteError` | 问题 9、10 |
| 8 | `twitter:title` 为空时用 telop | 问题 3 的兜底；v3 这时标题为空 |
| 9 | 线路带媒体请求头，值与 v3 的 `PlaybackHeaderResolver` 相同 | 问题 11 |
| 10 | 不再有 1 MiB 的响应上限和严格的 UTF-8 校验 | 这是 v3 这个适配器自己的传输层（问题 11）；v4 的传输由 live_net 统一负责，20 秒总时限相同，非法 UTF-8 按替换字符处理。首页已有约 600 KB，上限只会让它将来变大时整个分类失败 |
| 11 | 图片地址用通用的 `normalizeImageUrl` | 所有平台共用。v3 的 `picture` 会丢掉带用户名的地址、不补无协议的地址；样本里的图片结果完全相同 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **详情标题用 `twitter:title`**（“Live #…”），不优先用 telop。归档 v4 优先 telop（REG-TWITCASTING-004），会改变进房和关注卡片上的标题，列为升级候选 1。
- **请求头照 v3**：`Mozilla/5.0`、`Referer`、`Origin`，没有 `Accept-Language`。归档 v4 用桌面 Chrome UA 加 `Accept-Language: en`、不带 `Origin`；两种请求头下站点给的分类名相同。
- **画质名称 `HLS high`、`HLS medium`、`HLS low`**。归档 v4 叫“高、中、低”，会改变画质菜单。
- **列表按 v3 的窗口切片**：每页从原始 60 行里切，切完再过滤（加锁、群组、已删除、已结束、重复的频道），所以一页可能不满。归档 v4 一次返回整个窗口，没有页码。
- **列表的严格校验**：有一行字段不对（开关不是布尔值、频道名、直播号、`live_url`、在线人数）就整个列表 `ApiChanged`，不返回空列表或残缺列表（v3 的测试固定了这一点）。归档 v4 跳过坏行。
- **频道页必须和频道对得上**：`twitter:creator` 恰好一个且等于频道、页头 `data-user-id` 等于频道，都是 v3 的检查。归档 v4 不查页头。
- **搜索每页都重新请求**：站点一页给全部结果（最多 50 条），v3 翻页时重复请求同一页；这里请求次数与 v3 相同。
- **没有开播时间**：归档 v4 用 `elapsed_time` 算开播时间，3.x 的 `LiveRoom` 没有这个字段。
- **没有评论**：归档 v4 做了评论（`eventpubsuburl.php` → wss），v3 没有，列为升级候选 3。
- **平台名 “TwitCasting”**，同 v3；上游改成了多语言文字（M13）。

## 后续升级候选（待用户确认）

1. **详情标题优先用 telop**（REG-TWITCASTING-004）：进房和关注卡片与列表一致，显示主播设的副标题，没有时再用 “Live #…”。改一行即可。
2. **关注刷新只请求 `streamserver.php`**：约 1 KB，代替约 110 KB 的频道页；状态照常更新，标题、头像由 `mergeFrom` 保留旧值，不再随刷新更新。
3. **评论（弹幕）**：匿名 POST `eventpubsuburl.php`（表单 `movie_id`）拿到 wss 地址，收 JSON 评论；样本 `S07-pubsub`、`danmaku/S08-live` 已复制，直播号在 `TwitcastingRoomData.movieId`（D01）。
4. **搜索只请求一次**：第 1 页就拿到全部结果，翻页在本地切，省掉第 2、3 页的重复请求。
5. **私密直播在搜索里显示为不可播放**，而不是跳过（需要界面上的标识）。

## 回归条目的覆盖

- 001（未开播时忽略旧地址）：未开播的 `TwitcastingRoomData` 不保留任何地址；未开播的房间取画质不发请求就是 `StreamUnavailable`；恢复时站点说未开播也是 `StreamUnavailable`。有测试。
- 002（分片需要会话 Cookie `lvhls_ssid_{movie}`）：这个 Cookie 由媒体列表的 `Set-Cookie` 下发（`S06-media`，`Path=/tc.livehls/v1/streams/{movie}/hls/`，10 分钟），线路的固定请求头表达不了。本模块保证线路不带任何 Cookie、没有租期（有测试）；播放时由 FFmpeg 回传列表下发的 Cookie，中继和录制自己拉分片时必须保存并按路径回传（G、H01.1，v3 的录制用 `HlsSessionCookies` 做到了）。
- 003（录像链接不是频道）：`/{id}/movie/{movie}` 不识别，链接搜索返回空，工具箱不自动识别。有测试。
- 004（标题是 “Live #…”）：按规则保持 v3，测试固定了现状；telop 只在标题为空时兜底；改法见升级候选 1。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 热门页、分区页只要第 1 页、每页 60 条，再在页面里切页（手机端连续加载、桌面端翻页和改每页条数都不再请求，刷新换新窗口）；v3 的 `twitcasting_directory_paging_test.dart` 中页面控制器的部分 | M13 热门页、分区页（本模块移植了适配器的部分：只请求一个 60 条窗口、过滤后 59 条、窗口之后不请求、分区 id 原样转发） |
| 分区页卡片的分区名（v3 由页面控制器写 `area = 分区名`） | M13 分区页 |
| 媒体列表下发的会话 Cookie 回传（REG-TWITCASTING-002） | G 播放、中继；H01.1 录制 |
| 搜索能力表（v3 标为“直播和未开播”、可翻页、有网页搜索；实际上文字搜索只有直播，未开播只能用频道链接查到）、网页搜索地址 `https://twitcasting.tv/search/text/?tw_search_query=…` | M13 搜索页 |
| 外部打开 `https://twitcasting.tv/{编码后的频道}` | M13 |
| 3.x 设置迁移：平台列表追加 TwitCasting（`siteCatalogMigration` 38）、真实在线人数的平台列表追加 TwitCasting（`audienceMetricMigration` 7） | J02.1 |
| 平台名、人数设置页里本平台的文字（`site_twitcasting`、`audience_twitcasting_detail`） | M13 多语言 |
| 多画面、直播间的弹幕：v3 不支持 TwitCasting | D01（升级候选 3） |
| 响应体大小上限（v3 在这个适配器里自己做了 1 MiB） | 如需要，由 live_net 统一提供（Q01.1 已完成，这里只记录） |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出。页面读取器 `_Html` 放在本平台文件里（私有）；以后别的平台也要按选择器读 HTML 时，再把它移到通用文件。

## 测试

66 个用例，`live_core` 共 821 个，全部通过：

- `twitcasting_api_test.dart`（36 个）：逐个样本对照 v3 的输出（分类、推荐、分区、切片、搜索、在播和未开播的详情、画质和每档地址），有意的差异逐条断言；移植了 v3 `twitcasting_adapter_test.dart` 中固定行为的部分（它的合成样本内联在测试里）：在线人数和频道身份、加锁/群组/已删除/已结束的行、每个字段缺失都是 `ApiChanged`、搜索只取直播段和 50 条窗口、畸形行、口令直播、频道页对不上、状态码、`movie.live`、跨场次和非法的档位地址、线路的请求头；频道名规则。
- `twitcasting_site_test.dart`（30 个），用样本回放加少量合成响应：
  - 能力、请求头、代理用的平台名；
  - 分类只有第 1 页；推荐和分区的窗口请求、第 2 页不请求；移植 v3 `twitcasting_directory_paging_test.dart` 的适配器部分；调用方错误不发请求；
  - 搜索的路径和编码、每页请求、50 条之后不请求；频道链接搜索（未开播、在播但档位坏了、不存在、录像链接、第 2 页）；取消传到请求、取消后不发请求、回答晚于取消被丢弃；
  - 详情：两个请求且频道页不跟随跳转、三种深度相同、房间号保持请求时的号码、未开播、不存在（302 和 `{}`）、非频道名不发请求、口令和别的频道只发一个请求、状态码和传输错误；
  - 取流：在播房间不发请求、线路、未开播不发请求、列表卡片请求 `streamserver.php`、恢复只请求一次并换到新直播、不悄悄降档、恢复时已下播、坏档位；
  - 链接（移植 v3 的链接用例和工具箱用例）、分享文本不发请求。

## 升级落地（T02.U）

- 日期：2026-09-29（E03.4）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 12-1～12-5；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。12-3（评论）的连接属于 D01，这里只在平台层给出它要的数据。
- 只改了本平台：`twitcasting_api.dart`（解析）、`twitcasting_site.dart`（请求编排）和两份测试。没有改 `live_core` 的通用文件，没有新依赖。新样本 5 个（见下文）。
- 实测：2026-09-29（北京时间，UTC 为 9-28）直连、匿名、用适配器的请求头，读了首页的 22 个分类窗口（837 行）、约 70 个关键词的搜索页和 20 多个频道页、`streamserver.php`，下面的结论都来自这些回答。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 12-1 | 详情标题改为本场的副标题（telop）：频道页播放器标题下面那行字 `span.tw-player-page-title-description`，只取它自己的文字，不取里面的话题标签（`_Html.ownText`）；没有副标题时仍用 `twitter:title`（v3 的“Live #…”）。**没有用 `twitter:description`**（归档 v4 和 E03.4 的兜底都用它）：实测没有副标题时它是频道的个人简介（新样本 S04-page-live-tags 是 “Rock;Star”，另有 `ツイキャスという配信サイトに居ます。` 等），拿来当标题会把简介显示成标题；所以 `twitter:title` 为空时标题留空（占位规则，关注里存下的标题不被覆盖），不再用它兜底 | 进房后标题显示主播设的副标题（S04 是 “クラッシュバンディクー３”，v3 是 “Live #841525457”）；没设副标题的仍是 “Live #…” 或主播设的标题。说明：分类列表接口的 `telop`、`title` 和频道页不是同一份数据（实测 12 个在播频道：列表有 `telop` 的 6 个，与频道页的副标题全都不同；列表没有 `telop` 的 6 个里，5 个频道页有副标题），所以列表卡片和房间页的标题仍可能不同，这是平台给的数据，适配器不能统一 | 完成（T02.U） |
| 12-2 | 关注刷新（`getRoomDetailForRefresh`）和 `getLiveStatus` 只请求 `streamserver.php`（约 1 KB；频道页约 110 KB）。刷新结果只有状态和本场直播（`TwitcastingRoomData`），名字、头像、封面、标题、开播时间、受限类型都留空，合并时关注里存的值不变（E05.2：状态变了时开播时间和受限类型清空）；进房（`getRoomDetail`）和录制仍读频道页，标题和头像在进房时更新（`TwitcastingApi.refreshRoom`） | 关注页刷新更快、流量小得多；主播改了昵称、头像、标题后，要进一次房间才更新；刚开播的关注卡片刷新后没有开播时间，进房后才有（轻接口不给） | 完成（T02.U） |
| 12-3 | 平台层：在播房间的详情带弹幕参数 `TwitcastingDanmakuArgs`（频道 `channel`、本场直播号 `movieId`，`eventpubsuburl.php` 的 `movie_id` 就是它），放在 `danmakuData`，不多发请求；未开播没有。刷新结果不带（弹幕只在进房时连） | 平台层看不出变化；评论在 D01 接入 | 平台层完成，余下 D01 |
| 12-4 | 搜索第 1 页请求一次，结果（最多 50 条）作为快照保存，之后的页在 30 秒内都从快照里切，不再请求；超过 30 秒、或再取第 1 页（下拉刷新）时重新请求。快照按关键词分开，最多留 16 份；取消的搜索不发请求，也不从快照返回 | 结果不变，翻页不再等待网络；第 2 页起的请求没有了（v3 每页都请求同一个网页） | 完成（T02.U） |
| 12-5 | 搜索里的私密直播（“Private” 徽标、`data-can-play="false"`）不再跳过：直播中、受限类型 `private`、带开播时间。站点不让播的其他行标 `unplayable`。这类卡片取流时直接报 `StreamUnavailable`（说明写原因），不发请求（`TwitcastingApi.restricted`）。**平台限制**：匿名时私密直播在频道页显示成录像（`data-live-type="movie"`）、`streamserver.php` 回答未开播（新样本 S03/S04/S05-private，5 秒内先后录下），所以进房和关注刷新看到的是“未开播” | 搜索结果里私密直播显示为直播中并标“私密”（界面在 M13），点播放时提示是私密直播；进房显示未开播（平台对未登录的客户端就是这样回答的） | 平台层完成，余下 M13 |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 三处都能取到，不多发请求：<br>- 推荐、分区卡片：回答到达时刻减 `elapsed_time`（秒），取整到秒（`TwitcastingApi.startedBefore`）。S02 的 nabo66game 算出 14:26:34 UTC，与频道页、搜索页给的完全相同。<br>- 搜索卡片：每行的 `time[datetime]`（`Sun, 27 Sep 2026 23:26:34 +0900`，`TwitcastingApi.pageDate` 换算成 UTC）。<br>- 详情：频道页计时器 `span#updatetimer` 的 `data-started-at`（毫秒），只在 `data-live-type="live"`、`streamserver.php` 说在播、且两边是同一场（`data-movie-id` 等于 `movie.id`）时填；未开播时页面上是上一场录像的时间，不填。<br>- 关注刷新：`streamserver.php` 不给，留空（同一场直播时合并保留存下的值） |
| 受限类型 | 列表：`is_locked`（口令）为 `password`，其余为 `none`。搜索：可播放的直播 `none`，私密 `private`，站点不让播的其他行 `unplayable`。详情：频道页要求口令时 `password`，否则在播就是 `none`——私密直播对匿名客户端从不显示为在播（见 12-5），所以能看到在播的就是能看的；未开播不填。关注刷新留空（`streamserver.php` 看不出）。取流：带着本场直播数据的房间以数据为准（口令直播报 `StreamUnavailable`，说明写 `password-protected`）；没有直播数据、但卡片标了受限的，直接报 `StreamUnavailable` 并写明原因，不发请求 |
| 受限直播改为直播中 | 口令直播：v3 和 E03.4 在频道页就报 `NeedsLogin`，现在再请求一次 `streamserver.php`，在播就是直播中 + `password`（这种房间多一个请求）；页面上没有能核对的名字，名字、标题、头像留空。列表里加锁的直播：v3 跳过，现在显示为直播中 + `password`（实测 837 行里一个都没有，站点的列表似乎不收加锁的直播）。搜索里的私密直播见 12-5 |
| 占位信息 | 适配器没有占位文字。`twitter:title` 为空时标题留空（不再用可能是个人简介的 `twitter:description`）；口令直播的名字留空。`Live #…`、`<频道>'s Live` 是平台给的默认标题，12-1 的决定是没有副标题时照旧显示 |
| 回放、轮播、“不可播放” | TwitCasting 没有回放或轮播状态：未开播时频道页放的是上一场录像，v3 和现在都按未开播处理，不作为回放。`unplayable` 只用在搜索里站点不让播、又不是私密的直播行 |
| 画质命名 | 表里没有本平台的改名、合并条目，照统一原则保留 v3 的 `HLS high`、`HLS medium`、`HLS low`，id 仍是 `high`、`medium`、`low`，排序不变 |
| 默认编码 | 不涉及：`tc-hls` 只有 H.264（归档规格 §6.5，初始化段是 `avcC`），H.265 只在不用的 `llfmp4.h265` 里 |
| 房间身份 | 不变：频道名，E05.2 已把 `twitcasting` 放进不分大小写的平台 |
| 按主播关注 | 本来就按频道关注，直播号每场都变、只在 `TwitcastingRoomData` 里，没有单场身份要迁移 |
| 容错 | 列表、搜索里坏的一行只跳过这一行（v3 和 E03.4 整个列表 `ApiChanged`）；整个窗口的行全坏时仍是 `ApiChanged`，不把接口改版显示成空列表。一档画质的地址不对只去掉这一档，其余照常（v3 整个回答作废）；一档都没有才是 `ApiChanged` |
| 翻页 | 推荐、分区：第 1 页请求 60 条的窗口，之后的页在 30 秒内从同一份回答里切（原来每页都重新请求窗口），切法仍是 v3 的“先切后滤”；搜索见 12-4。快照按列表分开，最多 16 份，失败的请求不留快照 |
| 说明文字 | 不涉及：本平台没有公告或目录说明 |

### 请求数

| 场景 | v3 / E03.4 | 现在 |
|---|---|---|
| 关注刷新、`getLiveStatus` | 频道页 + `streamserver.php` | `streamserver.php` 1 个（12-2） |
| 进房、录制详情 | 2 个 | 不变；口令直播从 1 个变成 2 个（要知道是否在播） |
| 推荐、分区 | 每页 1 个（窗口之后的页不请求） | 第 1 页 1 个；30 秒内的后续页不请求 |
| 搜索 | 每页 1 个（50 条之后不请求） | 第 1 页 1 个；30 秒内的后续页不请求（12-4） |
| 取流 | 有直播数据的房间不请求；列表卡片 1 个 | 不变；标了受限的卡片不请求，直接报原因 |

### 画质 id 对照（给 J02.1）

没有变化，不需要旧 id → 新 id 的对照：画质仍是 `high`、`medium`、`low`（`TwitcastingApi.qualityKeys`），名称仍是 v3 的 `HLS high`、`HLS medium`、`HLS low`。

### 设置项

无。

### 房间身份迁移规则（给 J02.1）

无。房间身份仍是频道名（保留关注时的写法，比较不分大小写，E05.2）。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 | TwitCasting 评论：进房详情的 `danmakuData` 是 `TwitcastingDanmakuArgs(channel, movieId)`；匿名 POST `eventpubsuburl.php`（表单 `movie_id`）拿 wss 地址（样本 `S07-pubsub`、`danmaku/S08-live`）。主播重新开播后直播号会变，要重新取详情。口令直播的评论能否匿名连接没有验证 |
| M13 | 卡片按 `restriction` 标“私密”“口令”“不可播放”，发现页是否隐藏；搜索里的私密直播进房会显示未开播（平台如此），可以在卡片上直接提示而不进房；播放失败时按 `StreamUnavailable` 的原因提示；开播时间只在直播中显示；搜索、推荐、分区的第 1 页（下拉刷新）会重新请求，之后的页在 30 秒内来自同一份结果，v3 热门页、分区页自己切 60 条窗口的做法（E03.4 已记）仍适用 |
| J02.1 | 按 E05.2 存 `startedAt`、`restriction`。没有设置、画质或身份要迁移 |
| G | 没有新内容：线路、请求头、会话 Cookie（REG-TWITCASTING-002）不变 |
| H01.1 | 录制详情仍是完整详情；口令直播录制时 `getPlayQualities` 报 `StreamUnavailable` |

### 受阻和未核实

没有受阻的条目。以下没有样本，按统一原则实现、用合成数据测试：

- **口令（合言葉）直播**：归档规格就缺这个样本，这次也没找到（搜索、分类窗口里都没有加锁的直播）。页面文字仍按 v3 认 `Enter the secret word to access`；这种房间 `streamserver.php` 是否说在播、`tc-hls` 不输口令能否播放都不知道。现在的做法是在播就标 `password`、不播放；不支持输入口令。
- **列表的 `is_locked`、`is_group`**：837 行里都是 false。加锁按口令处理（见上）；`is_group` 的含义不清楚，仍照 v3 跳过。
- **搜索的其他受限行**：实测只见过 LIVE 和 Private 两种徽标；别的不让播的行按 `unplayable` 处理。搜索页的 Premier（付费）段 v3 不读，这次也没有接入（表外的新内容）。

### 与 v3 冻结输出的新差异

`expected.json` 没有改。样本对照测试里用 `changed:` 列出（注释写条目编号）：

- S04-page-live 的进房和频道链接搜索：`title`（12-1）。
- S04-page-live、S04-page-offline 的关注刷新（v3 `getRoomDetailForRefresh`）：`title`、`nick`、`avatar`、`cover` 留空（12-2）；另有用例检查合并进存下的房间后，除 12-1 的标题外与 v3 的刷新结果相同。
- S03 搜索第 1 页：v3 整页失败；现在 15 条，私密直播那一行是直播中 + `private`（12-5），其余 14 行与 `withoutPrivateRow` 逐字段相同。

E05.2 的新键（`startedAt`、`restriction`）和 `danmakuData` 单独断言：列表、搜索、详情的开播时间与三处来源互相对得上；各处的受限类型；未开播没有开播时间和受限类型。

### 新样本

2026-09-28 17:32～17:34 UTC 直连录制，匿名，请求头是适配器的 `TwitcastingApi.headers`，频道页不跟随跳转；`raw` 记原始回答的 SHA-256 和长度。v3 对它们没有需要冻结的输出，不带 `expected.json`。门禁的 `fixture privacy` 通过。

| 样本 | 内容 | 脱敏（`meta.json` 的 `scrubbed`） |
|---|---|---|
| `S04-page-live-tags` | 在播频道 c:gooniegoogoogaga 的频道页：副标题位置只有话题标签，`twitter:description` 是个人简介 “Rock;Star”（12-1 的依据） | 访客的 CSRF 令牌（`data-csrf-token`、`data-token`、页面变量里的 `csrf_token` 三种写法）、`web-authorize-session-id`、Set-Cookie `did`，换成同形的随机值 |
| `S05-stream-live-tags` | 同一频道的 `streamserver.php`（在播，直播号与页面相同） | 无（回答没有 Cookie、令牌） |
| `S03-search-private` | 关键词 “弾き語り” 的搜索页：23 条直播，其中 g:117931547061051040135 是私密直播 | Set-Cookie `hl`、`did` |
| `S04-page-private` | 同一频道的频道页：同一个直播号，但显示为录像（`data-live-type="movie"`），3 秒后录下 | 同 `S04-page-live-tags` |
| `S05-stream-private` | 同一频道的 `streamserver.php`：同一个直播号，`live: false` | 无 |

主播的公开信息（频道名、昵称、标题、直播号、头像地址）按 E03.4 的口径保留。

### 测试

本平台 87 个用例（新增 21 个，另改写了受影响的用例），`live_core` 共 3022 个，门禁 `--all` 通过：

- `twitcasting_api_test.dart`（49 个）：列表的加锁卡片、受限类型、开播时间（样本和各种 `elapsed_time`）、坏行跳过和全坏报错；搜索的私密卡片（S03 和新样本）、开播时间和 `pageDate`、不让播的行、坏行跳过；详情的副标题规则（合成页面和 S04-page-live-tags）、开播时间（同一场才填、录像不填）、受限类型、弹幕参数、口令页面；刷新结果和合并；私密直播在频道页和 `streamserver.php` 里是未开播；一档坏地址只去掉这一档；受限卡片的错误原因。
- `twitcasting_site_test.dart`（38 个）：列表 30 秒快照（同一份回答、另一个列表、过期、第 1 页重新请求、失败不留）、列表卡片的开播时间；搜索只请求一次、按关键词分开、过期和第 1 页重新请求、取消后不从快照返回；进房和录制的新字段；刷新和 `getLiveStatus` 只请求 `streamserver.php`、合并后的关注可以直接播放；私密直播的卡片不请求就报原因、进房是未开播；刷新后的数据优先于卡片上旧的受限标记；加锁卡片不请求；口令直播在播并标 `password`、取流报原因；刷新的错误映射。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.12 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.12-TwitCasting弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
