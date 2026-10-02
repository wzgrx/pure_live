# E03.12 PandaTV

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/pandalive/`（`pandalive_api.dart` 纯解析，含链接；`pandalive_site.dart` 请求编排）
- 样本：`fixtures/pandalive`，全部来自归档（2026-09-27 直连录制，匿名）：
  - v3 会请求的：人气目录第 1 页和最后一页 `S01-index-hot`、`S01-index-hot-last`，搜索的两个来源 `S03-search-live`、`S03-search-bj`，主播资料 `S04-member-live`、`-offline`、`-notfound`，`live/play` 的在播、已下播、成人 `S05-play-live`、`-castend`、`-needlogin`，IVS 主列表 `S06-master`；
  - v3 不请求、只供升级候选和 D01 用的：新人主播 `S02-index-newbj`，弹幕帧 `danmaku/S07-live`。
- 参考：
  - 归档 v4 的 PandaTV 适配器和规格（`spec/sites/pandalive.md`，回归条目 REG-PANDALIVE-001～005）；
  - pure_live_TV `e1cca224`：`lib/platforms/pandalive/` 与 v3 逐行相同，只改了导入路径，卡片和详情的在线、粉丝缺值时写空串、累计写空串而不是 null，没有行为修复（对照笔记 `~/ref/notes/tvcore/small_diffs.txt`、`sub_B.md` 的 pandalive 一节）。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；关注刷新和列表的请求不比 v3 多。

## 做法

- **接口照 v3**：`LiveSite` 和 v3 实现过的全部可选能力——原生目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `pandalive_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、关注刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、带实际画质的取流（`LivePlayUrlResolver`，给出线路）、恢复时重新取流（`LivePlayRecoveryResolver`），另加 `LiveSiteLinks`。3.x 的 JSON 不变。
- **匿名，照 v3**：所有请求以 `pandalive` 的名义发出（代理路由由应用按平台注入），带 v3 的请求头（桌面 Chrome 140 UA、`Accept: application/json, text/plain, */*`、`Accept-Language: ko-KR,ko;q=0.9,en;q=0.8`、`Origin: https://www.pandalive.co.kr`、`Referer` 为请求所代表的页面），**不跟随跳转**，不带 Cookie。表单的内容类型照 Dio 写 `application/x-www-form-urlencoded`，不带 charset。v3 没有 PandaTV 的登录和 Cookie 设置，所以不注入 `CookieVault`，也没有账号请求。
- **请求照 v3**：

  | 调用 | 请求 | 次数 |
  |---|---|---|
  | 分类 | 不请求：一个分类 PandaTV、一个分区“公开直播”（`public`） | 0 |
  | 目录、推荐、分区房间 | `POST api.pandalive.co.kr/v1/live/index`，表单 `offset=(页码-1)×30&limit=30&orderBy=hot`，Referer `/live`；页码 1～1000 | 1 |
  | 房间链接搜索（第 1 页） | `POST /v1/member/bj`，表单 `userId=<id>&info=media fanGrade`，Referer 房间页 | 1 |
  | 关键词搜索 | 第 1 页且关键词是合法的主播 id 时先查 `member/bj`（存在就只返回这个主播）；否则依次 `POST /v1/live/bj_list`（`offset&limit&searchVal`，Referer `/search/bj?text=`）和 `POST /v1/live/index`（`offset&limit&orderBy=user&searchVal`，Referer `/search/live?text=`），直播取 ⌈每页/2⌉ 条、主播取其余，各自最多 50 条、各按自己的 offset | 1～3 |
  | 关注刷新、开播状态 | `member/bj` | 1 |
  | 进房、录制详情、恢复取流 | `member/bj`；主播在播时再 `POST /v1/live/play`（`action=watch&userId&password=&shareLinkType=`），能播时再 `GET` 它给的 IVS 主列表（请求头同 API） | 1～3 |
  | 没有 `data` 的房间取流 | 同进房 | 1～3（v3 直接失败） |

- **房间身份与 v3 一致**：房间号是主播登录 id（`daisy00`，社交账号带后缀 `1506087545@ka`），**保持请求时的写法**（v3 不改大小写），与房间数据比对时不分大小写（v3 的 `_snapshot`）。数字编号 `idx` 是聊天频道号，放在 `PandaLiveRoomData.userIndex`，不作身份。v3 的 `userId` 字段照旧：目录和直播搜索卡片是登录 id，详情和主播搜索结果是数字编号。样本里所有房间号都与 `expected.json` 一致。
- **卡片照 v3**：
  - 目录和直播搜索（`live/index`）：标题 `title`（空时用昵称），昵称 `userNick`，头像 `userImg`，封面 `thumbUrl`（为 null 时 `ivsThumbnail`），分区是分类代码 `category`（如 `ind`），在线 `user`、粉丝 `fanCnt`，人数口径“在线”；公告：成人 → “该直播间需要平台成年验证。”，否则密码房 → “该直播间需要平台房间密码。”，否则 v3 的“PandaTV 远端聊天尚待接入；……”（3.x `zh.json` 的中文）；只收 `isLive` 为真的行，同一页一个主播只出现一次（不分大小写）；
  - 主播搜索（`live/bj_list`）：昵称同时作标题，头像 `thumbUrl`；带 `media` 时按它给标题、封面、分类、粉丝，状态按 `isLive`（真直播中、假未开播、都不是则未知），只有直播中才有在线人数，公告按成人、密码；`blockService` 为真、没有 id 或编号、`media` 不属于这个主播的行跳过（v3 同样跳过）；
  - 图片只接受 `*.pandalive.co.kr` 上的 https 地址（v3 的白名单），其他写空。
- **详情照 v3**：
  - 主播不在播（`member/bj` 没有 `media`）：频道卡片，标题 `channelTitle`（空时昵称）、封面是频道横幅、简介 `channelDesc`、粉丝、未开播；
  - 关注刷新：有 `media` 就是直播中，用它的标题、封面（为 null 时横幅）、分类、在线、粉丝，加上频道简介，公告是 v3 的聊天说明；
  - 进房：`live/play` 接受且在播时用它的 `media`（封面依次 `thumbUrl`、`ivsThumbnail`、横幅）；已下播（`castEnd`，或接受但不在播）是频道卡片、未开播；其他拒绝仍按 `member/bj` 的 `media` 显示直播中，公告按原因：`needAdult` 成人、`needPassword`/`password` 密码、其余（含粉丝专属 `needLogin`）“该直播间存在平台访问条件。”（v3 代码的写法，见问题 1）。
- **画质和线路照 v3**：
  - 读一次主列表（它的令牌只能用一次，REG-PANDALIVE-002），每个变体一个画质：id `<高>p` 加帧率后缀（≥ 50 为 `60`，≥ 25 为 `30`，更低不加），重复的 id 加 `_<序号>`；名称 `<id> · HLS`（如 `1080p30 · HLS`）；排序值高度 × 10⁷ + 码率；按高度、帧率、码率从高到低。样本是 `1080p30`～`160p30` 五档；
  - 每个画质一条线路：变体播放列表地址，请求头是 v3 `PlaybackHeaderResolver` 里 PandaTV 的那一组（UA、`Origin`、`Referer` 房间页；IVS 没有 Origin 一律 403，REG-PANDALIVE-003），格式 HLS，编码取变体的 `CODECS`（样本都是 `avc`），线路编号 `ivs`；
  - **有效期**：变体地址的令牌不透明，实测签发 34 分钟后仍可用、87 分钟后 403，过期后列表不再更新、播放停住。`PlayLease` 在 `live/play` 之后 30 分钟续期，不填到期时间，`cutsConnection` 为真（REG-PANDALIVE-005，采用归档 v4 的值）。v3 没有租期，只在失败后恢复；
  - 服务端不降档，应用的画质就是请求的画质。
