# Z05.2 英文界面下平台层给的文字还是中文：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `bbd52a2a3` 开始，接在 Z05.1 后面）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 清单 | 做了 | `packages/*/lib`（不含注释）带中文的字面量 501 个（任务书写 423 个，之后各平台任务又加了）：A 44、B 153、C 23、D 244、留下没做 37，逐条见下文“清单”。对照了 3.x 平台层的 96 个键：用得上的沿用 3.x 键名（如 `chzzk_time_machine_notice`、`fc2live_category_*`、`tiktok_quality_*`），3.x 没有的新起（如 `pandalive_fans_notice`、`kick_category_*`、`quality_name_*`） |
| c2 做法 | 做了，按 A | 平台层不改：`live_core`、`live_danmaku` 仍写中文（关注、备份、录制存的都是中文，不迁移数据）。应用新增 `apps/pure_live/lib/shared/rooms/platform_texts.dart`：三张“中文常量 → 键”的表，表里直接引用适配器的常量（`ChzzkApi.adultNotice`、`PandaLiveApi.areaNames['talk']` 等，不按文字猜），加三个显示函数。只在 `live_danmaku` 的 Kick 加了一个常量 `KickDanmakuProtocol.streamEndedNotice`（原来写在代码里的“直播已结束”），文字不变 |
| c3 公告和说明（A） | 做了 | `platformNotice(text)` 按行换：适配器写的行换成当前语言，平台自己的行（主播公告）原样；带数值的一条（小红书“显示 N 人看过”）按模板换。接在直播间详情的公告（`room_details.dart`）、没有弹幕时聊天区的公告（`chat_list.dart`） |
| c4 分区名、画质名、弹幕系统提示（B、C） | 做了大部分 | 分区名 `platformAreaName(platform, name)` 按平台查（同一个“游戏”，PandaTV 的换、国内平台的不换）：接在分区卡片和分区页标题（`areaDisplayName`）、分类标签（`platform_areas_view.dart`）、分区页副标题、直播间顶栏和详情的分区、换台列表。画质名 `platformQualityName(name)`：共用的画质名（`LiveQualityLabel` 的“原画、蓝光、超清……”）和适配器自己起的（“自适应 HLS”“HLS（推荐）”等），`原画 · FLV` 这种逐段换；接在画质按钮和菜单、画质与线路面板（含投屏说明）、多屏的画质菜单和“已降到某画质”提示。弹幕系统提示在 `ChatLine.notice` 换（猫耳 PK 提示、B 站警告和切断、17LIVE 暂停和恢复、Kick 直播结束、Twitch Cookie 失效、niconico 评论解锁）。带参数的弹幕行和画质名没做，见“留给以后” |

## 根因

- 3.x 的适配器直接调 `i18n`（`git show v3.2.11:lib/core/site/chzzk/chzzk_site.dart:244-246`），文字跟界面语言；4.x 按 ENGINEERING 第 4 节把平台层拆成不依赖翻译的纯 Dart 包，这些文字就成了中文常量，界面直接显示 `room.notice`、`area.areaName`、`quality.quality`。

## 改了哪些文件

- 新：`apps/pure_live/lib/shared/rooms/platform_texts.dart`（表和 `platformNotice`、`platformAreaName`、`platformQualityName`）。
- 显示处（每处只改取文字的那一行）：`features/live_play/layout/room_details.dart`、`features/live_play/danmaku/chat_list.dart`、`features/live_play/danmaku/chat_feed.dart`、`features/live_play/layout/room_header.dart`、`features/live_play/switch_room/room_switch_tiles.dart`、`features/live_play/buttons/stream_menu.dart`、`features/live_play/dialogs/stream_dialogs.dart`、`features/areas/areas_common.dart`、`features/areas/platform_areas_view.dart`、`features/area_rooms/area_rooms_page.dart`、`features/multiview/widgets/cell_controls.dart`、`features/multiview/widgets/focus_bar.dart`、`features/multiview/logic/multiview_controller.dart`（都在 `apps/pure_live/lib/` 下）。
- `packages/live_danmaku/lib/src/sites/kick.dart`：`streamEndedNotice` 常量。
- 翻译：两份文件各加 138 个键（zh 2693 个、en 2693 个），按键名排序、4 空格缩进。

## 新设置、翻译键、门禁基线

- 表里 145 个键：说明 44、弹幕提示 22（猫耳“对方未接受邀请”两条共用一个键）、分区和分类 45、画质 34；其中 138 个是新键，7 个（`fc2live_access_restricted`、`fc2live_adult_notice` 和 niconico 的 5 个公告）原来就在文件里。zh 的值就是适配器的常量（中文界面一字不差）。
- 改了已有的 7 个值：zh `niconico_program_scope` 改成适配器现在的文字（原值是 3.x 的“…；弹幕暂未接入。”，这个键以前不显示，常量早已去掉后半句）；en 的 `fc2live_access_restricted`、`fc2live_adult_notice`、`niconico_*` 4 个从 3.x 的开发说明式英文改成用户看得懂的。
- 没有新设置，没有门禁基线变化。

## 测试

