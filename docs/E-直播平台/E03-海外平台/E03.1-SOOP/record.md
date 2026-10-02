# E03.1 SOOP

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/soop/`（`soop_api.dart` 纯解析，`soop_site.dart` 请求编排）
- 样本：`fixtures/soop`，25 个真实接口录制，来自归档，另有弹幕样本 `danmaku/S07-live`（D01 用）。其中 21 个附有 v3 的冻结输出 `expected.json`（4 个主页接口样本 `S05-station-*` 是 v3 不请求的接口，没有期望值），生成方法见下文。
- 参考：
  - 归档 v4 的 SOOP 适配器和规格（`spec/sites/soop.md`，其中 8 条回归条目 REG-SOOP-001～008）；
  - pure_live_TV `fbbe6521`：SOOP 的请求和解析与 v3 相同，只是文字多语言化、去掉 GetX，没有行为修复；对照笔记 `~/ref/notes/tvcore/sub_B.md` 的 soop 一节。

按 E01.1 的做法：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。另按 2026-09-28 补充的规则：用户能看到的状态、分组、画质名称和列表内容都按 v3；修好但会改变这些内容的地方，列入“后续升级候选”；关注刷新和列表的请求不比 v3 多。

## v3 的冻结输出

归档里 SOOP 的样本没有 `expected.json`（归档只给五个大站生成过）。这次按同样的口径补上：

- 把 v3 的 `core/site/soop/soop_site.dart`、`LiveRoom`、`LiveArea`、`LivePlayQuality`、`LiveQualityLabel`、`HttpHeaderPolicy` **原样复制**到一个临时的纯 Dart 包里，只把运行环境换成桩：`HttpClient` 按请求回放样本（和 Dio 一样，JSON 类型的响应解码成对象，`text/html` 保持文本，非 2xx 抛出）、设置里的 SOOP Cookie 为空、GetX 没有注册播放器、日志静默。
- 逐个样本调用 v3 的入口（`getSubCategores`、`getCategores`、`getCategoryRooms`、`getRecommendRooms`、`searchRooms`、`getRoomDetail`、`getRoomDetailForRefresh`、`getRoomDetailForRecording`、`getPlayQualites`、`getCdnUrl`、`getStreamAid`、`getPlayUrls`），抛出的异常记为 `throws`，同时记下 v3 发出的请求（地址、表单、请求头）。
- 房间的投影与其他平台相同：`toJson` 加上 `link`、`data`、弹幕参数，去掉 null 和空集合。
- 详情封面里的 `_t=` 是 v3 取的当前时间，写成 `{now}`。

## 做法

- **接口和输出沿用 v3**：`LiveSite` 和 v3 实现过的可选能力（关注刷新、录制详情），外加取流线路（`LivePlayUrlResolver`）、恢复取流（`LivePlayRecoveryResolver`）和 `LiveSiteLinks`。3.x 的 JSON 不变。
- **请求照 v3**：
  - 目录、分区、推荐、搜索、播放接口、分配地址都带 v3 的 `getHeaders()`（`Origin`、`Referer` 为 `www.sooplive.co.kr`，Chrome 128 的 UA，`sec-fetch-*`）；
  - 用户存了 Cookie 时，所有请求、媒体请求头和弹幕握手都带上（v3 就是这样），Cookie 由构造参数注入的 `CookieVault` 提供，去掉控制字符；
  - 每个请求的 `site` 都是 `soop`，海外站点走不走代理由应用按平台配置（Q01.1 的 `ProxyPolicy`），适配器不管路由；
  - 请求次数：分类 5 页、分区和推荐和搜索各 1 个、详情（进房、刷新、录制）各 1 个，都与 v3 相同。
- **详情**：只请求 `player_live_api.php`（`type=live`），和 v3 一样。`RESULT` 按 v3：
  - 1：有 `VIEWPRESET` 才算在播，否则未开播；
  - 0（未开播，主播不存在也是 0）、-2（屏蔽）：刷新和录制是未开播、屏蔽，和 v3 一样；进房时 v3 把它们当成加载失败（直播间提示“获取房间信息失败”），这里在进房时报 `StreamUnavailable`，界面照旧显示失败；
  - -6（19 禁，需要登录）：三种深度都报 `NeedsLogin`，v3 进房是“状态未知”、刷新和录制抛 `StateError`，界面看到的仍是加载失败；
  - 其他值：`ApiChanged`。

  房间号保持请求时的号码，直播号（`BNO`）、分配服务器（`RMD`）、CDN 码和画质预设放在 `SoopRoomData`。
- **取流**：照 v3 的顺序，先向 `RMD/broad_stream_assign.html` 要播放列表地址，再用 `type=aid` 要播放密钥，地址是 `view_url?aid=…`。结果是一条线路：v3 播放层的 SOOP 请求头（Chrome 140 的 UA、`Origin: www.sooplive.co.kr`、`Referer: play.sooplive.co.kr/<房间>`、用户 Cookie）、HLS、预设里的编码、CDN 码作线路编号。带密钥的播放列表实测 40 分钟内一直可用（归档规格），所以没有租期；恢复时重新请求播放接口，换了场次也能接上。
- **画质**：与 v3 完全相同，包括名称、顺序和排序值（`hd4k` 仍排最后、显示 “hd4k”，见“后续升级候选”）。
- **弹幕**：只输出 `SoopDanmakuArgs`：v3 的地址（`CHDOMAIN` 的 `CHPT + 1` 端口，`wss`）、`CHATNO`、v3 给弹幕连接的请求头，另附明文端口的地址，是否回退由 D01 决定。

## 审查发现的 v3 问题

位置简写：`site` = `legacy/lib/core/site/soop/soop_site.dart`，`wsp` = `legacy/lib/modules/search/web_search_room_parser.dart`，`url_tool` = `legacy/lib/common/utils/live_url_tool.dart`，`phr` = `legacy/lib/player/core/playback_header_resolver.dart`。“按 v3 保留”的，修法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 未开播的主播进房提示“获取房间信息失败，请重试”，关注刷新却显示未开播；屏蔽的房间同样 | site:433-444、348-371；对照 site:385-391、411-416 | 进房路径把 `RESULT != 1` 一律当成失败，刷新和录制路径才区分 0、-2 | 按 v3 保留：进房报 `StreamUnavailable`（界面照旧显示加载失败），刷新和录制照旧是未开播、屏蔽 |
| 2 | 进房失败时返回“当前播放房间”的快照或空房间 | site:353-369、436-442 | 界面兜底写在平台层，还通过 GetX 读播放器 | 抛类型化错误，界面层用 `pendingAfterError` 保留旧信息（M13） |
| 3 | 19 禁直播：进房是“状态未知”，刷新和录制抛 `StateError`；取流时密钥为空，悄悄返回空地址 | site:392-395、417、538、301 | 需要登录没有专门的错误 | `NeedsLogin`（界面上仍是加载失败或无法播放） |
| 4 | 房间号换成响应里的 `BJID`，用大写链接打开的房间身份会变 | site:473 | 以响应为准 | 保持请求时的号码；链接里的 id 统一小写 |
| 5 | `userId` 存的是每次开播都变的直播号 | site:474 | 借用字段 | 直播号放进 `SoopRoomData`（界面不显示 `userId`） |
| 6 | 720p 预设（`hd4k`）排在 360p 之后，名称直接显示成 “hd4k” | site:270-282；`core/utils/live_quality_label.dart:62-71` | 分级表和画质名称表都没有 `hd4k` | 按 v3 保留 |
| 7 | 搜索结果没有分区 | site:659 | 读的 `standard_broad_cate_name` 响应里已经没有（有的是 `broad_cate_name`） | 按 v3 保留 |
| 8 | 标题里的 HTML 实体原样显示（`928개 냠냠 &amp; …`、`랜만&gt;&lt;`） | site:219、330、658 | 没有解码 | 按 v3 保留 |
| 9 | 缺字段时显示 "null" 或整页失败：昵称 `toString()`、`user_profile_img` 为空时类型错误、`TITLE` 为 "null"、一个字母的 `BJID` 截取越界、`data.list` 或 `broad` 为空时遍历 null、没有 `BNO` 时封面是 `…/m/null` | site:221、225、334、666、476、462、215、325、446、461 | 直接下标取值 | 缺字段为空；没有 `user_id` 的卡片跳过（样本里没有这类数据，现有内容不变） |
| 10 | 分类有一页失败时悄悄返回部分目录，第 1 页失败时目录为空；按“本页满 120 条”判断还有下一页 | site:122-142 | `catch` 后返回已有结果；不读 `is_more` | 后面的页失败仍返回已有的分区（v3）；第 1 页失败报错；按 `is_more` 翻页（544 个分区时请求数与 v3 相同，整 120 倍时少一次） |
| 11 | 只有 `CHIP` 时拼出的聊天主机是 `.sooplive.co.kr` | site:619-626 | 接口给的 `CHDOMAIN` 都在 `sooplive.com`（样本 `chat-6E0A4C4E.sooplive.com`） | 按 v3 保留（样本都有 `CHDOMAIN`，用不到这条） |
| 12 | `www.sooplive.co.kr/station/<id>` 被识别成主播 “station”，`vod.sooplive.co.kr/player/…` 被识别成主播 “player”；两套链接规则认的域名不同 | wsp:159-160；url_tool:146、334 | 规则分散在两处，只取第一段 | 一套规则认两个域名，`station` 取下一段，页面路径不算主播（v3 打开这些链接只会加载失败） |
| 13 | `view_url` 自带查询参数时拼出 `?a=b?aid=…` | site:302 | 直接拼 `?aid=` | 有查询参数时用 `&`（没有时地址与 v3 逐字相同） |
| 14 | 恢复取流时沿用详情里的旧直播号，主播重新开播后恢复失败 | site:285-307（没有实现恢复接口） | 直播号来自进房时的详情 | 恢复时重新请求播放接口（只在播放路径上多一个请求） |
| 15 | Cookie 和播放请求头读全局设置，播放请求头按平台写在播放层 | site:193；phr:123-131；`core/danmaku/soop_danmaku.dart:67-69` | GetX 单例 | Cookie 由 `CookieVault` 注入；请求头随线路给出 |
| 16 | 没有实现 `getLiveStatus`，基类永远返回 false | `core/interface/live_site.dart:252` | — | 用刷新的结果（v3 没有调用方） |
| 17 | 空关键词也发搜索请求 | site:629-651 | — | 直接返回空列表 |
| 18 | 推荐每次请求都把整个响应写进日志；一个永远不用的 Chrome 37 请求头表、图片扩展名表和 `isImage` | site:323；site:110-120、21-38、176-182 | 调试遗留、死代码 | 不移植 |

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson` 和 v3 的冻结输出；请求（地址、表单、请求头）另外比较。

