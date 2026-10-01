# F.5a 已批准升级里还没做的（原 M13.18 收尾）

- 状态：第 1、3、5、6 条完成（2026-10-02，[记录](../records/F.5a-2.md)）；第 2、4 条见其记录
- 档位：可以以后；规模：大
- 功能点：不是 v3 功能（[UPGRADES.md](../../UPGRADES.md) 的余项）（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：多处，见下
- 依赖：F.0～F.4 的“必须”完成后
- 来源：scratchpad `rest/m13_18_closing.md`（没开始）、M13.17 任务说明第 7 项
- 评审页：发评审页（条目多，逐条表态）
- 记录：[records/F.5a.md](../records/F.5a.md)（开发后）

## 要做的（逐条核对代码后再定范围）

1. 回填 `docs/UPGRADES.md` 状态列（约 60 条还写着“余下 M13”或“待做”）。
2. 平台和直播间：A-3 快手详情标题、A-6、B-7 Twitch Cookie 失效提示、B-16 酷狗 PK 对方聊天、11-1 Picarto 恢复时取最好一档、1-1 登录后播放哔哩哔哩轮播、B-14 名字颜色和徽章、8-8 Twitch 按引擎能力请求 HEVC/AV1。
3. 列表：卡片显示开播时间和简介（7-9、10-3、11-5、25-12、33-7）；1-1 轮播和封禁在历史卡片上的标识；搜索翻页共用快照（19-1、24-5、26-1）。
4. `live_core` 收尾（M7.1 留下）：YouTube 和 PandaTV 主列表读法合并、FC2 画质探测交出控制连接、哔哩哔哩轮播从 `play_time` 开始、LiveMe 和 TikTok 租期是否断开。
5. 数据：备份带上网络电视列表、搜索历史、多画面会话（恢复 3.x 备份照旧）；投屏给电视的标题改成“主播 - 标题”（M10 记录说要先问用户）。
6. 文字整理：`*_directory_scope` 目录说明、`audience_*_detail` 改通俗；清理不再引用的旧键；工具箱和账号页的 `i18n('site_$id')` 换成 `platformName`。

WebDAV Digest 已拆到 F.4b。

## 第 1、3、5、6 条的功能对比（2026-10-02）

按授权直接开发（v3 没有的部分都是已批准的升级或记录里的“留给后续”；要选的按 A 做）。投屏标题（第 5 条后半）协调员 2026-10-02 授权按“主播名 - 标题”做。

### 第 1 条：回填 UPGRADES 状态列

- v3：无（文档）。
- v4 现在：约 75 行写着“余下 M13”“待做”“部分完成”，其中多数已在 M13.x、U.x、F.x 做完。
- P1：M13 各页面和界面任务做完后没有回头改状态列（M13.18 收尾没开）。
- c1（修复）：逐行照代码和 `docs/modules/`、`docs/ui/records/`、`docs/features/records/` 核对；做了的写“完成（位置）”，没做的写去向（F.5a 其他条、F.x、受阻、不做）。本任务做掉的条目一起改。
- 测试：无（文档）。

### 第 3 条：列表

| v3 的行为 | 位置 |
|---|---|
| 卡片信息区只有标题和主播名；房间没有开播时间字段 | `lib/common/widgets/room_card.dart:1172-1221` |
| 观看历史用同一张卡片；v3 没有轮播、封禁状态 | `lib/modules/history/history_page.dart:219` |
| SHOWROOM 目录 30 秒内共用一份快照；搜索第 1 页新搜，之后 `_currentPage + 1` | `lib/core/site/showroom/showroom_site.dart:52`、`lib/modules/search/search_controller.dart:220-227` |

