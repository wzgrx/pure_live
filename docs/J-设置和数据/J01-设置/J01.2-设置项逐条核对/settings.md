# J01.2 设置项对照表

<!-- 由 tools/docs/settings_audit.py 生成（手写的部分在 tools/docs/settings_audit_notes.py），不要手改 -->

v4 的 240 个设置（`Settings.all`），每个一行，和 3.x（`v3.2.11`）比默认值、取值范围、设置页的范围、读取位置和生效时机。返回 [README](README.md)。

## 结论

| 结论 | 个数 |
|---|---:|
| 一样 | 219 |
| 确认改动 | 3 |
| 不一样，已改 | 18 |
| 不一样，待处理 | 0 |

“一样”：默认值和 3.x 一样（3.x 的常量和表达式已经展开），数值的范围也一样（3.x 的范围是它启动时和导入备份时的修正）；v4 新加的设置，“一样”指默认值和来源任务写的一致。“确认改动”写了依据（任务或决定）。“不一样，已改”是本任务改了注册表（`settings.dart`），“不一样，待处理”开了后续任务。

列的意思：**3.x 默认**是 Android 手机新装时的值，后面是 3.x 的文件:行（`lib/` 下）；**v4 范围**是注册表的 `min`/`max` 或可选值，存的值越界时夹紧、不在可选值里时用默认值；**设置页**是设置页这一行的滑块、加减或数字框的范围（空的是开关、选项或专门的页面）；**读取**是设置页以外读它的代码（`apps/pure_live/lib` 或 `packages/*/lib` 下）；**生效**：“立即”是界面监听着它，“读取时”是用到时读一次（例如进房、启动）；**目录**是设置页目录 `settings_catalog.dart` 里登记它的那一行的 id（`SettingsEntry.settings`；现在设置页还没有用它显示“已修改”，“恢复本页默认”用各页自己的列表），空的是没登记：本机记录、没有界面的、在自己的页面上设置的（网络电视、录制、本地互动、日志、电视界面、直播间里的状态）。

## 应用（app）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `autoRefreshTime` | Int | `3` | `3`（`app_settings_controller.dart:42`） | 不限 | 不限 |  | 没有读取 |  |  | 一样：3.x 也没有读取它的代码，只存、只进备份（功能清点第 15 节） |
| `enableDenseFavorites` | Bool | `true` | `true`（`app_settings_controller.dart:43`） |  |  |  | `features/favorite/favorite_page.dart:245`、`features/favorite/favorite_page.dart:393` | 立即 |  | 一样：3.x 也没有改它的界面（只有备份能改），v4 同样 |
| `enableBackgroundPlay` | Bool | `false` | `false`（`app_settings_controller.dart:44`） |  |  |  | `features/live_play/live_play_page.dart:310`、`features/live_play/logic/background_playback.dart:430`、`features/live_play/logic/background_playback.dart:451` | 立即 | `background_play` | 一样 |
| `enableAsmrSleepMode` | Bool | `false` | `false`（`app_settings_controller.dart:45`） |  |  |  | `features/live_play/live_play_page.dart:290` | 读取时 | `asmr_sleep` | 一样 |
| `asmrSleepMinutes` | Int | `60` | `60`（`app_settings_controller.dart:46`） | 1～525600 | 1～525600（`app_settings_controller.dart:227`） | 数字框，预设 `[15, 30, 45, 60, 90, 120, 240, 480, 720, 1440]` | `features/live_play/logic/room_controller.dart:475` | 读取时 | `asmr_minutes` | 一样 |
| `enableRotateScreen` | Bool | `false` | `false`（`app_settings_controller.dart:47`） |  |  |  | 没有读取 |  |  | 一样：3.x 也没有读取它的代码，只存、只进备份 |
| `enableScreenKeepOn` | Bool | `true` | `true`（`app_settings_controller.dart:48`） |  |  |  | `features/live_play/mini/floating_window.dart:226`、`features/live_play/player/player_view.dart:616`、`features/multiview/multiview_page.dart:871` | 立即 | `screen_keep_on` | 一样 |
| `enableAutoCheckUpdate` | Bool | `true` | `true`（`app_settings_controller.dart:49`） |  |  |  | `features/version/update_prompt.dart:40`、`features/version/update_prompt.dart:92` | 读取时 | `auto_update` | 一样 |
| `useGitHubOriginForUpdates` | Bool | `false` | `false`（`app_settings_controller.dart:50`） |  |  |  | `features/version/release_history_view.dart:480`、`features/version/update_feed.dart:404`、`features/version/update_prompt.dart:81` 等 4 处 | 立即 | `github_updates` | 一样 |
| `skippedUpdateVersion` | String，本机 | `''` | —（新加） |  |  |  | `features/version/update_prompt.dart:23`、`features/version/update_prompt.dart:92`、`features/version/update_prompt.dart:128` 等 4 处 | 读取时 |  | 一样：v4 新加（A06.3 c4，本机记录），默认值照来源任务 |
| `enableFullScreenDefault` | Bool | `false` | `false`（`app_settings_controller.dart:51`） |  |  |  | `features/live_play/live_play_page.dart:251`、`features/live_play/live_play_page.dart:256` | 读取时 | `fullscreen_default` | 一样 |
| `showSplashPage` | Bool | `true` | `true`（`app_settings_controller.dart:52`） |  |  |  | `features/splash/splash_page.dart:18`、`main.dart:51` | 读取时 | `splash` | 一样 |
| `refreshRateMode` | String | `'powerSaving'` | `'powerSaving'`（`app_settings_controller.dart:36-40、:53`） | `powerSaving` / `balanced` / `performance` |  |  | `app/app.dart:241`、`features/live_play/logic/room_refresh_rate.dart:37`、`features/live_play/logic/room_refresh_rate.dart:58` 等 8 处 | 立即 | `refresh_rate` | 一样：3.x 新装没有旧开关 `enableHighRefreshRate`，`_initialRefreshRateMode()` 得 `powerSaving`；旧开关为真的老用户迁移成 `balanced`（`legacy_snapshot.dart`） |
| `matchVideoFrameRate` | Bool | `true` | —（新加） |  |  |  | `features/live_play/logic/room_refresh_rate.dart:37`、`features/live_play/logic/room_refresh_rate.dart:57` | 立即 | `match_video_frame_rate` | 一样：v4 新加（R02.1，U.2i），默认值照来源任务 |
| `preferRealOnlineCounts` | Bool | `false` | `false`（`app_settings_controller.dart:54`） |  |  |  | `features/favorite/favorite_controller.dart:168`、`features/favorite/favorite_controller.dart:346`、`features/multiview/widgets/room_picker.dart:173` 等 10 处 | 立即 | `audience_heat` | 一样 |
| `realOnlinePlatforms` | StringList | `[douyin, kuaishou, cc, twitch, soop, acfun, picarto, twitcasting]` | `[douyin, kuaishou, cc, twitch, soop, acfun, picarto, twitcasting]`（`app_settings_controller.dart:11-20、:55`） |  |  |  | `features/favorite/favorite_controller.dart:169`、`features/favorite/favorite_controller.dart:347`、`features/multiview/widgets/room_picker.dart:174` 等 13 处 | 立即 | `audience_platforms` | 一样：`defaultRealOnlinePlatforms` 展开后一样；3.x 的 `audienceMetricMigration` 补的平台都已在列表里 |
| `savedMenuIds` | StringList | `[favorites, popular, areas, record]` | `[favorites, popular, areas, record]`（`app_settings_controller.dart:69`，`HomeMenu` 在 `common/consts/app_consts.dart:6-10`） |  |  |  | `app/app.dart:144`、`features/home/home_page.dart:136`、`live_store/src/legacy/legacy_snapshot.dart:213` 等 4 处 | 立即 | `home_menus` | 一样 |
| `enableMultiView` | Bool | `true` | `true`（`app_settings_controller.dart:60`） |  |  |  | `features/home/home_views.dart:98`、`features/home/menu_button.dart:137` | 立即 | `multiview` | 一样 |
| `enableNewWindowPlay` | Bool | `true` | `true`（`app_settings_controller.dart:61`） |  |  |  | `app/desktop/desktop_window.dart:84`、`app/desktop/desktop_window.dart:89`、`features/home/menu_button.dart:56` | 立即 | `new_window` | 一样 |
| `showUnplayableInDiscover` | Bool | `false` | —（新加） |  |  |  | `features/area_rooms/area_rooms_page.dart:77`、`features/area_rooms/area_rooms_page.dart:80`、`features/area_rooms/area_rooms_page.dart:81` 等 7 处 | 立即 | `show_unplayable` | 一样：v4 新加（UPGRADES 统一原则“受限”，J02.1），默认值照来源任务 |
| `detectClipboardRooms` | Bool | `true` | —（新加） |  |  |  | `app/intake/clipboard_rooms.dart:92` | 读取时 | `clipboard_rooms` | 一样：v4 新加（O03.2）；3.x 一直检测剪贴板、没有开关，默认开和 3.x 的行为一样 |
| `douyuForceRenew` | Bool | `false` | —（新加） |  |  |  | `app/platforms.dart:169`、`features/account/douyu_cookie_view.dart:177`、`features/account/douyu_cookie_view.dart:266` | 立即 | `douyu_renew` | 一样：v4 新加（UPGRADES 2-1），默认值照来源任务 |
| `twitchLanguages` | StringList | `[]` | —（新加） |  |  |  | `app/platforms.dart:179` | 读取时 | `twitch_languages` | 一样：v4 新加（UPGRADES 8-3）；空 = 不筛语言（3.x 固定只看中文和韩语，作为预设 `twitchLegacyLanguages` 提供） |
| `uiMode` | String，本机 | `'auto'` | —（新加） | `auto` / `phone` / `tv` |  |  | `app/app.dart:237`、`app/ui_mode.dart:20`、`app/ui_mode.dart:71` 等 5 处 | 立即 | `ui_mode` | 一样：v4 新加（X03.1（M14.1），本机记录），默认值照来源任务 |
| `tvFocusZoom` | Bool | `true` | —（新加） |  |  |  | `tv/pages/tv_settings_pane.dart:101`、`tv/pages/tv_settings_pane.dart:102`、`tv/tv_app.dart:67` | 立即 |  | 一样：v4 新加（A17.1 c2），默认值照来源任务 |

## 平台（favorite）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `hotAreasList` | StringList | 35 个：`bilibili, douyu, huya, douyin, kuaishou, cc, twitch, soop, yy, acfun, picarto, twitcasting, missevan, inke, kilakila, xiaohongshu, niconico, weibo, showroom, chzzk, kick, liveme, tiktok, youtube, bigo, pandalive, fc2live, steambroadcast, jdlive, kugoulive, baidulive, sixroom, looklive, 17live, iptv` | 34 个：`bilibili, douyu, huya, douyin, kuaishou, cc, twitch, soop, yy, acfun, picarto, twitcasting, missevan, inke, kilakila, xiaohongshu, niconico, weibo, showroom, chzzk, liveme, tiktok, youtube, bigo, pandalive, fc2live, steambroadcast, jdlive, kugoulive, baidulive, sixroom, looklive, 17live, iptv`（`favorite_room_controller.dart:20`，`AppConsts.supportSites` = `core/sites.dart:217-251`） |  |  |  | `app/bootstrap.dart:413`、`features/areas/areas_page.dart:141`、`features/areas/favorite_areas_view.dart:108` 等 25 处 | 立即 | `platform_list` | 确认改动：v4 多了 Kick（排在 chzzk 后面）：Kick 重新支持（UPGRADES X-1，E 组 M4.34）；其余 34 个和顺序一样 |
| `preferPlatform` | String | `'bilibili'` | `'bilibili'`（`favorite_room_controller.dart:24`） |  |  |  | `features/areas/areas_page.dart:84`、`features/hot_areas/hot_areas_page.dart:65`、`features/hot_areas/hot_areas_page.dart:67` 等 11 处 | 读取时 | `prefer_platform` | 一样 |

