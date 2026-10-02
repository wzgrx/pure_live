# E03.6 SHOWROOM

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/showroom/`（`showroom_api.dart` 纯解析，`showroom_site.dart` 请求编排）
- 样本：`fixtures/showroom`，10 个真实接口录制和 1 组评论帧，全部来自归档（2026-09-27 直连录制）：
  - 快照 `S01-onlives`（18 个类型，Popularity 64 个在播房间，含两个“没人在播”的消息格子）；
  - 房间键 `S02-status-key`、`S02-status-notfound`；资料 `S03-profile-live`/`-offline`/`-notfound`；状态 `S04-live-info-live`/`-offline`；取流 `S05-streaming-live`/`-offline`；
  - 评论帧 `danmaku/S06-live`（D01 用）。
- 参考：
  - 归档 v4 的 SHOWROOM 适配器和规格（`spec/sites/showroom.md`，回归条目 REG-SHOWROOM-001～003）；
  - pure_live_TV `lib/platforms/showroom/`：与 v3 相同，只改了导入路径和可空标注（`followers ?? ''` 等），没有行为修复（对照笔记 `sub_B.md` 的 showroom 一节）。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称和顺序、列表内容都按 v3；修好但会改变这些内容的地方，列入“后续升级候选”；关注刷新和列表的请求不比 v3 多。

## 做法

- **接口和输出沿用 v3**：`LiveSite`、`LiveRoom` 等模型和 3.x 的 JSON 不变。v3 实现过的可选能力全部保留：目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `showroom_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、恢复（`LivePlayRecoveryResolver`）。另加 `LivePlayUrlResolver`（线路要带请求头）和 `LiveSiteLinks`。
- **请求照 v3**：
  - 都带 v3 的 API 请求头（Chrome 140 UA、`Accept: application/json, text/plain, */*`、`Referer: https://www.showroom-live.com/`），**不跟随跳转**，以 `showroom` 的名义发出，代理由应用按平台注入；
  - 匿名：v3 的 SHOWROOM 没有 Cookie、没有登录，所以不注入 `CookieVault`；
  - 分类、目录、推荐、搜索都来自同一个 `api/live/onlives` 快照（一次给出全部在播房间），在本地分页；
  - 房间：`room/profile` 和 `live/live_info` 同时请求；用房间键时先请求 `room/status`；进房和录制时，在播的房间再请求 `live/streaming_url?abr_available=1`。
- **快照的复用照 v3**：不带取消令牌的调用（分类、推荐、分区房间、`searchRooms`）共用一份快照 30 秒；带令牌的调用（v3 的目录页和搜索页总是带）每次都重新请求，不碰共用的那份。v3 在第一份回答到达前，每个调用各发一次请求；现在共用进行中的那一次（只减少请求）。失败的请求不缓存。
- **目录、推荐、搜索照 v3**：
  - 一个分类 `SHOWROOM`（id `showroom`），每个类型一个分区（`areaType: genre`，id 为 `genre_id`，名称为英文的 `genre_name`），没人在播的类型也列出；
  - 原生目录每页 30 个，推荐是 Popularity（`genre_id` 0），快照里没有这一组时取所有房间各一次；
  - `getRecommendRooms`、`getCategoryRooms`、搜索按 v3 的 `_page` 切片：页码或条数小于 1、条数超过 100 都给空；
  - 搜索没有平台接口，在快照里按房间号、房间键（相等，忽略大小写）和名字、字幕（telop）、房间自己的类型名（包含，忽略大小写）过滤；链接在这里也只是关键词（v3 的链接由应用层的链接解析处理，M13）。
- **卡片照 v3**：标题是 telop，没有时是名字；封面和头像都用 `image_square`（没有时用 `image`），只收 `showroom-live.com`、`showroom-txlive.com` 及其子域的 https 地址；`view_num` 作为累计观看（REG-SHOWROOM-002）；`link` 是 `https://www.showroom-live.com/r/<房间键>`；房间带 v3 的媒体请求头（`httpHeaders`，3.x 的 JSON 里有）。
- **房间照 v3**：
  - **房间号是数字的 `room_id`**：v3 的详情总是返回资料里的 `room_id`，用房间键打开的房间也一样（样本对照：用 `0c1c310117354` 请求，`roomId` 是 `577362`）。3.x 存下的关注都是数字号；
  - 标题和主播名都是 `main_name`（没有时 `room_name`），分区是资料里的 `genre_name`（`music`），简介是 `description`，`view_num` 即使未开播也照写（v3）；
  - 是否在播只看 `live_info.live_status`：2 在播，0、1 未开播，其他值和答非所问（`room_id` 不符）是 `ApiChanged`；
  - 进房和录制的在播房间带 `ShowroomRoomData`：原样的 `streaming_url_list`（取流时才检查）、评论服务器 `bcsvr_host` 和本场的 `bcsvr_key`（v3 没有评论，留给 D01）；刷新不带（v3 同样）。
