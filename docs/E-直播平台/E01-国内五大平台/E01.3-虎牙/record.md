# E01.3 虎牙

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/huya/`（`huya_api.dart` 纯解析、签名和 Tars 载荷，`huya_site.dart` 请求编排），通用的 Tars 编解码在 `packages/live_core/lib/src/tars.dart`
- 样本：`fixtures/huya`，23 个真实接口录制和 1 份弹幕录制（`danmaku/S11-live`，D01 用），来自归档。每个接口样本附有 v3 解析器的冻结输出 `expected.json`。
- 参考：
  - 归档 v4 的虎牙适配器和规格（`spec/sites/huya.md`，回归条目 REG-HUYA-001～026）；
  - pure_live_TV `fbbe6521`：没有 `stream` 的详情（下播、回放）直接按快照建房间（采用），回放标为未开播（未采用，见下）；此外只是注释改英文、文字多语言化、弹幕改白色（弹幕在 D01）。

## 做法

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。

- **接口和输出沿用 v3**：`LiveSite`、`LiveRoom` 等模型和 3.x 的 JSON 不变；v3 实现过的可选能力全部保留：刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、逐线路取流（`LivePlayUrlCursorResolver`）、恢复（`LivePlayRecoveryResolver`）、租期查询（`LivePlayLeaseMetadata`）。另加 `LivePlayUrlResolver`（线路要带请求头和租期）和 `LiveSiteLinks`。
- **签名、线路和租期沿用 v3 的算法**：
  - FLV 先取原生 WUP 凭据，失败再走房间模板或网页 WUP；HLS 只用自己的 AntiCode；
  - 各线路并行签名，一条失败只丢这一条；
  - `seqid` 的毫秒严格递增；wsTime 不在本地延长；
  - 租期规则同 v3 的 `getPlayUrlRefreshAt`、`getPlayUrlInvalidAt`，现在直接算进每条线路的 `PlayLease`。
- **解析、签名和 Tars 编解码采用归档 v4 的实现**。它是 v3 的逐条重写，并且：
  - 错误有类型；
  - AntiCode 按原始拼写切分，不先解码再重新编码；
  - Tars 的 int8 按有符号读，坏数据报错而不是静默给默认值。
- **Tars 放在 `live_core` 的通用位置**（`src/tars.dart`，从 `live_core.dart` 导出）：`TarsWriter`、按标签解码的 `TarsStruct`、TUP3 封包 `WupPacket`。D01 的虎牙弹幕直接复用。虎牙专有的结构（`HuyaUserId`、`getCdnTokenInfoEx`、头条留言板）在 `huya_api.dart`。
- **v3 的 `HuyaSite.playUserAgent`**：进程级静态变量改成适配器实例上的值。
  - `loadPlayUserAgent()` 用 `live_net` 的 `raceJson` 竞速 v3 那组 GitHub 镜像，读 `assets/play_config.json` 的 `huya.user_agent`，只读一次；读不到用内置的 HYSDK UA。
  - v3 由启动流程调用（`startup_controller.dart:46-51`），这里同样由应用启动时调用（I01.1）；取流从不等它。
  - 媒体请求头用这个值，原生 WUP 请求仍用内置常量，同 v3。
- **线路带请求头**：从 v3 的 `PlaybackHeaderResolver` 搬来：UA、`Origin`、房间页作 `Referer`、登录 Cookie（v3 也发给 CDN）。
- **房间号保持请求时的号码**。流和弹幕需要的主播 UID、topSid、subSid、线路和画质放在 `HuyaRoomData`。
- **登录 Cookie** 由构造参数注入 `CookieVault`，发送范围同 v3：列表、详情、网页 WUP、媒体请求。
- **弹幕**只输出 `HuyaDanmakuArgs`：
  - `uid`、`topSid`、`subSid` 与 v3 传给弹幕连接的一致，`toString` 仍是 v3 的 JSON；
  - 另带 `superChats`，读头条留言板，D01 不必自己发 WUP 请求。

## 审查发现的 v3 问题

位置都在 `legacy/lib/` 下；未写目录的是 `core/site/huya/huya_site.dart`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 详情请求失败或没有 `stream` 时，进房返回“播放器里当前房间”的错误快照，或一个空的错误房间 | :730-742 | 用“有没有 `stream`”区分成功和失败 | 失败一律抛类型化错误；没有 `stream` 的房间按快照建房 |
| 2 | 同一个 REPLAY 房间，进房得到“状态未知”，录制抛 FormatException，刷新得到“回放” | :609-612, :730-733, :835-852 | 回放没有 `stream`，落进了失败分支 | 三个入口都返回回放房间（见差异 3） |
| 3 | 不存在的房间和字母别名（`status: 422`）得到错误房间或 FormatException | :606-612, :826-830 | 没有识别 422 | `NotFound` |
| 4 | topSid/subSid 取自最后一条在 `multiLine` 里匹配上的线路；直播中但没有 `multiLine` 的房间（S05-ratearray）拿到 0，头条留言从不拉取 | :632-637, :665-670 | 频道号和线路绑在一起取 | 取 `baseSteamInfoList` 第一个正值，没有时用 `chTopId`/`subChId` |
| 5 | 读醒目留言时重新请求一次完整详情，并把 `danmakuData` 直接强转；下播房间没有它，抛 TypeError | :1051-1060 | 为拿 topSid 走了进房流程 | 用最近一次详情记下的 topSid，没有时只请求一次 `profileRoom` |
| 6 | 搜索第 2 页带回第 1 页的 20 个房间（接口返回 `start + rows` 条） | :871-920 | 没处理接口的累积返回 | 条数多于 `rows` 时跳过前 `start` 条，同一响应里去重 |
| 7 | 分类：`gid` 是字符串或缺失时整个分类树崩溃；四个一级分类串行请求 | :173-194, :163-166 | `(item["gid"])?.toInt()`、`gid!` | `jsonInt` 兼容数字、小数和字符串，跳过无效项；并行请求，任一失败整体失败 |
| 8 | 列表和搜索里没有截图的房间，封面成了 `null?x-oss-process=…` | :212-215, :535-538, :892-895 | 对 null 调 `toString()` | 保持为空 |
| 9 | 推荐把所有异常包成 `Exception(e.toString())` | :560-562 | — | 类型化错误 |
| 10 | 房间对象不带 `data`（比如关注卡片）时，画质列表为空 | :240-243 | 只从 `detail.data` 读 | 没有时请求一次详情 |
| 11 | 所有线路签名失败时返回空列表；恢复时下播返回空结果 | :301-305, :320-326 | 错误伪装成“没有地址” | `StreamUnavailable`、`ApiChanged` 或 `NetworkFailure`（按原因） |
| 12 | `Sites.of` 每次新建适配器，签名时钟 `_lastSignatureMillis`、匿名身份缓存都跟着作废；播放和录制在不同实例上签名，同一毫秒仍可能拿到相同的 `seqid`（REG-HUYA-007 的保证只在一个实例内成立） | :47-55；`core/sites.dart`（E04.1 问题 2） | 状态放在短命的实例上 | M3 的注册表每个平台只建一个适配器；时钟、匿名身份、在途请求都在适配器上 |
| 13 | 媒体请求头由播放层按平台另算，UA 是进程级静态变量，WUP 用另一个常量 | :56, :361-372；`player/core/playback_header_resolver.dart:71-83` | 请求头和地址分开 | 线路自带请求头和租期（E01.1 的 `LivePlayLine`） |
| 14 | `buildAntiCode` 先把整个查询串解码再重新编码：base64 里的 `+` 被当成空格，`fm` 解不出；不归签名管的参数被改写 | :1066, :1140 | 用了 `Uri.queryParameters` | 按原始拼写切分，只替换签名的参数 |
| 15 | 房间模板签名失败、网页 WUP 也失败时，再用同一个模板签一次，必然再次失败，报出的也不是真正的原因 | :424-435 | — | 直接报网页 WUP 的错误；模板是过期的就报过期，好触发重新取详情 |
| 16 | 详情标题只取 `introduction`，列表和搜索会退回 `roomName` | :713，对比 :216-219 | — | 详情同样退回 `roomName` |
| 17 | Cookie 为空时也发空的 `Cookie` 头 | :207, :526, :600, :821 | — | 有 Cookie 才发 |
| 18 | `HuyaUrlDataModel.url/uid` 恒为空，`isXingxiu` 无人使用，`HuyaLineModel.bitRate` 可变且不用 | :1330-1377 | 历史遗留 | 不再保留 |
| 19 | Tars 的 int8 按无符号读，返回码 -3 读成 253 | `pkg/tars/codec/tars_input_stream.dart:48-50` | `getUint8` | 有符号 |
| 20 | Tars 解码吞掉错误：`skipToTag` 出错返回 false，`readBytes` 出错返回空，`UniAttribute.get` 出错返回默认对象；截断的响应静默解成默认值 | `tars_input_stream.dart:137-155, 417-420`；`pkg/tars/tup/uni_attribute.dart:182-196` | — | 坏数据抛 FormatException，平台层映射为 `ApiChanged` |
| 21 | Tars 客户端默认超时 60000 被当成秒；请求体按一字节一块发送 | `pkg/tars/net/base_tars_http.dart:34, 60, 70` | 单位写错；`Stream.fromIterable(data.map((e) => [e]))` | 走 `LiveHttp`：取令牌整次 8 秒，留言板 3 秒，一次发送整个请求体 |

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson` 和 v3 的冻结输出。

