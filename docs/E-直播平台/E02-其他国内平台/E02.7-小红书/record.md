# E02.7 小红书

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/xiaohongshu/`（`xiaohongshu_api.dart` 纯解析，`xiaohongshu_site.dart` 请求编排）
- 样本：`fixtures/xiaohongshu`，4 个真实录制（2026-09-27，直连，匿名），来自归档：在播、已结束、不存在三张分享页（`S01-room-*`）和一个失效短链（`S02-shortlink-expired`）。小红书没有弹幕，归档里也没有 `danmaku` 样本。
- 参考：
  - 归档 v4 的小红书适配器和规格（`spec/sites/xiaohongshu.md`）。规格**没有 REG 回归条目**，只有第 10 节“踩过的坑”两条；
  - pure_live_TV `lib/platforms/xiaohongshu/`：与 v3 逐行相同，只是改了导入路径、`title: share.title ?? ''` 等去掉可空，没有行为修复（对照笔记 `small_diffs.txt`、`sub_A.md` 的 xiaohongshu 一节）。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、画质名称、线路顺序和列表内容都按 v3；修好但会改变这些内容的地方，列入“后续升级候选”；关注刷新和列表的请求不比 v3 多。

## 做法

- **仅链接，照 v3**：网页版的直播列表要登录签名（`x-s`），匿名拿不到目录。v3 实现过的能力全部保留：
  - 目录分页（`LiveSiteDirectoryPager`）和目录说明（`LiveDirectoryNotice`，键 `xiaohongshu_directory_scope`）：目录永远是空的，不发请求；
  - 关注刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、取流（`LivePlayUrlResolver`）、恢复（`LivePlayRecoveryResolver`）；
  - 另加 `LiveSiteLinks`（分享页、短链、App 深链、分享文本）。
  - v3 没有 `LiveCancellableSearch`、`LiveSearchPaginationPolicy`，这里也不加。
- **房间就是公开分享页** `https://www.xiaohongshu.com/livestream/<房间号>`：
  - 匿名 GET，请求头是 v3 的 `XiaohongshuApi.headers`（`Referer: https://www.xiaohongshu.com/`、安卓 Chrome 87 UA），不带 Cookie；
  - **不跟随跳转**：回答必须是请求的那一页（v3 同样）；
  - 所有请求以 `xiaohongshu` 的名义发出，代理由应用按平台注入（live_net 的 `ProxyPolicy`）；
  - 进房、刷新、录制、状态查询、搜索都是这一个请求（v3 也是每次一个）。
- **页面解析照 v3**（`XiaohongshuShare`）：
  - 页面里恰好一个以 `window.__INITIAL_STATE__=` 开头的 `<script>`；字符串以外的裸 `undefined` 换成 `null`，其余必须是严格的 JSON（不执行脚本）。用的是 AcFun 时加进 `live_core` 的 `HtmlElement`，不引入 package:html；
  - 状态在 `liveStream` 下：`roomInfo.status` 2 且 `liveStatus` 为 `success` 是直播，3 且 `end` 是已结束，其他状态码显示为“未知”（v3），两者矛盾是 `ApiChanged`；
  - 页面自己的 `roomId` 有就必须等于请求的号码，直播页必须有；
  - 结束页的 `nextRoomInfo` 是平台推荐的另一场直播，带着它自己的拉流地址，**从不读取**；
  - `monetizeType` 不为 0 或 `joinLimitTypes` 有非 0 项是“受限”，两个字段缺一个是“未知”，这两种都不读拉流地址；
  - 标题、昵称、封面、头像、`displayViewerCount` 必须是 4096 字以内的字符串；页面超过 2 MiB 是 `ApiChanged`。
- **房间照 v3**：
  - 房间号就是请求的号码（每场直播一个新号，关注跟踪的是这一场）；没有主播号（`userId` 为空，v3 有意不填）；
  - 没有人数：`watching` 为空、口径 `unknown`；平台的展示观看值（“300万+”）只写进公告；
  - 公告是 v3 的三行文字（3.x `zh.json` 的中文）：房间号跟踪说明；受限或未知时加“存在访问条件”；有展示观看值时加“平台展示观看值：…（非已验证的实时在线人数）”；
  - `link` 是分享页地址。
  - 进房和录制的房间带 `XiaohongshuRoomData`（请求的号码、状态、是否公开、原样的 `pullConfig`、展示观看值）；刷新和搜索卡片不带（v3 同样）。
- **画质和线路照 v3**：
  - `pullConfig` 的 `h264` 行在前、`h265` 行在后；每个“编码 + `quality_type`”一个画质，id `h264:HD`，名称 `原画 · H264`，排序 0；
  - 每个地址一条线路，按页面顺序（录到的页面是 HLS 在前，3 条 FLV 在后）；格式按路径（`.m3u8` 是 HLS）；编码 `avc`/`hevc`；线路编号 `<格式>:<主机第一段>`（如 `flv:live-source-play-bak-tx`）；
  - 请求头就是 v3 `PlaybackHeaderResolver` 里小红书的那一组（与页面请求相同）；
  - 地址是没有签名的 http，没有有效期，所以没有 `PlayLease`；
  - 地址的约束照 v3：http(s)、默认端口、`xhscdn.com` 的子域名、没有用户名和片段、路径正好是 `/live/<房间号>.flv` 或 `.m3u8`，每个编码最多 32 行。
