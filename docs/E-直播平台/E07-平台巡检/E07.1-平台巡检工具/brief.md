# E07.1 平台巡检工具：任务书

## 背景

- 来源：docs v0 登记的第一档任务（旧编号 T02e.1）。用户每天在用国内五大平台，海外平台在开代理时用；平台改接口、加风控后，用户看到的是“打不开”“搜不到”“分区空白”，而我们要等 issue 才知道。
- 已经发生过的：2026-09-30～10-01 用临时程序（放在 scratchpad，没进仓库）跑过一次真实接口，当场发现三处已经失效：
  1. 哔哩哔哩分区页对游客每一页都是 -352（3.x 用的 `second/getList`），改成不签名的 `room/v1/area/getRoomList`（`packages/live_core/lib/src/sites/bilibili/bilibili_site.dart:247-266`）；
  2. 虎牙搜索房间和主播全部 `HTTP 403 Not allowed`（不带 User-Agent 被拒），改成带移动端 UA（`huya_site.dart:262-268` 的 `_searchHeaders`）；
  3. 抖音游戏直播间详情没有分区（`douyin_api.dart` 的 `_detailArea`）。
  
  这说明一两周不看就可能有功能悄悄坏掉；而那次的程序没留下，下次又要重写。
- 为什么现在做：第一档。4.0.0 已发布（2026-10-02），用户直接受影响；[E01.6](../../E01-国内五大平台/E01.6-国内五大平台巡检和修复/brief.md)（国内五大平台巡检和修复，也是第一档）要用这个工具。
- 已经做过的：归档 v4 有一个能用的探针 `tools/live_cli`（标签 `v4-archive`），但接口是归档 v4 的，要按现在的 `live_core` 重写（见“现状”）。

## 目标和验收

1. `tools/live_cli` 回到 master，是根目录 `pubspec.yaml` 的 `workspace` 成员；`tools/gate/check_deps.py:34` 写的依赖方向（只依赖 `live_core`、`live_net`、`live_danmaku`、`live_media`、`live_record` 中的需要的几个）和纯 Dart 规则（`:41`）通过；`dart analyze --fatal-infos` 无问题。
2. 本子分类文件夹有 `CHECKS.md`：检查项 P1～P13（下面“方案”第 1 阶段）每一项的做法和判定标准，以及 34 个平台各自的对象表（关键词、固定的未开播房间、不存在的房间号、特有情况、要不要代理、请求间隔、哪些项平台本来不支持）。维护者看过。
3. `dart run tools/live_cli/bin/live_cli.dart patrol` 能跑：
   - 选平台：`patrol bilibili douyu`、`--domestic`（国内 18 个）、`--overseas`（海外 16 个）、`--all`；
   - 代理：`--proxy host:port` 只给海外平台用，国内一律直连（`FixedProxyPolicy(perSite: …)`）；没给代理时海外平台全部记“没测到：没有代理”；
   - `--danmaku <秒>`（默认 0 = 不跑）：每个平台挑一个在播房间连弹幕这么久，记就绪时间和聊天条数；
   - `--out <文件>` 写 Markdown 报告，`--json <文件>` 写机器可读的结果；
   - 退出码：全部正常或不支持 0；有失败 1；参数错 64。
4. 报告格式和各平台 record.md 的“真实环境检查”表一致：开头一行写日期时间（UTC）、直连还是代理、匿名、每个平台用时和总用时；每个平台一张表 `| 检查项 | 结果 | 说明 |`，结果只能是“正常 / 失败 / 没测到 / 不支持”；失败的说明里写错误类型（`SiteError` 子类）、HTTP 状态或平台错误码、出错的步骤。报告里**不出现**完整的播放地址、签名参数、Cookie、设备号、本机出口 IP（地址只写主机名和路径前两段）。
5. 单元测试（`tools/live_cli/test/`）覆盖判定规则、容器识别、报告格式、参数解析和隐私过滤，全部用假的 `LiveSite`、`LiveHttp`，不访问网络（D-017）；门禁 `tools/gate/gate.sh --all` 通过。
6. 用这个工具把 34 个平台跑一遍（国内直连、海外经代理），报告存进本文件夹 `runs/<日期>.md`，record.md 写这一轮的结论；失败项各有去向（国内五大平台并进 E01.6；其余在 E02、E03 登记修复任务，或写明受阻原因）。