## 历史（history）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `historyLimit` | Int | `50` | `50`（`history_controller.dart:68`） | ≥ 0 | ≥ 0，负数回到 50（`history_controller.dart:8-15`） | 数字框，预设 `[0, 20, 50, 100, 200, 500]` | `features/history/history_page.dart:178`、`features/history/history_page.dart:221`、`live_store/src/rooms.dart:150` 等 6 处 | 立即 | `history_limit` | 不一样，已改：默认值和范围一样；存了负数时 3.x 回到 50，v4 原来夹成 0（不限），J01.3 改成和 3.x 一样回到默认值（`IntSetting` 的 `resetOutOfRange`） |

## 主题（theme）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `themeMode` | String | `'System'` | `'System'`（`theme_settings_controller.dart:17`） | `System` / `Dark` / `Light` |  |  | `app/app.dart:216`、`app/intake/system_intake.dart:58` | 立即 | `theme_mode` | 一样 |
| `enableDynamicTheme` | Bool | `false` | `false`（`theme_settings_controller.dart:18`） |  |  |  | `app/app.dart:221`、`tv/pages/tv_settings_pane.dart:83` | 立即 | `dynamic_color` | 一样 |
| `themeColorSwitch` | String | `'FF2E6FE0'` | `'FF2196F3'`（`theme_settings_controller.dart:13、:19`（`Colors.blue`）） |  |  |  | `app/app.dart:222`、`tv/pages/tv_settings_pane.dart:79`、`tv/pages/tv_settings_pane.dart:84` 等 8 处 | 立即 | `theme_color` | 确认改动：品牌蓝 `FF2E6FE0`（A11.2 C-3）；3.x 默认的蓝色存过的老用户迁移一次（`themeColorMigration`） |
| `pureBlackTheme` | Bool | `false` | —（新加） |  |  |  | `app/app.dart:223` | 立即 | `pure_black` | 一样：v4 新加（A11.2 C-4），默认值照来源任务 |
| `language` | String | `'简体中文'` | `'简体中文'`（`theme_settings_controller.dart:20`） |  |  |  | `app/app.dart:209`、`app/app.dart:211`、`main.dart:107` 等 4 处 | 立即 | `language` | 一样 |
| `crossAxisSpacing` | Double | `6` | `6`（`theme_settings_controller.dart:21`） | 0～64 | 0～64（`theme_settings_controller.dart:10-12`、:109-113） | 加减 0～64 | `features/areas/area_card.dart:161`、`features/areas/areas_common.dart:198`、`features/favorite/favorite_page.dart:394` 等 8 处 | 立即 | `cross_spacing` | 一样 |
| `mainAxisSpacing` | Double | `6` | `6`（`theme_settings_controller.dart:22`） | 0～64 | 0～64（同上） | 加减 0～64 | `features/areas/area_card.dart:162`、`features/areas/areas_common.dart:198`、`features/favorite/favorite_page.dart:395` 等 8 处 | 立即 | `main_spacing` | 一样 |
| `loadingStyle` | String | `'default'` | `'default'`（`theme_settings_controller.dart:23`，`common/consts/app_consts.dart:21`） |  |  |  | `app/app.dart:244` | 立即 | `loading_style` | 一样 |
| `loadingStyleColorSwitch` | String | `''` | `''`（`theme_settings_controller.dart:24`） |  |  |  | `app/app.dart:245` | 立即 | `loading_style` | 一样 |

## 本机记录（meta）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `themeColorMigration` | Int，本机 | `0` | —（新加） | 不限 |  |  | `live_store/src/live_store.dart:174`、`live_store/src/live_store.dart:179` | 读取时 |  | 一样：v4 新加（A11.2，本机记录），默认值照来源任务 |
| `remote_sync_device_id` | String，本机 | `''` | `''`（`modules/remote_receiver/remote_sync_service.dart:134-143（第一次用时生成）`） |  |  |  | `features/remote_receiver/remote_sync_service.dart:164`、`features/remote_receiver/remote_sync_service.dart:167` | 读取时 |  | 一样 |

## 字体（font）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `textScaleFactor` | Double | `1` | `1`（`font_settings_controller.dart:39`） | 0.5～2 | 0.5～2（`font_settings_controller.dart:16-18`） | 滑块 0.5～2，步长 0.05 | `app/app.dart:240`、`tv/pages/tv_areas_pane.dart:197`、`tv/pages/tv_settings_pane.dart:92` 等 5 处 | 立即 | `text_scale` | 一样 |
| `fontSizeBodySmall` | Double | `12` | `12`（`font_settings_controller.dart:40`） | 9～15 | 9～15（`font_settings_controller.dart:19-21`） | 滑块 9～15，步长 1 | `app/app.dart:225`、`shared/rooms/room_cards.dart:172` | 立即 | `font_sizes` | 一样 |
| `fontSizeBodyMedium` | Double | `13` | `13`（`font_settings_controller.dart:41`） | 11～17 | 11～17（`font_settings_controller.dart:22-24`） | 滑块 11～17，步长 1 | `app/app.dart:226`、`shared/rooms/room_cards.dart:173` | 立即 | `font_sizes` | 一样 |
| `fontSizeBodyLarge` | Double | `14` | `14`（`font_settings_controller.dart:42`） | 12～18 | 12～18（`font_settings_controller.dart:25-27`） | 滑块 12～18，步长 1 | `app/app.dart:227`、`shared/rooms/room_cards.dart:174` | 立即 | `font_sizes` | 一样 |
| `fontSizeTitleMedium` | Double | `15` | `15`（`font_settings_controller.dart:43`） | 13～20 | 13～20（`font_settings_controller.dart:28-30`） | 滑块 13～20，步长 1 | `app/app.dart:228`、`shared/rooms/room_cards.dart:175` | 立即 | `font_sizes` | 一样 |
| `fontSizeTitleLarge` | Double | `20` | `20`（`font_settings_controller.dart:44`） | 16～26 | 16～26（`font_settings_controller.dart:31-33`） | 滑块 16～26，步长 1 | `app/app.dart:229`、`shared/rooms/room_cards.dart:176` | 立即 | `font_sizes` | 一样 |
| `fontFamilyName` | String | `'Default'` | `'Default'`（`font_settings_controller.dart:45`） |  |  |  | `app/app.dart:232`、`app/fonts.dart:303`、`app/fonts.dart:395` 等 4 处 | 立即 | `app_font` | 一样 |
| `fontFamilyFileName` | String | `''` | `''`（`font_settings_controller.dart:46`） |  |  |  | `app/fonts.dart:150`、`app/fonts.dart:303`、`app/fonts.dart:397` | 读取时 | `app_font` | 一样 |
| `danmakuFontFamilyFileName` | String | `''` | `''`（`font_settings_controller.dart:47`） |  |  |  | `app/fonts.dart:304`、`app/fonts.dart:401` | 读取时 | `video_danmaku_font` | 一样 |

