# 归属清单（生成）

<!-- 由 tools/docs/owners.py 根据 docs/inventory/OWNERS.toml 生成，不要手改 -->

每个子分类管哪些代码、设置、平台和原生通道。由 `tools/docs/owners.py` 根据 [OWNERS.toml](OWNERS.toml) 生成，不要手改；规则怎么写见 OWNERS.toml 开头，查一个文件归谁用 `python3 tools/docs/owners.py --who <路径>`，列出某个子分类的全部文件用 `--files <子分类>`。门禁（`owners` 一步）检查每个代码文件、设置、平台、通道都有归属。

路径规则按 OWNERS.toml 里的顺序第一条匹配的生效，所以一条目录规则只管前面的规则没拿走的文件。本页只随归属表、设置、来源和通道变化，加删代码文件不用重新生成。

路径规则 205 条；设置 233 个（分节默认 23 条、单独指定 82 个）；来源 35 个；通道 15 个。

| 子分类 | 路径规则 | 设置 | 播放 | 弹幕 | 通道 |
|---|---:|---:|---:|---:|---:|
| A01 设计系统 | 3 | 17 |  |  |  |
| A02 组件 | 3 |  |  |  |  |
| A03 动效和手感 | 3 |  |  |  |  |
| A04 尺寸和适配 | 1 |  |  |  |  |
| A06 首页和全局 | 3 |  |  |  |  |
| A07 直播间界面 | 1 | 12 |  |  |  |
| A08 弹幕界面 | 5 | 9 |  |  |  |
| A09 浏览界面 | 9 | 9 |  |  |  |
| A10 录制界面 | 6 |  |  |  |  |
| A11 设置界面 | 1 |  |  |  |  |
| A12 账号和数据界面 | 6 |  |  |  |  |
| A13 网络电视和多画面界面 | 2 |  |  |  |  |
| A15 小页面 | 4 |  |  |  |  |
| A16 桌面界面 | 1 | 12 |  |  |  |
| A17 电视界面 | 2 | 1 |  |  |  |
| C01 进房和房间逻辑 | 2 | 3 |  |  |  |
| C02 小窗、画中画、后台播放 | 3 | 8 |  |  | 1 |
| C03 直播间工具 |  | 2 |  |  |  |
| D01 平台弹幕协议 | 1 | 1 |  | 30 |  |
| D02 过滤和屏蔽 | 2 | 10 |  |  |  |
| D03 飞行弹幕引擎 | 2 |  |  |  |  |
| D04 数据流和性能 | 1 |  |  |  |  |
| D05 弹幕设置生效 | 2 | 33 |  |  |  |
| D07 礼物和付费消息 | 1 |  |  |  |  |
| D08 本地互动 | 1 | 29 |  |  |  |
| E01 国内五大平台 | 5 |  | 5 |  |  |
| E02 其他国内平台 | 1 |  | 13 |  |  |
| E03 海外平台 | 16 | 1 | 16 |  |  |
| E04 链接解析和分享口令 | 2 |  |  |  |  |
| E05 平台框架和模型 | 1 |  |  |  |  |
| E06 平台层升级 | 1 |  |  |  |  |
| E07 平台巡检 | 1 |  |  |  |  |
| G01 引擎 | 3 | 8 |  |  |  |
| G02 会话和恢复 | 1 |  |  |  |  |
| G03 起播速度和弱网 | 1 |  |  |  |  |
| G04 画面 |  | 3 |  |  |  |
| G05 声音和媒体控制 | 1 | 4 |  |  | 1 |
| H01 录制核心 | 2 |  |  |  |  |
| H02 录制中心 | 6 |  |  |  |  |
| H03 录制设置和存储 | 4 | 13 |  |  |  |
| H04 自动录制和排队 | 1 | 6 |  |  |  |
| H05 录制通知 | 1 |  |  |  |  |
| I01 首页外壳和全局 | 5 | 3 |  |  |  |
| I02 热门 | 4 | 4 |  |  |  |
| I03 分区 | 2 | 1 |  |  |  |
| I04 关注 | 3 | 7 |  |  |  |
| I05 搜索 | 5 |  |  |  |  |
| I06 观看历史 | 2 | 1 |  |  |  |
| I08 小页面 | 1 | 1 |  |  |  |
| J01 设置 | 4 | 3 |  |  |  |
| J02 存储和加密 | 2 |  |  |  | 1 |
| J03 备份恢复 | 2 | 1 |  |  |  |
| J04 WebDAV | 3 |  |  |  |  |
| J05 设备同步 | 2 | 1 |  |  |  |
| J06 3.x 数据迁移 | 1 |  |  |  |  |
| K01 账号和登录方式 | 4 |  |  |  |  |
| K02 登录状态 | 1 | 3 |  |  |  |
| L01 网络电视 | 4 | 6 | 1 |  | 1 |
| L02 节目单和回看 | 3 |  |  |  |  |
| L03 点播和音乐 | 1 |  |  |  |  |
| N01 多画面 | 1 | 1 |  |  |  |
| N02 投屏 | 1 |  |  |  | 1 |
| O01 通知和前台服务 | 4 | 2 |  |  | 2 |
| O02 画中画 | 1 |  |  |  | 1 |
| O03 分享接收和快捷方式 | 3 | 1 |  |  | 1 |
| O04 权限 | 4 |  |  |  | 2 |
| O05 方向、刷新率、常亮 | 3 | 2 |  |  | 1 |
| O06 返回手势、平板和折叠屏 | 1 |  |  |  | 2 |
| Q01 请求和编码 | 2 |  |  |  |  |
| Q02 代理和镜像 | 1 | 6 |  |  |  |
| Q03 原生HTTP和WebSocket | 3 |  |  |  | 1 |
| Q04 网络状态和权限 | 1 |  |  |  |  |
| R02 刷新率 | 3 | 2 |  |  |  |
| R03 内存和图片 | 2 |  |  |  |  |
| S01 自动测试 | 2 |  |  |  |  |
| X01 Windows | 1 |  |  |  |  |
| X03 电视 |  | 1 |  |  |  |
| Y01 版本签名和发布 | 2 |  |  |  |  |
| Y02 更新通道 | 1 | 5 |  |  |  |
| Z01 工具链和依赖 | 1 |  |  |  |  |
| Z02 门禁 | 1 |  |  |  |  |
| Z03 清点和归属 | 1 |  |  |  |  |
| Z04 构建和装机 | 2 |  |  |  |  |
| Z05 多语言 | 1 | 1 |  |  |  |
| Z06 文档和登记表 | 2 |  |  |  |  |