## 现状（读代码得出，写文件:行）

- master 上没有 `tools/live_cli/`（`ls tools/` 只有 `brotli`、`check_latest`、`docs`、`ffmpeg_kit`、`gate`、`timeshift`、`ui`），但这些地方已经当它存在：`docs/specs/ENGINEERING.md:52`、`tools/gate/check_deps.py:34`、`:41`、`fixtures/README.md:17`、`:24`。
- 归档的工具（`git show v4-archive:tools/live_cli/...`）：
  - `pubspec.yaml`（依赖 `args`、`crypto`、`live_core`、`live_danmaku`、`live_media`、`live_net`、`live_record`、`path`；`resolution: workspace`；可执行 `live_cli`）；
  - `bin/live_cli.dart`：`CommandRunner` 注册 6 个命令，最后 `exit(exitCode)`（TLS 握手超时后不让 VM 挂着）；
  - `lib/src/probe/probe_command.dart`（207 行）：解析链接 → 详情 → 取流 → 读第一条线路前 64 KB（`_head`：`HttpClient`，10 秒连接、10 秒读，读够就断）→ `_container`（`FLV` 头、`#EXTM3U`、0x47、`ftyp`）→ 要中转的 HLS 经 `LoopbackRelay` 读第一个分片；
  - `lib/src/probe/sites.dart`：33 个平台的工厂表 `siteFactories`（`BilibiliSite.new` 这样只传 `http`）。
  - **不能直接搬**：它用的是归档 v4 的接口 `LinkResolver.resolve`、`RoomSource.detail`、`StreamSource.streams(detail, quality:)`、`Quality`、`LiveState`、`StreamLine.hlsRelay`；现在的 `LiveSite` 没有这些。
- 现在的平台接口（工具要调的）：`packages/live_core/lib/src/live_site.dart`：`getRecommendRooms`（`:42`）、`getCategories`（`:30`）、`getCategoryRooms`（`:39`）、`searchRooms`（`:33`）、`searchAnchors`（`:36`）、`getRoomDetail`（`:46`）、`getPlayQualities`（`:50`）；扩展 `LiveSiteCalls.resolvePlayUrls`（`:421`）、`discoverPlayQualities`（`:468`）；目录分页 `LiveSiteDirectoryPager`（`:375`，YouTube 等推荐走它）；结果 `LivePlayUrlResolution`（`:80`：`lines`、`inputRecipe`、`appliedQualityData`）；线路 `LivePlayLine`（`play_line.dart:41`：`url`、`headers`、`format`、`codec`、`lineId`、`lease`）、租期 `PlayLease`（`:18`：`refreshAt`、`expiresAt`、`cutsConnection`）；错误 `SiteError`（`site_error.dart:9`，9 个子类）；链接 `LiveSiteLinks.roomIdFromUrl`（`links.dart:56`）。
- 应用建适配器的参数（工具照它，但不依赖应用）：`apps/pure_live/lib/app/platforms.dart:135-188`：哔哩哔哩 `storedUid`、斗鱼 `login`/`forceRenewal`、虎牙/快手/Twitch/映客/TikTok/酷狗/百度/17LIVE `preferH264`、Twitch `gqlFallbacks`/`languages`、niconico 和 FC2 `proxy`、Kick `apiHttp`。工具里：Cookie 用空的 `MemoryCookieVault`（`packages/live_net/lib/src/cookies.dart:15`），`preferH264` 用默认 `true`，Twitch 不给后备（电脑上没有 Android TLS），Kick 的 `apiHttp` 就是 `IoLiveHttp`（会被 Cloudflare 拒，见风险）。
- 传输：`IoLiveHttp`（`packages/live_net/lib/src/io_http.dart:17`，`proxy`、`connectTimeout`）；`FixedProxyPolicy`（`proxy.dart:56`，`global` 和 `perSite`）、`HttpProxyRoute`（`:28`）、`DirectRoute`（`:13`）。
- 弹幕（只在 `--danmaku` 时用）：连接类在 `packages/live_danmaku/lib/src/sites/<平台>.dart`，应用的表在 `platforms.dart:196-239`（`buildDanmakuRegistry`）；不提供弹幕的：网易 CC、映客、小红书、微博、LiveMe、TikTok、网络电视（`:190-195` 的注释）。
- 上一轮的检查项和格式：[E01.1 记录](../../E01-国内五大平台/E01.1-哔哩哔哩/record.md)第 177 行起的“真实环境检查”表；其他平台 record.md 有同名的节。

