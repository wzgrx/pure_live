# E03.5 niconico

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/niconico/`（`niconico_api.dart` 纯解析，`niconico_seat.dart` 观看座位，`niconico_site.dart` 请求编排），另加通用的 `packages/live_core/lib/src/hls_master.dart`。
- 样本：`fixtures/niconico`，全部来自归档（2026-09-27 录制）：
  - 最近节目 `S01-recent-common-p1`、`S01-recent-req-p1`、`S01-recent-face-p1`，在播搜索 `S02-search`；
  - 观看页 `S03-watch-user-live`、`S03-watch-program-live`、`S03-watch-user-ended`、`S03-watch-channel`（付费频道的试看）、`S03-watch-notfound`（404）；
  - 座位会话 `seat/S04-seat`（`frames.jsonl`：`startWatching`、`seat`、`stream`（13 个按路径的 Cookie）、`messageServer`、`statistics`、`ping`/`pong`/`keepSeat`，约 65 秒）；
  - 评论服务器 `danmaku/S07-live`，D01 用。
- 参考：
  - 归档 v4 的 niconico 适配器和规格（`spec/sites/niconico.md`）。规格没有 REG-NICONICO 条目，只有 §10“踩过的坑”；与本平台相关的通用条目是 REG-LEASE-014、016、017（见“回归条目的覆盖”）。
  - pure_live_TV `e1cca224`：与 v3 相同，只是把 3.x 录制层里的主列表预读抽成 `niconico_master_reader.dart`、`totalViewers` 缺值写空串（对照笔记 `small_diffs.txt`、`sub_C.md`），没有行为修复。TV 的播放器只读 URL，这个平台在 TV 里其实播不了（`sub_C.md` 结论 2）。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；关注刷新和列表的请求不比 v3 多。

## 做法

- **接口和输出沿用 v3**：`LiveSite` 和 v3 实现过的全部可选能力——目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `niconico_directory_scope`）、画质探测（`LiveQualityDiscovery`）、可取消的搜索、关注刷新、录制详情、取流（`LivePlayUrlResolver`）、恢复、逐条线路（`LivePlayUrlCursorResolver`），外加 `LiveSiteLinks`。3.x 的 JSON 不变。
- **请求照 v3**：
  - 所有页面和列表请求都以 `niconico` 的名义发出（代理路由由应用按平台注入），带 v3 的请求头 `Referer: https://live.nicovideo.jp/`、`User-Agent: Mozilla/5.0`，**不跟随跳转**，不带 Cookie；
  - 分区、推荐：`front/api/pages/recent/v1/programs?tab=…&offset=<页码-1>&sortOrder=recentDesc`，站点每页 70 条，`totalCount > 页码 × 70` 时还有下一页；推荐就是 `common`（综合）；
  - 搜索：`front/api/pages/search/v1/programs?keyword=…&column=main&status=onair&page=…&disableGrouping=true`，每页 40 条，只有在播节目；
  - 详情：`watch/<节目号>`，进房、关注刷新、录制详情、开播状态各 1 个请求，与 v3 相同；
  - v3 的边界照旧：页码 1～10000、每页条数 1～100（站点页大小固定，这个参数只校验）、关键词最多 500 个字符。越界是调用方的错误（`ArgumentError`），不发请求。
- **房间身份与 v3 一致**：房间号是节目号 `lv…`（每场直播一个，3.x 存下的关注就是它）。详情的房间号就是请求的号码，并核对观看页里的节目号与它相同；列表的房间号是行里的节目号。
- **严格校验照 v3**：列表的每一行都要在播、提供者类型已知、有标题和名字、观看链接指向自己、节目不重复，否则整页 `ApiChanged`；观看页的状态、访问标志、人数、座位地址也按 v3 逐项检查。图片不合规（非 https、不在 `*.nimg.jp`/`*.nicovideo.jp`、带端口或凭据）只丢掉图片，不影响房间。
- **状态照 v3**：`ON_AIR` 是直播中，`RELEASED`（预约）和 `ENDED` 都是未开播；地区限制、需要登录的节目在直播时仍显示为直播中，公告里写明原因，到取流时才报错。人数是 `statistics.watchCount`，累计来场数，写进 `totalViewers`，口径 `totalViewers`。
- **公告和分区名**：v3 在平台层调用界面翻译。这里写 3.x `zh.json` 的中文（与中文界面下 3.x 存下的内容逐字相同），同时把状态和访问权限放进 `NiconicoRoomData`，界面按它显示自己语言的公告（M13）。分区名同理，界面按分区 id 翻译。
- **取流是会话型输入，照 v3 用“配方”，不是线路**：
  - 播放列表、分片、密钥各要自己路径上的那组 Cookie（全部合在一个请求头里主列表就 403），这些 Cookie 由观看座位（WebSocket）下发，座位关了一分钟内密钥服务器就拒发新密钥。线路的一组固定请求头表达不了这两点，所以本平台不给 `LivePlayUrlResolution.lines`，也没有 `PlayLease`；
  - 画质探测：重新读观看页 → 自己开一个座位 → 用座位给的主列表路径 Cookie 读主列表（5 秒，不跟随跳转，只带 Cookie）→ 列出画质 → 返回前关闭座位。整个探测最多 30 秒。画质按主列表的视频变体，名称是 v3 的 `800×450 · 1080800 bps`，id 是 `800x450@1080800`，从高到低；
  - 取流：返回 `LivePlayUrlResolution.owned(NiconicoInputRecipe(节目号, 分辨率, 码率))`，不发请求；恢复相同；逐条线路只有第 0 条。播放和录制按配方各自读观看页、开座位（`NiconicoSite.openSeat`）、按路径发 Cookie（G、H01.1）。