| 样本 | 结果 |
|---|---|
| S01 分类（5 页，544 个分区） | 一致，翻页次数也一致。v3 的 `shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S02 分区房间（60 条、34 条） | 一致，标题里的实体也照旧 |
| S03 推荐（60、20、0 条） | 一致；人数都是 PC 加手机（`total_view_cnt`） |
| S04 搜索（30 条、空结果） | 一致（分区都为空）；空结果页的 `HAS_MORE_LIST` 为真，列表照样为空 |
| S05 详情（在播） | 除 `userId`（直播号挪进 `SoopRoomData`）外一致；封面同样带 `_t`；弹幕地址和 `CHATNO` 一致 |
| S05 未开播、主播不存在 | 刷新、录制与 v3 一致（未开播）；进房 v3 是“状态未知”的出错房间，现在是 `StreamUnavailable` |
| S05 19 禁 | v3 进房“状态未知”、刷新和录制抛 `StateError`；现在三种深度都是 `NeedsLogin` |
| 画质（S05 在播） | 名称、编号、顺序、排序值、`data` 全部一致：原画、高清、标清、hd4k |
| S06 分配地址、播放密钥、播放地址 | 请求地址、表单、结果、最终地址都一致；19 禁的密钥 v3 为空，现在是 `NeedsLogin` |
| 请求头 | 与 v3 的 `getHeaders()` 一致，只是空 Cookie 不再发送 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 出错抛类型化错误，不返回出错快照或“状态未知”的房间：进房时 `RESULT` 0、-2 是 `StreamUnavailable`，19 禁是 `NeedsLogin`，其他是 `ApiChanged` 等 | 问题 1～3。界面看到的仍是 v3 的“加载失败”（M13 用 `pendingAfterError`），状态和分组不变 |
| 2 | 房间号保持请求时的号码，链接里的 id 统一小写 | 问题 4。v3 的关注都来自响应里的 `BJID`（平台给的都是小写），已有的关注身份不变 |
| 3 | `userId` 为空，直播号在 `SoopRoomData.bno`；详情带 `link`（直播页） | 问题 5；界面不显示这两个字段 |
| 4 | 缺字段为空，不出现 "null"，不整页失败 | 问题 9。分区房间缺头像时用推荐页同样拼出的头像。样本里没有这类数据 |
| 5 | 第 1 页分类失败时报错 | 问题 10。v3 显示空目录；后面的页失败仍按 v3 返回已有的分区 |
| 6 | 线路自带 v3 播放层的请求头、编码、CDN 码；没有租期 | 见“做法”。请求头与 `PlaybackHeaderResolver` 的 SOOP 分支逐项相同 |
| 7 | 没有详情数据的房间（列表卡片）取画质和取流时先请求播放接口；恢复时总是重新请求 | 问题 14。只在播放路径上；v3 对这类房间返回空列表 |
| 8 | 取流失败有类型：分配地址 `result` 不为 1 是 `StreamUnavailable`，密钥 -6 是 `NeedsLogin`，其他取不到密钥是 `StreamUnavailable`（密码房在说明里注明） | v3 返回空地址列表，界面同样是无法播放 |
| 9 | `view_url` 自带查询参数时用 `&aid=` | 问题 13 |
| 10 | 弹幕参数带上 v3 的握手请求头和明文端口地址 | v3 在连接时才读请求头；明文端口留给 D01 决定 |
| 11 | 链接：`station/<id>` 取下一段，`live`、`vod`、`player` 等页面不算主播，两个域名一套规则 | 问题 12。v3 打开这些链接只会加载失败 |
| 12 | `getLiveStatus` 用刷新的结果 | 问题 16（v3 没有调用方） |
| 13 | 空关键词不发请求；空 Cookie 不发送 | 问题 17；v3 总带一个空的 `Cookie` 头 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

（E06 平台层升级 已按升级决定改掉其中的主页接口、画质、标题、搜索分区、聊天主机和 `afreecatv.com` 链接，见文末“升级落地（E06 平台层升级）”。）

- **不查主页接口**。归档 v4 另请求 `chapi.sooplive.co.kr/api/<id>/station`：详情补人数、头像和简介，`RESULT` 0 时区分未开播和主播不存在（REG-SOOP-005），19 禁显示为在播（REG-SOOP-006）。这会改变关注列表的分组，刷新也多一个请求，列为后续升级候选。样本 `S05-station-*` 已经一起复制。
- **画质、标题、搜索分区、聊天主机都按 v3**（问题 6、7、8、11），见“后续升级候选”。归档 v4 的画质只按码率排序（原画缺码率时会排到最后），名称用预设的 `label`（“1080p”），也没有采用。
- **请求头照 v3**：API 请求的 `Origin`、`Referer` 是 `www.sooplive.co.kr`，UA 是 Chrome 128；媒体请求 `Origin` 是 `www.sooplive.co.kr`、`Referer` 是直播页。归档 v4 给播放接口换成直播页的 `Referer`、统一用 Chrome 140，媒体请求用 `play.sooplive.co.kr` 作 `Origin`。
- **Cookie 随所有请求发送**（目录、搜索、分配地址、媒体、弹幕）。归档 v4 只让播放接口带 Cookie。
- **不预先拦截密码房**。归档 v4 看到 `BPWD == Y` 就直接报“暂时无法播放”；v3 照样请求密钥，这里也请求，取不到时报 `StreamUnavailable` 并注明密码房（没有样本，不确定平台会不会给密钥）。
- **平台不回报实际画质，仍按 v3 假定请求的画质已生效**。归档 v4 标为“未确认”，界面会多出未确认的标记。
- **详情封面保留 v3 的 `_t` 缓存参数**，头像地址照 v3（推荐和搜索卡片用拼出的 `m/<id>.webp`，详情用 `<id>.jpg`）。
- **详情没有在线人数**（播放接口不给）。v3 进房时用列表卡片的人数兜底，这一步在 M13 做。
- **分区每页条数按设置发送并限制在 1～60，搜索限制在 1～50**；归档 v4 固定 60 和 30。推荐每页 60 条是平台定的。
- **不认 `afreecatv.com` 链接**（v3 不认）；归档 v4 认。
- **弹幕只给出 v3 的 TLS 地址和明文地址，不在这里决定回退**。
- 显示名仍是“SOOP直播”。上游 pure_live_TV 与 v3 相同，没有要采用的修复。

## 后续升级候选（由用户决定）

（2026-09-28 全部采用，编号 7-1～7-9，落地见文末“升级落地（E06 平台层升级）”。）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | `hd4k`（720p）排在原画之后、高清之前，名称“超清” | 排在 360p 之后，显示 “hd4k” | 样本 S05：`hd4k` 的 `label` 是 720p；上游对照笔记也指出这一点 |
| 2 | 标题、昵称解码 HTML 实体 | 显示 `&amp;`、`&gt;&lt;` | 样本 S02、S03 |
| 3 | 搜索卡片的分区取 `broad_cate_name` | 搜索卡片没有分区 | 样本 S04 |
| 4 | 进房时 `RESULT` 0 显示未开播、-2 显示屏蔽 | 提示“获取房间信息失败” | v3 刷新路径的注释：0 是明确的“未开播” |
| 5 | 主页接口：进房补在线人数、头像、简介；区分主播不存在（REG-SOOP-005）；19 禁显示为在播、取流时再提示登录（REG-SOOP-006） | 不请求 | 样本 `S05-station-*`；只在进房时请求，刷新不加请求 |
| 6 | 只有 `CHIP` 时聊天主机用 `.sooplive.com` | `.sooplive.co.kr` | 接口给的 `CHDOMAIN` 都在 `sooplive.com`；归档 v4 已改 |
| 7 | 认 `afreecatv.com/<id>` 链接 | 不认 | SOOP 自己的搜索结果仍给这种地址（样本 S04 的 `url`） |
| 8 | 密码房：识别 `BPWD` 后在界面提示，或支持输入密码（`pwd` 字段） | 取流失败 | 没有样本 |
| 9 | 分享文本里的 App 深链 `sooplive://player/live?broad_no=…&user_id=…`，列表里的开播时间 `broad_start` | 不支持 | 样本 S02 的 `scheme` |