## 3.x 基线

- 3.x 没有巡检工具，也没有探针；只有 `test/fixtures_expected/` 用样本回放（`fixtures/README.md`“生成和比对期望值”）。3.x 的接口用法只用来对照（`git show v3.2.11:lib/core/site/<平台>/`）。
- 本任务不改任何平台的行为，不改应用。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 12 节维护、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`（第 3 节工作区、目录图第 52 行、依赖方向）；`fixtures/README.md`（隐私规则：哪些字段算客户端地址）。
3. 本文件夹的 `README.md`；`git show v4-archive:tools/live_cli/lib/src/probe/probe_command.dart`、`v4-archive:tools/live_cli/lib/src/probe/sites.dart`、`v4-archive:tools/live_cli/bin/live_cli.dart`、`v4-archive:tools/live_cli/pubspec.yaml`。
4. 五大平台 record.md 的“真实环境检查”“修好的问题”两节（[E01.1](../../E01-国内五大平台/E01.1-哔哩哔哩/record.md)、[E01.2](../../E01-国内五大平台/E01.2-斗鱼/record.md)、[E01.3](../../E01-国内五大平台/E01.3-虎牙/record.md)、[E01.4](../../E01-国内五大平台/E01.4-抖音/record.md)、[E01.5](../../E01-国内五大平台/E01.5-快手/record.md)）；海外平台挑 Twitch、niconico、FC2 的同名节看代理和会话型取流怎么测的。
5. [docs/inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 14 节（每个平台能做什么：搜索只搜直播中、只能按房间号查、没有分区……，决定哪些项是“不支持”）；`apps/pure_live/lib/features/search/search_capability.dart:75-141`（每个平台的搜索能力）。

## 范围

- 可以改：新建 `tools/live_cli/`（`pubspec.yaml`、`analysis_options.yaml`、`bin/`、`lib/`、`test/`）；根目录 `pubspec.yaml` 的 `workspace` 加一行 `tools/live_cli`（`pubspec.lock` 随之变）；本子分类文件夹的 `CHECKS.md`；本任务文件夹的 `record.md`、`runs/`。
- 不能改：`packages/` 下任何代码（工具发现平台失效时只报告，修复在 E01.6 或另开的任务里做）；`apps/`；`fixtures/`（这次不录样本；`fixture capture` 命令另开任务取回）；门禁脚本（`check_deps.py` 已经有 `tools/live_cli` 的规则，不用改）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。
- 不能做：登录、发弹幕、点赞、关注等任何写操作；读媒体超过每条线路 64 KB；把 Cookie、设备号、令牌、签名地址、本机出口 IP 写进仓库。

## 方案和阶段

### 第 1 阶段：定检查项（`CHECKS.md`）

检查项（每个平台按能力挑）：

| 编号 | 检查 | 做法 | 正常的标准 |
|---|---|---|---|
| P1 | 推荐 | `getRecommendRooms(page: 1)`、`page: 2`（有 `LiveSiteDirectoryPager` 的平台用 `getDirectoryPage`） | 第 1 页非空；每个房间有 `roomId`，标题或主播名至少一个非空；第 2 页和第 1 页重复的不超过一半（没有第 2 页的平台写“不支持”） |
| P2 | 分类 | `getCategories(1, 30)` | 至少 1 类、每类至少 1 个分区；写出类数和分区总数 |
| P3 | 分区 | 第一个分类里分区最多的那个（或 `CHECKS.md` 指定的热门分区）`getCategoryRooms` 第 1、2 页 | 第 1 页非空，第 2 页不全重复 |
| P4 | 搜索房间 | `searchRooms(关键词)` | 非空；“只搜直播中”的平台每个都 `isLiveNow` |
| P5 | 搜索主播 | `searchAnchors(关键词)`（`search_capability.dart` 里 `anchors: true` 的平台） | 非空 |
| P6 | 在播详情 | 从 P1 里挑 3 个，`getRoomDetail` | `isLiveNow`；标题、主播名非空；有开播时间的平台 `startedAt` 不晚于现在 |
| P7 | 未开播详情 | `CHECKS.md` 的固定房间 | 状态是 offline、replay、carousel 之一，不抛错 |
| P8 | 不存在的房间 | `CHECKS.md` 的房间号 | 抛 `NotFound`（抛别的错写“失败：错误类型不对”） |
| P9 | 清晰度 | P6 的 3 个房间 `discoverPlayQualities` | 非空；名字非空、不重复 |
| P10 | 线路 | 每个房间默认档 `resolvePlayUrls`；每条线路读前 64 KB（照归档 `_head`，带线路的 `headers`） | 有线路；HTTP 2xx；开头字节和 `format` 对得上（`flv` → `FLV`，`hls` → `#EXTM3U`，TS → 0x47，fMP4 → `ftyp`）；会话型（`inputRecipe` 不为空：niconico、FC2、BIGO）记“配方，未打开”算正常 |
| P11 | 租期 | 线路的 `lease` | 有租期的：`refreshAt` 在现在之后、`expiresAt`（有的话）在 `refreshAt` 之后；写出剩余分钟 |
| P12 | 链接 | 用 P6 第一个房间的 `link`（没有时按平台房间地址拼）调 `roomIdFromUrl` | 认出同一个房间号（大小写不敏感的平台按 `SiteIds.ignoresRoomIdCase`） |
| P13 | 弹幕（`--danmaku`） | P6 第一个房间连 N 秒 | 就绪；写就绪用时、聊天条数、有没有重连；结果给 D01，失败不影响退出码以外的项 |