- **座位**（`NiconicoSeat`，3.x 的 `NiconicoSession`）：经 `live_net` 的 `SocketConnector` 按 `niconico` 的代理路由连接，握手带 `Origin`；只发文本帧；发 `startWatching`（abr、hls、高延迟、不评论、不重连）和 `getAkashic`；收到 `seat` 和 `stream` 才算打开（20 秒内）；按 `keepIntervalSec` 发 `keepSeat`，`ping` 回 `pong` 并补一次 `keepSeat`；新的 `stream` 替换并吊销旧授权；`error`、`disconnect`、90 秒无消息、连接断开都结束座位，不偷偷重连；关闭最多等 2 秒。另外记下 `messageServer`（评论服务器地址，D01 用），v3 没读它。
- **没有弹幕参数、没有登录**：v3 的 niconico 没有评论（`EmptyDanmaku`），也没有账号和 Cookie 设置，所以不注入 `CookieVault`，也不输出弹幕参数。评论服务器的地址只在座位上给出，D01 用 `openSeat` 自己开座位读 `messageServer`。
- **观看页不引入新依赖**：v3 用 package:html 取 `<script id="embedded-data">` 的 `data-props`。这里用一个只认 `<script>` 开始标签和属性的私有读取器（引号内的 `>` 不算结束，属性顺序、引号方式不限），再用 `decodeHtmlEntities` 解码。四个观看页样本的结果与 v3 逐字段一致。

## 审查发现的 v3 问题

位置简写（都在 `legacy/lib/` 下）：`S` = `core/site/niconico/niconico_site.dart`，`A` = `niconico_api.dart`，`W` = `niconico_watch.dart`，`D` = `niconico_directory.dart`，`SS` = `niconico_session.dart`，`ST` = `niconico_stream.dart`，`Q` = `niconico_quality_catalog.dart`，`L` = `niconico_link.dart`，`HI` = `recorder/services/niconico_hls_input.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 平台层反向依赖录制层：画质目录从录制服务里引入座位工厂和主列表读取器 | Q:7；HI:294-350 | 主列表预读写在录制层，平台层借用 | 座位（`NiconicoSeat`）放在本平台目录，主列表经 `LiveHttp` 读；HLS 主列表解析移到 `live_core` 的通用文件（见“新增的通用能力”） |
| 2 | 平台层用全局 HTTP 单例，自己实现流式读取（2 MiB、严格 UTF-8、20 秒）和取消；座位读全局的 WebSocket 代理设置 | A:22-63、A:81-96；SS:90；Q:67 | 结构问题 | 注入 `LiveHttp`（20 秒由请求超时负责）；座位经 `SocketConnector` 走 `ProxyPolicy` 给 `niconico` 的路由，与 HTTP 相同 |
| 3 | 错误没有类型：12 种 `NiconicoFailure`；调用方传错页码、每页条数、分区、超长关键词也报“结构变化” | W:5-25；S:83-94；D:18-36 | 平台自己的异常类型 | 类型化错误：401/403/406 `RiskControl`，观看页 404 `NotFound`，429 `RateLimited`，5xx、跳转和其他状态 `NetworkFailure`（v3 的 service、transport），结构不符 `ApiChanged`，不能播 `StreamUnavailable`/`RegionBlocked`/`NeedsLogin`；调用方错误是 `ArgumentError`，同 v3 一样不发请求 |
| 4 | 平台层调用界面翻译；公告按当时的界面语言写进房间，随关注一起存下 | S:72、S:134-155 | `i18n` 写在适配器里 | 写 3.x 的中文（与 3.x 中文界面存下的相同）；状态和访问权限放进 `NiconicoRoomData`，由界面翻译（M13） |
| 5 | 明确未开播的房间取画质得到空列表，播放器拿不到原因 | S:178 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 6 | 座位的 `error` 消息丢掉错误码：连接太多（稍后可重试）和没有权限分不出来 | SS:204-205 | 全部记为 `sessionError` | 按 `code` 分类：`NO_PERMISSION`/`NOT_PLAYABLE`/`TICKET_REQUIRED` `NeedsLogin`，`TOO_MANY_CONNECTIONS`/`CONNECT_ERROR` `RateLimited`，`INVALID_*` `ApiChanged`，其他 `StreamUnavailable`（归档 v4 的映射） |
| 7 | 频道节目的列表卡片没有头像（样本 S01-recent-face-p1 的 lv351292489） | D:91-100 | 频道的 `programProvider.icon` 是空字符串，`icon ??=` 只在缺值时才退回 `socialGroup.thumbnailUrl` | 提供者的图标不可用时退回社群图标（归档 v4 的做法）；只影响 v3 没有头像的卡片 |
| 8 | 主列表的状态码不分类：授权被拒的 403 和格式变化一样都是“schema” | HI:328 | — | 主列表 401/403 `RiskControl`，404/410 `StreamUnavailable`，429 `RateLimited`，5xx `NetworkFailure`，其他 `ApiChanged` |
| 9 | 画质已经读出来，只因关闭座位时 WebSocket 的关闭握手超过 2 秒，整个探测报“cleanup”失败，房间播不了 | Q:131-137；SS:256-274 | 把关闭握手的超时当成资源泄漏 | 关闭最多等 2 秒，之后放弃等待（`dart:io` 回收连接），探测照常返回 |
| 10 | 一行不合格（不在播、提供者类型未知、没有名字、节目重复）整页失败 | D:60-70、D:78-90 | 严格校验 | 按 v3 保留（样本里全部合格） |
| 11 | 链接只认 `https://live.nicovideo.jp/watch/lv…`：官方 App 分享的 `https://nico.ms/lv…`、旧版手机站 `sp.live.nicovideo.jp`、`http://`、主播页 `watch/user/<id>`、频道页 `watch/ch<号>` 都识别不了 | L:7；W:66-76 | 有意只认“核实过的”链接 | 按 v3 保留 |
| 12 | 关注的是“这一场”：节目号每场都变，主播下次开播就对不上 | W:31-33；公告 `niconico_program_scope` | 以节目号为房间身份 | 按 v3 保留（身份必须与 3.x 存下的关注一致） |
| 13 | 进房读一次观看页，取画质又读一次 | S:131-133；Q:96 | 座位的引导地址是短期的，v3 有意不保存 | 按 v3 保留（请求次数相同） |

## 样本与 v3 的冻结输出

