# E02.12 六间房

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/sixroom/`（`sixroom_api.dart` 纯解析和链接规则，`sixroom_site.dart` 请求编排）
- 样本：`fixtures/sixroom`，17 个真实接口录制：
  - 10 个来自归档（2026-09-27）：移动端列表 `S01-list-*`（5 个）、搜索页 `S02-search`/`-empty`、房间页 `S03-room-live`/`-offline`/`-notfound`。其中 `S01` 是归档 v4 改用的移动端列表接口，v3 不发，没有 `expected.json`，留给升级候选 4；
  - 7 个本模块补录（2026-09-28 13:51，同一分钟，本机默认出口，不经代理），都是 v3 自己的请求，请求头和表单与 v3 逐字相同：首页 `S04-home`（v3 的目录来源）；在播房间 8838 的房间页 `S05-page-live` 和 inroom 回答 `S05-inroom-live`；未开播房间 191111 的 `S05-page-offline`、`S05-inroom-offline`；不存在的用户 `S05-inroom-missing`（`flag` 402）；超长关键词的提示页 `S05-search-long`。归档没有录首页和 inroom，没有它们就无法对照 v3 的目录和详情；
  - 归档没有六间房的弹幕样本（v3 没有聊天，归档规格 §7 也没做），所以没有 `danmaku` 目录。
- 参考：
  - 归档 v4 的六间房适配器和规格（`spec/sites/sixroom.md`）。规格没有 REG-SIXROOM 条目，只有 §10“踩过的坑”三条（见“回归条目的覆盖”）；
  - pure_live_TV `lib/platforms/sixroom/`：与 v3 逐行相同，只改了导入路径和三处可空标注（对照笔记 `small_diffs.txt` 的 sixroom 一节、`sub_A.md` 的 sixroom 一节），没有行为修复。`sub_A.md` 已经指出 TV（即 v3）的房间页正则失配。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；修好但会改变这些内容的地方，列入“后续升级候选”；关注刷新和列表的请求不比 v3 多。

## 做法

- **接口和输出沿用 v3**：`LiveSite` 和 v3 实现过的全部可选能力——目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `sixroom_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、关注刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、取流（`LivePlayUrlResolver`）、恢复（`LivePlayRecoveryResolver`），外加 `LiveSiteLinks`。3.x 的 JSON 不变，平台名仍是 3.x 中文界面的“六间房直播”。
- **请求照 v3**：全部匿名，以 `sixroom` 的名义发出（代理由应用按平台注入），带 v3 的请求头（网页：Chrome 140 的 UA、`Accept`、`Accept-Language: zh-CN`、`Referer: https://v.6.cn/`；inroom：iOS 客户端 UA、`Referer: https://ios.6.cn/?ver=8.0.3&build=4`、表单类型），**不跟随跳转**，不带 Cookie（v3 的六间房没有账号）。一次列表调用、一次房间调用（包括它的全部请求）共用一个 20 秒的总时限（v3 的 `_scope`），超时是 `NetworkFailure`，调用方取消原样抛出取消；单个请求 15 秒（v3 的接收时限）。
- **目录照 v3**：
  - 一个分类“六间房直播”，六个分区（`areaType: official`）：全部 `all`、歌区 `song`、舞区 `dance`、脱口秀 `talk`、星颜 `face`、派对 `party`，只在第 1 页、每页条数至少 1 时给出前 `pageSize` 个，不发请求；
  - 所有列表都来自首页 `https://v.6.cn/`（约 1.1 MB，`window.__SMARTY_ALL_VARIABLES__` 里的 `typeList`，2026-09-28 共 443 个在播房间），按 `anchor_area` 等于分区名在本地筛选、分页。原生目录每页 30 个，推荐和分区房间每页 `pageSize` 个（最多 100）；
  - 首页快照 90 秒：“全部”的第 1 页（包括推荐第 1 页）总是重新下载，其他页和分区在 90 秒内复用；时钟倒退也重新下载（v3）。时钟可以注入；
  - 卡片：房间号 `rid`、用户 id `uid`（缺一个就跳过，同一房间只留第一张）、昵称（空时 `Six Rooms`）、标题（`livetitle`，再 `userMood`，再昵称）、头像 `picuser`、封面（`pospic`，再 `pic`，再 `pospic_sp`）、分区 `anchor_area`（空时显示“六间房直播”）、`count` 作为热度（口径 `popularity`），全部是直播中；图片只收 6.cn、6rooms.com、xiu123.cn 上的 https 地址（`//` 和 `http://` 补成 https，v3）。
- **搜索照 v3**：房间号或房间链接只在第 1 页查这个房间（不取流，房间不存在算没有结果）；其他关键词请求 `search.php?type=use&key=…`（一页），取前 `pageSize` 个：用户 id、`a.user-box` 链接里的房间号、`.alias` 作为昵称兼标题、`.pic img` 的 `data-src`（再 `src`）作为头像，状态“未知”。空白、页码小于 1、条数不在 1～100 给空，不发请求。结果全部记下，并用已知的卡片补全（v3 的 `_remember`）。
- **房间照 v3**：
  - 详情是移动端 `coop-mobile-inroom.php` 的 POST（表单 `av=3.1&encpass=&logiuid=&project=v6iphone&rate=1&rid=&ruid=<用户 id>`）。用户 id 取自列过的房间（目录、搜索、详情），没有时先读房间页 `https://v.6.cn/<房间号>`（v3 也这样做，见问题 1）：规范链接必须是这个房间，`rid: '<用户 id>'` 紧挨着这个房间的 `roomid`；
  - inroom：`flag` 为 `001`；`roominfo.rid` 和 `roominfo.id`（没有时 `roomParamInfo.uid`）必须是请求的房间和主播；私密房（`isPriveRoom`）或黑屏（`blackScreenInfo.msg`）是“受限”，显示为状态未知并加 3.x 的受限公告；有场次 id 和流名是直播；否则未开播。昵称 `alias`；标题 `liveinfo.title`，再 `roominfo.userMood`，再昵称；头像 `headPicUrl`、`picuser`（都取不到时显示封面，v3，见问题 2）；封面 `spredPic`、`pospic`、`largepic`、`pic`；分区 `anchor_area`，再 `rtypename`；`fans_num` 作为关注数；
  - **记住列过的房间**（v3 的 `_known`）：房间回答缺的用户 id、场次、头像、封面、分区、热度、关注数，占位的昵称和标题，以及“未知”的状态，从最近一次见到的卡片或房间补上，补完的再记下来。现在最多记 2000 个房间（v3 不设上限）；
  - 房间号保持请求时的号码（链接取出房间号，v3）；不是房间号的输入是 `NotFound`，不发请求；
  - 详情带 `SixRoomRoomData`：房间号、用户 id、场次、状态，进房和录制时还有 FLV 流（刷新不取，v3）。界面按状态显示自己语言的公告（M13）。进房详情另带弹幕参数 `SixRoomDanmakuArgs`（房间号和用户 id，不多发请求）。