- **画质和线路照 v3**：
  - `hls_all`（自适应主列表）是“自动”，排序 2000，排第一；`hls` 按 `quality`：1000 以上“原画”、200 以上“中画质”、其余“低画质”；id 是 `类型:id:quality`（如 `hls:2:1000`），同 v3；WebRTC 和其他类型跳过；
  - 每档一条 HLS 线路，带 v3 `PlaybackHeaderResolver` 里 SHOWROOM 的媒体请求头（UA、`Referer`），线路编号是节点主机名；地址没有签名和有效期，所以没有 `PlayLease`；确认的画质就是请求的画质（v3 同样）；
  - 行的检查照 v3：地址必须是 SHOWROOM 主机上的 https、没有空白和控制字符、用户名和片段，`id`、`label`、`quality`、`is_default` 要齐，最多 64 行；一行不对整档 `ApiChanged`。
- **链接照 v3 的 `ShowroomLink`**：`showroom-live.com` 或其子域、http(s)、没有用户名；`room/profile?room_id=<号>` 得到房间号，`/r/<键>` 和 `/<键>` 得到房间键，由进房时经 `room/status` 换成房间号（REG-SHOWROOM-003）。只由数字组成的房间键例外，见问题 1。
- **没有弹幕参数、没有账号**：v3 的 SHOWROOM 是 `EmptyDanmaku`，传给弹幕连接的参数为空，所以没有弹幕参数类；评论服务器记在 `ShowroomRoomData` 里（升级候选 3）。

## 审查发现的 v3 问题

位置简写：`A` = `legacy/lib/core/site/showroom/showroom_api.dart`，`S` = 同目录的 `showroom_site.dart`，`L` = `showroom_link.dart`，`phr` = `legacy/lib/player/core/playback_header_resolver.dart`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 房间键只由数字组成时，房间链接打不开（或打开别的房间）。样本 S01 的 64 个热门房间里有 3 个这样的键：386593 的 `7779344804`、158506 的 `49873983449`、567520 的 `106289890154` | L:31-32；A:268-269 | 链接解析把 `/r/<键>` 原样当作房间标识返回；进房时 `int.tryParse` 成功就当作房间号，去请求 `room/profile?room_id=7779344804` | 纯数字的键不直接返回，改为 `needsResolving`：解析链接时请求一次 `room/status`，得到数字房间号。其余的键仍然不发请求、由进房时查（v3） |
| 2 | 在播房间取不到 HLS 线路时（付费直播、只有 WebRTC、`streaming_url` 一时失败），整个房间页打不开，录制详情也失败 | A:333-341（`room`）、A:337-339；A:308-331 | 进房时就取流并检查，列表为空抛 `mediaUnavailable`，任一行不对抛 `schema` | 房间照常打开（在播），行原样记下；取流时再检查：没有线路是 `StreamUnavailable`，行不对是 `ApiChanged`；进房时的取流请求失败，取画质时再请求一次 |
| 3 | 快照里任一房间的 `streaming_url_list` 缺失或有一条不合规的地址，分类、目录、推荐、搜索全部失败 | A:343-363（`_live`）；S:172-190 | 解析快照时严格检查每行的线路，但卡片从来不用它们（房间的线路另从 `streaming_url` 取） | 不读快照里的线路；卡片自己的字段仍照 v3 严格检查（v3 的测试固定了“缺名字的行整个快照失败”） |
| 4 | 目录翻页和搜索每一页都重新下载约 170 KB 的快照，第 2、3 页和第 1 页来自不同的快照（房间会重复或漏掉） | S:48-49；`common/base/live_directory_controller.dart:183`、`modules/search/search_controller.dart:380` | 带取消令牌的调用绕过 30 秒缓存，而目录页和搜索页总是带令牌 | 保持 v3（请求数和列表内容都不变），列为升级候选 1 |
| 5 | 并发的调用各自请求快照 | S:50-53、S:59 | 缓存只在回答到达后才生效（`_catalogAt` 在完成时才写） | 共用进行中的请求（只减少请求，内容相同） |
| 6 | 未开播的房间取画质得到空列表，播放器拿不到原因 | S:259 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 7 | 没有详情数据的房间（列表卡片、刷新得到的房间）取画质报 `mediaUnavailable`，不能直接播放 | S:260-263 | 只从进房时的 `data` 读画质 | 请求一次 `streaming_url` |
| 8 | 恢复时重新读整个房间：`profile`、`live_info`、`streaming_url` 三个请求 | S:275-285 | 用 `getRoomDetail` 取新地址 | 只请求 `streaming_url`；画质 id 不在新回答里（或已下播）仍然报错，不悄悄换档（同 v3） |
| 9 | 查开播状态读的是刷新详情（`profile` 和 `live_info` 两个请求），资料接口失败也会让状态查询失败 | S:252-254 | 复用刷新详情 | 只请求 `live_info`（开播状态只看它） |
| 10 | 调用方传错页码或分区，报的是 `schema`、`identity`，而且是在请求快照之后；无效的切片也先请求再返回空 | S:98-100、S:108-118、S:153-158、S:165-170 | 参数检查放在请求之后，错误种类不分 | 页码和分区错误是 `ArgumentError`（`RangeError`），不发请求；无效切片直接返回空（v3 的结果），不发请求 |
| 11 | 各种失败都是平台自己的 `ShowroomException`，3xx、400 等都算“传输错误” | A:9-29、A:225-233 | 平台自定义异常 | 类型化错误：401/403 `RiskControl`，404 `NotFound`，429 `RateLimited`，5xx 和其他状态（含跳转）`NetworkFailure`，结构、身份不符 `ApiChanged`，不能播放 `StreamUnavailable`；取消原样抛出 |
| 12 | `/onlive`（直播一览页）、`/r` 等站点页面被当成房间键，打开后报“不存在” | L:4-14、L:31-32 | 保留路径不全 | 采用归档 v4 补的保留路径（`r`、`onlive`、`campaign`、`about`、`lottery`），这些链接不再识别 |
| 13 | 平台层依赖全局 `HttpClient`，自己实现流式读取（3 MiB、20 秒）；媒体请求头按平台写在播放层 | A:150-210；phr:171-172 | 结构问题 | 注入 `LiveHttp`（20 秒由 live_net 负责）；线路自带请求头 |
| 14 | 平台层调用界面翻译（画质名称） | S:220-226 | `i18n` 写在适配器里 | 用 3.x `zh.json` 的中文（自动、原画、中画质、低画质），界面的翻译在 M13 |