- **取流前的检查**：进房的 `PandaLiveRoomData` 带着画质和线路，取画质、取地址都不再请求；不能播放时说明原因：未开播或已下播 `StreamUnavailable`，成人、粉丝专属 `NeedsLogin`，密码房和其他拒绝 `StreamUnavailable`，在播却没有 HLS 主列表、主列表 404 或没有视频变体 `StreamUnavailable`。平台明确未开播、又没有 `data` 的房间直接报，不发请求。恢复时重新进房（v3），同一个画质 id 必须还在，旧地址不复用。
- **弹幕**：v3 没有 PandaTV 聊天（`EmptyDanmaku`，传给弹幕连接的参数为空），所以没有弹幕参数类，`getDanmaku()` 仍是空的。进房时 `live/play` 已经回了聊天频道 `channel` 和令牌 `token`（约 30 分钟），记在 `PandaLiveRoomData.chatChannel`、`chatToken` 里，不多发请求，由 D01 决定（同 E03.6 SHOWROOM 的做法）。
- **链接**（`roomIdFromUrl`，不发请求）：照搬 v3 的 `PandaLiveLink.parse`——http(s)，主机 `pandalive.co.kr`、`www.`、`m.`，默认端口，没有用户信息、片段、空白和控制字符，路径（忽略空段，段名不分大小写）`/live/play/<id>`、`/channel/<id>`、`/channel/<id>/home`，id 照写；另外识别网站现在的直播页 `/play/<id>`（见差异 9）。PandaTV 没有短链。

## 审查发现的 v3 问题

位置简写（都在 `legacy/lib/` 下）：`A` = `core/site/pandalive/pandalive_api.dart`，`S` = `core/site/pandalive/pandalive_site.dart`，`L` = `core/site/pandalive/pandalive_link.dart`，`phr` = `player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 不存在的主播、已下播、成人房都报“格式错误”，处理这些情况的代码从来没有执行过（REG-PANDALIVE-001） | A:197-200、A:259-268；A:380-384、A:406-416 | PandaTV 把拒绝放在 **HTTP 400** 的 JSON 里（`result: false`、`message`、`errorData.code`）；`_defaultRequest` 丢掉非 200 的正文，`_read` 把 400 一律当 `schema`。样本 `S04-member-notfound`、`S05-play-castend`、`S05-play-needlogin` 都是 400 | 400 照常解析 JSON：主播不存在 `NotFound`；`live/play` 的拒绝按 v3 代码原本的写法处理（`castEnd` 显示未开播，其余显示直播中加对应公告），取流时报原因 |
| 2 | 搜索任何形如主播 id、但不是现存主播的关键词（如 `daisy`、`abc`），整个搜索失败 | S:164-171 | 第 1 页先按 id 精确查 `member/bj`，只放过 `missing`；而不存在的主播是 400，按问题 1 成了 `schema`，被重新抛出 | 不存在（`NotFound`）时继续两个原生搜索；其他错误照 v3 抛出 |
| 3 | 粘贴不存在的主播的链接搜索，报错而不是没有结果 | S:153-162 | 同问题 1 | 没有结果 |
| 4 | 一行数据不合预期，整页目录失败 | A:297、A:428-446、A:676-706、A:716-736 | 每行都按详情的严格规则检查：不在播、标题或昵称为空、图片不在白名单、数字不合规、标志不是布尔都报 `schema`，id 不合规报 `identity` | 没有合法 id 或不在播的行跳过；标题空用昵称、昵称空用 id；其他字段取不到留空。只在 v3 失败的地方生效 |
| 5 | 详情里一个字段不合预期（昵称为空、头像不在白名单、人数不是数字），整个房间打不开 | A:549-607、A:676-706 | 同问题 4 | 留空或按 v3 的次序取下一个；主播、编号、`media` 的归属仍严格检查（`ApiChanged`） |
| 6 | 主列表里出现纯音频变体（没有分辨率）时房间打不开 | A:518-520 | 没有 `RESOLUTION` 报 `schema` | 跳过这种变体；一个视频变体都没有才 `StreamUnavailable` |
| 7 | 在播却没有 HLS 主列表（只有 WebRTC `whip`）、主列表没有变体时，房间直接打不开 | A:421-424、A:616-626 | “不能播”当成“详情失败”（`mediaUnavailable` 从 `room` 抛出） | 进房照常返回直播中的房间，取流时报 `StreamUnavailable`；主列表被拒（403）或看不懂仍让进房失败（同 v3） |
| 8 | 没有 `data` 的房间（列表卡片、刷新过的关注）取画质报 `identity`；恢复也要先有进房的快照 | S:244-254、S:271-273 | 只认进房时放进 `data` 的快照 | 先进房再取（3 个请求）；恢复直接重新进房 |
| 9 | 未开播的房间取画质得到空列表，播放器拿不到原因 | S:258 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 10 | 失败都是平台自己的 `PandaLiveException`，播放、录制只能按种类名判断 | A:11-32 | 平台自定义异常 | 类型化错误（见差异 4） |
| 11 | 平台层依赖全局 `HttpClient`，自己实现流式读取（POST 4 MiB、主列表 1 MiB、20 秒）和请求作用域；整个进房（3 个请求）共用一个 20 秒期限 | A:174-246 | 结构问题 | 注入 `LiveHttp`；超时由 live_net 的逐请求超时（20 秒）负责；大小上限在解析前按字符数检查（同 v3 `_read` 的第二道检查） |
| 12 | 媒体请求头按平台写在播放层，每个房间还带着一份没人读的 `httpHeaders`；房间号不合规时 `mediaHeaders` 抛 `FormatException`，播放层没有接住 | phr:192-193；S:87、S:116；A:165-169、L:40-44 | 地址和请求头分开放；`httpHeaders` 是 IPTV 的字段 | 线路自带请求头（值与 v3 相同，由已校验的 id 生成）；房间不再写 `httpHeaders` |
| 13 | 变体地址会过期（34～87 分钟），却没有续期时间，看一个多小时画面停住（REG-PANDALIVE-005） | S:271-281 | 没有租期 | 线路带 `PlayLease`（见“做法”） |
| 14 | 平台层调用界面翻译（分区名、四种公告） | S:52、S:82-86、S:110-115 | `i18n` 写在适配器里 | 用 3.x 的中文作默认文字（`PandaLiveApi.directoryAreaName`、`chatNotice` 等），界面的翻译在 M13 |
| 15 | 调用方传错参数（页码、别的分区、控制字符）报平台错误 | S:60-65、A:345-347、A:349-355、S:211-216 | 本地校验失败用 `schema`、`identity` | `ArgumentError`/`RangeError`，不发请求；不是主播 id 的房间号是 `NotFound`，不发请求 |
| 16 | 路径解不开的链接（如 `%FF`）让 `PandaLiveLink.parse` 抛 `FormatException`，搜索和链接导入直接失败 | L:17 | `pathSegments` 解码失败没有捕获 | 不算链接 |
| 17 | 网站现在的直播页 `https://www.pandalive.co.kr/play/<id>` 不识别，从浏览器复制的链接导入不了 | L:18-27 | 平台改了地址（旧的 `/live/play/<id>` 现在 307 跳到 `/play/<id>`），v3 没跟上 | 识别（差异 9）；房间的 `link` 仍写 v3 的旧地址（跳转可用），改地址列为升级候选 |
| 18 | 主列表属性值恰好是一个 `"` 时，去引号越界抛 `RangeError` | A:649 | 没有检查长度 | 至少两个字符才去引号；正常主列表结果不变 |

另外几处按 v3 保留：