| 样本 | 结果 |
|---|---|
| S01 分区（4 个一级分类） | 一致。v3 的 `shortName` 写 `null`，新代码写空字符串，3.x 读取时等价 |
| S02、S03 推荐和分区房间（8 页） | 房间、顺序、各字段一致；另外给出“是否还有下一页”（`totalPage` 或空页） |
| S04 搜索：有结果、对不上主播条目、无结果 | 一致 |
| S04 搜索第 2 页 | v3 显示 40 条（前 20 条是第 1 页）；新代码只留后 20 条，字段一致 |
| S05 直播中（多 CDN、星秀、只有 `rateArray`） | 进房和刷新的房间字段、画质（名称、id、排序）、线路（CDN、格式、https 基址、流名、主播 UID、各自的 AntiCode）都一致；只有 S05-ratearray 的 topSid/subSid 不同（问题 4） |
| S06 下播 | 进房、录制、刷新都一致 |
| S06 回放 | 刷新完全一致（状态是回放）；进房 v3 是错误房间，录制 v3 抛 FormatException，现在都是同样的回放房间 |
| S06 不存在、字母别名 | v3 是错误房间或 FormatException，现在是 `NotFound` |
| 签名 | 5 组 v3 `buildAntiCode` 的向量逐字节一致；WAP 形式只差 v3 对无关参数的重新编码（问题 14） |
| Tars/WUP | v3 `BaseTarsHttp` 生成的原生、网页（短 Cookie 和 string4 长 Cookie）请求逐字节一致；响应解码一致，只有 int8 返回码按有符号读（问题 19） |
| S11 头条留言板响应（录制） | 解出空列表，同 v3 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 出错抛类型化错误，不返回“出错快照”或空列表 | 问题 1、3、9、11。界面层改用 `pendingAfterError` 保留旧信息（M13） |
| 2 | 取流失败按原因报错：全是网络问题报 `NetworkFailure`，有结构问题报 `ApiChanged`，其余报 `StreamUnavailable` | v3 静默返回空列表 |
| 3 | REPLAY 房间在进房和录制里也返回回放房间（状态、标题、主播等照常），不再是错误房间或 FormatException；取画质、取流报 `StreamUnavailable`（界面显示“暂时无法播放”），录制器按“不是直播中”处理 | 问题 2。回放没有 `stream`（`liveData.hls` 是一段录像，v3 从不播放）。T02.U 起有录像就播放录像，见文末“升级落地（T02.U）” |
| 4 | `liveStatus` 是其它值或缺失时报 `ApiChanged` | v3 的刷新返回“状态未知”的房间；请求失败和接口变化都不应被当成房间状态（REG-HUYA-015）。界面上同样显示为待定 |
| 5 | 搜索第 2 页去掉重复的第 1 页 | 问题 6 |
| 6 | topSid/subSid 取自 `baseSteamInfoList` 或 `chTopId` | 问题 4；三个录到的直播间里各 CDN 的频道号都相同，且等于 `chTopId` |
| 7 | 读醒目留言不再重新请求完整详情 | 问题 5 |
| 8 | 详情标题在没有简介时退回房间名 | 问题 16 |
| 9 | 分类并行请求 | 问题 7；任何一个失败，整体报错，不返回缺一块的分类树 |
| 10 | 字母别名链接（`www.huya.com/lpl`）先在房间页里找 `TT_ROOM_DATA.profileRoom`，换成数字房间号 | `profileRoom` 不接受别名（S06-alias），v3 打开这类链接必然失败。找不到就不算识别出的链接；房间页跳转则继续解析跳转目标 |
| 11 | 所有线路因 AntiCode 过期而失败时，重新请求一次详情再签 | 进房后很久才换画质，详情里的模板会过期；v3 要等播放出错后走恢复 |
| 12 | 线路自带请求头、格式、编码、线路编号（`CDN|格式|native/web`）和租期 | 问题 13 |
| 13 | 签名不改写不归它管的参数 | 问题 14 |
| 14 | 没有截图的封面为空，图片地址统一规范化 | 问题 8 |
| 15 | 不再提供 v3 恒为空或无人使用的字段 | 问题 18 |