## 播放（player）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `videoFitIndex` | Int | `0` | `0`（`player_settings_controller.dart:33`） | 0～5 | 0～5，越界回到 0（`player_settings_controller.dart:135-139`） |  | `features/live_play/dialogs/player_dialogs.dart:35`、`features/live_play/dialogs/player_dialogs.dart:42`、`features/live_play/dialogs/player_dialogs.dart:58` 等 7 处 | 立即 | `video_fit` | 不一样，已改：默认值和范围一样；越界时 3.x 回到 0（适应），v4 原来夹到 0 或 5，J01.3 改成和 3.x 一样回到默认值（`IntSetting` 的 `resetOutOfRange`） |
| `videoPlayerKey` | String | `'mpv'` | `'mpv'`（`player_settings_controller.dart:11、:27、:34（iOS 是 ijk）`） |  |  |  | 没有读取 |  |  | 一样：v4 只用 mpv，这个键只为备份往返保留（J02.1 有意差异，F-ROOM-24 不做），没有读取 |
| `preferResolution` | String | `'原画'` | `'原画'`（`player_settings_controller.dart:36`，`player/utils/player_consts.dart:25`） | `原画` / `流畅` / `蓝光4M` / `蓝光8M` / `超清` |  |  | `features/live_play/logic/room_controller.dart:143`、`features/live_play/logic/room_controller.dart:603`、`features/multiview/logic/multiview_controller.dart:605` 等 5 处 | 立即 | `prefer_resolution` | 一样 |
| `preferResolutionCellular` | String | `'原画'` | `'原画'`（`player_settings_controller.dart:37`） | `原画` / `流畅` / `蓝光4M` / `蓝光8M` / `超清` |  |  | `features/live_play/logic/room_controller.dart:142`、`features/live_play/logic/room_controller.dart:603` | 读取时 | `prefer_resolution_cellular` | 一样 |
| `enableCodec` | Bool | `true` | `true`（`player_settings_controller.dart:39`） |  |  |  | `features/live_play/live_play_page.dart:426`、`features/multiview/multiview_page.dart:145`、`tv/room/tv_live_play_page.dart:35` | 读取时 | `hardware_decoding` | 一样 |
| `preferH264` | Bool | `true` | —（新加） |  |  |  | `app/platforms.dart:162`、`app/recording.dart:281`、`features/live_play/logic/room_controller.dart:631` 等 7 处 | 读取时 | `prefer_h264` | 一样：v4 新加（UPGRADES 统一原则、22-3），默认值照来源任务 |
| `playerCompatMode` | Bool | `false` | `false`（`player_settings_controller.dart:40`） |  |  |  | `features/live_play/live_play_page.dart:431`、`features/multiview/multiview_page.dart:150`、`tv/room/tv_live_play_page.dart:40` | 读取时 | `compat_mode` | 一样 |
| `customPlayerOutput` | Bool | `false` | `false`（`player_settings_controller.dart:41`） |  |  |  | `features/live_play/live_play_page.dart:427`、`features/multiview/multiview_page.dart:146`、`tv/room/tv_live_play_page.dart:36` | 读取时 | `custom_output` | 一样 |
| `videoOutputDriver` | String | `'gpu'` | `'gpu'`（`player_settings_controller.dart:42`） |  |  |  | `features/live_play/live_play_page.dart:428`、`features/multiview/multiview_page.dart:147`、`tv/room/tv_live_play_page.dart:37` | 读取时 | `video_output` | 一样 |
| `audioOutputDriver` | String | `'auto'` | `'auto'`（`player_settings_controller.dart:43`） |  |  |  | `features/live_play/live_play_page.dart:430`、`features/multiview/multiview_page.dart:149`、`tv/room/tv_live_play_page.dart:39` | 读取时 | `audio_output` | 一样 |
| `videoHardwareDecoder` | String | `'auto'` | `'auto'`（`player_settings_controller.dart:44`） |  |  |  | `features/live_play/live_play_page.dart:429`、`features/multiview/multiview_page.dart:148`、`tv/room/tv_live_play_page.dart:38` | 读取时 | `hardware_decoder` | 一样 |
| `floatPlay` | Bool | `false` | `false`（`player_settings_controller.dart:46`） |  |  |  | `features/live_play/live_play_page.dart:505` | 读取时 | `float_play` | 一样 |
| `floatWindowSize` | String | `'medium'` | —（新加） | `small` / `medium` / `large` | 3.x 没有这个设置，应用内小窗的大小按屏幕算（`player/core/player_manager.dart:4737`） |  | `features/live_play/mini/floating_window.dart:139` | 立即 | `float_window_size` | 一样：v4 新加（A07.22，V01.5，D-036）：小、中、大 = A07.8 c6 的大小 × 0.8、1、1.25；默认“中”和原来一样；不认识的值读成“中” |
| `floatWindowLandscapeScale` | Double | `1` | —（新加） | 0.25～4 | 3.x 不能拖小窗改大小 | 小窗上拖角或两指缩放；长边 160～屏幕短边 × 0.9（`mini_window.dart` 的 `inAppMiniScale`） | `features/live_play/mini/floating_window.dart:140`、`features/live_play/mini/floating_window.dart:265` | 立即 | `float_window_size` | 一样：v4 新加（A07.22，V01.5）：横屏画面小窗拖过的大小，是“小窗大小”的倍数；1 = 没拖过；选一档“小窗大小”回到 1 |
| `floatWindowPortraitScale` | Double | `1` | —（新加） | 0.25～4 | 3.x 不能拖小窗改大小 | 同上；竖屏画面的小窗另记一份 | `features/live_play/mini/floating_window.dart:141`、`features/live_play/mini/floating_window.dart:264` | 立即 | `float_window_size` | 一样：v4 新加（A07.22，V01.5）：竖屏画面小窗拖过的大小，和横屏画面的分开记（上游 a25facd94 的做法） |
| `windowsPipAlwaysOnTop` | Bool | `false` | `false`（`player_settings_controller.dart:47`） |  |  |  | `features/live_play/mini/room_mini_window.dart:177`、`features/live_play/mini/room_mini_window.dart:225`、`features/live_play/mini/room_mini_window.dart:226` 等 4 处 | 立即 | `pip_on_top` | 一样 |
| `autoPipOnLeave` | Bool | `false` | —（新加） |  |  |  | `features/live_play/mini/room_mini_window.dart:270`、`features/live_play/mini/room_mini_window.dart:280` | 立即 | `auto_pip` | 一样：v4 新加（A07.8，选择 J1），默认值照来源任务 |
| `enableRtxVsr` | Bool | `false` | `false`（`player_settings_controller.dart:48`） |  |  |  | `features/live_play/live_play_page.dart:432`、`features/multiview/multiview_page.dart:151`、`tv/room/tv_live_play_page.dart:41` | 读取时 | `rtx_vsr` | 一样 |
| `useHardStopOnExit` | Bool | `false` | `false`（`player_settings_controller.dart:52`） |  |  |  | `features/live_play/live_play_page.dart:515` | 读取时 | `hard_stop` | 一样 |
| `enablePortraitStreamAdaptation` | Bool | `true` | `true`（`player_settings_controller.dart:56`） |  |  |  | `features/live_play/live_play_page.dart:537`、`features/live_play/live_play_page.dart:713` | 立即 | `portrait_detect` | 一样 |
| `portraitAdaptiveHeight` | Bool | `true` | `true`（`player_settings_controller.dart:57`） |  |  |  | `features/live_play/live_play_page.dart:538`、`features/live_play/live_play_page.dart:714` | 立即 | `portrait_height` | 一样 |
| `portraitLayoutMode` | String | `'balanced'` | `'balanced'`（`player_settings_controller.dart:58`，`player/core/portrait_stream_support.dart:9`） |  |  |  | `features/live_play/live_play_page.dart:539`、`features/live_play/live_play_page.dart:715` | 立即 | `portrait_layout` | 一样 |
| `portraitFullscreenPolicy` | String | `'followSource'` | `'followSource'`（`player_settings_controller.dart:59-62`） |  |  |  | `features/live_play/live_play_page.dart:540`、`features/live_play/live_play_page.dart:716` | 立即 | `portrait_fullscreen` | 一样 |
| `portraitFullscreenDisplayMode` | String | `'ambient'` | `'ambient'`（`player_settings_controller.dart:63-66`） |  |  |  | `features/live_play/player/bar_parts.dart:276`、`features/live_play/player/bar_parts.dart:301`、`features/live_play/player/player_view.dart:628` | 立即 | `portrait_display` | 一样 |
| `portraitPipFollowSource` | Bool | `true` | `true`（`player_settings_controller.dart:67`） |  |  |  | `features/live_play/mini/floating_window.dart:138`、`features/live_play/mini/room_mini_window.dart:113`、`features/live_play/mini/room_mini_window.dart:270` | 立即 | `portrait_pip` | 一样 |
| `portraitDanmakuMode` | String | `'followGlobal'` | `'followGlobal'`（`player_settings_controller.dart:68`） |  |  |  | `features/live_play/player/player_view.dart:669` | 立即 | `portrait_danmaku` | 一样 |
| `rememberPortraitRoomOverride` | Bool | `true` | `true`（`player_settings_controller.dart:69`） |  |  |  | `features/live_play/logic/room_orientation.dart:58`、`features/live_play/logic/room_orientation.dart:81` | 读取时 | `portrait_remember` | 一样 |
| `portraitFullscreenSwipeSwitch` | Bool | `false` | —（新加） |  |  |  | `features/live_play/live_play_page.dart:542`、`features/live_play/live_play_page.dart:718` | 立即 | `portrait_swipe` | 一样：v4 新加（A07.2 c14、A07.3），默认值照来源任务 |
| `showPortraitDiagnostics` | Bool | `false` | `false`（`player_settings_controller.dart:70`） |  |  |  | `features/live_play/player/player_view.dart:677` | 立即 | `portrait_diagnostics` | 一样 |
| `portraitRoomOverrides` | Json | `{}` | `'{}'`（`player_settings_controller.dart:71`） |  |  |  | `features/live_play/logic/room_orientation.dart:53`、`features/live_play/logic/room_orientation.dart:70`、`features/live_play/logic/room_orientation.dart:82` | 读取时 | `portrait_reset` | 一样：3.x 在 Hive 里存 JSON 字符串 `'{}'`，v4 存映射；读 3.x 的字符串时解码（`JsonSetting`） |
| `livePlayChatCollapsed` | Bool | `false` | —（新加） |  |  |  | `features/live_play/live_play_page.dart:541`、`features/live_play/live_play_page.dart:635`、`features/live_play/live_play_page.dart:717` | 立即 |  | 一样：v4 新加（A07.5 第 7 条，直播间里记住），默认值照来源任务 |
| `roomSwitcherLayout` | String | `'grid'` | —（新加） | `grid` / `list` |  |  | `features/live_play/switch_room/room_switch_panel.dart:223`、`features/live_play/switch_room/room_switch_panel.dart:233` | 立即 |  | 一样：v4 新加（A07.13 c4，D-022），默认值照来源任务 |