- **关注刷新时，`member/bj` 列出 `media` 就算直播中**，不看它的 `isLive`（A:397-399）。录到的样本里不在播的主播没有 `media`；两者不一致时房间会显示直播中、进房后再按 `live/play` 显示未开播。见升级候选 6。
- **目录卡片的 `userId` 是登录 id，详情和主播搜索结果的是数字编号**（S:70、S:93）。房间身份是 `roomId`，不受影响。
- **按 id 搜索时只返回这一个主播**（S:164-171），不再做原生搜索；第 2 页起才按关键词搜。

## v3 的冻结输出

归档没有 PandaTV 的 `expected.json`（旧版对照工具只做了前五个平台，v3 应用也已经构建不了）。本模块用 `fixtures/pandalive/legacy_expected.dart` 生成，做法同 CHZZK、LiveMe：

- 把 v3 的 `PandaLiveApi`、`PandaLiveLink`、`PandaLiveSite`（`legacy/lib/core/site/pandalive/` 三个文件）原样搬进一个 Dart 程序。v3 本来就把传输做成可注入的函数（`PandaLiveRequest`），所以只换了它：按方法、主机、路径、查询参数（不比已脱敏的 IVS `token`）和表单字段（不比 `info`：样本按 `info=media` 录制，v3 发 `media fanGrade`，回答只多一个 v3 不读的 `fanGrade` 列表）读样本；状态码不是 200 时正文为空（同 v3 的 `_defaultRequest`）；没有样本的请求抛 StateError，v3 的 `_scope` 会把它变成 `transport`，所以另外记下、在调用结束后重新抛出，缺样本会让生成失败；
- 网络路径上的 `_defaultRequest`、`readBody` 没有搬；Dio 的 `CancelToken` 只留 v3 用到的成员，v3 的 `withRequestCancellation` 原样搬入；`PandaLiveSite` 保留方法体，去掉 `extends`/`implements`、`@override` 和 `getDanmaku`，构造函数改为必须注入 API；`i18n` 返回 3.x `zh.json` 的文字；v3 的模型只搬用到的部分；输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记下发出的请求（方法、地址、表单、Referer，主列表不带 `token`）；
- 已下播和成人两个样本录制时没有录 `member/bj`：脚本用 `S04-member-live` 换上该主播的 id 和编号（成人的再把 `isAdult` 设为真）作回答，站点测试也这样做；
- 搜索样本是按每个来源 20 条录的，v3 会核对回答的 `page.limit` 与请求一致，所以按每页 40 条调用（v3 的拆法正好是 20 + 20）；
- 在仓库根目录运行：`dart run fixtures/pandalive/legacy_expected.dart`，只用 Dart SDK。连续运行两次，输出逐字节相同。

10 个样本有 `expected.json`：

- `S01-index-hot`：固定目录、目录说明键、平台名、目录第 1 页、推荐、分区房间，第 0 页和别的分区（都不发请求，报错），列表卡片取画质（v3 报 `identity`）；`S01-index-hot-last`：第 5 页；
- `S03-search-live`：直播搜索（v3 API 层 + 站点的卡片）和整个搜索（每页 40 条，两个请求）；`S03-search-bj`：主播搜索；
- `S04-member-live`（配 `S05-play-live`、`S06-master`）：进房、刷新、录制、开播状态、画质、每档地址、`resolvePlayUrlsRaw`、恢复，按 id、房间链接、频道主页和 `/play/` 链接搜索，24 个链接向量的 `PandaLiveLink.parse`、`parseOrId`、`url`、`mediaHeaders`；
- `S04-member-offline`：同上的房间入口和按 id、频道链接搜索；`S04-member-notfound`：房间入口和两种搜索（v3 全是 `schema`）；
- `S05-play-castend`、`S05-play-needlogin`：进房、录制详情（v3 都是 `schema`）和单独的 `live/play` 请求；
- `S06-master`：v3 `parseManifest` 的结果和站点给出的画质。

`S02-index-newbj` 和弹幕帧 v3 不请求，没有期望值。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序和每档地址；请求比较方法、地址、表单（含字段顺序）、Referer 和次数。所有房间只有 `httpHeaders` 一个键不同（差异 7）。

