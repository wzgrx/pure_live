# E02.2 网易 CC

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 9-1～9-7）和国内平台完善（2026-10-01，真实环境检查和弹幕调查）都记在 [record.md](record.md)
- 旧编号：M4.09、M4.U.9、T02b.2
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；未开播显示（UPGRADES A-6）在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md) 确认；弹幕：平台不给匿名访客弹幕，D01 里没有 CC 的任务（UPGRADES C-22，见“留下的问题”）；CC Cookie 页在 K01.1，画质 id 迁移在 J02.1；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/cc/`（`cc_api.dart` 895 行解析，`cc_site.dart` 449 行请求编排）；样本 `fixtures/cc/`（ls 共 34 项：33 组接口录制，另有 `legacy_expected.dart` 补出 3.x 冻结输出；没有弹幕样本）；应用在 `apps/pure_live/lib/app/platforms.dart:151` 建 `CcSite(http)`，弹幕登记表不登记 CC（同文件 `:191-195` 的注释）

## 目标

把 3.x 的网易 CC 适配器（`lib/core/site/cc/cc_site.dart` 424 行、`cc_catalog.dart` 118 行）重构进 `live_core`。首次重构保持 3.x 用户实际看到的样子（画质名称、可选项、播放地址），只在 3.x 报错的地方兜底（未开播主播进房 RangeError、链接误认）；升级落地时按用户采用的 9-1～9-7 换成真正不同的画质、移动端分类、重播频道标回放、关注刷新区分不存在。

## 平台接口要点

| 功能 | 接口（全部匿名；请求头 UA 和 `Referer: https://cc.163.com/`） | 位置 |
|---|---|---|
| 分类 | 移动端 `api.cc.163.com/v1/wapcc/gamecategory?catetype=0` 取 4 个一级分类（网游、手游、竞技、综艺），再各请求一次取分区（约 106 个）；同时读大神的游戏表（`inf.ds.163.com/…/base-info-list/by-type`）和直播配置（`inf-act.ds.163.com/…/commonAppConfig`）得到“官方房间/专题”入口（id `official:<ccid>`，在浏览器里打开）；共 7 个请求，大神两个失败只少官方入口 | `cc_site.dart:98`、`:107`、`:123`；`cc_api.dart:82`、`:99`、`:136`、`:202` |
| 分区房间 | `cc.163.com/api/category/<gametype>/`，每页固定 30，满页才有下一页（目录分页 `_CcCategoryDirectory.getDirectoryPage`）；坏行只跳过这一行 | `cc_site.dart:154`、`:157`、`:441`；`cc_api.dart:225` |
| 推荐 | `cc.163.com/api/category/live/`，条数照调用方（热门页一次要 100）；卡片读 `gamename` 作分区（9-2） | `cc_site.dart:181`；`cc_api.dart:249` |
| 搜索 | `cc.163.com/search/anchor/`（路径带斜杠，3.x 少斜杠多一次 301），每页 1～50；在播主播用直播封面和热度（9-5）；房间搜索和主播搜索是同一个接口 | `cc_site.dart:197`、`:212`；`cc_api.dart:296` |
| 详情 | `api.cc.163.com/v1/activitylives/anchor/lives?anchor_ccid=` 拿频道号，再 `cc.163.com/live/channel/?channelids=`；没有频道就是未开播；进房时读房间页 `cc.163.com/<ccid>/` 补全并区分不存在；关注刷新另请求 `api.cc.163.com/v1/wapcc/recommendbyccid?ccid=`（约 2.5 KB，`code` 4 是不存在，8 秒超时）；录制和开播状态只发 1 个请求 | `cc_site.dart:229`、`:257`、`:276-291`；`cc_api.dart:343`、`:366`、`:425`、`:444` |
| 画质和线路 | `vapi.cc.163.com/video_play_url/<ccid>`：`vbrname_list` 从高到低，名字用 `vbrname_mapping`（原画、蓝光5M、蓝光3M、超清、高清、标清）；取流按 `vbrname=<档位码>`，FLV 两个 CDN（`hs`、`ali`）互为备用，`cdn_list` 没覆盖的 CDN 各补一次请求；`auth_key` 租期 300 秒（提前 60 秒续）、`cutsConnection` 为假；取画质的回答 30 秒内给第一次播放用一次；失败时退回 3.x 的跳转播放列表 `cgi.v.cc.163.com/redirect/video/<ccid>.m3u8` | `cc_site.dart:302`、`:336`、`:359`、`:369`；`cc_api.dart:628`、`:642`、`:686`、`:738` |
| 画质 id 换算 | `CcApi.qualityIdFromLegacy`：3.x 的 `high` → `ultra`、`medium` → `high`、`low` → `standard`、`blueray_20M` → `blueray_5M_avc`，`original` 不变；只能对旧 id 套用一次 | `cc_api.dart:609-620` |
| 链接 | `cc.163.com/<数字>`、`ds.163.com/glive/?ccid=`、`h5.cc.163.com/cc/<ccid>`，只收数字 | `cc_site.dart:394`、`:408` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/cc/`） | 现在（`packages/live_core/lib/src/sites/cc/`） | 说明 |
|---|---|---|---|
| 分类 | `cc_site.dart:32` `getCategores`、`cc_catalog.dart`：大神配置“直播分类”20 个分区 + 官方入口，两个请求串行 | `cc_site.dart:98` | 9-4：移动端 4 组 106 个分区 + 官方入口；3.x 存下的分区 id（`gametype`）照常能打开（9050 明日之后不在新目录里，仍能按 id 列出） |
| 画质 | `getPlayQualites` `:128`、`getPlayUrls` `:219`：每档都是同一个跳转播放列表拼签名，服务端忽略签名，全部 302 到同一路 1 Mbps；跳转后的 HLS 300 秒过期 | `cc_site.dart:302`、`:336` | 9-1：`video_play_url`，每档不同的流（实测原画约 8 Mbps、超清 2、高清 1、标清 0.6） |
| 详情 | `getRoomDetail` `:262`；`_loadRoomDetail` `:297-300` 未开播时拿 `null` 查频道，`data[0]` 抛 RangeError，进房“状态未知”；`:314` 房间号取响应里的 `ccid` | `cc_site.dart:229`、`:276` | 未开播如实返回；进房区分不存在；房间号保持请求时的号码 |
| 重播频道 | “【重播】”开头的仍是直播中 | 回放（有流照常播） | 9-3；2026-09-29 全站在播约 100 个，34 个是重播 |
| 推荐卡片 | `getRecommendRooms` `:248` 读 `game_name`，推荐的行只有 `gamename`，没有分区名 | 读 `gamename` | 9-2 |
| 搜索卡片 | `searchRooms` `:354`：头像作封面、粉丝数作人数 | 在播的用直播封面和热度 | 9-5 |
| 关注刷新 | 不区分不存在 | `recommendbyccid` 区分 | 9-7 |
| 开播状态 | `getLiveStatus` `:398-400` 永远返回 true | 按详情判断 | 3.x 问题 10 |
| 链接 | `common/utils/live_url_tool.dart:141-142`、`:321` 把 `cc.163.com/任何单词` 当房间，不认 `ds.163.com/glive/` | 只收数字 ccid，认三种地址 | 3.x 问题 11、12 |
| 弹幕 | `getDanmaku()` `:27` 是 `EmptyDanmaku` | 不登记，直播间显示一次“不支持” | 匿名加入房间没有回答 |

## 结果

- 首次重构（2026-09-28，提交 `480454577`）：15 个 3.x 问题、11 条有意差异见 record.md；实测确认 3.x 的画质选择不起作用（4 档全部 302 到同一个 `…tc2.m3u8`）。
- 升级落地（2026-09-29，`c64520ece`）：9-1～9-7 全部做完；开播时间取 `startat`（北京时间，按 `liveMinute` 核对时区）；有档位表的在播房间受限类型为 `none`；分区列表的坏行只跳过这一行。请求数：分类 2 → 7，未开播的关注刷新 1 → 2，取画质 0 → 1，进房后第一次播放仍是 0。
- 国内平台完善（2026-10-01）：真实接口全部正常（线路全是 H.264 的 FLV），没有要修的；弹幕调查：`wss://weblink.cc.163.com/` 能连、设备注册和心跳都通，但匿名“加入房间”（`{512, 1}`）没有任何回答，判断要登录用户，按任务要求不硬做（记录里的候选 C-1，即 UPGRADES C-22）。
- 测试：`packages/live_core/test/sites/cc_api_test.dart` 39 个 `test(` 写法、`cc_site_test.dart` 33 个（record.md 按实际用例统计 79 个：46 + 33）。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出，9-2、9-3、9-5、9-6 的变化用 `changed:` 列出；画质 id 对照表核对 3.x 每一档都能在同一房间的新列表里找到；关注刷新的 `NotFound`、超时和异常回答；取画质的回答复用（只用一次、换档作废、30 秒过期）；`video_play_url` 失败时退回 3.x 画质。E06.1 的 A-6 引用 `cc_site_test.dart:415` 的“an offline anchor on room entry: the room page fills the room”。
- 真实接口：2026-09-28 逐档逐线路请求核对；2026-09-29 凌晨用新适配器跑一遍（分类 106 个分区加 4 个官方入口、推荐 99 个房间、在播 4 档、未开播和不存在的刷新、搜索）；2026-10-01（2026-09-30 20:40 UTC）直连、匿名再跑一遍并做弹幕探针。都不用代理。
- 真机：播放在 K90 上看过（2026-10-01 两轮真机测试，[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节网易 CC 一行“播放：完成，K90 看过”；弹幕“无”）。

## 留下的问题

- 弹幕（UPGRADES 附录 C 的 C-22，部分完成）：密钥库可存 CC Cookie（J02.1），账号列表有 CC Cookie 页（K01.1，标明暂未用于请求）；余下 `CcSite` 和 CC 弹幕接上 Cookie 后试登录用户的 `{2, 2}` 再“加入房间” → 未排，要用户提供登录 Cookie（V03.3 “需要维护者决定”），没有任务管。
- 付费、私密、密码房没有在播的例子（2026-09-29 扫了全站 100 个在播房间），受限类型只填 `none`：没有任务管。
- `ultra`、`standard`、`blueray_5M_avc` 与 3.x 档位的对应是实测核对，没有录成样本（`original`、`medium` 有样本）。
- 分类名“官方房间/专题”（`CcApi.officialLabel`）是平台层给的中文，英文界面仍显示中文 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
- 跨页去重：分区、推荐、搜索都是服务端按偏移分页，翻页之间新开播的房间会把行挤到下一页，留给列表页统一处理，没有单独的任务。