## 样本与 v3 的冻结输出

归档没有 SHOWROOM 的 `expected.json`（旧版对照工具只做了前五个平台，v3 应用也已经构建不了，规格 §11 也写明没有）。本模块用 `fixtures/showroom/legacy_expected.dart` 生成，做法同映客、小红书：

- 把 v3 的 `ShowroomApi`、`ShowroomSite`、`ShowroomLink` 原样搬进一个 Dart 脚本。v3 本来就把传输做成可注入的函数（`ShowroomRequest`），所以只换了它：按主机、路径和查询读样本，状态码不是 200 时正文为空（同 v3），没有样本的请求记在 `unmatched` 里；
- 唯一没有录到的回答是 `live/live_info?room_id=1`（v3 和 `S03-profile-notfound` 同时请求它），脚本按规格 §1（未知房间的 `room/profile`、`room/status`、`live/live_info` 都是 404）回答 404，并在输出里注明；
- `i18n` 换成用到的四个键的中文；Dio 的取消令牌、v3 的 `LiveRoom`、`LiveArea`、`LiveCategory`、`LivePlayQuality`、`LiveDirectoryPage`、`LivePlayUrlResolution` 只搬用到的部分（包括 `toJson` 里 v3 的 `HttpHeaderPolicy.normalize`）；只在网络路径上的 `_defaultRequest`、`readBody` 没有搬；
- 输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记请求。运行：`dart run fixtures/showroom/legacy_expected.dart`。

6 个样本有 `expected.json`：

| 样本 | 内容 |
|---|---|
| `S01-onlives` | 分类（第 1、2 页）；原生目录（推荐第 1～4 页、18 个类型各两页、不存在的类型、别的平台、第 0 页）；推荐的 8 种切片；分区的 4 种切片；8 个关键词和翻页、空白、链接的搜索；30 秒缓存 |
| `S03-profile-live` | 与 `S02-status-key`、`S04-live-info-live`、`S05-streaming-live` 一起，按房间号和房间键：进房、刷新、录制详情、开播状态、画质、每档地址、恢复 |
| `S03-profile-offline` | 与 `S04-live-info-offline` 一起：同上 |
| `S03-profile-notfound`、`S02-status-notfound` | 各入口的错误 |
| `S02-status-key` | 房间键查询；20 个链接的 `ShowroomLink.parse`；外部打开的地址 `ShowroomLink.roomUrl` |

`S04-*`、`S05-*` 没有单独的 `expected.json`，随 `S03-*` 一起回放。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序和地址；另比较请求。