| 样本 | 结果 |
|---|---|
| S01 目录（第 1 页 30 个，第 5 页 8 个） | 房间、顺序、各字段一致；是否还有下一页一致；表单一致；推荐和分区房间给出同样的列表。第 0 页、别的分区 v3 报 `schema`/`identity`，现在是 `RangeError`/`ArgumentError`，都不发请求；列表卡片取画质 v3 报 `identity`，现在先进房 |
| S03 搜索（`데이지`） | 直播 2 个、主播 4 个逐键一致（主播的 `userId` 是数字编号，3 个未开播）；整个搜索 5 个房间、顺序（直播在前、`daisy00` 只出现一次）一致；两个请求的地址、表单、Referer、先后一致 |
| S04 在播（+S05、S06） | 进房、录制 3 个请求，刷新、开播状态 1 个，逐项与 v3 相同；房间逐键一致（进房在线 47 取自 `live/play`，刷新 50 取自 `member/bj`）；五档画质的名称、id、排序和地址逐字一致，`resolvePlayUrlsRaw` 不发请求、应用的画质一致；恢复 3 个请求、地址一致；按 id、`/live/play/` 和频道主页链接搜索各 1 个请求、结果一致；`/play/` 链接 v3 没有结果，现在找到这个主播（差异 9） |
| S04 未开播 | 进房、刷新、录制各 1 个请求，频道卡片（标题“데이지ෆ님의 방송국”、没有横幅、简介、粉丝 9）逐键一致；开播状态 false；v3 取画质得到空列表，现在 `StreamUnavailable`（不发请求） |
| S04 不存在（400） | v3 进房、刷新、开播状态、按 id 和链接搜索都报 `schema`；现在详情是 `NotFound`，链接搜索没有结果，按 id 搜索继续做原生搜索（问题 1～3） |
| S05 已下播、成人（400） | v3 进房和录制都报 `schema`（2 个请求）；现在已下播显示频道卡片、未开播，成人显示直播中和成人公告，取流时分别报 `StreamUnavailable`、`NeedsLogin`，都是 2 个请求 |
| S06 主列表 | 五档（1080p30、720p30、480p30、360p30、160p30）的名称、id、排序、变体地址逐字一致 |
| 链接 | 24 个向量中 22 个与 v3 相同；`/play/<id>`（`www.` 和 `m.`）v3 不识别，现在识别 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | HTTP 400 的回答照常解析：主播不存在 `NotFound`；`live/play` 已下播显示未开播，成人、密码、其他限制显示直播中和对应公告 | 问题 1。显示的状态和公告就是 v3 代码为这些情况写好的，只是从来没有走到；用户以前看到的是加载失败 |
| 2 | 按 id 搜索找不到主播时继续原生搜索；链接指向不存在的主播时没有结果 | 问题 2、3。只在 v3 失败的地方生效 |
| 3 | 列表里不合规的行跳过或留空，详情里不合规的字段留空，不让整页、整个房间失败 | 问题 4、5。录到的页面和房间结果相同 |
| 4 | 出错抛类型化错误：401/403 `RiskControl`，404 `NotFound`（主列表 404 是 `StreamUnavailable`），429 `RateLimited`，5xx、其他状态（含跳转）和传输失败 `NetworkFailure`，看不懂的回答、没有代码的拒绝、主播或 `media` 对不上 `ApiChanged`；取消原样抛出；调用方的参数错误 `ArgumentError`/`RangeError`，不是主播 id 的房间号 `NotFound`，同 v3 不发请求 | 问题 10、15。界面看到的仍是加载失败 |
| 5 | 不能播放的房间照常进入，取流时说明原因（未开播、已下播、没有 HLS、没有视频变体 `StreamUnavailable`，成人、粉丝专属 `NeedsLogin`，密码房 `StreamUnavailable`）；纯音频变体跳过 | 问题 6、7、9。状态和公告不变 |
| 6 | 没有 `data` 的房间取流前先进房；恢复直接重新进房 | 问题 8。正常进房流程不受影响，请求数与 v3 进房相同 |
| 7 | 房间不写 `httpHeaders`；线路自带请求头、格式、编码、线路编号和有效期 | 问题 12、13。请求头的值与 `PlaybackHeaderResolver` 的 PandaTV 分支逐项相同；3.x 存下的旧值照读、`mergeFrom` 照留 |
| 8 | 进房时记下 `live/play` 的聊天频道和令牌（`PandaLiveRoomData`） | 给 D01 用，不发请求；`getDanmaku()` 仍是空的 |
| 9 | 识别 `https://www.pandalive.co.kr/play/<id>`（和 `m.`）；路径解不开的文字不算链接 | 问题 16、17。这是网站现在的直播页地址，v3 的旧地址会跳到这里；不改变任何原来能识别的链接 |
| 10 | 进房不再有 20 秒的总期限，由每个请求各自的 20 秒超时代替；响应在解析前按字符数查 4 MiB（主列表 1 MiB）；非法 UTF-8 变成替换字符而不是报错 | 问题 11；同 E03.7 等模块 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **目录只有一个固定分区“公开直播”**。归档 v4 另有“新人主播”（`onlyNewBj=Y`，样本 `S02-index-newbj` 已复制），会改变发现页，列为升级候选 1。
- **画质名称照 v3**：`1080p30 · HLS`，30 帧也带后缀，重复的 id 加 `_<序号>`。归档 v4 写 `1080p`，并把源画质（`VIDEO="chunked"`）标“原画”，画质菜单会变，列为升级候选 5。
- **进房时就调用 `live/play` 并读主列表**（3 个请求），主列表被拒则进房失败：归档 v4 只查 `member/bj`，取流时再调用。
- **主列表请求带 v3 的整组 API 请求头**（含 `Accept: application/json`、`Accept-Language`），线路只带媒体请求头。
- **媒体 `Referer` 是房间页 `/live/play/<id>`**（v3 `mediaHeaders`、上游 TV 相同）；归档 v4 用站点根。两者都带 `Origin`，都能播。
- **`member/bj` 照 v3 要 `info=media fanGrade`**：归档 v4 只要 `media`。粉丝等级从来不读，列为升级候选 9。
- **搜索照 v3**：按 id 精确查找、每页按调用方的条数拆成直播 ⌈n/2⌉ 和主播其余（归档 v4 固定各 20 条、之后的页只翻主播）、先主播后直播依次请求、超过 100 字没有结果（归档 v4 截断后搜索）、短于 2 字没有结果。
- **房间号保持请求时的写法**，不改大小写。
- **没有累计观看数**：归档 v4 把 `playCnt` 写成累计，但 3.x 的人数能力表（`audience.dart`）写的是 PandaTV 没有累计，v3 的公告也说明 `playCnt` 不作为人数，列为升级候选 3。
- **分区是平台的分类代码**（`ind`、`game`），没有名称接口，照 v3 原样显示。
- **标题不做 HTML 实体解码**，同 v3 和归档 v4。
- **图片只接受 `*.pandalive.co.kr` 的 https 地址**（v3 和上游 TV 的白名单；归档 v4 的 `endsWith('pandalive.co.kr')` 少了点号，上游笔记记为风险）。
- **成人、粉丝专属房仍显示直播中**，取流时才说明：同 v3 代码和归档 v4。
- 显示名仍是“PandaTV”，目录说明键仍是 `pandalive_directory_scope`，公告是 3.x 的中文原文。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复；它把在线、粉丝、累计缺值写空串，这里同样写空串（`mergeFrom` 因此保留存下的值）。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 增加“新人主播”分区（`live/index` 加 `onlyNewBj=Y`） | 只有“公开直播” | 归档 v4 规格 §2.1、§2.2；样本 `S02-index-newbj`。会改变发现页 |
| 2 | PandaTV 弹幕（匿名只读，Centrifugo） | 没有弹幕 | 归档 v4 规格 §7：`wss://chat-ws.neolive.kr/connection/websocket`，用 `live/play` 的 `token` 连接、订阅 `channel`，25 秒心跳；弹幕帧样本 `danmaku/S07-live`。进房已经记下频道和令牌，由 D01 决定 |
| 3 | 显示累计观看（`playCnt`） | 不显示 | 归档 v4；需要同时改人数能力表和公告 |
| 4 | 房间的 `link` 和外部打开改成 `/play/<id>` | `/live/play/<id>`（307 跳转） | 归档 v4 规格 §1 |
| 5 | 源画质标“原画”，画质 id 去掉 `30` 后缀 | `1080p30 · HLS` | 归档 v4 规格 §5。会改变画质菜单和存下的画质偏好 |
| 6 | 关注刷新以 `media.isLive` 为准，为假时显示未开播 | 有 `media` 就是直播中 | 归档 v4；问题清单后的第一条 |
| 7 | 公告改成用户能看懂的说明（现在是“远端聊天尚待接入；user 字段按……”这类开发说明） | 3.x 原文 | M13 翻译时一并考虑 |
| 8 | 分类代码显示成名称 | 显示 `ind` 等代码 | 平台没有名称接口（归档规格 §12 第 4 条） |
| 9 | `member/bj` 只要 `media` | 另要从不读的 `fanGrade` | 归档 v4 |
| 10 | 卡片和详情的 `userId` 统一 | 卡片是登录 id，详情是数字编号 | v3 两处写法不同 |
| 11 | 按 id 搜索时也给出原生搜索的结果 | 存在就只给这一个主播 | 归档 v4 不做精确查找（`bj_list` 本来就按 id 匹配） |
| 12 | 显示开播时间（`startTime`，韩国时间，REG-PANDALIVE-004） | 不显示 | 归档 v4；`LiveRoom` 没有开播时间字段 |

## 回归条目的覆盖

归档规格有 5 条，除 004 外都属于平台层，都有测试：

- 001（400 一律当格式错误）：400 照常解析；不存在的主播 `NotFound`，`castEnd`、`needAdult` 等按代码处理，按 id 搜索不再失败。样本 `S04-member-notfound`、`S05-play-castend`、`S05-play-needlogin` 和合成回答都有测试。
- 002（主列表只能读一次）：进房读一次主列表，交出变体地址；取画质、取地址不再请求；恢复重新调用 `live/play` 拿新主列表，从不重读旧的；主列表 403 是 `RiskControl`。
- 003（媒体请求没有 Origin 时 403）：每条线路都带 `Origin`，与 v3 的媒体请求头相同。
- 004（开播时间差 9 小时）：不适用。v3 不显示开播时间，`LiveRoom` 也没有这个字段；列为升级候选 12。
- 005（看一个多小时画面停住）：线路带 30 分钟的租期，`cutsConnection` 为真。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕：`getDanmaku()`、`PandaLiveRoomData.chatChannel`/`chatToken`、弹幕帧样本 `danmaku/S07-live` | D01（升级候选 2） |
| 分区名、目录说明（`pandalive_directory_scope`）、四种公告、平台名的繁体和英文 | M13 多语言。本模块给出 3.x 的中文（`PandaLiveApi.directoryAreaName`、`directoryScope`、`chatNotice`、`adultNotice`、`passwordNotice`、`restrictedNotice`） |
| 目录说明常驻（`LiveDirectoryNotice`） | M13 热门页、分区页 |
| 搜索能力表：含未开播、可翻页、没有网页搜索（3.x `modules/search/search_capability.dart:74-78`） | M13 搜索页 |
| 外部打开 `https://www.pandalive.co.kr/live/play/<id>`（3.x `modules/live_play/services/room_external_opener.dart:121-126`） | M13；地址由 `PandaLiveApi.roomUrl` 和房间的 `link` 提供 |
| 本地互动包（3.x `local_interaction_controller.dart:449-456`） | M13 |
| 平台注册和图标（3.x `core/sites.dart:194`、`247`、`361-365`） | I01.1 应用骨架；平台 id 已在 M3 的 `SiteIds.pandaLive` |
| 平台列表升级时追加 PandaTV（`favorite_room_controller.dart:79`，`siteCatalogMigration` 第 23 版；3.x `test/pandalive_catalog_migration_test.dart`） | J02.1 |
| 播放和录制按线路的请求头、有效期打开（3.x `playback_header_resolver.dart:192-193`）；变体地址的准确有效期（归档规格 §12 待确认 1） | G、H01.1 |
| 录制平台契约（3.x `test/recording_platform_contract_test.dart:35`） | H01.1 |
| 人数能力（`user` 是在线，没有累计） | 已在 E05.1 的 `audience.dart` |
| 3.x 的链接工具和网页搜索解析里的 PandaTV 分支（`live_url_tool.dart:119`、`243-244`，`web_search_room_parser.dart:104-105`） | 已由本模块的 `LiveSiteLinks` 加 M3 的 `LinkParser` 代替 |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出。主列表用本平台自己的解析（移植 v3 的 `parseManifest`；共享的 `HlsMasterPlaylist` 不接受 IVS 主列表里的 `TYPE=VIDEO` 条目），链接用 M3 的 `LiveSiteLinks`、`LinkParser`，JSON 读取用 `json.dart`。

