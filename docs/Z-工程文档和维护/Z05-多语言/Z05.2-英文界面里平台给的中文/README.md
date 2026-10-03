# Z05.2 英文界面下平台层给的文字还是中文

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：已批准升级 [20-10、25-7、25-8、26-6、29-6、30-10](../../../specs/UPGRADES.md)（各平台的公告、分区名“改成用户看得懂的说明”）的余项：中文界面已完成，“英文界面仍显示平台层给的中文 → 多语言（未排）”。V03.3 核对时开了本任务，并对照 3.x 发现范围比这 6 条大。
- 相关：D-005（用户看得到的文字 zh、en 都要有）；Z05.1（翻译键清理，会列出运行时拼出来的键）；各平台任务 E02.x、E03.x（平台层的文字常量）；I02.1、I03.1（目录说明 `LiveDirectoryNotice`）

## 目标

界面语言选英文时，平台层给出、由我们自己写的说明文字（公告、受限说明、目录说明、我们翻译的分区名和画质名、弹幕的系统提示）也是英文；中文界面不变。这是 3.x 的行为：3.x 的平台适配器直接调翻译（`i18n('chzzk_time_machine_notice')`），文字跟界面语言。平台本身给的内容（直播标题、主播名、国内平台的分区名）不翻译。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 平台层的说明文字 | 平台适配器直接调 `i18n`：22 个文件、96 个键，例如 `lib/core/site/chzzk/chzzk_site.dart:246` 的 `i18n('chzzk_time_machine_notice')`、`lib/core/site/pandalive/pandalive_site.dart:83-86`、`:111-114` 的公告、`lib/core/site/fc2live/fc2_site.dart:78-83` 的分区名、`:134-137` 的公告、`:248` 的画质名 | `packages/live_core` 不依赖翻译（ENGINEERING 第 4 节分层），这些文字写成中文常量，例如 `packages/live_core/lib/src/sites/chzzk/chzzk_api.dart:252`、`:256`、`:260`（成人、地区、回看公告），`pandalive/pandalive_api.dart:198-212`（5 条公告）、`:218` 的 `areaNames`，`fc2live/fc2live_api.dart:287` 的 `areaNames`、`:298` 的 `noticeText`、`:435` 的 `areaName`；3.x 的 96 个键在 v4 的翻译文件里只剩 15 个 | 按界面语言给出 |
| 目录说明 | 同上（`*_directory_scope` 等键） | 已有机制：平台实现 `LiveDirectoryNotice`（`packages/live_core/lib/src/live_site.dart:412-415`，只给键 `directoryNoticeKey`），应用翻译（`apps/pure_live/lib/features/popular/popular_grid.dart:17`、`features/area_rooms/area_rooms_page.dart:96`）；20 个平台实现了它 | 不变，作为其他文字的做法参考 |
| 直播间公告的显示 | 详情页显示 `notice` | `apps/pure_live/lib/features/live_play/layout/room_details.dart:158` 显示 `room.notice`；`features/live_play/danmaku/chat_list.dart:948` 没有弹幕的平台在聊天区显示公告或简介 | 显示前换成当前语言 |
| 规模 | — | `packages/live_core`、`live_danmaku`、`live_media`、`live_player`、`live_record`、`live_iptv`、`live_vod` 的代码（不含注释）里带中文的字符串字面量 423 个、73 个文件（含正则、内部用的，第 1 阶段筛） | 列清楚后分批改 |

## 方案

- c1（第 1 阶段）列清单：扫 `packages/*/lib` 的中文字面量，分成四类：A 我们写给用户看的说明（公告、受限说明、聊天区说明）；B 我们翻译的分区名、画质名；C 弹幕的系统提示（如猫耳 FM 的 PK 提示 `packages/live_danmaku/lib/src/sites/missevan.dart:129-130`）；D 不用改的（解析用的正则和关键字、平台原文、国内平台给的分区名、画质偏好匹配用的标准名“原画”等）。对照 3.x 的 96 个键，标出每条在 3.x 里的键名和英文（`git show v3.2.11:assets/translations/en.json`）。清单写进 `record.md`。
- c2 做法（建议 A）：沿用 `LiveDirectoryNotice` 的思路，平台层给**键**而不是文字：`live_core` 里每个说明常量旁边定一个键（照 3.x 的键名，如 `chzzk_time_machine_notice`），`LiveRoom.notice` 仍存中文（关注、备份、3.x 兼容不变），应用显示前用一张“中文常量 → 键”的表（`apps/pure_live/lib/shared/rooms/platform_texts.dart`，由 `live_core` 导出常量建表，不是按文字猜）换成当前语言。B 方案是给 `LiveSite` 注入一个取文字的函数（平台层按语言给），要改 35 个适配器的构造，且关注里存下的文字会混语言，不建议。
- c3（第 2 阶段）公告和说明：A 类全部接上，zh.json 的值就是现在的中文常量（中文界面一个字不变），en.json 写英文（优先用 3.x 的英文，3.x 的英文是开发说明式的要改成用户看得懂的，同 UPGRADES“说明文字”原则）。
- c4（第 3 阶段）分区名和画质名、弹幕系统提示：B、C 类。分区名只翻译我们自己从代码翻出来的（PandaTV、FC2、niconico 等），关注里存的 `area` 照旧；画质名只在显示时换，存下的画质偏好和录制任务的画质名不变（D-018、J02.1 的对照）。

## 性能任务：测量

无：显示前查一张常量表，开销可以忽略。

## 验证

- 自动测试：`apps/pure_live/test/` 加“表里每个键在 zh.json、en.json 都有、zh 的值等于 `live_core` 的常量”的一致性测试（防止以后改了常量忘了改翻译）；直播间详情在英文界面显示英文公告的界面测试（用 `fixtures/chzzk/S06-live-detail-adult`、`S06-live-detail-region` 的样本）。
- 真机：待真机（brief 的真机步骤）。

## 留下的问题

- Z05.1 会清理“不用的键”：本任务加回来的 3.x 键要在 Z05.1 的清单里标成“运行时用到”，两个任务谁后做谁核对。
- 电视外壳（A17）用同一套翻译，做电视时不用另做。