## 回归条目的覆盖

- 平台层的条目都有测试直接覆盖：
  - 003 人数用 PC 加手机，不单用 `current_view_cnt`（样本逐条核对）；
  - 004 原画缺码率仍排第一，`auto` 不列（v3 的名称分级）；
  - 007 搜索只以空页结束（空结果页 `HAS_MORE_LIST` 为真）；
  - 008 线路没有租期，恢复时重新请求播放接口。
- 002 的一半在这里：弹幕参数给出 `CHPT + 1` 的 TLS 地址和 `CHPT` 的明文地址，测试核对了录制的两次握手地址；回退本身在 D01。
- 005、006 按 v3 的显示保留，测试固定了现在的行为（`RESULT` 0 刷新为未开播、进房报 `StreamUnavailable`，都只发一个请求；19 禁在三种深度都是 `NeedsLogin`），改法见“后续升级候选”第 5 条。
- 001（保留大小写的握手、`chat` 子协议）属于弹幕协议，在 D01 覆盖。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕协议（`SoopDanmaku`：`ESC TAB` 包头、登录和加入、20 秒心跳、保留大小写的握手、TLS 端口不通时是否回退明文端口） | D01；本模块输出 `SoopDanmakuArgs`，样本在 `fixtures/soop/danmaku/S07-live` |
| `getDanmaku()` | 同 E01.1：D01 用一张“平台 → 弹幕连接”的表 |
| 进房时用列表卡片的人数兜底（v3 的 `withAudienceFallbackFrom`）、出错时保留旧信息并提示“获取房间信息失败” | M13 直播间 |
| Cookie 页（手动粘贴，去掉控制字符）；Cookie 加密存储，实现 `CookieVault` | M13、J02.1 |
| 按平台走代理（SOOP 是海外站点） | 应用设置（J02.1、I01.1）注入 `ProxyPolicy` |
| 外部打开 `https://play.sooplive.co.kr/<id>` | M13；地址由 `SoopApi.roomPageUrl` 和详情的 `link` 提供 |
| 分区页、搜索页是否按页加载 | M13 |

