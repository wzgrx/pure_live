# T02b.3 AcFun 直播

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/acfun/`（`acfun_api.dart` 纯解析，`acfun_site.dart` 请求编排）
- 样本：`fixtures/acfun`，13 个真实接口录制，来自归档，另有弹幕样本 `danmaku/S07-live`（T06a 用）。归档没有 `expected.json`，这次按 SOOP（T02c.1）的做法补上，方法见下文。
- 参考：
  - 归档 v4 的 AcFun 适配器和规格（`spec/sites/acfun.md`，其中 7 条回归条目 REG-ACFUN-001～007）；
  - pure_live_TV `fbbe6521`：与 v3 相同，只是文字多语言化、改用不可变模型（`copyWith`），没有行为修复；
  - 对照笔记 `~/ref/notes/tvcore/sub_A.md` 的 acfun 一节，其中指出归档 v4 的两个风险，都已核实并避开（见“保持 v3 行为”第 1、2 条）。

按 T02a.1 的做法：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称和列表内容都按 v3；关注刷新和列表的请求不比 v3 多。

## v3 的冻结输出

归档只给五个大站生成过 `expected.json`。这次按 SOOP 的口径补上：

- 把 v3 的 `core/site/acfun/` 四个文件、`LiveRoom`、`LiveArea`、`LivePlayQuality`、`LiveCategory`、`LiveAnchorItem`、`HttpHeaderPolicy` **原样复制**到一个临时的纯 Dart 包里（依赖 v3 用的 `html`、`dio`），只把运行环境换成桩：
  - `HttpClient` 按请求回放样本，和 Dio 一样：JSON 类型的响应解码成对象（先按 v3 的 `CustomTransformer` 把 `json;` 改成 `application/json`），其他保持文本，非 2xx 抛出；
  - `LiveSite` 的各接口是 v3 的默认实现，弹幕和房间音量是空操作。
- 逐个样本调用 v3 的入口：`getCategores`、`getRecommendRooms`（第 1、2 页）、`getCategoryRooms`、`AcfunSearchClient.parsePage`、`searchRooms` 和 `searchAnchors`（v3 搜索页用的每页 20 条）、`getRoomDetailForRefresh`、`getLiveStatus`、`getRoomDetail`、`getRoomDetailForRecording`、`getPlayQualites`、`getPlayUrls`、`AcfunApi.playback`。抛出的异常记为 `throws`（含 v3 的错误种类和 `result`），同时记下 v3 发出的请求（地址、表单、请求头）。
- 房间的投影与其他平台相同：`toJson` 加上 `link`，去掉 null 和空集合；进房得到的播放数据（`AcfunPlayback`）写在 `data`。
- 访客的设备号是随机的，写成 `web_{did}`。

## 做法

- **接口和输出沿用 v3**：`LiveSite` 和 v3 实现过的可选能力（关注刷新、录制详情、恢复取流），外加取流线路（`LivePlayUrlResolver`）和 `LiveSiteLinks`。3.x 的 JSON 不变。
- **全部匿名**，v3 没有 AcFun 的 Cookie 设置，这里也不注入 `CookieVault`。
- **请求照 v3**：
  - 列表、分区、详情、访客登录、`startPlay` 都带 v3 的 `playHeaders`（Chrome 140 的 UA、`Referer: https://live.acfun.cn/`），登录另带 `Cookie: _did=web_<16 位字母数字>;`；
  - 搜索带 UA 和 `Referer: https://www.acfun.cn/search`（没有 UA 时站点答 403，REG-ACFUN-006）；
  - 请求次数：分类 1 个（`count=1`，不动任何列表的游标）、列表每页 1 个、搜索每页最多 4 个服务端页、关注刷新和开播状态各 1 个（只有 `live/info`，从不登录）、进房和录制是 `live/info` 加（在播时）访客登录和 `startPlay`，都与 v3 相同。