- 新增 `apps/pure_live/test/shared/platform_texts_test.dart`（3 个）：表里每个键两份文件都有、zh 等于适配器的常量、en 没有中文、键和文字一一对应；表覆盖适配器自己的词表（`Fc2LiveApi.noticeText`、`NiconicoApi.noticeText`、`PandaLiveApi.areaNames`、`KickApi.categoryNames`、`ChzzkApi.categoryTypeNames`、`SeventeenLiveApi.regions`、`TikTokApi.qualityNames`、`LiveMeApi.qualityNames`、`Fc2LiveApi.tierQualities`、猫耳的 PK 表等，以后加词忘了加键会失败）；英文界面换、平台自己的行不换、国内平台同名分区不换、中文界面全部原样。
- 新增 `apps/pure_live/test/features/live_play/platform_texts_room_test.dart`（1 个界面测试）：英文界面进 PandaTV 直播间，画质按钮是 “Source”，聊天区的“直播已结束”是英文，详情里的成人公告是英文、主播自己的公告原样、分区是 “Talk”。
- “改之前会失败”的验证：把显示处的改动撤掉（表和翻译保留）跑界面测试，在画质按钮一步就失败（找不到 “Source”）；恢复后通过。
- Z05.1 的检查同时通过：新键都在 `platform_texts.dart` 里用引号写出，算“有人用”。
- `packages/live_danmaku`：format、`dart analyze --fatal-infos`、`dart test` 全过（1595 个）；应用：format、`dart analyze --fatal-infos`、全部 `flutter test` 1012 个全过（原 1008 + 新 4）。

## 真机上要看的（待真机）

按 brief 的真机步骤：设置 → 语言 → English 后进 CHZZK、PandaTV、FC2 的直播间看详情公告；分区页看 PandaTV、FC2、niconico 的分区和分类标签（国内平台的分区照旧中文）；猫耳 FM PK 中的直播间看聊天区提示；画质按钮和画质菜单是英文；切回简体中文后全部恢复、和改之前一字不差；英文界面下关注一个 PandaTV 直播间，切回中文看关注页（存的数据不带语言）。

## 留给以后

- 房间卡片、直播间上滑换台的预览（`shared/rooms/room_cards.dart`、`features/live_play/player/room_swipe.dart`）这次没接：前者现在不显示分区，后者是 A07.16 正在改的文件，等它合并后在 `room_swipe.dart:241` 的分区套 `platformAreaName` 即可。电视界面（`lib/tv/`）同理，做 A17 时套同样三个函数。
- `room_controller.dart:614` 的“平台实际返回某画质”提示（G03.1 正在改的文件）没套 `platformQualityName`，合并后补一行。
- 带参数的 37 处（清单“留下没做的”）：Chzzk、Kick、Picarto、YouTube、Kilakila、猫耳的礼物、订阅、置顶、转播行，B 站带原因的“直播间收到警告：…”，以及 `清晰度 N`、`画质 N`、`HLS 码率档 N` 这类带编号的画质名。按文字查表做不到，要让 `live_danmaku` 给出结构化的消息（种类加参数）、画质给编号，由应用按语言拼，是单独的一个任务。
- 目录说明（`*_directory_scope`）本来就按键显示，没动；它们的 zh 值和适配器的 `directoryScope` 常量现在不全相同（各平台任务改过文字），以后可以把它们也加进一致性测试。
- `fc2live_access_restricted` 的中文还是开发说明式（“界面保留受限状态，不将其显示成未开播”），属于平台任务（E 组）改常量的事；英文已写成用户能懂的。

## 清单（c1）

扫描方法：`packages/*/lib/**/*.dart` 去掉注释行后，带中文（含全角标点）的字符串字面量，2026-10-08 共 501 个，79 个文件。A、B、C 每条写键；D 按文件和原因合并（行号列出）。

### A 我们写给用户的说明（公告、受限说明）：44 个