- **取流前的检查照 v3 的 `_snapshot`**：已结束或状态未知是 `StreamUnavailable`，受限或未知是 `NeedsLogin`，没有地址是 `StreamUnavailable`，地址不合规是 `ApiChanged`。
- **恢复时重新读分享页**（v3），同一个画质 id 必须还在，不悄悄换档。
- **搜索照 v3 的精确查找**：
  - 房间号、分享页链接、App 深链直接得到房间号；`xhslink.com` 短链在 12 秒内逐跳读 `Location`（不跟随跳转、不下载落地页），只在 `xhslink.com` 内继续；
  - 其他关键词、第 2 页以后都返回空，不发请求；
  - 找到号码后请求一次分享页，得到刷新深度的房间（没有 `data`）；404 返回空，其他错误照样抛出（v3）。
- **链接照 v3 的 `XiaohongshuLink`**：
  - 分享页：主机只能是 `www.xiaohongshu.com` 或 `xiaohongshu.com`，路径 `/livestream/<号>`、`/livestream/dynpath<8 位>/<号>`（分享跳转的中间形式）、`/hina/livestream/<号>[/<别名>]`；路径按原样检查，不能有百分号转义、反斜杠和点段；
  - 深链：`xhsdiscover://live_audience?room_id=<号>&source=<非空>`，`room_id`、`source` 各恰好一个，不能有路径、端口、用户名和片段；分享文本里的深链前面不能紧贴别的链接字符，遇到中文标点截断；
  - 短链：`xhslink.com/<码>`、`xhslink.com/m/<码>`。`resolveUrl` 自己逐跳，只有小红书房间才算结果，落到别处（首页、笔记、主页、别的网站）返回 null，**不交给其他平台**（v3 就不接受）。
- **没有弹幕、没有账号**：v3 是 `EmptyDanmaku`，分享页的 `comments` 匿名时为空，所以没有弹幕参数类；v3 也没有小红书的 Cookie 和登录，所以不注入 `CookieVault`。

## 审查发现的 v3 问题

位置简写：`S` = `legacy/lib/core/site/xiaohongshu/xiaohongshu_site.dart`，`A` = `xiaohongshu_api.dart`，`H` = `xiaohongshu_share.dart`，`L` = `xiaohongshu_link.dart`，`phr` = `legacy/lib/player/core/playback_header_resolver.dart`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 字段写成字符串的页面（`"status":"2"`、`"joinLimitTypes":"[0]"`，归档规格 2026-09-27 记录的形状）整页报“结构错误”，房间打不开 | H:157-158、H:172-179 | 按 JSON 类型严格检查：`status`、`monetizeType` 必须是整数，`joinLimitTypes` 必须是整数列表 | 同样的整数写成字符串也接受（只在 v3 失败的地方兜底）。录到的三张页面都是整数，v3 能解析（见下文）；归档规格和上游笔记说“v3/TV 已坏”，按样本看并不成立 |
| 2 | 一个拉流地址不合规，整个房间都失败：进房、关注刷新、搜索全都报错 | H:187-189、H:205-246 | 读页面时就校验 `pullConfig` | 读页面时只记下原样的 `pullConfig`，取流和录制时再校验（`ApiChanged`）；房间资料和状态照常 |
| 3 | 没有 `data` 的房间（搜索卡片、关注刷新得到的房间）取画质、取地址、恢复都报 identity 错误 | S:121-126（`_snapshot`）、S:85-86、S:114 | 只认进房时的分享页快照 | 先读一次分享页再取；正常进房流程不受影响 |
| 4 | 已结束的房间取画质得到空列表，播放器拿不到原因 | S:143 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 5 | 不存在的房间（`pageStatus: "error"`，“未找到直播间，请稍后再试”）报的是笼统的 `api` 错误 | H:146-148 | v3 认为前端对网络、不存在、受限用同一个错误页 | `NotFound`（平台自己的提示就是“未找到直播间”，样本 S01-room-notfound 是不存在的房间）；搜索里仍然报错，同 v3 |
| 6 | 各种失败都是平台自己的 `XiaohongshuException`，播放和录制只能按种类名判断 | H:5-24、A:91-99、S:121-137 | 平台自定义异常 | 类型化错误：401/403/406 `RiskControl`，404 `NotFound`，429 `RateLimited`，5xx 和其他状态（含跳转）`NetworkFailure`，结构和身份不符 `ApiChanged`，受限 `NeedsLogin`，不能播放 `StreamUnavailable`；取消原样抛出 |
| 7 | 平台层依赖全局 `HttpClient`，自己实现流式读取（2 MiB、20 秒）和请求作用域 | A:25-66、A:68-86 | 结构问题 | 注入 `LiveHttp`；20 秒由 live_net 的请求超时负责；2 MiB 在解析前检查一次 |
| 8 | 每次解析都把整页再 UTF-8 编码一遍来计字节数 | H:81 | 两种长度都查 | 只有长度超过上限三分之一的文本才编码计数（同 Picarto） |
| 9 | 搜索的短链会话每次新建一个 `Dio`，不走应用的代理设置 | S:105、`common/utils/live_short_link_session.dart:7` | 会话自带客户端 | 会话用注入的 `LiveHttp`，以 `xiaohongshu` 的名义请求，走本平台的代理 |
| 10 | 媒体请求头按平台写在播放层 | phr:159-160 | 地址和请求头分开放 | 线路自带请求头 |
| 11 | 平台层调用界面翻译（平台名、公告三行） | S:30、S:72-77 | `i18n` 写在适配器里 | 用 3.x 的中文作默认文字（`XiaohongshuApi.roomScopeNotice` 等），界面的翻译在 M13 |
| 12 | 不是房间号的输入进房报 identity 错误 | H:69-74、S:36-39 | 本地校验失败用 identity | `NotFound`，不发请求；调用方传错参数（目录页码、分类、别的平台的房间）是 `ArgumentError` |