- **房间号保持请求时的号码**（作者 id，只去掉首尾空白）。这一场直播的 `liveId`、画质和签名地址放在 `AcfunRoomData`（v3 的 `AcfunPlayback`）。
- **访客会话**：内存里复用 5 分钟，并发调用共用一次登录（v3）。`startPlay` 被拒（`result` 不是 1 也不是 129004）时丢掉会话、当次换新会话再请求一次（REG-ACFUN-003）；129004（直播已关播）是 `StreamUnavailable`，保留会话。`acSecurity` 可以没有，只有弹幕用它。
- **分页**：站点用不透明游标（`pcursor`）翻页，这里仍按页码提供，与 v3 相同：
  - 列表：每个“每页条数 + 分区”一条游标链，第 1 页的新请求就是刷新（开始新链，正在加载的第 1 页共用）；最后一页之后的页直接为空，不发请求（T02.U 起跨页去重，见文末）；
  - 搜索：服务端每页 30 条，应用的每页（v3 搜索页用 20）从服务端页里依次切出，短页不会让结果提前结束（REG-ACFUN-002），页号 × 30 达到 `data-total` 才结束；一页最多 8 秒、4 个服务端页；第 1 页的新请求重新开始，并取消旧搜索的请求。
- **取流**：画质来自进房时的 `startPlay`（`videoPlayRes` 是 JSON 字符串），按 v3 的排序值从高到低；每个画质在每个清单（CDN）里各一个地址。线路带 v3 播放层的请求头（UA、`Referer`、`Origin: https://live.acfun.cn`）、格式（路径 `.flv` 为 FLV，`.m3u8` 为 HLS）、CDN 主机作线路编号，以及按 `auth_key` 算出的租期：第一段是 Unix 秒的到期时间（签发后 30 天），提前 10 分钟续期（最多提前有效期的四分之一），到期不断开已建立的连接。恢复时重新请求 `startPlay`。
- **弹幕**：v3 没有接 AcFun 弹幕（`EmptyDanmaku`）。进房时本来就要请求 `startPlay`，这里把网页端长连接需要的值整理成 `AcfunDanmakuArgs`：作者 id、`liveId`、访客会话（用户 id、设备号、令牌、可空的 `acSecurity`）、`availableTickets`、`enterRoomAttach`，另有 `refresh`（新会话、新 `startPlay`）。协议和是否接入由 T06a 决定。

## 审查发现的 v3 问题