## 测试

82 个用例，`live_core` 共 2197 个，全部通过：

- `pandalive_api_test.dart`（43 个）：逐个样本对照 v3 的输出（固定目录、目录两页、两种搜索、三种 `member/bj`、三种 `live/play`、主列表），有意的差异逐条断言（`httpHeaders`、400 的处理、`/play/` 链接）；v3 测试里解析部分的移植（目录卡片、主播搜索的跳过规则、身份核对、看起来像 IVS 的假主机）；不合规的行和字段；拒绝的代码、公告和取流原因；主列表的命名、排序、重复 id、纯音频、相对地址、编码和 v3 拒绝的形状；线路的请求头、格式、编码、线路编号、租期；状态码映射；图片白名单；链接规则（24 个 v3 向量）；REG-PANDALIVE-001～003、005。
- `pandalive_site_test.dart`（39 个），用样本回放加合成回答：
  - 平台名、目录说明、能力、固定目录不请求、没有弹幕；
  - 目录：请求地址、表单和字段顺序、请求头、不跟随跳转、第 5 页的 offset、推荐和分区房间、调用方错误不请求；
  - 搜索：两个来源的先后、表单、Referer 与 v3 一致，结果与 v3 一致；每页条数的拆法和各自的 offset、一次只发一个请求；合并和去重；一个来源失败、两个都失败、没有结果又有失败；链接搜索（第 2 页不请求、`/play/`、不存在的主播）；按 id 搜索（在播、未开播、不存在时继续搜、其他失败照抛）；不发请求的空结果和调用方错误；取消（请求前、两个来源之间）；
  - 房间：进房和录制的 3 个请求（方法、地址、表单、Referer、主列表的请求头和令牌）与 v3 相同，刷新和开播状态 1 个请求，未开播、不存在、非法房间号不请求；已下播、成人（合成的 `member/bj` + 录制的 400）；主列表 403、看不懂、404、没有视频，没有 HLS；其他拒绝的公告和原因；刷新合并进 3.x 存下的关注；
  - 取流：进房得到的房间不再请求，每档地址和 `resolvePlayUrlsRaw` 与 v3 一致，线路属性；卡片先进房；恢复 3 个请求、地址一致；恢复时画质没了；大小写不同的同一个主播、别的主播的数据、别的平台；
  - 错误映射（传输失败、取消、各状态码、没有代码的拒绝）；
  - 链接（经 `LinkParser`）：分享文本里的直播页、频道主页、`/play/`，其他页面和主机不识别，没有短链，不发请求。

## 升级落地（T02.U）