对象表（`CHECKS.md` 写全 34 行；下面是起点，执行者按 FEATURES 第 14 节和各平台 record.md 补全固定房间号）：

| 平台 | 网络 | 关键词 | 平台特有的情况（写进 P6～P8、P12） | 本来不支持的项 |
|---|---|---|---|---|
| 哔哩哔哩 | 直连 | 英雄联盟 | 短号 6；一个轮播房间（P7 期望 carousel）；游客请求 400 实际给 250（P9、P10 记实际档） | — |
| 斗鱼 | 直连 | 英雄联盟 | 靓号 1；字母别名 `lpl`、`LPL`（P12 用别名页，要请求）；轮播房间 93976 | — |
| 虎牙 | 直连 | 英雄联盟 | 字母别名 `lpl`；一个回放房间 | P4 只搜直播中 |
| 抖音 | 直连 | 王者荣耀 | 用 `web_rid` 进房；一个游戏直播间（P6 分区非空） | P5 |
| 快手 | 直连，请求间隔 2.5 秒 | 王者荣耀 | 大小写不同的用户 id `kpl704668133` / `KPL704668133` | — |
| 网易 CC、YY、AcFun、猫耳、克拉克拉、京东、酷狗、六间房 | 直连 | 各平台常见词（写进表） | YY：FLV 优先没打开（E06.3），P10 是移动 HLS | 按 `search_capability.dart` |
| 映客 | 直连 | — | 搜索是推荐里筛选 | P2/P3 看 FEATURES；P13 不提供弹幕 |
| 小红书、微博、百度、LOOK | 直连 | — | 只能按房间号查：P4 用一个已知房间号 | P2/P3（小红书无分区）、P5；小红书、微博 P13 不提供 |
| Twitch | 代理 | league of legends | 电脑上没有 Android TLS 后备，GraphQL 可能被拒：单独标“电脑上被拒” | — |
| SOOP、Picarto、TwitCasting、niconico、SHOWROOM、CHZZK、PandaTV、FC2、Steam、17LIVE | 代理 | 各平台常见词 | niconico、FC2 是会话型（P10 记配方）；niconico 用 `nico.ms` 链接测 P12 | 按 `search_capability.dart` |
| LiveMe | 代理 | — | | P2/P3（无分区）；P13 受阻 |
| TikTok | 代理 | — | 只能精确查频道：P4 用一个已知频道名 | P1、P2、P3（受阻 22-8）；P13 受阻 |
| YouTube | 代理 | 直播关键词 | 推荐是“直播”频道页（目录分页）；P12 用 `@handle` 链接 | P2/P3 |
| BIGO | 代理 | — | 会话型取流；搜索是推荐里筛选 | |
| Kick | 代理 | — | 接口要 Android 系统 TLS，电脑上预计被 Cloudflare 拒：整行标“没测到：要 Android 原生通道”，不算失败 | |
| 网络电视 | — | — | 不巡检（用户自己的列表） | 全部 |