位置简写：`site` = `legacy/lib/core/site/acfun/acfun_site.dart`，`api` = `.../acfun_api.dart`，`dir` = `.../acfun_directory.dart`，`search` = `.../acfun_search.dart`，`phr` = `legacy/lib/player/core/playback_header_resolver.dart`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 取流偶发失败，要再点一次才好 | api:279-283 | `startPlay` 被拒时只把会话作废，本次请求照样失败，下一次才用新会话 | 当次换新会话再请求一次，仍被拒是 `RiskControl`（REG-ACFUN-003） |
| 2 | 翻页报“分页过期” | dir:27-28、39；search:71、80、86 | 页码和游标的对应存在共享的序列里：另一处刷新第 1 页、序列被挤出缓存、或另一页正在加载时，请求就直接失败 | 列表：缺游标时把前面的页重新读一遍；搜索：另一页在加载时等它完成，序列不对时按这一页的位置重新开始（REG-ACFUN-004） |
| 3 | 一张卡片或一个分区不合格，整页、整个目录、整路流都失败 | site:85-90（经 api:220-230）；search:175-186；api:199-201、296、307 | 逐项校验失败时抛出整页的错误 | 不合格的卡片、分区、清单、画质跳过；答复外层（`result`、`liveList`、`pcursor`、搜索总数和“无结果”标记）仍严格校验 |
| 4 | 不存在的主播报“格式错误”；刚关播的房间报“服务错误”；HTTP 403、429、5xx 都算网络错误 | api:223-224、279、106-112 | 只有 transport/service/schema 三种错误，HTTP 状态码被丢掉 | 类型化错误：`NotFound`、`StreamUnavailable`、`RiskControl`、`RateLimited`、`NetworkFailure`、`ApiChanged` |
| 5 | 直播中的房间只要缺 `streamName` 就整个详情失败 | api:228 | 要求 `liveId` 和 `streamName` 同时有或同时无 | 只看 `liveId`（归档 v4 和规格的做法） |
| 6 | 未开播的房间取画质返回空列表，看不出原因 | site:146 | — | `StreamUnavailable`（不发请求）；界面照旧显示无法播放 |
| 7 | 列表卡片（没有播放数据）直接取画质报“格式错误” | site:148、158 | 只认进房得到的 `AcfunPlayback` | 先请求 `startPlay`（只在播放路径上） |
| 8 | 恢复取流把整个房间重新读一遍 | site:166-173 | 复用 `getRoomDetail` | 只请求 `startPlay`，少一个请求 |
| 9 | 详情没有简介，而搜索卡片有 | site:36-58；search:200 | 没读 `user.signature` | 详情的简介取主播签名（与搜索卡片同一段文字） |
| 10 | 会话、列表游标和搜索序列是全局静态对象 | site:18-24 | 共享单例 | 每个适配器实例各有一份（注册表每个平台只建一个） |
| 11 | 播放请求头按平台写在播放层 | phr:168-169 | 地址和请求头分开放 | 线路自带请求头 |
| 12 | 超过 512 字的关键词、页码小于 1 直接报错 | search:64；dir:22 | — | 长关键词照常请求；页码按 1 处理 |

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson` 和 v3 的冻结输出；画质、线路地址、请求另外比较。

| 样本 | 结果 |
|---|---|
| S01 分类（`count=1`） | 一个分类（id `acfun`，名称“AcFun 直播”），5 个分区（含“全部”）、顺序、类型、图片一致；v3 的 `shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S01 推荐（19 个房间，一页） | 房间、顺序、各字段一致；第 2 页不发请求、返回空，与 v3 一致 |
| S02 游戏分区（8 个房间） | 一致，请求（含 `filters`）一致 |
| S04 搜索第 1 页、第 4 页、模糊匹配、无结果 | 作者、顺序、总数、“2.4万”这样的粉丝数、简介、状态（都是未开播）一致 |
| S04 搜索（v3 搜索页每页 20 条） | 前 20 条与 v3 一致，搜索主播一致 |
| S05 详情（直播、未开播） | 除简介（新增，见下）外一致；未开播没有标题、封面、人数，与 v3 一样 |
| S05 不存在的主播 | v3 是格式错误，现在是 `NotFound` |
| S06 访客登录 | 表单、Cookie 格式、UA、Referer 一致；`startPlay` 的查询参数（顺序也一致）、表单一致 |
| S06 `startPlay`（直播） | `liveId`、四档画质的 id、名称（蓝光 8M、蓝光 4M、超清、高清）、排序值、地址一致；`getPlayQualites`、`getPlayUrls` 一致 |
| S06 `startPlay`（关播） | v3 是服务错误（129004），现在是 `StreamUnavailable` |
| 请求头 | API 请求与 v3 的 `playHeaders` 一致；媒体请求头与 `PlaybackHeaderResolver` 的 AcFun 分支一致 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 出错抛类型化错误；进房时直播刚结束（`startPlay` 129004）是 `StreamUnavailable` | 问题 4。界面看到的仍是 v3 的加载失败或无法播放 |
| 2 | `startPlay` 被拒时当次换会话重试一次 | 问题 1（REG-ACFUN-003）。只在被拒时多一次登录和请求 |
| 3 | 不再报“分页过期” | 问题 2（REG-ACFUN-004）。列表只在丢了游标时重读前面的页；搜索的另一页等正在加载的页完成 |
| 4 | 不合格的卡片、分区、画质跳过，不让整页失败 | 问题 3。样本里没有这类数据，现有内容不变 |
| 5 | 在播只看 `liveId` | 问题 5 |
| 6 | 未开播的房间取画质是 `StreamUnavailable`；没有播放数据的在播卡片先请求 `startPlay` | 问题 6、7 |
| 7 | 恢复取流只请求 `startPlay`；要求的画质不在新答复里时是 `StreamUnavailable`，不换别的画质（与 v3 一样） | 问题 8 |
| 8 | 详情带简介（主播签名，解码 HTML 实体） | 问题 9。3.x 的搜索卡片已经把同一段文字当简介显示 |
| 9 | 线路自带请求头、格式、线路编号和租期 | 见“做法”。请求头与 `PlaybackHeaderResolver` 逐项相同；v3 没有租期 |
| 10 | 认手机直播页 `m.acfun.cn/live/detail/{id}` | v3 不认，打开这种分享链接只会失败；不影响已有的链接 |
| 11 | `AcfunDanmakuArgs` | v3 没有 AcFun 弹幕；这些值来自进房本来就有的请求，是否接入由 T06a 决定 |
| 12 | 图片地址经通用的 `normalizeImageUrl` | 与其他平台一致；样本里的地址不变 |
| 13 | 长关键词照常搜索，页码小于 1 按 1 | 问题 12 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