保持 v3 行为、没有采用归档 v4 或上游做法的地方：

- **REPLAY 按 v3 显示为回放**：刷新与 v3 完全一致，关注列表的“回放”分组不变。上游电视版把回放标为未开播，这会改变关注列表的分组，未经用户同意不采用。
- **房间号保持请求时的号码**。归档 v4 换成响应里的 `profileRoom`，那样关注的身份可能变化。
- **线路顺序按服务端给出的顺序**：先全部 FLV，再全部 HLS。归档 v4 改成“原生 FLV、网页 FLV、HLS”。
- **首次取流用进房时的详情**，只有恢复才重新请求详情（同 v3）。归档 v4 每次打开都重新请求。
- **Cookie 照 v3 发送**：列表、详情、网页 WUP、媒体请求。归档 v4 只给网页 WUP 发。
- **播放 UA 仍从 GitHub 镜像读取**（v3 的 `getHuYaUA`），只是改用 `raceJson`、不阻塞取流。归档 v4 的规格主张不访问上游仓库和镜像。
- **主播搜索和开播状态查询**照 v3 提供（归档 v4 去掉了）。
- **画质按请求的算已生效**（`appliedQualityData` 是请求的码率），同 v3；虎牙不回报实际画质。
- **主播搜索的每页条数**照 v3 不限 50。
- **分类名、平台名**保持中文（`虎牙直播`）；上游改成了多语言文字。