归档没有 niconico 的 `expected.json`（归档的旧版对照工具只做了前五个平台，v3 应用也构建不了）。本模块用 `fixtures/niconico/legacy_expected.dart` 生成，做法同 E03.4 TwitCasting：

- 把 v3 的 `niconico_watch.dart`、`niconico_api.dart`、`niconico_directory.dart`、`niconico_site.dart`、`niconico_stream.dart` 和 `core/common/hls_session_cookies.dart` 原样搬进一个 Dart 脚本，只把网络换成读样本：列表按路径和查询参数回放，观看页的请求一律回放本次加载的观看页样本（样本录的是 `watch/user/<id>`、`watch/ch<号>`，与 v3 请求的节目号是同一页）；和 v3 的 `_defaultRequest` 一样，非 200 的响应正文为空；没有样本的请求抛 StateError。`i18n` 返回 3.x `zh.json` 的文字。
- 画质目录、座位和配方没有搬：它们要实时 WebSocket 和主列表，样本里没有主列表。
- v3 用 package:html 解析观看页，工作区不依赖它，所以脚本用临时的包配置运行（命令写在脚本开头，`html: 0.15.6` 只用于生成期望值）。
- 输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`）。

10 个 `expected.json`：

| 样本 | 内容 |
|---|---|
| `S01-recent-common-p1` | 分类（第 1、2 页）、目录第 1 页（推荐）、`getRecommendRooms` |
| `S01-recent-req-p1`、`S01-recent-face-p1` | 分区的目录第 1 页和 `getCategoryRooms` |
| `S02-search` | 搜索第 1 页（每页 20，3.x 搜索页的参数）和是否有下一页 |
| `S03-watch-*` | 三种深度的详情、开播状态、观看页解析出的状态、访问权限、人数和座位地址（`S03-watch-notfound` 是 `missing` 错误） |
| `seat/S04-seat` | 录下的 `stream` 消息：主列表、画质表、Cookie 数，以及主列表、视频分片、音频分片、密钥、会话密钥各自得到的 Cookie 请求头（时间取录制时刻） |

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；座位授权比较每个路径的 Cookie 请求头。

| 样本 | 结果 |
|---|---|
| S01 分类 | 一致：1 个分类 `niconico`，7 个分区（综合、创作与挑战、游戏、视频介绍、露脸直播、连麦互动、VTuber），`areaType` 都是 `recent`。v3 的 `areaPic`、`shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S01 综合（70 条）、视频介绍（10 条）、露脸直播（44 条） | 节目、顺序、各字段、`hasMore` 一致；露脸直播里唯一的频道节目多了头像（问题 7） |
| S02 搜索（40 条） | 一致；`hasMore` 为真（`totalCount` 156） |
| S03 直播（用户、按节目号）、已结束、频道试看 | 三种深度都一致，包括公告和封面（直播时优先截图，没有截图用 640×360 缩略图）；观看页的状态、访问权限、人数、座位地址一致 |
| S03 不存在 | v3 是 `missing` 错误；现在是 `NotFound` |
| S04 授权 | 主列表、画质表、13 个 Cookie 一致；五种路径的 Cookie 请求头逐字相同（路径长的在前，同路径按下发顺序） |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 出错抛类型化错误，调用方错误是 `ArgumentError` | 问题 3。界面看到的仍是加载失败（M13 用 `pendingAfterError`），状态和分组不变 |
| 2 | 明确未开播的房间取画质报 `StreamUnavailable` | 问题 5。只在播放路径上 |
| 3 | 座位的错误按错误码分类 | 问题 6 |
| 4 | 频道节目的列表卡片有头像 | 问题 7。v3 在这里是空的，别的卡片不变 |
| 5 | 主列表的状态码分类 | 问题 8 |
| 6 | 关闭座位慢不再让画质探测失败 | 问题 9 |
| 7 | 房间多带 `NiconicoRoomData`（状态、访问权限），不写进 JSON | 问题 4，给界面翻译公告用 |
| 8 | 座位记下评论服务器地址 | D01 用；不多发消息 |
| 9 | 页面、列表不再逐字节限制下载大小和严格 UTF-8；解析前仍按 2 MiB 检查 | 问题 2。传输由 live_net 统一负责，20 秒总时限相同；非法 UTF-8 按替换字符处理 |
| 10 | Cookie 的过期时间只认 RFC 1123 格式（`Mon, 28 Sep 2026 18:41:00 GMT`） | 不依赖 `dart:io`。服务端只发这种格式（样本 S04） |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **房间身份是节目号**（问题 12）。归档 v4 改成主播身份（`user/<id>`、`ch<号>`），观看页 `watch/user/<id>` 返回主播最新一场。那样 3.x 存下的 `lv…` 关注就对不上了，列为升级候选 1。
- **画质按主列表的视频变体分档**，名称 `800×450 · 1080800 bps`。归档 v4 只有一档 `abr`“自动”，由适配器持有座位、线路带中继配方和 60/150 秒的租期，会改变画质菜单和播放方式。
- **每个使用者自己开座位**：探测用完就关，播放和录制各开一个（3.x 的所有权模型）。归档 v4 由适配器按节目持有、续租共享；笔记 `sub_C.md` 还指出它有并发打开两个座位的竞态、没有静默看门狗。这里没有共享，也保留了 v3 的 90 秒静默看门狗。
- **严格校验**（问题 10）：归档 v4 跳过坏行、不核对观看链接和座位地址。
- **链接只认 v3 的写法**（问题 11）：归档 v4 还认 `sp.live.nicovideo.jp`、`nico.ms/lv…`、`watch/user/<id>`、`watch/ch<号>`，并把节目链接换成主播身份。
- **没有简介、开播时间和弹幕**：归档 v4 读 `program.description`（HTML）、`beginTime`，并实现了评论服务器（NDGR）。3.x 的 `LiveRoom` 没有开播时间字段；简介和弹幕列为升级候选。
- **请求头照 v3**（`Mozilla/5.0`、`Referer`）：归档 v4 用 Chrome 140 UA、`Accept-Language: ja,en`、不带 `Referer`。
- **分类名 `niconico`、分区名用 3.x 的中文**：归档 v4 是“カテゴリ”和日文分区名。
- **座位在 `ping` 后补一次 `keepSeat`、发 `getAkashic`**：同 v3（归档 v4 不发 `getAkashic`）。
- **频道节目的详情没有头像**：频道的 `supplier` 没有 `icons`，v3 和归档 v4 都不退回社群图标（用户节目的社群是“已删除的社区”，退回会显示错的图）。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复；它把主列表预读从录制层移到平台目录，这里同样放在平台层（经 `LiveHttp`）。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 关注主播而不是某一场：房间号用 `user/<id>`、`ch<号>`，观看页 `watch/user/<id>` 给出最新一场；3.x 的 `lv…` 关注在迁移时（J02.1）读一次观看页换成主播身份 | 关注只对应这一场，下次开播要重新关注 | 归档 v4 规格 §1；样本 S03-watch-user-live 与 S03-watch-program-live 是同一页 |
| 2 | 识别 App 分享的 `https://nico.ms/lv…`、旧手机站 `sp.live.nicovideo.jp`；（配合 1）识别 `watch/user/<id>`、`watch/ch<号>` | 这些链接识别不了 | 归档 v4 规格 §1 |
| 3 | 评论（弹幕）：座位给出 `messageServer.viewUri`，长轮询 NDGR protobuf | 没有弹幕，公告里写“弹幕暂未接入” | 归档 v4 规格 §7；样本 `danmaku/S07-live`；座位已记下地址 |
| 4 | 单行坏数据只跳过这一行 | 整页失败 | 问题 10；归档 v4 |
| 5 | 详情带简介（`program.description`，去掉 HTML） | 没有简介 | 观看页有这个字段 |
| 6 | 进房时把观看页的座位引导地址交给第一次画质探测，省一次观看页请求 | 进房、探测各读一次 | 问题 13；引导地址的有效期待确认 |