v4 现在：
- `AudiencePolicy.cardOf(room, now:)` 有 `now` 时把“已播 N”接在主播名后（`shared/rooms/room_cards.dart:82`）。只有关注页传了 `now`（`features/favorite/favorite_page.dart:448`、`:531`）；推荐和分区房间（`shared/rooms/room_grid.dart:601`）、搜索（`features/search/search_view.dart:587`）、观看历史（`features/history/history_page.dart:440-442`）都没传。
- 简介：`LiveRoom.introduction` 有值，但 U.4a 卡片信息区只有标题、主播名两行，长按对话框也去掉了简介（U.4a 记录“和设计不一样的地方”第 1 条）。
- 历史卡片走 `cardOf` → `roomMark`（`shared/rooms/room_texts.dart:129`），轮播、已封禁、平台已下线已标在封面左下（U.5c 换卡片时带上的），没有测试。
- 搜索：新搜索请求第 1 页、翻页 `_page + 1`（`features/search/search_model.dart:286`、`:298`），经 `searchRoomsWithCancellation` 到平台的 `searchRoomsCancellable`：SHOWROOM、FC2 第 1 页取新快照，之后的页在 30 / 20 秒内共用（`showroom_site.dart:246-251`、`fc2live_site.dart:265-270`）；BIGO 搜索一直用目录那份（`bigo_site.dart:328`）。所以搜索翻页已经共用快照，M13.5 写“余下搜索页”时没有核对，也没有测试。

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 推荐、分区房间、搜索的卡片不显示开播时间（7-9、10-3、25-12、33-7） | `RoomGridCard` 只在调用方传 `now` 时显示，M13.1、M13.5、U.5a 没传 |
| P2 | 卡片不显示简介（11-5） | U.4a 设计的信息区只有两行，没有简介的位置 |
| P3 | 历史卡片的轮播 / 封禁标识、搜索翻页共用快照都已做到，但没有测试，UPGRADES 仍写“余下” | 做的任务没有专门核对这几条 |

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 增强 | `RoomGridCard` 没传 `now` 时取共用时钟（`roomClockProvider`，测试可换）：推荐、分区房间、搜索的直播中卡片在主播名后显示“已播 N”，和关注页同一个位置、同一种写法；不加定时器，随页面重建更新 | P1 |
| c2 | 保留 | 简介不上卡片（照 U.4a 信息位，不硬加），写进记录；要显示得先改 U.4a 设计 | P2 |
| c3 | 保留 | 历史卡片的轮播、已封禁标识，补测试 | P3 |
| c4 | 保留 | 搜索翻页共用快照，补测试（真的 SHOWROOM 适配器 + 假网络：第 1 页取一次，翻页不再取，再搜一次取新的） | P3 |

需要选的：A1（建议）观看历史卡片不显示“已播”（历史是上次看时的快照，刷新前时间会过时）；B 也显示。

测试和 K90：c1 推荐页和搜索的卡片显示“已播 12 分钟”、没开播或没开播时间的不显示；c3、c4 如上。K90：推荐页 AcFun 卡片主播名后有“已播”；搜索 AcFun 关键词同样；观看记录里一个哔哩哔哩轮播房间标“轮播”。

风险：没有新的常驻任务；时间只在页面重建时更新（同关注页）；主播名很长时“已播”会被省略号挤掉（同关注页）。

### 第 5 条：数据

| v3 的行为 | 位置 |
|---|---|
| 完整备份的分区：`favorite`、`history`、`iptv`（只有网络电视的设置）、`tags`、`webdav`、`cookie`；没有网络电视列表；v3 没有搜索记录和多画面会话 | `lib/common/services/settings/backup_controller.dart:56-90` |
| 恢复按分区名逐个解析，不认识的分区不管 | 同文件 `:185-196` |
| 投屏只给地址，电视上的标题就是地址 | `lib/modules/live_play/dialogs/live_dlna_dialog.dart:56-57` |

v4 现在：
- `exportBackup` 在 `BackupService.exportAll` 的结果上加了 `search` 分区（搜索记录，M13.10，`shared/backup/backup_data.dart:28-44`），本地备份和 WebDAV 都走它。
- 网络电视列表在 `iptv_*` 表（M12.1，`app/iptv_library.dart`），多画面上次的会话在 `meta` 的 `multiview.session`（`features/multiview/logic/multiview_controller.dart:170`、`:354`），都不在备份里（M12.1、M13.12 记录“留给后续”）。
- 投屏：`DlnaCastController` 只调 `setSource(地址)`（`packages/live_cast/lib/src/controller.dart:346`），`DlnaRenderer.setSource` 建的 `CastMedia` 没有标题（`renderer.dart:191`），元数据标题回退成地址（`renderer.dart:44`）。

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 换设备或重装后网络电视列表要重新导入 | 备份只写 `BackupService` 的分区和搜索记录，IPTV 库是 M12.1 后加的 |
| P2 | 多画面“上次看的直播间”恢复不了 | 同上，M13.12 留给后续 |
| P3 | 电视上显示一串地址 | M10 没接标题（当时要先问用户） |

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 增强 | 完整备份加 `iptvLibrary` 分区：播放列表（不含内置的“hot”）连同频道（保留频道 id，关注的电视频道仍对得上）和节目单对应关系；节目单源只存名字和地址。恢复时文件里有这个分区就把播放列表换成文件里的（同 id 覆盖、文件里没有的删掉、内置的不动），节目单源只补上没有的（节目内容下次同步再取）；3.x 的备份没有这个分区，不动。分区名不用 `iptv`（3.x 的网络电视设置在那里）。预览多一行“网络电视列表” | P1 |
| c2 | 增强 | 完整备份加 `multiview` 分区（上次的布局、省流、弹幕开关和各格房间）；恢复时替换，3.x 的备份不动；预览多一行“多画面” | P2 |
| c3 | 保留 | 搜索记录照旧（M13.10），本条只核对 | — |
| c4 | 修复 | 投屏标题“主播名 - 直播间标题”（主播名为空只写标题，都为空照旧用地址）。`live_cast` 加可选接口 `CastMediaTarget`（`setMedia`），`DlnaRenderer` 实现；控制器有标题时用它；直播间的投屏传房间的主播名和标题 | P3 |

