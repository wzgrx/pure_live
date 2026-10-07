# E01.4 抖音

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 4-1）、国内平台完善（2026-10-01）和附录 C 落地（C-12、C-13）都记在 [record.md](record.md)
- 旧编号：M4.04、M4.U.4、T02a.4
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；弹幕 D01.5（用这里的 X-Bogus）；竖屏比例预判 G04.1（读这里的 `stream_url`）；巡检 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/douyin/`（`douyin_api.dart` 1265 行解析，`douyin_site.dart` 867 行请求编排、会话和链接，`douyin_sign.dart` 437 行签名）；样本 `fixtures/douyin/`（23 组，含弹幕 `danmaku/S13-live`）

## 目标

把 3.x 的抖音适配器（`lib/core/site/douyin/douyin_site.dart` 904 行、`douyin_search.dart` 599 行、`douyin_audience.dart` 58 行，签名在 `lib/utils/douyin/abogus.dart` 和弹幕的 `xbogus.dart`）重构进 `live_core`：推荐、分类和分区、搜索、详情（enter、reflow、房间页三条路）、清晰度和线路、恢复、账号、链接都和 3.x 一样能用；签名保持纯 Dart、逐位和 3.x 一致。修掉 3.x 的 22 个问题（换号后要重启才生效、在线人数被标成累计观看、综合搜索永远失败、推荐翻页重复追加、房间不存在报“发送HEAD请求失败”等）。

## 平台接口要点

| 功能 | 接口（`live.douyin.com` 除非另写） | 位置 |
|---|---|---|
| 会话 | 每个 Cookie 一个会话，Cookie 一变就换；匿名 `ttwid` 从首页 `/?from_nav=1` 取，每个会话只取一次、并发共用；首页没下发时 5 分钟内不再拉 | `douyin_site.dart:45` |
| 签名 | msToken（184 个随机字符）、a_bogus（SM3 自己实现，常量表逐位照搬）用在 enter 和分区；X-Bogus 给弹幕（`DouyinSigner.danmakuSignature`）；时钟和随机数可注入 | `douyin_sign.dart` |
| 分类 | 首页 `categoryData`（8 个一级分类；“游戏”下 7 个子分类和约 148 个具体游戏，C-12） | `:211` |
| 分区房间 | `/webcast/web/partition/detail/room/v2/`（a_bogus 签名，`partition=<id_str>`、`partition_type=<type>`）；遇到滑块改请求 `webcast.amemv.com` 同一路径一次 | `:17`、`:222-283` |
| 推荐 | `/webcast/feed/`，没有页码，每次随机抽样；第 2 页起只给没出现过的，最多连抽 3 次凑够 15 个（C-13） | `:326`、`:350` |
| 搜索 | 依次试 `www.douyin.com/aweme/v1/web/live/search/`、`…/general/search/stream/`（分块正文）、`/webcast/web/partition/search/` 分区匹配（匿名时前两个回 2483“请先登录”）；主播搜索返回空（界面隐藏） | `:376`、`:385-429` |
| 详情 | 先 `/webcast/room/web/enter/`（a_bogus），失败（不存在除外）再抓房间页（RSC 流式载荷，解开 `"$13"` 引用）；用本场 room_id 请求时走 `webcast.amemv.com/webcast/room/reflow/info/`，房间号换成主播的 web_rid | `:531`、`:552`、`:563`、`:615` |
| 开播时间 | enter 没有；直播中且还没有开播时间时按本场 room_id 多发一次 reflow（最多等 3 秒，结果按场次记住最多 64 场） | `:615-659` |
| 画质和线路 | 地址随详情下发；按 sdk_key 关联、排除纯音频档、按语义等级排序、相同地址的别名只留一个；先 FLV 后 HLS（线路编号 `flv`、`hls`、`flv-2`……）；有效期从 `expire`、`volcTime`、`wsTime + keeptime`、`k + t` 读出（实测 7 天），提前 min(10 分钟, 寿命 / 4) 续期；恢复时重新取详情 | `:686-717`；`DouyinRoomData` |
| 账号 | `/webcast/user/me/`，20003 是 `NeedsLogin` | `:743` |
| 链接 | `live.douyin.com/<web_rid>`、`www.douyin.com/<web_rid>`；`v.douyin.com` 短链和 `webcast.amemv.com/…/reflow/<room_id>` 都换成 web_rid | `:761`、`:782`、`:804` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/douyin/`） | 现在 | 说明 |
|---|---|---|---|
| 会话和 Cookie | `douyin_site.dart:36`、`:46-67` 第一次拿到的 Cookie 存进进程级静态变量，换号要重启；搜索另有一份匿名 Cookie | `CookieVault` 每次读，变了就换会话 | 3.x 问题 1、2、3 |
| 分类 | `getCategores` `:133`，两级 | `douyin_site.dart:211`，“游戏”下多一级具体游戏 | C-12；分区 id 格式 `id_str,type` 不变，3.x 关注的分区原样可用 |
| 分区房间 | `:177`，格式不对的分区号使分区页崩溃 | `:222` | 报 `NotFound`；滑块时转 amemv |
| 推荐 | `:235`，第 2 页把同一批房间再追加一遍 | `:326` | 采用电视版的去重修复，再凑够 15 个 |
| 搜索 | `douyin_search.dart`，任何失败都显示成“没有结果”，综合搜索按单个 JSON 解析必然失败 | `:376` | 分块解析；分区匹配改为签名；最后一步失败报类型化错误 |
| 详情 | `:388`；房间不存在和没有 ttwid 都落到页面兜底，报“发送HEAD请求失败”；页面兜底只剩 4 档画质，简介显示成标题；详情分区一律为空 | `:615` | `NotFound` 不兜底、空正文是 `RiskControl` 照旧兜底；解开引用后画质完整；分区取游戏名或分区路径（2026-10-01 修） |
| 人数 | `douyin_audience.dart:27`、`:42` 不看 `display_type`，在线人数标成累计；取分档文本“2000+” | `douyin_api.dart` 按 `display_type` 归类，先取精确整数 | 3.x 问题 8、9 |
| 取流 | `getPlayQualites` `:664`、`getPlayUrls` `:845`；地址没有有效期，恢复时重开旧地址；请求头在播放层写死 | `:686-717` | 线路带请求头和有效期，恢复重新取详情；下播报 `StreamUnavailable` |
| enter 缺 `status` | 一律当未开播 | 看 `data.room_status`（0 为直播中） | UPGRADES 4-1 |
| 签名 | `lib/utils/douyin/abogus.dart`（依赖 dart_sm）、`xbogus.dart` | `douyin_sign.dart` | a_bogus 4 组、签名地址 2 组、X-Bogus 5 组向量和 3.x 一致；3.x 第 24、25 字段恒为 0 的怪异照旧（服务端接受） |
| 弹幕 | `getDanmaku()` `:28` | `live_danmaku/lib/src/sites/douyin.dart`（D01.5） | 精确在线人数、聊天带发送时间 |