## A01 设计系统

- 代码：`apps/pure_live/lib/app/fonts.dart`、`packages/live_ui/lib/src/theme/`、`packages/live_ui/lib/src/icons/`
- 设置：`themeMode`、`enableDynamicTheme`、`themeColorSwitch`、`pureBlackTheme`、`themeColorMigration`、`crossAxisSpacing`、`mainAxisSpacing`、`loadingStyle`、`loadingStyleColorSwitch`、`textScaleFactor`、`fontSizeBodySmall`、`fontSizeBodyMedium`、`fontSizeBodyLarge`、`fontSizeTitleMedium`、`fontSizeTitleLarge`、`fontFamilyName`、`fontFamilyFileName`

## A02 组件

- 代码：`apps/pure_live/lib/shared/panels/`、`apps/pure_live/lib/shared/under_construction.dart`、`packages/live_ui/`

## A03 动效和手感

- 代码：`packages/live_ui/lib/src/theme/motion.dart`、`packages/live_ui/lib/src/widgets/refresh_view.dart`、`packages/live_ui/lib/src/widgets/scrolling.dart`

## A04 尺寸和适配

- 代码：`packages/live_ui/lib/src/theme/grid_columns.dart`

## A06 首页和全局

- 代码：`apps/pure_live/lib/features/home/`、`apps/pure_live/lib/features/splash/`、`apps/pure_live/lib/shared/app_prompts.dart`