后续升级候选（2026-09-28 用户已采用，编号 3-1，落地见文末“升级落地（T02.U）”）：

- **回放单独处理或标为不可播放**。虎牙的回放没有可播的流，卡片却在“回放”分组里，点进去只能看到“暂时无法播放”。可以把它标为未开播（上游电视版的做法），或者在界面上标出“不可播放”，或者接入 `liveData.hls` 的录像。

## 回归条目的覆盖

REG-HUYA-001～019、022～026 都有测试或实现直接覆盖：

- 001、002、019：`api` 和 `site` 测试检查每类线路的租期和是否断开连接；
- 003：房间令牌为空、已签好、是模板三种情况下都先走原生凭据；
- 004、005、007、008：v3 签名向量、过期边界、完整模板、`seqid` 递增、rotl64；
- 006：FLV 用 FLV 令牌，HLS 用 HLS 令牌，HLS 从不请求原生凭据；
- 009：网页路径用 Cookie 的 yyuid 或匿名 UID，不用主播 UID；
- 010：`HuyaApi.selectRefreshedLine`（v3 `HuyaTransportPolicy` 的表驱动用例全部移植），由 G、H01.1 调用；
- 011：一条线路失败不影响其它线路；
- 012、013：`ratio` 的替换和删除，没有画质列表时只给原画；
- 014：列表、搜索、详情的人数都是热度，在线人数留空；
- 015：只有明确的下播状态算下播，网络错误和未知状态都不是；回放在三个入口都是回放，取流报 `StreamUnavailable`；
- 016：`_` 参数和 no-cache 请求头；
- 017：匿名登录失败时用临时 UID，不缓存，下次重试；临时 UID 的取值不越界；
- 018：CDN 名取自 `multiLine[].cdnType`；
- 022：取令牌整次 8 秒、留言板 3 秒；连接的关闭由 `live_net` 的超时和取消负责；
- 023：线路和 `HuyaUserId` 的文字输出不含令牌、流名和 Cookie；
- 024：默认媒体 UA 是 HYSDK；
- 025：恢复一定重新请求详情和签名；
- 026：`iAppId` 固定 66，签名只用本地时钟和服务端 wsTime。

020、021 属于弹幕协议，在 D01 覆盖。本模块提供它们需要的东西：弹幕参数、Tars 编解码、头条留言板的请求和解析（按事件 id 去重的依据 `huya:{lMessageId}`）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕协议（`HuyaDanmaku`）、头条留言的后台重试和去重（REG-HUYA-020、021）、弹幕颜色 | D01；本模块输出 `HuyaDanmakuArgs`，Tars 编解码在 `live_core` |
| `getDanmaku()` | D01 用“平台 → 弹幕连接”的表代替（同 E01.1） |
| 刷新后按线路身份选线（`selectRefreshedLine`）、按租期预取或接管 | G 播放、H01.1 录制 |
| 启动时调用 `loadPlayUserAgent()` | I01.1 |
| Cookie 输入页、App 深链（`yykiwi://`，外部打开） | M13 |

## 新增的通用能力

- `live_core/lib/src/tars.dart`：Tars 编解码和 TUP3 封包，D01 复用。
- `live_net/lib/src/race.dart`：`GitHubMirror`（v3 的 `githup_mirror.dart`），生成一个 GitHub 文件的全部镜像地址；检查更新、字体下载（I01.1、M13）也会用到。

## 测试

新增 117 个用例，`live_core` 共 292 个，全部通过：

- `huya_api_test.dart`（84 个）：
  - 逐个样本对照 v3 的输出，有意的差异逐条断言；
  - 直播状态、热度、画质、错误类型；
  - v3 的签名向量、模板、过期、`seqid`、rotl64；
  - 媒体地址、`ratio` 和 `codec`、请求头、诊断文字不含令牌；
  - 各类线路的租期、令牌有效期、凭据类别；
  - v3 选线表；
  - v3 的 Tars/WUP 字节向量、各类型往返、坏数据、头条留言板、录制的留言板响应。
- `huya_site_test.dart`（32 个），用样本回放加脚本化的 WUP 和匿名登录应答：
  - 分类、列表、搜索的请求和请求头，第 2 页去重；
  - 进房、刷新、录制、开播状态；下播、回放（取画质和取流报 `StreamUnavailable`）、不存在的房间和别名；
  - 醒目留言复用 topSid；
  - 原生 FLV 和网页 HLS 的完整取流（原生请求与 v3 逐字节一致）、画质、原生失败走网页、网页令牌、全部失败的错误类型、过期后重取一次；
  - 恢复、逐线路取流、匿名登录失败与重试、并发打开共享原生请求但签名不同、租期查询；
  - 播放 UA 的竞速读取；
  - 链接和别名解析；传输错误的映射。
- `live_net` 的 `race_test.dart` 加 1 个：`GitHubMirror` 的地址和顺序。

## 升级落地（T02.U）