## 弹幕（danmaku）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `hideDanmaku` | Bool | `false` | `false`（`danmaku_settings_controller.dart:58`） |  |  |  | `features/live_play/local_interaction/local_composer.dart:640`、`features/live_play/mini/compact_danmaku.dart:146`、`features/live_play/player/player_controls.dart:641` 等 5 处 | 立即 | `danmaku_on_video` | 一样 |
| `noEmojiMode` | Bool | `false` | `false`（`danmaku_settings_controller.dart:59`） |  |  |  | `shared/danmaku/danmaku_settings.dart:35`、`shared/danmaku/danmaku_templates.dart:37`、`shared/danmaku/danmaku_templates.dart:160` | 立即 | `danmaku_no_emoji` | 一样 |
| `danmakuTopArea` | Double | `0` | `0`（`danmaku_settings_controller.dart:60`） | 0～300 | 0～300（`danmaku_settings_controller.dart:115`） | 滑块 0～300，步长 1 | `shared/danmaku/danmaku_settings.dart:29`、`shared/danmaku/danmaku_templates.dart:29`、`shared/danmaku/danmaku_templates.dart:152` 等 4 处 | 立即 | `danmaku_top` | 一样 |
| `danmakuArea` | Double | `1` | `1`（`danmaku_settings_controller.dart:61`） | 0～1 | 0～1（`danmaku_settings_controller.dart:116`） | 滑块 0～1，步长 0.01 | `shared/danmaku/danmaku_settings.dart:27`、`shared/danmaku/danmaku_templates.dart:28`、`shared/danmaku/danmaku_templates.dart:151` 等 4 处 | 立即 | `danmaku_area` | 一样 |
| `danmakuBottomArea` | Double | `0.5` | `0.5`（`danmaku_settings_controller.dart:62`） | 0～300 | 0～300（`danmaku_settings_controller.dart:117`） | 滑块 0～300，步长 1 | `shared/danmaku/danmaku_settings.dart:30`、`shared/danmaku/danmaku_templates.dart:30`、`shared/danmaku/danmaku_templates.dart:153` 等 4 处 | 立即 | `danmaku_bottom` | 一样 |
| `danmakuSpeed` | Double | `120` | `120`（`danmaku_settings_controller.dart:63`） | 20～400 | 20～400（`danmaku_settings_controller.dart:118`） | 滑块 20～400，步长 1 | `shared/danmaku/danmaku_settings.dart:25`、`shared/danmaku/danmaku_templates.dart:31`、`shared/danmaku/danmaku_templates.dart:154` 等 4 处 | 立即 | `danmaku_speed` | 不一样，已改：注册表原来不限，3.x 存的值和导入的备份都夹到这个范围；改成同样的 `min`/`max` |
| `danmakuFontSize` | Double | `16` | `16`（`danmaku_settings_controller.dart:64`） | 10～30 | 10～30（`danmaku_settings_controller.dart:119`） | 滑块 10～30，步长 0.5 | `shared/danmaku/danmaku_settings.dart:23`、`shared/danmaku/danmaku_templates.dart:32`、`shared/danmaku/danmaku_templates.dart:155` 等 6 处 | 立即 | `danmaku_font_size` | 不一样，已改：注册表原来不限，3.x 存的值和导入的备份都夹到这个范围；改成同样的 `min`/`max` |
| `danmakuFontWeight` | Int | `500` | `500`（`danmaku_settings_controller.dart:65`） | 100～900 | 100～900（`danmaku_settings_controller.dart:41-44、:120`） | 滑块 100～900，步长 100 | `shared/danmaku/danmaku_settings.dart:24`、`shared/danmaku/danmaku_templates.dart:33`、`shared/danmaku/danmaku_templates.dart:156` 等 4 处 | 立即 | `danmaku_font_weight` | 不一样，已改：注册表原来不限，3.x 存的值和导入的备份都夹到这个范围；改成同样的 `min`/`max`；3.x 还取整到整百（550 → 600），J01.3 加了同样的取整（`IntSetting` 的 `step: 100`） |
| `danmakuFontBorder` | Double | `1.5` | `1.5`（`danmaku_settings_controller.dart:66`） | 0～4 | 0～4（`danmaku_settings_controller.dart:121`） | 滑块 0～4，步长 0.1 | `features/live_play/mini/compact_danmaku.dart:157`、`shared/danmaku/danmaku_settings.dart:32`、`shared/danmaku/danmaku_templates.dart:34` 等 5 处 | 立即 | `danmaku_stroke_width` | 一样 |
| `danmakuOpacity` | Double | `1` | `1`（`danmaku_settings_controller.dart:67`） | 0～1 | 0～1（`danmaku_settings_controller.dart:122`） | 滑块 0～1，步长 0.01 | `shared/danmaku/danmaku_settings.dart:26`、`shared/danmaku/danmaku_templates.dart:35`、`shared/danmaku/danmaku_templates.dart:158` 等 6 处 | 立即 | `danmaku_opacity` | 一样 |
| `enableDanmakuDisplay` | Bool | `true` | `true`（`danmaku_settings_controller.dart:68`） |  |  |  | `features/live_play/danmaku/chat_list.dart:437`、`features/live_play/danmaku/chat_list.dart:446`、`features/live_play/local_interaction/local_composer.dart:640` 等 14 处 | 立即 | `video_danmaku_show` | 一样 |
| `enableDanmakuStroke` | Bool | `true` | `true`（`danmaku_settings_controller.dart:69`） |  |  |  | `features/live_play/mini/compact_danmaku.dart:156`、`shared/danmaku/danmaku_settings.dart:31`、`shared/danmaku/danmaku_templates.dart:36` 等 5 处 | 立即 | `danmaku_stroke` | 一样 |
| `danmakuListStyle` | String | `'compact'` | —（新加） | `compact` / `card` |  |  | `features/live_play/danmaku/chat_list.dart:449` | 立即 | `danmaku_list_style` | 一样：v4 新加（A07.1，U.2a），默认值照来源任务 |
| `danmakuListFontSize` | Int | `0` | —（新加） | 12～22 | 3.x 没有这个设置，弹幕卡片写死 14 号（`modules/live_play/widgets/danmaku/danmaku_list_view.dart:468-509`） | 滑块 chatListFontSizeDefaultStop.toDouble()～22，步长 1 | `features/live_play/danmaku/chat_list.dart:457` | 立即 | `danmaku_list_font_size` | 一样：v4 新加（A08.15，D-040）：默认 0 = 跟主题的正文字号，和以前一样；12～22，超出范围读成 0；粉丝牌、徽章、头像、礼物图按比例，系统字体放大照样乘上去；飞行弹幕不受影响 |
| `danmakuListLineSpacing` | String | `'standard'` | —（新加） | `compact` / `standard` / `loose` | 3.x 没有这个设置，行距固定 |  | `features/live_play/danmaku/chat_list.dart:458` | 立即 | `danmaku_list_spacing` | 一样：v4 新加（A08.15，D-040）：默认“标准”和以前一样；“紧密”各处上下间距减半、文字行高 1.4，“宽松”间距 1.5 倍、行高 1.7；不认识的值读成“标准” |
| `showChatGifts` | Bool | `true` | —（新加） |  |  |  | `features/live_play/logic/room_controller.dart:296`、`features/live_play/logic/room_controller.dart:456`、`features/live_play/logic/room_controller.dart:855` 等 6 处 | 立即 | `danmaku_show_gifts` | 一样：v4 新加（A08.6 c3，B-21），默认值照来源任务 |
| `chatGiftsAboveTier` | Bool | `false` | —（新加） |  | 3.x 没有平台礼物 |  | `features/live_play/logic/room_controller.dart:458`、`features/live_play/logic/room_controller.dart:1254` | 立即 | `danmaku_valuable_gifts` | 一样：v4 新加（A08.12，D-040）：默认关，和以前一样显示所有礼物；开着时聊天列表只留值钱以上（约 10 元起）的平台礼物，连击加起来够了再显示；只在“在聊天列表显示礼物”开着时起作用 |
| `giftValueInYuan` | Bool | `false` | —（新加） |  | 3.x 没有平台礼物 |  | `features/live_play/danmaku/chat_list.dart:454`、`features/live_play/danmaku/message_panel.dart:159` | 立即 | `danmaku_gift_yuan` | 一样：v4 新加（A08.12，D-040）：默认关，礼物价值照平台单位写；开着时金瓜子、钻石、抖币、分按平台固定比例写成元，海外币种不换算 |
| `danmakuShowGifts` | Bool | `false` | —（新加） |  | 3.x 没有平台礼物，飞行弹幕只有聊天 |  | `features/live_play/logic/room_controller.dart:300`、`features/multiview/logic/multiview_controller.dart:225`、`features/multiview/logic/multiview_controller.dart:1030` | 读取时 | `danmaku_fly_gifts` | 一样：v4 新加（A08.12，D-040）：默认关，和以前一样礼物不飞；开着时值钱以上的平台礼物飞过直播间画面、全屏、小窗和画中画、多画面、电视，很值钱的在顶部停 4 秒，连击只飞开头和总数，每秒最多 3 条 |
| `superChatIncludesMembership` | Bool | `true` | —（新加） |  | 3.x 没有上舰和会员，醒目留言只有哔哩哔哩、斗鱼、虎牙 |  | `features/live_play/logic/room_controller.dart:304`、`features/live_play/logic/room_controller.dart:459` | 立即 | `danmaku_membership_cards` | 一样：v4 新加（D07.2）：默认开，是 D-040 写明的例外：哔哩哔哩上舰、YouTube 会员，Twitch、CHZZK、Kick、Picarto 的订阅在醒目留言页多一张卡，到点移除；聊天列表里的行开关两种情况都不变；关掉和以前一样 |
| `showChatNames` | Bool | `true` | —（新加） |  | 3.x 没有这个设置，弹幕列表总显示用户名 |  | `features/live_play/danmaku/chat_list.dart:452` | 立即 | `danmaku_show_names` | 一样：v4 新加（A08.10，用户 2026-10-09）：默认开，和 3.x 一样显示用户名；关掉后直播间的弹幕列表只显示内容，长按面板仍显示用户名 |
| `danmakuPausedBehavior` | String | `'pause'` | —（新加） | `pause` / `continue` |  |  | `features/live_play/mini/compact_danmaku.dart:165`、`features/live_play/player/player_view.dart:678`、`features/multiview/multiview_page.dart:883` 等 4 处 | 立即 | `danmaku_paused` | 一样：v4 新加（A07.10 c3），默认值照来源任务 |
| `danmakuFps` | Int | `60` | `60`（`danmaku_settings_controller.dart:70`） | 30～240 | 30～240（`danmaku_settings_controller.dart:123`） | 滑块 30～240，步长 1 | `features/live_play/player/player_view.dart:673`、`shared/danmaku/danmaku_settings.dart:53`、`shared/danmaku/danmaku_templates.dart:38` 等 4 处 | 立即 | `danmaku_fps` | 一样 |
| `danmakuAutoFps` | Bool | `true` | `true`（`danmaku_settings_controller.dart:71`） |  |  |  | `features/live_play/player/player_view.dart:672`、`shared/danmaku/danmaku_settings.dart:52`、`shared/danmaku/danmaku_templates.dart:39` 等 5 处 | 立即 | `danmaku_auto_fps` | 一样 |
| `danmakuMaxVisibleCount` | Int | `48` | —（新加） | 10～120 | 3.x 没有这个设置，直播间和多画面写死 48 | 滑块 10～120，步长 2 | `features/live_play/player/player_view.dart:679`、`features/multiview/multiview_page.dart:897`、`tv/room/tv_live_play_page.dart:472` | 立即 | `danmaku_max_visible` | 一样：v4 新加（D05.2，V01.4，D-036）：默认 48 和 3.x 一样；10～120，超出范围（上游电视版存 0 表示按设备）读成 48 |
| `enableDanmakuTapInteraction` | Bool | `true` | `true`（`danmaku_settings_controller.dart:72`） |  |  |  | `features/live_play/player/player_view.dart:469`、`live_store/src/legacy/legacy_snapshot.dart:430` | 读取时 | `danmaku_tap` | 一样 |
| `enableDanmakuLongPressInteraction` | Bool | `true` | `true`（`danmaku_settings_controller.dart:73`） |  |  |  | `features/live_play/player/player_view.dart:469`、`features/live_play/player/player_view.dart:676`、`live_store/src/legacy/legacy_snapshot.dart:431` | 立即 | `danmaku_long_press` | 一样 |
| `holdDanmakuOnPress` | Bool | `true` | —（新加） |  |  |  | `features/live_play/player/player_view.dart:482` | 读取时 | `danmaku_hold_on_press` | 一样：v4 新加（D03.4，V01.3，D-036）：默认开（D-039，用户 2026-10-09）；按住一条飞行弹幕时它停住，松手继续；关掉和 3.x 一样 |
| `collapseRepeatedDanmaku` | Bool | `false` | `false`（`danmaku_settings_controller.dart:74`） |  |  |  | `features/live_play/logic/room_controller.dart:484`、`features/live_play/logic/room_controller.dart:501`、`features/multiview/logic/multiview_controller.dart:308` 等 4 处 | 立即（直播间和多画面监听它，重建过滤器） | `collapse_repeated` | 一样 |
| `repeatedDanmakuWindowSeconds` | Int | `5` | `5`（`danmaku_settings_controller.dart:75`） | 1～30 | 1～30（`danmaku_settings_controller.dart:259-261`，导入备份时） | 滑块 1～30，步长 1 | `features/live_play/logic/room_controller.dart:485`、`features/live_play/logic/room_controller.dart:502`、`features/multiview/logic/multiview_controller.dart:309` 等 4 处 | 立即（直播间和多画面监听它，重建过滤器） | `repeat_window` | 不一样，已改：注册表原来只有下限 1，3.x 导入时夹到 1～30、设置页滑块也是 1～30；补上 `max: 30` |
| `savedDanmakuTemplate` | String | `''` | `''`（`danmaku_settings_controller.dart:77`） |  |  |  | 弹幕设置的“模板”本身（`shared/danmaku/danmaku_settings_content.dart`、`danmaku_templates.dart`） | 立即 |  | 一样 |
| `danmakuFontFamilyName` | String | `'Default'` | `'Default'`（`danmaku_settings_controller.dart:78`） |  |  |  | `app/fonts.dart:304`、`app/fonts.dart:399`、`app/fonts.dart:400` 等 6 处 | 立即 | `video_danmaku_font` | 一样 |
| `enablePipDanmaku` | Bool | `true` | `true`（`danmaku_settings_controller.dart:17、:79`） |  |  |  | `features/live_play/logic/room_controller.dart:452`、`features/live_play/logic/room_controller.dart:1110`、`features/live_play/mini/compact_danmaku.dart:144` 等 6 处 | 立即 | `pip_danmaku` | 一样 |
| `pipDanmakuAutoScale` | Bool | `true` | `true`（`danmaku_settings_controller.dart:80`） |  |  |  | `features/live_play/mini/compact_danmaku.dart:147`、`shared/danmaku/pip_danmaku_settings.dart:61`、`shared/danmaku/pip_danmaku_settings.dart:62` | 立即 | `pip_auto_scale` | 一样 |
| `pipDanmaNoEmojiMode` | Bool | `false` | `false`（`danmaku_settings_controller.dart:83`） |  |  |  | `features/live_play/mini/compact_danmaku.dart:161`、`shared/danmaku/pip_danmaku_settings.dart:55`、`shared/danmaku/pip_danmaku_settings.dart:56` | 立即 | `pip_no_emoji` | 一样 |
| `pipDanmakuUseOriginalColor` | Bool | `true` | `true`（`danmaku_settings_controller.dart:84`） |  |  |  | `features/live_play/mini/compact_danmaku.dart:154`、`shared/danmaku/pip_danmaku_settings.dart:40`、`shared/danmaku/pip_danmaku_settings.dart:68` | 立即 | `pip_original_color` | 一样 |
| `pipDanmakuColor` | Int | `0xFFFFFFFF` | `0xFFFFFFFF`（`danmaku_settings_controller.dart:85`） | 不限 | 不限 |  | `features/live_play/mini/compact_danmaku.dart:155`、`shared/danmaku/pip_danmaku_settings.dart:41`、`shared/danmaku/pip_danmaku_settings.dart:77` | 立即 | `pip_color` | 一样 |
| `pipDanmakuFontSize` | Double | `12` | `12`（`danmaku_settings_controller.dart:86`） | 8～24 | 8～24（`danmaku_settings_controller.dart:272-274`） | 滑块 8～24，步长 0.5 | `features/live_play/mini/compact_danmaku.dart:148`、`shared/danmaku/pip_danmaku_settings.dart:42`、`shared/danmaku/pip_danmaku_settings.dart:86` | 立即 | `pip_size` | 不一样，已改：注册表原来不限，3.x 存的值和导入的备份都夹到这个范围；改成同样的 `min`/`max`；3.x 在导入备份时夹，设置页滑块同样 8～24 |
| `pipDanmakuFontWeight` | Int | `500` | `500`（`danmaku_settings_controller.dart:87`） | 100～900 | 100～900（`danmaku_settings_controller.dart:124、:275`） | 滑块 100～900，步长 100 | `features/live_play/mini/compact_danmaku.dart:150`、`shared/danmaku/pip_danmaku_settings.dart:43`、`shared/danmaku/pip_danmaku_settings.dart:96` | 立即 | `pip_weight` | 不一样，已改：注册表原来不限，3.x 存的值和导入的备份都夹到这个范围；改成同样的 `min`/`max`；取整到整百同上（J01.3） |
| `pipDanmakuSpeed` | Double | `90` | `90`（`danmaku_settings_controller.dart:88`） | 20～400 | 20～400（`danmaku_settings_controller.dart:276-278`） | 滑块 20～400，步长 1 | `features/live_play/mini/compact_danmaku.dart:149`、`shared/danmaku/pip_danmaku_settings.dart:44`、`shared/danmaku/pip_danmaku_settings.dart:105` | 立即 | `pip_speed` | 不一样，已改：注册表原来不限，3.x 存的值和导入的备份都夹到这个范围；改成同样的 `min`/`max` |
| `pipDanmakuOpacity` | Double | `0.9` | `0.9`（`danmaku_settings_controller.dart:89`） | 0.1～1 | 0.1～1（`danmaku_settings_controller.dart:279-281`） | 滑块 0.1～1，步长 0.05 | `features/live_play/mini/compact_danmaku.dart:151`、`shared/danmaku/pip_danmaku_settings.dart:45`、`shared/danmaku/pip_danmaku_settings.dart:114` | 立即 | `pip_opacity` | 不一样，已改：注册表原来是 0～1，3.x 导入时和设置页滑块都是 0.1～1；下限改成 0.1（0 会让小窗弹幕完全看不见） |
| `pipDanmakuArea` | Double | `0.5` | `0.5`（`danmaku_settings_controller.dart:90`） | 0.1～1 | 0.1～1（`danmaku_settings_controller.dart:282-284`） | 滑块 0.1～1，步长 0.05 | `features/live_play/mini/compact_danmaku.dart:152`、`shared/danmaku/pip_danmaku_settings.dart:46`、`shared/danmaku/pip_danmaku_settings.dart:123` | 立即 | `pip_area` | 不一样，已改：注册表原来是 0～1，3.x 导入时和设置页滑块都是 0.1～1；下限改成 0.1 |
| `pipDanmakuMaxVisibleCount` | Int | `6` | `6`（`danmaku_settings_controller.dart:91`） | 1～20 | 1～20（`danmaku_settings_controller.dart:285-287`） | 加减 1～20 | `features/live_play/mini/compact_danmaku.dart:153`、`shared/danmaku/pip_danmaku_settings.dart:128`、`shared/danmaku/pip_danmaku_settings.dart:131` | 立即 | `pip_max_visible` | 不一样，已改：注册表原来只有下限 1，3.x 导入时和设置页加减都是 1～20；补上 `max: 20` |
| `pipDanmakuEmitInterval` | Double | `0.35` | `0.35`（`danmaku_settings_controller.dart:92`） | 0.05～2 | 0.05～2（`danmaku_settings_controller.dart:288-290`） | 滑块 0.05～2，步长 0.05 | `features/live_play/mini/compact_danmaku.dart:163`、`shared/danmaku/pip_danmaku_settings.dart:47`、`shared/danmaku/pip_danmaku_settings.dart:140` | 立即 | `pip_interval` | 不一样，已改：注册表原来不限，3.x 存的值和导入的备份都夹到这个范围；改成同样的 `min`/`max` |
| `pipDanmakuFps` | Int | `30` | `30`（`danmaku_settings_controller.dart:93`） | 15～240 | 15～240（`danmaku_settings_controller.dart:291`） | 滑块 15～240（`playback_tiles.dart` 的 `PipFpsTile`） | `features/live_play/mini/compact_danmaku.dart:159`、`shared/danmaku/pip_danmaku_settings.dart:49`、`shared/danmaku/pip_danmaku_settings.dart:168` | 立即 | `pip_fps` | 不一样，已改：注册表原来不限，3.x 存的值和导入的备份都夹到这个范围；改成同样的 `min`/`max` |
| `pipDanmakuAutoFps` | Bool | `true` | `true`（`danmaku_settings_controller.dart:94`） |  |  |  | `features/live_play/mini/compact_danmaku.dart:158`、`shared/danmaku/pip_danmaku_settings.dart:48`、`shared/danmaku/pip_danmaku_settings.dart:147` | 立即 | `pip_auto_fps` | 一样 |
| `filterDouyuSuspectedAutomatedMessages` | Bool | `false` | `false`（`danmaku_settings_controller.dart:35、:99-102`） |  |  |  | `app/platforms.dart:243` | 立即（斗鱼弹幕每条消息都读） | `video_block_list` | 一样 |
| `enableDanmakuSimilarityFilter` | Bool | `false` | `false`（`danmaku_settings_controller.dart:39、:105-108`） |  |  |  | `features/live_play/logic/room_controller.dart:486`、`features/live_play/logic/room_controller.dart:503`、`features/multiview/logic/multiview_controller.dart:310` 等 4 处 | 立即（直播间和多画面监听它，重建过滤器） | `video_block_list` | 一样 |
| `danmakuSimilarityThreshold` | Int | `85` | `85`（`danmaku_settings_controller.dart:109`） | 50～100 | 50～100（`danmaku_settings_controller.dart:125`） | 滑块 50～100（屏蔽页 `block_manager.dart`） | `features/live_play/logic/room_controller.dart:487`、`features/live_play/logic/room_controller.dart:504`、`features/multiview/logic/multiview_controller.dart:311` 等 4 处 | 立即（直播间和多画面监听它，重建过滤器） | `video_block_list` | 一样 |
| `danmakuSimilarityCacheDuration` | Int | `3` | `3`（`danmaku_settings_controller.dart:110`） | 1～60 | 1～60（`danmaku_settings_controller.dart:126`） | 滑块 1～60（屏蔽页 `block_manager.dart`） | `features/live_play/logic/room_controller.dart:488`、`features/live_play/logic/room_controller.dart:505`、`features/multiview/logic/multiview_controller.dart:312` 等 4 处 | 立即（直播间和多画面监听它，重建过滤器） | `video_block_list` | 一样 |
| `danmakuSimilarityMaxCacheSize` | Int | `100` | `100`（`danmaku_settings_controller.dart:111`） | 20～1000 | 20～1000（`danmaku_settings_controller.dart:127`） | 滑块 20～1000（屏蔽页 `block_manager.dart`） | `features/live_play/logic/room_controller.dart:489`、`features/live_play/logic/room_controller.dart:506`、`features/multiview/logic/multiview_controller.dart:313` 等 4 处 | 立即（直播间和多画面监听它，重建过滤器） | `video_block_list` | 一样 |
| `blockEmoteOnlyDanmaku` | Bool | `false` | —（新加） |  |  | 开关（屏蔽页 `block_manager.dart`“按内容屏蔽”） | `features/live_play/logic/room_controller.dart:490`、`features/live_play/logic/room_controller.dart:509`、`features/multiview/logic/multiview_controller.dart:314` 等 4 处 | 立即（直播间和多画面监听它，重建过滤器） | `video_block_list` | 一样：v4 新加（D02.2，V03.6 E11，D-040）：默认关，和 3.x 一样（3.x 没有这个屏蔽）；只有表情的平台弹幕不显示 |
| `blockLongDanmaku` | Bool | `false` | —（新加） |  |  | 开关（屏蔽页 `block_manager.dart`“按内容屏蔽”） | `features/live_play/logic/room_controller.dart:491`、`features/live_play/logic/room_controller.dart:510`、`features/multiview/logic/multiview_controller.dart:315` 等 4 处 | 立即（直播间和多画面监听它，重建过滤器） | `video_block_list` | 一样：v4 新加（D02.2，D-040）：默认关，和 3.x 一样；超过“最多字数”的平台弹幕不显示 |
| `blockLongDanmakuLength` | Int | `30` | —（新加） | 10～100 | 3.x 没有这个设置 | 滑块 10～100（屏蔽页 `block_manager.dart`，“屏蔽超长弹幕”关着时变灰） | `features/live_play/logic/room_controller.dart:492`、`features/live_play/logic/room_controller.dart:511`、`features/multiview/logic/multiview_controller.dart:316` 等 4 处 | 立即（直播间和多画面监听它，重建过滤器） | `video_block_list` | 一样：v4 新加（D02.2）：默认 30，10～100（超出范围夹到两端），一个表情算一个字 |
| `youtubeShowAllChat` | Bool | `false` | —（新加） |  |  |  | `app/platforms.dart:268`、`features/live_play/logic/room_controller.dart:468` | 立即 | `youtube_all_chat` | 一样：v4 新加（UPGRADES B-13），默认值照来源任务 |