## A07 直播间界面

- 代码：`apps/pure_live/lib/features/live_play/`
- 设置：`enablePortraitStreamAdaptation`、`portraitAdaptiveHeight`、`portraitLayoutMode`、`portraitFullscreenPolicy`、`portraitFullscreenDisplayMode`、`portraitPipFollowSource`、`portraitDanmakuMode`、`rememberPortraitRoomOverride`、`portraitFullscreenSwipeSwitch`、`portraitRoomOverrides`、`livePlayChatCollapsed`、`roomSwitcherLayout`

## A08 弹幕界面

- 代码：`apps/pure_live/lib/features/live_play/danmaku/`、`apps/pure_live/lib/features/live_play/local_interaction/`、`apps/pure_live/lib/features/settings/danmaku_page.dart`、`apps/pure_live/lib/features/shield/`、`apps/pure_live/lib/shared/danmaku/`
- 设置：`danmakuListStyle`、`showChatGifts`、`chatGiftsAboveTier`、`giftValueInYuan`、`danmakuShowGifts`、`showChatNames`、`enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction`、`holdDanmakuOnPress`

## A09 浏览界面

- 代码：`apps/pure_live/lib/features/areas/`、`apps/pure_live/lib/features/area_rooms/`、`apps/pure_live/lib/features/hot_areas/`、`apps/pure_live/lib/features/favorite/`、`apps/pure_live/lib/features/history/`、`apps/pure_live/lib/features/popular/`、`apps/pure_live/lib/features/search/`、`apps/pure_live/lib/features/tags/`、`apps/pure_live/lib/shared/rooms/`
- 设置：`room_card_mobile_preset`、`room_card_desktop_preset`、`room_card_mobile_config`、`room_card_desktop_config`、`page_show_size_selector`、`page_show_goto_button`、`page_show_scroll_top`、`page_default_size`、`page_size_options_raw`

## A10 录制界面

- 代码：`apps/pure_live/lib/features/live_play/buttons/record_button.dart`、`apps/pure_live/lib/features/live_play/player/recording_badge.dart`、`apps/pure_live/lib/features/live_play/record/`、`apps/pure_live/lib/features/record_settings/`、`apps/pure_live/lib/features/recorder/`、`apps/pure_live/lib/shared/record/`

## A11 设置界面

- 代码：`apps/pure_live/lib/features/settings/`

## A12 账号和数据界面

- 代码：`apps/pure_live/lib/features/account/`、`apps/pure_live/lib/features/auth/`、`apps/pure_live/lib/features/backup/`、`apps/pure_live/lib/features/remote_receiver/`、`apps/pure_live/lib/features/web_dav/`、`apps/pure_live/lib/shared/qr_scan.dart`

## A13 网络电视和多画面界面

- 代码：`apps/pure_live/lib/features/iptv/`、`apps/pure_live/lib/features/multiview/`

## A15 小页面

- 代码：`apps/pure_live/lib/features/about/`、`apps/pure_live/lib/features/toolbox/`、`apps/pure_live/lib/features/version/`、`apps/pure_live/lib/shared/links/`

## A16 桌面界面

- 代码：`apps/pure_live/lib/app/desktop/`
- 设置：`enableNewWindowPlay`、`window_width`、`window_height`、`rememberPipPosition`、`windows_pip_display_id`、`windows_pip_width`、`windows_pip_height`、`windows_pip_x`、`windows_pip_y`、`dontAskExit`、`exitChoose`、`enableStartUp`

## A17 电视界面

- 代码：`apps/pure_live/lib/routes/tv_router.dart`、`apps/pure_live/lib/tv/`
- 设置：`tvFocusZoom`

## C01 进房和房间逻辑