- **取流照 v3，改为线路**：
  - 画质只有一档，id `flv:source`，名称是 3.x 的“FLV 原始线路”，知道分辨率和码率时写成“FLV 原始线路 · 1024x768 · 2652 kbps”，排序值是码率（没有时 1）；
  - 地址 `https://wlive.6rooms.com/httpflv/v<用户 id>-<场次>[-many].flv`（流名必须与主播和场次对得上，v3）；`resolvePlayUrlsRaw` 不发请求，确认的画质是 `flv:source`；恢复时重新请求房间（知道用户 id 时一个请求，v3，REG-LEASE-005）；
  - 线路：FLV，编码取自 `streamInfo.videoCodec`（样本是 `avc`），线路编号 `wlive`；**请求头为空**：v3 的 `PlaybackHeaderResolver` 没有六间房分支，播放器和录制器实际什么都不发（房间里的 `httpHeaders` 从未被用到），2026-09-28 实测不带请求头照样 302 到网宿并拿到 FLV；没有 `PlayLease`（地址不带到期参数）；
  - 不能播时说明原因：卡片、刷新得到的房间、未开播、受限、状态未知都是 `StreamUnavailable`；流名对不上是 `ApiChanged`；别的画质、别的平台的房间是 `ArgumentError`。
- **开播状态**：刷新的请求（v3）；受限和状态未知报 `StreamUnavailable`，不当作未开播。
- **链接照 v3**：纯房间号（2～12 位，不以 0 开头）和 http(s) 的 `v.6.cn`、`m.6.cn` 链接，路径恰好是 `/<房间号>` 或 `/profile/<房间号>`（`profile` 不分大小写，可带查询，不带用户信息和片段，默认端口）；其他主机、搜索页、`m.v.6.cn` 等都不认，不发请求。
- **没有 Cookie、登录**：v3 的六间房全部匿名，所以不注入 `CookieVault`。

## 审查发现的 v3 问题