## 音量（volume）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `defaultMobileVolume` | Double | `0.5` | `0.5`（`volume_settings_controller.dart:8`） | 0～1 | 0～1（`volume_settings_controller.dart:103-106`） | 滑块 0～1，步长 0.01 | `features/multiview/logic/multiview_controller.dart:893` | 读取时 | `mobile_volume` | 一样：直播间里手机音量固定 1、只有多画面读它，和 3.x 一样（3.x 的适配器在手机上强制 1.0，见 G05 说明） |
| `defaultDesktopVolume` | Double | `1` | `1`（`volume_settings_controller.dart:9`） | 0～1 | 0～1（同上） | 滑块 0～1，步长 0.01 | `features/live_play/logic/room_controller.dart:815`、`features/multiview/logic/multiview_controller.dart:894` | 读取时 | `desktop_volume` | 一样 |
| `globalVolumeMute` | Bool | `false` | `false`（`volume_settings_controller.dart:10`） |  |  |  | `features/live_play/logic/room_controller.dart:802`、`features/multiview/logic/multiview_controller.dart:891` | 读取时 | `global_mute` | 一样 |
| `roomVolumes` | Json | `{}` | `'{}'`（`volume_settings_controller.dart:11`） |  |  |  | `features/live_play/logic/room_controller.dart:806`、`features/live_play/logic/room_controller.dart:834`、`features/live_play/logic/room_controller.dart:836` 等 6 处 | 读取时 |  | 一样：3.x 在 Hive 里存 JSON 字符串 `'{}'`，v4 存映射；每个房间的值读出时夹到 0～1（`live_player` 的 `roomVolume`） |

## 直播间卡片（roomCard）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `room_card_mobile_preset` | String | `'normal'` | `'normal'`（`room_card_settings_controller.dart:15、:251`） | `compact` / `normal` / `rich` / `custom` |  |  | `shared/rooms/room_cards.dart:144`、`shared/rooms/room_cards.dart:153` | 立即 | `room_card` | 一样 |
| `room_card_desktop_preset` | String | `'normal'` | `'normal'`（`room_card_settings_controller.dart:252`） | `compact` / `normal` / `rich` / `custom` |  |  | `shared/rooms/room_cards.dart:144`、`shared/rooms/room_cards.dart:153` | 立即 | `room_card` | 一样 |
| `room_card_mobile_config` | Json | `{}` | `{}`（`room_card_settings_controller.dart:253-259`） |  |  |  | `shared/rooms/room_cards.dart:145`、`shared/rooms/room_cards.dart:154` | 立即 | `room_card` | 一样：3.x 没存时用预设的外观（`_storedPresetFallback`），v4 的空映射同样表示“用预设” |
| `room_card_desktop_config` | Json | `{}` | `{}`（`room_card_settings_controller.dart:260-266`） |  |  |  | `shared/rooms/room_cards.dart:145`、`shared/rooms/room_cards.dart:154` | 立即 | `room_card` | 一样：同上 |