1. **画质排序用 v3 的排序值**：有 `level` 的档是 `1000000 + level`，排在只有码率的档前面，只有码率的档按码率排（REG-ACFUN-005）。**归档 v4 写成 `level ?? bitrate`**，两种刻度混在一起比：一档没有 `level`、码率 8000 的流会排到 `level` 130 的原画前面。上游笔记指出的这个风险已核实，测试里固定了混合情况下的顺序。
2. **`acSecurity` 不是必需的**。**归档 v4 在登录答复缺它时报 `ApiChanged`**，取流也跟着失败；它只有弹幕的注册交换用得到（v3 的测试里访客答复就没有它）。这里缺失时会话照常，`AcfunVisitor.security` 为 null，由弹幕（T06a）处理。
3. **分区保留“全部”（filterId 0）**，与 v3 一样；归档 v4 去掉了。（T02.U 的 10-2 已去掉；存下的“全部”分区按推荐读。）
4. **分类只有一个**：id 是 `acfun`，名称和分区的 `typeName` 都是显示名“AcFun 直播”，关注的分区与 3.x 通用；归档 v4 的分类 id 是 `filterType`，名为“直播分类”。
5. **仍按页码翻页**，游标在适配器里，界面的分页方式不变；归档 v4 直接把游标交给界面。（T02.U 的 10-5 另提供按游标取页 `getDirectoryPageAtCursor`，界面在 M13 换用。）
6. **搜索按服务端 30 条一页切成应用的页**；归档 v4 一个服务端页就是一页。
7. **搜索卡片标题为空，简介放在简介里**；归档 v4 把简介当标题。
8. **保留关注数**：详情取 `user.fanCountValue`，搜索卡片取“N 粉丝”；归档 v4 两处都没填。
9. **一个画质的所有地址都保留**（只去掉完全相同的）；归档 v4 同一主机只留一条。
10. **个人主页 `www.acfun.cn/u/{id}` 不算房间**，与 v3 一样（v3 的测试特意排除它）；归档 v4 认它。（T02.U 的 10-1 已认，也认手机主页。）
11. **媒体请求头带 `Origin`**（v3 的 `PlaybackHeaderResolver`）；归档 v4 只有 UA 和 `Referer`。
12. **进房和录制都在读详情时请求 `startPlay`**，关注刷新不请求，与 v3 相同。
13. 显示名仍是“AcFun 直播”；归档 v4 是“AcFun”。上游 pure_live_TV 与 v3 相同，没有要采用的修复。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 认个人主页 `www.acfun.cn/u/{id}` 为房间 | 不认 | 归档 v4 认；作者 id 就是房间号 |
| 2 | 去掉“全部”分区 | 列出，内容与推荐相同 | 归档 v4 已去掉 |
| 3 | 显示开播时间（`createTime`） | 不显示 | 列表和详情都有这个字段 |
| 4 | 接入 AcFun 弹幕 | 没有弹幕 | 归档 v4 已实现（REG-ACFUN-001、007），样本 `danmaku/S07-live`；本模块已给出 `AcfunDanmakuArgs` |
| 5 | 列表改用游标分页（`LiveSiteCursorDirectoryPager`），刷新后不必重读前面的页 | 按页码 | 需要界面（M13）配合，会换用另一种列表控制器 |

## 回归条目的覆盖

- 平台层的条目都有测试直接覆盖：
  - 002：搜索的短页不提前结束、不漏人，页号 × 30 达到总数才结束（移植 v3 的“稀疏页”用例）；
  - 003：被拒的会话当次换新会话再请求一次，两次都被拒是 `RiskControl`，只重试一次；
  - 004：列表刷新后再翻页会重读前面的页；搜索的另一页等正在加载的页；序列被挤出后按位置重新开始；
  - 005：`level` 和码率两种刻度不混排（含没有 `level` 的高码率档）；
  - 006：搜索带浏览器 UA 和 `Referer`，403 是 `RiskControl`。