## 样本与 v3 的冻结输出

归档没有小红书的 `expected.json`（旧版对照工具只做了前五个平台，v3 应用也已经构建不了）。本模块用 `fixtures/xiaohongshu/legacy_expected.dart` 生成，做法同 TwitCasting、猫耳：

- 把 v3 的 `XiaohongshuShare`、`XiaohongshuLink`、`XiaohongshuApi`、`XiaohongshuSite` 原样搬进一个 Dart 脚本。v3 本来就把传输做成可注入的函数（`XiaohongshuRequest`），所以只换了它：按主机和路径读样本，状态码不是 200 时正文为空（同 v3），没有样本的请求抛 StateError；
- 短链会话只保留 `XiaohongshuLink.resolve` 用到的部分（去重预算、不跟随跳转、录下的状态和 `Location`）；
- Dio 的取消令牌、请求作用域和截止时间的竞速、网络路径上的 `readBody` 没有搬；`i18n` 返回 3.x `zh.json` 的文字；
- v3 的 `LiveRoom`、`LivePlayQuality` 只搬用到的部分；输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记请求数；
- v3 用 package:html 找脚本，工作区不依赖它，所以用临时的包配置运行，命令写在脚本开头。这个依赖只用于生成期望值，不进任何包。

4 个样本都有 `expected.json`：三张分享页各记录进房、刷新、录制详情、状态、按房间号和分享链接搜索（及第 2 页）、画质和每档地址、恢复；短链样本记录 `XiaohongshuLink.resolve` 和两种短链搜索。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序和每档地址，另比较请求数。