### 第 2 阶段：写工具

| 文件 | 内容 |
|---|---|
| `tools/live_cli/pubspec.yaml`、`analysis_options.yaml` | 照归档；依赖只留 `args`、`live_core`、`live_net`、`live_danmaku`（`--danmaku` 用），不要 `live_record`、`path`；dev `test`、`very_good_analysis` |
| `bin/live_cli.dart` | `CommandRunner` 注册 `probe`、`patrol`；保留归档的 `exit(exitCode)` |
| `lib/src/sites.dart` | 34 个平台的工厂表（按现在的构造参数，见“现状”），`proxyFor(platform)`：国内直连、海外走 `--proxy` |
| `lib/src/probe/probe_command.dart` | 按现在的接口重写：`live_cli probe <平台> <房间号或链接>`：链接先经 `LinkParser`（`links.dart:197`）→ 详情 → 清晰度 → 默认档线路 → 每条线路开头字节 |
| `lib/src/patrol/targets.dart` | `CHECKS.md` 的对象表（同一份数据） |
| `lib/src/patrol/checks.dart` | P1～P13 的实现；每项一个函数，返回 `CheckResult(结果, 说明, 用时)`；异常转成说明（`SiteError` 写类名和 `detail`，`TransportFailure` 写原因）；每项超时 30 秒；平台之间串行，平台内按 `targets` 的间隔 |
| `lib/src/patrol/media.dart` | `head()`、`container()`（照归档 `_head`、`_container`） |
| `lib/src/patrol/report.dart` | Markdown 和 JSON；`redact(Uri)` 只留主机和路径前两段；说明文字过一遍去掉 IP（同 `tools/gate/check_fixtures.py` 的规则：保留段和文档段以外的 IPv4 换成 `x.x.x.x`） |
| `lib/src/patrol/patrol_command.dart` | 参数（平台、`--domestic`、`--overseas`、`--all`、`--proxy`、`--danmaku`、`--out`、`--json`）、退出码 |
| 根目录 `pubspec.yaml` | `workspace:` 加 `tools/live_cli` |

做完的标准：`dart run tools/live_cli/bin/live_cli.dart patrol bilibili --out /tmp/x.md` 在本机能跑出一张表；单元测试和门禁通过。

### 第 3 阶段：跑一遍并记录

- 国内 18 个平台直连跑；海外 16 个经维护者的代理跑（`--proxy 127.0.0.1:<端口>`，问维护者要）；各加 `--danmaku 60` 跑一次国内五大平台。
- 报告存 `runs/<YYYY-MM-DD>.md`（报告本身已脱敏，可以进仓库）；record.md 写：日期时间、网络、总用时；每个平台“正常 N、失败 N、没测到 N、不支持 N”；每个失败项的初步根因（文件:行）和去向。
- 失败项的去向：国内五大平台写进 E01.6 的 record.md 由 E01.6 修；其余平台每个失效在登记表对应子分类登记一个修复任务（标题写“接 E07.1：……”），或写明受阻原因。

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 定检查项 | 上面的 P1～P13 和 34 行对象表，固定房间号从各平台 record.md 和样本（`fixtures/<平台>/`）里找 | `docs/E-直播平台/E07-平台巡检/CHECKS.md`（新） | 34 行都有；每项有判定标准；维护者看过 |
| 2 写工具 | 上表的文件 | `tools/live_cli/`、根 `pubspec.yaml`、`pubspec.lock` | 单元测试 ≥ 20 个通过；门禁通过；本机跑通一个平台 |
| 3 跑一遍并记录 | 全部平台跑一次 | `runs/<日期>.md`、`record.md`、（另开的任务） | 34 个平台都有结果；失败项都有去向 |