- 001（弹幕）、007（礼物表）属于弹幕协议，在 T06a 覆盖；本模块提供 `AcfunDanmakuArgs`，样本在 `fixtures/acfun/danmaku/S07-live`。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕协议（快手中台长连接、AES-128-CBC、protobuf 帧、礼物表 `gift/list`）和缺 `acSecurity` 时的处理 | T06a；本模块输出 `AcfunDanmakuArgs` |
| `getDanmaku()` | 同 T02a.1：T06a 用一张“平台 → 弹幕连接”的表 |
| 外部打开 `https://live.acfun.cn/live/{id}` | M13；地址由 `AcfunApi.roomPageUrl` 和房间的 `link` 提供 |
| 搜索页对 AcFun 的说明（“搜作者，含未开播”，3.x `search_coverage_acfun`） | M13 |
| 真实在线数设置里的 AcFun 开关（3.x 默认开启） | T09b.1、M13 |
| 热门、分区页的翻页和“没有更多” | M13 |
| 录制把 `StreamUnavailable` 当成未开播 | T08a.1 |

## 新增的通用能力

- `html.dart`：`HtmlElement.parseFragment`，一个不引入依赖的宽松 HTML 片段读取器（元素树、属性、类名、文本、按条件查找）。v3 的搜索用 `package:html` 的选择器解析，这里用它代替，不用正则，属性顺序变化也不受影响；脚本只当文本，不执行。
- `json.dart`：`decodeHtmlEntities` 认识 `&ensp;`、`&emsp;`、`&thinsp;`（搜索卡片的“2.4万&ensp;粉丝”）。
- `live_core.dart` 按字母顺序加了三行导出。

## 测试

79 个用例，`live_core` 共 774 个，全部通过：

- `acfun_api_test.dart`（39 个）：逐个样本对照 v3 的输出（分类、推荐、分区、搜索四页、详情、访客会话、`startPlay`、画质和地址），有意的差异逐条断言；移植 v3 的 `acfun_adapter_contract_test.dart` 和 `acfun_navigation_test.dart` 中解析的部分（排序、隐藏和非法地址、无名称的画质、身份校验、人数、游标、搜索卡片的三种状态、“无结果”与被拦截的答复）；`level` 与码率混排、缺 `acSecurity`、租期、线路请求头、HTTP 状态的错误映射。
- `acfun_site_test.dart`（37 个），用样本回放加脚本应答：
  - 分类、推荐、分区的请求和请求头与 v3 相同，最后一页之后不发请求，他站分区不发请求；
  - 游标链、并发共用、刷新后重读前面的页、重复游标；
  - 搜索：v3 的请求，20 条一页切 30 条的服务端页，短页，失败后重试不丢已读的行，同页共用、另一页等待，刷新取消旧请求，乱序按位置开始，超时取消，4 个空页的上限；
  - 详情：关注刷新只读 `live/info`、进房和录制的三个请求与 v3 相同、未开播、不存在、非法房间号、进房时刚关播；
  - 访客会话：并发共用一次登录、5 分钟后续期、被拒重试一次、关播保留会话、缺 `acSecurity` 照常播放、登录被拒不缓存；
  - 取流、列表卡片先请求 `startPlay`、恢复重新请求、恢复时画质不在了、弹幕参数的刷新；
  - 链接（移植 v3 的链接用例，另加手机页）和分享文本、传输错误和取消。
- `html_test.dart`（3 个）：通用 HTML 片段读取器。

## 升级落地（T02.U）