| 样本 | 结果 |
|---|---|
| S01 分类 | 一致：1 个分类 `SHOWROOM`，18 个分区（Popularity、Newcomer、Music…New30day），顺序、id、名称一致。v3 的 `areaPic`、`shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S01 目录、推荐、分区 | 推荐 4 页（30、30、4、0）和 18 个类型各两页的房间、顺序、每个字段（包括标题的 telop、封面、累计观看、关注数、媒体请求头）、页码和“还有下一页”都一致；8 种推荐切片、分区切片一致；请求一致，只有 v3 先请求再给空的无效切片现在不发请求 |
| S01 搜索 | 8 个关键词（房间号、大写的房间键、纯数字房间键、名字、字幕、类型名、`room` 翻两页、无结果）的房间和请求都一致；链接当关键词，1 个请求、没有结果，一致 |
| S02/S03/S04/S05 在播 | 按房间号和房间键，进房、刷新、录制的房间全部一致，房间号都是 `577362`；请求一致（按号 3、2、3 个，按键 4、3、4 个）；4 档画质的名称、id、排序和地址一致；恢复的地址和确认的画质一致（现在 1 个请求，v3 是 3 个）；开播状态一致（现在 1 个请求，v3 是 2 个） |
| S03/S04 未开播 | 房间和请求一致；v3 取画质是空列表、恢复是 `mediaUnavailable`，现在都是 `StreamUnavailable`（问题 6、8） |
| S03-profile-notfound、S02-status-notfound | v3 的 `missing`，现在是 `NotFound`；请求一致（号 2 个，键 1 个） |
| S02 链接 | 20 个链接里 18 个一致；`/onlive`、`/r` 现在不识别（问题 12） |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 纯数字的房间键在解析链接时查 `room/status`，得到数字房间号 | 问题 1。v3 在这里打开的是错误的房间号；其他链接不变 |
| 2 | 在播但取不到线路的房间照常打开，取流时报错 | 问题 2。房间资料和状态与 v3 相同，只是失败的位置从“进房”移到“播放” |
| 3 | 快照不读每行自己的线路 | 问题 3。只在 v3 整个失败时有区别 |
| 4 | 共用进行中的快照请求 | 问题 5。只减少请求 |
| 5 | 未开播取画质报 `StreamUnavailable`；没有数据的房间取画质先请求 `streaming_url` | 问题 6、7 |
| 6 | 恢复只请求 `streaming_url`（1 个请求，v3 是 3 个）；开播状态只请求 `live_info`（1 个，v3 是 2 个） | 问题 8、9。结果相同 |
| 7 | 调用方错误是 `ArgumentError`，其他错误是类型化的 `SiteError`；无效切片不发请求 | 问题 10、11 |
| 8 | `/onlive`、`/r`、`/campaign`、`/about`、`/lottery` 不再当作房间键 | 问题 12 |
| 9 | 线路带媒体请求头，值与 v3 的 `PlaybackHeaderResolver` 相同 | 问题 13 |
| 10 | 不再有 3 MiB 的响应上限和严格的 UTF-8 校验 | 这是 v3 这个适配器自己的传输层（问题 13）；v4 的传输由 live_net 统一负责，20 秒总时限相同，非法 UTF-8 按替换字符处理。快照现在约 170 KB（同 TwitCasting 的处理） |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **画质名称和 id 照 v3**：“自动”“原画”“中画质”“低画质”，id `hls_all:100:0`、`hls:2:1000`。归档 v4 叫“原画、中、低、自动”，id 是 `1000`、`auto`，会改变画质菜单和已存的画质 id。
- **“自动”排第一**（v3 和上游 TV 都是）。归档 v4 把原画排第一、“自动”排最后，默认原画；列为升级候选 2。
- **快照缓存 30 秒**（v3、上游 TV）。归档 v4 每次都重新请求。
- **目录每页 30 个，推荐和分区按 v3 切片**。归档 v4 一次给出一整组。
- **搜索只在快照里过滤**，链接不特殊处理。归档 v4 遇到链接会去查房间（未开播也返回）；v3 由应用层的链接解析做这件事（M13）。
- **快照严格检查卡片字段**：缺名字、房间键不合规等整个快照 `ApiChanged`（v3 的测试固定了这一点）。归档 v4 跳过坏行。
- **图片只收 SHOWROOM 主机的 https 地址**，主机按“等于根域名或以 `.根域名` 结尾”判断（v3、上游 TV）。归档 v4 用不带点的 `endsWith`，`evilshowroom-live.com` 也能通过（对照笔记 `sub_B.md` 建议 7）。
- **进房后的标题是 `main_name`**，列表里的标题是 telop 优先（v3）。归档 v4 的详情标题用 `live_info.room_name`（样本里两者相同）。
- **`view_num` 在未开播时也显示**（v3，未开播的样本是 0）。归档 v4 只在直播时给累计观看；列为升级候选 4。
- **房间带媒体请求头 `httpHeaders`**（3.x 的 JSON 里有）。归档 v4 没有。
- **分类 id 是 `showroom`**，分区 `areaType` 是 `genre`（v3，3.x 存下的关注分区要对得上）。归档 v4 的分类 id 是 `genre`。
- **没有开播时间**：归档 v4 用 `started_at` 算开播时间，3.x 的 `LiveRoom` 没有这个字段。
- **没有评论**：归档 v4 做了评论 WebSocket，v3 没有，列为升级候选 3。
- **进房和录制都在进房时取线路**（v3 的三个请求），刷新只要资料和状态（两个请求）。
- 显示名 “SHOWROOM”（v3）；上游改成了多语言文字。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 目录翻页和搜索翻页共用同一份快照（例如 30 秒内），下拉刷新时再取新的 | 每一页都重新下载约 170 KB，各页来自不同的快照，房间可能重复或漏掉 | 问题 4；对照笔记 `sub_B.md` 建议 8 |
| 2 | 默认画质改为原画，“自动”排最后 | “自动”排第一，默认选它 | 归档 v4 |
| 3 | 评论（弹幕）：连 `wss://<bcsvr_host>/`，发 `SUB\t<bcsvr_key>`，每 60 秒 `PING\tshowroom` | 没有评论 | 归档规格 §7；`bcsvr_host`、`bcsvr_key` 已在 `ShowroomRoomData` 里，评论帧样本 `danmaku/S06-live` 已复制（D01） |
| 4 | 未开播的房间不显示 `view_num` | 显示“0 人看过” | 归档 v4；`view_num` 是本场的访问人次 |
| 5 | 付费直播（`premium_room_type` 不为 0）在房间页上标明 | 能进房，播放时报“暂时无法播放” | 归档规格 §12 待确认 1，需要付费房间的样本 |

## 回归条目的覆盖

REG-SHOWROOM-001～003 都属于平台层，都有测试：