## 结果

- 首次重构（2026-09-28，提交 `6b4a3d35b`；当天另有 `107bd1aa7` 把没有状态的 enter 照 3.x 当未开播）：22 个 3.x 问题见 record.md“审查发现的 v3 问题”，13 条有意差异见“与 v3 的有意差异”。保留 3.x 的做法：推荐卡片没有分区时写“热门推荐”、匿名搜索用分区匹配兜底、媒体请求头带 Cookie、房间号用 web_rid、详情的兜底顺序、搜索卡片封面先用主播大头像。
- 升级落地（2026-09-29，`68de720c2`）：4-1；开播时间取 reflow 的 `start_time`；在播却没有视频档的标 `unplayable`；搜索卡片没有昵称时留空（不再写“抖音直播”）。
- 国内平台完善（2026-10-01，`59602ec7b`）：真实接口检查全部正常（签名仍有效，28 条线路可拉）；修了游戏直播间详情没有分区；进房时补开播时间。附录 C（`49ea1ccc4`）：分区加具体游戏一级、推荐翻页凑满。2026-10-02（`0d63d2d3c`）线路带上声明的画面尺寸，给 G04.1 的竖屏预判用。
- 测试：`packages/live_core/test/sites/douyin_api_test.dart` 46 个 `test(` 写法、`douyin_site_test.dart` 56 个（record.md 统计为 48、68 个用例）；弹幕 `packages/live_danmaku/test/sites/douyin_test.dart` 63 个。

## 验证

- 自动测试：样本逐键对照 3.x，新键 `startedAt`、`restriction` 逐个断言；签名用 3.x 代码原样算出的向量，SM3 另用国标 GB/T 32905-2016 的两个示例；会话并发、Cookie 切换、搜索兜底顺序（请求序列和 3.x 相同）、链接（移植 3.x 四个测试文件里抖音的用例）。
- 真实接口：2026-10-01 跑了推荐、分类、分区两页、搜索、3 个在播和 1 个未开播房间、28 条线路、reflow、两个房间各 2 分钟弹幕；附录 C 时实测游戏分区和推荐凑满（record.md）。
- 真机：播放和弹幕 K90 看过（2026-10-01，[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）。竖屏比例预判缺（F-ROOM-22）归 G04.1。

## 留下的问题

- 礼物：匿名网页端录不到 `WebcastGiftMessage`，没做上报。
- 主播搜索：要登录才有，匿名只有 2483，3.x 也没有。
- 付费、私密直播：`paid_live_data.paid_type`、`basis.secret_room` 在所有看到的房间里都是 0，没有读。
- enter 给的全是 H.264，“优先 H.264”对抖音没有可选的档。
- 3.x 用本场 room_id 存的关注刷新时身份对不上，迁移时可以用 `DouyinApi.isRoomId` 找出来换成 web_rid（交给 J06.1 / J02.1）。
- 接口会变：定期巡检归 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)。