- 日期：2026-09-29
- 依据：[升级决定](../../../specs/UPGRADES.md) 的 10-1～10-5（“落地方式”只有 10-3、10-5 有内容，其余按上面“后续升级候选”的原文做）；另按“统一原则”逐项检查了开播时间、受限、占位信息、回放、房间身份、容错、翻页、画质。
- 只改了平台层（`acfun_api.dart` 解析，`acfun_site.dart` 请求编排）和两个测试文件。没有新增通用代码，没有新样本（原因见“受阻的条目”）；用到的只读探测（2026-09-29，直连，匿名）写在各条里，结果没有存成样本。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 10-1 | `roomIdFromUrl` 认个人主页：`www.acfun.cn/u/{id}`、`acfun.cn/u/{id}`（也认旧写法 `…/u/{id}.aspx`），以及手机主页 `m.acfun.cn/upPage/{id}`。作者 id 就是房间号，不发请求。探测：`acfun.cn/u/…` 和 `.aspx` 都 301 到 `www.acfun.cn/u/{id}`；手机浏览器打开 `www.acfun.cn/u/{id}` 会跳到 `m.acfun.cn/upPage/{id}`（页面标题是主播名）；`m.acfun.cn/u/{id}` 是手机站首页，不认 | 粘贴或分享 UP 主的主页链接能直接打开他的直播间（3.x 识别不了） | 完成（T02.U） |
| 10-2 | 取分类时去掉“全部”（filterId 0，`AcfunApi.allFilterId`），剩虚拟偶像、游戏、娱乐、其他 4 个分区。3.x 存下的“全部”分区照常能打开：`getCategoryRooms` 把它当推荐读（不带 `filters`，和同样页大小的推荐共用一条游标链）。探测：同一时刻“全部”和推荐的 23 个房间逐个相同、顺序相同；网页端在“全部”为空时也改读推荐 | 分类页少了“全部”一格（内容和推荐一样）；已关注的“全部”分区仍可用 | 完成（T02.U） |
| 10-3 | 直播中的列表卡片、进房、关注刷新、录制详情填 `startedAt`：`createTime`（毫秒）；进房时 `live/info` 没有它就取 `startPlay` 的 `liveStartTime`（样本和探测里两者相同）。未开播、搜索卡片没有，不填；0、负数、不像毫秒的值不填。没有多发请求 | 列表、房间页、关注能显示已开播多久（显示在 M13） | 平台层完成，余下 M13 |
| 10-4 | 弹幕协议属于 T06a，本次不做，只核对了参数：2026-09-29 匿名登录加 `startPlay` 实测，访客答复仍有 `acSecurity`，`startPlay` 仍给 `liveId`、4 张 `availableTickets`、`enterRoomAttach`。归档 v4 弹幕要的值（访客 id、设备号、令牌、`acSecurity`、`liveId`、票据、`enterRoomAttach`，握手的 UA 和 `Origin`）都在 `AcfunDanmakuArgs` 里；礼物表 `gift/list` 用和 `startPlay` 相同的查询参数，由 T06a 请求。付费直播没有票据：进房时不给弹幕参数，`danmakuArgs()` 报 `StreamUnavailable` | 无（弹幕在 T06a） | 平台层完成，余下 T06a |
| 10-5 | 适配器实现 `LiveSiteCursorDirectoryPager`：`getDirectoryPageAtCursor(page, cursor, category, cancel)` 一页一个请求（30 个房间），直接用平台的 `pcursor`，不经过适配器里页码到游标的表，刷新后不必重读前面的页；第 1 页带游标、后面的页不带游标是 `ArgumentError`（不发请求），游标指向自己是 `ApiChanged`，取消令牌交给传输层。`getDirectoryPage(page)` 走原来的游标链，另给出 `hasMore` 和下一页的游标，取消只结束自己的等待，不打断别人共用的请求。v3 的 `getRecommendRooms`、`getCategoryRooms` 不变 | 现在看不出变化；M13 换列表控件后，刷新后再往下翻不用重读前面的页 | 平台层完成，余下 M13 |

### 按统一原则补的

