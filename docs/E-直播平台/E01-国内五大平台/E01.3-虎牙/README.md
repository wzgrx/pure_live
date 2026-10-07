# E01.3 虎牙

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 3-1 回放）、国内平台完善（2026-10-01）和附录 C 落地都记在 [record.md](record.md)
- 旧编号：M4.03、M4.U.3、T02a.3
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；弹幕 D01.4（复用这里的 Tars 编解码）；回放点播的播放在 G 组；巡检 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/huya/`（`huya_api.dart` 1307 行解析、签名和 Tars 载荷，`huya_site.dart` 853 行请求编排）；通用 Tars 编解码 `packages/live_core/lib/src/tars.dart`（448 行）；样本 `fixtures/huya/`（26 组）

## 目标

把 3.x 的虎牙适配器（`lib/core/site/huya/huya_site.dart` 1377 行，加 `huya_utils.dart`、`huya_request_params.dart`、`huya_transport_policy.dart` 和 `pkg/tars`）重构进 `live_core`：分类、推荐、分区、搜索房间和主播、详情、醒目留言（头条留言板）、清晰度、原生 WUP 和网页 AntiCode 两套签名、逐线路取流、恢复、租期、链接都和 3.x 一样能用。修掉 3.x 的 21 个问题（回放进房得到“状态未知”、搜索第 2 页重复第 1 页、Tars int8 读错符号、签名改写不相关的参数、超时单位写错等），Tars 移到通用位置给弹幕复用。

## 平台接口要点

| 功能 | 接口 | 位置 |
|---|---|---|
| 分类 | `live.cdn.huya.com/liveconfig/game/bussLive?bussType=1/2/3/8`，四个一级分类并行请求，任一失败整体报错 | `huya_site.dart:190`、`:195` |
| 推荐、分区房间 | `www.huya.com/cache.php`（`m=LiveList`），每页 120 个，按 `totalPage` 或空页判断末页 | `:206-218` |
| 搜索 | `search.cdn.huya.com/`（房间、主播），必须带 User-Agent（不带回 403，2026-10-01 修）；接口返回 `start + rows` 条，第 2 页跳过前 `start` 条 | `:237`、`:251`、`:268` |
| 详情 | `mp.huya.com/cache.php?do=profileRoom`（毫秒 `_` 绕过约 30 秒的公共缓存，`showSecret=1`）；422 是不存在或字母别名，报 `NotFound` | `:286-300`、`:348` |
| 匿名身份 | `udblgn.huya.com/web/anonymousLogin` | `:789` |
| 签名 | FLV 先取原生 WUP 凭据（`wup.huya.com`，`getCdnTokenInfoEx`），失败再走房间模板或网页 WUP；HLS 只用自己的 AntiCode；各线路并行签名，一条失败只丢这一条；`seqid` 的毫秒严格递增；AntiCode 按原始拼写切分 | `:443`、`:759`；`huya_api.dart` |
| 线路和租期 | 线路编号 `CDN|格式|native/web`，带 UA、Origin、房间 Referer、登录 Cookie；原生 FLV 约 300 秒不断开，HLS 约 120 秒会断开 | `:492`、`:500` |
| 恢复和录制 | 恢复时重新取 `profileRoom` 再签（`:454`）；录制逐线路取（`:473`）；所有线路因 AntiCode 过期失败时重新取一次详情 | |
| 播放 UA | `loadPlayUserAgent()` 用 `raceJson` 竞速 GitHub 镜像读 `assets/play_config.json` 的 `huya.user_agent`，只读一次，读不到用内置 HYSDK UA；应用启动时调用，取流不等它 | `:397`、`:402` |
| 醒目留言 | WUP 读头条留言板（`messageBoard(topSid)`），topSid 用最近一次详情记下的值 | `:366`、`:373` |
| 回放 | REPLAY 的 `liveData.hls`（没有时 `hlsUrl`）是上一场录像（点播 m3u8，不签名不过期）；清晰度另请求 `liveapi.huya.com/moment/getMomentContent?videoId=` | `:410-423` |
| 优先 H.264 | `HuyaSite(preferH264:)`，关时 FLV 线路请求 `codec=265`（平台没有 H.265 转码就退回 H.264，`codec` 标未知），HLS 仍是 264 | `app/platforms.dart:148` 传入 |
| 链接 | 数字房间号；字母别名（`www.huya.com/lpl`）读房间页的 `TT_ROOM_DATA.profileRoom` 换成数字房间号 | `:813`、`:820`、`:829-832` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/huya/huya_site.dart`） | 现在 | 说明 |
|---|---|---|---|
| 分类 | `getCategores` `:155`，串行，`gid` 是字符串就整个崩溃 | `huya_site.dart:190` | 并行；`jsonInt` 兼容数字和字符串，跳过无效项 |
| 推荐、分区 | `:519`、`:197` | `:210`、`:206` | 一致，另给出是否还有下一页；没有截图的封面为空（3.x 是 `null?x-oss-process=…`） |
| 搜索 | `:871`、`:923` | `:237`、`:251` | 第 2 页去掉 3.x 带回的第 1 页 20 个房间；带 UA |
| 详情 | `getRoomDetail` `:566`，用“有没有 `stream`”区分成败，回放和失败混在一起；`:730-742` 返回“播放器里当前房间”的快照 | `:348` | 回放、下播按快照建房；失败抛类型化错误；标题没有简介时退回房间名 |
| 回放 | 进房“状态未知”、录制抛 `FormatException`、刷新得到回放，三处不一致；从不播放 | 三处都是回放；有录像就播放录像（点播，可拖动） | UPGRADES 3-1，2026-09-29 |
| 取流 | `getPlayQualites` `:240`、`getPlayUrls` `:278`；全部签名失败返回空列表 | `:412`、`:443` | 按原因报 `StreamUnavailable`、`ApiChanged`、`NetworkFailure`；关注卡片没有 `data` 时请求一次详情 |
| 签名 | `buildAntiCode` `:1066`、`:1140` 用 `Uri.queryParameters` 先解码再编码，base64 里的 `+` 变空格 | `huya_api.dart` 按原始拼写切分 | 5 组 3.x 签名向量逐字节一致 |
| Tars | `pkg/tars`：int8 无符号读（-3 读成 253）、错误吞成默认值、60000 毫秒当成秒、请求体一字节一块发 | `src/tars.dart`（`TarsWriter`、`TarsStruct`、`WupPacket`） | 有符号、坏数据抛错、走 `LiveHttp`（取令牌 8 秒、留言板 3 秒） |
| 醒目留言 | `:1051-1060` 重新请求完整详情并强转 `danmakuData`，下播房间抛 `TypeError` | `:366` | 复用 topSid，没有时只请求一次 `profileRoom` |
| 实例 | `Sites.of` 每次新建，签名时钟和匿名身份跟着作废 | 注册表每个平台一个实例（E04.1） | 3.x 问题 12 |
| 弹幕 | `getDanmaku()` `:42` | `live_danmaku/lib/src/sites/huya.dart`（D01.4） | 礼物上报、头条通知直接解析面板、下播通知结束连接 |