- 代码：`apps/pure_live/lib/features/live_play/logic/`、`apps/pure_live/lib/shared/rooms/play_quality.dart`
- 设置：`enableFullScreenDefault`、`preferResolution`、`preferResolutionCellular`

## C02 小窗、画中画、后台播放

- 代码：`apps/pure_live/lib/features/live_play/logic/background_playback.dart`、`apps/pure_live/lib/features/live_play/logic/mini_window.dart`、`apps/pure_live/lib/features/live_play/mini/room_mini_window.dart`
- 设置：`enableBackgroundPlay`、`floatPlay`、`floatWindowSize`、`floatWindowLandscapeScale`、`floatWindowPortraitScale`、`windowsPipAlwaysOnTop`、`autoPipOnLeave`、`useHardStopOnExit`
- 通道：`pure_live/background_playback`

## C03 直播间工具

- 设置：`enableAsmrSleepMode`、`asmrSleepMinutes`

## D01 平台弹幕协议

- 代码：`packages/live_danmaku/`
- 设置：`youtubeShowAllChat`
- 弹幕：`bilibili`、`douyu`、`huya`、`douyin`、`kuaishou`、`twitch`、`soop`、`yy`、`acfun`、`picarto`、`twitcasting`、`missevan`、`kilakila`、`niconico`、`showroom`、`chzzk`、`kick`、`liveme`、`tiktok`、`youtube`、`bigo`、`pandalive`、`fc2live`、`steambroadcast`、`jdlive`、`kugoulive`、`baidulive`、`sixroom`、`looklive`、`17live`

## D02 过滤和屏蔽

- 代码：`apps/pure_live/lib/shared/danmaku/masked_blocks.dart`、`packages/live_danmaku/lib/src/filters/`
- 设置：`collapseRepeatedDanmaku`、`repeatedDanmakuWindowSeconds`、`filterDouyuSuspectedAutomatedMessages`、`enableDanmakuSimilarityFilter`、`danmakuSimilarityThreshold`、`danmakuSimilarityCacheDuration`、`danmakuSimilarityMaxCacheSize`、`blockEmoteOnlyDanmaku`、`blockLongDanmaku`、`blockLongDanmakuLength`

## D03 飞行弹幕引擎