位置简写（都在 `legacy/lib/` 下）：`A` = `core/site/sixroom/sixroom_api.dart`，`S` = `sixroom_site.dart`，`L` = `sixroom_link.dart`，`phr` = `player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | **没在本次运行里列过的房间一律打不开**：关注刷新、从关注进房、录制、粘贴链接、按房间号搜索都报 `schema`；只有先看过目录或搜索、记住了用户 id 的房间能进 | A:280-283、A:383-387；S:185-192 | 房间页正则要求 `roomid: '<n>'` 带引号，页面现在写 `roomid: 8838,`（样本 S05-page-live、S03-room-*，归档规格 §10、对照笔记 `sub_A.md` 都已指出） | 修正则：`roomid` 带不带引号都认（数字后面不能再跟数字）。请求照 v3 的设计：先房间页取用户 id，再 inroom（两个请求；记住用户 id 时一个） |
| 2 | 详情的头像总是空，界面显示封面 | A:447；S:97 | 读 `roominfo.headPicUrl`（现在是空）和 `roominfo.picuser`（没有这个字段），头像其实在 `roominfo.uoption.picuser` | 按 v3 保留（用户一直看到的样子：先看过目录的用卡片头像，否则显示封面）；真头像只在既没有头像也没有封面时兜底，改显示真头像列为升级候选 1 |
| 3 | 详情标题总是昵称，关注刷新会用昵称盖掉卡片存下的签名 | A:424 | 读 `roominfo.userMood`，回答里没有；签名在 `roomParamInfo.operation.userMood` | 按 v3 保留，列为升级候选 2 |
| 4 | 关键词超过 15 个字（6.cn 的上限）就报“无权访问” | A:269、A:338-341 | 6.cn 对超长关键词回“六间房提示您：输入内容过长”（样本 S05-search-long），v3 把所有提示页当 `access`；v3 自己的上限是 80 | “输入内容过长”算没有结果；超过 80 个字也给空结果，不发请求（v3 是 `schema`）。其他提示页仍报错（`RiskControl`，带提示文字） |
| 5 | 搜索结果的状态总是“未知”，页面其实标了“直播中” | A:364 | 不读 `<i class="live">` | 按 v3 保留，列为升级候选 3 |
| 6 | 错误没有类型：9 种 `SixRoomFailure`；调用方传错分区、画质、平台也报 `identity`、`mediaUnavailable`；`_scope` 把任何非平台异常（包括解析时的程序错误）都记成 `transport`；inroom 的 `flag` 402（“暂不能进入此房间”，没有房间的用户）和格式问题混在 `access` 里 | A:12-21、A:198-215、A:401、A:589-598；S:65-75、S:178-183、S:256 | 平台自己的异常类型 | 类型化错误：404/410 `NotFound`，429 `RateLimited`，401/403 和跳转 `RiskControl`（v3 的 `access`），5xx 和其他状态码 `NetworkFailure`，结构不符 `ApiChanged`，`flag` 402 `NotFound`、其他 `flag` `RiskControl`、没有 `flag` `ApiChanged`，不能播 `StreamUnavailable`；分区、画质、平台错误是 `ArgumentError`，第 10000 页以后是 `RangeError`，都不发请求 |
| 7 | 明确未开播的房间取画质得到空列表，播放器拿不到原因 | S:226 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 8 | 开播状态在受限、状态未知时报 `access` | S:207-211 | 同问题 6 | `StreamUnavailable`，仍然不当作未开播 |
| 9 | 房间写了媒体请求头（`httpHeaders`），但播放器和录制器从不用它 | A:143-147；S:111；phr:52-196（没有六间房分支，落到 `default` 的空表） | 请求头按平台写在播放层 | 线路不带请求头（v3 实际的行为，实测 CDN 不要求）；房间的 `httpHeaders` 按 3.x 的 JSON 保留 |
| 10 | 记住的房间没有上限，浏览越久占用越多 | S:28、S:77-83 | `Map` 只增不删 | 最多 2000 个，最旧的先忘；首页只有约 450 个房间，平常用不到这个上限，结果与 v3 相同 |
| 11 | 已经下播的房间，刷新后仍显示最近一张卡片的热度 | A:87 | 补全时 `popularity ?? known.popularity` 不看状态；inroom 没有热度 | 按 v3 保留（用户看到的内容），列为升级候选 5 |
| 12 | 刷新得到的房间不能播放 | S:112、S:213-221 | 只有进房和录制详情带 `data`（刷新不读流） | 按 v3 保留（刷新的内容和请求数不变）；现在报 `StreamUnavailable` 并说明要先进房 |
| 13 | 房间链接的路径含非法百分号编码（`/%FF`）时抛 `FormatException` | L:25 | 解码路径不捕获异常 | 认不出，返回 null |
| 14 | 平台层用全局 HTTP 单例，自己实现流式读取（8 MiB、严格 UTF-8）；平台名以外的文字（公告、画质名）调用界面翻译，公告按当时的界面语言写进房间并随关注存下 | A:155-196；S:34、S:87-90、S:99、S:237-238 | 结构问题；`i18n` 写在适配器里 | 注入 `LiveHttp`，下载后按 UTF-8 字节检查 8 MiB；写 3.x `zh.json` 的中文（与 3.x 中文界面存下的相同），状态放进 `SixRoomRoomData`，由界面翻译（M13） |
| 15 | 每次刷新目录都下载约 1.1 MB 的首页；详情的 inroom 回答约 19 万字节（含观众列表和聊天记录） | A:238-262、A:284-289 | v3 的接口选择 | 按 v3 保留（换接口会改变列表内容、分页、分区和详情字段），列为升级候选 4 |

## 样本与 v3 的冻结输出

归档没有六间房的 `expected.json`（归档的旧版对照工具只做了前五个平台，规格 §11 也写明没有旧版期望值）。本模块用 `fixtures/sixroom/legacy_expected.dart` 生成，做法同 Steam 直播、BIGO LIVE：

- 把 v3 的 `SixRoomApi`、`SixRoomLink`、`SixRoomSite` 原样搬进一个 Dart 脚本。v3 本来就把传输做成可注入的函数（`SixRoomRequest`），所以只换了它：按方法、主机、路径、查询参数和表单读样本，回给录下的状态码和正文；没有样本的请求抛 StateError，v3 的 `_scope` 把它记为 `transport`，脚本另记在 `unmatched` 里（生成结果里没有出现）。只在网络路径上用到的 `_defaultRequest`、`_readBody` 没有搬，构造函数改为必须注入传输；站点类保留方法体，去掉 `extends`/`implements`、`@override` 和 `getDanmaku`（`EmptyDanmaku`）。首页快照的时钟用 v3 自己的 `clock` 参数注入。
- `withRequestCancellation` 照抄，Dio 的取消令牌换成桩；`i18n` 返回 3.x `zh.json` 的文字（带 easy_localization 的 `{name}` 参数）；v3 的 `LiveRoom` 等模型只搬用到的部分（`toJson` 里有 v3 的 `HttpHeaderPolicy.normalize`）。
- v3 用 `package:html` 解析网页，工作区不依赖它，所以脚本用临时的包配置运行（`html: 0.15.6`，同 Steam 直播；命令写在脚本开头）。
- 输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记请求的方法、地址、请求头和表单。

12 个样本有 `expected.json`：

| 样本 | 内容 |
|---|---|
| `S04-home` | 分类（第 1、2 页，条数 3、0）；`parseDirectoryHtml`（443 个房间）；“全部”的 15 页和六个分区的每一页（同一个站点，记录每次的请求）；歌区第 1 页；边界（第 0 页、第 0 页加别的平台、第 10000 和 10001 页、别的平台、别的类型、未知分区、带空格的分区 id）；90 秒快照的 9 步（空缓存、分区、第 2 页、第 1 页、+89 秒、+90 秒、推荐第 2 页和第 1 页、时钟倒退）；推荐的 8 种切片；3 个分区的前 5 个、派对第 2 页、别的平台；首页的 17 种改动（`typeList` 是列表或 JSON 文本、没有标记、没有 `typeList`、不是 JSON、不完整、字符串里的括号、空、重复、坏的房间号和用户 id、数字、`lid`、5 种标题、8 种图片、7 种 `count`、分区、不是对象的行）；38 个链接的 `parseRoomId`、4 个 `watchUrl`；`mediaHeaders`；目录说明键和平台名 |
| `S02-search` | 与 `S02-search-empty`、`S05-search-long`、`S05-page-live`、`S05-inroom-live`、`S03-room-notfound` 一起：`parseSearchHtml`（35 张卡片）和 3 种改动的页面；19 组关键词、页码和条数的搜索（包括超长、超过 80 个字、房间号、房间链接、资料页链接、不存在的房间） |
| `S02-search-empty`、`S05-search-long` | `parseSearchHtml` |
| `S05-inroom-live` | 与 `S05-page-live`、`S04-home` 一起：冷启动（v3 先读房间页）和看过目录后的三种深度的详情、开播状态，进房和刷新得到的房间的画质、地址、恢复、`getPlayUrls` 和别的画质；只知道用户 id 时 v3 的详情（`SixRoomApi.room`，两种深度）；坏的用户 id；房间链接、别的平台、不是房间号；看过房间后的目录卡片；`parseRoomJson` 的录下的回答（两种深度、4 种问法）和 48 种改动；7 组 `mediaUri` |
| `S05-inroom-offline` | 与 `S05-page-offline`、`S02-search` 一起：冷启动和搜索过后的房间调用；只知道用户 id 时的详情；`parseRoomJson` |
| `S05-inroom-missing` | 知道用户 id 时的详情（402）；`parseRoomJson` |
| `S03-room-notfound` | 详情、开播状态、按房间号搜索（404）；把 404 页当房间页解析 |
| `S05-page-live` | `parseRoomUserIdHtml`：录下的页面和 13 种改动（`roomid` 带单引号或双引号即 v3 的格式、问别的房间、问链接、问坏的 id、规范链接是别的房间、没有规范链接、`rid` 旁是别的房间、没有 `rid`、`roomid` 多一位、提示页、短页面、v3 测试的页面） |
| `S05-page-offline`、`S03-room-live`、`S03-room-offline` | `parseRoomUserIdHtml`（录下的页面；未开播的另有带引号的改动） |

**脱敏**：补录脚本按归档规则（`tools/live_cli/lib/src/fixture/rules/sixroom.dart`）把推流服务器的内网地址 `ip`（房间页和 inroom 里同一个值，换成同一个同形的合成值）换掉；另外：

- 首页的 `recid` 和脚本里的 `ZHANG_ZHI_RECID`（每次请求递增的推荐编号）换成同形的合成值；
- inroom 的 `roomlist`（在场观众）每个列表只留主播本人，`safeStar`（守护之星，一位观众）的用户 id、昵称、房间号和头像换成合成值（昵称写“观众1”）；它的用户 id 也出现在主播自己设置的充值链接 `operation.paylink` 里，那是主播公开页面的内容，保留；`roommsg`（最近的聊天）换成空列表。
- 原值还能找到就拒绝写入。复制后又检查了全部 17 个样本（包括归档的 10 个）：没有出口 IP（出现的 IPv4 只有 UA 里的 `132.0.0.0`、推流端版本号、合成的内网地址，以及主播推流端报告 `banlvInfo` 里的局域网 `192.168.x.x`，归档规格 §11 定为主播公开数据、原样保留）；没有 Cookie（6.cn 不下发）、访客或设备编号、token；响应头里没有回显客户端地址的字段（master 的 `tools/gate/check_fixtures.py` 对 37 个 JSON 文件检查通过）。主播昵称、头像、房间号、用户 id 是公开信息，保留（同归档规格 §11）。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；另比较请求的方法、地址、请求头和表单。

| 样本 | 结果 |
|---|---|
| S04 分类 | 一致：1 个分类“六间房直播”，6 个分区。v3 的 `areaPic`、`shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S04 首页 | 443 个房间的每个字段（房间号、用户 id、场次、昵称、标题、头像、封面、分区、热度、状态）一致；17 种改动的首页一致（v3 的 `schema` 现在是 `ApiChanged`） |
| S04 目录、推荐、分区 | “全部”15 页 443 张卡片的每个字段（包括公告和 `httpHeaders`）、“还有下一页”一致；六个分区每一页的房间和顺序一致；每次调用的请求（下载或复用首页）与 v3 相同；90 秒快照的 9 步结果和请求一致；8 种推荐切片、分区切片一致；v3 先进入 `_scope` 再报错的第 10001 页现在不发请求 |
| S02 搜索 | 35 张卡片、3 种改动的页面、13 组关键词的结果和请求一致；v3 的提示页（`access`）现在是 `RiskControl`，没有结果区块（`schema`）是 `ApiChanged` |
| S05 超长关键词 | v3 报 `access`（请求一次），现在是空结果（同样一次请求）；超过 80 个字 v3 报 `schema`，现在是空结果，都不发请求 |
| S05 房间号搜索 | v3 读房间页后报 `schema`；现在是这个房间（房间页加 inroom 两个请求），与 v3 只知道用户 id 时的详情一致 |
| S05 房间页 | 录下的 4 个页面 v3 都报 `schema`（问题 1），现在读出用户 id；v3 格式（带引号）的页面和各种改动结果一致（v3 的 `identity`、`schema` 现在是 `ApiChanged`，`missing` 是 `NotFound`，问坏的 id 是 `ArgumentError`） |
| S05 在播房间 | 看过目录后三种深度的房间逐字段一致（标题是昵称、头像取卡片的、热度 23444 取卡片的、关注数 425628），请求一致（只有 inroom）；冷启动 v3 报 `schema`，现在与 v3 只知道用户 id 时的详情逐字段一致（头像显示封面），请求是 v3 发过的房间页加 inroom；看过房间后的目录卡片带上了关注数，与 v3 一致 |
| S05 取流 | 画质“FLV 原始线路 · 1024x768 · 2652 kbps”/`flv:source`、排序 2652、地址、确认的画质一致，都不发请求；恢复的请求（一个 inroom）和地址一致；刷新得到的房间 v3 报 `identity`，现在报 `StreamUnavailable`；别的画质 v3 报 `mediaUnavailable`，现在是 `ArgumentError` |
| S05 未开播 | 冷启动和搜索过后三种深度的房间一致（搜索卡片的头像、关注数 1812607），开播状态为假；v3 取画质给空列表，现在报 `StreamUnavailable` |
| S05 inroom 解析 | 录下的两个回答和 48 种改动的结果一致（私密、黑屏、没有场次或流名、流名对不上、`-many`、没有 `streamInfo`、`bitrate`、其他线路、标题、签名、昵称、6 种头像、4 种封面、分区、6 种关注数）；v3 的 `identity` 现在是 `ApiChanged`（坏的输入是 `ArgumentError`），`schema` 是 `ApiChanged`，`access` 按 `flag` 分成 `NotFound`（402）、`RiskControl`、`ApiChanged` |
| S03 不存在 | 详情、开播状态 v3 是 `missing`，现在是 `NotFound`；搜索都是空结果；请求一致 |
| 链接 | 38 个链接一致，只有 `/%FF`：v3 抛 `FormatException`，现在认不出 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 没列过的房间（关注、链接、房间号搜索、录制）能打开了：先读房间页取用户 id，再 inroom | 问题 1。请求与 v3 的设计相同（v3 也先发房间页，只是解析失败），房间内容与 v3 只知道用户 id 时相同 |
| 2 | 超过 15 个字的关键词给空结果（v3 报 `access`），超过 80 个字也给空结果（v3 `schema`） | 问题 4 |
| 3 | 出错抛类型化错误；调用方错误不发请求；不是房间号的输入是 `NotFound` | 问题 6 |
| 4 | 明确未开播的房间取画质报 `StreamUnavailable`（v3 给空列表）；卡片、刷新得到的房间、受限、状态未知报 `StreamUnavailable`（v3 `identity`、`mediaUnavailable`）；流名对不上报 `ApiChanged`；别的画质、别的平台是 `ArgumentError` | 问题 6、7、12。只在播放路径上，状态和分组不变 |
| 5 | 开播状态在受限、状态未知时报 `StreamUnavailable`（v3 `access`） | 问题 8。仍然不当作未开播 |
| 6 | 取流结果是线路：FLV、编码、线路编号 `wlive`，请求头为空，没有租期 | 问题 9。地址与 v3 相同 |
| 7 | 各种深度的详情都带 `SixRoomRoomData`（不写进 JSON；刷新得到的不含流）；进房详情带 `SixRoomDanmakuArgs` | 留给 D01 和 M13，不多发请求 |
| 8 | 既没有头像也没有封面时，头像用 inroom 的 `uoption.picuser`（v3 为空） | 问题 2 的兜底。样本里的房间都有封面，显示与 v3 相同 |
| 9 | 记住的房间最多 2000 个 | 问题 10 |
| 10 | 不再有逐字节的 8 MiB 流式读取和严格 UTF-8；下载后仍按 UTF-8 字节检查 8 MiB | 问题 14。传输由 live_net 统一负责，20 秒总时限相同；非法 UTF-8 按替换字符处理（同 Steam 直播、BIGO LIVE） |
| 11 | 网页用 `HtmlElement` 解析（v3 `package:html`） | 不增加依赖；35 张搜索卡片、4 个录下的房间页和全部改动的页面，结果与 v3 逐字段相同 |
| 12 | 链接路径的非法百分号编码认不出（v3 抛异常）；搜索卡片的链接解析失败时跳过这张卡片（v3 整个搜索报 `transport`） | 问题 13 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **目录仍来自首页**。归档 v4 改用移动端列表接口 `coop-mobile-getlivelistnew.php`（每页 20 个，样本 `S01-list-*`）：没有“全部”和“星颜”（`u10` 返回空，归档规格 §2.1），推荐换成跨分区的 `special`，列表内容、顺序和分页都会变，3.x 关注的分区 id（`song` 等）也对不上。列为升级候选 4。
- **`count` 是热度**（口径 `popularity`，3.x 的人数口径表 `live_room.dart:214-221`）。归档 v4 当作在线人数，对照笔记 `sub_A.md` 认为需要实测确认。
- **详情仍读 inroom**。归档 v4 只读房间页：拿不到关注数 `fans_num`，也识别不了私密房和黑屏（对照笔记 `sub_A.md`：“TV 有、v4 没有”），标题会换成 `privNotic`，分区换成 `usertype` 的映射。
- **搜索卡片的状态是“未知”**。归档 v4 读 `class="live"` 分成直播和未开播；列为升级候选 3。
- **画质名称“FLV 原始线路 · …”、id `flv:source`**。归档 v4 叫“原画”、id `source`，会改变画质菜单。
- **线路不带请求头**（v3 播放和录制实际发的）。归档 v4 带桌面 UA、`Origin`、`Referer`；实测不需要。
- **有 6 个分区**，第一个是“全部”。归档 v4 只有 4 个，分类叫“分区”。
- **房间号的写法**：保持请求时的号码（链接取出房间号），与 v3 相同，3.x 存下的关注能对上。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 详情和刷新显示主播真头像（inroom `roominfo.uoption.picuser`） | 没看过目录的房间头像位置显示封面，关注刷新会把存下的头像换成封面 | 问题 2；样本 S05-inroom-* |
| 2 | 详情标题用签名（`roomParamInfo.operation.userMood`，或房间页的 `privNotic`） | 详情标题是昵称，关注刷新盖掉卡片的签名 | 问题 3 |
| 3 | 搜索卡片按 `<i class="live">` 标出直播中 | 全部是“未知” | 问题 5；归档 v4、归档规格 §3 |
| 4 | 目录改用移动端列表接口（按分区分页，不再下载 1.1 MB 首页），详情改读房间页（不再下载 19 万字节的 inroom） | 首页本地筛选；inroom 详情 | 问题 15；归档 v4、归档规格 §2、§4；样本 `S01-list-*`、`S03-room-*`。需要先确认星颜、私密房和关注数的来源 |
| 5 | 已下播的房间不再沿用卡片的热度 | 显示最后一次卡片的热度 | 问题 11 |
| 6 | 聊天（6.cn 私有 WebSocket） | 没有聊天，公告写“远端聊天尚待接入” | 归档规格 §7（匿名接入方式待确认）；本模块已输出 `SixRoomDanmakuArgs` |