## 新增的通用能力

没有。只在 `live_core.dart` 里加了两行导出；用到的 `json.dart` 工具（E01.1）、`LiveRequest.form`（Q01.1）都已存在。

## 测试

62 个用例，`live_core` 共 406 个，全部通过：

- `soop_api_test.dart`（39 个）：逐个样本对照 v3 的输出（分类、列表、搜索、详情三种深度、画质、分配地址、密钥、播放地址），有意的差异逐条断言；人数口径（移植 v3 的 `soop_platform_test.dart`）、画质的分级（移植 v3 的画质用例）、弹幕地址（移植 v3 的 `soop_danmaku_endpoint_test.dart`，并核对录制的握手地址）、线路的请求头、`RESULT` 和 HTTP 状态的错误映射、缺字段；按 v3 保留的内容（实体、搜索分区、`hd4k`）也有断言。
- `soop_site_test.dart`（23 个），用样本回放加少量合成响应：
  - 目录逐页的请求和请求头与 v3 相同，后面的页失败返回已有分区、第 1 页失败报错、取消原样抛出，重复页不会死循环；
  - 分区、推荐、搜索的请求与 v3 相同，每页条数的限制，空关键词；
  - 详情的表单和请求头与 v3 相同、房间号保持、三种深度、未开播和不存在（刷新为未开播，进房报错，每次一个请求）、19 禁、非法房间号；
  - 取流：进房得到的房间不再请求详情，先分配地址再要密钥，地址与 v3 相同；列表卡片先请求播放接口；恢复总是重新请求；未开播和 19 禁；
  - 用户 Cookie 随每个请求、线路和弹幕握手发送，没有时一个都不带；
  - 链接（移植 v3 的链接用例，另加 `station`、大写、页面路径）和分享文本；
  - 传输错误的映射，取消原样抛出。

