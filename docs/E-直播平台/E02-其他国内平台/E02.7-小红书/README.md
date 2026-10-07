# E02.7 小红书

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 16-1～16-5，16-5 受阻）记在 [record.md](record.md)
- 旧编号：M4.16、M4.U.16、T02b.7
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（受限类型、按主播关注的统一原则）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)（`xhsdiscover://` 深链、`xhslink.com` 短链、链接后的中文截断）；弹幕：平台不提供（匿名分享页的 `comments` 为空，评论接口要签名），D01 里没有小红书的任务；画质 id 迁移在 J02.1；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/xiaohongshu/`（`xiaohongshu_api.dart` 675 行解析、链接和公告文字，`xiaohongshu_site.dart` 256 行请求编排）；样本 `fixtures/xiaohongshu/`（ls 共 5 项：4 组接口录制（在播、已结束、不存在的分享页和失效短链），另有 `legacy_expected.dart` 补出 3.x 冻结输出）；应用在 `apps/pure_live/lib/app/platforms.dart:167` 建 `XiaohongshuSite(http)`，弹幕登记表不登记小红书（同文件 `:191-195` 的注释）

## 目标

把 3.x 的小红书适配器（`lib/core/site/xiaohongshu/` 四个文件共 642 行）重构进 `live_core`。小红书只能“按链接看”：网页的直播列表要登录签名（`x-s`），匿名拿不到目录；房间就是公开分享页，每场直播一个新房间号，关注跟踪的是这一场。修掉 3.x 的 12 个问题（字段写成字符串的页面整个打不开、一个拉流地址不合规整个房间失败、搜索卡片取不了画质、不存在的房间报笼统错误等）。

## 平台接口要点

| 功能 | 接口 | 位置 |
|---|---|---|
| 目录 | 永远是空的，不发请求；目录说明键 `xiaohongshu_directory_scope`（文字 `XiaohongshuApi.directoryScope`） | `xiaohongshu_site.dart:54`、`:91-100`；`xiaohongshu_api.dart:154` |
| 详情 | 分享页 `www.xiaohongshu.com/livestream/<房间号>`，匿名 GET，`Referer` + 安卓 Chrome 87 UA，不跟随跳转，页面超过 2 MiB 是 `ApiChanged`；读页面里唯一的 `window.__INITIAL_STATE__=` 脚本（裸 `undefined` 换 `null` 后按 JSON 解析，不执行脚本）；`roomInfo.status` 2 且 `liveStatus` `success` 是直播，3 且 `end` 是已结束；`pageStatus: "error"` 是 `NotFound`；进房、刷新、录制、状态查询、搜索都是这一个请求；结束页的 `nextRoomInfo`（平台推荐的别人的直播）从不读取 | `xiaohongshu_site.dart:61`、`:78`、`:163-185`；`xiaohongshu_api.dart:209`、`:290`、`:313` |
| 受限 | 网页脚本里的枚举：`monetizeType` 非 0 是付费（取流 `StreamUnavailable`），`joinLimitTypes` 的非 0 项是群聊、`Family`（取流 `StreamUnavailable`）和限定地区（`RegionBlocked`）；字段缺失是“访问情况不明”（`NeedsLogin`）；受限和不明的都不读拉流地址；公开但没有地址的标 `unplayable` | `xiaohongshu_api.dart:18`、`:345`、`:382-398` |
| 画质和线路 | `pullConfig` 按 `quality_type` 分档（录到的只有 `HD`，名字用页面的 `quality_type_name`“原画”），H.264 线路在前、H.265 在后（标 `hevc`），每种编码里 FLV 在 HLS 前；线路编号 `<格式>:<主机第一段>`；地址是没有签名的 http（FLV 先 302 到 CDN 节点），没有租期；一行不合规只跳过这一行；恢复时重新读分享页；旧 id `h264:HD`、`h265:HD` 也认 | `xiaohongshu_site.dart:198-224`；`xiaohongshu_api.dart:165-172`、`:415`、`:444`、`:476`、`:492`、`:514` |
| 搜索 | 只做精确查找：房间号、分享页链接、App 深链直接得号；`xhslink.com` 短链在 12 秒内逐跳读 `Location`，只在 `xhslink.com` 内继续；找不到房间（含“未找到直播间”）返回空结果 | `xiaohongshu_site.dart:113`、`:127`、`:141` |
| 链接 | 分享页 `/livestream/<号>`、`/livestream/dynpath<8 位>/<号>`、`/hina/livestream/<号>`；深链 `xhsdiscover://live_audience?room_id=<号>`（16-2 起不再要求 `source`）；短链 `xhslink.com/<码>`、`/m/<码>`（`needsResolving`、`resolveUrl`）；分享文本里的链接遇到中文标点截断；落不到小红书房间就没有结果，不交给别的平台 | `xiaohongshu_site.dart:237-255`；`xiaohongshu_api.dart:525-621` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/xiaohongshu/`） | 现在（`packages/live_core/lib/src/sites/xiaohongshu/`） | 说明 |
|---|---|---|---|
| 页面解析 | `xiaohongshu_share.dart:157-179` 要求整数，`"status":"2"` 这样的页面整个打不开 | 整数写成字符串也接受 | 3.x 问题 1 |
| 拉流地址校验 | `xiaohongshu_share.dart:187-246` 读页面时就校验，一行不合规进房、刷新、搜索全失败 | 取流时才校验，一行不合规只跳过它 | 3.x 问题 2；16-4 |
| 没有 `data` 的房间 | `xiaohongshu_site.dart:121-126`（`_snapshot`）取画质报 identity 错误 | 先读一次分享页 | 3.x 问题 3 |
| 不存在 | `xiaohongshu_share.dart:148` 笼统的 `api` 错误；搜索报错 | `NotFound`；搜索给空结果 | 3.x 问题 5；16-1 |
| 画质 | 按编码分档：`原画 · H264`、`原画 · H265`，id `h264:HD`；HLS 在前 | 一档“原画”（id `HD`），H.264 线路在前、FLV 在前 | 16-3；旧 id 用 `XiaohongshuApi.qualityIdFromLegacy` |
| 深链 | 必须带 `source` | 只要 `room_id` | 16-2 |
| 受限房间取流 | 一律 `NeedsLogin` | 按受限类型报（付费、私密、限定地区） | 统一原则 |
| 公告文字 | 3.x `zh.json` 的开发说明式原文（“以直播房间号跟踪”“非已验证的实时在线人数”） | 改成通俗说法（`XiaohongshuApi.roomScopeNotice`、`restrictedNotice`，人数如“小红书显示 300万+ 人看过（累计的约数，不是在线人数）”） | 统一原则“说明文字” |
| 短链会话 | `common/utils/live_short_link_session.dart:7` 每次新建 Dio，不走代理 | 共用 `ShortLinkSession`，以 `xiaohongshu` 的名义走本平台的代理 | 3.x 问题 9 |
| 弹幕 | `xiaohongshu_site.dart:34` `getDanmaku()` 是 `EmptyDanmaku` | 不登记 | 无变化 |