## 翻页（page）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `page_show_size_selector` | Bool | `true` | `true`（`page_settings_controller.dart:14`） |  |  |  | `features/areas/platform_areas_view.dart:236`、`features/favorite/favorite_page.dart:400`、`shared/rooms/room_grid.dart:511` | 立即 | `page_size_selector` | 一样 |
| `page_show_goto_button` | Bool | `true` | `true`（`page_settings_controller.dart:15`） |  |  |  | `features/areas/platform_areas_view.dart:237`、`features/favorite/favorite_page.dart:401`、`shared/rooms/room_grid.dart:512` | 立即 | `page_goto` | 一样 |
| `page_show_scroll_top` | Bool | `true` | `true`（`page_settings_controller.dart:16`） |  |  |  | `features/favorite/favorite_page.dart:399`、`shared/rooms/room_grid.dart:510` | 立即 | `page_scroll_top` | 一样 |
| `page_default_size` | Int | `0` | `12`（`page_settings_controller.dart:17、:23-34（宽于 960 逻辑像素是 20）`） | 0～100 | 1～100 且必须是可选的条数之一，否则取第一个（`page_settings_controller.dart:9-10`、:51-62） | 数字框，预设 `[0, 12, 20, 30, 40, 60]` | `features/areas/platform_areas_view.dart:238`、`shared/rooms/paging.dart:30`、`shared/rooms/room_grid.dart:513` | 立即 | `page_default_size` | 确认改动：v4 默认 0 = 由界面按宽度定（`shared/rooms/paging.dart` 的 `pageSizesOf`，结果和 3.x 一样是 12 或 20），J02.1 有意差异（纯 Dart 包拿不到屏幕宽度）；3.x 读到 v4 备份里的 0 时取可选条数的第一个，同样是 12 或 20 |
| `page_size_options_raw` | String | `''` | `''`（`page_settings_controller.dart:19`） |  |  |  | `features/areas/platform_areas_view.dart:239`、`shared/rooms/paging.dart:24`、`shared/rooms/room_grid.dart:514` 等 5 处 | 立即 | `page_size_options` | 一样：空 = 按宽度用 3.x 的默认可选条数（12/24/36/48 或 20/40/60/80），和 3.x 一样 |

## 刷新（refresh）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `autoRefreshFavorite` | Bool | `false` | `false`（`refresh_config_controller.dart:21`） |  |  |  | `features/favorite/favorite_controller.dart:341`、`features/favorite/favorite_controller.dart:359` | 立即（重排定时器） | `auto_refresh` | 一样 |
| `refreshFavoriteOnResume` | Bool | `true` | `true`（`refresh_config_controller.dart:26`） |  |  |  | `features/favorite/favorite_controller.dart:334` | 读取时 | `refresh_on_resume` | 一样 |
| `autoRefreshInterval` | Int | `30` | `30`（`refresh_config_controller.dart:27`） | 5～360 | 5～360（`refresh_config_controller.dart:6-14`） | 选项 5～360 分钟，12 档 | `features/favorite/favorite_controller.dart:342`、`features/favorite/favorite_controller.dart:360` | 立即（重排定时器） | `refresh_interval` | 一样 |
| `maxConcurrentRefresh` | Int | `4` | `4`（`refresh_config_controller.dart:28`） | 1～20 | 1～20（`refresh_config_controller.dart:9-18`） | 加减 1～20 | `features/favorite/favorite_controller.dart:309`、`features/history/history_page.dart:92` | 读取时 | `refresh_concurrency` | 一样 |
| `liveAlertEnabled` | Bool | `false` | —（新加） |  |  |  | `features/favorite/favorite_controller.dart` 的 `liveAlerts`（每轮刷新后比较）和 `_scheduleAutoRefresh`（没开“关注自动刷新”时每 15 分钟只查要提醒的关注） | 立即（重排定时器；关掉时忘记看到过的状态） | `live_alert` | 一样：v4 新加（O01.1，V01.1，D-036）：默认关，和以前一样不发通知；开了以后关注的主播开播时发系统通知（只在 Android） |
| `liveAlertTagIds` | StringList | `[]` | —（新加） |  |  |  | `features/favorite/favorite_controller.dart:231` | 下一轮检查 | `live_alert_tags` | 一样：v4 新加（O01.1，V01.1）：空 = 提醒全部关注；选了标签只提醒带这些标签的关注，已删除的标签不算 |
| `autoRefreshThumbnails` | Bool | `false` | `false`（`refresh_config_controller.dart:29`） |  |  |  | 同上（`CoverRefreshTimer`） | 立即 | `refresh_covers` | 一样 |
| `thumbnailRefreshInterval` | Int | `30` | `30`（`refresh_config_controller.dart:30`） | 5～360 | 5～360（`refresh_config_controller.dart:6-14`） | 选项 5～360 分钟，8 档 | 封面刷新定时器 `features/settings/data_tools.dart` 的 `CoverRefreshTimer`（启动时接上，F-APP-20） | 立即 | `cover_interval` | 一样 |

## 网络电视（iptv）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `selectedSourceName` | String | `''` | `''`（`iptv_settings_controller.dart:22`） |  |  |  | `features/iptv/iptv_page.dart:78`、`features/iptv/iptv_page.dart:87` | 读取时 |  | 一样 |
| `selectedSourceId` | String | `''` | `''`（`iptv_settings_controller.dart:23`） |  |  |  | `app/bootstrap.dart:314`、`app/bootstrap.dart:332`、`features/iptv/iptv_page.dart:70` 等 8 处 | 立即 |  | 一样 |
| `isAutoSyncEnabled` | Bool | `false` | `false`（`iptv_settings_controller.dart:24`） |  |  |  | `app/bootstrap.dart:315`、`app/bootstrap.dart:413`、`features/iptv/iptv_page.dart:687` 等 4 处 | 立即 |  | 一样 |
| `autoSyncHoursInterval` | Int | `24` | `24`（`iptv_settings_controller.dart:25`） | 2～72 | 2～72（`iptv_settings_controller.dart:7-12`） | 网络电视页的选项 | `app/bootstrap.dart:417`、`features/iptv/iptv_page.dart:688`、`features/iptv/iptv_page.dart:711` | 立即 |  | 一样 |
| `customIptvUserAgent` | String | `''` | `''`（`iptv_settings_controller.dart:26`） |  |  |  | `features/iptv/iptv_page.dart:689`、`features/iptv/iptv_page.dart:722`、`features/live_play/logic/room_controller.dart:751` | 立即 |  | 一样 |
| `m3uDirectory` | String | `'m3uDirectory'` | `'m3uDirectory'`（`iptv_settings_controller.dart:27`） |  |  |  | 没有读取 |  |  | 一样：3.x 的默认值就是这个字面量；3.x 也没有读取它的代码 |

## 代理（proxy）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `enableProxy` | Bool | `false` | `false`（`proxy_settings_controller.dart:11`） |  |  |  | `app/platforms.dart:45`、`platform/system_access.dart:83`、`platform/system_access.dart:90` | 下一个请求（每个请求都读） | `player_proxy_link` | 一样 |
| `proxyHost` | String | `''` | `''`（`proxy_settings_controller.dart:12`） |  |  |  | `app/platforms.dart:46`、`platform/system_access.dart:84`、`platform/system_access.dart:90` | 下一个请求（每个请求都读） | `player_proxy` | 一样 |
| `proxyPort` | Int | `7897` | `7897`（`proxy_settings_controller.dart:9、:13`，`core/common/proxy_routing.dart:1`） | 1～65535 | 1～65535，越界回到 7897（`core/common/proxy_routing.dart:2-9`） | 代理对话框的数字框 | `app/platforms.dart:47` | 下一个请求（每个请求都读） | `player_proxy` | 不一样，已改：默认值和范围一样；越界时 3.x 回到 7897，v4 原来夹到 1 或 65535，J01.3 改成和 3.x 一样回到默认值（`IntSetting` 的 `resetOutOfRange`） |
| `enableAppProxy` | Bool | `false` | `false`（`proxy_settings_controller.dart:16`） |  |  |  | `app/platforms.dart:23`、`platform/system_access.dart:81`、`platform/system_access.dart:89` | 下一个请求（每个请求都读） | `app_proxy` | 一样 |
| `appProxyHost` | String | `''` | `''`（`proxy_settings_controller.dart:17`） |  |  |  | `app/platforms.dart:24`、`platform/system_access.dart:82`、`platform/system_access.dart:89` | 下一个请求（每个请求都读） | `app_proxy` | 一样 |
| `appProxyPort` | Int | `7897` | `7897`（`proxy_settings_controller.dart:18`） | 1～65535 | 同上 | 代理对话框的数字框 | `app/platforms.dart:25` | 下一个请求（每个请求都读） | `app_proxy` | 不一样，已改：同上，J01.3 改成和 3.x 一样回到默认值（`IntSetting` 的 `resetOutOfRange`） |

## 窗口（windowSize）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `window_width` | Double | `1280` | `1280`（`window_size_controller.dart:103`） | 400～16384 | 400～16384（`window_size_controller.dart:97-101`、:320-324） | 窗口大小对话框 | `app/desktop/desktop_window.dart:289`、`app/desktop/desktop_window.dart:529` | 读取时 | `window_size` | 一样 |
| `window_height` | Double | `720` | `720`（`window_size_controller.dart:104`） | 300～16384 | 300～16384（同上） | 窗口大小对话框 | `app/desktop/desktop_window.dart:290`、`app/desktop/desktop_window.dart:530` | 读取时 | `window_size` | 一样 |
| `rememberPipPosition` | Bool | `true` | `true`（`window_size_controller.dart:107`） |  |  |  | `app/desktop/mini_window.dart:138`、`app/desktop/mini_window.dart:228` | 读取时 | `pip_remember_position` | 一样 |
| `windows_pip_display_id` | String | `''` | `''`（`window_size_controller.dart:8`） |  |  |  | `app/desktop/mini_window.dart:139`、`app/desktop/mini_window.dart:238` | 读取时 | `pip_reset_position` | 一样 |
| `windows_pip_width` | Double | `0` | `0`（`window_size_controller.dart:11`） | 0～16384 | 0～16384；宽或高 ≤ 0 时四个都归零（`window_size_controller.dart:277-313`） |  | `app/desktop/mini_window.dart:141`、`app/desktop/mini_window.dart:234` | 读取时 | `pip_reset_position` | 不一样，已改：注册表原来不限；补上 3.x 的 0～16384（只有 Windows 用）。“宽或高 ≤ 0 时都归零”在读的地方做（`mini_window.dart` 只在宽高都大于 0 时恢复） |
| `windows_pip_height` | Double | `0` | `0`（`window_size_controller.dart:14`） | 0～16384 | 同上 |  | `app/desktop/mini_window.dart:142`、`app/desktop/mini_window.dart:235` | 读取时 | `pip_reset_position` | 不一样，已改：同上 |
| `windows_pip_x` | Double | `0` | `0`（`window_size_controller.dart:17`） | 不限 | 不限 |  | `app/desktop/mini_window.dart:144`、`app/desktop/mini_window.dart:236` | 读取时 | `pip_reset_position` | 一样 |
| `windows_pip_y` | Double | `0` | `0`（`window_size_controller.dart:20`） | 不限 | 不限 |  | `app/desktop/mini_window.dart:144`、`app/desktop/mini_window.dart:237` | 读取时 | `pip_reset_position` | 一样 |