每个阶段都能单独合并：阶段 1 只有文档；阶段 2 是新目录和一行 `workspace`，不影响应用；阶段 3 只有文档。

## 测试

- `tools/live_cli/test/checks_test.dart`：用 `LiveSite` 的假子类（返回固定的房间、清晰度、线路，或抛 `NotFound`、`RiskControl`）测每个 P 的判定：例如“第 2 页和第 1 页全重复 → 失败”“P8 抛 `RiskControl` → 失败：错误类型不对”“只搜直播中的平台搜出未开播房间 → 失败”“配方取流 → 正常（配方，未打开）”。
- `media_test.dart`：`container()` 对 FLV 头、`#EXTM3U`、0x47、`ftyp`、空、HTML 错误页的识别；`head()` 用本机 `HttpServer`（`127.0.0.1`，不出网）给 128 KB，断言只读 64 KB 就断开。
- `report_test.dart`：Markdown 表格式和 record.md 一致；`redact` 去掉查询参数和第三段以后的路径；说明里的 `203.0.113.7` 保留、`8.8.8.8` 换掉；JSON 往返。
- `patrol_command_test.dart`：参数组合、没有代理时海外平台“没测到”、退出码。
- 测试里的定时器至少 1 秒；**不访问真实平台**（D-017），本机 `HttpServer` 只监听回环地址。
- 跑法：`cd tools/live_cli && dart test`；门禁 `tools/gate/gate.sh --all` 会自动包含新成员。

## 真机验证（维护者在 K90 上做）

不需要：工具在电脑上跑。第 3 阶段如果发现失效，修复任务各自有真机步骤。

## 风险和注意

- **请求频率**：每个平台每轮几十个请求；快手间隔 2.5 秒（2026-10-01 没被限流）；哔哩哔哩游客容易触发 -352，遇到 `RiskControl` 就停这个平台、写“没测到：风控”，换时间再跑，**不重试刷接口**。
- **时段**：凌晨在播房间少、聊天少，P6、P13 可能挑不到；报告写明时间，拿不到在播房间写“没测到”，不算正常。
- **电脑和手机的差别**：Kick、Twitch 在应用里走 Android 的系统 TLS（`platforms.dart:119-126`），电脑上可能被拒；报告单独标出来，不当成平台失效。海外平台的结果取决于代理出口的地区。
- **隐私**：报告进仓库前人工看一眼：没有完整播放地址、没有 Cookie、没有设备号；门禁 `fixture privacy` 只查 `fixtures/`，报告靠 `redact` 和人工检查。
- **不要把巡检放进门禁或自动测试**：联网的结果每次不同，会让门禁随机失败（D-017）。
- 可能冲突的文件：根目录 `pubspec.yaml`、`pubspec.lock`（别的任务加依赖时）；E01.6 同时做时，`CHECKS.md` 以本任务为准。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录 `flutter pub get`（工作区一起解析）。
- 分支 `ai/E07.1` 或本机工作区；提交信息以 `[E07.1]` 开头（英文），一个阶段一个提交；不推 master。
- 提交前：`tools/live_cli` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze --fatal-infos`、`dart test`；`python3 tools/gate/check_deps.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（哪些检查项写完、哪些平台跑过）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

检查项和对象表是否定稿；工具的命令和参数；测试数量；第一轮结果（每个平台正常、失败、没测到、不支持各几项）；每个失败项的初步根因（文件:行）和去向；新登记的修复任务；建议的巡检频率（建议每两周一次、发布前一次，写进 PROCESS 第 12 节由维护者决定）。