- 日期：2026-09-29
- 依据：[升级决定](../../../specs/UPGRADES.md)。本平台只有 3-1 一行；另按“统一原则”填 E05.2 的开播时间和受限类型。
- 代码只改了 `sites/huya/` 两个文件，没有改通用文件。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 |
|---|---|---|
| 3-1 回放 | `profileRoom` 的 REPLAY 回答里，`liveData.hls`（没有时用 `hlsUrl`）是上一场的录像：一个点播 m3u8，不用签名、不过期，huya.com 上的 http 升成 https（已实测 https 可用）。<br>**有录像**：状态仍是回放，受限类型 `none`，关注分组仍是“回放”；进房数据直接带上录像（`HuyaRoomData.replay`），打开时不必再请求 `profileRoom`。<br>**取画质**：另请求一次 `liveapi.huya.com/moment/getMomentContent?videoId=`（`vid` 取自录像地址），列出全部清晰度（S15-vod：1080P 源、720P、360P，实测都是 H.264）。源清晰度（地址里 `definition=yuanhua`）按统一原则叫“原画”，其余用平台的 `defName`。这个请求失败或列表为空时，只给 `profileRoom` 那一档（360P）。<br>**取流**：一条 HLS 线路，`lineId` 是 `replay|hls`；请求头是媒体 UA（默认 HYSDK）、Origin 和房间页 Referer，不带登录 Cookie；没有租期。恢复时直接返回同一地址，不再请求。录制按线路取第 0 条。<br>**没有录像**：回放 + `unplayable`，关注分组归入未开播（E05.2 的 `followGroup`）；取画质、取流报 `StreamUnavailable`（原因写 without a recording）。 | 关注列表里的虎牙回放点进去能看这一场的录像，从头播放，可选原画、720P、360P。拿不到录像的回放归入未开播分组，并标“不可播放”（M13 显示）。 |
| 统一原则：开播时间 | 直播中的 `profileRoom` 填 `startedAt`，取自 `liveData.startTime`（Unix 秒）。下播和回放不填，因为这时的 `startTime` 是上一场的。推荐、分区列表和搜索的回答都没有开播时间，留空。 | 房间页和关注刷新后能显示“已开播多久”（M13）。 |
| 统一原则：受限类型 | 按网页播放器（`vplayer.js`、`room_match`）的读法：<br>- `isRoomPay`（`data` 或 `liveData` 里；网页叫 `isPayRoom`）为真：`paid`；<br>- 否则 `isSecret` 为 1：`password`。这是私密房，网页播放器要求输入密码，不打开流；<br>- 这些字段都为假：`none`；回答里一个也没有：null（未提供）。<br>列表卡片同样看 `isRoomPay`。搜索回答里没有这些字段，所以留 null。<br>受限的直播照常显示为直播中，分在直播分组，弹幕参数照给。取画质和取流报 `StreamUnavailable`，原因写 `restricted room (paid)` 或 `restricted room (password)`，不签名，也不请求令牌。 | 付费房、私密房的卡片标出受限类型（M13），播放时说明原因，不再是打不开的黑屏。 |

没有采用的统一原则：

- **源画质改叫“原画”**：直播画质照 v3 用平台给的名字（`蓝光10M`、`蓝光8M` 等）。原因有两条：本平台没有这一条；v3 的画质偏好列表 `['原画','蓝光8M','蓝光4M','超清','流畅']` 按名字精确匹配，改名会让存下“蓝光8M”偏好的用户选到别的档。新做的回放画质按统一原则，源画质叫“原画”。
- 翻页快照、说明文字、按主播关注、房间身份不分大小写：本平台不涉及。虎牙的列表按页由服务端分好；房间号是数字，字母别名在 E01.3 已换成数字房间号。

### 画质 id 对照（给 J02.1）

没有变化。直播画质的 id 仍是码率（0 是源画质），不需要旧 id → 新 id 的对照。回放画质是新增的，id 是录像地址里的 `definition`（`yuanhua`、`1300`、`350`）。`profileRoom` 给的那一档和 `getMomentContent` 列表里同一档的 id 一样，只在播放时用，不进存储。

### 设置项

无。

### 房间身份迁移规则（给 J02.1）

无。房间身份不变（数字房间号，请求时的号码），也不加进 `SiteIds.caseInsensitiveRoomIds`。

### 请求数

- 推荐、分区、搜索、关注刷新的请求数不变，开播时间和受限类型都从原有回答里读。
- 打开有录像的回放房间时，取画质多一次 `getMomentContent`。这是 3-1 要的：`profileRoom` 只给 360P。进房时回放已带录像，取画质不再请求 `profileRoom`；回放恢复不请求。
- 受限直播取流时不请求令牌。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| G | 回放线路是 HLS 点播（`#EXT-X-PLAYLIST-TYPE:VOD`，带 `#EXT-X-ENDLIST`；S06-replay 那一场约 8.7 小时，播放列表可达 2 MB），`lease` 为空。播放器要按点播处理：可以拖动，播到结尾就结束，不能当成断流反复恢复。 |
| M13 | 卡片按 `followGroup` 分组，按 `restriction` 标“不可播放”“付费”“私密”，房间页显示开播时长。发现页默认隐藏不能播放的直播。回放房间显示为点播，加进度条。 |
| D01 | 回放房间不给弹幕参数（`danmakuData` 为空），同 v3。 |
| J02.1 | 按 E05.2 存 `startedAt`、`restriction`；没有迁移项。 |