- 001（没人在播的类型给消息格子）：跳过没有 `room_id` 的格子，其他坏行仍然整个失败；样本 S01 的 Newcomer、Announcer 是空分区。
- 002（`view_num` 被当成在线人数）：卡片和房间的 `view_num` 都是累计观看，在线人数、热度为空。
- 003（分享的是房间键）：房间键经 `room/status` 换成数字房间号（进房、刷新、开播状态）；纯数字的键在解析链接时就查（问题 1）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 目录说明（`showroom_directory_scope`）、画质名称（`showroom_quality_*`）、平台名（`site_showroom`）的繁体和英文 | M13 多语言。本模块给出 3.x 的中文画质名称 |
| 目录页每页 30 个、带取消令牌翻页，以及目录说明的显示（3.x `LiveDirectoryController`） | M13 热门页、分区页 |
| 搜索能力表：只有直播、可翻页、没有网页搜索（3.x `search_capability.dart:39-43`、`search_controller.dart:107-108`）；搜索框里的链接交给链接解析 | M13 搜索页 |
| 外部打开 `https://www.showroom-live.com/room/profile?room_id=<号>`（3.x `room_external_opener.dart:79-84`） | M13；地址由 `ShowroomApi.roomUrl` 提供 |
| 本地互动包（3.x `local_interaction_controller.dart:394-395`） | M13 |
| 平台列表升级时追加 SHOWROOM（`favorite_room_controller.dart:71`，第 15 版） | J02.1 |
| 人数口径（`view_num` 算累计、不支持在线人数，3.x `live_room.dart:109-115`） | 已在 E05.1 的 `audience.dart` |
| 评论（v3 没有）；`getDanmaku()` | D01（升级候选 3）；同 E01.1，D01 用一张“平台 → 弹幕连接”的表 |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出。链接的查询用 M3 的 `ShortLinkSession`，不需要改动。

## 测试

55 个用例，`live_core` 共 1455 个，全部通过：

- `showroom_api_test.dart`（28 个）：逐个样本对照 v3 的输出（分类、全部目录页、推荐和分区切片、搜索、在播和未开播房间的三种深度、画质、每档地址和恢复、房间键、链接、外部地址），有意的差异逐条断言；移植 v3 `showroom_catalog_test.dart`（消息格子跳过、坏行整个失败）；卡片字段、累计观看、Popularity 的兜底、重复的类型、图片主机；资料和状态的检查、`live_status` 取值、答非所问；状态码映射；画质的阈值、排序和逐行检查；线路的请求头、格式、线路编号、没有租期。
- `showroom_site_test.dart`（27 个），用样本回放加少量合成回答：
  - 请求头、不跟随跳转、平台名、目录说明、没有弹幕；传输错误和状态码的映射；
  - 快照：30 秒共用、带令牌的调用每次重新请求且不碰共用的那份、并发共用和失败不缓存；
  - 分类、目录页、切片和请求与 v3 一致；调用方错误和无效切片不发请求；不存在的类型；
  - 搜索与 v3 一致；取消传到请求、取消后不发请求、回答晚于取消被丢弃；
  - 房间：按号和按键的三种深度与 v3 一致、房间号是数字号、未开播、开播状态只请求一次、不存在、非法标识不发请求、取流失败或为空时照常进房、线路坏在取流时报错、答非所问、关注合并；
  - 取流：用进房时的行不再请求、卡片和刷新得到的房间先请求、别的房间的数据不用、没有的画质、别的平台、恢复只请求一次并与 v3 一致、恢复时已下播；
  - 链接（经 `LinkParser`）：房间键和房间号不发请求、站点页面不识别、纯数字房间键经 `room/status` 解析、未知的键没有结果。

## 升级落地（T02.U）

- 日期：2026-09-29（E03.6）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 5 行（19-1～19-5）；“落地方式”只有 19-1 写了，其余按上面“后续升级候选”的原文做。模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。19-3（评论）的连接属于 D01，这里只在平台层给出它要的参数。
- 只改了本平台：`showroom_api.dart`（解析）、`showroom_site.dart`（请求编排）和两份测试。没有改 `live_core` 的通用文件，没有新依赖，没有新样本（见“新样本”）。
- 实测：2026-09-28 18:40～19:00 UTC 直连、匿名，用适配器的请求头：
  - `live/onlives` 共 109 个在播房间行（去重后 49 个房间），`premium_room_type` 全是 0，每行都有 `started_at`；其中 4 行（2 个房间）`live_type` 是 4（`is_radio_now`，只有声音的直播），也有 HLS 地址，照常处理；
  - 用新适配器实际走了一遍：推荐第 1 页 30 个、第 2 页 11 个，一共 41 个没有重复，第 2 页和随后的取分类都没有再请求；卡片和进房都有开播时间、`none`；进房带弹幕参数（`online.showroom-live.com`）；画质顺序是原画、中画质、低画质、自动；未开播的房间（61576）刷新后没有人数、开播时间和受限类型。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 19-1 | 快照的复用改为：目录（`getDirectoryPage`）和可取消搜索（`searchRoomsCancellable`）的**第 1 页**（下拉刷新）总是重新请求 `live/onlives`，成功后作为共用快照；**第 2 页起**以及取分类、推荐和分区切片、不带令牌的 `searchRooms`，都用 30 秒内（`ShowroomSite.snapshotLifetime`）的这份快照，不管它是谁取的。带令牌的调用只复用已经到达的快照，否则用自己的令牌单独请求（取消它不会让别的调用失败）；不带令牌的调用照旧共用进行中的请求。失败或取消的请求不留快照，之前的快照照常可用。超过 30 秒再翻页会重新请求（再次成为共用快照） | 热门页、分区页、搜索结果往下翻时不再等待网络，每页来自同一份在播列表，不会重复或漏掉房间（v3 每页各下载约 170 KB 的新快照）；下拉刷新仍取最新的 | 平台层完成，余下 M13 |