| 位置 | 文字 | 键或原因 |
|---|---|---|
| `live_core/lib/src/sites/baidulive/baidulive_api.dart:401` | 人数是正在观看的人数，主播的粉丝数另外显示。 | `baidulive_chat_notice` |
| `live_core/lib/src/sites/baidulive/baidulive_api.dart:409` | 这场直播需要付费观看或受到平台限制，暂时不能在这里播放。 | `baidulive_restricted_notice` |
| `live_core/lib/src/sites/bigo/bigo_api.dart:355` | 列表里的人数是正在观看的人数；进入直播间后，人数随弹幕更新。 | `bigo_chat_notice` |
| `live_core/lib/src/sites/bigo/bigo_api.dart:360` | Bigo Live 现在要求登录才能观看这个直播间，暂时不能在这里播放。 | `bigo_login_required` |
| `live_core/lib/src/sites/bigo/bigo_api.dart:365` | 这个直播间设置了密码或付费观看，暂时不能在这里播放。 | `bigo_access_restricted` |
| `live_core/lib/src/sites/chzzk/chzzk_api.dart:252` | 成人直播需要登录 CHZZK 并通过年龄验证，本应用暂时无法播放。 | `chzzk_adult_notice` |
| `live_core/lib/src/sites/chzzk/chzzk_api.dart:256` | 当前地区受到播放限制。 | `chzzk_region_notice` |
| `live_core/lib/src/sites/chzzk/chzzk_api.dart:260` | 这场直播在 CHZZK 网页上可以回看，本应用只播放实时画面。 | `chzzk_time_machine_notice` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:299` | 该 FC2 直播需要登录、积分、门票或付费；界面保留受限状态，不将其显示成未开播。 | `fc2live_access_restricted` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:300` | 该房间由平台标记为成人内容，不进入普通公开目录。 | `fc2live_adult_notice` |
| `live_core/lib/src/sites/jdlive/jdlive_api.dart:270` | 列表里的人数是累计观看；直播中连上弹幕后，显示的是正在观看的人数。 | `jdlive_chat_notice` |
| `live_core/lib/src/sites/jdlive/jdlive_api.dart:274` | 这场京东直播只能在京东 App 里观看。 | `jdlive_restricted_notice` |
| `live_core/lib/src/sites/kick/kick_api.dart:162` | 该直播已被 Kick 标记为成人内容（18+）。 | `kick_mature_notice` |
| `live_core/lib/src/sites/kugoulive/kugoulive_api.dart:174` | 人数是正在观看的人数，没有时显示热度；粉丝数单独显示。 | `kugoulive_chat_notice` |
| `live_core/lib/src/sites/kugoulive/kugoulive_api.dart:180` | 这个直播间要登录酷狗才能观看，本应用暂时无法播放。 | `kugoulive_restricted_notice` |
| `live_core/lib/src/sites/liveme/liveme_api.dart:422` | 这里暂时看不到 LiveMe 直播间的聊天。人数分别是热度、正在观看和累计观看。 | `liveme_chat_notice` |
| `live_core/lib/src/sites/looklive/looklive_api.dart:378` | 人数是正在观看的人数，热度另外显示。 | `looklive_chat_notice` |
| `live_core/lib/src/sites/looklive/looklive_api.dart:382` | 这个 LOOK 直播间被平台禁播或正在违规整改，现在不能观看。 | `looklive_banned_notice` |
| `live_core/lib/src/sites/looklive/looklive_api.dart:386` | 这场 LOOK 直播只能在 LOOK App 里观看。 | `looklive_app_only_notice` |
| `live_core/lib/src/sites/looklive/looklive_api.dart:390` | 这场 LOOK 直播要购票才能观看。 | `looklive_paid_notice` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:424` | 节目尚未开始。 | `niconico_scheduled` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:425` | 此节目要求登录官方站点。 | `niconico_login_required` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:426` | 此节目设有地区访问限制。 | `niconico_region_restricted` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:427` | 此节目的当前观看权限受限。 | `niconico_access_restricted` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:428` | 收藏对应本次节目，主播的新节目需重新添加。 | `niconico_program_scope` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:198` | 人数分别是正在观看和本场累计观看。 | `pandalive_chat_notice` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:201` | 成人直播需要登录 PandaTV 并通过本人认证，本应用暂时无法播放。 | `pandalive_adult_notice` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:204` | 这个直播间设了密码，本应用暂时无法播放。 | `pandalive_password_notice` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:208` | 这个直播间只对粉丝开放，本应用暂时无法播放。 | `pandalive_fans_notice` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:212` | 这个直播间有观看限制（例如需要登录），本应用暂时无法播放。 | `pandalive_restricted_notice` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:160` | 17LIVE 要求观看者年满 18 周岁。 | `seventeen_age_notice` |
| `live_core/lib/src/sites/sixroom/sixroom_api.dart:318` | 人数是平台的热度，不是正在观看的人数。 | `sixroom_chat_notice` |
| `live_core/lib/src/sites/sixroom/sixroom_api.dart:322` | 这个六间房直播间是私密房或暂时黑屏，现在不能在这里观看。 | `sixroom_restricted_notice` |
| `live_core/lib/src/sites/steambroadcast/steambroadcast_api.dart:424` | 人数是正在观看的人数。 | `steambroadcast_chat_notice` |
| `live_core/lib/src/sites/steambroadcast/steambroadcast_api.dart:433` | 这位主播的 Steam 账号目前被限制直播，暂时不能观看。 | `steambroadcast_restricted_notice` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:267` | TikTok 直播的评论暂时不能在这里显示。在线人数是正在看的人数，累计是进过直播间的人数。 | `tiktok_chat_notice` |
| `live_core/lib/src/sites/weibo/weibo_api.dart:176` | 微博每场直播都有单独的链接，这里关注的是这一场。主播下次开播时，请重新导入新的直播链接。 | `weibo_room_scope` |
| `live_core/lib/src/sites/weibo/weibo_api.dart:181` | 这场直播设置了观看限制（仅好友、仅主播本人、付费或仅限微博 App），这里无法播放。 | `weibo_restricted` |
| `live_core/lib/src/sites/weibo/weibo_api.dart:185` | 这场直播已关闭播放，这里无法播放。 | `weibo_disabled_notice` |
| `live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart:141` | 小红书每场直播都有新的房间号，这里关注的是这一场。主播下次开播时，请重新导入新的分享链接。 | `xiaohongshu_room_scope` |
| `live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart:145` | 这场直播设置了观看条件（付费、仅限部分观众或限定地区），这里无法播放。 | `xiaohongshu_restricted` |
| `live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart:149` | 暂时无法确认这场直播是否公开，这里可能无法播放。 | `xiaohongshu_unknown_access` |
| `live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart:159` | 小红书显示 $value 人看过（累计的约数，不是在线人数） | `xiaohongshu_display_viewers`（带 `{value}`） |
| `live_core/lib/src/sites/youtube/youtube_api.dart:396` | 仅在直播页给出同时观看人数时显示在线人数，不把累计播放量当作在线人数。 | `youtube_chat_notice` |

### B 我们自己起的分区名、画质名：153 个