| 样本 | 结果 |
|---|---|
| S01-room-live | 进房、刷新、录制、按房间号和链接搜索的房间全部一致（房间号、标题、昵称、头像、封面、公告两行、`link`、人数为空）；画质 `原画 · H264`（id `h264:HD`、排序 0）一致；4 个地址和顺序（HLS、3 条 FLV）一致；恢复 1 个请求、地址一致；状态 `true`；每个入口 1 个请求，第 2 页 0 个 |
| S01-room-ended | 房间一致（已结束，公告只有第一行）；`nextRoomInfo` 里另一场直播的地址不读；v3 取画质得到空列表、取地址是 `notLive`，现在都是 `StreamUnavailable`（问题 4） |
| S01-room-notfound | v3 每个入口都抛 “Xiaohongshu api”；现在是 `NotFound`（问题 5），搜索照样报错 |
| S02-shortlink-expired | 一致：1 个请求，302 到首页，不是房间，没有结果；链接前后带文字的输入 v3 不识别、不发请求，现在也一样 |
| 请求 | 地址、请求头（`Referer`、安卓 UA，没有 Cookie）、不跟随跳转与 v3 相同 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 不存在的房间是 `NotFound` | 问题 5。界面看到的仍是加载失败，搜索仍是报错 |
| 2 | 出错抛类型化错误 | 问题 6。状态和分组不变：只有平台说已结束才是未开播，状态码不认识仍显示“未知” |
| 3 | 整数写成字符串的字段也接受 | 问题 1。只在 v3 失败的地方生效；录到的页面结果相同 |
| 4 | 拉流地址在取流时才校验 | 问题 2。房间资料、状态与 v3 相同，只是失败的位置从“进房”移到“播放” |
| 5 | 没有 `data` 的房间取流前先读一次分享页 | 问题 3。只在播放路径上，v3 在这里报错 |
| 6 | 已结束的房间取画质报 `StreamUnavailable`，不发请求 | 问题 4 |
| 7 | 线路自带请求头、格式、编码、线路编号，没有租期 | 问题 10。请求头与 `PlaybackHeaderResolver` 的小红书分支逐项相同 |
| 8 | 图片地址统一经 `normalizeImageUrl` | 与其他平台一致；样本的结果完全相同（保留原样的写法） |
| 9 | 响应只在解析前查 2 MiB；非法 UTF-8 变成替换字符而不是报错 | 问题 7、8；live_net 没有逐请求的大小上限 |
| 10 | 搜索的短链请求走本平台的代理 | 问题 9 |
| 11 | 不是房间号的输入是 `NotFound`，调用方的参数错误是 `ArgumentError` | 问题 12；同 v3 一样不发请求 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **房间号就是请求的号码**，每场直播一个号，关注跟踪这一场（归档 v4 也是）。3.x 存下的关注身份不变。
- **画质按编码分档**：`原画 · H264`、`原画 · H265`，id `h264:HD`。归档 v4 用 `quality_type` 作 id、`原画` 作名称，把两种编码的地址并进一档，会改变画质菜单和已存的画质 id。上游 TV 同 v3。
- **线路按页面顺序（HLS 在前）**：归档 v4 把 FLV 提到前面。
- **拉流地址严格校验**（`*.xhscdn.com`、`/live/<房间号>.*`、默认端口），一行不合规整档失败：归档 v4 接受任何 http(s) 地址。
- **状态码不认识时房间显示“未知”**，不报错；只有 `getLiveStatus` 报 `ApiChanged`（v3 的 schema）。归档 v4 一律 `ApiChanged`。
- **公告照 v3**（房间号跟踪说明、受限说明、平台展示观看值）：归档 v4 没有公告，上游 TV 同 v3。
- **深链必须带非空的 `source`**：归档 v4 不再要求。
- **短链落不到小红书房间就没有结果**（null），不报 `UnsupportedLink`，也不交给别的平台。
- **目录照 v3**：空目录加说明，第 0 页和分类是调用方错误；归档 v4 没有目录接口。
- **搜索照 v3**：只做房间号和链接的精确查找，404 为空、其他错误照抛；归档 v4 没有搜索。
- **受限房间照常显示**（在播），取流时才报错（`NeedsLogin`）。
- **页面请求头只有 `Referer` 和 UA**：归档 v4 多了 `Accept`。
- **刷新和搜索卡片不带 `data`**（v3）。
- 显示名仍是“小红书”。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 搜索不存在的房间号时给空结果，而不是报错 | 报错（v3 的“api”，现在是 `NotFound`） | 平台页面明确说“未找到直播间”；样本 S01-room-notfound |
| 2 | 深链不再要求 `source` 参数 | 没有 `source` 的深链不识别 | 归档 v4 的做法；分享页里的深链都带 `source=share_out_of_app` |
| 3 | 合并两种编码为一档“原画”，线路 AVC 全部在前、其中 FLV 优先 | 按编码分档，HLS 在前 | 归档 v4（FLV 直播更稳），上游笔记建议 10（AVC 全在 HEVC 前）；会改变画质菜单 |
| 4 | 一行地址不合规时只跳过这一行，其余线路照常播放 | 整档 `ApiChanged` | 现在录到的都是合规地址 |
| 5 | 跟随主播：按深链里的 `host_id` 找到主播当前的直播 | 关注只跟踪这一场，主播换号后要重新导入 | 归档规格第 12 节待确认 4，需要先找到可用的接口和样本 |

## 回归条目的覆盖

归档规格没有 REG 条目。第 10 节“踩过的坑”两条都属于平台层，都有测试：

- 字段变成字符串（`status: "2"`、`joinLimitTypes: "[0]"`、`isSportsEvent: "False"`、`pullConfig` 为对象）：解析结果与整数形状相同（问题 1）；
- 结束页的 `nextRoomInfo`：已结束的房间不读它的地址，取流 `StreamUnavailable`（样本 S01-room-ended）。

规格第 12 节待确认的几项没有真实样本，用合成回答覆盖：指向直播的短链（经过 `dynpath` 的跳转、相对跳转、深链落地）、付费和各种限制观看、H.265 和多档画质。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 目录说明（`xiaohongshu_directory_scope`）、公告三行、平台名、人数设置页说明（`audience_xiaohongshu_detail`）的繁体和英文 | M13 多语言。本模块给出 3.x 的中文（`XiaohongshuApi.directoryScope`、`roomScopeNotice`、`restrictedNotice`、`displayViewersNotice`），公告的依据在 `XiaohongshuRoomData`（是否公开、展示观看值） |
| 空目录页显示说明、不翻页（3.x `LiveDirectoryController.pageNotice`） | M13 热门页 |
| 搜索能力表：房间号查找、含未开播、不分页、没有网页搜索（3.x `search_capability.dart:116-120`、`search_controller.dart:109-110`） | M13 搜索页 |
| 外部打开 `https://www.xiaohongshu.com/livestream/<房间号>`（3.x `room_external_opener.dart:141-143`） | M13；地址由 `XiaohongshuApi.roomUrl` 和房间的 `link` 提供 |
| 本地互动包（3.x `local_interaction_controller.dart:369-376`）；多画面不支持小红书弹幕 | M13；D01 |
| 平台列表升级时追加小红书（`favorite_room_controller.dart:68`，`siteCatalogMigration` 第 12 版，从 11 及以下升级时追加） | J02.1 |
| 录制遇到详情错误时是否重试：3.x 的录制对任何详情错误都有限重试（`recorder/services/stream_resolver_service.dart:139-145`）。小红书的页面错误现在是 `NotFound`，而平台提示是“请稍后再试”，H01.1 决定重试策略时要考虑 | H01.1 |
| `getDanmaku()` | 同 E01.1：D01 用一张“平台 → 弹幕连接”的表；小红书没有弹幕 |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出。页面脚本用 AcFun 时加进来的 `HtmlElement`（`html.dart`）查找，短链用 M3 的 `ShortLinkSession`，都不需要改动。