### 没有样本、没有验证的部分

- **付费房、私密房**：没有真实样本。2026-09-29 扫了推荐列表全部 75 页，共 8874 个在播房间，`isRoomPay` 都是 0。字段的含义来自网页播放器代码，测试用合成数据。已购买的登录用户能不能取到付费直播的流没有验证，现在一律报 `StreamUnavailable`；以后有样本再调整。
- 没有“受阻”的条目。

### 新样本

| 样本 | 请求 | 用途 |
|---|---|---|
| `S15-vod` | `getMomentContent?videoId=1126494362`，就是 S06-replay 那一场录像 | 三个清晰度；360P 和 S06-replay 的 `liveData.hls` 是同一个文件 |
| `S15-vod-missing` | `getMomentContent?videoId=1` | 不存在的录像：`status` 200，清晰度列表为空 |

- 2026-09-28 直连录制，不带 Cookie。归档规格里 S07～S14 已经分给别的样本（有些还没录），所以编号用 S15。
- 脱敏：6 处 `srckey`（每个清晰度的 `url` 和 `m3u8`）按归档规则算作秘密，换成 S06-replay 用过的同形合成值 `YfEmSCSkFIYrUpW8CZY5Ig%3D%3D`，已记进 `meta.json` 的 `scrubbed`。响应头里只有 CDN 和缓存信息：`eagleid` 开头的 8 位十六进制是 CDN 节点地址，两次请求各不相同，不是出口地址。门禁的 `fixture privacy` 检查通过。
- 这两个样本是接口的新回答，没有 v3 输出，所以不带 `expected.json`。

### 与 v3 冻结输出的对照

v3 写过的键都不变，样本对照测试不需要 `changed:`：
- 回放的状态、`isRecord`、`status` 与 v3 的刷新输出相同；
- `startedAt`、`restriction` 是 E05.2 新增的键，只在有值时写，不在 v3 的键集合里。

测试单独断言了这两个字段。原来“回放取画质、取流报 `StreamUnavailable`”的用例改成了播放录像。

### 测试

新增 13 个用例：`huya_api_test.dart` 93 个（+9），`huya_site_test.dart` 36 个（+4）。`live_core` 共 2895 个，全部通过。

- 列表：付费卡片、没有标记的卡片；每张录制的卡片都是 `none`，没有开播时间。搜索卡片两个字段都为空。
- 详情：三个直播样本的开播时间和 `none`；开播时间的字符串、0、缺失；付费、私密、两者都有、都没有；下播没有这两个字段。
- 回放：录像地址、视频号、诊断文字不含 `srckey`、分组、单一清晰度；没有录像、`hlsUrl` 兜底、非 m3u8 或非 http 的地址都算 `unplayable`。
- 录像清晰度：S15-vod 的名称、id、排序和地址，与 S06-replay 同一档对得上；S15-vod-missing 为空；状态码和 HTTP 错误；去重和缺名字；地址规则；未知清晰度。
- 适配器：
  - 回放进房带录像，取画质的请求和请求头，取流一条线路（没有租期、没有 Cookie），恢复不请求，录制取第 0 条；
  - `getMomentContent` 失败或为空时用 `profileRoom` 那一档；
  - 没有录像的回放处处报 `StreamUnavailable`；
  - 付费和私密的直播报 `StreamUnavailable`，不请求令牌，弹幕参数照给；
  - 直播画质在回放上恢复报 `StreamUnavailable`；
  - 刷新带开播时间和受限类型。

## 国内平台完善（T02.D，2026-10-01）

代码只改了 `sites/huya/` 两个文件和 `live_danmaku` 的 `sites/huya.dart`，没有改通用文件。

### 真实环境检查

2026-10-01 匿名、只读、直连，用本仓库的 `HuyaSite` 和 `HuyaDanmakuConnection` 跑（临时程序，不进仓库）。修好搜索后重跑一遍，下表是第二遍的结果。