| 19-2 | 画质列表改为 `hls` 各档按 `quality` 从高到低（原画、中画质、低画质），自适应主列表“自动”排最后：`sort` 从 2000 改为 `ShowroomApi.autoSort`（-1），比任何一档都低。名称和 id 都不变（`hls:2:1000`、`hls_all:100:0`），所以存下的画质偏好不用迁移 | 画质菜单的顺序变成原画、中画质、低画质、自动，默认播原画（v3 自动排第一） | 完成（T02.U） |
| 19-3 | 平台层：新类 `ShowroomDanmakuArgs`（`roomId`、`host`、`key`，即 `live_info` 的 `bcsvr_host`、`bcsvr_key`）。在播房间的进房和录制详情放在 `danmakuData`，不多发请求；刷新、未开播没有。只认 `showroom-live.com` 及其子域的主机名（不带端口、路径），键不超过 256 字、不含空白和控制字符（帧用制表符分隔），不合格就不给，房间照常打开。原来记在 `ShowroomRoomData` 的 `bcsvrHost`、`bcsvrKey` 移到这个类里。`getDanmaku()` 仍是 `EmptyDanmaku`，连接由 D01 的“平台 → 弹幕连接”表接上 | 平台层看不出变化；评论在 D01 接入 | 平台层完成，余下 D01 |
| 19-4 | 详情（进房、刷新、录制）在 `live_info` 说未开播时，`watching`、`totalViewers` 留空（v3 写 `view_num`，未开播时是 0）；关注数不变，人数口径仍是 `totalViewers`。列表卡片只有在播的房间，照旧有人数 | 未开播的房间不再显示“0 人看过”。关注列表里，刚下播的房间合并时会保留上次的人数（E05.2 的合并规则：空值不覆盖），要由界面在未开播时不显示人数（见“留给其他模块”） | 平台层完成，余下 M13 |
| 19-5 | 没有做：找不到付费直播的样本，不知道付费直播时 `premium_room_type` 写什么、取流接口回答什么（见“受阻和未核实”）。`premium_room_type` 不是 0 时受限类型留空（不知道），不标“付费” | 无变化 | 受阻：没有付费直播的样本 |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 两处都能取到，不多发请求：<br>- 卡片（目录、推荐、分区、搜索）：快照每行的 `started_at`（Unix 秒）；<br>- 详情（进房、刷新、录制）：`room/profile` 的 `current_live_started_at`，只在 `live_info` 说在播时填。未开播时这个字段不是本场的：S03-profile-offline 是 0，实测有付费直播预告的房间写的是预告的开播时间（如 358854 是 2026-09-30 10:50 UTC）。<br>0、2000 年以前、2100 年以后、不是整数的都不填（`ShowroomApi.startTime`）。S01 的 577362 两处都是 1790516942（2026-09-27 13:49:02 UTC）。`getLiveStatus` 只返回是否在播 |
| 受限类型 | 快照的行和 `live_info` 都有 `premium_room_type`：0（普通直播，任何人可看）填 `none`；其他值留空（`ShowroomApi.restrictionOf`），见 19-5。未开播不填；刷新也读 `live_info`，所以同样填。`live_info` 里的 `age_verification_status`、`is_under_18`、`is_under_16` 在所有样本和实测里都是 0，看不出是房间的限制还是访客的状态，不用 |
| 受限的直播改为直播中 | 不需要改：本平台从来没有用 `banned`、`unknown` 表示受限，是否在播只看 `live_status`。`premium_room_type` 不是 0 的在播房间仍是直播中（受限类型留空）；取不到 HLS 时在取流时报 `StreamUnavailable`（E03.6 问题 2 已是这样） |
| 占位信息 | 没有：名字是必填的 `main_name`（没有就跳过这一行或报错），标题是 telop 或名字（v3），封面是平台的房间图。两份快照里没有默认图（`radio_image_url` 的 `default.png` 是只有声音的直播的背景，不读） |
| 回放、轮播、“不可播放” | 不适用：SHOWROOM 的接口只有在播和未开播 |
| 画质命名 | 表里没有本平台的改名、合并条目，保留 v3 的“自动”“原画”“中画质”“低画质”和 id；只改了顺序（19-2） |
| 默认编码 | 不涉及：只有 H.264 的 HLS（归档规格 §6.4） |
| 房间身份 | 不变：数字 `room_id`，不分大小写的问题不存在（E05.2） |
| 按主播关注 | 本来就是：房间就是主播的房间，没有单场的身份 |
| 容错 | 快照：一行读不出来（不是对象，缺名字，房间号、房间键、人数不对……）只跳过这一行；类型的 `genre_id`、`genre_name` 不对或 `lives` 不是列表（或超过 5000 行）只跳过这个类型（v3 和 E03.6 都是整个快照 `ApiChanged`，v3 的测试固定了这一点）。有在播的行但一行都读不出来、或一个类型都没有时仍报 `ApiChanged`，接口改版不会显示成空目录；只有“没人在播”的消息格子是正常的空。<br>画质：一行 HLS 不对（地址不是 SHOWROOM 主机的 https、缺 `label`、`id`、`quality`、`is_default`，不是对象）只少这一档；HLS 行都读不出来是 `ApiChanged`，没有 HLS 行是 `StreamUnavailable`（v3 是任何一行不对整个 `ApiChanged`）。坏行不会挡住后面同地址的好行 |
| 翻页 | 见 19-1 |
| 弹幕 | 见 19-3 |
| 说明文字 | 平台层不改文字键 `showroom_directory_scope`；19-1 之后 v3 这句“目录和关键词搜索在同一快照内本地分页”终于属实，但整句仍是开发说明式的，建议的新文字见“留给其他模块” |