## 测试

219 个用例，`live_core` 共 1333 个，全部通过：

- `xiaohongshu_api_test.dart`（114 个）：逐个样本对照 v3 的输出（在播、已结束的房间各种深度，画质和地址），有意的差异逐条断言（不存在、已结束取流）；线路的请求头、格式、编码、线路编号、没有租期；移植 v3 `xiaohongshu_share_test.dart` 的用例（`undefined` 扫描、非 JSON 表达式、没有或多个状态脚本、超大页面、房间号、身份、各种受限、未知状态、没有 `pullConfig`、结构错误、地址约束、签名查询和去重、32 行上限、状态码）；字符串字段的兜底；H.265 分档；链接规则（深链、分享页别名、非房间地址、短链、跳转、分享文本）。
- `xiaohongshu_site_test.dart`（105 个），用样本回放加合成回答，移植 v3 `xiaohongshu_application_test.dart`（适配器部分）和 `xiaohongshu_share_link_test.dart`：
  - 能力、目录（空、不请求、取消、调用方错误）；
  - 房间：请求地址、请求头、不跟随跳转、平台名；各种深度与 v3 一致且各 1 个请求；关注合并；非法房间号不请求；不存在；未知状态；录制详情的检查；坏地址只影响取流；状态码和传输错误的映射；
  - 搜索：房间号和各种链接各 1 个请求、第 2 页不请求、关键词不请求、404 为空、其他错误照抛、失效短链、短链到房间、请求的 12 秒上限；
  - 取流：进房得到的房间不再请求、编码分档和恢复、恢复时身份变了、受限、已结束、画质没了、卡片先读页面、别的房间的数据不用、别的平台；
  - 链接（经 `LinkParser`）：深链、分享页、点段、非法地址、短链逐跳、各种跳转状态、分享文字、落到别处不请求也不交给别的平台、非跳转状态、多个 `Location`、相对跳转、片段去重、请求预算、失败后继续找后面的链接、取消和超时。

## 升级落地（T02.U）

- 日期：2026-09-29（E02.7）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 5 行（16-1～16-5）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。16-4 的“落地方式”是开发预填的“只在 v3 原本失败的地方生效”，其余 4 行空着，按上面“后续升级候选”的原文做（16-3 照归档 v4 合并两种编码、上游笔记建议 10 让 AVC 全部排在 HEVC 前）。
- 只改了本平台：`xiaohongshu_api.dart`（解析）、`xiaohongshu_site.dart`（请求编排）和两份测试。没有改 `live_core` 的通用文件，没有新依赖，没有新样本。
- 上面“保持 v3 行为”一节里的这几条现在改了：画质按编码分档、线路按页面顺序（HLS 在前）、一行地址不合规整档失败、深链必须带 `source`、公告的文字；“做法”里受限房间取流一律 `NeedsLogin` 也改成按受限类型报。其余照旧：房间号就是请求的号码、状态码不认识显示“未知”、短链落不到房间没有结果、空目录、搜索只做精确查找、请求头、刷新和搜索卡片不带 `data`。
- 实测：2026-09-28 17:50～18:05 UTC 直连，只读地请求了：已结束样本的分享页（`nextRoomInfo` 推荐了另一个在播房间）、这个在播房间的分享页、它的主播主页、网页直播接口 4 个、网页的脚本（`fe-static.xhscdn.com` 的 `main`、`vendor` 和直播页的分块）、在播房间的 FLV 和 HLS 地址。新代码解析这两张新页面的结果正常（在播：一档“原画”，3 条 FLV 在前、HLS 在后，受限类型 `none`；已结束：未开播，没有受限类型）。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 16-1 | 搜索找到房间号后读分享页，页面说“未找到直播间”（`pageStatus: "error"`，`NotFound`）时返回空结果，与 HTTP 404 一样。按房间号、分享页链接、深链、短链搜索都一样。其他错误（风控、限流、网络、改版）照样报错。进房、刷新、录制遇到不存在的房间仍是 `NotFound` | 搜索不存在的房间号或它的链接，显示“没有结果”，不再显示搜索失败 | 完成（T02.U） |
| 16-2 | `XiaohongshuApi.deepLinkRoomId` 不再要求 `source`：`xhsdiscover://live_audience?room_id=<号>` 只要 `room_id` 恰好一个、是合法房间号，`source` 有没有、空不空、有几个都行。其余限制照旧（不能有路径、端口、用户名、片段；分享文本里的深链不能紧贴别的链接，遇到中文标点截断）。搜索、链接识别、分享文本都经过它，一起生效 | 粘贴不带 `source` 的 App 深链（例如分享文字被别的 App 截短了）也能打开房间 | 完成（T02.U） |
| 16-3 | 画质按 `quality_type` 分档，不再按编码：<br>- 录到的 `HD` 是一档，名字用页面的 `quality_type_name`（“原画”），id 是 `HD`；排序仍是 0；<br>- 这一档的线路：H.264 全部在前、H.265 在后；每种编码里 FLV 在前、HLS 在后，其余按页面顺序；<br>- 线路编号 `<格式>:<主机第一段>`（`flv:live-source-play`），H.265 加 `:hevc`，同一主机重复的加 `#2`、`#3`；编码标 `avc`、`hevc`；<br>- 页面以后给多个 `quality_type` 时，每个一档，按地址出现的顺序；<br>- 取流时认 v3 的旧 id（`h264:HD`、`h265:HD`），按对照当作 `HD`，确认画质报新 id | 画质菜单从“原画 · H264”（有 H.265 时还有“原画 · H265”）变成一项“原画”。默认先播 FLV（录到的页面是 3 条 FLV、1 条 HLS），出错时换下一条线路；有 H.265 时排在最后作为备用 | 平台层完成，余下 J02.1 |
| 16-4 | 拉流地址一行一行检查（`_stream`），不合规的只跳过这一行：不是对象、地址不是字符串或超过 4096 字、画质或名称为空或太长、地址不合规（不是 http(s)、不是 `xhscdn.com` 的子域、带用户名或片段、端口不对、路径不是 `/live/<房间号>.flv` 或 `.m3u8`）。整体的检查照旧报 `ApiChanged`：`pullConfig` 不是 JSON 对象、超过 65536 字、编码列表不是列表或超过 32 行、有行但一行都用不上 | 平时看不出变化；某条地址不合规时，其余线路照常播放（v3 整个房间都不能播放和录制） | 完成（T02.U） |
| 16-5 | 没有做，受阻：找不到匿名可用的“按主播找当前直播”的接口，见下文“受阻” | 不变：关注仍跟踪这一场，主播重新开播要重新导入分享链接 | 受阻 |