## 回归条目的覆盖

归档规格没有 REG-SIXROOM 条目。§10“踩过的坑”和 `spec/regressions.md` 里涉及平台层的通用条目，都有测试或说明：

- **所有房间详情失败**（§10，旧正则要求带引号的 `roomid`）：修了正则（问题 1），4 个录下的房间页都能读出用户 id，v3 格式的页面仍然认；冷启动的房间、房间号搜索和链接都有测试。
- **目录慢、流量大**（§10，每次下载首页）、**详情请求大**（§10，inroom）：按 v3 保留（换接口会改变用户看到的列表和详情），列为升级候选 4；90 秒快照和“记住用户 id 就不读房间页”有测试。
- REG-COMMON-001（失败不等于下播）：传输失败、各种状态码、`flag` 都是类型化错误；受限、状态未知的开播状态报错，不当作未开播。
- REG-COMMON-002（错误有类型）：8 种状态码、传输失败、`flag`、提示页和调用方错误的映射。
- REG-COMMON-003（五态）：直播、未开播；受限和搜索卡片是“未知”。
- REG-COMMON-004（人数口径）：首页 `count` 是热度，缺值时口径未知，不写 0；关注数单独放在 `followers`。
- REG-COMMON-005（画质以确认为准）：确认的画质是 `flv:source`。
- REG-COMMON-008（请求头随线路走）：线路自带请求头（空，与 v3 实际发的一致）。
- REG-COMMON-011（链接识别）：38 个链接与 v3 一致，经 `LinkParser` 的分享文本、搜索页、仿冒域名、片段链接不认，不发请求。
- REG-LEASE-001、005（租期是结果的一部分；恢复重新取）：没有租期；恢复重新请求 inroom，不复用旧地址。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 聊天（v3 没有；6.cn 私有 WebSocket）；`getDanmaku()` | D01（升级候选 6）；本模块输出 `SixRoomDanmakuArgs`；没有弹幕样本；同 E01.1，D01 用一张“平台 → 弹幕连接”的表 |
| 播放、录制按线路打开 FLV（v3 的 `PlaybackHeaderResolver`、`ffmpeg_header_factory.dart` 没有六间房分支） | G、H01.1 |
| 目录说明 `sixroom_directory_scope`、公告 `sixroom_chat_notice`/`sixroom_restricted_notice`、画质名 `sixroom_quality_source`/`sixroom_quality_source_detail`、平台名 `site_sixroom` 的繁体和英文，分区名（全部、歌区……）的多语言，按 `SixRoomRoomData.state` 显示公告 | M13 多语言。本模块给出 3.x 的中文 |
| 搜索能力表：原生搜索、覆盖直播和未开播、不翻页、没有网页搜索（3.x `search_capability.dart:106-110`） | M13 搜索页 |
| 外部打开房间页（3.x `room_external_opener.dart:137-138`） | M13；地址由 `SixRoomApi.link` 提供 |
| 本地互动包（3.x `local_interaction_controller.dart:497-504`） | M13 |
| 平台列表升级时追加六间房（`favorite_room_controller.dart:93`，第 37 版） | J02.1 |
| 人数口径（3.x `live_room.dart:214-221`） | 已在 E05.1 的 `audience.dart` |
| 录制平台清单（3.x `test/recording_platform_contract_test.dart:41`） | H01.1 |
| 图片请求的请求头（3.x `networkImageHeaders`） | A01.1 |