## 回归条目的覆盖

归档规格没有 REG-NICONICO 条目。§10“踩过的坑”和 `spec/regressions.md` 里涉及本平台的通用条目，属于平台层的部分都有测试：

- **主列表 403（把所有路径的 Cookie 合进一个请求头）**、REG-LEASE-014（Cookie 的作用域）：授权只给路径匹配的那组，固定在主列表的源（https、同主机、无端口和凭据），整段路径匹配，按过期时间剔除，吊销后清空并拒绝再取；数量和大小有上限。录下的授权五种路径逐字对照 v3，另有 v3 的合成授权用例。
- REG-LEASE-016（变体和音轨按身份选择）：`HlsMasterSelection` 按地址选择，保留变体关联的音轨；一个音轨组有多个音轨、同一分辨率和码率出现两次时，画质探测报 `ApiChanged`，不给出播不了的画质（移植 v3 `hls_master_selection_test.dart`、`niconico_quality_catalog_test.dart`）。
- REG-LEASE-017（会话型输入不导出私有地址）：取流结果没有 URL（`urls` 为空，`inputRecipe` 是 `NiconicoInputRecipe`），房间 JSON 里没有座位引导地址和令牌；两个探测各开各的座位。
- **座位立刻被关（发了二进制帧）**：座位只发 JSON 文本帧，收到二进制帧按结构变化结束。
- **播着播着解不了密（座位关了）**：座位按 `keepIntervalSec` 保活、`ping` 回 `pong`，90 秒无消息才结束；播放和录制期间保持座位由 G、H01.1 负责（见下）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 按配方打开输入：读观看页、开座位（`NiconicoSite.openSeat`），播放期间保持座位；按请求路径发 `seat.current.cookieHeaderFor(url)`；新的授权换了主列表时结束并重新获取；按 `resolution`、`bandwidth` 用 `HlsMasterSelection` 选变体，保留关联音轨；LL-HLS、fMP4、AES-128（3.x 的 `NiconicoHlsInput`、`NiconicoPlaybackInput`、`FFmpegHlsInputRelay`） | G 播放、H01.1 录制 |
| 投屏和复制直链遇到会话型输入时提示“需要会话”（REG-LEASE-017） | N02.1、M13 |
| 评论（弹幕）连接 | D01（升级候选 3）；`getDanmaku()` 同 E01.1，用“平台 → 弹幕连接”的表 |
| 目录说明文字 `niconico_directory_scope`、分区名 `niconico_category_*`、公告各段（`niconico_scheduled`、`niconico_login_required`、`niconico_region_restricted`、`niconico_access_restricted`、`niconico_program_scope`）的多语言，按 `NiconicoRoomData` 和分区 id 显示 | M13 |
| 搜索能力表（只有在播、可翻页、有网页搜索）、网页搜索 `https://live.nicovideo.jp/search?keyword=…&status=onair`（3.x `search_capability.dart:38`、`search_controller.dart:105-106`） | M13 搜索页 |
| 外部打开 `https://live.nicovideo.jp/watch/<节目号>`，按节目号重建，不用存下的 `link`（3.x `room_external_opener.dart:73-78`） | M13；地址由 `NiconicoApi.watchUrl` 提供 |
| 人数设置页的说明 `audience_niconico_detail`、本地互动的平台包、多画面不支持本平台弹幕 | M13 |
| 3.x 设置迁移：平台列表追加 niconico（`favorite_room_controller.dart:69`，第 13 版） | J02.1 |
| 目录页的翻页和取消（3.x `LiveDirectoryController`，关闭页面时取消请求、丢弃晚到的卡片） | M13 |

## 新增的通用能力

- `hls_master.dart`：`HlsMasterPlaylist`、`HlsMasterVariant`、`HlsMasterSelection`，3.x `core/common/hls_master_selection.dart` 的移植（逻辑不变，只把 UTF-8 计数改成长度超过上限三分之一时才编码）。有界的普通主列表解析，看不懂的内容一律 `FormatException`；按地址选择变体并保留关联音轨，`rewrite` 把主列表缩成所选的那一档。本平台用它列画质；以后 CHZZK（3.x 同样用它）和 G、H01.1 的中继也用它。v3 的测试移植为 `test/hls_master_test.dart`（录制层的预读计划部分随 H01.1）。
- `live_core.dart` 按字母顺序加了四行导出。其余用到的 `decodeHtmlEntities`、`jsonUrl`、`LiveDirectoryPage`、`LiveInputRecipe`、`LivePlayUrlResolution.owned`、`live_net` 的 `SocketConnector`/`ProxyPolicy` 都已存在。