### 按统一原则补的

| 原则 | 做了什么 |
|---|---|
| 开播时间 | 平台不提供，`startedAt` 不填：分享页的页面状态里没有开播时间（S01 样本和 2026-09-28 新读的在播页都一样）；网页取评论的接口 `get_simple_interaction` 的 `startTimestamp` 是评论的游标，不是开播时间，而且要签名（见“受阻”） |
| 受限类型 | 网页脚本里的枚举：`monetizeType` 是 `Free = 0`、`Paid = 1`；`joinLimitTypes` 是 `GroupChat = 1`（主播的群聊成员）、`Family = 2`、`IpFence = 4`（限定地区）。直播中的房间（进房、关注刷新、录制、按房间号搜索都读同一张页面）按页面填：<br>- 公开 → `none`；<br>- `monetizeType` 不是 0 → `paid`（网页对它显示“本场直播需付费观看”）；<br>- 群聊、`Family` → `private`（只对主播选的一圈人开放；`Family` 的确切含义网页没有文字，按最接近的“私密”）；<br>- `IpFence` → `regionBlocked`；<br>- 其他非 0 值 → `unplayable`；<br>- 几种同时出现时按付费、私密、地区的顺序取第一种；<br>- 公开但页面没给任何拉流地址（没有 `pullConfig`、为空、两个编码列表都空）→ `unplayable`；<br>- `monetizeType` 或 `joinLimitTypes` 缺一个（访问情况不明）→ 留空。<br>已结束、状态不明的房间不填。`XiaohongshuRoomData.restriction` 另外记下页面原样的受限类型（任何状态都有），`access` 由它推出。<br>取流时按类型报错：`paid`、`private`、`unplayable` 报 `StreamUnavailable`（说明里写原因），`regionBlocked` 报 `RegionBlocked`，访问情况不明照 v3 报 `NeedsLogin`。受限房间照旧不读拉流地址（v3 同样） |
| 受限的直播改为直播中 | 本来就是：v3 的受限房间照常显示在播，没有用 `banned`、`unknown` 表示受限 |
| 回放、不可播放 | 平台没有直播回放：结束页只有“直播已结束”和别人的推荐。网页里的 `replayInfo.replayNoteId` 只用于体育赛事，是一篇视频笔记，不是这场直播的回放地址，不涉及。在播但拿不到地址的标 `unplayable`（见上一行） |
| 占位信息 | 没有发现占位值：标题、昵称、封面、头像缺失时本来就留空（v3 同样），页面也不给默认封面 |
| 房间身份 | 不变：房间号是数字，没有大小写问题 |
| 容错 | 见 16-4。页面是单个房间，读不出来照旧报错 |
| 翻页 | 不涉及：没有目录，搜索只有第 1 页 |
| 画质命名 | 见 16-3：页面给的源画质名字就是“原画” |
| 默认编码 | 见 16-3：H.264 线路全部在前，H.265 线路标 `hevc` 排在最后。“优先 H.264”设置在 G；关掉时由 G 按线路的编码调整顺序 |
| 按主播关注 | 见 16-5，受阻 |
| 弹幕 | 不涉及：本平台不在要接入弹幕的平台里；匿名的页面 `comments` 为空，网页轮询评论的接口要签名 |
| 说明文字 | 公告三行和目录说明是 3.x `zh.json` 的原文，里面有“以直播房间号跟踪”“公开完整直播源”“非已验证的实时在线人数”“导入官网 /livestream/ 分享链接”这类开发说明，改成用户看得懂的话（多语言键不变，见下表）。另外把 v3 合在一起的“受限或待确认”拆成两行：受限的房间说明有观看条件，访问情况不明的房间说明暂时无法确认 |