## 新增的通用能力

没有。用到的 `HtmlElement`、`LivePlayLine`、`LivePlayUrlResolution.lines`、`LiveDirectoryPage` 都已存在；`live_core.dart` 按字母顺序加了两行导出。没有新的第三方依赖（生成期望值用的 `package:html` 只在临时包配置里）。

## 测试

新增 45 个用例，`live_core` 共 2560 个，全部通过：

- `sixroom_api_test.dart`（21 个）：逐个样本对照 v3 的输出（分类、443 个首页房间和 15 页卡片、六个分区、首页的 17 种改动、38 个链接、35 张搜索卡片和改动、超长关键词、4 个录下的房间页和 13 种改动、两个 inroom 回答和 48 种改动、402、7 组 `mediaUri`、只知道用户 id 时的房间），有意的差异逐条断言；移植 v3 `sixroom_site_test.dart` 的样本（首页、搜索页、房间页、在播和未开播的 inroom）；另有画质名称、线路、房间数据的不能播原因、补全规则、状态码和大小上限。
- `sixroom_site_test.dart`（24 个），用样本回放加少量合成回答：
  - 请求的方法、地址、请求头和表单与 v3 逐个相同、不跟随跳转、15 秒、平台名、目录说明、没有弹幕；传输错误和 8 种状态码；20 秒总时限；调用方取消；
  - 目录：分类不发请求；“全部”15 页和六个分区每一页的房间、“还有下一页”和请求与 v3 一致；90 秒快照的 9 步；第 0 页、别的平台和分区、第 10001 页不发请求；推荐和分区切片；
  - 搜索：13 组关键词的结果和请求与 v3 一致；超长关键词；房间号和链接查到房间；搜索过后的房间只发 inroom；其他提示页；
  - 房间：冷启动三种深度的房间和请求（v3 的房间页加 inroom）；看过目录后与 v3 一致（只发 inroom）；房间链接；看过房间后的卡片；未开播；不存在的房间（404、402）和不是房间号的输入；私密房和黑屏；只记 2000 个房间；
  - 取流：画质、地址、线路（FLV、`avc`、`wlive`、没有请求头和租期），不发请求；恢复重新取一个请求；卡片、刷新得到的房间、未开播不能播；流名对不上；恢复时已经下播；
  - 链接（经 `LinkParser`）：分享文本、带查询和中文标点的链接、资料页，搜索页、`m.v.6.cn`、仿冒域名、`www.6.cn`、带片段的链接不认，不发请求。

## 升级落地（E06 平台层升级）

- 日期：2026-09-29（E02.12）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 31-1～31-6（“落地方式”只有 31-4 有内容：换移动端列表，“全部”“星颜”能从其他接口补上就保留，已关注分区在 J02.1 迁移；其余按上面“后续升级候选”的原文做）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。31-6（聊天）属于 D01，本任务不做。
- 改动：只改了本平台：`sixroom_api.dart`（解析）、`sixroom_site.dart`（请求编排）、两份测试和 9 个新样本（见“新样本”）。没有改 `live_core` 的通用文件，没有新依赖。
- 实测：2026-09-28 20:48～21:03 UTC（北京时间凌晨，在播房间少），直连、匿名、只读：
  - 移动端列表 `coop-mobile-getlivelistnew.php`：逐个试了类型。`u0`（歌区）、`u1`（舞区）、`u2`（脱口秀）、`u8`（派对）、`special`（推荐）、`new`、`male`、`r1`、`r10` 等有房间；`u10`（星颜）、`u11`、`all`、`allLive`、`hot`、`index`、`cnew` 都回 `content: []`；`type` 为空时回 App 首页的“热门”`roomList`（46 个）和菜单 `menuList`（热门、好声音 `u0`、舞蹈 `u1`、脱口秀 `u2`、唠嗑 `u3`、星颜 `u10`……）。换 `av`、`isnew`、`project` 参数，星颜仍是空的，列表行里也始终没有头像字段。`size` 参数照单全收（30、100 都行），`roomListCount` 给出各类型的总数；
  - 网页端：首页脚本 `chunkimport-index_2016` 里，分区频道页的数据来自 `/subareaIndex/getSubareaIndexNew.php?subarea=<n>`（`singer_all` 0、`fu1` 1、`u2` 2、`u3` 3、`u8` 8、`u10` 10），首页“全部”来自 `/api/index/getLiveAjax.php`（约 59 万字节，与首页本身相当）。`subarea=10` 一次给出星颜的全部在播房间（“大图”`bigLiveList.list` 3～4 个加 `liveList` 6 个，与 `roomListCount.u10` 一致），带头像；
  - 同一时刻（20:50）首页 `typeList` 有 109 个在播房间，移动端各列表合起来只有 81 个，都在首页里；首页多出来的 28 个（15 个歌区、5 个脱口秀、5 个舞区、2 个星颜、1 个派对，多是“代理”房间）App 不展示。`special` 32 个，按人气从高到低，跨分区，含星颜；App 的“热门”46 个，不按人气排。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 31-1 | 详情、关注刷新、录制的头像取 inroom 的 `headPicUrl`、`picuser`（3.x 读的，实际为空或没有），再取 `roominfo.uoption.picuser`（主播本人的头像）；都取不到时留空，不再拿封面顶替（`liveRoom` 去掉了“头像 → 封面 → 真头像”的兜底，`SixRoomRoom.ownerAvatar` 并入 `avatar`） | 没看过目录就进房、从关注进房、刷新关注时，头像是主播本人的（3.x 显示的是封面，并随关注存下）。先看过“全部”或星颜列表的与 3.x 相同（卡片的 `picuser` 就是同一张图） | 完成（E06 平台层升级） |