## 测试

新增 256 个用例，`live_core` 共 1370 个，全部通过：

- `hls_master_test.dart`（33 个）：移植 v3 `hls_master_selection_test.dart`（每个变体保留音轨、按地址选择、换了会话或媒体就失败、多音轨要显式选择、混合音频不附加外部音轨、27 种不支持的主列表），另加源地址的校验。
- `niconico_api_test.dart`（166 个）：逐个样本对照 v3 的输出（分类、三个分区、搜索、四个观看页三种深度、404、录下的授权五种路径），有意的差异逐条断言；移植 v3 的 `niconico_api_test.dart`、`niconico_directory_test.dart`、`niconico_stream_test.dart`、`niconico_quality_catalog_test.dart`（解析部分）和 `niconico_application_test.dart` 的链接用例（小样本内联）：属性解码、官方节目的座位路径、状态与访问权限分开、登录要求优先、身份检查、坏页面、12 种不合规的座位地址、图片退回和丢弃、目录的分页和 12 种坏页、授权的 Cookie 作用域、过期和吊销、不合规的授权（9 种整体问题、10 种 Cookie 属性、7 种主列表地址）、画质和 4 种坏主列表、配方、座位消息、HTTP 状态。
- `niconico_site_test.dart`（57 个），用样本回放、录下的座位对话（假 WebSocket）和手动时钟：
  - 能力；分类只有第 1 页、不发请求；页码和每页条数的边界；
  - 目录的请求、请求头、不跟随跳转，页码偏移，7 个分区逐个请求，别的分区不发请求，取消；
  - 搜索的参数和编码、空关键词、超长关键词，取消前不发请求、令牌传到请求、晚到的回答被丢弃；
  - 详情：每种深度 1 个请求、不开座位，房间号是节目号，与 3.x 存下的关注合并，非节目号不发请求，404、5xx 和传输错误；
  - 画质探测：观看页、座位（地址、`Origin`、平台的代理路由、`startWatching` 的内容）、主列表只带它路径的 Cookie，返回前关闭座位；两个探测不共用座位；未开播不发请求；已结束、地区限制、需要登录、无权观看都不开座位；主列表被拒、座位报错、座位不发授权、总时限、调用方取消、读主列表时座位结束或换了主列表；
  - 配方：身份、没有 URL、恢复相同、只有第 0 条线路、不发请求；别的节目的画质、改名的画质、未开播、别的平台；
  - 座位协议（移植 v3 `niconico_session_test.dart`）：录下的对话、定时保活、`ping`、关闭后不再发送；授权先于 `seat` 不算打开；间隔变化替换定时器；新授权吊销旧授权；7 种结束方式都不重连；90 秒静默；5 种不合规的间隔；启动超时和取消时晚到的连接被关闭且不发送；发送失败；关闭最多等待关闭超时；非座位地址和已取消的令牌不连接；
  - 链接和分享文本（不发请求）。

## 升级落地（T02.U）