公告和目录说明（中文默认值，在 `XiaohongshuApi` 里）：

| 3.x 的键 | 3.x 的原文 | 现在 |
|---|---|---|
| `xiaohongshu_room_scope`（`roomScopeNotice`，每个房间的第一行） | 当前以直播房间号跟踪；主播重新开播使用新房间号时，请重新导入分享链接。 | 小红书每场直播都有新的房间号，这里关注的是这一场。主播下次开播时，请重新导入新的分享链接。 |
| `xiaohongshu_restricted`（`restrictedNotice`，受限的房间） | 该房间存在访问条件或访问状态待确认，当前没有可用的公开完整直播源。 | 这场直播设置了观看条件（付费、仅限部分观众或限定地区），这里无法播放。 |
| 新增（`unknownAccessNotice`，访问情况不明的房间；3.x 用上一行） | — | 暂时无法确认这场直播是否公开，这里可能无法播放。 |
| `xiaohongshu_display_viewers`（`displayViewersNotice`） | 平台展示观看值：300万+（非已验证的实时在线人数） | 小红书显示 300万+ 人看过（累计的约数，不是在线人数）。依据：网页把 `displayViewerCount` 显示成“…人看过” |
| `xiaohongshu_directory_scope`（`directoryScope`，目录说明） | 暂无已接入的公开直播目录。请在搜索页输入直播房间号，或导入官网 /livestream/ 分享链接；收藏仅跟踪该直播房间，不代表跨场次跟随主播。 | 小红书没有公开的直播列表。请在搜索页输入直播房间号，或粘贴小红书的直播分享链接或分享文字；关注的是这一场直播，主播下次开播时要重新导入。 |

### 画质 id 对照（给 J02.1）

| v3 的 id（v3 的名字） | 新 id（新名字） | 说明 |
|---|---|---|
| `h264:HD`（原画 · H264） | `HD`（原画） | 同一路流，现在是“原画”里的 H.264 线路 |
| `h265:HD`（原画 · H265） | `HD`（原画） | 同一路流，现在是“原画”里的 H.265 线路（排在最后） |
| `h264:<quality_type>`、`h265:<quality_type>` | `<quality_type>` | 规则相同；录到的页面只有 `HD` |
| 其他 | 不变 | — |

- 代码：`XiaohongshuApi.legacyQualityIds`（常量表，录到的两个 id）、`XiaohongshuApi.qualityIdFromLegacy(id)`（去掉首尾空白，查表，再按 `h264:`/`h265:` 前缀去掉编码，编码不分大小写；都不是就原样返回）。可以重复套用：新 id 不带编码前缀。
- 适配器取流、恢复时也认旧 id（确认画质报新 id），漏迁的也能播。
- v3 的全局画质偏好按名字存（原画、蓝光8M……），不是本平台的 id。v3 的“原画”对不上“原画 · H264”，按比例落到第一档；现在“原画”能直接对上。没有要改名迁移的偏好。

### 设置项

无。本平台的 5 行都不需要开关。

### 身份迁移规则（给 J02.1）

- 房间身份不变：仍是每场直播的房间号（16-5 受阻），3.x 存下的关注照常刷新，没有要迁移的身份。
- 以后找到接口、改为按主播关注时的规则（现在不生效，留作依据）：主播的 id 是在播页 `roomInfo.deeplink` 里的 `host_id`（24 位十六进制，如 `683946f7000000001d0085c9`）；已结束的页面没有 `deeplink`，所以旧的单场关注只有在那一场还在播时才能从页面换到主播，已结束的换不了，只能保留单场身份。

### 请求数

没有变化：进房、关注刷新、录制、状态查询、按房间号或链接搜索各 1 个分享页请求；短链每跳 1 个；目录 0 个；取画质和第一次取流 0 个（卡片没有 `data` 时先读 1 次）；恢复 1 个。16-1 只是把已经拿到的回答当成空结果，不多发请求。测试断言了请求数。

### 与 v3 冻结输出的新差异

样本对照测试里用 `changed:` 列出、原因写在旁边；`expected.json` 没有改：