- 代码：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`、`apps/pure_live/lib/shared/danmaku/emotes.dart`

## D04 数据流和性能

- 代码：`apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart`

## D05 弹幕设置生效

- 代码：`apps/pure_live/lib/shared/danmaku/danmaku_settings.dart`、`apps/pure_live/lib/shared/danmaku/danmaku_templates.dart`
- 设置：`danmakuFontFamilyFileName`、`hideDanmaku`、`noEmojiMode`、`danmakuTopArea`、`danmakuArea`、`danmakuBottomArea`、`danmakuSpeed`、`danmakuFontSize`、`danmakuFontWeight`、`danmakuFontBorder`、`danmakuOpacity`、`enableDanmakuDisplay`、`enableDanmakuStroke`、`danmakuPausedBehavior`、`danmakuFps`、`danmakuAutoFps`、`danmakuMaxVisibleCount`、`savedDanmakuTemplate`、`danmakuFontFamilyName`、`enablePipDanmaku`、`pipDanmakuAutoScale`、`pipDanmaNoEmojiMode`、`pipDanmakuUseOriginalColor`、`pipDanmakuColor`、`pipDanmakuFontSize`、`pipDanmakuFontWeight`、`pipDanmakuSpeed`、`pipDanmakuOpacity`、`pipDanmakuArea`、`pipDanmakuMaxVisibleCount`、`pipDanmakuEmitInterval`、`pipDanmakuFps`、`pipDanmakuAutoFps`

## D07 礼物和付费消息

- 代码：`apps/pure_live/lib/features/live_play/logic/gift_combiner.dart`

## D08 本地互动

- 代码：`apps/pure_live/lib/features/live_play/local_interaction/logic/`（本地互动的数据和规则（D-040））
- 设置：`localInteraction.enabled`、`localInteraction.userName`、`localInteraction.title`、`localInteraction.showAsDanmaku`、`localInteraction.showPlatformBadge`、`localInteraction.showLevelBadge`、`localInteraction.enableGiftEffects`、`localInteraction.previewPlatform`、`localInteraction.coins`、`localInteraction.experience`、`localInteraction.history`、`localInteraction.danmakuPreset`、`localInteraction.danmakuColor`、`localInteraction.danmakuFontSize`、`localInteraction.danmakuSpeed`、`localInteraction.danmakuFontWeight`、`localInteraction.danmakuShowStroke`、`localInteraction.danmakuStrokeWidth`、`localInteraction.danmakuPlacement`、`localInteraction.danmakuFontFamily`、`localInteraction.danmakuItalic`、`localInteraction.danmakuOpacity`、`localInteraction.danmakuLetterSpacing`、`localInteraction.danmakuStrokeColor`、`localInteraction.danmakuShowShadow`、`localInteraction.danmakuShadowColor`、`localInteraction.danmakuShadowBlur`、`localInteraction.danmakuShadowOffset`、`localInteraction.danmakuFixedDurationMs`

## E01 国内五大平台

- 代码：`packages/live_core/lib/src/sites/bilibili/`、`packages/live_core/lib/src/sites/douyu/`、`packages/live_core/lib/src/sites/huya/`、`packages/live_core/lib/src/sites/douyin/`、`packages/live_core/lib/src/sites/kuaishou/`
- 播放：`bilibili`、`douyu`、`huya`、`douyin`、`kuaishou`

## E02 其他国内平台

- 代码：`packages/live_core/lib/src/sites/`（其余都是国内平台）
- 播放：`cc`、`yy`、`acfun`、`missevan`、`inke`、`kilakila`、`xiaohongshu`、`weibo`、`jdlive`、`kugoulive`、`baidulive`、`sixroom`、`looklive`

## E03 海外平台

- 代码：`packages/live_core/lib/src/sites/soop/`、`packages/live_core/lib/src/sites/twitch/`、`packages/live_core/lib/src/sites/picarto/`、`packages/live_core/lib/src/sites/twitcasting/`、`packages/live_core/lib/src/sites/niconico/`、`packages/live_core/lib/src/sites/showroom/`、`packages/live_core/lib/src/sites/chzzk/`、`packages/live_core/lib/src/sites/kick/`、`packages/live_core/lib/src/sites/liveme/`、`packages/live_core/lib/src/sites/tiktok/`、`packages/live_core/lib/src/sites/youtube/`、`packages/live_core/lib/src/sites/bigo/`、`packages/live_core/lib/src/sites/pandalive/`、`packages/live_core/lib/src/sites/fc2live/`、`packages/live_core/lib/src/sites/steambroadcast/`、`packages/live_core/lib/src/sites/seventeenlive/`
- 设置：`twitchLanguages`
- 播放：`twitch`、`soop`、`picarto`、`twitcasting`、`niconico`、`showroom`、`chzzk`、`kick`、`liveme`、`tiktok`、`youtube`、`bigo`、`pandalive`、`fc2live`、`steambroadcast`、`17live`

## E04 链接解析和分享口令

- 代码：`apps/pure_live/lib/shared/rooms/share_code.dart`、`packages/live_core/lib/src/links.dart`

## E05 平台框架和模型

- 代码：`packages/live_core/`

## E06 平台层升级

- 代码：`apps/pure_live/lib/app/platforms.dart`

## E07 平台巡检

- 代码：`tools/live_cli/`

## G01 引擎

- 代码：`packages/live_media/`、`packages/live_player/lib/src/engine*.dart`、`packages/live_player/lib/src/mpv_*.dart`
- 设置：`videoPlayerKey`、`enableCodec`、`preferH264`、`playerCompatMode`、`customPlayerOutput`、`videoOutputDriver`、`audioOutputDriver`、`videoHardwareDecoder`

## G02 会话和恢复

- 代码：`packages/live_player/`

## G03 起播速度和弱网

- 代码：`packages/live_player/lib/src/timing.dart`

## G04 画面

- 设置：`videoFitIndex`、`enableRtxVsr`、`showPortraitDiagnostics`

## G05 声音和媒体控制

- 代码：`apps/pure_live/lib/features/live_play/logic/audio_focus.dart`
- 设置：`defaultMobileVolume`、`defaultDesktopVolume`、`globalVolumeMute`、`roomVolumes`
- 通道：`pure_live/device_controls`

## H01 录制核心

- 代码：`apps/pure_live/lib/platform/recording_platform.dart`、`packages/live_record/`

## H02 录制中心

- 代码：`apps/pure_live/lib/app/recording.dart`、`apps/pure_live/lib/features/recorder/logic/`、`apps/pure_live/lib/features/recorder/recorder_texts.dart`、`apps/pure_live/lib/shared/record/record_actions.dart`、`apps/pure_live/lib/shared/record/record_state.dart`、`apps/pure_live/lib/shared/record/saved_file.dart`

## H03 录制设置和存储

- 代码：`apps/pure_live/lib/features/record_settings/record_settings_texts.dart`、`packages/live_record/lib/src/naming.dart`、`packages/live_record/lib/src/settings.dart`、`packages/live_record/lib/src/storage.dart`
- 设置：`segmentTime`、`autoReconnect`、`maxCacheMB`、`enableCacheLimit`、`recordSavePath`、`default_quality`、`max_retry_count`、`retry_delay`、`recorder_prefer_best_stream`、`recorder_rw_timeout`、`recorder_thread_queue_size`、`recorder_folder_naming_strategy`、`recorder_record_danmaku`

## H04 自动录制和排队

- 代码：`packages/live_record/lib/src/scheduler.dart`
- 设置：`maxTaskCount`、`enable_polling`、`live_check_interval`、`enable_backoff`、`max_check_interval`、`auto_start_on_boot`

## H05 录制通知

- 代码：`apps/pure_live/lib/app/recording_notice.dart`

## I01 首页外壳和全局

- 代码：`apps/pure_live/lib/app/`、`apps/pure_live/lib/main.dart`、`apps/pure_live/lib/routes/`、`apps/pure_live/lib/platform/plugins.dart`、`apps/pure_live/lib/features/home/home_menu.dart`
- 设置：`savedMenuIds`、`enableLocalLog`、`logLevel`

## I02 热门

- 代码：`apps/pure_live/lib/features/popular/popular_catalog.dart`、`apps/pure_live/lib/shared/rooms/room_cards.dart`、`apps/pure_live/lib/shared/rooms/room_feed.dart`、`apps/pure_live/lib/shared/rooms/room_texts.dart`
- 设置：`preferRealOnlineCounts`、`realOnlinePlatforms`、`showUnplayableInDiscover`、`preferPlatform`

## I03 分区

- 代码：`apps/pure_live/lib/features/areas/area_catalog.dart`、`apps/pure_live/lib/features/areas/areas_common.dart`
- 设置：`hotAreasList`

## I04 关注

- 代码：`apps/pure_live/lib/features/favorite/favorite_controller.dart`、`apps/pure_live/lib/features/favorite/favorite_rules.dart`、`apps/pure_live/lib/features/favorite/follow_refresher.dart`
- 设置：`enableDenseFavorites`、`autoRefreshFavorite`、`refreshFavoriteOnResume`、`autoRefreshInterval`、`maxConcurrentRefresh`、`autoRefreshThumbnails`、`thumbnailRefreshInterval`

## I05 搜索

- 代码：`apps/pure_live/lib/features/search/search_capability.dart`、`apps/pure_live/lib/features/search/search_history.dart`、`apps/pure_live/lib/features/search/search_model.dart`、`apps/pure_live/lib/features/search/search_ranking.dart`、`apps/pure_live/lib/shared/in_app_web.dart`（网页搜索和哔哩哔哩网页登录共用）

## I06 观看历史

- 代码：`apps/pure_live/lib/features/history/history_refresh.dart`、`apps/pure_live/lib/features/history/history_sections.dart`
- 设置：`historyLimit`

## I08 小页面

- 代码：`apps/pure_live/lib/features/toolbox/toolbox_actions.dart`
- 设置：`showSplashPage`

## J01 设置

- 代码：`apps/pure_live/lib/features/settings/loading_style_names.dart`、`apps/pure_live/lib/features/settings/settings_catalog.dart`、`apps/pure_live/lib/features/settings/settings_model.dart`、`packages/live_store/lib/src/settings/`
- 设置：`autoRefreshTime`、`autoShutDownTime`、`enableAutoShutDownTime`

## J02 存储和加密

- 代码：`apps/pure_live/lib/platform/secret_cipher.dart`、`packages/live_store/`
- 通道：`pure_live/secret_cipher`

## J03 备份恢复

- 代码：`apps/pure_live/lib/shared/backup/`、`packages/live_store/lib/src/backup/`
- 设置：`backupDirectory`

## J04 WebDAV

- 代码：`apps/pure_live/lib/features/web_dav/web_dav_auth.dart`、`apps/pure_live/lib/features/web_dav/web_dav_client.dart`、`packages/live_store/lib/src/webdav.dart`

## J05 设备同步

- 代码：`apps/pure_live/lib/features/remote_receiver/mdns_peers.dart`、`apps/pure_live/lib/features/remote_receiver/remote_sync_*.dart`
- 设置：`remote_sync_device_id`

## J06 3.x 数据迁移

- 代码：`packages/live_store/lib/src/legacy/`

## K01 账号和登录方式

- 代码：`apps/pure_live/lib/features/account/account_platforms.dart`、`apps/pure_live/lib/features/account/account_services.dart`、`apps/pure_live/lib/features/account/bilibili_web_cookies.dart`、`packages/live_store/lib/src/accounts.dart`（哔哩哔哩多账号的名册（K01.2））

## K02 登录状态

- 代码：`apps/pure_live/lib/features/account/account_state.dart`
- 设置：`douyuForceRenew`、`bilibiliUid`、`douyuCookieSavedAt`

## L01 网络电视

- 代码：`apps/pure_live/lib/app/iptv_*.dart`、`apps/pure_live/lib/platform/platform_services.dart`（GBK 解码和组播锁）、`apps/pure_live/lib/features/iptv/iptv_data.dart`、`packages/live_iptv/`
- 设置：`selectedSourceName`、`selectedSourceId`、`isAutoSyncEnabled`、`autoSyncHoursInterval`、`customIptvUserAgent`、`m3uDirectory`
- 播放：`iptv`
- 通道：`pure_live/text_codec`

## L02 节目单和回看

- 代码：`apps/pure_live/lib/features/live_play/logic/iptv_guide_rows.dart`、`packages/live_iptv/lib/src/catchup.dart`、`packages/live_iptv/lib/src/guide/`

## L03 点播和音乐

- 代码：`packages/live_vod/`

## N01 多画面

- 代码：`apps/pure_live/lib/features/multiview/logic/`
- 设置：`enableMultiView`

## N02 投屏

- 代码：`packages/live_cast/`
- 通道：`pure_live/multicast_lock`

## O01 通知和前台服务

- 代码：`apps/pure_live/lib/platform/live_alert_channel.dart`、`apps/pure_live/lib/features/favorite/live_alerts.dart`、`apps/pure_live/android/**/Recorder*.kt`、`apps/pure_live/android/**/LiveAlerts.kt`
- 设置：`liveAlertEnabled`、`liveAlertTagIds`
- 通道：`pure_live/live_alerts`、`pure_live/recorder`

## O02 画中画

- 代码：`apps/pure_live/android/**/MainActivity.kt`（多个通道的宿主，待定）
- 通道：`pure_live/pip`

## O03 分享接收和快捷方式

- 代码：`apps/pure_live/lib/app/intake/`、`apps/pure_live/lib/platform/share_channel.dart`、`apps/pure_live/android/**/ShareIntakePlugin.kt`
- 设置：`detectClipboardRooms`
- 通道：`pure_live/share_intake`

## O04 权限

- 代码：`apps/pure_live/lib/platform/system_*.dart`、`apps/pure_live/lib/shared/permission_prompts.dart`、`apps/pure_live/android/**/PermissionsPlugin.kt`、`apps/pure_live/android/**/SystemAccessPlugin.kt`
- 通道：`pure_live/permissions`、`pure_live/system_access`

## O05 方向、刷新率、常亮

- 代码：`apps/pure_live/lib/platform/display_mode.dart`、`apps/pure_live/lib/platform/screen_orientation.dart`、`packages/live_player/lib/src/screen_wake.dart`
- 设置：`enableRotateScreen`、`enableScreenKeepOn`
- 通道：`pure_live/display_mode`

## O06 返回手势、平板和折叠屏

- 代码：`apps/pure_live/lib/features/live_play/logic/predictive_back.dart`
- 通道：`pure_live/app`、`pure_live/predictive_back`

## Q01 请求和编码

- 代码：`packages/live_net/`、`tools/brotli/`

## Q02 代理和镜像

- 代码：`packages/live_net/lib/src/proxy.dart`
- 设置：`enableProxy`、`proxyHost`、`proxyPort`、`enableAppProxy`、`appProxyHost`、`appProxyPort`

## Q03 原生HTTP和WebSocket

- 代码：`apps/pure_live/lib/platform/native_http.dart`、`apps/pure_live/lib/platform/twitch_webview_http.dart`、`apps/pure_live/android/**/AppChannelsPlugin.kt`（原生 HTTP、加密、GBK、组播锁，待定）
- 通道：`pure_live/native_http`

## Q04 网络状态和权限

- 代码：`apps/pure_live/lib/app/network.dart`

## R02 刷新率

- 代码：`apps/pure_live/lib/features/live_play/logic/room_refresh_rate.dart`、`packages/live_player/lib/src/frame_rate.dart`、`packages/live_ui/lib/src/widgets/refresh_rate.dart`
- 设置：`refreshRateMode`、`matchVideoFrameRate`

## R03 内存和图片

- 代码：`apps/pure_live/lib/app/image_cache.dart`、`apps/pure_live/lib/shared/images.dart`

## S01 自动测试

- 代码：`tools/coverage/`、`tools/timeshift/`

## X01 Windows

- 代码：`apps/pure_live/windows/runner/`

## X03 电视

- 设置：`uiMode`

## Y01 版本签名和发布

- 代码：`apps/pure_live/lib/features/version/app_version.dart`、`tools/release/`

## Y02 更新通道

- 代码：`apps/pure_live/lib/features/version/update_feed.dart`
- 设置：`enableAutoCheckUpdate`、`useGitHubOriginForUpdates`、`skippedUpdateVersion`、`downloadDirectoryPath`、`downloadDirectoryDecisionMade`

## Z01 工具链和依赖

- 代码：`tools/check_latest/`

## Z02 门禁

- 代码：`tools/gate/`

## Z03 清点和归属

- 代码：`tools/ui/inventory.py`

## Z04 构建和装机

- 代码：`tools/device/`、`tools/ffmpeg_kit/`

## Z05 多语言

- 代码：`apps/pure_live/lib/i18n/`
- 设置：`language`

## Z06 文档和登记表

- 代码：`tools/docs/`、`tools/ui/`（效果图和评审页工具，待定）

## 没有弹幕的来源

`cc`、`inke`、`xiaohongshu`、`weibo`、`iptv`