| 功能 | 结果 | 说明 |
|---|---|---|
| 推荐第 1、2 页 | 各 120 个 | 标题、主播、头像、封面、热度全部齐全；两页没有重复 |
| 分类 | 4 个一级、343 个分区 | 网游 96、单机 119、娱乐 19、手游 109 |
| 分区第 1 页（英雄联盟） | 120 个 | 分区名全部一致，字段齐全 |
| 搜索房间 | **修复前 HTTP 403**；修复后正常 | “英雄联盟”第 1 页 30、第 2 页 10，两页不重复；按主播名搜到对应房间 |
| 搜索主播 | **修复前 HTTP 403**；修复后正常 | “英雄联盟”30 个（在播 5、未播 25） |
| 详情：3 个在播房间（998 主机游戏、60066 三角洲行动、520258 星秀） | 正常 | 标题、主播、头像、封面、热度、开播时间、受限类型（`none`）、弹幕参数都有；线路 4～6 条 |
| 详情：未开播房间（333003） | 正常 | 未开播，标题、主播、头像齐全，没有开播时间和弹幕参数 |
| 画质 | 正常 | 4～6 档（如 蓝光50M、蓝光20M、蓝光8M、蓝光4M、超清、流畅），源画质在前 |
| 线路 | 28/28 条可拉 | 每个房间的最高和最低画质、每条线路各取开头 64 KB：FLV（AL、TX、HS、txdirect，原生签名）都是 FLV 头 + AVC；HLS（网页签名）播放列表和第一个分片都是 TS。`wsSecret`、`wsTime`、`fm`、`seqid` 签名都被 CDN 接受；租期：原生 FLV 约 300 s、不断开，HLS 约 120 s、会断开 |
| H.265 | 能取到 | 同一条原生 FLV 线路把 `codec=264` 换成 `codec=265`：998、60066 回 HEVC（FLV 视频编码 12），520258 仍回 AVC（没有 H.265 转码时平台退回 H.264）；不带 `codec` 是 AVC |
| 弹幕 998（120 s） | 正常 | 聊天 58 条，热度 6 次（444 万左右，与列表热度一致）；礼物 19 个（修复前不报） |
| 弹幕 60066（120 s） | 正常 | 聊天 290 条，热度 6 次（362 万左右）；礼物 27 个；1 次头条通知（2001314），留言板为空，没有醒目留言（通知的消息体本身也是空面板） |

### 修好的问题

| # | 问题 | 根因 | 做法 |
|---|---|---|---|
| 1 | 搜索房间、搜索主播全部失败（`ApiChanged: getSearchContent: HTTP 403`，回答 `{"message":"Not allowed"}`） | 搜索接口现在拒绝不带 User-Agent 的请求（curl 实测：不带 UA 是 403，带 curl 默认 UA 或移动端 UA 都是 200）。v3 用 Dio，会带 Dio 自己的 UA；本仓库的 `IoLiveHttp` 不设默认 UA，搜索请求又没有自己带 | 搜索（房间、主播）带 v3 其他接口用的移动端 UA；分类请求同样带上（现在不带也能用，同一个隐患）。测试断言这三种请求的请求头 |

### 这次做的已批准项

| 依据 | 做了什么 | 用户会看到什么 |
|---|---|---|
| 统一原则“默认编码”（设置加“优先 H.264”，默认开） | `HuyaSite` 加 `preferH264`（同 Twitch 的写法，每次取流时读）。开（默认）：和以前一样，所有线路 `codec=264`。关：FLV 线路请求 `codec=265`（网页播放器能解 HEVC 时就这样请求），平台有 H.265 转码就给 HEVC，没有就退回 H.264，所以这类线路的 `codec` 标为未知（null）；HLS 仍是 `codec=264`（网页的 HEVC HLS 是另一个地址，没有实测）。房间 AntiCode 里自带 `codec` 时照旧不改 | 默认不变。关掉“优先 H.264”后，支持 H.265 的房间走 HEVC，码率相同画质更好；设备不能硬解时由 G 处理 |
| 附录 B 同类做法（B-9、B-10、B-11、B-23：礼物上报，界面暂不显示，B-21 在 M13 统一决定显示） | 弹幕解析 uri 6501（`SendItemSubBroadcastPacket`，本房间的礼物），报 `LiveMessageType.gift`，数据是 `HuyaGift`（礼物 id、名字 `sPropsName`、个数、连击计数 `iItemGroup`、`lPayTotal`），发送者、`huya:<lMsgId>` 作消息 id，文字 `虎粮 ×1`。没有名字的不报（网页按礼物表取名，本客户端不读礼物表） | 暂时看不出（界面还不显示礼物） |

没有做的统一原则：开播时间、受限类型、回放在 T02.U 已做；本平台没有撤回类消息（网页脚本的 uri 表里没有删除或撤回消息的通知）。

### 候选（改变用户看到的内容，未做，由协调者统一问用户）

| 编号 | 内容 | 现状 | 建议 | 依据 |
|---|---|---|---|---|
| D3-1 | 头条通知（uri 2001314）的消息体本身就是留言板面板（`GameEventMessageBoardPanel`），直接解析，不再每次通知后请求留言板（最多 4 次） | 照 v3 忽略消息体，后台补拉留言板 | 采用：醒目留言出现得更快，少请求；只在消息体解不开时补拉 | 网页脚本 `room_match` 的 uri 表 `2001314: GameEventMessageBoardPanel`；本次录到的一次通知，消息体是和留言板回答同结构的空面板 |
| D3-2 | 下播通知（uri 8001 `EndLiveNotice`）：显示“直播已结束”通知并结束弹幕连接（同 B-14 17LIVE 的做法） | 不处理，下播后连接一直空等 | 采用，先录到下播样本再做 | 网页脚本 `taf-signal` 的 uri 表；本次没有录到下播 |
| D3-3 | 贵族开通、续费（uri 1001 `NobleNotice`）显示为通知（同 B-9 猫耳的做法） | 忽略 | 可选（屏幕上会多出系统行）；录到样本后再做 | 同上；本次 4 分钟没有出现 |