- 日期：2026-09-29（E03.5）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 17-1～17-6；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。17-3（评论）的连接属于 D01，这里只给出它要的参数。
- 只改了本平台：`niconico_api.dart`（解析）、`niconico_site.dart`（请求编排）和两份测试；`niconico_seat.dart` 没有改。没有改 `live_core` 的通用文件，没有新依赖。新样本 4 个（见下文）。
- 实测：2026-09-28 17:58～18:32 UTC，经本机代理（127.0.0.1:7897）、匿名、用适配器的请求头：7 个分区各 1～3 页、两个关键词的搜索、6 个观看页（用户、频道、官方节目和它的频道）、座位引导地址的有效期（17-6）。下面的结论都来自这些回答。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 17-1 | 房间身份改成主播：用户的节目是 `user/<用户 id>`，频道的节目是 `ch<频道号>`；观看页 `watch/user/<id>`、`watch/ch<号>` 给出主播最新的一场（在播时就是这一场）。**官方节目仍是节目号 `lv…`**：它没有主播页——实测 `watch/ch2525`（搜索里官方节目“ニコニコ実況”的社群）是 404；官方节目 lv351173882 在播时，它的社群频道页 `watch/ch2627923` 显示的是 2025 年的一场频道节目（新样本 S03-watch-official、S03-watch-official-channel，前后相差一分钟）。所以按 `providerType` 定身份，不按 `supplierType`（官方节目的 `supplierType` 也是 `channel`；归档 v4 进房换身份时按 `supplierType`，会把这种节目换成错的频道）。规则 `NiconicoApi.roomIdOf`：`community`（或 `user`）且有提供者 id → `user/<id>`（列表 `programProvider.id`、搜索和观看页 `supplier.programProviderId`，观看页还要 `supplierType` 为 `user`）；`channel` 且社群是 `ch…` → 社群 id（列表、搜索的 `socialGroup.id`，观看页 `socialGroup.type` 为 `channel`）；其他（官方、缺 id）→ 节目号。<br>- 列表、搜索的卡片和 `link`（`NiconicoApi.watchUrl(房间号)`）都用新身份；同一页里同一个房间的第二场不再出卡（先出现的留下）。<br>- 适配器仍接受旧的 `lv…`：观看页在播时 1 个请求，直接返回主播的房间；已结束或预约中时再读主播页（第 2 个请求），因为主播可能正在播另一场（测试用合成的“旧节目已结束、主播在播新一场”）。`resolveRoomId` 只换身份（节目号 1 个请求，主播 0 个），给 J02.1 迁移用。<br>- 观看页按请求的身份核对：节目号要相同（v3）；主播页要是这个用户（`programProviderId`）或这个频道（社群 id），否则 `ApiChanged`。<br>- 详情的 `NiconicoRoomData` 多了本场节目号 `programId`；画质绑定房间和本场节目（`NiconicoQuality.roomId`、`programId`），别的房间的画质照旧拒绝；配方仍是节目号 + 变体，播放、录制照旧按节目开座位。`openSeat` 接受任何房间号。<br>- 频道房间的详情头像用频道图标（`socialGroup.thumbnailImageUrl`，只在社群是频道时；与列表卡片同一规则，v3 的详情为空）。<br>- 主播房间的公告去掉“收藏对应本次节目，主播的新节目需重新添加；弹幕暂未接入。”（对主播关注已经不对）；官方节目仍有这句。公告为空时是 null | 关注的是主播或频道：主播下次开播还是这一个关注，关注页照常刷新。列表、搜索里的卡片就是主播，打开外部链接是主播的直播页。频道的详情有头像。官方节目照旧按这一场关注。3.x 存下的节目号关注在 J02.1 迁移后换成主播（迁移前刷新不会合并，见“房间身份迁移规则”） | 平台层完成，余下 J02.1/M13 |
| 17-2 | 节目链接：除 v3 的 `https://live.nicovideo.jp/watch/lv…` 外，识别 `http://`、旧手机站 `sp.live.nicovideo.jp/watch/lv…`、App 分享的 `nico.ms/lv…`（`NiconicoApi.programIdFromUrl`）。节目要换成主播，所以这类链接 `needsResolving`，`resolveUrl` 经短链会话读一次该节目自己的 https 观看页（不请求链接本身），返回主播的房间；读不到、解析不了时返回节目号（进房时适配器再换）。<br>主播链接不发请求（`roomIdFromUrl`，`NiconicoApi.broadcasterRoomIdFromUrl`）：`live.nicovideo.jp`、`sp.live.nicovideo.jp` 的 `watch/user/<id>`、`watch/ch<号>`；用户主页 `www.nicovideo.jp/user/<id>`（也认 `nicovideo.jp`、`sp.nicovideo.jp`，允许一个小写子页如 `/live_programs`）；频道页 `ch.nicovideo.jp/ch<号>`、`ch.nicovideo.jp/channel/ch<号>`（允许一个子页如 `/live`）。http 和 https 都认；端口、凭据、编码或点段路径、其他主机仍不认。自定义名字的频道页 `ch.nicovideo.jp/<名字>` 要多一次请求，没有认 | 粘贴 App 分享、旧手机站、主播主页、频道页的链接都能打开，关注的是主播。节目链接要读一次观看页（经链接解析的会话，走 `links` 的代理路由；走不通时退回节目号，进房时再换） | 完成（T02.U） |
| 17-3 | 平台层：在播且匿名可看的详情带 `NiconicoDanmakuArgs(roomId, programId)`（`danmakuData`），不多发请求；未开播、受限（开不了座位）的没有；刷新和录制详情同样带（同一个观看页）。D01 用 `NiconicoSite.openSeat(roomId)` 开座位，读 `seat.messageServer`（E 已记下）。`getDanmaku()` 仍是空的弹幕源 | 看不出变化；评论在 D01 接入 | 平台层完成，余下 D01 |
| 17-4 | 列表、搜索里一行坏数据只跳过这一行：不是对象、节目号不合规、观看链接不指向自己、不在播、提供者类型未知、没有标题或名字、人数不合规。整页都是坏行时仍 `ApiChanged`（接口改版不显示成空列表），空页照常是空。信封（`meta`、`totalCount`、行数上限）仍按 v3 整页检查 | 平时看不出；v3 整页失败的地方现在只少那一张卡 | 完成（T02.U） |
| 17-5 | 详情的 `introduction` 是 `program.description` 的纯文本（`NiconicoApi.plainText`）：`<br>`、块结束换行；含这些标签的 HTML 里原始换行只是排版，当空格；其他标签去掉、保留文字（链接地址留下）；实体解码；逐行去空白，连续空行只留一个。纯文本的简介保留自己的换行。未开播时是最近一场的简介（与标题一样） | 详情显示简介（S03-watch-channel 的简介有 HTML，显示成分行的文字） | 完成（T02.U） |
| 17-6 | 进房（`getRoomDetail`）读到的座位引导地址（在播且匿名可看时的 `webSocketUrl` 加 `frontend_id`）留给同一房间的第一次画质探测：60 秒内有效（`bootstrapLifetime`，构造参数，0 关掉）、只用一次、最多留 8 个，不进房间数据、不导出。用它开座位失败（除了取消）时重读观看页再开一次。关注刷新、录制详情、开播状态不留。有效期实测见下 | 进房后开始播放少一次观看页请求：v3 是进房 1 次 + 画质探测 1 次 + 播放器开座位 1 次，现在探测不读 | 完成（T02.U） |

**座位引导地址的有效期**（17-6 的前提，2026-09-28 实测，在播的 24 小时频道节目 lv351383086，脚本读一次观看页后反复用同一个地址开座位，发 v3 的 `startWatching`）：