| 31-2 | 详情标题：直播标题 `liveinfo.title`，再 3.x 读的 `roominfo.userMood`（实际没有），再主播签名 `roomParamInfo.operation.userMood`，最后才是昵称。签名与首页、移动端卡片的 `userMood` 是同一段文字（8838：“但行好事，莫问前程”）。房间页的 `privNotic` 是 `operation.privnote`（主播的房间公告，另一段文字），没有采用 | 详情、关注刷新的标题是主播签名，与列表卡片一致；关注刷新不再把卡片存下的签名换成昵称 | 完成（E06 平台层升级） |
| 31-3 | 搜索卡片按 `<i class="live" title="直播中">` 标直播中；没有这个标记、链接是 `/profile/<房间号>`（页面对未开播的主播给资料页链接）的标未开播；两者都看不出来的仍是“未知”（3.x 全部是“未知”） | 搜索结果里在播的主播显示直播中，其余显示未开播（样本 S02：35 个里 2 个在播） | 完成（E06 平台层升级） |
| 31-4 | **列表**：推荐（`getDirectoryPage` 不带分区、`getRecommendRooms`）改为移动端 `special`（归档适配器的做法）；歌区 `u0`、舞区 `u1`、脱口秀 `u2`、派对 `u8` 改为对应的移动端列表，每页一个请求，`size` 用界面的页大小（目录 30，其余 1～100），“还有下一页”按 `roomListCount`（没有时按满页）。“全部”仍是首页（移动端没有“全部”，网页的 `getLiveAjax.php` 与首页一样大），星颜改用网页端 `subarea=10`（移动端 `u10` 是空的）；这两个一次读全，本地分页，第 1 页重新读、之后的页 90 秒内复用（3.x 首页的做法）。分区的 id 和名字不变（`all`、`song`、`dance`、`talk`、`face`、`party`）。同一列表、同一页大小从第 1 页起的序列里，前面几页给过的房间不再列出（列表按人气变动，翻页时会重复）；同一页再请求一次不受影响。<br>**详情改读房间页**：没有做，见“受阻和未核实” | 推荐页（3.x 是“全部”）变成 App 的推荐列表：按人气排、跨分区，凌晨实测 34 个（首页当时约 110 个，晚高峰约 440 个）；每页只下载约 6 万字节，不再每次下载 0.5～1.1 MB 的首页。歌区、舞区、脱口秀、派对按 App 的顺序分页，只含 App 展示的房间（少了“代理”等只在网页展示的房间），卡片没有头像（移动端列表不给，界面显示昵称首字；看过的房间用记住的头像）。“全部”与 3.x 相同。星颜照常可用，带头像。翻页不再出现同一个房间两次 | 列表：平台层完成，余下 J02.1/M13；详情改读房间页受阻 |
| 31-5 | 补全（3.x 的 `enrich`）分出“属于这一场的”：热度、开播时间、场次号只在房间仍在直播、而且与记住的卡片是同一场（场次号相同或有一方没有）时才沿用；受限类型只在同一场时沿用。已下播的、换了一场的房间不再带上次卡片的热度。关注数、头像、封面、分区照旧补 | 刷新到已下播或重新开播的房间时，不再给出上一场的热度（热度口径为“未知”）；在播的同一场照旧显示卡片的热度 | 平台层完成，余下 M13 |
| 31-6 | 本任务不做（D01）。平台层已有弹幕参数 `SixRoomDanmakuArgs`（房间号和用户 id，进房时给出，不多发请求） | 无 | 待做（不变） |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 都填 UTC：首页卡片、移动端列表卡片、网页星颜列表的 `realstarttime`（秒）；详情取 inroom 的 `liveinfo.starttime`（秒，与首页同一场的 `realstarttime` 相同）。只在直播中填，0、空、负数、不是数字的不填。网页星颜的“大图”行只有“3小时7分前”这种相对时间，不填（进房后由详情补上）。搜索卡片没有开播时间 |
| 受限类型 | inroom 能判断，一律填：私密房（`isPriveRoom`）是 `private`，黑屏（`blackScreenInfo.msg` 非空）是 `unplayable`，其余 `none`；回答里两个字段都没有时留空。卡片（首页、移动端、星颜、搜索）看不出，不填 |
| 受限的直播改为直播中 | `SixRoomState.restricted` 去掉。私密房、黑屏的房间有场次号就是直播中（不要求流名，平台可能对受限的房间不给流名），分组在直播中，卡片标受限类型；没有场次号是未开播。3.x 是“状态未知”（E05.2 点名的“用 unknown 表示受限”）。开播状态查询对受限的直播返回在播（3.x 报 `access`，E02.12 报 `StreamUnavailable`）。取流报 `StreamUnavailable`，说明写“private room”或“black screen: <平台的提示>”；受限的房间进房不生成流地址 |
| 占位信息 | 去掉 `Six Rooms`：没有昵称时昵称为空，没有标题、签名和昵称时标题为空（首页、移动端、星颜、搜索卡片和 inroom 都是）。头像不再用封面顶替（31-1）。没有分区时分区为空，不再写平台名“六间房直播”（3.x 的做法，会随关注存下）；首页 443 个房间里只有 1 个没有分区 |
| 回放、“不可播放” | 六间房没有回放：inroom、房间页、列表都没有回放地址，下播就是未开播。黑屏是“平台说在播、但不给本客户端看”，标 `unplayable` |
| 画质命名 | 本平台表里没有改名、合并的条目，保留 3.x 的“FLV 原始线路 · 分辨率 · 码率”和 id `flv:source` |
| 默认编码 | 只有一条 FLV（样本是 AVC），“优先 H.264”对本平台没有影响 |
| 房间身份 | 不变：房间号是数字，大小写无关，不加入 `SiteIds.caseInsensitiveRoomIds` |
| 按主播关注 | 表里没有本平台的条目。房间号本来就是主播固定的房间（不是单场），不需要改 |
| 容错 | 移动端列表、星颜列表：不是对象、没有房间号或用户 id 的行只跳过这一行；一页有行而没有一行能读，或者没有这个类型的列表，报 `ApiChanged`（接口改版不会显示成空列表）；`flag` 不是 `001` 报 `RiskControl`（带平台的提示），没有 `flag` 报 `ApiChanged`，与 inroom 相同。首页照旧 |
| 翻页 | 见 31-4：移动端列表是平台分页，每页一个请求，跨页去重；“全部”和星颜一次读全、本地分页，第 1 页重新读、之后 90 秒内共用同一份（3.x 首页的时长，比统一原则的 20～30 秒长：翻到第 2 页以后再重新读会让分页错位） |
| 弹幕 | 见 31-6 |
| 说明文字 | 两个公告改成用户看得懂的话（多语言键不变，M13 按房间的受限类型显示自己语言的文字）：`sixroom_chat_notice` 从“六间房远端聊天尚待接入；大厅 count 保留为平台热度，不标记为唯一并发人数，主播粉丝数单独展示。”改为“这里暂时看不到六间房的聊天。人数是平台的热度，不是正在观看的人数。”；`sixroom_restricted_notice` 从“该六间房直播受私密房或黑屏访问条件限制，界面保持未知状态，不将其显示成未开播。”改为“这个六间房直播间是私密房或暂时黑屏，现在不能在这里观看。”。目录说明 `sixroom_directory_scope` 是界面的文字键，平台层不改，建议的新文字见“留给其他模块” |