### 请求数

| 场景 | E03.6 | 现在 | 原因 |
|---|---|---|---|
| 目录、搜索第 1 页（带令牌） | 1 | 1 | — |
| 目录、搜索第 2 页起（带令牌） | 每页 1 | 30 秒内 0；超过 30 秒 1 | 19-1 |
| 取分类、推荐和分区切片、`searchRooms`（不带令牌） | 30 秒内共用 1 个 | 不变，也能用目录、搜索取到的快照 | 19-1 |
| 不带令牌的 `getDirectoryPage` 第 1 页 | 30 秒内共用 | 1（刷新） | 19-1：第 1 页就是下拉刷新；v3 的目录页总是带令牌，所以实际请求不变 |
| 进房、录制 | 在播 3 个、未开播 2 个（房间键再加 1） | 不变 | 弹幕参数来自已有的 `live_info` |
| 关注刷新 | 2 个 | 不变 | — |
| 开播状态、取流、恢复 | 1 / 0～1 / 1 | 不变 | — |

### 画质 id 对照（给 J02.1）

没有变化，不需要旧 id → 新 id 的对照：id 仍是 `类型:编号:quality`（样本里 `hls:2:1000`、`hls:6:200`、`hls:4:100`、`hls_all:100:0`），名称仍是“原画”“中画质”“低画质”“自动”。v3 的画质偏好按名字存，名字没变。

### 设置项

无。

### 房间身份迁移规则（给 J02.1）

无。房间身份仍是数字 `room_id`；房间键（`room_url_key`）和以前一样只是链接里的写法，进房时经 `room/status` 换成房间号。

### 与 v3 冻结输出的新差异

`expected.json` 没有改。样本对照测试里用 `changed:` 列出（注释写条目编号），E05.2 的新键用 `added:` 单独断言：

- S01 的全部目录页、推荐和分区切片、搜索：房间和每个键与 v3 一致；新键是每行的 `started_at` 和 `none`（统一原则）。
- S03-profile-live + S04-live-info-live 的进房、刷新、录制：与 v3 一致；新键是开播时间（`current_live_started_at`）和 `none`；进房和录制另有 `danmakuData`（不在 JSON 里，19-3）。
- S03-profile-offline + S04-live-info-offline：`watching`、`totalViewers` 从 `'0'` 变为空（19-4）；没有新键。
- S05 的画质：名称、id、地址与 v3 一致；顺序和“自动”的 `sort`（2000 → -1）变了（19-2）。恢复的地址和确认的画质与 v3 一致。
- 快照缓存的请求（`cache`）：与 v3 一样是 2 个。
- 坏行、坏类型、坏画质行只跳过自己（容错），只有合成用例；v3 在这些情况下整个失败。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 | SHOWROOM 评论：进房和录制详情的 `danmakuData` 是 `ShowroomDanmakuArgs(roomId, host, key)`。按归档规格 §7：连 `wss://<host>/`（443 端口；`bcsvr_port` 8080 是旧的明文端口），握手带 `Origin: https://www.showroom-live.com` 和 UA；连上后发文本帧 `SUB\t<key>`，每 60 秒发 `PING\tshowroom`（回 `ACK\tshowroom`）；消息是 `MSG\t<key>\t<JSON>`，键不是本场的丢弃，`t` 1 评论、2 礼物、8 字幕更新、18 系统通知。评论帧样本 `danmaku/S06-live`（E03.6 已复制）。键每场不同，主播重新开播后要重新取详情 |
| G | 默认画质：列表第一档就是原画。v3 按名字匹配画质偏好，匹配不到时按偏好在“原画、蓝光8M、蓝光4M、超清、流畅”里的位置按比例选下标；“自动”排最后以后，偏好“流畅”会按比例选到“自动”。按比例选时应跳过“自动”（`sort` 是 `ShowroomApi.autoSort`、id 以 `hls_all:` 开头） |
| J02.1 | 按 E05.2 存 `startedAt`、`restriction`。没有设置、画质 id 或身份要迁移 |
| M13 | 目录页、搜索页下拉刷新时重新取第 1 页（v3 已是这样），之后的页 30 秒内来自同一份快照；目录说明 `showroom_directory_scope` 改写，建议：“这里是 SHOWROOM 此刻所有正在直播的房间，按类型分组；搜索只在这些正在直播的房间里按房间号、房间名、字幕和类型查找。粘贴直播间链接可以打开没有在直播的房间。人数是本场累计观看，不是实时在线人数。”英文：“All SHOWROOM rooms live right now, grouped by genre. Search looks only through these live rooms, by room number, name, caption or genre. Paste a room link to open a room that is not live. The count is this broadcast's total views, not viewers right now.”<br>未开播的房间不显示人数：关注列表合并刷新结果时会保留上次在播时的人数（E05.2 的空值不覆盖规则），卡片要按 `isLiveNow` 决定是否显示人数（19-4；这条对所有平台都适用）。开播时间只在直播中显示。19-5 解除受阻后，卡片按 `restriction` 标“付费” |
| H01.1 | 录制详情也带弹幕参数；录制评论与否由 H01.1 决定 |