- 地址里 `audience_token` 带一个时间戳，恰好是页面返回时刻加 86400 秒，和 Set-Cookie `audience_token` 的 `Max-Age=86400` 一致；
- 同一个地址在读页后 0、60、300、900、1800 秒各开一次，每次都在 1.5 秒内收到 `seat` 和 `stream`；另两组只在 300 秒、900 秒第一次使用，同样成功；最后读新页面的对照组也成功；
- 所以 60 秒的保留期远在有效期内；保留期短，是因为只为“进房后马上播放”这一步，过期了就照 v3 重新读页。

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 三处都有，不多发请求：列表 `beginAt`（毫秒）、搜索 `beginTime`（秒）、观看页 `program.beginTime`（秒，只在在播时填）。不是整数或不在 2001～2286 年之间的不填。同一场在列表和观看页上的时间相同（S01 的 lv351482868、lv351292489 与 S03 对照）。关注刷新就是完整的观看页，照样填 |
| 受限类型 | 详情（在播时）：匿名可看 `none`——付费频道节目的免费开头也是 `none`，`NiconicoRoomData.paid` 为真（S03-watch-channel：`condition.payment` 为 `Ticket`、有 `trialWatch`、`canWatch` 为真）；地区 `regionBlocked`；要求登录 `needsLogin`；`canWatch` 为假时按页面字段：`isPrivate` → `private`，付费（`condition.payment` 或 `program.payment`）→ `paid`，`isFollowerOnly` → `subscribersOnly`，其余 `needsLogin`。未开播不填。<br>列表：`isPayProgram` → `paid`、`isFollowerOnly` → `subscribersOnly`、两个都为假 → `none`、没有这两个字段（v3 测试里的行）→ 留空；搜索同理（`payment`、`isFollowerOnly`）。S01-face 的频道节目 `isPayProgram` 为真，卡片标 `paid`，它的观看页可以免费看开头，进房后是 `none` |
| 受限直播改为直播中 | v3 已经是：地区、登录、无权观看的节目在播时都显示直播中。取流：地区 `RegionBlocked`、登录 `NeedsLogin`、私密、付费、仅关注者 `StreamUnavailable`（说明写原因；v3 这三种都报 `NeedsLogin`），都在开座位之前、不连接。卡片上标了 `paid` 的不预先拒绝：付费频道节目常有免费开头，由观看页决定 |
| 占位信息 | 适配器没有占位文字。用户节目的社群是“削除されたコミュニティ”（已删除的社区 co0，图标是 404 图），名字和图标都不用（频道头像只在社群是频道时退回） |
| 回放、轮播、“不可播放” | 不涉及。niconico 的时移（タイムシフト）是某一场的录像，不是房间状态：按主播关注后，这一场结束就是未开播（v3 同样）。已结束页面给的时移座位地址不读（新样本 S03-watch-channel-ended） |
| 画质命名 | 表里没有本平台的改名、合并条目，照统一原则保留 v3 的 `800×450 · 1080800 bps`，id 仍是 `800x450@1080800` |
| 默认编码 | 不涉及：主列表只有 H.264（`avc1`） |
| 房间身份 | `user/<数字>`、`ch<数字>` 只有数字和固定的小写前缀，仍区分大小写（不加进 `SiteIds.caseInsensitiveRoomIds`），`CH1`、`User/1` 不认 |
| 按主播关注 | 17-1 |
| 容错 | 17-4；图片不合规只丢图片（v3） |
| 翻页 | 不涉及快照：目录和搜索都是站点原生分页，每页一个请求，没有本地切片。最近节目按开播时间倒序，翻页之间新开播的节目会把行挤到下一页，跨页去重留给 M13 的列表（按房间身份） |
| 说明文字 | 主播房间去掉“收藏对应本次节目…”这句（17-1）。其余公告、目录说明不变，M13 按 `NiconicoRoomData` 和分区 id 显示自己语言的文字 |

### 请求数

| 场景 | v3 / E03.5 | 现在 |
|---|---|---|
| 关注刷新、`getLiveStatus`、进房、录制详情（主播或官方节目） | 观看页 1 个 | 不变 |
| 同上，3.x 存下的节目号（J02.1 迁移前、旧历史、旧链接） | 1 个 | 节目在播 1 个；已结束或预约中 2 个（再读主播页） |
| 进房后的画质探测 | 观看页 + 座位 + 主列表 | 60 秒内第一次：座位 + 主列表（17-6）；之后不变 |
| 目录、搜索 | 每页 1 个 | 不变 |
| 链接识别 | 不请求 | 节目链接 1 个（17-2）；主播链接不请求 |
| `resolveRoomId`（新） | — | 节目号 1 个；主播不请求 |

### 画质 id 对照（给 J02.1）

没有变化，不需要对照：画质仍按主列表的视频变体，id 是 `宽x高@码率`，名称是 `宽×高 · 码率 bps`。画质数据多出的房间号（`NiconicoQuality.roomId`）只在内存里。

### 设置项

无。17-6 的保留期是构造参数 `bootstrapLifetime`（默认 60 秒），不是用户设置。

### 房间身份迁移规则（给 J02.1）

| 存下的房间号 | 新房间号 |
|---|---|
| `user/<id>`、`ch<号>` | 不变 |
| `lv<号>` | 调 `NiconicoSite.resolveRoomId('lv<号>')`：读 `https://live.nicovideo.jp/watch/lv<号>`（1 个请求）。观看页 `program.providerType` 为 `community`（或 `user`）且 `program.supplier.supplierType` 为 `user` → `user/<program.supplier.programProviderId>`；`providerType` 为 `channel` 且 `socialGroup.type` 为 `channel` → `socialGroup.id`（`ch…`）；其他（官方节目、缺 id）→ 不变。纯函数是 `NiconicoApi.watch(页面, roomId: 'lv<号>').roomId`，规则本身是 `NiconicoApi.roomIdOf` |

- 换身份时：JSON 的 `roomId` 换成新身份，`link` 换成 `NiconicoApi.watchUrl(新身份)`（或删掉，下次刷新补上），`notice` 删掉（3.x 存的“收藏对应本次节目…”，新的详情给空公告，合并时不会覆盖它）；名字、标题、头像、封面、标签保留，下次刷新更新。
- 合并：几个节目号关注是同一个主播，或者已经关注了这个主播时，按 E05.2 的规则合并成一条（保留先关注的那条，合并标签）。
- 失败：`NotFound`（节目已删除，404）换不了，保留原来的 `lv`（进房显示加载失败，由用户删除）；网络等其他错误保留原值，下次启动再试。迁移前后适配器都接受 `lv`。
- 迁移前：适配器对节目号返回主播身份的房间，`mergeFrom` 因为身份不同会忽略它，所以关注刷新要排在迁移之后（测试 “a 3.x follow is merged only once migrated”）。
- 迁移请求逐个发，不要并发。观看历史里的 `lv` 可以不迁移：进房时适配器返回主播的房间。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 | 评论（17-3）：详情的 `danmakuData` 是 `NiconicoDanmakuArgs(roomId, programId)`；用 `NiconicoSite.openSeat(roomId)` 开座位（读观看页，走本平台的代理路由），`seat.messageServer` 是评论服务器（NDGR，样本 `danmaku/S07-live`）。主播换了一场（座位 `disconnect` 的 `END_PROGRAM`，或观看页的节目号变了）要重新开座位。`getDanmaku()` 仍是空的弹幕源，接入时换成“平台 → 弹幕连接”的表 |
| G、H01.1 | 配方不变（节目号 + 变体）。主播房间的配方是画质探测时在播的那一场；那一场结束后（座位 `disconnect`），从房间重新取详情和画质，就跟到主播的下一场 |
| J02.1 | 上面的身份迁移；按 E05.2 存 `startedAt`、`restriction`。没有设置、画质要迁移 |
| M13 | 关注按适配器返回的房间号（用节目号或节目链接进房，得到的是主播）；外部打开用 `NiconicoApi.watchUrl(房间号)`（网页上 `watch/user/<id>`、`watch/ch<号>` 同样是最新一场）；公告按 `NiconicoRoomData`：主播房间没有“只对应本场”一句，官方节目仍有，`paid` 且可看时可以提示“付费节目，可以免费看开头”；卡片按 `restriction` 标受限，发现页是否隐藏；开播时间只在直播中显示；最近节目翻页的跨页去重 |