| 原则 | 做了什么 | 用户会看到什么 |
|---|---|---|
| 开播时间 | 见 10-3 | 见 10-3 |
| 受限类型 | 付费直播（门票）是 `paid`。依据是 2026-09-29 下载的 `live.acfun.cn` 播放页脚本：网页的 `liveInfo` 就是 `live/info` 的答复，买票用其中的 `paidShowUuid`，`paidShowUserBuyStatus` 是看的人买过没有；`startPlay` 答 380205 时网页显示“未购票”（`liveNotPaid`），129004 是关播，129015 是看的人被封禁（`userBanned`）。所以：直播中的列表卡片和详情（进房、关注刷新）有 `paidShowUuid` 且没买是 `paid`；有 `paidShowUserBuyStatus` 字段、没有 `paidShowUuid` 是 `none`；两个都没有留 null。进房时以 `startPlay` 为准：380205 是 `paid`（详情里没有 `paidShowUuid` 也一样），取到流就是 `none`。未开播、搜索卡片留 null。样本里所有卡片和详情都只有 `paidShowUserBuyStatus: false`，都是 `none` | 付费直播在列表和房间页显示为直播中，卡片标出付费（M13），播放时说明原因 |
| 受限的直播改为直播中 | 之前（3.x 和 T02b.3）`startPlay` 的 380205 被当成会话被拒：换新会话再请求一次，仍被拒就是 `RiskControl`，进房失败。现在 380205 不换会话，房间照常返回（直播中、`paid`、没有播放数据和弹幕参数）；取画质、取流、恢复、弹幕参数报 `StreamUnavailable`（`restricted room (paid)`）；已标 `paid` 的卡片直接报错，不发请求。129015 仍按会话被拒处理（匿名访客换一个会话就好） | 付费直播能进房间看到信息，不再是“加载失败” |
| 占位信息 | 已符合，没有改动：名字、标题、封面拿不到时本来就是空。没设封面的直播，平台给的封面是主播头像，是真实图片，保留 | 无 |
| 回放 | 不适用：AcFun 直播没有回放 | 无 |
| 房间身份 | 不变：作者 id 是数字，不加进 `SiteIds.caseInsensitiveRoomIds` | 无 |
| 按主播关注 | 本来就是：房间号就是作者 id，10-1 的主页链接也解析到同一个 id | 无 |
| 容错 | 已符合，没有改动（T02b.3 问题 3）：坏卡片、坏分区、坏画质只跳过这一个 | 无 |
| 翻页 | 列表跨页去重：同一条游标链从第 1 页往后翻时，前面各页（以及本页前面）列过的房间不再列出；重新读第 1 页（下拉刷新）时从头算；去重的记录和游标放在一起按页存，重读同一页结果不变，不增加请求。快照：列表和搜索都是平台分页，游标链和搜索序列从第 1 页一直用到下一次刷新，没有一次取全的列表可共用。搜索不去重：作者搜索按相关度排，服务端页是稳定的序列，样本和 3.x 的用例都没有跨页重复，去重还会让“页号 × 30 达到总数才结束”（REG-ACFUN-002）的计数变复杂。`getDirectoryPageAtCursor` 不存状态，也不去重，由 M13 的列表按 `identityKey` 去重 | 往下翻不会再看到重复的房间；极少数情况下一页全是重复的，会返回空列表 |
| 画质命名 | 不改：本平台没有改名条目，名字是平台自己给的（蓝光 8M、蓝光 4M、超清、高清）。`BLUE_RAY` 的地址是不带后缀的源流（`kszt_….flv`，其余档带 `_hd4000`、`_hd2000`、`_sd1000`），但平台叫它“蓝光 8M”，所以不改叫“原画” | 无 |
| 默认编码 | 不涉及：`startPlay` 只请求 FLV（`pullStreamType=FLV`），答复里没有编码字段 | 无 |

### 请求数

| 场景 | 之前 | 现在 |
|---|---|---|
| 取分类 | 1 | 1 |
| 推荐、分区每页 | 1 | 1 |
| 打开存下的“全部” | 1（带 `filters`） | 1（读推荐） |
| 按游标取页（10-5，新） | — | 1 |
| 关注刷新、开播状态 | 1 | 1 |
| 进房、录制：直播 | 3 | 3 |
| 进房、录制：付费直播 | 5（被拒后换会话重试），然后失败 | 3 |
| 已标付费的卡片取流 | — | 0 |
| 搜索 | 不变 | 不变 |

### 画质 id 对照、设置项、身份迁移（给 T09b.1、M13）