### 请求数

| 场景 | E02.12（3.x） | 现在 | 说明 |
|---|---|---|---|
| 分类 | 0 | 不变 | — |
| 推荐（热门页）每页 | 第 1 页 1 个（首页，0.5～1.1 MB），之后的页 90 秒内 0 个 | 每页 1 个（`special`，30 个约 6 万字节） | 31-4：页数多时请求多，下载量少得多 |
| 歌区、舞区、脱口秀、派对每页 | 90 秒内与其他列表共用首页，0～1 个 | 每页 1 个（约 1.5～6 万字节） | 31-4 |
| 星颜 | 同上 | 第 1 页 1 个（约 6.5 万字节），之后的页 90 秒内 0 个 | 31-4 |
| 全部 | 第 1 页 1 个（首页），之后的页 90 秒内 0 个 | 不变 | — |
| 关键词搜索、房间号搜索 | 1；房间号 2（房间页 + inroom）或 1 | 不变 | — |
| 进房、录制、关注刷新、开播状态 | 1（记住了用户 id）或 2 | 不变 | 各列表的卡片都带用户 id，看过列表的房间仍是 1 个 |
| 取流 | 0 | 不变 | — |
| 恢复取流 | 1 | 不变 | — |
| 链接导入 | 0 | 不变 | — |

### 画质 id 对照（给 J02.1）

无：唯一的画质 `flv:source`（FLV 原始线路）名字和 id 都没有变。3.x 的画质偏好按名字存，不受影响。

### 设置项

无。本平台的 6 行都不需要开关。

### 身份迁移规则（给 J02.1）

- 房间身份不变（房间号，3.x 起就是），没有旧 id → 新 id 的规则，也没有大小写不同的重复关注。
- **已关注的分区**：分区的 `platform`（`sixroom`）、`areaType`（`official`）、`areaId`（`all`、`song`、`dance`、`talk`、`face`、`party`）和名字都没有变，3.x 存下的分区关注原样可用，不需要迁移；只是这些分区现在的房间来自移动端列表和网页星颜列表（31-4）。J02.1 迁移时核对即可。
- 数据清理建议（可选）：3.x 在没有名字时存下了 `Six Rooms`，没有分区时存下了“六间房直播”，没看过卡片时头像存成了封面。迁移 `sixroom` 的关注时可以清空：`nick`、`title` 等于 `Six Rooms` 的；`area` 等于“六间房直播”的；`avatar` 等于 `cover` 的。下次刷新（31-1、31-2）会补上真实的值。

### 与 v3 冻结输出的新差异

`expected.json` 没有改。样本对照测试里用 `changed:` 列出（测试里的常量 `_notice`、`_inroomRoom`、`_inroomAfterCard`、`_inroomParse`、`_searchCard` 写明了编号），变了的键另外断言新值：

- 所有房间：`notice`（说明文字）。
- S04 首页：443 个房间的解析、15 页卡片与 3.x 相同，只有那 1 个没有分区的房间 `area` 从“六间房直播”变为空（占位信息）；改动的首页里没有名字的两行（`titles` 的 1004、1005）`nick`、`title` 从 `Six Rooms` 变为空。“全部”分区每一页的房间、“还有下一页”和请求与 3.x 相同。
- S04 的其他分区、推荐、90 秒快照里歌区等步骤：3.x 来自首页，现在来自移动端列表和网页星颜列表（31-4），不再对照；“全部”的切片（3.x 的推荐就是全部房间）、第 10000 页、快照里“全部”的两步仍与 3.x 对照。
- S02 搜索：`state` 从 `unknown` 变为 `live`（2 张）或 `offline`（33 张）（31-3），卡片的 `liveStatus`、`status` 随之变化，`area` 从“六间房直播”变为空；改动的页面里资料页链接变为 `offline`、没有标记的房间链接仍是 `unknown`，没有名字的从 `Six Rooms` 变为空。
- S05 inroom：`title` 从昵称变为签名（31-2；有直播标题或 `roominfo.userMood` 的两种改动不变），`avatar` 从空变为 `uoption.picuser`（31-1；`headPicUrl`、`picuser` 有效的改动不变）。私密房、黑屏的 4 种改动 `state` 从 `restricted` 变为 `live`（受限类型另断言）；没有名字的两种改动 `nick` 从 `Six Rooms` 变为空。
- 房间（冷启动、只知道用户 id、搜索或目录之后）：没见过卡片时 `title`、`avatar`（3.x 显示封面）变了；见过首页卡片或搜索卡片后只有 `title` 变了（卡片的头像与 `uoption.picuser` 是同一张图）。新键 `startedAt`（直播中）、`restriction`（`none`）。
- 取流、恢复、画质、链接、状态码、S03 不存在的房间：没有变化。受限的直播开播状态从报错变为在播。
- 移动端列表、网页星颜列表、31-5 的场次判断：v3 没有输出，用 S01、S06 样本和合成回答测试。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 | 31-6 六间房聊天（6.cn 私有 WebSocket，归档规格 §7）。平台层已给出 `SixRoomDanmakuArgs`（房间号、用户 id） |
| J02.1 | 按 E05.2 存 `startedAt`、`restriction`（`none`、`private`、`unplayable`）。已关注的分区不需要迁移（见上）；可选的占位值清理 |
| M13 | 受限类型：`private` 标“私密”、`unplayable` 标“黑屏”（不可播放），发现页默认隐藏；公告按上面的新文字翻译。开播时间只在直播中显示。移动端列表卡片没有头像，显示昵称首字即可。31-5：关注刷新时 `LiveRoom.mergeFrom` 遇到空热度会保留存下的值（E05.2 的合并规则只对 `startedAt`、`restriction` 按场次清空），重新开播后的刷新在拿到新卡片前可能仍显示上一场的热度，界面合并关注时建议状态变化就清掉热度。目录说明 `sixroom_directory_scope` 建议改为：“推荐和歌区、舞区、脱口秀、派对来自六间房 App 的列表，往下翻会继续加载；“全部”是官网的全部在播房间，星颜来自官网的星颜频道。搜索能找到未开播的主播；也可以输入房间号，或粘贴 v.6.cn、m.6.cn 的直播间链接。”英文：“Recommended and the Song, Dance, Talk and Party areas come from the 6.cn app's lists; scroll for more. All is every live room on the website, and Faces is the website's Faces channel. Search finds offline streamers too; you can also enter a room number or paste a v.6.cn or m.6.cn room link.” |