## 升级落地（E06 平台层升级）

- 日期：2026-09-29（E03.1）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 7-1～7-9；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。7-6（聊天服务器）属于弹幕，连接由 D01.8 做，这里只改了平台层给出的弹幕参数。
- 只改了本平台：`soop_api.dart`（解析）、`soop_site.dart`（请求编排）和两份测试。没有改 `live_core` 的通用文件，没有新依赖。新样本 6 个（见下文）。
- 实测：2026-09-29 用改好的适配器请求了真实接口（推荐全部 40 页约 2370 个房间，每种受限类型挑一个房间进房、刷新、取画质和取流，另查了不存在和未开播的主播、搜索），结果和下面写的一致。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 7-1 | 新增 `SoopApi.qualityName`：`hd4k`（720p）叫“超清”。`qualitySort` 给 `hd4k` 一档 3.5 亿，排在原画（6 亿）之后、`hd`（3 亿）之前；其他档的排序值和 v3 相同。同一个根因还有 `hd8k`：1440p 直播的 1080p 转码档（新样本 S05-live-1440p，实测推荐前排就有），v3 同样显示成 “hd8k” 排最后，按同样做法叫“蓝光”，和 `fullhd` 同档（4 亿）。画质 id 仍是平台的请求名，没有变 | 画质菜单从“原画、高清、标清、hd4k”变成“原画、超清、高清、标清”；1440p 直播是“原画、蓝光、超清、高清、标清” | 完成（E06 平台层升级） |
| 7-2 | 标题、昵称解码 HTML 字符：推荐、分区、搜索卡片，详情的 `TITLE`、`BJNICK`，主页接口的昵称、简介和直播标题；搜索卡片的分区名也解码 | `928개 냠냠 &amp; …` 显示成 `928개 냠냠 & …`，`랜만&gt;&lt;` 显示成 `랜만><` | 完成（E06 平台层升级） |
| 7-3 | 搜索卡片的分区读 `broad_cate_name`，没有时再读 v3 的 `standard_broad_cate_name` | 搜索结果卡片显示分区（S04 全部 30 条都有） | 完成（E06 平台层升级） |
| 7-4 | `SoopApi.roomDetail` 去掉 `roomEntry` 参数：`RESULT` 0 在进房时也是未开播，-2 是屏蔽，和刷新一致 | 进入未开播主播的直播间，显示未开播（带昵称、头像、简介，见 7-5），不再提示“获取房间信息失败”；被屏蔽的显示屏蔽 | 完成（E06 平台层升级） |
| 7-5 | 进房时和播放接口**同时**请求主页接口 `chapi.sooplive.co.kr/api/<id>/station`（请求头同其他接口，带用户 Cookie）。新增 `SoopStation`、`SoopStationBroadcast`、`SoopApi.station`、`SoopApi.withStation`：补主播设的头像 `profile_image`、简介 `station_title`、在线人数 `current_sum_viewer`（PC 加手机）；受限直播缺的昵称、标题、封面、开播时间也从这里补。主页接口回答 HTTP 515、`code` 9000 时，未开播的房间报 `NotFound`（REG-SOOP-005）。主页接口失败（网络、改版、取消）不影响进房，房间就是播放接口的回答；未开播时仍是未开播。播放接口说未开播而主页接口说在播时，按在播显示，受限类型用主页接口的，没有就标 `unplayable`（平台说在播但不给本客户端地址）。19 禁（`RESULT` -6）在进房、刷新、录制时都是直播中、受限类型 `adult`，标题和开播时间取自这个回答；取流报 `NeedsLogin`（REG-SOOP-006） | 直播间显示主播自己设的头像、简介和在线人数；输入不存在的主播 id 提示“不存在”；19 禁直播在关注列表和直播间都显示直播中，标“成人”，播放时提示需要登录（界面在 M13） | 平台层完成，余下 M13 |
| 7-6 | 只有 `CHIP` 时拼出的聊天主机改为 `chat-<十六进制>.sooplive.com`。用两个样本核对过：去掉 `CHDOMAIN` 后由 `CHIP` 拼出的地址与接口给的 `CHDOMAIN` 完全相同（S05-live-live、S05-live-password） | 平台层看不出变化（样本都有 `CHDOMAIN`）；弹幕连接在 D01.8 | 平台层完成，余下 D01 |
| 7-7 | 链接规则认 `afreecatv.com` 及其子域（`afreecatv.com/<id>`、`play.afreecatv.com/<id>/<直播号>`、`bj.afreecatv.com/<id>`、`station/<id>`），规则和 SOOP 两个域名相同 | 粘贴 SOOP 搜索结果里的 `http://afreecatv.com/<id>` 能打开房间（S04 的 30 个地址全部识别成对应主播） | 完成（E06 平台层升级） |
| 7-8 | 识别密码房：`RESULT` 1 且 `BPWD` 为 `Y`（新样本 S05-live-password）、`RESULT` -8（19 禁加密码，新样本 S05-live-adult-password）、列表的 `is_password`、主页接口的 `is_password`，都标 `password`，房间仍是直播中。取流：`RESULT` 1 的密码房照 v3 仍请求分配地址和密钥，密钥被拒（`RESULT` 0，新样本 S06-aid-password）时报 `StreamUnavailable`，说明写 `password-protected`；-8 的房间没有直播数据，直接报 `StreamUnavailable`（`password-protected`）。输入密码没有做，见“受阻” | 密码房显示直播中并标“密码”，播放时提示是密码房（界面在 M13） | 平台层完成，余下 M13；输入密码受阻：没有能验证的密码 |
| 7-9 | App 深链：`SoopSite.roomIdsInShareText` 认分享文本里的 `sooplive://player/live?broad_no=…&user_id=<id>`（S02 的 `scheme` 就是这个形式），先于网页链接；新增 `SoopApi.appLink(房间号, bno:)` 生成同样的深链、`SoopApi.appLinkRoomId` 解析，供 M13 的分享文本或“在 SOOP App 中打开”使用。列表开播时间：推荐、分区、搜索卡片的 `broad_start`（韩国时间）换成 UTC 填 `startedAt` | 粘贴带 SOOP App 深链的分享文本能打开房间；列表卡片可以显示开播时间（只在直播中显示，界面在 M13） | 平台层完成，余下 M13 |