## 退出（exit）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `dontAskExit` | Bool | `false` | `false`（`exit_settings_controller.dart:23`） |  |  |  | `app/desktop/close_dialog.dart:47`、`app/desktop/close_dialog.dart:113`、`app/desktop/close_dialog.dart:116` 等 5 处 | 读取时 | `close_window` | 一样 |
| `exitChoose` | String | `'exit'` | `'exit'`（`exit_settings_controller.dart:10、:24`） | `exit` / `minimize` |  |  | `app/desktop/close_dialog.dart:9`、`app/desktop/close_dialog.dart:46`、`app/desktop/close_dialog.dart:112` 等 5 处 | 读取时 | `close_window` | 一样 |
| `autoShutDownTime` | Int | `120` | `120`（`exit_settings_controller.dart:13、:25`） | 1～525600 | 1～525600（`exit_settings_controller.dart:13-17`） | 数字对话框 | 定时退出 `features/settings/settings_editors.dart` 的 `AutoExitTimer`（设置页打开时接上，F-APP-21） | 立即（重新计时） | `auto_exit_minutes` | 一样 |
| `enableAutoShutDownTime` | Bool | `false` | `false`（`exit_settings_controller.dart:26`） |  |  |  | 同上（`AutoExitTimer`） | 立即 | `auto_exit` | 一样 |

## 开机启动（startup）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `enableStartUp` | Bool | `true` | `true`（`startup_controller.dart:25`） |  |  |  | `app/desktop/desktop_window.dart:226`、`app/desktop/desktop_window.dart:353`、`app/desktop/desktop_window.dart:379` | 读取时 | `startup` | 一样 |

## 录制（recorder）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `segmentTime` | Int | `300` | `300`（`recorder/consts/recorder_config.dart:99`） | 60～3600 | 60～3600（`recorder/consts/recorder_config.dart:56-57`） | 滑块 1～60 分钟（录制设置页 `record_settings_page.dart`） | `app/recording.dart:262`、`app/recording.dart:308`、`app/recording.dart:332` | 读取时 |  | 一样 |
| `maxTaskCount` | Int | `3` | `3`（`recorder/consts/recorder_config.dart:109`） | 1～10 | 1～10（`recorder/consts/recorder_config.dart:58-59`） | 加减 1～10（录制设置页 `record_settings_page.dart`） | `app/recording.dart:263`、`app/recording.dart:309`、`app/recording.dart:333` | 读取时 |  | 一样 |
| `autoReconnect` | Bool | `true` | `true`（`recorder/pages/record_settings/record_settings_controller.dart:47`） |  |  |  | `app/recording.dart:264`、`app/recording.dart:310`、`app/recording.dart:334` | 读取时 |  | 一样 |
| `maxCacheMB` | Int | `1024` | `1024`（`recorder/consts/recorder_config.dart:126`） | ≥ 1 | ≥ 1（`recorder/consts/recorder_config.dart:60`、:76） | 数字对话框（录制设置页 `record_settings_page.dart`） | `app/recording.dart:265`、`app/recording.dart:311`、`app/recording.dart:335` | 读取时 |  | 一样 |
| `enableCacheLimit` | Bool | `false` | `false`（`recorder/pages/record_settings/record_settings_controller.dart:66`） |  |  |  | `app/recording.dart:266`、`app/recording.dart:312`、`app/recording.dart:336` | 读取时 |  | 一样 |
| `recordSavePath` | String，本机 | `''` | `''`（`recorder/consts/recorder_config.dart:142`） |  |  |  | `app/recording.dart:267`、`app/recording.dart:313`、`app/recording.dart:337` | 读取时 |  | 一样 |
| `default_quality` | String | `'原画'` | `'原画'`（`recorder/consts/recorder_config.dart:151-152`） | `原画` / `蓝光8M` / `蓝光4M` / `超清` / `流畅` |  |  | `app/recording.dart:268`、`app/recording.dart:314`、`app/recording.dart:338` | 读取时 |  | 一样 |
| `max_retry_count` | Int | `5` | `5`（`recorder/consts/recorder_config.dart:162`） | 1～20 | 1～20（`recorder/consts/recorder_config.dart:61-62`） | 滑块 1～20（录制设置页 `record_settings_page.dart`） | `app/recording.dart:269`、`app/recording.dart:315`、`app/recording.dart:339` | 读取时 |  | 一样 |
| `retry_delay` | Int | `30` | `30`（`recorder/consts/recorder_config.dart:171`） | 5～120 | 5～120（`recorder/consts/recorder_config.dart:63-64`） | 滑块 5～120（录制设置页 `record_settings_page.dart`） | `app/recording.dart:270`、`app/recording.dart:316`、`app/recording.dart:340` | 读取时 |  | 一样 |
| `enable_polling` | Bool | `false` | `false`（`recorder/pages/record_settings/record_settings_controller.dart:54`） |  |  |  | `app/recording.dart:271`、`app/recording.dart:317`、`app/recording.dart:341` 等 4 处 | 读取时 |  | 一样 |
| `live_check_interval` | Int | `30` | `30`（`recorder/consts/recorder_config.dart:189`） | 10～300 | 10～300（`recorder/consts/recorder_config.dart:65-66`） | 滑块 10～300（录制设置页 `record_settings_page.dart`） | `app/recording.dart:272`、`app/recording.dart:318`、`app/recording.dart:342` | 读取时 |  | 一样 |
| `enable_backoff` | Bool | `false` | `false`（`recorder/pages/record_settings/record_settings_controller.dart:56`） |  |  |  | `app/recording.dart:273`、`app/recording.dart:319`、`app/recording.dart:343` | 读取时 |  | 一样 |
| `max_check_interval` | Int | `300` | `300`（`recorder/consts/recorder_config.dart:207`） | 300～3600 | 300～3600（`recorder/consts/recorder_config.dart:67-68`） | 滑块 5～60 分钟（录制设置页 `record_settings_page.dart`） | `app/recording.dart:274`、`app/recording.dart:320`、`app/recording.dart:344` | 读取时 |  | 一样 |
| `auto_start_on_boot` | Bool | `false` | `false`（`recorder/pages/record_settings/record_settings_controller.dart:59`） |  |  |  | `app/recording.dart:275`、`app/recording.dart:321`、`app/recording.dart:345` | 读取时 |  | 一样 |
| `recorder_prefer_best_stream` | Bool | `true` | `true`（`recorder/pages/record_settings/record_settings_controller.dart:40`） |  |  |  | `app/recording.dart:276`、`app/recording.dart:322`、`app/recording.dart:346` | 读取时 |  | 一样 |
| `recorder_rw_timeout` | Int | `15` | `15`（`recorder/consts/recorder_config.dart:248`） | 15～60 | 15 / 30 / 60，别的值回到 15（`recorder/consts/recorder_config.dart:69`、:86） | 选项 15 / 30 / 60（录制设置页 `record_settings_page.dart`） | `app/recording.dart:277`、`app/recording.dart:323`、`app/recording.dart:347` | 读取时 |  | 一样：注册表夹到 15～60，`live_record` 的 `RecordSettings` 再按 3.x 只认 15 / 30 / 60（`packages/live_record/lib/src/settings.dart:45`），结果一样 |
| `recorder_thread_queue_size` | Int | `2048` | `2048`（`recorder/consts/recorder_config.dart:255`） | 512～8192 | 512 / 1024 / 2048 / 4096 / 8192，别的值回到 2048（`recorder/consts/recorder_config.dart:70`、:88-89） | 选项（录制设置页 `record_settings_page.dart`） | `app/recording.dart:278`、`app/recording.dart:324`、`app/recording.dart:348` | 读取时 |  | 一样：同上，`RecordSettings` 按 3.x 只认这 5 个（`settings.dart:46`） |
| `recorder_folder_naming_strategy` | Bool | `false` | `false`（`recorder/pages/record_settings/record_settings_controller.dart:60`） |  |  |  | `app/recording.dart:279`、`app/recording.dart:325`、`app/recording.dart:349` | 读取时 |  | 一样 |
| `recorder_record_danmaku` | Bool | `false` | `false`（`recorder/pages/record_settings/record_settings_controller.dart:63`） |  |  |  | `app/recording.dart:280`、`app/recording.dart:326`、`app/recording.dart:350` | 读取时 |  | 一样 |