- **画质 id**：不变（`BLUE_RAY`、`SUPER`、`HIGH`、`STANDARD`，名称也不变），没有对照表。
- **设置项**：没有。
- **身份**：不变。10-1 的主页链接解析到作者 id，就是 3.x 存的房间号，不用迁移。
- **分区**：3.x 存下的“全部”（`areaType` 1、`areaId` 0）仍可用（读推荐），T09b.1 原样保留即可，不用迁移。

### 与 v3 冻结输出的新差异

样本对照测试里写明，原因写条目编号：

- 分类（S01-list-filters）：没有“全部”（10-2）；其余 4 个分区逐项一致。
- 推荐、分区（S01-list-all、S02-list-game）、直播详情（S05-info-live）：新键 `startedAt`（10-3）和 `restriction`（`none`，统一原则），3.x 读取时忽略（T02g.2 的 JSON 兼容规则）；其余键一致。测试断言新增的键只有这两个（详情另有 T02b.3 起就有的简介）。
- 未开播详情（S05-info-offline）：没有新键。
- `startPlay`（S06-startplay-live）：画质和地址不变，另读 `liveStartTime`。
- 链接：3.x 不认的 `www.acfun.cn/u/42` 现在是房间 42（10-1）。

### 留给其他模块

| 内容 | 去向 |
|---|---|
| 弹幕协议和礼物表，用 `AcfunDanmakuArgs`（10-4） | T06a |
| 列表控件改用 `getDirectoryPageAtCursor`，按 `identityKey` 跨页去重（10-5） | M13 |
| 开播时间只在直播中显示（10-3）；付费直播卡片的标记、播放时的提示、发现页默认隐藏不能播放的直播 | M13 |
| 录制遇到付费直播：详情是直播中，取流报 `StreamUnavailable` | T08a.1 |
| 存下的“全部”分区照常可用，不用迁移 | T09b.1（知悉） |

### 受阻的条目

没有。有一处缺样本：探测时没有付费直播在播（推荐 26 个、23 个房间，都只有 `paidShowUserBuyStatus: false`），`paidShowUuid` 和 380205 的判断来自网页脚本，测试用合成答复。以后遇到在播的付费直播时补录样本核对。

### 测试

本平台 94 个用例（新增 18 个，另改写了分类、REG-ACFUN-004、链接和取流的用例），`live_core` 共 2956 个，全部通过：

- `acfun_api_test.dart`（43 个）：
  - 样本对照：分类去掉“全部”（10-2），其余逐项一致；列表、详情的 `startedAt` 等于 `createTime`、`restriction` 是 `none`，新增的键只有这两个；未开播没有；
  - 付费直播：`paidShowUuid` 未买是 `paid`、已买是 `none`，没有字段是 null，未开播都不填，受限的直播仍在直播中分组；`startPlay` 380205 是 `paid`、没有播放数据和票据；
  - 开播时间的解析（毫秒、字符串、秒、坏值）；`startPlay` 的 `liveStartTime`。
- `acfun_site_test.dart`（51 个）：
  - 10-2：分类没有“全部”；存下的“全部”读推荐（不带 `filters`，与 3.x 的推荐请求相同），和推荐共用一条链；
  - 翻页：跨页去重、重读同一页结果不变、第 1 页重新开始、请求数不变；REG-ACFUN-004 的用例改为每页不同的房间；
  - 10-5：按游标取页的请求（游标、页大小、请求头、分区、“全部”、他站分区、取消令牌），页码和游标不匹配、游标指向自己；按页码取页的 `hasMore`、下一页游标、与推荐共用链，取消只结束自己的等待；
  - 10-3：关注刷新、进房的开播时间和受限类型，请求数与 3.x 相同；进房时用 `liveStartTime` 补；
  - 付费直播：进房是直播中、`paid`、没有播放数据和弹幕参数，不换会话；取画质、取流、恢复、弹幕参数报错；已标付费的卡片不发请求；关注刷新从 `live/info` 标出；详情没标时以 `startPlay` 为准，取到流就是 `none`；
  - 10-1：主页链接（带查询、`.aspx`、手机主页、大写主机）和不认的写法，分享文本不发请求。

## 后续（T06a 弹幕）

本平台的聊天（弹幕）已由 T06a.10 完成，见 [记录](../../../T06/T06a/T06a.10/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 T02 当时的情况，不再改动。