`hd8k` 不在升级表里，是 7-1 同一个问题（v3 的分档表缺平台较新的档名）在 1440p 直播上的表现，按 7-1 的做法一并处理，汇报时单独说明。

### 统一原则在 SOOP 上的落实

| 事项 | 做法 |
|---|---|
| 开播时间 | 列表：`broad_start`，格式 `2026-09-22 19:59:31`（分区列表多 `.0`），是韩国时间，按 UTC+9 换算（`SoopApi.koreanTime`）。依据：S05 的 `BTIME` 和同一场的 `broad_start` 按 UTC+9 完全对上；S02、S03、S04 最晚的开播时间都早于录制时间，按 UTC 理解就会晚于录制时间。详情：播放接口的 `BTIME` 是已播秒数（S05-live-live 的 455474 秒、S05-live-adult 的 14665 秒，换算后与主页接口的 `broad_start` 分秒不差），开播时间 = 请求时刻 − `BTIME`，取整到秒（`SoopApi.startedBefore`），三种深度都有，不需要多发请求。`RESULT` -14 的回答没有 `BTIME`：刷新时不填（合并时保留存下的值），进房时用主页接口的 `broad_start`。两种来源可能差 1 秒 |
| 受限类型 | 来源：播放接口 `RESULT` 1 的 `BPWD`、`P_MIN_TIER`、`GRADE`；-6 是 `adult`，-8 是 `password`，-14 是 `subscribersOnly`（新样本 S05-live-subscribers）；列表的 `is_password`、`subscription_only`、`broad_grade`（分区列表是 `grade`）；主页接口 `broad` 的同名字段。几种同时成立时按“密码 > 仅订阅 > 成人”取一种（`SoopApi.restrictionOf`、`stricter`），先报登录也解决不了的。字段都在且都没有限制时填 `none`；回答里没有这些字段（未开播、屏蔽、`RESULT` 1 但没有 `VIEWPRESET`）时留空。取流时的错误（`SoopApi.noStream`）：`adult` 报 `NeedsLogin`，`password`、`subscribersOnly`、`unplayable` 报 `StreamUnavailable`，说明里写原因 |
| 受限的直播改为直播中 | -6、-8、-14 在进房、刷新、录制时都是直播中（v3：进房“状态未知”，刷新和录制抛 `StateError`；E03.1：-6 报 `NeedsLogin`，-8、-14 报 `ApiChanged`）。列表卡片本来就是直播中，现在带上受限类型。2026-09-29 实测推荐全部房间里约 11% 是成人、约 6% 是密码房（深夜时段），另有几个仅订阅 |
| 占位信息 | 适配器没有占位文字。-14 的回答没有标题、昵称，留空（刷新合并时保留关注里存下的值） |
| 回放、轮播、“不可播放” | SOOP 的这些接口没有回放和轮播状态。`unplayable` 只用在“播放接口说未开播、主页接口说在播”这一种情况 |
| 画质命名 | 源画质本来就叫“原画”；每档只有一条线路（CDN 码），没有要合并的档。样本和实测的预设都是 H.264（`AV1` 为 0），“优先 H.264”对本平台没有影响 |
| 房间身份 | 不变：主播 id，E05.2 已按不分大小写比较。`afreecatv.com` 链接和 App 深链得到的 id 同样转小写 |
| 按主播关注 | 本来就是按主播（BJ id）关注，没有单场 id，不需要迁移 |
| 容错 | 不变：坏行跳过（E03.1 问题 9）；主页接口失败不影响进房 |
| 翻页 | 分区、推荐、搜索都是服务端分页，适配器不缓存；A-4（按页加载）和跨页去重在 M13 |