| 位置 | 文字 | 键或原因 |
|---|---|---|
| `live_core/lib/src/quality_label.dart:25` | 默认 | `quality_name_default` |
| `live_core/lib/src/quality_label.dart:35` | 默认 | `quality_name_default` |
| `live_core/lib/src/quality_label.dart:41` | 杜比 | `quality_name_dolby` |
| `live_core/lib/src/quality_label.dart:43` | 原画 | `quality_name_original` |
| `live_core/lib/src/quality_label.dart:44` | 蓝光 | `quality_name_bluray` |
| `live_core/lib/src/quality_label.dart:45` | 超清 | `quality_name_super_hd` |
| `live_core/lib/src/quality_label.dart:46` | 高清 | `quality_name_hd` |
| `live_core/lib/src/quality_label.dart:47` | 流畅 | `quality_name_smooth` |
| `live_core/lib/src/quality_label.dart:53` | 原画 | `quality_name_original` |
| `live_core/lib/src/quality_label.dart:54` | 蓝光 | `quality_name_bluray` |
| `live_core/lib/src/quality_label.dart:55` | 超清 | `quality_name_super_hd` |
| `live_core/lib/src/quality_label.dart:56` | 高清 | `quality_name_hd` |
| `live_core/lib/src/quality_label.dart:57` | 标清 | `quality_name_sd` |
| `live_core/lib/src/quality_label.dart:58` | 流畅 | `quality_name_smooth` |
| `live_core/lib/src/quality_label.dart:59` | 自动 | `quality_name_auto` |
| `live_core/lib/src/quality_label.dart:64` | 原画 | `quality_name_original` |
| `live_core/lib/src/quality_label.dart:65` | 蓝光 | `quality_name_bluray` |
| `live_core/lib/src/quality_label.dart:66` | 超清 | `quality_name_super_hd` |
| `live_core/lib/src/quality_label.dart:67` | 高清 | `quality_name_hd` |
| `live_core/lib/src/quality_label.dart:68` | 标清 | `quality_name_sd` |
| `live_core/lib/src/quality_label.dart:69` | 流畅 | `quality_name_smooth` |
| `live_core/lib/src/quality_label.dart:70` | 自动 | `quality_name_auto` |
| `live_core/lib/src/quality_label.dart:75` | 原画 | `quality_name_original` |
| `live_core/lib/src/quality_label.dart:76` | 蓝光 | `quality_name_bluray` |
| `live_core/lib/src/quality_label.dart:77` | 超清 | `quality_name_super_hd` |
| `live_core/lib/src/quality_label.dart:78` | 高清 | `quality_name_hd` |
| `live_core/lib/src/quality_label.dart:79` | 标清 | `quality_name_sd` |
| `live_core/lib/src/quality_label.dart:80` | 流畅 | `quality_name_smooth` |
| `live_core/lib/src/quality_label.dart:81` | 自动 | `quality_name_auto` |
| `live_core/lib/src/quality_label.dart:82` | 默认 | `quality_name_default` |
| `live_core/lib/src/quality_label.dart:93` | 原画 | `quality_name_original` |
| `live_core/lib/src/quality_label.dart:107` | 2K 超清 | `quality_name_2k` |
| `live_core/lib/src/quality_label.dart:108` | 1080P 高清 | `quality_name_1080p` |
| `live_core/lib/src/quality_label.dart:109` | 720P 清晰 | `quality_name_720p` |
| `live_core/lib/src/quality_label.dart:110` | 480P 流畅 | `quality_name_480p` |
| `live_core/lib/src/quality_label.dart:111` | 360P 极速 | `quality_name_360p` |
| `live_core/lib/src/sites/acfun/acfun_api.dart:427` | 高清 | `quality_name_hd` |
| `live_core/lib/src/sites/acfun/acfun_api.dart:428` | 超清 | `quality_name_super_hd` |
| `live_core/lib/src/sites/acfun/acfun_api.dart:429` | 蓝光 | `quality_name_bluray` |
| `live_core/lib/src/sites/acfun/acfun_api.dart:430` | 高码率 | `quality_name_high_bitrate` |
| `live_core/lib/src/sites/baidulive/baidulive_api.dart:946` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/baidulive/baidulive_api.dart:956` | 回放 | `quality_name_replay` |
| `live_core/lib/src/sites/bigo/bigo_api.dart:343` | 公开推荐 | `bigo_category_public` |
| `live_core/lib/src/sites/bigo/bigo_api.dart:371` | 直播自动 | `bigo_quality_live` |
| `live_core/lib/src/sites/cc/cc_api.dart:60` | 官方房间/专题 | `cc_official_entries` |
| `live_core/lib/src/sites/cc/cc_api.dart:555` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/cc/cc_api.dart:556` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/cc/cc_api.dart:557` | 高清 | `quality_name_hd` |
| `live_core/lib/src/sites/cc/cc_api.dart:558` | 标准 | `quality_name_standard` |
| `live_core/lib/src/sites/cc/cc_api.dart:559` | 标准 | `quality_name_standard` |
| `live_core/lib/src/sites/cc/cc_api.dart:560` | 低清 | `quality_name_low` |
| `live_core/lib/src/sites/cc/cc_api.dart:561` | 蓝光 | `quality_name_bluray` |
| `live_core/lib/src/sites/cc/cc_api.dart:624` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/cc/cc_api.dart:624` | 超清 | `quality_name_super_hd` |
| `live_core/lib/src/sites/cc/cc_api.dart:624` | 高清 | `quality_name_hd` |
| `live_core/lib/src/sites/cc/cc_api.dart:624` | 标清 | `quality_name_sd` |
| `live_core/lib/src/sites/cc/cc_api.dart:656` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/chzzk/chzzk_api.dart:243` | 公开热门直播 | `chzzk_public_directory` |
| `live_core/lib/src/sites/chzzk/chzzk_api.dart:281` | 游戏 | `chzzk_category_game` |
| `live_core/lib/src/sites/chzzk/chzzk_api.dart:282` | 娱乐 | `chzzk_category_entertainment` |
| `live_core/lib/src/sites/chzzk/chzzk_api.dart:283` | 体育 | `chzzk_category_sports` |
| `live_core/lib/src/sites/chzzk/chzzk_api.dart:284` | 其他 | `chzzk_category_etc` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:288` | 全部公开直播 | `fc2live_category_all` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:289` | 闲聊 | `fc2live_category_chat` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:290` | 游戏 / 作业 | `fc2live_category_game` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:291` | 视频 | `fc2live_category_video` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:292` | 音频 | `fc2live_category_audio` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:293` | 其他 | `fc2live_category_other` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:317` | 自适应 HLS | `fc2live_quality_auto` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:328` | 超清 3M（β） | `fc2live_quality_3m` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:329` | 超清 2M | `fc2live_quality_2m` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:330` | 高清 | `quality_name_hd` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:331` | 标清 | `quality_name_sd` |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart:332` | 流畅 | `quality_name_smooth` |
| `live_core/lib/src/sites/huya/huya_api.dart:271` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/huya/huya_api.dart:538` | 默认 | `quality_name_default` |
| `live_core/lib/src/sites/huya/huya_api.dart:637` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/inke/inke_api.dart:171` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/jdlive/jdlive_api.dart:245` | 精选直播购物 | `jdlive_category_featured` |
| `live_core/lib/src/sites/jdlive/jdlive_api.dart:283` | HLS（推荐） | `jdlive_quality_hls` |
| `live_core/lib/src/sites/jdlive/jdlive_api.dart:286` | FLV 原始线路 | `quality_name_flv_source` |
| `live_core/lib/src/sites/jdlive/jdlive_api.dart:293` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/kick/kick_api.dart:153` | 游戏 | `kick_category_games` |
| `live_core/lib/src/sites/kick/kick_api.dart:154` | 生活 | `kick_category_irl` |
| `live_core/lib/src/sites/kick/kick_api.dart:155` | 音乐 | `kick_category_music` |
| `live_core/lib/src/sites/kick/kick_api.dart:156` | 博彩 | `kick_category_gambling` |
| `live_core/lib/src/sites/kick/kick_api.dart:157` | 创作 | `kick_category_creative` |
| `live_core/lib/src/sites/kick/kick_api.dart:158` | 其他 | `kick_category_alternative` |
| `live_core/lib/src/sites/kilakila/kilakila_api.dart:427` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/kugoulive/kugoulive_api.dart:225` | 高清 | `quality_name_hd` |
| `live_core/lib/src/sites/liveme/liveme_api.dart:435` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/liveme/liveme_api.dart:436` | 流畅 | `quality_name_smooth` |
| `live_core/lib/src/sites/looklive/looklive_api.dart:351` | 视频直播 | `looklive_category_video` |
| `live_core/lib/src/sites/looklive/looklive_api.dart:354` | 语音直播 | `looklive_category_audio` |
| `live_core/lib/src/sites/looklive/looklive_api.dart:399` | HLS 原始线路 | `quality_name_hls_source` |
| `live_core/lib/src/sites/looklive/looklive_api.dart:402` | FLV 原始线路 | `quality_name_flv_source` |
| `live_core/lib/src/sites/missevan/missevan_api.dart:137` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:408` | 综合 | `niconico_category_common` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:409` | 创作与挑战 | `niconico_category_try` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:410` | 游戏 | `niconico_category_live` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:411` | 视频介绍 | `niconico_category_req` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:412` | 露脸直播 | `niconico_category_face` |
| `live_core/lib/src/sites/niconico/niconico_api.dart:413` | 连麦互动 | `niconico_category_totu` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:180` | 公开直播 | `pandalive_public_directory` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:187` | 新人主播 | `pandalive_category_newbj` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:219` | 个人直播 | `pandalive_category_ind` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:220` | 聊天 | `pandalive_category_talk` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:221` | 音乐 | `pandalive_category_music` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:222` | 游戏 | `pandalive_category_game` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:223` | 体育 | `pandalive_category_sports` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:224` | 其他 | `pandalive_category_etc` |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart:236` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/picarto/picarto_api.dart:157` | 公开直播（不含成人内容） | `picarto_public_directory` |
| `live_core/lib/src/sites/picarto/picarto_api.dart:569` | 自动 | `quality_name_auto` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:164` | 音频直播 | `seventeen_audio_room` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:182` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:183` | 增强高清 | `seventeen_quality_enhanced` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:184` | 高清 | `quality_name_hd` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:220` | 地区 | `seventeen_category_region` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:226` | 日本 | `seventeen_region_jp` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:226` | 台湾 | `seventeen_region_tw` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:226` | 香港 | `seventeen_region_hk` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:231` | 日本 | `seventeen_region_jp` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:232` | 台湾 | `seventeen_region_tw` |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:233` | 香港 | `seventeen_region_hk` |
| `live_core/lib/src/sites/showroom/showroom_api.dart:587` | 自动 | `quality_name_auto` |
| `live_core/lib/src/sites/showroom/showroom_api.dart:588` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/showroom/showroom_api.dart:589` | 中画质 | `showroom_quality_medium` |
| `live_core/lib/src/sites/showroom/showroom_api.dart:590` | 低画质 | `showroom_quality_low` |
| `live_core/lib/src/sites/sixroom/sixroom_api.dart:330` | FLV 原始线路 | `quality_name_flv_source` |
| `live_core/lib/src/sites/soop/soop_api.dart:171` | 热门 | `soop_category_hot` |
| `live_core/lib/src/sites/soop/soop_api.dart:675` | 蓝光 | `quality_name_bluray` |
| `live_core/lib/src/sites/soop/soop_api.dart:676` | 超清 | `quality_name_super_hd` |
| `live_core/lib/src/sites/steambroadcast/steambroadcast_api.dart:406` | 热门社区直播 | `steambroadcast_category_trending` |
| `live_core/lib/src/sites/steambroadcast/steambroadcast_api.dart:441` | 自适应 HLS | `fc2live_quality_auto` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:271` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:282` | 原始画质 | `tiktok_quality_origin` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:283` | 超清 60 帧 | `tiktok_quality_uhd60` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:284` | 高清 60 帧 | `tiktok_quality_hd60` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:285` | 超清 | `quality_name_super_hd` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:286` | 高清 | `quality_name_hd` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:287` | 标清 | `quality_name_sd` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:288` | 流畅 | `quality_name_smooth` |
| `live_core/lib/src/sites/tiktok/tiktok_api.dart:289` | 自动 | `quality_name_auto` |
| `live_core/lib/src/sites/twitch/twitch_api.dart:890` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/twitch/twitch_api.dart:895` | 自动 | `quality_name_auto` |
| `live_core/lib/src/sites/weibo/weibo_api.dart:172` | 公开推荐 | `weibo_public_directory` |
| `live_core/lib/src/sites/weibo/weibo_api.dart:194` | 原始流 | `weibo_original_stream` |
| `live_core/lib/src/sites/weibo/weibo_api.dart:198` | 原画 | `quality_name_original` |
| `live_core/lib/src/sites/youtube/youtube_api.dart:439` | HLS 自动 | `youtube_quality_hls_auto` |
| `live_core/lib/src/sites/youtube/youtube_api.dart:442` | DASH 自动 | `youtube_quality_dash_auto` |
| `live_core/lib/src/sites/yy/yy_api.dart:823` | 流畅 | `quality_name_smooth` |
| `live_core/lib/src/sites/yy/yy_api.dart:823` | 高清 | `quality_name_hd` |

### C 弹幕的系统提示：23 个

| 位置 | 文字 | 键或原因 |
|---|---|---|
| `live_danmaku/lib/src/sites/bilibili.dart:505` | 直播间收到警告 | `bilibili_warning_notice` |
| `live_danmaku/lib/src/sites/bilibili.dart:509` | 直播被切断 | `bilibili_cut_off_notice` |
| `live_danmaku/lib/src/sites/kick.dart:119` | 直播已结束 | `kick_stream_ended_notice` |
| `live_danmaku/lib/src/sites/missevan.dart:129` | 主播正在匹配 PK 对手，请耐心等候 | `missevan_pk_match_start` |
| `live_danmaku/lib/src/sites/missevan.dart:130` | PK 已开始，快送礼支持主播吧 | `missevan_pk_match_success` |
| `live_danmaku/lib/src/sites/missevan.dart:131` | 对方未接受邀请 | `missevan_pk_invite_declined` |
| `live_danmaku/lib/src/sites/missevan.dart:132` | 对方未接受邀请 | `missevan_pk_invite_declined` |
| `live_danmaku/lib/src/sites/missevan.dart:137` | 恭喜主播获得 PK 胜利，继续支持主播吧 | `missevan_pk_won` |
| `live_danmaku/lib/src/sites/missevan.dart:137` | 主播 PK 失败，再接再厉哦 | `missevan_pk_lost` |
| `live_danmaku/lib/src/sites/missevan.dart:137` | 主播 PK 平局，再接再厉哦 | `missevan_pk_drawn` |
| `live_danmaku/lib/src/sites/missevan.dart:142` | 幻影 PK 即将开启，准备迎战！ | `missevan_global_pk_match_ready` |
| `live_danmaku/lib/src/sites/missevan.dart:143` | 本场幻影 PK 已跳过 | `missevan_global_pk_match_skip` |
| `live_danmaku/lib/src/sites/missevan.dart:144` | 幻影 PK 匹配中，敬请期待…… | `missevan_global_pk_match_start` |
| `live_danmaku/lib/src/sites/missevan.dart:145` | 本场幻影 PK 未匹配到合适的对手 | `missevan_global_pk_match_fail` |
| `live_danmaku/lib/src/sites/missevan.dart:146` | 匹配成功！幻影 PK 正式开战！ | `missevan_global_pk_match_success` |
| `live_danmaku/lib/src/sites/missevan.dart:148` | 幻影 PK 已结束 | `missevan_global_pk_finish` |
| `live_danmaku/lib/src/sites/missevan.dart:165` | 恭喜胜利！ | `missevan_global_pk_won` |
| `live_danmaku/lib/src/sites/missevan.dart:165` | 本场幻影 PK 战成平局 | `missevan_global_pk_drawn` |
| `live_danmaku/lib/src/sites/missevan.dart:165` | 本场幻影 PK 遗憾落败 | `missevan_global_pk_lost` |
| `live_danmaku/lib/src/sites/niconico.dart:348` | 评论锁定已解除 | `niconico_comment_unlocked_notice` |
| `live_danmaku/lib/src/sites/seventeenlive.dart:319` | 主播暂停了直播（画面静止、没有声音） | `seventeen_muted_notice` |
| `live_danmaku/lib/src/sites/seventeenlive.dart:322` | 主播恢复了直播 | `seventeen_unmuted_notice` |
| `live_danmaku/lib/src/sites/twitch.dart:190` | Twitch 的 Cookie 已失效，弹幕已改为匿名接收，请重新填写 Twitch Cook… | `twitch_cookie_expired_notice` |

### 留下没做的（带参数，要改结构，见“留给以后”）：37 个

| 位置 | 文字 | 键或原因 |
|---|---|---|
| `live_core/lib/src/quality_label.dart:35` | 清晰度 $idText | 带编号的画质名（`清晰度 N`）：要改成键加参数，没做 |
| `live_core/lib/src/sites/acfun/acfun_api.dart:431` | 画质 $id | 带参数的画质名或说明：要改成键加参数，没做 |
| `live_core/lib/src/sites/kuaishou/kuaishou_api.dart:726` | 清晰度 $sort | 带参数的画质名或说明：要改成键加参数，没做 |
| `live_core/lib/src/sites/kugoulive/kugoulive_api.dart:944` | ${variant.protocol.toUpperCase()} 码率档 ${variant… | 带参数的画质名或说明：要改成键加参数，没做 |
| `live_danmaku/lib/src/sites/chzzk.dart:470` | 「$tier」订阅券 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/chzzk.dart:474` | 向频道赠送了 $quantity 张$pass | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/chzzk.dart:474` | 向频道赠送了$pass | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/chzzk.dart:477` | 赠送了$pass | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/chzzk.dart:477` | 向 $receiver 赠送了$pass | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/chzzk.dart:538` | 置顶消息：$text | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/chzzk.dart:540` | $author 置顶了消息：$text | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/chzzk.dart:541` | $pinner 置顶了 $author 的消息：$text | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kick.dart:175` | $name 送出了 ${giftName.isEmpty ?  | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kick.dart:220` | $name 订阅了 $months 个月 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kick.dart:220` | $name 订阅了频道 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kick.dart:231` | $giver 向 ${_text(names.first)} 赠送了订阅 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kick.dart:231` | $giver 赠送了 $count 个订阅 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kick.dart:243` | $host 带着 $viewers 位观众来了 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kick.dart:243` | $host 转播了本频道 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kick.dart:252` | 置顶消息：$text | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kick.dart:252` | 置顶了 $author 的消息：$text | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kilakila.dart:341` | 我送了${receiverName.isEmpty ?  | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kilakila.dart:341` |  : receiverName}$count个${present.name} | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/kilakila.dart:396` | ${amount(price)}红豆 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/missevan.dart:377` | $price 钻 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/missevan.dart:435` | }$action了${host.isEmpty ?  | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/missevan.dart:435` | }$name贵族 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/picarto.dart:240` | 打赏给 $receiver | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/picarto.dart:241` | 打赏给 $receiver：$text | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/picarto.dart:306` | $from 突袭了 $to | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/picarto.dart:341` | 有人匿名向 Picarto 社区赠送了 $recipients 份 $channel 的订阅 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/picarto.dart:342` | $receiver 收到匿名赠送的 $months 个月 $channel 订阅 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/picarto.dart:344` | $sender 向 Picarto 社区赠送了 $recipients 份 $channel … | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/picarto.dart:345` | $sender 赠送给 $receiver $months 个月订阅 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/picarto.dart:351` | $sender 开通了 $channel 的 $level 级订阅 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/picarto.dart:351` | $sender 订阅了 $channel，$months 个月 | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |
| `live_danmaku/lib/src/sites/youtube.dart:641` | 送出 Super Sticker${amount.isEmpty ?  | 带参数的弹幕行（礼物、订阅、置顶）：要改成结构化的消息，没做 |

### D 不改：244 个

| 文件 | 行 | 原因 |
|---|---|---|
| `live_core/lib/src/audience.dart` | 327, 331, 332, 333 | 人数单位和链接的解析 |
| `live_core/lib/src/audience.dart` | 328 | 正则或解析用的模式 |
| `live_core/lib/src/json.dart` | 108 | 正则或解析用的模式 |
| `live_core/lib/src/json.dart` | 112, 113 | 人数单位和链接的解析 |
| `live_core/lib/src/links.dart` | 209, 239 | 正则或解析用的模式 |
| `live_core/lib/src/sites/acfun/acfun_api.dart` | 21 | 正则或解析用的模式 |
| `live_core/lib/src/sites/acfun/acfun_api.dart` | 544 | 解析平台返回用的关键字或标点 |
| `live_core/lib/src/sites/acfun/acfun_site.dart` | 92 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/baidulive/baidulive_api.dart` | 380, 381, 382, 383, 384, 385, 386 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/baidulive/baidulive_api.dart` | 391 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/baidulive/baidulive_api.dart` | 396 | 目录说明的默认文字：界面已按 `*_directory_scope` 键显示（`LiveDirectoryNotice`） |
| `live_core/lib/src/sites/baidulive/baidulive_api.dart` | 404 | 3.x 的旧说明（`legacyChatNotice`），只用来对照和迁移时清掉，不显示 |
| `live_core/lib/src/sites/bilibili/bilibili_api.dart` | 385 | 解析平台返回用的关键字或标点 |
| `live_core/lib/src/sites/bilibili/bilibili_site.dart` | 74 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/cc/cc_api.dart` | 159, 781 | 解析平台返回用的关键字或标点 |
| `live_core/lib/src/sites/cc/cc_site.dart` | 68 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/chzzk/chzzk_api.dart` | 248 | 目录说明的默认文字：界面已按 `*_directory_scope` 键显示（`LiveDirectoryNotice`） |
| `live_core/lib/src/sites/douyin/douyin_api.dart` | 91 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/douyin/douyin_site.dart` | 129 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/douyu/douyu_api.dart` | 368 | 解析平台返回用的关键字或标点 |
| `live_core/lib/src/sites/douyu/douyu_site.dart` | 102 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart` | 309 | 3.x 的旧说明（`legacyChatNotice`），只用来对照和迁移时清掉，不显示 |
| `live_core/lib/src/sites/fc2live/fc2live_api.dart` | 557 | 诊断信息（英文，不显示） |
| `live_core/lib/src/sites/huya/huya_api.dart` | 256, 257, 258, 259 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/huya/huya_site.dart` | 167 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/inke/inke_api.dart` | 130, 148 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/inke/inke_api.dart` | 137 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/inke/inke_api.dart` | 155 | 平台的占位文字，用来识别后换掉 |
| `live_core/lib/src/sites/inke/inke_site.dart` | 79 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/kilakila/kilakila_api.dart` | 403 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/kilakila/kilakila_api.dart` | 407, 407 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/kuaishou/kuaishou_api.dart` | 79, 80, 81, 82, 83, 84, 85, 86, 489 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/kuaishou/kuaishou_api.dart` | 502 | 正则或解析用的模式 |
| `live_core/lib/src/sites/kuaishou/kuaishou_site.dart` | 77 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/kugoulive/kugoulive_api.dart` | 161 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/kugoulive/kugoulive_api.dart` | 167 | 目录说明的默认文字：界面已按 `*_directory_scope` 键显示（`LiveDirectoryNotice`） |
| `live_core/lib/src/sites/kugoulive/kugoulive_api.dart` | 222, 223, 224, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/looklive/looklive_api.dart` | 344 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/missevan/missevan_api.dart` | 107 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/missevan/missevan_api.dart` | 112, 112, 112 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/missevan/missevan_site.dart` | 51 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/pandalive/pandalive_api.dart` | 192 | 目录说明的默认文字：界面已按 `*_directory_scope` 键显示（`LiveDirectoryNotice`） |
| `live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart` | 171 | 目录说明的默认文字：界面已按 `*_directory_scope` 键显示（`LiveDirectoryNotice`） |
| `live_core/lib/src/sites/sixroom/sixroom_api.dart` | 293 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/sixroom/sixroom_api.dart` | 339, 340, 341, 342, 343, 344 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/sixroom/sixroom_api.dart` | 679 | 解析平台返回用的关键字或标点 |
| `live_core/lib/src/sites/soop/soop_api.dart` | 314 | 解析平台返回用的关键字或标点 |
| `live_core/lib/src/sites/soop/soop_site.dart` | 36 | 正则或解析用的模式 |
| `live_core/lib/src/sites/soop/soop_site.dart` | 72 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/steambroadcast/steambroadcast_api.dart` | 428 | 3.x 的旧说明（`legacyChatNotice`），只用来对照和迁移时清掉，不显示 |
| `live_core/lib/src/sites/weibo/weibo_api.dart` | 163 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/weibo/weibo_api.dart` | 191 | 目录说明的默认文字：界面已按 `*_directory_scope` 键显示（`LiveDirectoryNotice`） |
| `live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart` | 154 | 目录说明的默认文字：界面已按 `*_directory_scope` 键显示（`LiveDirectoryNotice`） |
| `live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart` | 529 | 正则或解析用的模式 |
| `live_core/lib/src/sites/xiaohongshu/xiaohongshu_site.dart` | 50 | 平台名：界面按 `site_<id>` 键显示 |
| `live_core/lib/src/sites/youtube/youtube_api.dart` | 399 | 3.x 的旧说明（`legacyChatNotice`），只用来对照和迁移时清掉，不显示 |
| `live_core/lib/src/sites/yy/yy_api.dart` | 121, 122, 123, 124, 125, 126, 127, 129, 130, 131 | 国内平台自己的分区名（3.x 也不翻译） |
| `live_core/lib/src/sites/yy/yy_api.dart` | 137, 141 | 平台的占位文字，用来识别后换掉 |
| `live_core/lib/src/sites/yy/yy_site.dart` | 74 | 平台名：界面按 `site_<id>` 键显示 |
| `live_danmaku/lib/src/sites/bilibili.dart` | 341 | 正则或解析用的模式 |
| `live_danmaku/lib/src/sites/bilibili.dart` | 562 | 把平台原文拼起来的标点 |
| `live_danmaku/lib/src/sites/chzzk.dart` | 470, 500 | 平台给的名字或占位（匿名用户、主播、表情） |
| `live_danmaku/lib/src/sites/jdlive.dart` | 83 | 平台给的名字或占位（匿名用户、主播、表情） |
| `live_danmaku/lib/src/sites/kick.dart` | 229 | 平台给的名字或占位（匿名用户、主播、表情） |
| `live_danmaku/lib/src/sites/kick.dart` | 244 | 把平台原文拼起来的标点 |
| `live_danmaku/lib/src/sites/kuaishou.dart` | 81 | 平台给的名字或占位（匿名用户、主播、表情） |
| `live_danmaku/lib/src/sites/looklive.dart` | 118 | 平台给的名字或占位（匿名用户、主播、表情） |
| `live_danmaku/lib/src/sites/missevan.dart` | 422, 423 | 平台给的名字或占位（匿名用户、主播、表情） |
| `live_danmaku/lib/src/sites/niconico.dart` | 153, 154, 340, 344, 351, 362, 363, 365, 366, 367, 452 | 平台原文（日文） |
| `live_danmaku/lib/src/sites/sixroom.dart` | 128 | 平台给的表情占位 |
| `live_danmaku/lib/src/sites/youtube.dart` | 641 | 平台给的名字或占位（匿名用户、主播、表情） |
| `live_danmaku/lib/src/sites/youtube.dart` | 653, 659 | 把平台原文拼起来的标点 |
| `live_danmaku/lib/src/sites/yy.dart` | 45 | 平台给的名字或占位（匿名用户、主播、表情） |
| `live_iptv/lib/src/guide/matcher.dart` | 148 | 正则或解析用的模式 |
| `live_iptv/lib/src/iptv_site.dart` | 45, 125 | IPTV 列表解析和频道名的匹配 |
| `live_iptv/lib/src/playlist/txt_parser.dart` | 35, 35, 48 | IPTV 列表解析和频道名的匹配 |
| `live_net/lib/src/proxy.dart` | 95, 96, 97, 98, 99 | 全角符号的替换 |
| `live_record/lib/src/resolver.dart` | 113 | 存下的设置和录制的画质名（D-018、J02.1），不随语言变 |
| `live_record/lib/src/settings.dart` | 5, 5, 5, 5, 5, 21 | 存下的设置和录制的画质名（D-018、J02.1），不随语言变 |
| `live_store/lib/src/legacy/legacy_rules.dart` | 13, 13 | 存下的设置和录制的画质名（D-018、J02.1），不随语言变 |
| `live_store/lib/src/settings/settings.dart` | 188, 288, 296, 301, 301, 301, 301, 301, 1039, 1039, 1039, 1039, 1039, 1045, 1046, 1046, 1046, 1046, 1046 | 存下的设置和录制的画质名（D-018、J02.1），不随语言变 |
| `live_ui/lib/src/scope.dart` | 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63 | 共用组件的中文默认文字，应用按语言填 `LiveUiStrings` |
| `live_vod/lib/src/music/lyrics.dart` | 147, 148, 149, 150 | 正则或解析用的模式 |
| `live_vod/lib/src/music/matcher.dart` | 48, 48, 48, 48, 48, 49, 49 | 点播的标签匹配和平台给的画质名 |
| `live_vod/lib/src/music/matcher.dart` | 50, 51 | 正则或解析用的模式 |
| `live_vod/lib/src/music/third_party.dart` | 251 | 点播的标签匹配和平台给的画质名 |
| `live_vod/lib/src/parse.dart` | 270, 610, 718 | 点播的标签匹配和平台给的画质名 |
| `live_vod/lib/src/pgc_models.dart` | 217, 217 | 点播的标签匹配和平台给的画质名 |
| `live_vod/lib/src/streams.dart` | 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36 | 点播的标签匹配和平台给的画质名 |
