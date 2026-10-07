# E02.8 微博直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 18-1～18-10，18-10 受阻）记在 [record.md](record.md)
- 旧编号：M4.18、M4.U.18、T02b.8
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（受限的直播仍是直播，回放 + `unplayable`）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)（`t.cn` 短链）；弹幕：平台匿名没有找到实时评论通道，D01 里没有微博的任务；回放点播的播放在 G02.1，直播间按点播播放在 C01.1；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/weibo/`（`weibo_api.dart` 665 行解析、链接和公告文字，`weibo_site.dart` 347 行请求编排）；样本 `fixtures/weibo/`（ls 共 13 项：12 组接口录制，另有 `legacy_expected.dart` 补出 3.x 冻结输出）；应用在 `apps/pure_live/lib/app/platforms.dart:169` 建 `WeiboSite(http)`，弹幕登记表不登记微博（同文件 `:191-195` 的注释）

## 目标

把 3.x 的微博直播适配器（`lib/core/site/weibo/` 三个文件共 631 行）重构进 `live_core`。微博只有一份公开推荐快照和单场房间接口，房间号是场次号（关注跟踪的是这一场）。修掉 3.x 的 16 个问题（旧场次链接被拒、不存在的场次报“接口错误”、回放取画质返回空列表、一张图片地址不规范整页失败等）；升级落地后推荐从 9 条变成约 50 条、受限的直播标直播中、公开回放能播放录像、认 `t.cn` 短链。

## 平台接口要点

| 功能 | 接口（`weibo.com/l/!/2/wblive/` 下两个匿名 GET，`Referer: https://weibo.com/l/wblive/`、UA `Mozilla/5.0`，不跟随跳转，回答最多 1 MiB） | 位置 |
|---|---|---|
| 分类 | 一个“微博直播”分类、一个“公开推荐”分区，不发请求；目录说明键 `weibo_directory_scope`（文字 `WeiboApi.directoryScope`） | `weibo_site.dart:59`、`:98`；`weibo_api.dart:190`、`:251` |
| 推荐 | `pc_recommend/list.json?count=100&uid=`（约 51 条，只收录在播场次，卡片标直播中，没有人数、受限类型和开播时间）；推荐和分区是同一个快照，只有一页，第 2 页起为空且不请求 | `weibo_site.dart:107-128`；`weibo_api.dart:95`、`:280` |
| 搜索 | 场次号或直播链接直接查房间；`t.cn` 短链先请求一次再查房间（共 2 个请求）；其他关键词在推荐快照里按昵称过滤（去空白、不分大小写，HTML 实体解码后比较）；不存在的场次是空结果 | `weibo_site.dart:136`、`:153`、`:182`；`weibo_api.dart:314`、`:536` |
| 详情 | `room/show_pc_live.json?live_id=<场次号>`：`status` 1 直播、3 回放、5 未开播；`watch_limit` 不为 0 或 `play_switch` 为 0 时状态照 `status` 给，另标受限类型（8 仅限 App、10 仅好友、11 仅主播本人、12 付费，其他和播放关闭是 `unplayable`），平台说明 `pay_dialog_info.buy_tip` 记进 `WeiboRoomData.tip`；`error_code` 27401 是 `NotFound`；进房、关注刷新、录制都是这一个请求；头像先用 1024 px 的 `user.avatar` | `weibo_site.dart:206`、`:215-231`；`weibo_api.dart:124-150`、`:342`、`:415`、`:428` |
| 画质和线路 | 直播一档“原始流”（id `original`），每次取流和恢复重新读房间、核对主播，线路是 FLV（HLS 字段真是 m3u8 时作第二条），请求头为空（3.x 播放层没有微博分支，实测不带 UA 也能拉），没有租期；公开回放一档“原画”（id `replay`），一条 `replay_origin_url` 的 HLS 点播线路（http 换成 https），进房时已在房间数据里，不再请求；受限、播放关闭、已结束取流报 `StreamUnavailable`（带受限类型和平台原话） | `weibo_site.dart:248-318`；`weibo_api.dart:117`、`:194-198`、`:447`、`:496-525` |
| 链接 | `weibo.com/l/wblive/p/show/<场次号>`、`/l/wblive/m/show/<场次号>`、媒体中心旧链接 `live.media.weibo.com/live/show?id=`；`t.cn` 短链只读一次响应头（`needsResolving`、`resolveUrl`），落到别的平台交回所有平台再认（18-9） | `weibo_site.dart:327-344`；`weibo_api.dart:555`、`:579`、`:594` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/weibo/`） | 现在（`packages/live_core/lib/src/sites/weibo/`） | 说明 |
|---|---|---|---|
| 场次号 | `weibo_api.dart:203-209`（`validateLiveId`）、`weibo_link.dart:8-29` 只认 `1022:232132` + 16 位数字和 `1042152:` + 32 位十六进制，旧场次在请求前就被拒 | `weibo_api.dart:156` 写法放宽，另认媒体中心旧链接 | 3.x 问题 1 |
| 推荐 | `weibo_api.dart:187` `count=10`（平台只给 9 条），状态“未知” | `count=100`，直播中 | 18-1、18-2 |
| 状态 | 只认 1、3；受限一律“未知” | 5 是未开播；受限照 `status` 给并标受限类型 | 18-3、18-4 |
| 回放 | 显示为回放，取画质返回空列表 | 有录像就播放（点播），没有的归未开播并标 `unplayable` | 18-5 |
| 不存在 | `weibo_api.dart:257-262` HTTP 200 + 27401 当“接口错误”，精确搜索整个失败 | `NotFound`，搜索为空 | 3.x 问题 2 |
| 图片和校验 | 一张图片地址不规范或少一个用不到的字段，整页或整个房间失败 | 图片经 `normalizeImageUrl`，坏行只跳过 | 3.x 问题 6、16；18-8 |
| 头像 | 50 px 的 `profileImageUrl` | 先用 1024 px 的 `user.avatar` | 18-6 |
| 标题、昵称 | 不解码 HTML 字符 | `decodeHtmlEntities` | 18-7 |
| 画质对象 | `weibo_site.dart:16-20`（`_WeiboChoice`）带房间身份，列表卡片取流报“身份错误” | 只比 id，没有详情的房间先读一次 | 3.x 问题 8 |
| 短链 | 不认 `t.cn` | 认 | 18-9 |
| 公告文字 | “收藏跟踪当前直播场次，不是主播账号……” | 改成通俗说法，并把“访问限制”“播放关闭”拆成两行（`WeiboApi.roomScopeNotice`、`restrictedNotice`、`disabledNotice`） | 统一原则“说明文字” |
| 弹幕 | `weibo_site.dart:42` `getDanmaku()` 是 `EmptyDanmaku` | 不登记 | 无变化 |

## 结果

- 首次重构（2026-09-28，提交 `d104f69e9`）：16 个 3.x 问题、10 条有意差异见 record.md；补录了 3.x 实际发的 `count=10` 推荐和它的第一个房间。
- 升级落地（2026-09-29，`de3404bbe`）：18-1～18-9 完成；18-10“按主播跟随”受阻；开播时间取 `startTime`（毫秒，只在直播中）；新样本 4 个（`S04-shortlink`、`S04-shortlink-missing`、`S04-shortlink-room`、`S04-self-only-replay`）。另记：`/l/pc/anchor/live?live_id=` 对受限场次也给地址，用它等于绕过观看限制，适配器不用。没有画质、身份、设置要迁移。
- 界面接上：回放按点播播放（G02.1、C01.1）；受限标记和播放失败的说明（C01.1，`room_status.dart` 的 `restrictionReason`）。
- 测试：`packages/live_core/test/sites/weibo_api_test.dart` 44 个 `test(` 写法、`weibo_site_test.dart` 41 个（record.md 按实际用例统计 183 个：114 + 69）。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出；旧场次号、27401、13 种受限和回放组合、`watch_limit` 各值的类型和说明、回放录像、`t.cn` 短链（认 5 种、不认 13 种）、坏行跳过、请求数。
- 真实接口：2026-09-28 18:40～19:00 UTC 直连、匿名只读请求了推荐 `count=100`（51 条）、5 个 `t.cn` 短链、回放 m3u8 和第一个分片、PC 和手机版网页播放器脚本、找主播当前直播的几条路。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节微博直播一行：播放“完成”，弹幕“无”，搜索“只能按房间号查”，关注“只能按场次”，备注“18-10 按主播关注受阻”）。

## 留下的问题

- 18-10 按主播跟随（UPGRADES 18-10，受阻）：按主播找当前直播要访客 Cookie 或登录（`show_pc_live` 和 `/l/pc/anchor/live` 不认 `uid`，主页、时间线跳访客验证或 403，手机版接口 HTTP 432）；房间接口对任何状态都给主播 `user.uid`，以后有接口可以逐个换成主播（不存在的场次保留原样）。没有任务管。
- 搜索页说明：record.md 指出的 `search_coverage_weibo` 已换成 `search_scope_weibo`（`apps/pure_live/lib/features/search/search_capability.dart:123`），但中文仍写“开播状态进入后确认”，没提 `t.cn` 短链；推荐卡片现在就是直播中，可以顺手改。没有任务管。
- 弹幕：PC 网页播放器在直播中用 `webim` 模块按场次号收弹幕，没有验证匿名能否连上，线索留给以后（D01 没有任务）。
- 预告（网页脚本里状态 0，倒数计时）没有样本，照 3.x 仍是“未知”。
- 公告、目录说明、分区名“公开推荐”、画质名“原始流”是平台层给的中文，英文界面仍显示中文 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