### 受阻和未核实

**31-4 的“详情改读房间页”受阻**：房间页（约 6.5 万字节）比 inroom（约 19 万字节）小，也有昵称、头像、封面、场次号、流名、编码、开播时间（`flvTitle` 里的 `tm`）和黑屏（`blackScreen`），但：

- 没有关注数：`fans_num` 只在 inroom 里（页面上只有“粉丝排行”的空框，数据要另发请求）；
- 没有私密房标记：`isPriveRoom` 只在 inroom 里，房间页找不到对应字段（归档规格 §12 也列为待确认）；
- 签名不同：房间页的 `privNotic` 是 `operation.privnote`（主播的房间公告），不是卡片和 31-2 用的 `userMood`，只读房间页会让详情标题和列表卡片不一致；
- 分区只有 `usertype`（`u0` 这样的类型号），要自己换算成名字。

候选原文写了“需要先确认星颜、私密房和关注数的来源”：星颜找到了（网页 `subarea=10`），私密房和关注数只有 inroom 有。所以详情仍按 3.x 读 inroom（冷启动时先读房间页取用户 id，请求数不变）。

没有核实的：

- **私密房、黑屏的真实样本**：没有遇到，仍按 3.x 的字段和合成数据测试。私密房在播时 inroom 给不给场次号和流名不知道：现在有场次号就算直播中（不要求流名）；黑屏的 `blackScreenInfo.endtm` 没有使用。
- **星颜的 `subarea=10` 是网页频道页用的接口**，不分页，带约 5 万字节的配置（`honorConfig`）；`downFilterUids`（网页对游客隐藏的主播，与 `getLiveAjax.php` 的 `hiddenLiveList` 重合）没有用来过滤，与 3.x 首页的做法一致。
- **晚高峰的移动端列表**：只在凌晨录制过（S06；归档的 S01 是 2026-09-27 18:00 UTC，北京时间凌晨两点）；`special` 在 S01 是 64 个（App 共 128 个），S06 是 34 个。
- **表外发现，没有做**：inroom 的 `roomlist.content.num`（8838 是 23136，同一分钟首页卡片的 `count` 是 23444）看起来就是热度，可以让没看过卡片的直播间也显示热度、让关注刷新拿到当场的热度；这会改变用户看到的内容，按 AGENTS.md 的规则先列出，等用户决定。

### 新样本

2026-09-28 21:02 UTC 直连录制（同一分钟），匿名、只读。移动端列表用 3.x inroom 的请求头去掉表单类型（iOS 客户端 UA、`Accept`、`Accept-Language`、`Referer: https://ios.6.cn/?ver=8.0.3&build=4`），查询参数是归档适配器的（`av=3.1&encpass=&logiuid=&isnew=1`），`size=30`；网页星颜列表用 3.x 的网页请求头。`raw` 记原始回答（解压后）的 SHA-256 和长度。v3 不发这些请求，不带 `expected.json`。

| 样本 | 内容 |
|---|---|
| `S06-list-special-p1`、`-p2` | 推荐第 1 页 30 个、第 2 页 4 个（`roomListCount.special` 34），跨分区，含星颜 |
| `S06-list-u0-p1`、`-p2` | 歌区第 1 页 30 个、第 2 页 4 个（34） |
| `S06-list-u1-p1`、`S06-list-u2-p1`、`S06-list-u8-p1` | 舞区 18 个、脱口秀 5 个、派对 17 个（各一页） |
| `S06-list-u10-p1` | 星颜：`{"flag":"001","content":[]}`（移动端没有星颜的证据） |
| `S06-subarea-face` | 网页星颜列表：`bigLiveList.list` 3 个加 `liveList` 6 个 |

脱敏：移动端列表的 `recid`（每次请求的推荐编号，形如 `T<毫秒>-0`）换成同形的合成值（录制那一分钟的毫秒数加序号），记在各自 `meta.json` 的 `scrubbed`（`$.content.recid`）。另外查过：请求不带 Cookie，回答没有 Set-Cookie；响应头只有 CDN 节点名和请求编号（`x-via`、`x-ws-request-id`），没有回显客户端地址的字段；正文只有主播的公开信息（房间号、用户 id、昵称、头像、封面、签名、人数）和网页的配置，没有访客编号、设备编号、令牌和出口地址（新样本里的 IPv4 只有 UA 的 `140.0.0.0` 和 CSP 头里的 `127.0.0.1`）。`downFilterUids` 是主播的用户 id（与 `hiddenLiveList` 的主播重合），保留。门禁的 `fixture privacy` 通过。归档的 S01 样本没有改。

### 新增的通用能力

无。

### 测试

本平台 54 个用例（E02.12 是 45 个；新增 9 个，另改写了受影响的对照用例），`live_core` 共 3439 个，门禁 `--all` 通过；本平台两个测试文件在时钟 +30 天、+5 年下都通过（快照的时钟都注入，开播时间只和样本里的时间比较，不和“现在”比较）：

- `sixroom_api_test.dart`（24 个）：
  - 对照：分类和分区、38 个链接、S04 首页 443 个房间和 15 页卡片、17 种改动的首页、35 张搜索卡片和改动、4 个房间页和 13 种改动、两个 inroom 回答和 48 种改动、402、`mediaUri`、只知道用户 id 时的房间，变了的键用 `changed:` 列出并断言新值；
  - 31-1、31-2：真头像、签名、没有头像时不用封面、没有名字时为空；
  - 31-3：搜索卡片的直播标记和资料页链接；
  - 31-4：分区的来源、请求地址与样本一致；S01、S06 各列表的卡片、“还有下一页”（按总数、满页、空页、`content: []`）；坏行跳过，读不出的列表和 `flag` 报错；网页星颜列表的顺序、头像、开播时间和错误；
  - 31-5：已下播、换了一场时不沿用热度和开播时间，同一场沿用，受限类型随场次；
  - 统一原则：开播时间（首页、列表、inroom，坏值不填）、受限类型（私密、黑屏、没有字段）、受限的直播是直播中、新的公告。
- `sixroom_site_test.dart`（30 个）：
  - 请求：3.x 的首页、inroom、房间页请求逐个相同；推荐、分区、星颜的新请求和请求头；状态码、传输错误、20 秒总时限、取消（列表和星颜也覆盖）；
  - 目录：“全部”15 页和“全部”分区与 3.x 逐页相同；歌区、舞区、脱口秀、派对每页一个移动端请求；星颜一次读全、本地分页、90 秒；推荐是 `special`；跨页去重（同一页再请求、换页大小、第 1 页重来）；首页的 90 秒快照只用于“全部”；第 0 页、别的分区、第 10000、10001 页；“全部”的切片与 3.x 的推荐切片相同；
  - 搜索：13 组关键词的结果和请求与 3.x 相同（卡片状态按 31-3）；房间号、链接；搜索之后的房间；
  - 房间：冷启动、目录之后、搜索之后的房间和请求与 3.x 相同（变了的键列出）；移动端列表之后一个请求；私密房、黑屏是直播中、开播状态为在播、取流说明原因；31-5 的关注刷新；记住 2000 个房间；
  - 取流、恢复、链接：同 E02.12。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.28 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.28-六间房弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