- 日期：2026-09-29（E03.12）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 12 行（25-1～25-12）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。“落地方式”只有 25-9、25-10（开发预填）和 25-12（模型部分已完成）写了，其余按上面“后续升级候选”的原文做。25-2（弹幕）的连接属于 D01，这里只给出它要的参数。
- 改了的文件：本平台的 `pandalive_api.dart`（解析）、`pandalive_site.dart`（请求编排）和两份测试；通用文件只动了 `audience.dart` 里 PandaTV 自己那一行（`hasTotalViewers` 由 false 改为 true，25-3 的原文就要求“同时改人数能力表”），没有加通用能力，没有新依赖，没有新样本。
- 实测：2026-09-28 19:20～20:05 UTC，直连、匿名、用适配器的请求头，只读：人气目录翻到底（5 页 132 场）、新人主播、`member/bj`、按 id 和昵称的两种搜索、一个密码房的 `member/bj` 和 `live/play`，官网 PC 版和移动版的页面脚本（找分类名称）、`/v1/config/preset`、`/v1/page/www`；最后用新适配器实际走了一遍（分类、两个目录、按 id 和关键词搜索、刷新、进房、取画质、用 v3 的画质 id 取地址并读到变体列表、密码房进房）。下面的结论都来自这些回答和已有样本。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 25-1 新人主播 | 分类里在“公开直播”（`public`，v3）后面加一个分区“新人主播”（`newbj`，`PandaLiveApi.newBroadcasterAreaId`、`newBroadcasterAreaName`）：`live/index` 的表单多一个 `onlyNewBj=Y`（字段顺序与官网和样本 `S02-index-newbj` 相同），其余（每页 30、按人气、Referer `/live`、解析）与公开直播一样。`checkArea` 返回分区 id，认这两个分区；v3 存下的“公开直播”照常可用。推荐仍是公开直播 | 分类页多一个“新人主播”，列出平台标为新人的主播（样本 7 场，实测 4 场） | 平台层完成，余下 M13（分区名的多语言） |
| 25-2 弹幕 | 平台层只给参数：新类 `PandaLiveDanmakuArgs(userId, channel, token)`，进房、录制详情在 `live/play` 接受且在播时放进 `danmakuData`：`channel` 是回答的 `channel`（不是数字时用主播编号），`token` 是它的聊天令牌（约 30 分钟），`userId` 用来重新调用 `live/play` 取新令牌。不多发请求。聊天服务器地址 `PandaLiveApi.chatServer`（`wss://chat-ws.neolive.kr/connection/websocket`，官网配置的 `newChat.node`）。被拒绝（成人、密码、粉丝专属、已下播）的没有参数（拿不到令牌）；在播但没有 HLS 的照给（聊天不依赖视频）。关注刷新不给。E03.12 放在 `PandaLiveRoomData` 里的 `chatChannel`、`chatToken` 移到这里。`getDanmaku()` 仍是空的弹幕源 | 看不出变化；弹幕在 D01 接入 | 平台层完成，余下 D01 |
| 25-3 累计观看 | 在播的房间带 `totalViewers` = `playCnt`（这一场的进入次数，直播中就有，实测 132 场都大于 0）：目录、新人主播、直播搜索的卡片，主播搜索里在播的行，刷新、进房、录制。未开播不带。`audience.dart` 的 PandaTV 一行改为有累计 | 默认的人数显示（热度模式）下，卡片显示累计观看（标“累计”）；“真实在线”模式显示在线人数。房间公告说明了两个数字的意思（25-7） | 平台层完成，余下 M13 |
| 25-4 `/play/` 链接 | `PandaLiveApi.roomUrl` 改为 `https://www.pandalive.co.kr/play/<id>`：房间的 `link`、外部打开的地址，以及所有代表房间页的 Referer（`member/bj`、`live/play`、主列表、线路的媒体请求头；录样本时官网发的就是它）。旧的 `/live/play/<id>` 链接照常识别 | 分享、外部打开的链接是官网现在的地址，不再经过一次跳转 | 平台层完成，余下 M13（外部打开） |
| 25-5 画质 | 画质 id 去掉 `30`：`<高>p`，50 帧以上仍加 `60`（`1080p60`），重复的仍加 `_<序号>`；源画质（主列表里 `VIDEO="chunked"` 的变体）名称为“原画”，其余名称就是 id（`720p`，去掉 ` · HLS`）；源画质排第一，`sort` 加 `PandaLiveApi.sourceRank`。取地址、恢复也认 v3 的 id（`PandaLiveApi.qualityIdFromLegacy`，确认的画质报新 id）。对照表见下 | 画质菜单从“1080p30 · HLS、720p30 · HLS……”变成“原画、720p、480p……”（实测一场 60 帧的是“原画、720p60、480p、360p、160p”）。默认偏好“原画”能直接对上源画质 | 平台层完成，余下 J02.1 |
| 25-6 以“是否在播”为准 | `member/bj` 的 `media.isLive` 为假时房间是未开播（`PandaLiveApi.listedLive`）：关注刷新、`getLiveStatus`、按 id 和链接搜索都是频道卡片；进房也不再调用 `live/play`（1 个请求，E03.12 要 2 个，结果相同：`live/play` 会回 `castEnd` 或“已接受但未在播”）。`isLive` 为真或不是开关值时照旧当作在播 | 主播刚下播时关注页不再显示“直播中” | 完成（T02.U） |
| 25-7 公告 | 四种公告和目录说明改成用户看得懂的话（文字键不变，M13 按平台翻译）：<br>- 普通房间 `chatNotice`：v3“PandaTV 远端聊天尚待接入；user 字段按平台当前在线人数展示，playCnt 不作为并发人数。”→“这里暂时看不到 PandaTV 直播间的聊天。人数分别是正在观看和本场累计观看。”<br>- 成人 `adultNotice`：“该直播间需要平台成年验证。”→“成人直播需要登录 PandaTV 并通过本人认证，本应用暂时无法播放。”<br>- 密码 `passwordNotice`：“该直播间需要平台房间密码。”→“这个直播间设了密码，本应用暂时无法播放。”<br>- 其他限制 `restrictedNotice`：“该直播间存在平台访问条件。”→“这个直播间有观看限制（例如需要登录），本应用暂时无法播放。”<br>- 新增粉丝专属 `fansNotice`：“这个直播间只对粉丝开放，本应用暂时无法播放。”<br>- 目录说明 `directoryScope`：“公开直播是 PandaTV 官网正在直播的公开房间，按人气排序；新人主播是平台标出的新主播。搜索会同时查找直播标题和主播，未开播的主播也会列出；也可以输入主播 ID，或粘贴 PandaTV 的直播间、频道链接。”<br>公告按受限类型选（`PandaLiveApi.noticeOf`）：成人、密码、粉丝专属、其他限制，没有限制或看不出来用普通公告 | 房间公告、目录说明是看得懂的话（M13 显示和翻译） | 平台层完成，余下 M13 |
| 25-8 分类名称 | 平台没有名称接口，官网 PC 版、移动版的页面和脚本里也没有分类名（实测，见“受阻和存疑”），所以按代码本身的意思在本平台放一张表 `PandaLiveApi.areaNames`：`ind` 个人直播、`talk` 聊天、`music` 音乐、`game` 游戏、`sports` 体育、`etc` 其他（录到和实测的全部代码）；不认识的代码照原样显示（v3）。卡片、搜索、详情的 `area` 都用名称（`areaNameOf`） | 卡片上的分区从 `ind`、`game` 变成“个人直播”“游戏”（近九成的直播是 `ind`） | 平台层完成，余下 M13（分类名的多语言） |
| 25-9 少要一个字段 | `member/bj` 的表单改为 `userId&info=media`（v3 还要从不读的 `fanGrade`）。样本本来就是这样录的，站点测试不再忽略 `info` | 看不出变化 | 完成（T02.U） |
| 25-10 主播编号统一 | 目录、新人主播、直播搜索卡片的 `userId` 改为主播编号 `userIdx`（v3 写登录 id），与详情、主播搜索相同；没有编号的行写空。房间身份（`roomId`）不变 | 看不出变化；关注刷新前后 `userId` 不再在登录 id 和编号之间来回变 | 完成（T02.U） |
| 25-11 按 id 搜索也给关键词结果 | 第 1 页的关键词是合法的主播 id 时，照常做两个原生搜索（主播搜索按 id 前缀匹配、不分大小写，实测 `daisy` 列出 4 个 `daisy…`，`DAISY00` 找到 `daisy00`），再把这个主播挪到第一个；两个搜索都没列出它时才在它们之后查 `member/bj`（找到就放第一个，不存在就不加，其他失败只在没有任何结果时报出）。v3 先查 `member/bj`、存在就只返回它 | 输入主播 id 时，除了这个主播，还能看到 id 相近的主播和相关直播；这个主播仍排第一 | 完成（T02.U） |
| 25-12 开播时间 | `startTime`（`2026-09-28 02:00:35`，韩国时间、不带时区）换成 UTC 填进 `startedAt`（`PandaLiveApi.koreanTime`）：目录、新人主播、直播搜索的卡片，主播搜索里在播的行，刷新、进房、录制。`0000-00-00 00:00:00`、格式不对、不存在的日期、2000 年以前的不填；未开播不填。时区的依据：实测时（19:27 UTC）最新的开播时间“2026-09-29 04:25:10”按韩国时间是 2 分钟前，按 UTC 会是 9 小时后；样本 S01 最新一场按韩国时间在录制前一小时内（REG-PANDALIVE-004） | 在播的房间能显示开播多久（M13 只在直播中显示） | 平台层完成，余下 M13 |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 25-12 |
| 受限类型 | 平台在直播对象上标了 `isAdult`、`isPw`、`type`（`free`/`fan`），所以所有带直播对象的地方都填（`PandaLiveApi.restrictionOf`）：成人 → `adult`，否则密码 → `password`，否则 `type` 为 `fan` → `subscribersOnly`，`free` → `none`，`type` 缺失或不认识 → 不填（看不出来）。目录和搜索的卡片、主播搜索里在播的行、关注刷新（`member/bj` 带这些标记，所以刷新也填）都按标记。进房：`live/play` 接受且在播 → `none`；在播但没有 HLS、主列表 404 或没有视频变体 → `unplayable`；拒绝时按代码（`needAdult` → `adult`，`needPassword`/`password` → `password`），代码说不清时按 `member/bj` 的标记，再不行 `needLogin` → `needsLogin`、其他代码 → `unplayable`（`refusalRestriction`）。实测：匿名看密码房（`isPw` 为真）时 `live/play` 回的是 `needLogin`（“로그인이 필요한 방송입니다”），所以按标记标成 `password`。未开播、已下播不填 |
| 受限的直播改为直播中 | E03.12 已是：成人、密码、粉丝专属和其他拒绝都显示直播中。取流的错误改为按受限类型报（E05.2 的表，`restrictionError`）：成人、需要登录 `NeedsLogin`；密码、粉丝专属、其他 `StreamUnavailable`（说明里带代码和受限类型，如 `live/play: needLogin (password)`）。与 E03.12 的不同：回 `needLogin` 的密码房、粉丝专属房由 `NeedsLogin` 改为 `StreamUnavailable`（本应用没有 PandaTV 登录，登录了也看不了） |
| 回放、“不可播放” | 在播却给不出地址的标 `unplayable`（见上）。PandaTV 没有回放地址 |
| 重播 | 录像重播标为回放（`replay`），同 Twitch 的 rerun（8-9）：直播对象的 `onAirType` 或 `liveType` 为 `rec` 时（`PandaLiveApi.isRerun`），目录、新人主播、直播搜索的卡片，主播搜索里在播的行，关注刷新、进房、录制详情（接受或被拒绝）都是回放，其余字段（人数、开播时间、受限类型、公告）与直播相同。依据：统一原则“回放、轮播、重播”，主会话 2026-09-29 按用户授权决定；实测 2026-09-28 人气目录 132 场里 9 场是 `rec`，标题都以“[녹]”（녹화，录像）开头，两个字段总是一起出现；样本 S01 第 1 页 30 场里 5 场、S02 7 场里 2 场。重播有流，取流和直播完全一样（`live/play` + 主列表），`isPlayableNow` 为真，关注分组在回放组；`getLiveStatus` 为假（回放不是直播，E05.2）。v3 显示为直播中 |
| 占位信息 | 适配器没有占位文字。E03.12 在昵称为空时用登录 id 顶替（“昵称空用 id”），这正是统一原则说的替身，改为留空（界面显示平台名，`displayNick`）；标题为空时仍用昵称（v3 的规则，真实数据）。这只影响 v3 本来报错的行。官网默认的频道标题“〈昵称〉님의 방송국”和直播标题“〈昵称〉님의 방송입니다”是平台给主播的真实标题（官网就这样显示，含主播名），保留 |
| 画质命名 | 25-5 |
| 默认编码 | 不涉及：实测和样本都只有 H.264（`avc1`），线路标了 `avc` |
| 房间身份 | 不变：登录 id，已在 `SiteIds.caseInsensitiveRoomIds`（E05.2） |
| 按主播关注 | 不涉及：房间本来就是主播 |
| 容错 | 列表、详情的坏行、坏字段 E03.12 已经只跳过或留空。这次补上：`live/play` 的 `PlayList` 里不是列表、不是对象、不是 IVS 地址的项只跳过自己，取下一个（v3 整个进房失败），全都不能用才 `ApiChanged`；主列表里没有地址、帧率或码率越界、地址不是 IVS 的变体只少这一档（v3 整个房间打不开），一档都不剩时，有坏变体是 `ApiChanged`，否则 `StreamUnavailable` |
| 翻页 | 不涉及快照：目录和两个搜索都是平台原生的 offset 分页，每页一个请求；跨页去重留给 M13 的列表（按房间身份），同 CHZZK |
| 弹幕 | 25-2 |
| 说明文字 | 25-7 |