### 请求数

| 场景 | v3 / E03.1 | 现在 |
|---|---|---|
| 关注刷新、录制详情 | 播放接口 1 个 | 不变 |
| 分类、分区、推荐、搜索 | 5 页 / 各 1 个 | 不变 |
| 进房 | 播放接口 1 个 | 2 个：播放接口和主页接口**同时**发出（7-5 要求的请求），进房耗时基本不变 |
| 取流 | 分配地址 + 密钥（没有直播数据的房间先请求播放接口） | 不变；-6、-8、-14 的房间在那一次播放接口请求后直接报原因，不再请求分配地址 |

### 画质 id 对照（给 J02.1）

没有要迁移的：画质 id 仍是平台的请求名（`original`、`hd8k`、`hd4k`、`hd`、`sd`），旧 id 和新 id 相同，所以没有提供对照常量。只改了名称和顺序：

| id | v3 名称 | 现在 |
|---|---|---|
| `hd4k`（720p） | hd4k，排最后 | 超清，原画之后、高清之前 |
| `hd8k`（1440p 直播的 1080p） | hd8k，排最后 | 蓝光，原画之后、超清之前 |

3.x 的画质偏好是全局按名称存的（原画、蓝光 8M、蓝光 4M、超清、流畅），不按平台存 id，所以 SOOP 没有要迁移的存储；改名后 SOOP 多了能按名称命中的“超清”“蓝光”档，怎么匹配由 G/M13 定。

### 设置项

无。

### 身份迁移规则（给 J02.1）

无。房间身份仍是主播 id，含义和写法都没变。

### 留给其他模块

| 内容 | 去向 |
|---|---|
| SOOP 弹幕连接：用 `SoopDanmakuArgs`（聊天主机规则已按 7-6 改好；TLS 端口不通时是否退回明文端口，REG-SOOP-002）。-6、-8、-14 的回答没有 `CHATNO`，这些房间进房时没有弹幕参数 | D01.8 |
| 直播间的未开播、屏蔽显示（7-4）；“主播不存在”的提示（7-5 的 `NotFound`）；卡片和直播间的受限标记（成人、密码、仅订阅、不可播放）；发现页是否隐藏受限直播（`needsLogin`、`adult` 登录后可能可以播放）；播放失败时按错误类型提示登录或说明原因；开播时间只在直播中显示；分享文本是否带 `SoopApi.appLink` 的深链、是否提供“在 SOOP App 中打开”；以后若能输入密码，密码输入框 | M13 |
| 存储：本平台没有新设置、没有画质 id 或身份变化 | J02.1（无事可做） |
| 播放器：没有要配合的（线路、请求头、租期都没变） | G（无事可做） |

### 受阻和未核实

- **7-8 的“输入密码”受阻**：播放接口的表单里有 `pwd` 字段，看起来是提交密码用的，但没有知道密码的密码房可以验证：不知道只在 `type=aid` 带上是否够、密码错时怎么回答、登录的管理员是否不需要密码。所以适配器照 v3 发空的 `pwd`，只做了“识别后提示”。找到能验证的房间后再做（构造参数接收密码来源、表单带上 `pwd`，界面在 M13）。
- **未核实（没有登录样本）**：登录后播放接口对 19 禁、仅订阅直播回答 `RESULT` 1 时，`GRADE` 19、`P_MIN_TIER` 大于 0 分别标 `adult`、`subscribersOnly`——按字段名和列表字段的含义推断。匿名时这两种直播不会回答 1，所以不影响匿名用户。
- `RESULT` -2（屏蔽）仍没有样本，按 v3 的注释处理。