## 结果

- 首次重构（2026-09-28，提交 `3982eaa0e`）：12 个 3.x 问题、11 条有意差异见 record.md；页面解析照 3.x 的严格程度（页面超过 2 MiB、字段超过 4096 字是 `ApiChanged`）。
- 升级落地（2026-09-29，`fc41c1a1d`）：16-1～16-4 完成；16-5“跟随主播”受阻（见“留下的问题”）；平台不提供开播时间；受限类型按网页脚本的枚举；公告和目录说明改写。请求数没有变化。没有新样本。
- 测试：`packages/live_core/test/sites/xiaohongshu_api_test.dart` 45 个 `test(` 写法、`xiaohongshu_site_test.dart` 46 个（record.md 按实际用例统计 245 个：135 + 110，多数是循环生成的）。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（`notice` 逐行核对只是换了说法）；字符串整数、8 种不合规地址和 7 种不完整的行只跳过一行、旧画质 id、深链没有 `source`、短链逐跳、不存在给空结果；受限类型用合成回答。
- 真实接口：2026-09-28 17:50～18:05 UTC 直连只读请求了已结束和在播的分享页、主播主页、4 个网页直播接口、网页脚本、在播房间的 FLV 和 HLS 地址（16-5 的结论来自这里）；新代码解析两张新页面正常（在播一档“原画”，3 条 FLV 在前、HLS 在后，`none`）。读到的页面没有录成样本。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节小红书一行：播放“完成”，弹幕“无”，搜索“只能按房间号查”，分区“无（v3 同）”，关注“只能按场次”）。

## 留下的问题

- 16-5 跟随主播（UPGRADES 16-5，受阻）：按主播找当前直播要登录 Cookie 或网页签名（主播主页匿名 302 到验证码页或登录页，网页直播接口 HTTP 406 要签名，H5 用户信息 HTTP 500），匿名只能从在播页的 `roomInfo.deeplink` 拿到 `host_id`（24 位十六进制）；以后有接口时按 record.md“身份迁移规则”迁移，已结束的单场关注换不了。没有任务管。
- 受限类型没有真实页面，只有合成回答；`Family` 的确切含义网页没有说明。
- 公告、目录说明、人数说明是平台层给的中文，英文界面仍显示中文 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
- 没有目录、没有开播时间、没有弹幕，是平台限制。
- 录制遇到 `NotFound`（平台提示“请稍后再试”）是否重试，由录制按自己的规则定（H01.1）。