- S01 在播、已结束的房间（进房、刷新、录制、两种搜索）：`notice`（说明文字原则），测试逐行核对新文字就是 v3 那几行换了说法、行数和顺序不变；v4 的新键由 `added` 断言：在播是 `restriction: none`，已结束没有；两者都没有 `startedAt`。
- S01 在播的画质：`quality`、`id`（16-3），测试断言 v3 的 id 经 `qualityIdFromLegacy` 就是新 id；每档地址（16-3），同样的 4 个地址，顺序改为 3 条 FLV 在前、HLS 在后。
- S01 不存在：按房间号和链接搜索从报错改为空结果（16-1）；进房仍是 `NotFound`。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| G | 一个画质多条线路：FLV 在前、HLS 在后，出错时换下一条；有 H.265 时排在最后，线路标 `hevc`，“优先 H.264”关掉时由 G 调整顺序。地址不签名、没有租期；FLV 地址先 302 到 CDN 节点，要跟随跳转（2026-09-28 实测，跟随后是正常的 FLV 头） |
| J02.1 | 存下的画质 id 按上面的对照换成 `HD`（16-3） |
| M13 | 受限类型的标记（付费、私密、限定地区、不可播放）和播放失败时的说明；四段文字（`xiaohongshu_room_scope`、`xiaohongshu_restricted`、新增的访问情况不明、`xiaohongshu_display_viewers`）和目录说明 `xiaohongshu_directory_scope` 的多语言，中文以上表为准；搜索页对不存在的房间显示“没有结果”；画质菜单只有“原画” |
| D01 | 无：本平台没有弹幕 |

### 受阻

**16-5 跟随主播**：卡在找不到匿名可用的接口。2026-09-28 只读地试过：

| 途径 | 结果 |
|---|---|
| 分享页 `/livestream/<房间号>` | 在播页的 `roomInfo.deeplink` 带主播的 `host_id`，这是唯一公开给出主播身份的地方；已结束的页面没有 `deeplink`，也没有 `host_id` |
| 结束页的 `nextRoomInfo` | 平台推荐的别人的直播，不是这个主播的下一场（S01-room-ended 里是另一个主播；新读的一次也是） |
| 主播主页 `www.xiaohongshu.com/user/profile/<host_id>` | 匿名请求 302 到验证码页（`/website-login/captcha`，手机 UA）或登录页（`/login`，桌面 UA） |
| 网页直播接口（`live-room.xiaohongshu.com/api/sns/red/live/h5/v1/…`：`room/current_room_info`、`core/current_live_status`、`room/stop_info_2c`（带 `hostId`）） | HTTP 406，回答 `{"code":-1,"success":false}`：要网页的签名请求头，和目录要 `x-s` 签名是同一个原因。而且这几个接口都按房间号查，只有结束页推荐接口收 `hostId`，返回的也是推荐列表 |
| H5 用户信息 `www.xiaohongshu.com/api/sns/h5/v1/user_info` | HTTP 500（`create invoker failed`） |

网页脚本里也没有“按主播找当前直播”的接口。要做需要登录 Cookie 或网页签名（不在本次范围，也会违背“匿名可读”的前提），所以保持单场关注。以后若有可用接口，身份迁移按上面“身份迁移规则”里的 `host_id` 做。

没有样本、只靠实测的部分：受限类型的枚举来自网页脚本（2026-09-28 的 `c5137` 分块），没有录到付费、私密、限定地区的真实页面，测试用合成回答；`Family` 的确切含义网页没有文字说明。

### 新样本

无。开播时间、受限类型、画质合并、容错、深链都用已有的 4 个样本加合成回答；实测读到的页面和脚本没有录成样本。

### 测试

本平台 245 个用例（新增 26 个，另改写了画质、线路、受限、地址约束、深链、搜索不存在的用例），`live_core` 共 3094 个，全部通过；门禁 `gate.sh --all` 通过：

- `xiaohongshu_api_test.dart`（135 个）：
  - 样本对照：`notice` 逐行核对、`added`（在播 `none`、已结束没有）、没有开播时间；画质“原画”、id 对照、FLV 在前的 4 个地址；
  - 受限类型：付费（两种值）、群聊、`Family`、地区、未知限制、几种同时出现的优先级；访问情况不明留空并报 `NeedsLogin`；已结束和状态不明的房间不填；公开但没有地址（4 种写法）标 `unplayable`；读不出的 `pullConfig` 不标；
  - 16-4：8 种不合规地址、7 种不完整的行各自只跳过一行，全部不合规报 `ApiChanged`；不是对象的行跳过、另一种编码照常；
  - 16-3：两种编码合成一档的线路顺序和编号、多个 `quality_type` 分开、同主机重复编号、旧 id 对照和取流、没有的画质；
  - 16-2：不带 `source`、空 `source`、多个 `source`、带 `host_id` 的深链，分享文本里的深链；缺 `room_id`、空 `room_id` 仍不认。
- `xiaohongshu_site_test.dart`（110 个）：
  - 各深度与 v3 一致（`notice` 除外）并带受限类型；目录说明的键不变、文字改写；
  - 录制：付费、地区、访问不明、没有地址、状态不明各自的错误，刷新里的受限类型；
  - 16-4：一条坏地址只少一条线路、录制照常，全坏时取流和录制报 `ApiChanged`、页面照常；
  - 16-1：不存在的房间按号和链接搜索为空、各 1 个请求，短链到不存在的房间为空；其他错误照抛；
  - 取流：一档“原画”、FLV 在前；旧 id `h264:HD` 能取流和恢复；两种编码合档后重排和恢复；恢复遇到付费报 `StreamUnavailable`；
  - 16-2：不带 `source` 的深链经 `LinkParser` 导入，不发请求。