### 受阻和未核实

没有受阻的条目。以下没有样本，按页面字段实现、用合成数据测试：

- 在播但匿名不能看的节目（私密、付费且没有免费开头、仅关注者）：这次读的 7 个分区 534 行和两次搜索 33 行里，`isPayProgram`、`payment`、`isFollowerOnly` 全是假；只有样本 S01-face 的频道付费节目 `isPayProgram` 为真（能免费看开头）。观看页上的三种拒绝按字段名 `isPrivate`、`payment`、`isFollowerOnly` 判断。
- `sp.live.nicovideo.jp`、`nico.ms` 的链接没有实际请求：适配器不请求它们，只取节目号（写法同归档 v4 规格 §1）。
- 同一个用户同时有两场在播时 `watch/user/<id>` 给哪一场；列表同一页里只留先出现的一场。

### 与 v3 冻结输出的新差异

`expected.json` 没有改。样本对照测试里用 `changed:` 列出（注释写条目编号）：

- S01 三页、S02：每张卡的 `roomId`、`link`（17-1）；另外逐行断言 v3 的节目号仍在同一位置、新身份按 `roomIdOf` 得出。
- S03 四个观看页（三种深度）：`roomId`、`link`、`notice`（17-1），S03-watch-channel 的 `avatar`（17-1）；另外断言 v3 的值（节目号、带“收藏对应本次节目”的公告、频道空头像）。

E05.2 的新键（`startedAt`、`restriction`）和 `introduction`（17-5）、`danmakuData`（17-3）单独断言。

### 新样本

2026-09-28 18:12 UTC 经本机代理录制，匿名，请求头是 `NiconicoApi.headers`，不跟随跳转；`raw` 记原始回答的 SHA-256 和长度。脱敏的值换成同形的随机值，写入前检查原值都已不在。v3 对它们没有需要冻结的输出，不带 `expected.json`。门禁的 `fixture privacy` 通过。

| 样本 | 内容 | 脱敏（`meta.json` 的 `scrubbed`） |
|---|---|---|
| `S02-search-channel` | 关键词“ニュース”的在播搜索：12 条，用户 8、频道 3（其中两个频道属于同一个提供者“有限会社阿部珈琲館”）、官方 1（没有 `supplier`，社群 ch2525） | Set-Cookie `nicosid` 和回显它的 `x-niconico-sid` |
| `S03-watch-official` | 官方节目 lv351173882（在播）：`providerType` 为 `official`，`supplierType` 为 `channel`，社群 ch2627923；座位路径没有 `unama` | 座位地址和 `audienceToken` 里的匿名令牌，Set-Cookie `nicosid`、`audience_token`、`nicolivehistory` |
| `S03-watch-official-channel` | 一分钟后的 `watch/ch2627923`：2025 年的频道节目 lv348051859（已结束），不是在播的官方节目 | `audienceToken`，同上三个 Set-Cookie |
| `S03-watch-channel-ended` | `watch/ch2640864`：S03-watch-channel 那一场已结束，付费，页面给出时移座位地址 | 同 `S03-watch-official`，另有 `csrfToken` |

主播的公开信息（名字、头像、节目标题、简介）按 E03.5 的口径保留。

### 测试

本平台 307 个用例（E03.5 是 223 个；新增和改写的见下），`live_core` 全部通过，门禁 `--all` 通过：

- `niconico_api_test.dart`（229 个）：S01、S02 的主播身份和 v3 对照、开播时间、受限类型；新样本 S02-search-channel 的三种身份；S03 四个观看页按主播身份对照 v3、按主播页请求得到同一个房间、频道头像、付费频道的免费开头、简介、开播时间、评论参数；官方节目和它的频道页、已结束的频道；404 和各种身份不符；房间号的形式和 `roomIdOf` 的规则；七种受限情况的受限类型和取流错误、未开播不填；开播时间的范围；列表行的受限类型；简介的各种写法；同一主播只出一张卡、坏行跳过和全坏报错；主播房间的公告；画质绑定房间；节目链接 9 种、主播链接 11 种、不认的 26 种。
- `niconico_site_test.dart`（78 个）：主播和频道的详情（每种深度 1 个请求）、旧节目号在播 1 个请求、已结束 2 个请求、主播在播另一场、官方节目、`resolveRoomId`、刷新合并、未迁移的旧关注不合并及迁移后合并、不合规的房间号不发请求、别人的主播页；主播房间的画质探测和配方、`openSeat` 接受主播、受限节目在开座位前报原因、标了付费的卡片仍由观看页决定；17-6：进房后播放只读一次观看页、只用一次、旧节目号进房、过期、刷新等不保留、保留期为 0、被拒后重读一次、未开播不保留、取消不重试；主播链接不请求、节目链接读一次观看页、官方节目链接、读不到时退回节目号。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.15 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.15-niconico弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