### 与 v3 冻结输出的新差异

样本对照测试里用 `changed:` 列出，注释写条目编号：

- 列表（S02、S03、S04）：`title`、`nick` 与 v3 的值解码后相同（7-2）；S04 的 `area`（7-3）。新键 `startedAt`、`restriction` 由单独的用例检查（3.x 没有这两个键，读取时忽略）。
- 详情 S05-live-live：新键 `startedAt`、`restriction`；进房补了主页接口后，`avatar`、`introduction`、`watching`、`onlineViewers` 不同（7-5）。
- S05-live-offline、S05-live-missing 的进房（v3 `getRoomDetail`）：`liveStatus` 由 3（未知）变 1（未开播，7-4），`watching` 为 `0`（与 v3 的刷新相同）。
- S05-live-adult：三种深度都是直播中、`adult`（v3：状态未知、`StateError`，7-5）。
- 画质 S05-live-live：`hd4k` 的名称和排序值（7-1），其余三档与 v3 逐项相同。
- 弹幕：v3 的端点用例里由 `CHIP` 拼出的主机改为 `.sooplive.com`（7-6）。

### 新样本

2026-09-28 16:43～16:59 UTC 直连录制，不带 Cookie，请求头是适配器的 `apiHeaders()`；`raw` 记原始回答的 SHA-256 和长度；都没有 v3 的期望值（v3 对它们的处理与已有样本相同或会报错）。门禁的 `fixture privacy` 通过。

| 样本 | 内容 | 脱敏（`meta.json` 的 `scrubbed`） |
|---|---|---|
| `S05-live-password` | 播放接口 `type=live`，密码房 nsh100427：`RESULT` 1、`BPWD` Y | `COLONY_CONTENT`、`FTK` 的十六进制部分、Set-Cookie 的值（`AbroadChk`、`AbroadVod`、`_au`、`_au3rd`、`_ausa`、`_ausb`）换成同形合成值 |
| `S06-aid-password` | 同一场 `type=aid`、`quality=original`：`RESULT` 0，不给密钥 | Set-Cookie 的值 |
| `S05-live-adult-password` | 19 禁加密码 qazeee：`RESULT` -8，带 `TITLE`、`BTIME` | Set-Cookie 的值 |
| `S05-live-subscribers` | 仅订阅 kirababy2：`RESULT` -14，`P_MIN_TIER` 2，没有标题和时间 | Set-Cookie 的值 |
| `S05-station-subscribers` | 同一主播的主页接口：`broad.subscription_only` 2 | 送礼榜、贴纸榜里其他用户的 id、昵称、头像换成假名（`fan01`…、`팬01`…，规则 `person`）；Set-Cookie `bjStationHistory` 的值。JSON 按已有主页样本的格式缩进写出 |
| `S05-live-1440p` | 1440p 直播 rrvv17：预设含 `hd8k`（1080p） | `TS`、`TS_SNAPSHOT` 地址里的 `data`、`COLONY_CONTENT`、`FTK`、Set-Cookie 的值 |

主播的公开信息（id、昵称、标题、直播号、聊天服务器、主页简介）按 E03.1 的口径保留。

### 测试

本平台 93 个用例（新增 31 个，另改写了受影响的对照用例），`live_core` 共 2932 个，门禁 `--all` 通过：

- `soop_api_test.dart`（62 个）：列表对照加 `changed:`；标题解码（7-2）；三种列表的开播时间（韩国时间换算，并与录制时间比较）和受限类型（S02 13 个成人、S03 2 个成人、S04 1 个密码和 1 个成人、仅订阅）；搜索分区（7-3）；详情的开播时间和受限类型；未开播、不存在在各深度是未开播（7-4）；-6、-8、-14、`BPWD` 各一个样本；`RESULT` 1 的受限字段组合；屏蔽；主页接口的解析（在播、未开播、19 禁、仅订阅、不存在、出错）和 `withStation` 的各种组合（在播补资料、主页接口是另一场、未开播、19 禁、仅订阅、播放接口未开播但主页接口在播、屏蔽）；`restrictionOf`、`stricter`、`koreanTime`、`startedBefore`；画质（S05 对照、分档表、1440p 的 `hd8k`）；由 `CHIP` 拼出的聊天主机等于 `CHDOMAIN`（7-6）；App 深链的生成和解析；密码房的密钥被拒。
- `soop_site_test.dart`（31 个）：进房请求播放接口和主页接口（顺序、请求头、Cookie）；主页接口超时、取消、502、改版时进房照常；刷新和录制仍只发一个请求；未开播进房是未开播、不存在是 `NotFound`、主页接口失败时是未开播；屏蔽；19 禁在各深度直播中、取流 `NeedsLogin`；密码房和仅订阅的取流错误；密码房照 v3 请求分配地址和密钥后报密码房；画质顺序（7-1）；`afreecatv.com` 链接（S04 的 30 个地址）和 App 深链（经 `LinkParser`，不发请求）。