## 结果

- 首次重构（2026-09-28，提交 `c1a82891f`；当天另有 `9c8da06e1` 把 REPLAY 保持为回放）：21 个 3.x 问题和处理见 record.md“审查发现的 v3 问题”，15 条有意差异见“与 v3 的有意差异”。保留 3.x 的做法：回放显示为回放（上游电视版改成未开播，会改变关注分组，没有采用）、房间号保持请求时的号码、线路顺序按服务端、Cookie 照 3.x 发给列表、详情、网页 WUP 和媒体请求、主播搜索和开播状态查询。
- 升级落地（2026-09-29，`dc2080a18`）：回放有录像就播放录像（`getMomentContent` 列出 1080P 源、720P、360P，源叫“原画”）；开播时间取 `liveData.startTime`；受限类型按网页播放器的读法（`isRoomPay` → `paid`，`isSecret` 1 → `password`），受限的直播取流报 `StreamUnavailable` 且不请求令牌。直播画质名字不改（3.x 的画质偏好按名字精确匹配）。
- 国内平台完善（2026-10-01，`ce7de2d01`）：真实接口检查发现搜索全部 403，根因是 `IoLiveHttp` 不设默认 UA 而搜索请求没带，已修；28 条线路全部可拉；加了“优先 H.264”开关；弹幕礼物上报。附录 C（`5a9fa6a5e`）：头条通知直接解析留言板面板、下播通知结束弹幕连接（弹幕层）。
- 测试：`packages/live_core/test/sites/huya_api_test.dart` 66 个 `test(` 写法、`huya_site_test.dart` 35 个（record.md 统计为 94、37 个用例，部分循环生成）；弹幕 `packages/live_danmaku/test/huya_test.dart` 57 个。

## 验证

- 自动测试：样本逐键对照 3.x；3.x 的签名向量、`seqid`、Tars/WUP 字节向量（原生、网页短 Cookie 和长 Cookie）逐字节一致；回放录像、受限房、优先 H.264、搜索的 UA 断言都有用例。
- 真实接口：2026-10-01 跑了推荐两页、分类（343 个分区）、分区、搜索、3 个在播和 1 个未开播房间的详情、28 条线路（每条读开头 64 KB）、两个房间各 120 秒弹幕；附录 C 时 55 个房间 8 分钟录到 3 条下播通知（record.md“真实环境检查”“附录 C 落地”）。
- 真机：播放和弹幕 K90 看过（2026-10-01，[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）；回放点播的进度条和拖动要在直播间界面里看（C、G 组）。

## 留下的问题

- 付费房、私密房没有真实样本（2026-09-29 扫了推荐 75 页 8874 个房间，`isRoomPay` 全是 0），按网页代码实现；已购买的登录用户能不能取到流没验证。
- 贵族开通、续费通知（附录 C 的 C-11，uri 1001）没录到，没做。
- 关掉“优先 H.264”时 HLS 仍是 264（网页的 HEVC HLS 是另一个地址，没实测）。
- 播放 UA 依赖 GitHub 镜像上的 `assets/play_config.json`，镜像都不通时用内置 UA。
- 接口会变：定期巡检归 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)。