需要选的：
- A1（建议）播放列表恢复时整份替换（同关注、历史）；B 只补上没有的。
- A2（建议）带上频道（恢复后不联网就能看，关注的频道对得上；几千个频道的列表约多 1 MB）；B 只带地址，恢复后要同步。
- A3（建议）节目单源只带地址，节目内容不进备份（量大，重新同步即可）；B 连节目一起带。

测试和 K90：单元测试覆盖导出、预览、恢复、3.x 备份不动、内置列表不动、投屏标题拼法和控制器发出的元数据。K90：完整备份 → 删一个播放列表、关掉多画面 → 恢复，列表和“恢复上次”回来；投屏到电视看标题（要用户的电视，TASKS 第 5 节投屏条目）。

风险：备份文件随频道数变大；3.x 读 v4 的文件时忽略新分区；设备同步和同步到电视走 `BackupService`（不在本任务目录），不带这三样，写进记录。

### 第 6 条：文字整理

| v3 的行为 | 位置 |
|---|---|
| 目录说明、人数口径说明是开发说明式的原文（“原生会话分页”“cvExposure”“view_num”） | `assets/translations/zh.json:1590`（`audience_bilibili_detail`）、`:1843`（`showroom_directory_scope`）等 |

v4 现在：
- 分区房间页顶部说明读 `*_directory_scope`（`features/area_rooms/area_rooms_page.dart:96`），推荐页没有改写的平台也读（`features/popular/popular_grid.dart:17`）；设置“各平台口径说明”读 `audience_<id>_detail`（`features/settings/audience_pages.dart:196`）。推荐页的 `popular_scope_*` U.4b 已改通俗。
- 账号页 `i18n(nameKey ?? 'site_$id')`（`features/account/account_platforms.dart:71`）、工具箱支持平台列表 `i18nOr('site_${site.id}', site.name)`（`shared/links/supported_platforms.dart:61`）没走 `platformName`（M12.2 统一的入口）。
- 翻译文件中英各约 830 个键代码里已经没人用（3.x 的旧页面、Firebase、v4 改版前的文字，如 U.12 记录的 `shield_tab_*`、`shield_clear*`、`version_history_desc`、`about_installed_version`、`version_file_size`）。

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 说明是开发笔记，部分已经不准（14-6 映客“部分在播间暂无公开播放地址”、克拉克拉“弹幕暂未接入”、20-6 CHZZK“包含边界项的游标分页”） | 照搬 v3 原文，UPGRADES“说明文字”留给 M13 |
| P2 | 平台名两套入口 | M12.2 统一时这两处没换 |
| P3 | 不用的键占翻译文件三成，改文字时容易改错 | 页面改版后旧键没删（U.8、U.12 记录“留在翻译文件里”） |

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修复 | `*_directory_scope` 改写：这个列表是什么、不包括什么、人数什么意思；中英都改，去掉不准的说法 | P1 |
| c2 | 修复 | `audience_*_detail` 改通俗（不出现接口字段名），口径说明页的开头一句跟着改 | P1 |
| c3 | 修复 | 账号页、工具箱的平台名用 `platformName` | P2 |
| c4 | 修复 | 用脚本找出全仓库代码里没有字面量、也不符合动态拼键（`'site_$id'`、`'room_mark_${…}'` 等）的键，从 zh、en 删掉，清单写进记录 | P3 |

测试：说明文字里没有接口字段名（ASCII 下划线词）；代码里 `i18n('…')` 用到的键在 zh、en 里都有（删键的保护）；账号、工具箱的平台名测试照旧。K90：分区页（SHOWROOM、FC2）顶部说明、设置“各平台口径说明”看文字。

风险：别的分支如果用到了被删的旧键，合并后会显示键名；上面“用到的键都在”的测试会在合并后的门禁里查出来。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 第 1、3、5、6 条写功能对比、开发完成（投屏标题按协调员授权一起做），待 K90 验证 |