### 请求数

| 场景 | E03.12 | 现在 | 原因 |
|---|---|---|---|
| 分类 | 0 | 0 | — |
| 公开直播、新人主播、推荐的一页 | 1 | 1 | 25-1 |
| 关键词搜索（不是主播 id，或第 2 页起） | 2（每页只有 1 条时 1） | 不变 | — |
| 按主播 id 搜索第 1 页 | 存在 1，不存在 3 | 搜索列出了它 2，没列出 3 | 25-11 本身要多给结果；主播搜索按 id 匹配，一般是 2 |
| 房间链接搜索 | 1 | 1 | — |
| 关注刷新、`getLiveStatus` | 1 | 1 | — |
| 进房、录制详情 | 在播 3，拒绝 2，未开播 1 | 不变；`media` 说不在播的 1（E03.12 是 2） | 25-6 |
| 取流：带进房数据的房间 | 0 | 0 | — |
| 取流：没有进房数据的卡片 | 3；明确未开播 0 | 不变 | — |
| 恢复取流 | 3 | 3 | — |

关注刷新和列表没有多请求；只有按 id 搜索第 1 页多了请求，是 25-11 本身的要求。

### 画质 id 对照（给 J02.1）

| v3 的 id（v3 的名字） | 新 id（新名字） | 说明 |
|---|---|---|
| `<高>p30`（`<高>p30 · HLS`），如 `1080p30`、`720p30` | `<高>p`（源画质叫“原画”，其余叫 `<高>p`） | 25～49 帧不再加 `30` |
| `<高>p30_<n>` | `<高>p_<n>` | 同一主列表里重复的档，序号规则不变 |
| `<高>p60`、`<高>p60_<n>` | 不变 | 50 帧以上仍加 `60` |
| `<高>p`（25 帧以下） | 不变 | 现在同一高度的 30 帧档也叫 `<高>p`，两档并存时后出现的那档变成 `<高>p_<n>`（没见过这种主列表） |
| 其他 | 不变 | — |

- 代码：`PandaLiveApi.qualityIdFromLegacy(id)`（去掉首尾空白，`^<高>p30(_<n>)?$` 去掉 `30`，其余原样返回；可以重复套用）。规则式，没有常量表：id 由主列表的分辨率生成，不是固定的几个。
- 适配器取地址、恢复时也认旧 id（确认的画质报新 id），漏迁的也能播。
- v3 的全局画质偏好按名字存（原画、蓝光8M、蓝光4M、超清、流畅），不是本平台的 id。v3 对 PandaTV 从来对不上名字（`1080p30 · HLS`），按比例选档；现在默认的“原画”能直接对上源画质，其余档仍按比例选。没有要改名迁移的全局偏好；这张表给 v4 按房间存下的画质用。

### 设置项

无。本平台的 12 行都不需要开关。

### 身份迁移规则（给 J02.1）

- 房间身份不变（主播登录 id，比较不分大小写），不需要迁移；25-10 改的是 `userId` 字段，不是身份。
- 3.x 存下的 `link` 是 `/live/play/<id>`：刷新合并时由新的 `/play/<id>` 覆盖；不刷新也能用（官网 307 跳转）。J02.1 可以顺手按 `PandaLiveApi.roomUrl` 改写，不是必需。
- 分区：3.x 存下的只可能是 `{platform: pandalive, areaType: directory, areaId: public}`，照常可用，不需要迁移；新分区 `newbj` 同样是 `directory` 类型。
- 3.x 存下的房间 `area` 是分类代码（`ind`），刷新后变成名称（个人直播）；不刷新时界面可以用 `PandaLiveApi.areaNameOf` 显示名称，存储不需要改。

### 与 v3 冻结输出的新差异

样本对照测试里用 `changed:` 列出，原因写条目编号；3.x 从来没写过的 `startedAt`、`restriction`、`totalViewers` 由 `_expectParity` 的 `added` 逐个断言；`expected.json` 没有改：