### 受阻和未核实

- **19-5 付费直播（受阻）**：
  - 付费直播的列表接口是 `GET https://www.showroom-live.com/api/premium_live/search?page=1&count=30&is_pickup=0&time=<Unix 秒>`（`is_pickup=1` 是精选；从 `premium_live` 页面的脚本里找到）。2026-09-28 18:42 UTC 查到 5 场，都还没开始（`is_onlive: false`，`premium_live_type` 都是 4）：358854 在 2026-09-30 11:00 UTC，291006 在 10-01 13:00，421059 在 10-06 11:00，115356 在 10-10 04:00，484073 在 10-31 08:00。当时快照里 109 行的 `premium_room_type` 全是 0。
  - 这 5 个房间未开播时，`live_info` 和 `room/profile` 的 `premium_room_type` 也都是 0，所以这个字段只在付费直播进行时才可能不同，写什么值、`streaming_url` 是空列表还是报错、快照里会不会列出，都没有证据。归档规格把 `premium_room_type != 0` 当作付费（§12 待确认 1），也没有样本。
  - 最早能补录的是 358854（`https://www.showroom-live.com/r/1ce973505769`）在 2026-09-30 11:00 UTC（北京时间 19:00）开始的付费直播：届时录 `live/onlives`、`live/live_info`、`room/profile`、`live/streaming_url`，确认后把 `restrictionOf` 的非 0 值改成 `paid`，取流时报带原因的 `StreamUnavailable`。现在非 0 值留空，不会误标。
- **年龄验证**：`age_verification_status`、`is_under_18`、`is_under_16` 在样本和实测里都是 0，含义不明，没有用。
- **只有声音的直播**（`live_type` 4、`is_radio_now`）：实测 2 个房间都有 HLS 地址，按普通直播处理；画面只有背景图，是平台如此。

### 新样本

无。19-5 需要的付费直播样本现在录不到（见上）；其他条目用现有样本和合成数据就能测试，实测只用于核对，没有存成样本。

### 测试

本平台 61 个用例（E03.6 是 55 个；新增 6 个，另改写了快照、容错、画质顺序、详情的用例），`live_core` 共 3256 个，门禁 `--all` 通过：

- `showroom_api_test.dart`（33 个）：
  - 样本对照：S01 每张卡片的开播时间和 `none`；S03 在播详情的开播时间和 `none`，未开播详情没有人数（19-4）；S05 画质顺序（19-2），名称、id、地址和恢复与 v3 一致；
  - 容错：坏行只跳过自己、全是坏行仍报错、只有消息格子是空；坏类型只跳过自己、没有类型仍报错；坏画质行只少一档、全坏是 `ApiChanged`、坏行不挡住同地址的好行；
  - 开播时间的取值范围；`premium_room_type` 的各种值；未开播时不用 `current_live_started_at`；
  - `live_info`：在播时的受限类型和弹幕参数、未开播都没有；弹幕参数的主机和键的检查、不合格时房间照常在播；`toString` 不带键；
  - 画质阈值和排序：“自动”排在 `quality` 为 0 的一档之后。
- `showroom_site_test.dart`（28 个）：
  - 19-1：第 1 页重新请求并成为共用快照；第 2、3 页、分区第 2 页、搜索第 2 页、取分类、推荐切片都不再请求，三页 64 个房间不重复不遗漏；搜索第 1 页也是刷新；29 秒内复用、30 秒重新请求（带令牌）并再次共用；不带令牌的第 1 页也刷新；时钟倒退时不复用；
  - 带令牌的后续页不等进行中的共用请求、自己请求并成为共用快照；取消、回答晚于取消、失败都不留快照，之前的快照照常可用；v3 的缓存场景仍是 2 个请求；
  - 进房和录制带 `ShowroomDanmakuArgs`，刷新不带；三种深度的开播时间、`none`；未开播没有人数、开播时间、受限类型和弹幕参数；在播 → 下播的合并清掉开播时间和受限类型（人数保留，交给 M13）；
  - 画质顺序和 id、用第一档（原画）播放刷新得到的房间、恢复“自动”。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.16 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.16-SHOWROOM弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
