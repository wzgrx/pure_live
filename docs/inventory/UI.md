# 界面清单（逐项，生成）

由 `tools/ui/inventory.py --items` 生成，不要手改。每个任务列出 v3（`v3.2.11`）和 pure_live_TV 代码里的页面、对话框、底部面板、菜单和覆盖层，名称取代码旁边的中文文案（取不到时用方法名或类名），位置是“文件:行”。同一个弹窗可能在两处出现（组件类和调用处），设计时按实际界面合并。

| 任务 | 页面 | 对话框 | 底部面板 | 菜单 | 覆盖层 | 提示条 |
|---|---:|---:|---:|---:|---:|---:|
| [A02.1](#a021) | 2 | 1 | 0 | 0 | 0 | 0 |
| [A02.2](#a022) | 0 | 6 | 0 | 0 | 0 | 1 |
| [A07.1](#a071) | 1 | 1 | 0 | 0 | 0 | 1 |
| [A07.2](#a072) | 0 | 2 | 0 | 0 | 0 | 0 |
| [A07.4](#a074) | 0 | 6 | 0 | 0 | 2 | 3 |
| [A08.1](#a081) | 5 | 0 | 0 | 0 | 0 | 9 |
| [A07.6](#a076) | 1 | 7 | 2 | 3 | 0 | 6 |
| [A07.7](#a077) | 0 | 1 | 0 | 0 | 1 | 0 |
| [A07.8](#a078) | 0 | 0 | 0 | 0 | 1 | 0 |
| [A08.2](#a082) | 0 | 1 | 2 | 0 | 0 | 1 |
| [A06.1](#a061) | 2 | 1 | 0 | 2 | 0 | 1 |
| [A06.2](#a062) | 1 | 0 | 0 | 0 | 0 | 0 |
| [A06.4](#a064) | 1 | 0 | 0 | 0 | 0 | 0 |
| [A06.3](#a063) | 0 | 5 | 0 | 0 | 0 | 7 |
| [A09.1](#a091) | 0 | 4 | 0 | 0 | 0 | 5 |
| [A09.2](#a092) | 2 | 0 | 0 | 0 | 0 | 0 |
| [A09.3](#a093) | 2 | 0 | 0 | 0 | 0 | 0 |
| [A09.4](#a094) | 2 | 0 | 0 | 0 | 0 | 0 |
| [A09.5](#a095) | 1 | 1 | 0 | 0 | 0 | 1 |
| [A09.6](#a096) | 2 | 0 | 0 | 0 | 0 | 0 |
| [A09.7](#a097) | 1 | 1 | 0 | 1 | 0 | 7 |
| [A09.8](#a098) | 1 | 0 | 0 | 0 | 0 | 0 |
| [A09.9](#a099) | 1 | 3 | 0 | 0 | 0 | 4 |
| [A11.1](#a111) | 1 | 0 | 0 | 0 | 0 | 0 |
| [A11.2](#a112) | 7 | 10 | 0 | 0 | 0 | 13 |
| [A11.3](#a113) | 6 | 9 | 0 | 0 | 0 | 2 |
| [A11.4](#a114) | 5 | 11 | 0 | 0 | 0 | 2 |
| [A11.5](#a115) | 2 | 1 | 0 | 0 | 0 | 1 |
| [A10.1](#a101) | 1 | 1 | 0 | 0 | 0 | 0 |
| [A10.2](#a102) | 1 | 5 | 0 | 0 | 0 | 4 |
| [A13.2](#a132) | 1 | 0 | 6 | 1 | 0 | 0 |
| [A13.1](#a131) | 2 | 11 | 0 | 0 | 0 | 43 |
| [A12.1](#a121) | 1 | 1 | 0 | 0 | 0 | 0 |
| [A12.2](#a122) | 10 | 1 | 0 | 0 | 0 | 1 |
| [A12.3](#a123) | 3 | 3 | 0 | 0 | 0 | 21 |
| [A12.4](#a124) | 2 | 0 | 0 | 0 | 0 | 9 |
| [A12.5](#a125) | 2 | 3 | 0 | 2 | 0 | 2 |
| [A12.6](#a126) | 1 | 4 | 0 | 0 | 0 | 7 |
| [A15.1](#a151) | 1 | 0 | 0 | 0 | 0 | 0 |
| [A15.2](#a152) | 3 | 5 | 0 | 0 | 1 | 4 |
| [A09.10](#a0910) | 1 | 4 | 0 | 0 | 0 | 2 |
| [A08.3](#a083) | 1 | 0 | 0 | 0 | 0 | 0 |
| [A16.1](#a161) | 0 | 2 | 0 | 1 | 0 | 2 |
| [A17.1](#a171) | 3 | 3 | 0 | 0 | 1 | 2 |
| [A17.2](#a172) | 2 | 5 | 0 | 0 | 0 | 3 |
| [A17.3](#a173) | 9 | 0 | 0 | 0 | 0 | 0 |
| [A17.4](#a174) | 2 | 2 | 0 | 0 | 8 | 4 |
| [A17.5](#a175) | 6 | 1 | 0 | 0 | 0 | 1 |
| [A17.6](#a176) | 10 | 0 | 0 | 0 | 3 | 18 |
| [A17.7](#a177) | 13 | 20 | 0 | 0 | 2 | 34 |
| [A17.8](#a178) | 8 | 0 | 0 | 0 | 0 | 11 |
| [A17.9](#a179) | 49 | 12 | 0 | 2 | 0 | 10 |

## A02.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A02.1-01 | 页面 | AppStatusView | `v3:common/widgets/app_status_view.dart:12` |
| A02.1-02 | 页面 | EmptyView | `v3:common/widgets/empty_view.dart:4` |
| A02.1-03 | 对话框 | standardTile | `v3:common/widgets/widget_extensions.dart:309` |

## A02.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A02.2-01 | 对话框 | showAlertDialog | `v3:plugins/utils.dart:119` |
| A02.2-02 | 对话框 | showMessageDialog | `v3:plugins/utils.dart:143` |
| A02.2-03 | 对话框 | showEditTextDialog | `v3:plugins/utils.dart:219` |
| A02.2-04 | 对话框 | showEditTextDialog | `v3:plugins/utils.dart:225` |
| A02.2-05 | 对话框 | _SharedAlertDialog | `v3:plugins/utils.dart:395` |
| A02.2-06 | 对话框 | _EditTextDialog | `v3:plugins/utils.dart:507` |

## A07.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A07.1-01 | 页面 | LivePlayPage | `v3:modules/live_play/pages/live_play_page.dart:9` |
| A07.1-02 | 对话框 | 取消关注 · `_toggleFavorite` | `v3:modules/live_play/widgets/button/favorite_floating_button.dart:31` |

## A07.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A07.2-01 | 对话框 | PortraitOrientationPickerDialog（本直播间画面方向） | `v3:modules/live_play/widgets/video_player/portrait_playback_picker_dialog.dart:17` |
| A07.2-02 | 对话框 | PortraitFullscreenDisplayModePickerDialog（竖屏全屏画面模式） | `v3:modules/live_play/widgets/video_player/portrait_playback_picker_dialog.dart:85` |

## A07.4

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A07.4-01 | 覆盖层 | VideoControllerPanel | `v3:modules/live_play/widgets/video_player/video_controller_panel.dart:99` |
| A07.4-02 | 对话框 | initState | `v3:modules/live_play/widgets/video_player/video_controller_panel.dart:405` |
| A07.4-03 | 对话框 | _showSchedule | `v3:modules/live_play/widgets/video_player/video_controller_panel.dart:443` |
| A07.4-04 | 对话框 | 竖屏全屏画面模式 · `_showPicker` | `v3:modules/live_play/widgets/video_player/video_controller_panel.dart:635` |
| A07.4-05 | 对话框 | _showPicker | `v3:modules/live_play/widgets/video_player/video_controller_panel.dart:688` |
| A07.4-06 | 对话框 | 选择清晰度 · `_showSelector` | `v3:modules/live_play/widgets/video_player/video_controller_panel.dart:1059` |
| A07.4-07 | 对话框 | _liveProgramme | `v3:modules/live_play/widgets/video_player/video_controller_panel.dart:1859` |
| A07.4-08 | 覆盖层 | SettingsPanel | `v3:modules/live_play/widgets/video_player/video_controller_panel.dart:2120` |

## A08.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A08.1-01 | 页面 | DanmakuSettingsPage | `v3:modules/live_play/pages/danmaku_settings_page.dart:9` |
| A08.1-02 | 页面 | KeywordBlockPage（请输入关键词） | `v3:modules/live_play/pages/keyword_block_page.dart:6` |
| A08.1-03 | 页面 | SuperChatPage（暂无醒目留言） | `v3:modules/live_play/pages/super_chat_page.dart:5` |
| A08.1-04 | 页面 | DanmakuListView | `v3:modules/live_play/widgets/danmaku/danmaku_list_view.dart:51` |
| A08.1-05 | 页面 | DanmakuTabView（全局弹幕显示已关闭；仍可切换到“弹幕设置”调整主播放器和小窗弹幕。） | `v3:modules/live_play/widgets/danmaku/danmaku_tab.dart:8` |

## A07.6

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A07.6-01 | 对话框 | KnownRoomLinkDialog | `v3:modules/live_play/dialogs/known_room_link_dialog.dart:10` |
| A07.6-02 | 页面 | LiveDlnaPage | `v3:modules/live_play/dialogs/live_dlna_dialog.dart:103` |
| A07.6-03 | 对话框 | 输入 1 分钟至 365 天之间的分钟数 · `show` | `v3:modules/live_play/dialogs/room_timer_dialog.dart:10` |
| A07.6-04 | 对话框 | 应用音量失败，请重试。 · `show` | `v3:modules/live_play/dialogs/room_volume_dialog.dart:17` |
| A07.6-05 | 底部面板 | 复制 · `show` | `v3:modules/live_play/widgets/danmaku/danmaku_message_actions.dart:10` |
| A07.6-06 | 对话框 | 关键词已加入弹幕屏蔽列表 · `showKeywordDialog` | `v3:modules/live_play/widgets/danmaku/danmaku_message_actions.dart:69` |
| A07.6-07 | 对话框 | _DanmakuKeywordDialog（屏蔽弹幕关键词） | `v3:modules/live_play/widgets/danmaku/danmaku_message_actions.dart:82` |
| A07.6-08 | 菜单 | 选择播放线路/节点 | `v3:modules/live_play/widgets/resolution_selector/line_selector.dart:24` |
| A07.6-09 | 菜单 | 选择清晰度 | `v3:modules/live_play/widgets/resolution_selector/resolution_selector.dart:24` |
| A07.6-10 | 菜单 | 菜单 | `v3:modules/live_play/widgets/button/live_play_menu_button.dart:23` |
| A07.6-11 | 对话框 | _switchLiveRoom | `v3:modules/live_play/widgets/button/live_play_menu_button.dart:90` |
| A07.6-12 | 底部面板 | 新窗口启动失败，请重试 · `_showLocalInteraction` | `v3:modules/live_play/widgets/button/live_play_menu_button.dart:152` |
| A07.6-13 | 对话框 | 录制中 · `_showActionDialog` | `v3:modules/live_play/widgets/button/record_action_button.dart:204` |

## A07.7

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A07.7-01 | 对话框 | 退出全屏 · `_buildHeader` | `v3:modules/live_play/widgets/placeholder/not_living_video_widget.dart:74` |
| A07.7-02 | 覆盖层 | PlaybackFailureOverlay | `v3:modules/live_play/widgets/video_player/playback_failure_overlay.dart:5` |

## A07.8

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A07.8-01 | 覆盖层 | CompactDanmakuOverlay | `v3:modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart:6` |

## A08.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A08.2-01 | 对话框 | showLocalDanmakuStyleEditor | `v3:modules/live_play/widgets/local_interaction/local_danmaku_style_editor.dart:12` |
| A08.2-02 | 底部面板 | 本地弹幕样式 · `showLocalDanmakuStyleEditor` | `v3:modules/live_play/widgets/local_interaction/local_danmaku_style_editor.dart:33` |
| A08.2-03 | 底部面板 | LocalInteractionSheet（本地互动体验） | `v3:modules/live_play/widgets/local_interaction/local_interaction_sheet.dart:5` |

## A06.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A06.1-01 | 菜单 | 更多 | `v3:common/widgets/common_appbar_actions.dart:13` |
| A06.1-02 | 菜单 | 菜单 | `v3:common/widgets/menu_button.dart:15` |
| A06.1-03 | 页面 | HomePage | `v3:modules/home/home_page.dart:20` |
| A06.1-04 | 对话框 | _checkForStartupUpdate | `v3:modules/home/home_page.dart:208` |
| A06.1-05 | 页面 | HomeMobileView（关注） | `v3:modules/home/mobile_view.dart:5` |

## A06.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A06.2-01 | 页面 | HomeTabletView（关注） | `v3:modules/home/tablet_view.dart:6` |

## A06.4

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A06.4-01 | 页面 | SplashScreen | `v3:modules/splash/splash_screen.dart:6` |

## A06.3

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A06.3-01 | 对话框 | DownloadApkDialog（准备中...） | `v3:common/widgets/download_apk_dialog.dart:127` |
| A06.3-02 | 对话框 | 选择下载目录 · `showDownloadDirectoryChoiceDialog` | `v3:common/widgets/download_directory_dialog.dart:20` |
| A06.3-03 | 对话框 | ShareCommandImportDialog（分享） | `v3:common/widgets/share_command_import_dialog.dart:6` |
| A06.3-04 | 对话框 | 分享 · `show` | `v3:common/widgets/share_command_import_dialog.dart:12` |
| A06.3-05 | 对话框 | 未选择下载目录，已取消下载 · `_showDownloadDialog` | `v3:plugins/update.dart:100` |

## A09.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.1-01 | 对话框 | 关注 · `showFollowDialog` | `v3:common/widgets/room_card.dart:131` |
| A09.1-02 | 对话框 | 分享 · `onLongPress` | `v3:common/widgets/room_card.dart:183` |
| A09.1-03 | 对话框 | 设置房间标签 / 分类 · `submitNewTag` | `v3:common/widgets/room_card.dart:393` |
| A09.1-04 | 对话框 | 取消关注 · `_toggleFavorite` | `v3:common/widgets/room_card.dart:1260` |

## A09.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.2-01 | 页面 | PopularGridView（未发现直播） | `v3:modules/popular/popular_grid_view.dart:5` |
| A09.2-02 | 页面 | PopularPage | `v3:modules/popular/popular_page.dart:7` |

## A09.3

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.3-01 | 页面 | FavoritePage（已开播） | `v3:modules/favorite/favorite_page.dart:9` |
| A09.3-02 | 页面 | RoomGridView（无已开播直播间） | `v3:modules/favorite/room_grid_view.dart:13` |

## A09.4

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.4-01 | 页面 | AreaGridView | `v3:modules/areas/areas_grid_view.dart:8` |
| A09.4-02 | 页面 | AreasPage | `v3:modules/areas/areas_page.dart:8` |

## A09.5

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.5-01 | 页面 | AreasRoomPage（未命名分区） | `v3:modules/area_rooms/area_rooms_page.dart:9` |
| A09.5-02 | 对话框 | 取消关注 · `_toggleFavorite` | `v3:modules/area_rooms/area_rooms_page.dart:115` |

## A09.6

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.6-01 | 页面 | FavoriteAreasPage（关注分区） | `v3:modules/areas/favorite_areas_page.dart:8` |
| A09.6-02 | 页面 | HotAreasPage（平台显示） | `v3:modules/hot_areas/hot_areas_page.dart:5` |

## A09.7

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.7-01 | 对话框 | 系统组件缺失 · `_showWebView2MissingDialog` | `v3:modules/search/search_controller.dart:561` |
| A09.7-02 | 页面 | SearchPage（输入直播关键字） | `v3:modules/search/search_page.dart:14` |
| A09.7-03 | 菜单 | 继续网页搜索 · `_sortLabel` | `v3:modules/search/search_page.dart:261` |

## A09.8

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.8-01 | 页面 | WebSearchPage（网页搜索） | `v3:modules/search/web_search_page.dart:8` |

## A09.9

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.9-01 | 页面 | HistoryPage（历史记录更改未保存，请重试。） | `v3:modules/history/history_page.dart:7` |
| A09.9-02 | 对话框 | 清空历史 · `_showHistoryLimitDialog` | `v3:modules/history/history_page.dart:75` |
| A09.9-03 | 对话框 | 历史记录 · `_showDestructiveConfirmation` | `v3:modules/history/history_page.dart:131` |
| A09.9-04 | 对话框 | _HistoryLimitDialog（历史记录更改未保存，请重试。） | `v3:modules/history/history_page.dart:248` |

## A11.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A11.1-01 | 页面 | SettingsPage（配置预览） | `v3:modules/settings/settings_page.dart:18` |

## A11.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A11.2-01 | 页面 | FontFamilyManagerPage（字体已成功重置为默认值） | `v3:modules/settings/pages/font_family_manager_page.dart:13` |
| A11.2-02 | 对话框 | _showFontWeightSelector | `v3:modules/settings/pages/font_family_manager_page.dart:533` |
| A11.2-03 | 对话框 | FontWeightSelectorDialog（字库载入失败，请重试） | `v3:modules/settings/pages/font_family_manager_page.dart:625` |
| A11.2-04 | 页面 | FontSettingsPage（精细化字号微调） | `v3:modules/settings/pages/font_settings_page.dart:5` |
| A11.2-05 | 对话框 | 将五项精细字号全部恢复为默认值？ · `_resetToDefaults` | `v3:modules/settings/pages/font_settings_page.dart:132` |
| A11.2-06 | 页面 | LoadingStyleSettingsPage（修改加载颜色） | `v3:modules/settings/pages/loading_style_settings_page.dart:10` |
| A11.2-07 | 页面 | NavigationSettingsPage（导航栏显示控制） | `v3:modules/settings/pages/navigation_settings_page.dart:7` |
| A11.2-08 | 页面 | PageSettingsPage（分页设置） | `v3:modules/settings/pages/page_settings.dart:6` |
| A11.2-09 | 对话框 | 单页可选数量列表 · `_showManageOptionsDialog` | `v3:modules/settings/pages/page_settings.dart:57` |
| A11.2-10 | 页面 | RoomCardSettingsPage（直播间预览） | `v3:modules/settings/pages/room_card_settings_page.dart:5` |
| A11.2-11 | 页面 | ThemeSettingsPage（主题定制） | `v3:modules/settings/pages/theme_settings_page.dart:14` |
| A11.2-12 | 对话框 | 主题模式 · `showThemeModeSelectorDialog` | `v3:modules/settings/pages/theme_settings_page.dart:196` |
| A11.2-13 | 对话框 | 切换语言 · `showLanguageSelecterDialog` | `v3:modules/settings/pages/theme_settings_page.dart:228` |
| A11.2-14 | 对话框 | showCustomSpacingDialog | `v3:modules/settings/pages/theme_settings_page.dart:268` |
| A11.2-15 | 对话框 | ThemeSpacingDialog（请输入 0 到 64 之间的间距） | `v3:modules/settings/pages/theme_settings_page.dart:350` |
| A11.2-16 | 对话框 | showAppColorPickerDialog | `v3:modules/settings/widgets/app_color_picker_dialog.dart:94` |
| A11.2-17 | 对话框 | _AppColorPickerDialog | `v3:modules/settings/widgets/app_color_picker_dialog.dart:114` |

## A11.3

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A11.3-01 | 页面 | AudienceMetricSettingsPage（观看数据与排行口径） | `v3:modules/settings/pages/audience_metric_settings_page.dart:4` |
| A11.3-02 | 页面 | MpvOptionPage | `v3:modules/settings/pages/mpv_option_page.dart:7` |
| A11.3-03 | 页面 | PipDanmakuSettingsPage（小窗弹幕） | `v3:modules/settings/pages/pip_danmaku_settings_page.dart:12` |
| A11.3-04 | 对话框 | 恢复小窗弹幕默认值 · `_confirmReset` | `v3:modules/settings/pages/pip_danmaku_settings_page.dart:40` |
| A11.3-05 | 页面 | PlayerKernelSettingsPage（播放内核设置） | `v3:modules/settings/pages/player_kernel_settings_page.dart:16` |
| A11.3-06 | 对话框 | 切换播放器 · `showVideoSetDialog` | `v3:modules/settings/pages/player_kernel_settings_page.dart:288` |
| A11.3-07 | 对话框 | 网络代理配置 · `showProxySettingsDialog` | `v3:modules/settings/pages/player_kernel_settings_page.dart:340` |
| A11.3-08 | 对话框 | _PlayerProxySettingsDialog（网络代理配置） | `v3:modules/settings/pages/player_kernel_settings_page.dart:354` |
| A11.3-09 | 页面 | PortraitLiveSettingsPage（竖屏直播适配） | `v3:modules/settings/pages/portrait_live_settings_page.dart:6` |
| A11.3-10 | 对话框 | 均衡（推荐） · `_refreshPresentation` | `v3:modules/settings/pages/portrait_live_settings_page.dart:191` |
| A11.3-11 | 页面 | VideoSettingsPage（视频设置） | `v3:modules/settings/pages/video_settings_page.dart:19` |
| A11.3-12 | 对话框 | 更新自动助眠设置失败，请重试 · `_showAsmrSleepTimerDialog` | `v3:modules/settings/pages/video_settings_page.dart:308` |
| A11.3-13 | 对话框 | _showPreferredResolutionSelectorDialog | `v3:modules/settings/pages/video_settings_page.dart:444` |
| A11.3-14 | 对话框 | 重置小窗位置和大小 · `_confirmReset` | `v3:modules/settings/pages/video_settings_page.dart:526` |
| A11.3-15 | 对话框 | _AsmrSleepTimerDialog（请输入 1 分钟至 365 天之间的分钟数） | `v3:modules/settings/pages/video_settings_page.dart:577` |

## A11.4

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A11.4-01 | 页面 | GeneralSettingsPage（通用） | `v3:modules/settings/pages/general_settings_page.dart:11` |
| A11.4-02 | 对话框 | 界面刷新率 · `_showRefreshRateModeDialog` | `v3:modules/settings/pages/general_settings_page.dart:196` |
| A11.4-03 | 对话框 | 请输入支持范围内的窗口尺寸 · `_showWindowSizeDialog` | `v3:modules/settings/pages/general_settings_page.dart:263` |
| A11.4-04 | 对话框 | 请输入支持范围内的窗口尺寸 · `_showCountdownDurationDialog` | `v3:modules/settings/pages/general_settings_page.dart:270` |
| A11.4-05 | 对话框 | _WindowSizeDialog（请输入支持范围内的窗口尺寸） | `v3:modules/settings/pages/general_settings_page.dart:274` |
| A11.4-06 | 对话框 | _CountdownDurationDialog（设置应用退出等待时间） | `v3:modules/settings/pages/general_settings_page.dart:426` |
| A11.4-07 | 页面 | LocalInteractionSettingsPage（本地用户与互动） | `v3:modules/settings/pages/local_interaction_settings_page.dart:5` |
| A11.4-08 | 页面 | NetworkProxySettingsPage | `v3:modules/settings/pages/network_proxy_settings_page.dart:16` |
| A11.4-09 | 页面 | PlatformSettingsPage（平台显示与授权） | `v3:modules/settings/pages/platform_settings_page.dart:4` |
| A11.4-10 | 对话框 | 首选直播平台 · `showPreferPlatformSelectorDialog` | `v3:modules/settings/pages/platform_settings_page.dart:81` |
| A11.4-11 | 对话框 | _PreferPlatformSelectorDialog（首选直播平台） | `v3:modules/settings/pages/platform_settings_page.dart:85` |
| A11.4-12 | 页面 | RefreshSettingsPage（刷新设置） | `v3:modules/settings/pages/refresh_settings.dart:5` |
| A11.4-13 | 对话框 | 刷新间隔时间 · `showRefreshIntervalDialog` | `v3:modules/settings/pages/refresh_settings.dart:104` |
| A11.4-14 | 对话框 | 首页并发刷新任务 · `showMaxConcurrentDialog` | `v3:modules/settings/pages/refresh_settings.dart:126` |
| A11.4-15 | 对话框 | 缩略图刷新间隔 · `showThumbnailRefreshIntervalDialog` | `v3:modules/settings/pages/refresh_settings.dart:155` |
| A11.4-16 | 对话框 | _RefreshRadioDialog | `v3:modules/settings/pages/refresh_settings.dart:172` |

## A11.5

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A11.5-01 | 页面 | CacheDataSettingsPage（错误） | `v3:modules/settings/pages/cache_data_settings_page.dart:9` |
| A11.5-02 | 对话框 | 确认清空本地缓存？ · `_confirmClearCache` | `v3:modules/settings/pages/cache_data_settings_page.dart:56` |
| A11.5-03 | 页面 | LocalConfigPreviewPage（本地配置预览） | `v3:modules/settings/pages/local_config_preveiw.dart:8` |

## A10.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A10.1-01 | 页面 | RecorderPage（录制中心） | `v3:recorder/pages/recorder/recorder_page.dart:12` |
| A10.1-02 | 对话框 | 取消监控 · `_remove` | `v3:recorder/pages/recorder/recorder_page.dart:769` |

## A10.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A10.2-01 | 页面 | RecordSettingsPage（录制设置） | `v3:recorder/pages/record_settings/record_settings_page.dart:10` |
| A10.2-02 | 对话框 | 确认清空录制文件目录？ · `_clearCache` | `v3:recorder/pages/record_settings/record_settings_page.dart:241` |
| A10.2-03 | 对话框 | 最大同时录制任务数 · `_showMaxTaskDialog` | `v3:recorder/pages/record_settings/record_settings_page.dart:371` |
| A10.2-04 | 对话框 | 设置最大缓存 (MB) · `_showCacheDialog` | `v3:recorder/pages/record_settings/record_settings_page.dart:403` |
| A10.2-05 | 对话框 | 录制设置未保存，请重试 · `_showCacheDialog` | `v3:recorder/pages/record_settings/record_settings_page.dart:425` |
| A10.2-06 | 对话框 | _RecordIntegerDialog | `v3:recorder/pages/record_settings/record_settings_page.dart:482` |

## A13.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A13.2-01 | 页面 | MultiviewPage | `v3:modules/multiview/multiview_page.dart:36` |
| A13.2-02 | 底部面板 | 换台 · `_openPickerFor` | `v3:modules/multiview/multiview_page.dart:253` |
| A13.2-03 | 底部面板 | 换台 · `_showCellActions` | `v3:modules/multiview/multiview_page.dart:278` |
| A13.2-04 | 底部面板 | 多画面 · `_showQualitySheet` | `v3:modules/multiview/multiview_page.dart:320` |
| A13.2-05 | 底部面板 | 线路 {index} · `_showLineSheet` | `v3:modules/multiview/multiview_page.dart:795` |
| A13.2-06 | 底部面板 | 音量 · `_showVolumeSheet` | `v3:modules/multiview/multiview_page.dart:820` |
| A13.2-07 | 底部面板 | _showDanmakuSettings | `v3:modules/multiview/multiview_page.dart:875` |
| A13.2-08 | 菜单 | 选择清晰度 · `_buildQualityEntry` | `v3:modules/multiview/multiview_page.dart:1073` |

## A13.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A13.1-01 | 页面 | IptvManagePage | `v3:modules/iptv/iptv_manage.dart:44` |
| A13.1-02 | 页面 | IptvPage | `v3:modules/iptv/iptv_page.dart:13` |
| A13.1-03 | 对话框 | 电子节目单源切换成功 · `_showSourceSelectionDialog` | `v3:modules/iptv/iptv_page.dart:103` |
| A13.1-04 | 对话框 | 同步配置已保存 · `_showEditUserAgentDialog` | `v3:modules/iptv/iptv_page.dart:231` |
| A13.1-05 | 对话框 | 选择自动同步时间间隔 · `_showIntervalSelectionMenu` | `v3:modules/iptv/iptv_page.dart:241` |
| A13.1-06 | 对话框 | 导入播放列表 (M3U / TXT) · `showIptvImportDialog` | `v3:modules/iptv/iptv_page.dart:310` |
| A13.1-07 | 对话框 | 导入电视节目单 (XML / GZ / JSON) · `showEpgImportDialog` | `v3:modules/iptv/iptv_page.dart:375` |
| A13.1-08 | 对话框 | 导入已完成，但列表刷新失败。请重新打开此页面查看，勿重复导入。 · `showEditTextDialog` | `v3:modules/iptv/iptv_page.dart:467` |
| A13.1-09 | 对话框 | _UserAgentDialog（修改请求头 (User-Agent)） | `v3:modules/iptv/iptv_page.dart:501` |
| A13.1-10 | 对话框 | _NetworkImportDialog（请输入下载地址） | `v3:modules/iptv/iptv_page.dart:693` |
| A13.1-11 | 对话框 | _EpgSourceDialog | `v3:modules/iptv/iptv_page.dart:808` |
| A13.1-12 | 对话框 | 该订阅名称已存在 · `importEpgFile` | `v3:core/iptv/services/epg_import_manager.dart:215` |
| A13.1-13 | 对话框 | 该订阅名称已存在 · `importIptvFile` | `v3:core/iptv/services/iptv_import_manager.dart:261` |

## A12.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A12.1-01 | 页面 | AccountPage（三方认证） | `v3:modules/account/account_page.dart:9` |
| A12.1-02 | 对话框 | 退出登录 · `_showLogoutDialog` | `v3:modules/account/account_page.dart:252` |

## A12.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A12.2-01 | 页面 | DouyuCookiePage（粘贴斗鱼完整 Cookie（含 dy_auth）） | `v3:modules/account/douyu/douyu_cookie_page.dart:16` |
| A12.2-02 | 页面 | KuaishouCookiePage（输入快手直播cookie） | `v3:modules/account/kuaishou/kuaishou_cookie_page.dart:5` |
| A12.2-03 | 页面 | HuyaCookiePage（输入虎牙直播cookie） | `v3:modules/account/huya/huya_cookie_page.dart:5` |
| A12.2-04 | 页面 | TwitchCookiePage（粘贴 Twitch Cookie） | `v3:modules/account/twitch/twitch_cookie_page.dart:5` |
| A12.2-05 | 页面 | SoopCookiePage（粘贴 SOOP Live Cookie） | `v3:modules/account/soop/soop_cookie_page.dart:5` |
| A12.2-06 | 页面 | YyCookiePage（粘贴 {name} Cookie） | `v3:modules/account/yy/yy_cookie_page.dart:5` |
| A12.2-07 | 页面 | BiliBiliQRLoginPage（哔哩哔哩账号登录） | `v3:modules/account/bilibili/qr_login_page.dart:8` |
| A12.2-08 | 页面 | BiliBiliWebLoginPage（哔哩哔哩账号登录） | `v3:modules/account/bilibili/web_login_page.dart:6` |
| A12.2-09 | 页面 | DouyinCookiePage（输入抖音直播cookie） | `v3:modules/account/douyin/douyin_cookie_page.dart:5` |
| A12.2-10 | 页面 | AccountCookieEditorPage | `v3:modules/account/widgets/account_cookie_editor.dart:34` |
| A12.2-11 | 对话框 | 舍弃 Cookie 修改？ · `_confirmDiscard` | `v3:modules/account/widgets/account_cookie_editor.dart:115` |

## A12.3

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A12.3-01 | 页面 | MinePage（云端操作未完成，请重试。） | `v3:modules/auth/mine_page.dart:30` |
| A12.3-02 | 对话框 | 云端操作未完成，请重试。 · `_confirmAndRun` | `v3:modules/auth/mine_page.dart:86` |
| A12.3-03 | 页面 | SignInPage（登录成功） | `v3:modules/auth/sign_in_page.dart:8` |
| A12.3-04 | 对话框 | 操作确认 · `_showConfirm` | `v3:modules/auth/user_manage_page.dart:155` |
| A12.3-05 | 对话框 | 操作确认 · `confirmedAction` | `v3:modules/auth/user_manage_page.dart:495` |
| A12.3-06 | 页面 | UserDetailConfigMainPage | `v3:modules/auth/components/user_detail_main_page.dart:19` |

## A12.4

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A12.4-01 | 页面 | BackupPage（加载中...） | `v3:modules/backup/backup_page.dart:14` |
| A12.4-02 | 页面 | ScanCodePage | `v3:modules/backup/scan_page.dart:50` |

## A12.5

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A12.5-01 | 页面 | WebDavHelpPage | `v3:modules/web_dav/web_dav_help.dart:13` |
| A12.5-02 | 页面 | WebDavPage | `v3:modules/web_dav/web_dav_page.dart:12` |
| A12.5-03 | 对话框 | _showConfigDialog | `v3:modules/web_dav/web_dav_page.dart:27` |
| A12.5-04 | 对话框 | 取消 · `_showConfirmation` | `v3:modules/web_dav/web_dav_page.dart:213` |
| A12.5-05 | 菜单 | 更多操作 · `_buildAppBar` | `v3:modules/web_dav/web_dav_page.dart:257` |
| A12.5-06 | 菜单 | 更多操作 · `_buildFileItem` | `v3:modules/web_dav/web_dav_page.dart:509` |
| A12.5-07 | 对话框 | _WebDavConfigDialog（编辑配置: {name}） | `v3:modules/web_dav/web_dav_page.dart:579` |

## A12.6

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A12.6-01 | 页面 | RemoteSyncPage（设备同步） | `v3:modules/remote_receiver/remote_sync_page.dart:11` |
| A12.6-02 | 对话框 | 设备同步 · `_confirmIncoming` | `v3:modules/remote_receiver/remote_sync_page.dart:39` |
| A12.6-03 | 对话框 | 配对码 · `_askPairingCode` | `v3:modules/remote_receiver/remote_sync_page.dart:63` |
| A12.6-04 | 对话框 | 接收配置 · `_receiveFromDevice` | `v3:modules/remote_receiver/remote_sync_page.dart:105` |
| A12.6-05 | 对话框 | 选择同步操作 · `_scanQr` | `v3:modules/remote_receiver/remote_sync_page.dart:162` |

## A15.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A15.1-01 | 页面 | ToolBoxPage（链接解析） | `v3:modules/toolbox/toolbox_page.dart:7` |

## A15.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A15.2-01 | 页面 | AboutPage（纯粹直播） | `v3:modules/about/about_page.dart:8` |
| A15.2-02 | 页面 | VersionHistoryPage | `v3:modules/about/version_history.dart:14` |
| A15.2-03 | 对话框 | _showMobileDetailsDialog | `v3:modules/about/version_history.dart:310` |
| A15.2-04 | 对话框 | 点击下载 · `_confirmDownload` | `v3:modules/about/version_history.dart:406` |
| A15.2-05 | 覆盖层 | _DesktopChangelogDetailPanel | `v3:modules/about/version_history.dart:477` |
| A15.2-06 | 对话框 | NoNewVersionDialog（检查更新） | `v3:modules/about/widgets/version_dialog.dart:6` |
| A15.2-07 | 对话框 | NewVersionDialog（检查更新） | `v3:modules/about/widgets/version_dialog.dart:26` |
| A15.2-08 | 页面 | VersionPage（版本更新） | `v3:modules/version/version_page.dart:16` |
| A15.2-09 | 对话框 | 下载源 {num} · `_showActionDialog` | `v3:modules/version/version_page.dart:360` |

## A09.10

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A09.10-01 | 页面 | TagManagementPage（标签管理） | `v3:modules/tags/tag_management_page.dart:9` |
| A09.10-02 | 对话框 | 标签详情 · `_showTagDetails` | `v3:modules/tags/tag_management_page.dart:280` |
| A09.10-03 | 对话框 | 删除标签 · `_showTagDialog` | `v3:modules/tags/tag_management_page.dart:378` |
| A09.10-04 | 对话框 | 删除标签 · `_confirmDelete` | `v3:modules/tags/tag_management_page.dart:389` |
| A09.10-05 | 对话框 | _TagEditorDialog（标签名称不能为空） | `v3:modules/tags/tag_management_page.dart:462` |

## A08.3

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A08.3-01 | 页面 | DanmuShieldPage（弹幕关键词屏蔽） | `v3:modules/shield/danmu_shield_page.dart:6` |

## A16.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A16.1-01 | 菜单 | 每页 · `_buildNumBlock` | `v3:common/base/desktop_components.dart:238` |
| A16.1-02 | 对话框 | 窗口操作失败，请重试 · `_showExitDialog` | `v3:plugins/utils.dart:258` |
| A16.1-03 | 对话框 | _ExitDecisionDialog（提示） | `v3:plugins/utils.dart:321` |

## A17.1

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A17.1-01 | 覆盖层 | GlobalRoomPushOverlay（该平台已下线，无法再打开，可在关注列表中取消关注） | `tv:domains/device/global_room_push.dart:13` |
| A17.1-02 | 对话框 | TvConfirmDialog | `tv:core/dialog/tv_confirm_dialog.dart:8` |
| A17.1-03 | 对话框 | TvDialog | `tv:core/dialog/tv_dialog.dart:10` |
| A17.1-04 | 对话框 | TvInputDialog（确定） | `tv:core/dialog/tv_input_dialog.dart:3` |
| A17.1-05 | 页面 | AppStatusView | `tv:core/widgets/app_status_view.dart:266` |
| A17.1-06 | 页面 | TvPage | `tv:core/widgets/tv_page.dart:4` |
| A17.1-07 | 页面 | TvTabView | `tv:core/widgets/tv_tab_view.dart:4` |

## A17.2

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A17.2-01 | 对话框 | _ExitConfirmDialog（确定要退出吗？） | `tv:features/home/exit_confirm_dialog.dart:8` |
| A17.2-02 | 对话框 | 确定要退出吗？ · `showExitConfirmDialog` | `tv:features/home/exit_confirm_dialog.dart:15` |
| A17.2-03 | 页面 | HomePage（直播） | `tv:features/home/home_page.dart:24` |
| A17.2-04 | 对话框 | 选择模式 · `_showModeDialog` | `tv:features/home/home_page.dart:75` |
| A17.2-05 | 对话框 | 选择模式 · `modeRow` | `tv:features/home/home_page.dart:116` |
| A17.2-06 | 对话框 | 加载中 · `_openDownload` | `tv:features/home/home_update_dialog.dart:67` |
| A17.2-07 | 页面 | AgreementPage（使用须知） | `tv:features/agreement/agreement_page.dart:6` |

## A17.3

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A17.3-01 | 页面 | AreaGridView | `tv:modules/live/areas/area_grid_view.dart:8` |
| A17.3-02 | 页面 | AreaRoomsPage | `tv:modules/live/areas/area_rooms_page.dart:7` |
| A17.3-03 | 页面 | AreasPage | `tv:modules/live/areas/areas_page.dart:9` |
| A17.3-04 | 页面 | FavoritePage | `tv:modules/live/favorite/favorite_page.dart:9` |
| A17.3-05 | 页面 | HistoryPage | `tv:modules/live/history/history_page.dart:11` |
| A17.3-06 | 页面 | HotPage | `tv:modules/live/hot/hot_page.dart:8` |
| A17.3-07 | 页面 | FavoriteAreasPage | `tv:modules/live/favorite_areas/favorite_areas_page.dart:8` |
| A17.3-08 | 页面 | TvSearchPage（主播） | `tv:modules/live/search/tv_search_page.dart:7` |
| A17.3-09 | 页面 | TvSearchResultPage | `tv:modules/live/search/tv_search_result_page.dart:8` |

## A17.4

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A17.4-01 | 页面 | LivePlayPage | `tv:modules/live/playback/pages/live_play_page.dart:19` |
| A17.4-02 | 覆盖层 | _SidePanel | `tv:modules/live/playback/pages/live_play_page.dart:85` |
| A17.4-03 | 对话框 | RoomSwitchDialog | `tv:modules/live/playback/dialogs/room_switch_dialog_parts.dart:18` |
| A17.4-04 | 对话框 | 切换直播间 · `_close` | `tv:modules/live/playback/dialogs/room_switch_dialog_parts.dart:264` |
| A17.4-05 | 页面 | DanmakuListView（暂无弹幕） | `tv:modules/live/playback/widgets/danmaku/danmaku_list_view.dart:9` |
| A17.4-06 | 覆盖层 | DanmakuOverlay | `tv:modules/live/playback/widgets/danmaku/danmaku_overlay.dart:14` |
| A17.4-07 | 覆盖层 | DanmakuSettingsPanel（弹幕开关） | `tv:modules/live/playback/widgets/panels/danmaku_settings_panel.dart:14` |
| A17.4-08 | 覆盖层 | PlayerIndexPanel | `tv:modules/live/playback/widgets/panels/player_index_panel.dart:26` |
| A17.4-09 | 覆盖层 | PlaylistPanel（暂无） | `tv:modules/live/playback/widgets/panels/playlist_panel.dart:23` |
| A17.4-10 | 覆盖层 | ShieldPanel | `tv:modules/live/playback/widgets/panels/shield_panel.dart:19` |
| A17.4-11 | 覆盖层 | PlaybackFailureOverlay | `tv:modules/live/playback/widgets/video_player/playback_failure_overlay.dart:15` |
| A17.4-12 | 覆盖层 | VideoControllerPanel | `tv:modules/live/playback/widgets/video_player/video_controller_panel_parts.dart:19` |

## A17.5

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A17.5-01 | 页面 | IptvHeadersSectionPage（同步配置已保存） | `tv:modules/live/iptv/pages/iptv_headers_section.dart:9` |
| A17.5-02 | 页面 | IptvImportSectionPage（参数错误） | `tv:modules/live/iptv/pages/iptv_import_section.dart:12` |
| A17.5-03 | 页面 | IptvManageSectionPage（IPTV 设置） | `tv:modules/live/iptv/pages/iptv_manage_section.dart:9` |
| A17.5-04 | 页面 | IptvResourcesSectionPage（已有订阅数据已保留，请重试。） | `tv:modules/live/iptv/pages/iptv_resources_section.dart:11` |
| A17.5-05 | 页面 | IptvSyncSectionPage（请设置需要同步的资源） | `tv:modules/live/iptv/pages/iptv_sync_section.dart:8` |
| A17.5-06 | 对话框 | confirmReplaceIptvSource | `tv:modules/live/iptv/services/iptv_confirm_dialog.dart:25` |
| A17.5-07 | 页面 | MoviePlaybackPage（解析失败，请检查链接格式） | `tv:modules/live/movie_playback/movie_playback_page.dart:4` |

## A17.6

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A17.6-01 | 页面 | VideoSectionView | `tv:modules/video/video_section_view.dart:22` |
| A17.6-02 | 页面 | VideoPlayerPage | `tv:modules/video/pages/playback/video_player_widgets.dart:21` |
| A17.6-03 | 覆盖层 | VideoCommentsPanel | `tv:modules/video/pages/playback/widgets/video_comments_panel.dart:7` |
| A17.6-04 | 覆盖层 | VideoPartsPanel（播放列表） | `tv:modules/video/pages/playback/widgets/video_parts_panel.dart:9` |
| A17.6-05 | 页面 | VideoHomePage | `tv:modules/video/pages/home/video_home_page.dart:12` |
| A17.6-06 | 页面 | VideoDetailPage（请先登录B站账号） | `tv:modules/video/pages/archive/video_detail_page.dart:15` |
| A17.6-07 | 页面 | VideoPgcPage | `tv:modules/video/pages/discover/video_pgc_page.dart:7` |
| A17.6-08 | 页面 | VideoRegionPage | `tv:modules/video/pages/discover/video_region_page.dart:13` |
| A17.6-09 | 页面 | VideoSeasonPage（第） | `tv:modules/video/pages/discover/video_season_page.dart:16` |
| A17.6-10 | 覆盖层 | VodDanmakuOverlay | `tv:modules/video/widgets/vod_danmaku_overlay.dart:19` |
| A17.6-11 | 页面 | UgcCommentsPage | `tv:modules/vod/pages/ugc_comments_page.dart:10` |
| A17.6-12 | 页面 | UgcDynamicsPage（数据加载失败） | `tv:modules/vod/pages/ugc_dynamics_page.dart:13` |
| A17.6-13 | 页面 | UgcUserSpacePage | `tv:modules/vod/pages/ugc_user_space_widgets.dart:6` |

## A17.7

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A17.7-01 | 页面 | MusicSectionView | `tv:modules/music/music_section_view.dart:29` |
| A17.7-02 | 页面 | MusicArchivePage（请先登录B站账号） | `tv:modules/music/pages/playback/music_archive_page.dart:15` |
| A17.7-03 | 页面 | MusicNowPlayingQueuePage（还没有播放的音乐） | `tv:modules/music/pages/playback/music_now_playing_queue_widgets.dart:13` |
| A17.7-04 | 页面 | MusicPlayerPage | `tv:modules/music/pages/playback/music_player_page.dart:28` |
| A17.7-05 | 对话框 | MusicLyricPickerDialog（选择歌词） | `tv:modules/music/pages/playback/widgets/player_lyric_picker.dart:9` |
| A17.7-06 | 对话框 | 选择歌词 | `tv:modules/music/pages/playback/widgets/player_lyric_picker.dart:19` |
| A17.7-07 | 页面 | MusicNowPlayingView | `tv:modules/music/pages/playback/widgets/player_now_playing_view.dart:17` |
| A17.7-08 | 覆盖层 | MusicQueuePanel（清空队列） | `tv:modules/music/pages/playback/widgets/player_queue_panel.dart:132` |
| A17.7-09 | 对话框 | 清空队列 · `_confirmClear` | `tv:modules/music/pages/playback/widgets/player_queue_panel.dart:201` |
| A17.7-10 | 覆盖层 | MusicPlayerSettingsPanel（设置） | `tv:modules/music/pages/playback/widgets/player_settings_panel.dart:7` |
| A17.7-11 | 页面 | MusicFavDetailPage（已将 {count} 首加入喜欢） | `tv:modules/music/pages/playlist/music_fav_detail_page.dart:12` |
| A17.7-12 | 页面 | MusicFavFoldersPage（喜欢的歌曲） | `tv:modules/music/pages/playlist/music_fav_folders_page.dart:18` |
| A17.7-13 | 对话框 | 编辑歌单 · `_showPlaylistMenu` | `tv:modules/music/pages/playlist/music_fav_folders_page.dart:219` |
| A17.7-14 | 对话框 | 清空歌曲 · `_confirmClearPlaylist` | `tv:modules/music/pages/playlist/music_fav_folders_page.dart:275` |
| A17.7-15 | 对话框 | 同步更新 · `_showFolderMenu` | `tv:modules/music/pages/playlist/music_fav_folders_page.dart:298` |
| A17.7-16 | 对话框 | 删除歌单 · `_confirmDeletePlaylist` | `tv:modules/music/pages/playlist/music_fav_folders_page.dart:342` |
| A17.7-17 | 对话框 | 确定 · `showPlaylistNameDialog` | `tv:modules/music/pages/playlist/music_playlist_dialogs.dart:13` |
| A17.7-18 | 对话框 | 加入歌单 · `showAddToPlaylistDialog` | `tv:modules/music/pages/playlist/music_playlist_dialogs.dart:41` |
| A17.7-19 | 对话框 | 保存到歌单 · `showPlaylistPicker` | `tv:modules/music/pages/playlist/music_playlist_dialogs.dart:162` |
| A17.7-20 | 对话框 | 选择音乐平台 · `showImportPlaylistDialog` | `tv:modules/music/pages/playlist/music_playlist_import_dialog.dart:16` |
| A17.7-21 | 对话框 | 导入歌单 · `showImportPlaylistDialog` | `tv:modules/music/pages/playlist/music_playlist_import_dialog.dart:43` |
| A17.7-22 | 对话框 | 导入歌单 · `showImportPlaylistDialog` | `tv:modules/music/pages/playlist/music_playlist_import_dialog.dart:100` |
| A17.7-23 | 页面 | MusicUserPlaylistDetailPage（已将 {count} 首加入喜欢） | `tv:modules/music/pages/playlist/music_user_playlist_detail_page.dart:17` |
| A17.7-24 | 对话框 | 已取消喜欢 · `_showSongMenu` | `tv:modules/music/pages/playlist/music_user_playlist_detail_page.dart:311` |
| A17.7-25 | 页面 | MusicCloudHistoryPage（删除这条记录） | `tv:modules/music/pages/discover/music_cloud_history_page.dart:10` |
| A17.7-26 | 对话框 | 删除这条记录 · `_showRowMenu` | `tv:modules/music/pages/discover/music_cloud_history_page.dart:70` |
| A17.7-27 | 页面 | MusicDailyPage（收藏夹为空或没有更多可推荐） | `tv:modules/music/pages/discover/music_daily_page.dart:15` |
| A17.7-28 | 对话框 | 选择收藏夹 · `_pickFolder` | `tv:modules/music/pages/discover/music_daily_page.dart:72` |
| A17.7-29 | 对话框 | 重新推荐 · `_confirmReroll` | `tv:modules/music/pages/discover/music_daily_page.dart:203` |
| A17.7-30 | 页面 | MusicRankingPage | `tv:modules/music/pages/discover/music_ranking_page.dart:11` |
| A17.7-31 | 对话框 | 播放全辑 · `_confirmUnfollowArchive` | `tv:modules/music/pages/mine/music_follow_section.dart:249` |
| A17.7-32 | 对话框 | 取消关注 · `_confirmUnfollowUp` | `tv:modules/music/pages/mine/music_follow_section.dart:287` |
| A17.7-33 | 页面 | MusicRecentsPage | `tv:modules/music/pages/mine/music_recents_page.dart:13` |
| A17.7-34 | 页面 | MusicSearchPage（搜索B站歌曲、MV、演唱会） | `tv:modules/music/pages/search/music_search_page.dart:14` |
| A17.7-35 | 对话框 | 下一首播放 · `Function` | `tv:modules/music/widgets/music_song_menu.dart:37` |

## A17.8

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A17.8-01 | 页面 | WallpaperApiGroupPage | `tv:features/wallpaper/wallpaper_api_group_page.dart:12` |
| A17.8-02 | 页面 | WallpaperApiPage（随机壁纸 API） | `tv:features/wallpaper/wallpaper_api_page.dart:14` |
| A17.8-03 | 页面 | WallpaperGalleryPage | `tv:features/wallpaper/wallpaper_gallery_page.dart:15` |
| A17.8-04 | 页面 | WallpaperImmersivePage | `tv:features/wallpaper/wallpaper_immersive_page.dart:19` |
| A17.8-05 | 页面 | WallpaperItemsPage | `tv:features/wallpaper/wallpaper_items_page.dart:23` |
| A17.8-06 | 页面 | WallpaperLibraryPage（壁纸库） | `tv:features/wallpaper/wallpaper_library_page.dart:14` |
| A17.8-07 | 页面 | WallpaperPage（背景设置） | `tv:features/wallpaper/wallpaper_page.dart:21` |
| A17.8-08 | 页面 | WallpaperPreviewPage | `tv:features/wallpaper/wallpaper_preview_page_parts.dart:23` |

## A17.9

| 编号 | 类型 | 名称 | 位置 |
|---|---|---|---|
| A17.9-01 | 页面 | SettingsCatalogView（发现新版本） | `tv:features/settings/tv_settings_page.dart:189` |
| A17.9-02 | 页面 | TvSettingsRoutePage（设置） | `tv:features/settings/tv_settings_page.dart:328` |
| A17.9-03 | 页面 | AboutSettingsSectionPage（发现新版本） | `tv:features/settings/pages/about_settings_section.dart:7` |
| A17.9-04 | 页面 | AccountBilibiliPage（已登录账号） | `tv:features/settings/pages/account_bilibili_page.dart:17` |
| A17.9-05 | 页面 | BilibiliQrLoginView | `tv:features/settings/pages/account_bilibili_page.dart:226` |
| A17.9-06 | 对话框 | 二维码登录 · `showBilibiliQrLoginDialog` | `tv:features/settings/pages/account_bilibili_page.dart:382` |
| A17.9-07 | 页面 | AccountCookiePage（局域网遥控服务未启动，请检查电视与手机是否在同一网络） | `tv:features/settings/pages/account_cookie_page.dart:17` |
| A17.9-08 | 页面 | AccountSettingsSectionPage | `tv:features/settings/pages/account_settings_section.dart:14` |
| A17.9-09 | 页面 | AppDownloadPage（版本更新） | `tv:features/settings/pages/app_download_page.dart:21` |
| A17.9-10 | 页面 | AppUpdatePage（在线更新） | `tv:features/settings/pages/app_update_page.dart:21` |
| A17.9-11 | 页面 | AudienceMetricSectionPage（卡片显示与排行方式） | `tv:features/settings/pages/audience_metric_section.dart:7` |
| A17.9-12 | 页面 | AudioOutputSettingsSectionPage（音频输出驱动(--ao)） | `tv:features/settings/pages/audio_output_settings_section.dart:12` |
| A17.9-13 | 页面 | BackupBrowserSectionPage（用手机相机扫码打开网页，在浏览器里下载或导入备份文件（与本地备份是同一种文件）） | `tv:features/settings/pages/backup_browser_page.dart:12` |
| A17.9-14 | 页面 | BackupManageSectionPage（设置已应用） | `tv:features/settings/pages/backup_manage_section.dart:11` |
| A17.9-15 | 菜单 | 恢复备份 · `_openBackupMenu` | `tv:features/settings/pages/backup_manage_section.dart:79` |
| A17.9-16 | 页面 | BackupSettingsSectionPage（加载中） | `tv:features/settings/pages/backup_settings_section.dart:12` |
| A17.9-17 | 页面 | CacheSettingsSectionPage（缩略图已刷新） | `tv:features/settings/pages/cache_settings_section.dart:6` |
| A17.9-18 | 页面 | ColorPickerSectionPage（选择颜色） | `tv:features/settings/pages/color_picker_section.dart:65` |
| A17.9-19 | 页面 | DanmakuSettingsSectionPage（弹幕观看模板） | `tv:features/settings/pages/danmaku_settings_section.dart:7` |
| A17.9-20 | 页面 | DanmakuShieldSectionPage（弹幕关键词屏蔽） | `tv:features/settings/pages/danmaku_shield_section.dart:21` |
| A17.9-21 | 对话框 | BlockEntryAddDialog（屏蔽弹幕关键词） | `tv:features/settings/pages/danmaku_shield_section.dart:140` |
| A17.9-22 | 对话框 | 屏蔽弹幕关键词 · `_submit` | `tv:features/settings/pages/danmaku_shield_section.dart:202` |
| A17.9-23 | 对话框 | BlockEntryDetailDialog | `tv:features/settings/pages/danmaku_shield_section.dart:227` |
| A17.9-24 | 对话框 | _submit | `tv:features/settings/pages/danmaku_shield_section.dart:236` |
| A17.9-25 | 页面 | DecoderSettingsSectionPage（不使用硬解（纯软解）） | `tv:features/settings/pages/decoder_settings_section.dart:17` |
| A17.9-26 | 页面 | DeviceSyncSectionPage（设备同步） | `tv:features/settings/pages/device_sync_section.dart:14` |
| A17.9-27 | 页面 | FontFamilyManagerSectionPage | `tv:features/settings/pages/font_family_manager_section.dart:21` |
| A17.9-28 | 菜单 | 应用 · `_onSelectFamily` | `tv:features/settings/pages/font_family_manager_section.dart:123` |
| A17.9-29 | 页面 | GeneralSettingsSectionPage（通用） | `tv:features/settings/pages/general_settings_section.dart:13` |
| A17.9-30 | 页面 | GridSpacingSectionPage（网格间距设置） | `tv:features/settings/pages/grid_spacing_section.dart:10` |
| A17.9-31 | 页面 | IconPickerSectionPage（选择图标） | `tv:features/settings/pages/icon_picker_section.dart:20` |
| A17.9-32 | 页面 | LoadingStyleSectionPage（修改加载动画） | `tv:features/settings/pages/loading_style_widgets.dart:11` |
| A17.9-33 | 页面 | LocalConfigPreviewSectionPage（备份版本） | `tv:features/settings/pages/local_config_preview_section.dart:10` |
| A17.9-34 | 页面 | LogViewerPage（在浏览器中查看日志） | `tv:features/settings/pages/log_viewer_page.dart:17` |
| A17.9-35 | 页面 | ModeSettingsSectionPage（模式设置） | `tv:features/settings/pages/mode_settings_section.dart:5` |
| A17.9-36 | 页面 | MusicSettingsSectionPage（播放默认） | `tv:features/settings/pages/music_settings_section.dart:11` |
| A17.9-37 | 页面 | NavIconsSectionPage（图标） | `tv:features/settings/pages/nav_icons_section.dart:14` |
| A17.9-38 | 页面 | NavOrderSectionPage（排序） | `tv:features/settings/pages/nav_order_section.dart:16` |
| A17.9-39 | 页面 | NavVisibilitySectionPage（导航栏显示方式） | `tv:features/settings/pages/nav_visibility_section.dart:13` |
| A17.9-40 | 页面 | NavigationSectionPage（导航栏显示控制） | `tv:features/settings/pages/navigation_section.dart:12` |
| A17.9-41 | 页面 | PageSettingsSectionPage（通用分页控制条） | `tv:features/settings/pages/page_settings_section.dart:15` |
| A17.9-42 | 页面 | PlatformDisplayOrderSectionPage（平台排序） | `tv:features/settings/pages/platform_display_order_section.dart:15` |
| A17.9-43 | 页面 | PlatformDisplaySectionPage（平台显示） | `tv:features/settings/pages/platform_display_section.dart:13` |
| A17.9-44 | 页面 | PlatformDisplayVisibilitySectionPage（显示平台） | `tv:features/settings/pages/platform_display_visibility_section.dart:10` |
| A17.9-45 | 页面 | PlatformSettingsSectionPage（平台显示与授权） | `tv:features/settings/pages/platform_settings_section.dart:6` |
| A17.9-46 | 页面 | PlayerKernelSettingsSectionPage（核心内核设置） | `tv:features/settings/pages/player_kernel_settings_section.dart:23` |
| A17.9-47 | 页面 | ProxySettingsSectionPage | `tv:features/settings/pages/proxy_settings_section.dart:4` |
| A17.9-48 | 页面 | RefreshSettingsSectionPage（主页缓存） | `tv:features/settings/pages/refresh_settings_section.dart:10` |
| A17.9-49 | 页面 | RendererSettingsSectionPage（视频输出驱动(--vo)） | `tv:features/settings/pages/renderer_settings_section.dart:15` |
| A17.9-50 | 页面 | TagManagementSectionPage（设置已应用） | `tv:features/settings/pages/tag_management_dialogs.dart:8` |
| A17.9-51 | 对话框 | _AddTagDialog（标签名称不能为空） | `tv:features/settings/pages/tag_management_dialogs.dart:101` |
| A17.9-52 | 对话框 | 添加 · `_submit` | `tv:features/settings/pages/tag_management_dialogs.dart:167` |
| A17.9-53 | 对话框 | _TagDetailDialog（标签详情） | `tv:features/settings/pages/tag_management_dialogs.dart:195` |
| A17.9-54 | 对话框 | 标签详情 · `_submit` | `tv:features/settings/pages/tag_management_dialogs.dart:204` |
| A17.9-55 | 页面 | ThemePickerSectionPage（主题外观） | `tv:features/settings/pages/theme_picker_section.dart:9` |
| A17.9-56 | 页面 | ThemeSettingsSectionPage（系统默认字体） | `tv:features/settings/pages/theme_settings_section.dart:9` |
| A17.9-57 | 页面 | UpdateHistoryPage（版本历史） | `tv:features/settings/pages/update_history_page.dart:13` |
| A17.9-58 | 对话框 | 发布于 {date} · `showReleaseNotesDialog` | `tv:features/settings/pages/update_history_page.dart:216` |
| A17.9-59 | 页面 | VideoSettingsSectionPage | `tv:features/settings/pages/video_settings_section.dart:17` |
| A17.9-60 | 页面 | UserLockSettingsView（输入当前密码） | `tv:features/settings/pages/widgets/account_lock.dart:234` |
| A17.9-61 | 页面 | StartupUnlockView | `tv:features/settings/pages/widgets/account_lock.dart:342` |
| A17.9-62 | 对话框 | DownloadApkDialog | `tv:features/settings/widgets/download_apk_dialog.dart:33` |
| A17.9-63 | 对话框 | _install | `tv:features/settings/widgets/download_apk_dialog.dart:163` |