- 所有房间：`link`（25-4）、`notice`（25-7），以及 E03.12 起就有的 `httpHeaders`。
- 在播的房间（S01 两页、S03 直播搜索、S03 主播搜索的在播行、S04 刷新、S04+S05 进房和录制）：`area`（25-8）；`startedAt`（25-12）、`totalViewers`（25-3）、`restriction`（`none`）。
- `live/index` 的卡片（S01、S03 直播搜索）：`userId`（25-10）。
- 重播的卡片（S01 第 1 页 5 张）：`liveStatus`、`isRecord`、`status`（回放，统一原则“回放、轮播、重播”）。
- 未开播的房间（S04 频道、S03 主播搜索的未开播行）：只有 `link`、`notice`。
- 画质（S06）：名称和 id（25-5），源画质的 `sort` 加 `sourceRank`；变体、顺序和地址与 v3 相同，v3 的 id 经 `qualityIdFromLegacy` 正好是新 id。
- 请求：`member/bj` 的表单（25-9）、所有房间页 Referer（25-4）；站点测试把 v3 的请求按这两条改写后逐项比较，其余（方法、地址、表单字段和顺序、次数）与 v3 相同。按 id 搜索的请求（25-11）、`media` 说不在播时的进房（25-6）另有测试。
- 分类：v3 的分区逐字段相同，后面多一个新人主播（25-1）。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 | 弹幕（25-2）：用 `PandaLiveDanmakuArgs` 连接 `PandaLiveApi.chatServer`（握手带 `Origin: https://www.pandalive.co.kr` 和 UA）。`token` 是进房时 `live/play` 给的（约 30 分钟），过期或重连时用 `userId` 重新 POST `live/play`（`PandaLiveApi.playForm`，Referer `PandaLiveApi.roomUrl`）取新的 `token` 和 `channel`；被拒绝（成人、密码、粉丝专属、已下播）就不连。协议（Centrifugo JSON：connect、subscribe、25 秒心跳）和消息类型见归档规格 §7，弹幕帧样本 `danmaku/S07-live` |
| J02.1 | 画质 id 对照（上表，`qualityIdFromLegacy`）；房间身份、分区不需要迁移；`link` 可选改写；按 E05.2 存 `startedAt`、`restriction` |
| M13 | 分区名“新人主播”（25-1）和六个分类名（25-8）的多语言，英文建议：新人主播 New broadcasters；个人直播 Personal、聊天 Talk、音乐 Music、游戏 Games、体育 Sports、其他 Other。四种公告、新的粉丝专属公告和目录说明（25-7）按上面的新文字翻译（键 `pandalive_chat_notice`、`pandalive_adult_notice`、`pandalive_password_notice`、`pandalive_restricted_notice`、`pandalive_directory_scope`，粉丝专属要新键），英文建议：“PandaTV chat is not shown here yet. The numbers are viewers now and entries to this broadcast so far.”“Adult broadcasts need a PandaTV login with identity verification; this app cannot play them yet.”“This room has a password; this app cannot play it yet.”“This room is for fans only; this app cannot play it yet.”“This room has viewing conditions (such as a login); this app cannot play it yet.”“Public lives are PandaTV's public broadcasts on air, by popularity; new broadcasters are the ones the platform marks as new. Search finds broadcast titles and broadcasters, offline ones included; you can also enter a broadcaster ID or paste a PandaTV room or channel link.” 外部打开用 `/play/<id>`（25-4，`PandaLiveApi.roomUrl`）。人数（25-3）：PandaTV 现在有在线和累计，3.x 的人数设置页没有 PandaTV 这一项，要加上（“真实在线”模式能选 PandaTV）。卡片按 `restriction` 标出成人、密码、粉丝专属、不可播放，发现页默认隐藏不能播放的直播；开播时间只在直播中显示 |

### 受阻和存疑

没有受阻的条目。存疑、只靠字段名或推断的部分：

- **`ind` 的名称**（25-8）：官网 PC 版和移动版的页面、全部页面脚本、`/v1/config/preset`、`/v1/page/www` 都没有分类名称（官网不显示分类；设置分类的主播端要登录）。`talk`、`music`、`game`、`sports`、`etc` 是英文单词本身，`ind` 按“个人（individual）”理解（官网的关键词自称“개인방송”，近九成的直播是它），名称是推断的。以后找到官方名称时改 `PandaLiveApi.areaNames` 一处即可。
- **粉丝专属**：没有录到 `type` 为 `fan` 的直播（匿名的目录里 132 场都是 `free`），`subscribersOnly` 按归档规格 §2.3 的字段说明判断。
- **重播**：`rec` 的含义按标题前缀“[녹]”和字段名判断（平台没有说明）；只认小写的 `rec`，别的取值照旧是直播。

### 新样本

无。新人主播用 E03.12 已复制的 `S02-index-newbj`（当时 v3 不请求）。实测的请求只用于核实，没有录成样本；密码房的实测结果写在测试的合成回答里（`needLogin` + `isPw`）。

### 测试

本平台 104 个用例（E03.12 是 82 个，新增 22 个，另改写了目录、搜索、进房、画质、取流的用例），`live_core` 共 3352 个，全部通过：

- `pandalive_api_test.dart`（59 个）：
  - 重播：S01、S02 里的重播（5/30、2/7，两个字段都是 `rec`、标题以“[녹]”开头）都是回放、可播放、在回放组；任一字段为 `rec` 就是重播，人数、开播时间、受限类型、公告照旧；主播搜索、刷新、进房（接受和被拒绝）也是回放；
  - 样本对照：上面列出的 `changed:` 和 `added`，改了的键逐个断言新值（`userId` 是编号、`area` 是名称、`link` 是 `/play/`、`notice` 是新文字）；
  - 25-1：两个分区、v3 存下的分区仍有效、`checkArea`；S02 的表单（`onlyNewBj=Y`、字段顺序）和 7 张卡片；
  - 25-12：韩国时间换算、各种坏值、样本里最新的开播时间在录制前一小时内；
  - 25-8：六个代码的名称、不认识的代码、样本里出现的代码都有名称；
  - 25-7：公告和目录说明不含开发术语；
  - 25-3：人数能力表、卡片的默认显示是累计、“真实在线”显示在线；
  - 受限类型：卡片的标记和公告（成人、密码、粉丝专属、`free`、不认识的 `type`）、刷新的标记、拒绝的代码和标记（含密码房回 `needLogin`）、错误类型、没有 HLS 的 `unplayable`；
  - 25-6：`isLive` 为假是未开播，为真、`Y`、缺失、不是开关值仍在播；
  - 25-9：表单与样本录制时相同；
  - 25-2：弹幕参数（频道、令牌、不是数字的频道、没有令牌、拒绝和未开播没有参数、`toString` 不含令牌）；
  - 25-5：S06 的名称、id、`sort`、地址，v3 的 id 映射到新 id；60 帧、重复 id、源画质在任何位置都排第一；`qualityIdFromLegacy` 的规则；用 v3 的 id 取地址；
  - 容错：`PlayList` 里的坏项跳过、主列表里的坏变体只少这一档、全坏是 `ApiChanged`；
  - 占位：昵称为空时留空；
  - 原有的状态码、拒绝、开关、图片白名单、链接（v3 的旧链接仍识别，`roomUrl` 是 `/play/`）。
- `pandalive_site_test.dart`（45 个）：
  - 重播：推荐卡片、刷新、进房、录制详情都是回放，`getLiveStatus` 为假，卡片先进房再取画质，进房照常取到画质和地址、带弹幕参数；
  - 请求与 v3 对照（按 25-4、25-9 改写后逐项相同），`member/bj` 的表单与样本严格匹配；
  - 25-1：新人主播一个请求、表单、7 个房间；别的分区是调用方错误；
  - 25-11：搜索列出了这个 id 时 2 个请求、它排第一（大小写不同也行）；没列出时第 3 个请求查 `member/bj`，与 v3 的请求相同，结果排第一；不存在的 id 不加；`member/bj` 的其他失败在有结果时不报、没结果时报；两个搜索都失败但主播存在；第 2 页不查；取消在查 `member/bj` 之前生效；超过 1000 页的 id 是调用方错误；
  - 25-2：进房、录制带弹幕参数，刷新和拒绝、未开播不带，数字频道；
  - 25-6：`media` 说不在播时刷新、开播状态、进房、链接搜索都只有 `member/bj`，进房没有 `live/play`；
  - 25-5：画质名称和 id、每档地址与 v3 相同、确认的是新 id；v3 存下的 `1080p30`、`360p30` 能播；恢复 3 个请求、地址与 v3 相同；
  - 受限：成人、密码（含 `needLogin` + `isPw`）、需要登录、没有 HLS、主列表 404、没有视频的受限类型和错误；刷新的 `none`；
  - 原有的目录、搜索、刷新合并、错误映射、链接。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.22 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.22-PandaTV弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