## 本地互动（localInteraction）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `localInteraction.enabled` | Bool | `true` | `true`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:86`） |  |  |  | `features/live_play/buttons/room_menu_button.dart:312`、`features/live_play/local_interaction/local_interaction_scope.dart:34`、`features/live_play/local_interaction/logic/local_interaction.dart:283` 等 4 处 | 立即 |  | 一样 |
| `localInteraction.userName` | String | `'Pure Live'` | `'Pure Live'`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:87`） |  | 最多 20 个字（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:821-824`） |  | `features/live_play/local_interaction/logic/local_interaction.dart:289`、`features/live_play/local_interaction/logic/local_interaction.dart:347` | 读取时 |  | 一样：v4 保存时同样截到 20 个字 |
| `localInteraction.title` | String | `'listener'` | `'listener'`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:88`） | `listener` / `night_owl` / `supporter` / `guardian` |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:292`、`features/live_play/local_interaction/logic/local_interaction.dart:295` | 读取时 |  | 一样 |
| `localInteraction.showAsDanmaku` | Bool | `true` | `true`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:89`） |  |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:301`、`features/live_play/local_interaction/logic/local_interaction.dart:303` | 读取时 |  | 一样 |
| `localInteraction.showPlatformBadge` | Bool | `true` | `true`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:90`） |  |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:306`、`features/live_play/local_interaction/logic/local_interaction.dart:308` | 读取时 |  | 一样 |
| `localInteraction.showLevelBadge` | Bool | `true` | `true`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:91`） |  |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:311`、`features/live_play/local_interaction/logic/local_interaction.dart:313` | 读取时 |  | 一样 |
| `localInteraction.enableGiftEffects` | Bool | `true` | `true`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:92`） |  |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:316`、`features/live_play/local_interaction/logic/local_interaction.dart:318` | 读取时 |  | 一样 |
| `localInteraction.previewPlatform` | String | `'bilibili'` | `'bilibili'`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:93`） |  |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:321`、`features/live_play/local_interaction/logic/local_interaction.dart:323` | 读取时 |  | 一样 |
| `localInteraction.coins` | Int | `1000` | `1000`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:94`） | ≥ 0 | 不限 |  | `features/live_play/local_interaction/logic/local_interaction.dart:326`、`features/live_play/local_interaction/logic/local_interaction.dart:649`、`features/live_play/local_interaction/logic/local_interaction.dart:708` 等 4 处 | 读取时 |  | 一样：v4 下限 0（3.x 送礼前检查余额，不会存负数），没有实际差别 |
| `localInteraction.experience` | Int | `0` | `0`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:95`） | ≥ 0 | 不限 |  | `features/live_play/local_interaction/logic/local_interaction.dart:329`、`features/live_play/local_interaction/logic/local_interaction.dart:648`、`features/live_play/local_interaction/logic/local_interaction.dart:854` | 读取时 |  | 一样：同上 |
| `localInteraction.history` | StringList | `[]` | `[]`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:96`） |  | 最多 30 条（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:907`） |  | `features/live_play/local_interaction/logic/local_interaction.dart:337`、`features/live_play/local_interaction/logic/local_interaction.dart:709`、`features/live_play/local_interaction/logic/local_interaction.dart:736` 等 5 处 | 读取时 |  | 一样 |
| `localInteraction.danmakuPreset` | String | `'clean'` | `'clean'`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:97`） |  |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:952`、`features/live_play/local_interaction/logic/local_interaction.dart:1012`、`features/live_play/local_interaction/logic/local_interaction.dart:1016` | 读取时 |  | 一样 |
| `localInteraction.danmakuColor` | Int | `0xFFFFFFFF` | `0xFFFFFFFF`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:98`） | 不限 |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:959`、`features/live_play/local_interaction/logic/local_interaction.dart:1017` | 读取时 |  | 一样 |
| `localInteraction.danmakuFontSize` | Double | `19` | `19`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:99`） | 14～32 | 14～32（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:745`） | 滑块 14～32（本地互动样式面板 `local_style_panel.dart`） | `features/live_play/local_interaction/logic/local_interaction.dart:962`、`features/live_play/local_interaction/logic/local_interaction.dart:1018` | 读取时 |  | 一样 |
| `localInteraction.danmakuSpeed` | Double | `130` | `130`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:100`） | 60～260 | 60～260（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:746`） | 滑块 60～260（本地互动样式面板 `local_style_panel.dart`） | `features/live_play/local_interaction/logic/local_interaction.dart:965`、`features/live_play/local_interaction/logic/local_interaction.dart:1019` | 读取时 |  | 一样 |
| `localInteraction.danmakuFontWeight` | Int | `600` | `600`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:101`） | 400～900 | 400～900（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:747`） |  | `features/live_play/local_interaction/logic/local_interaction.dart:968`、`features/live_play/local_interaction/logic/local_interaction.dart:1020` | 读取时 |  | 一样 |
| `localInteraction.danmakuShowStroke` | Bool | `true` | `true`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:102`） |  |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:971`、`features/live_play/local_interaction/logic/local_interaction.dart:1021` | 读取时 |  | 一样 |
| `localInteraction.danmakuStrokeWidth` | Double | `1.5` | `1.5`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:103`） | 0～4 | 画的时候 0.5～4（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:749`） | 滑块 0.5～4（本地互动样式面板 `local_style_panel.dart`） | `features/live_play/local_interaction/logic/local_interaction.dart:974`、`features/live_play/local_interaction/logic/local_interaction.dart:1022` | 读取时 |  | 一样：存的值 3.x 不限、画的时候夹到 0.5～4；v4 存的值夹到 0～4，画的时候同样夹到 0.5～4（`local_interaction.dart` 的样式） |
| `localInteraction.danmakuPlacement` | String | `'scroll'` | `'scroll'`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:104`） | `scroll` / `top` / `bottom` |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:977`、`features/live_play/local_interaction/logic/local_interaction.dart:1023` | 读取时 |  | 一样 |
| `localInteraction.danmakuFontFamily` | String | `'system'` | `'system'`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:105`） | `system` / `rounded` / `serif` / `mono` |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:980`、`features/live_play/local_interaction/logic/local_interaction.dart:1024` | 读取时 |  | 一样 |
| `localInteraction.danmakuItalic` | Bool | `false` | `false`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:106`） |  |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:983`、`features/live_play/local_interaction/logic/local_interaction.dart:1025` | 读取时 |  | 一样 |
| `localInteraction.danmakuOpacity` | Double | `1` | `1`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:107`） | 0.35～1 | 0.35～1（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:753`） | 滑块 0.35～1（本地互动样式面板 `local_style_panel.dart`） | `features/live_play/local_interaction/logic/local_interaction.dart:986`、`features/live_play/local_interaction/logic/local_interaction.dart:1026` | 读取时 |  | 一样 |
| `localInteraction.danmakuLetterSpacing` | Double | `0` | `0`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:108`） | -0.5～3 | -0.5～3（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:754`） | 滑块 -0.5～3（本地互动样式面板 `local_style_panel.dart`） | `features/live_play/local_interaction/logic/local_interaction.dart:989`、`features/live_play/local_interaction/logic/local_interaction.dart:1027` | 读取时 |  | 一样 |
| `localInteraction.danmakuStrokeColor` | Int | `0xFF000000` | `0xFF000000`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:109`） | 不限 |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:992`、`features/live_play/local_interaction/logic/local_interaction.dart:1028` | 读取时 |  | 一样 |
| `localInteraction.danmakuShowShadow` | Bool | `false` | `false`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:110`） |  |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:995`、`features/live_play/local_interaction/logic/local_interaction.dart:1029` | 读取时 |  | 一样 |
| `localInteraction.danmakuShadowColor` | Int | `0xFF000000` | `0xFF000000`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:111`） | 不限 |  |  | `features/live_play/local_interaction/logic/local_interaction.dart:998`、`features/live_play/local_interaction/logic/local_interaction.dart:1030` | 读取时 |  | 一样 |
| `localInteraction.danmakuShadowBlur` | Double | `2` | `2`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:112`） | 0～6 | 0～6（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:758`） | 滑块 0～6（本地互动样式面板 `local_style_panel.dart`） | `features/live_play/local_interaction/logic/local_interaction.dart:1001`、`features/live_play/local_interaction/logic/local_interaction.dart:1031` | 读取时 |  | 一样 |
| `localInteraction.danmakuShadowOffset` | Double | `1` | `1`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:113`） | 0～4 | 0～4（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:759`） | 滑块 0～4（本地互动样式面板 `local_style_panel.dart`） | `features/live_play/local_interaction/logic/local_interaction.dart:1004`、`features/live_play/local_interaction/logic/local_interaction.dart:1032` | 读取时 |  | 一样 |
| `localInteraction.danmakuFixedDurationMs` | Int | `4000` | `4000`（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:114`） | 2000～10000 | 2000～10000（`modules/live_play/widgets/local_interaction/local_interaction_controller.dart:760`） | 滑块 2000～10000（本地互动样式面板 `local_style_panel.dart`） | `features/live_play/local_interaction/logic/local_interaction.dart:1007`、`features/live_play/local_interaction/logic/local_interaction.dart:1033` | 读取时 |  | 一样 |
| `localInteraction.replayOnEnter` | Bool | `true` | —（新加） |  | 3.x 没有这个设置，离开直播间本地弹幕就没了 |  | `features/live_play/local_interaction/logic/local_interaction.dart:444`、`features/live_play/local_interaction/logic/local_interaction.dart:446` | 读取时 |  | 一样：v4 新加（D08.1，D-040 写明的例外）：默认开；重进同一个直播间时，24 小时内在这里发过的本地弹幕（最多 20 条）放在弹幕列表顶上、标“之前发的”、不飞过画面；关掉和 3.x 一样 |
| `localInteraction.phrases` | StringList | `[]` | —（新加） |  | 3.x 没有常用语 | 设置 → 本地用户与互动 →“常用语”一组（加、改、删 4 秒撤销、拖动排序）；长按自己的本地弹幕“存为常用语” | `features/live_play/local_interaction/logic/local_interaction.dart:358`、`features/live_play/local_interaction/logic/local_interaction.dart:385`、`features/live_play/local_interaction/logic/local_interaction.dart:395` 等 6 处 | 读取时 |  | 一样：v4 新加（D08.2）：默认空，老用户看不到变化（D-040）；最多 20 条（`StringListSetting.maxItems`），去掉首尾空白、空的和重复的（`tidy`）；每条最多 40 个字（本地弹幕的长度，应用读写时按字截，`LocalCatalog.clipDanmaku`）；跟设置一起进备份和设备同步 |
| `localInteraction.growthEnabled` | Bool | `true` | —（新加） |  | 3.x 没有本地成长：经验只来自送礼，体验币只来自按钮 | 设置 → 本地用户与互动 →“本地用户资料”一组的开关“本地成长” | `features/live_play/local_interaction/logic/local_interaction.dart:511`、`features/live_play/local_interaction/logic/local_interaction.dart:516` | 读取时 |  | 一样：v4 新加（D08.3，D-040 写明的例外）：默认开；看直播每满 10 分钟 +10 经验 +20 币（每天最多 300 经验）、每天第一次进直播间 +20 经验 +100 币、发本地弹幕 +1 经验（每天最多 50）；关掉和 3.x 一样只有送礼加经验；跟设置一起进备份和设备同步 |
| `localInteraction.growthDay` | String | `''` | —（新加） |  | 3.x 没有 | 没有单独的界面：身份卡和设置页“今天已签到 · 看直播 +N/300 · 弹幕 +N/50”读它 | `features/live_play/local_interaction/logic/local_interaction.dart:535`、`features/live_play/local_interaction/logic/local_interaction.dart:548`、`features/live_play/local_interaction/logic/local_interaction.dart:551` 等 4 处 | 读取时 |  | 一样：v4 新加（D08.3）：当天的计数（本机日期、看了多久、看直播和弹幕各得了多少经验、签到过没有），JSON，应用读写（`LocalGrowthDay`）；不是今天的读成什么都没得；默认空；跟设置一起进备份和设备同步，恢复同一天的备份不会再签到一次 |

## 备份（backup）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `backupDirectory` | String，本机 | `''` | `''`（`backup_controller.dart:37`） |  |  |  | `features/backup/backup_page.dart:86`、`features/backup/backup_page.dart:213`、`features/backup/backup_page.dart:230` | 读取时 |  | 一样 |

## 下载目录（cache）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `downloadDirectoryPath` | String，本机 | `''` | `''`（`cache_controller.dart:108、:124-130`） |  |  |  | `app/downloads.dart:13`、`app/downloads.dart:16`、`features/version/update_download.dart:42` 等 6 处 | 读取时 | `download_directory` | 一样 |
| `downloadDirectoryDecisionMade` | Bool，本机 | `false` | `false`（`cache_controller.dart:112、:132-138`） |  |  |  | `features/version/update_download.dart:43`、`features/version/update_download.dart:134`、`features/version/update_download.dart:146` 等 4 处 | 读取时 |  | 一样 |

## 日志（log）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `enableLocalLog` | Bool | `false` | —（新加） |  |  |  | `app/app_log.dart:138`、`app/app_log.dart:197`、`app/app_log.dart:210` 等 5 处 | 立即 |  | 一样：v4 新加（I01.3；3.x 的开关只管当次运行、默认关），默认值照来源任务 |
| `logLevel` | String | `'info'` | —（新加） | `debug` / `info` / `warning` / `error` |  |  | `app/app_log.dart:139`、`app/app_log.dart:196`、`app/app_log.dart:205` 等 5 处 | 立即 |  | 一样：v4 新加（I01.3），默认值照来源任务 |

## 账号（cookie）

| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| `bilibiliUid` | Int，本机 | `0` | `0`（`cookie_settings_controller.dart:11`） | 不限 | 不限 |  | `app/platforms.dart:164`、`features/account/account_services.dart:122`、`features/account/account_services.dart:131` 等 11 处 | 读取时 |  | 一样 |
| `douyuCookieSavedAt` | Int，本机 | `0` | `0`（`cookie_settings_controller.dart:22`） | 不限 | 不限 |  | `app/platforms.dart:84`、`app/platforms.dart:91`、`features/account/account_services.dart:211` 等 7 处 | 读取时 |  | 一样 |

## 3.x 有、v4 不作为设置的键

3.x 用 `hive*` 存、v4 不作为设置的键共 20 个：8 个 `<平台>Cookie` 和 `douyuLtp0`、`douyuDid` 进加密的 `SecretStore`；`favoriteRooms`、`favoriteAreas`、`historyRooms`、`shieldList`、`blockedDanmakuUsers`、`webDavConfigs`、`currentWebDavConfig` 进各自的存储；`audienceMetricMigration`、`danmakuInteractionMigration`、`siteCatalogMigration` 是 3.x 的迁移标记。另有 `enableHighRefreshRate`（换成 `refreshRateMode`）、`recorder_tasks`、`record_history`、`cached_area_pics` 等不经 `hive*` 的键，见功能清点（`docs/inventory/FEATURES.md`）第 15 节，都在 `packages/live_store/lib/src/legacy/legacy_snapshot.dart` 导入到别处或有意丢掉。