另外核对过、不需要改的：

- **在线人数**：虎牙公开接口和弹幕都没有同时在线人数，列表、详情、8006 都是热度（REG-HUYA-014），实测与网页显示的热度一致。
- **AL 线路**：有的房间 `baseSteamInfoList` 有 AL，但 `multiLine` 不列（`iWebPriorityRate` 为 -1），网页也不用；照 v3 只用 `multiLine` 列出的线路。
- **每档是否有 H.265**：`bitRateInfo.iHEVCBitRate` 和实测对不上（源画质写 -1，实际能取到 HEVC），不据此标注画质；由“优先 H.264”统一决定请求哪种编码。
- **上游电视版**：虎牙部分和 E01.3 核对时相同（回放标为未开播仍不采用）；归档 v4 的待确认项（密码房、付费房）仍没有真实样本。

### 新样本

`fixtures/huya/danmaku/S18-gift`：本次检查里房间 60066 的 120 s 弹幕，只留 27 个礼物推送（命令 7、uri 6501），按解析读的字段重新编码；发送者换成同位数的随机 uid 和“观众N”（同一人一套），其余字段（支付单号、头像、用户和贵族结构、特效、扩展数据）删去，其余 433 帧不留。见 `meta.json`。门禁的 `fixture privacy` 通过。

### 测试

新增 4 个用例：`huya_api_test.dart` 94 个（+1：关掉优先 H.264 时的地址），`huya_site_test.dart` 37 个（+1：`preferH264` 关和开；分类、搜索、主播搜索的用例加了 UA 断言），`live_danmaku` 的 `huya_test.dart` 54 个（+2：S18 礼物、没有名字或坏消息体）。都通过。

## 附录 C 落地（T02.D2）

2026-10-01，用户批准附录 C 后做 C-9、C-10；C-11 没录到样本，没做。代码只改了 `sites/huya/huya_api.dart` 和 `live_danmaku` 的 `sites/huya.dart`。

| 编号 | 做了什么 | 用户会看到什么 |
|---|---|---|
| C-9 | 头条通知（uri 2001314）的消息体按留言板面板（`GameEventMessageBoardPanel`）解析：`HuyaApi.headlineNotice` 和留言板回答共用同一段面板解析（`_panel`，字段、时间窗、价格、`huya:<lMessageId>` 不变），每条留言立刻作为醒目留言上报，和补拉的结果共用“每次连接只报一次”。空面板就是留言板已空，不再请求。消息体缺失、为空、不是 Tars 或没有 tag 1 列表时，照旧在后台补拉留言板（0、0.6、1.8、4 s）。`HuyaDanmakuProtocol.decode` 加 `now:`（醒目留言的时间窗），连接加 `now:`；`superChatNotices` 改为“需要补拉的通知数”（S11、S16 的 3.x 对照不变：那些通知都没有消息体） | 醒目留言随通知同时出现，不再等补拉；每条通知少 1～4 个请求 |
| C-10 | 下播通知（uri 8001 `EndLiveNotice`：0 lPresenterUid、1 iReason、2 lLiveId、3 sReason）：`decode` 报出各通知的主播 uid（`ended`），连接收到本房间主播（或没写 uid）的下播通知时，先报完同一帧里的其他消息，再以 `connectionFailed`（`Broadcast ended`）结束，不重连；别的主播的不理 | 主播下播后弹幕连接随即结束，不再空等和重连 |
| C-11 | 没做 | 不变 |

**录制**：匿名、只读、直连，08:14～08:22（北京时间）共 8 分钟，推荐前两页里 55 个在播房间各开一个连接（临时程序，不进仓库）。3 个房间下播，各收到一条 8001（`sReason` 都是“主播结束直播”，`iReason` 0），服务端之后不关连接（其中一个又开了 6.5 分钟），所以必须由客户端结束。这段时间没有出现 1001（贵族开通、续费），也没有 1002、1005、1006（贵族进场）和 2001314，C-11 留待以后录到再做。

**新样本**：
- `fixtures/huya/danmaku/S19-headline`：T02.D 那次录制（房间 60066，2026-09-30）里唯一的头条通知，原样保留；消息体是空面板。不含观众信息。
- `fixtures/huya/danmaku/S20-end`：本次录到的 3 条下播通知，原样保留，`conn` 是房间号，主播 uid 记在 `meta.json`。不含观众信息。

**测试**：`live_danmaku` 的 `huya_test.dart` 57 个（+3：S19 空面板和合成面板的解析、非面板仍补拉；连接直接上报面板里的留言、重复只报一次、不请求；S20 三条通知的 uid，本房间的结束连接、别的房间的不理）。`live_core` 的虎牙测试 131 个不变，都通过。
