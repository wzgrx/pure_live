# 功能清点（v3 → v4）

- 更新：2026-10-02（第 1 版）
- 计划：[FEATURE_PLAN.md](FEATURE_PLAN.md)；任务：[TASKS.md](TASKS.md)；做法：[PROCESS.md](PROCESS.md)
- 范围：v3（标签 `v3.2.11`，本机只读副本 `~/ref/v3ref`）里用户能用到的每一个功能点。界面怎么画不在这里（见 `docs/ui/`），这里只管“能做什么、做了没有、对不对”。
- **本阶段只判断 Android（手机和平板）**（用户 2026-10-02 决定）。Windows、Linux、电视、苹果平台的功能以后再清点；Windows 专属的功能点列在第 13 节，只写“以后”。

## 怎么读

- **编号**：`F-<模块>-<序号>`，例如 `F-ROOM-13`。任务（[TASKS.md](TASKS.md)）按编号引用。
- **v3 位置**：`lib/` 下的路径省略 `lib/`；Android 原生写 `android/...`；`文件:行` 指主要实现的起点。
- **依据**：v4 代码路径省略 `apps/pure_live/lib/`；包写 `packages/<包>`；`M13.x`、`U.x` 是 `docs/modules/`、`docs/ui/records/` 里的记录。
- **Android**：是 / 否 / 部分（只在某种条件下适用）。
- **v4 现状**：

| 现状 | 意思 |
|---|---|
| 完成 | 代码和测试都在，记录写明行为同 v3（或是确认过的改动）。最后仍在 K90 上统一验证（TASKS 第 5 节） |
| 部分 | 做了一部分，缺的写在备注 |
| 缺失 | master 上没有（有半成品的写明分支） |
| 有问题 | 有入口或设置，但不生效，或行为和 v3 不同又不是确认过的改动 |
| 没验证 | 代码在，但关键部分靠原生、系统服务、联网或真机，单元测试覆盖不到，记录里标了“没验证”；K90 真机验证前不算完成 |
| 不做 | 用户或计划已决定不恢复 |

## 统计

| 模块 | 功能点 | 完成 | 部分 | 缺失 | 有问题 | 没验证 | 不做 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 应用和全局 APP | 24 | 17 | 0 | 1 | 0 | 6 | 0 |
| 2 Android 系统集成 AND | 9 | 0 | 1 | 3 | 0 | 5 | 0 |
| 3 网络和代理 NET | 4 | 2 | 0 | 1 | 0 | 1 | 0 |
| 4 推荐和分区 BRW | 9 | 9 | 0 | 0 | 0 | 0 | 0 |
| 5 房间卡片 CARD | 5 | 5 | 0 | 0 | 0 | 0 | 0 |
| 6 关注 FAV | 8 | 8 | 0 | 0 | 0 | 0 | 0 |
| 7 搜索和历史 SRC、HIS | 7 | 6 | 0 | 0 | 0 | 1 | 0 |
| 8 直播间 ROOM、RT、PORT、MINI | 46 | 35 | 1 | 6 | 1 | 2 | 1 |
| 9 弹幕和本地互动 DM、LOC | 20 | 15 | 0 | 3 | 2 | 0 | 0 |
| 10 多画面 MV | 6 | 5 | 0 | 0 | 0 | 1 | 0 |
| 11 录制 REC | 13 | 7 | 0 | 1 | 0 | 5 | 0 |
| 12 网络电视、账号、备份、工具、标签 | 25 | 18 | 1 | 0 | 0 | 5 | 1 |
| **合计** | **176** | **127** | **3** | **15** | **3** | **26** | **2** |

另：第 13 节 Windows 专属 14 项（以后）；第 14 节 35 个平台（33 个 v3 平台、Kick、网络电视）的能力表；第 15 节设置项核对。

v3 没有的、不在清点里的：开播提醒（v3 没有通知开播的功能）、WebDAV 定时备份（v3 没有）、录制历史页（v3 只有路由 `kRecordHistory`，没有页面）。已批准的升级（[UPGRADES.md](../UPGRADES.md)）不是 v3 功能，余项归 TASKS 的 F.8a。

---

## 1 应用和全局（APP）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-APP-01 | 首次启动导入 3.x 数据（设置、关注、历史、分组、屏蔽、Cookie、WebDAV、录制任务） | `common/global/initialized.dart:69`、`common/services/utils/settings_upgrade_migration.dart:29` | 是 | 没验证 | `packages/live_store` 的 `LegacyMigration`（M9）、`app/bootstrap.dart`（M12）；测试用造的 Hive 文件 | 测试包 `.v4dev` 读不到 3.x 的私有目录，只有覆盖安装才会真走这条路（见 FEATURE_PLAN 第 7 节） |
| F-APP-02 | 导入 3.x 的网络电视库 `pure_live_tv.db` | `core/iptv/local/database.dart:42` | 是 | 没验证 | `app/iptv_legacy.dart`（M12.1） | 同上 |
| F-APP-03 | 启动页（可关） | `modules/splash/splash_screen.dart:6`、`main.dart:197` | 是 | 完成 | `features/splash/`（M13.13、U.3c） | |
| F-APP-04 | 启动后检查更新、新版本对话框（可关） | `modules/home/home_page.dart:205`、`plugins/update.dart:18` | 是 | 完成 | `features/version/update_prompt.dart`（M13.13、M12.2、U.3d） | |
| F-APP-05 | 应用内下载更新包并安装（断点续传、“安装未知应用”权限） | `common/widgets/download_apk_dialog.dart:32`、`:148` | 是 | 没验证 | `app/downloads.dart`、`features/version/update_download.dart`（M12.4） | 权限页跳转、系统安装器没在真机走过 |
| F-APP-06 | 多语言（简体中文、英文、跟随系统） | `common/services/settings/theme_settings_controller.dart:20` | 是 | 完成 | `i18n/`（M12） | |
| F-APP-07 | 主题模式、主题色、动态取色 | `theme_settings_controller.dart:17`、`main.dart:145` | 是 | 完成 | M13.7、U.6b | |
| F-APP-08 | 文字缩放、五种字号 | `main.dart:140`、`common/services/settings/font_settings_controller.dart:40` | 是 | 完成 | M13.7 | |
| F-APP-09 | 下载字体、设置应用字体 | `plugins/font_download_manager.dart:12`、`modules/settings/pages/font_family_manager_page.dart:13` | 是 | 没验证 | `app/fonts.dart`（M12.4） | 下载和注册后的界面没在真机看 |
| F-APP-10 | 加载动画样式（85 种） | `modules/settings/pages/loading_style_settings_page.dart:10` | 是 | 完成 | M13.7 | |
| F-APP-11 | 首页菜单（关注、热门、分区、录制），可排序、隐藏 | `modules/home/home_page.dart:113`、`modules/settings/pages/navigation_settings_page.dart:7` | 是 | 完成 | `features/home/`（M12、U.3a） | |
| F-APP-12 | 再点“关注”刷新关注 | `modules/home/home_page.dart:108` | 是 | 完成 | M12、M13.2 | |
| F-APP-13 | 后台 15 秒以上回来刷新当前页 | `modules/home/home_page.dart:151` | 是 | 完成 | M12（`HomeSignals`） | |
| F-APP-14 | 返回键退到后台，不退出应用 | `modules/home/home_page.dart:220` | 是 | 完成 | 原生通道 `pure_live/app`（M12） | |
| F-APP-15 | 界面刷新率三档（省电、均衡、性能），显示当前和最高刷新率 | `common/widgets/adaptive_refresh_rate_scope.dart:88`、`common/services/display_mode_service.dart:5` | 是 | 没验证 | M12、`platform/display_mode.dart`（M12.4） | 播放时按视频帧率切换是 U.2i 的增强，未开始 |
| F-APP-16 | 图片解码缓存上限 | `common/global/initialized.dart:31` | 是 | 完成 | M12 | |
| F-APP-17 | 系统内存紧张时清图片缓存 | `common/global/platform/desktop_manager.dart:774` | 是 | 缺失 | v4 没有 `didHaveMemoryPressure` | |
| F-APP-18 | 图片请求头（哔哩哔哩 Referer、浏览器 UA） | `common/utils/network_image_url.dart:29` | 是 | 完成 | `shared/images.dart`（M12.2） | |
| F-APP-19 | 清除图片缓存、刷新直播缩略图、显示缓存大小 | `modules/settings/pages/cache_data_settings_page.dart:9` | 是 | 完成 | `features/settings/data_tools.dart`（M12.3、M12.4） | |
| F-APP-20 | 定时刷新封面 | `common/services/settings/cache_controller.dart:234` | 是 | 完成 | `data_tools.dart` 的 `CoverRefreshTimer`（M12.3） | |
| F-APP-21 | 定时关闭应用 | `common/services/settings/exit_settings_controller.dart:9`、`modules/settings/pages/general_settings_page.dart:91` | 是 | 完成 | `features/settings/settings_editors.dart` 的 `AutoExitTimer`，`app/startup.dart:49` 启动时接上 | |
| F-APP-22 | 日志（最近 2000 条、写文件、查看、导出） | `common/services/settings/log_controller.dart:10` | 是 | 完成 | `app/app_log.dart`、`features/settings/log_page.dart`（M12.4） | v3 用本机网页看日志，v4 改为应用内页面 |
| F-APP-23 | 边到边显示、透明状态栏和导航栏、四个方向可转 | `common/global/platform/mobile_manager.dart:11` | 是 | 没验证 | 依赖 Flutter 默认的边到边；没找到对应代码 | 真机看状态栏、导航栏颜色 |
| F-APP-24 | 配置预览（各模块原始配置、复制） | `modules/settings/pages/local_config_preveiw.dart:8` | 是 | 完成 | `data_tools.dart`（M13.7） | |

## 2 Android 系统集成（AND）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-AND-01 | 剪贴板识别分享口令（启动时、回前台 1 秒后），弹“进入直播间” | `common/global/platform/desktop_manager.dart:621`、`plugins/share_command_handler.dart:28`、`common/widgets/share_command_import_dialog.dart:6` | 是 | 缺失 | master 只有生成口令（`shared/rooms/share_code.dart`）和 U.3d 的对话框（`shared/rooms/room_prompt.dart`） | 半成品：分支 `worktree-agent-a27f9a86b17d9663f` 提交 `341513e13` |
| F-AND-02 | 接收系统分享和“打开方式”：直播链接进房，m3u/txt 导入网络电视，xml/gz/json 导入节目单 | `main.dart:105`、`common/utils/shared_media_intake.dart:9`、`common/utils/shared_live_link_opener.dart:12`、`android/app/src/main/AndroidManifest.xml:38,78` | 是 | 缺失 | 清单有过滤器，没有接收代码（现在点了只打开应用） | 半成品：同上分支 `341513e13`、`e8ff1bb40` |
| F-AND-03 | 打开后台播放、助眠时申请通知权限和“忽略电池优化”，被拒时说明并给系统设置入口 | `player/core/live_audio_service.dart:207` | 是 | 缺失 | master 没有申请代码 | 半成品：同上分支 `4157aafbc`（分支另在第一次录制时问一次通知权限，v3 没有）；Android 13 起没有通知权限时前台服务的通知不显示 |
| F-AND-04 | Android 17 本地网络权限（代理指向局域网、设备同步） | `common/services/local_network_access.dart:10` | 部分（Android 17） | 没验证 | `platform/system_access.dart`（M12.4） | K90 不是 Android 17，验证不了 |
| F-AND-05 | Cookie、密码加密存储 | `common/services/settings/cookie_settings_controller.dart:9`（v3 明文） | 是 | 没验证 | `platform/secret_cipher.dart`（Android Keystore，M12） | v3 明文，v4 加密；Keystore 没在真机跑 |
| F-AND-06 | 系统画中画（系统关了画中画时说明并去设置） | `player/core/player_manager.dart:2808`、`modules/live_play/widgets/video_player/video_controller_panel.dart:423` | 是 | 没验证 | `features/live_play/mini/room_mini_window.dart`、`MainActivity` 的 `pure_live/pip`（M13.14、U.2j） | K90 第二轮：回来后控制条卡住，M13.16 已防御性修改，未复验 |
| F-AND-07 | 系统媒体通知（标题、主播、封面、播放暂停、停止） | `player/core/live_audio_handler.dart:12` | 是 | 没验证 | `features/live_play/logic/background_playback.dart`（M13.14） | v4 只在后台播放或助眠打开时显示（M13.14 确认的改动） |
| F-AND-08 | Android 14 起的预测返回手势 | `modules/live_play/services/android_predictive_back_service.dart:7`、`android/.../MainActivity.kt:26` | 是 | 部分 | 原生通道 `pure_live/predictive_back` 在（`android/.../MainActivity.kt:74`），Dart 侧没有调用 | |
| F-AND-09 | 原生 HTTP 通道（系统 TLS，Twitch、Kick 用） | `android/.../NativeHttpChannel.kt:16`、`core/common/android_native_http.dart:13` | 是 | 没验证 | `platform/native_http.dart`（M12、M4.34） | |

## 3 网络和代理（NET）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-NET-01 | 应用代理（平台请求、弹幕、图片、WebDAV） | `common/services/settings/proxy_settings_controller.dart:16`、`common/global/initialized.dart:81` | 是 | 完成 | `app/platforms.dart` 的 `SettingsProxyPolicy`（M1、M12） | |
| F-NET-02 | 播放代理（独立的一组设置，播放走它，关掉时直连；录制的中继走应用代理，`common/global/initialized.dart:94`） | `player/core/playback_proxy_policy.dart:6`、`modules/settings/pages/network_proxy_settings_page.dart:16` | 是 | 缺失 | 设置页有入口，但 `proxyPort` 没人读，播放和录制只走应用代理 | 3.x 用户的播放代理现在不生效；半成品：M12.5 分支 `2894bdfe0` |
| F-NET-03 | 断网预检、移动数据提示 | `common/base/base_controller.dart:19` | 是 | 完成 | `app/network.dart`（M12.3） | |
| F-NET-04 | Twitch 网页完整性令牌（无界面浏览器） | `core/utils/twitch/twitch_web_integrity.dart:9` | 是 | 没验证 | `platform/twitch_webview_http.dart`（UPGRADES X-1） | |

## 4 推荐和分区（BRW）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-BRW-01 | 推荐页按平台浏览（平台来自“平台显示”，首选平台） | `modules/popular/popular_page.dart:7` | 是 | 完成 | `features/popular/`（M13.1、U.4b） | |
| F-BRW-02 | 各平台的翻页方式、按人数排序 | `modules/popular/popular_grid_controller.dart:35`、`modules/popular/popular_controller.dart:50` | 是 | 完成 | `shared/rooms/room_feed.dart` | |
| F-BRW-03 | 下拉刷新、滚动加载、回到顶部 | `common/base/base_controller.dart`、`common/services/settings/page_settings_controller.dart:8` | 是 | 完成 | M13.1 | 桌面页码栏手机上不出现（同 v3） |
| F-BRW-04 | 分区页：分类标签、分区网格、借图 | `modules/areas/areas_page.dart:8`、`plugins/area_pic_mapper.dart:8` | 是 | 完成 | `features/areas/`（M13.5、U.4d） | |
| F-BRW-05 | 分区房间 | `modules/area_rooms/area_rooms_page.dart:9` | 是 | 完成 | `features/area_rooms/`（M13.5、U.4e） | |
| F-BRW-06 | 关注分区（分区房间页的按钮、关注的分区页） | `modules/area_rooms/area_rooms_page.dart:104`、`modules/areas/favorite_areas_page.dart:8` | 是 | 完成 | M13.5、U.4f | |
| F-BRW-07 | 平台显示（开关、排序、首选平台） | `modules/hot_areas/hot_areas_page.dart:5`、`common/services/settings/favorite_room_controller.dart:20,24` | 是 | 完成 | `features/hot_areas/` | |
| F-BRW-08 | 网络电视频道在分区页直接播放；CC 官方入口用浏览器打开 | `routes/app_navigation.dart:18,23` | 是 | 完成 | `routes/app_navigator.dart` | |
| F-BRW-09 | 人数口径（热度或在线，按平台选） | `common/services/settings/app_settings_controller.dart:54`、`modules/settings/pages/audience_metric_settings_page.dart:4` | 是 | 完成 | `shared/rooms/room_cards.dart` 的 `AudiencePolicy` | |

## 5 房间卡片（CARD）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-CARD-01 | 点卡片进直播间 | `common/widgets/room_card.dart:121` | 是 | 完成 | `shared/rooms/room_grid.dart`、`live_ui` 的 `LiveRoomCard`（U.4a） | |
| F-CARD-02 | 长按菜单：房间信息、关注、取消关注（先确认） | `common/widgets/room_card.dart:177`、`:1232` | 是 | 完成 | `shared/rooms/room_menu.dart`（M12.2、U.4a） | |
| F-CARD-03 | 设置标签（未关注先问关注、就地新建标签） | `common/widgets/room_card.dart:234` | 是 | 完成 | `shared/rooms/room_tags_dialog.dart` | |
| F-CARD-04 | 分享（系统分享面板，内容是 3.x 格式的口令） | `common/utils/share_command_handler.dart:18` | 是 | 完成 | `shared/rooms/share_code.dart`、share_plus（M12.3） | K90 第二轮看过分享面板 |
| F-CARD-05 | 卡片外观（手机和桌面各一份、预设、显示内容） | `common/services/settings/room_card_settings_controller.dart:25`、`modules/settings/pages/room_card_settings_page.dart:5` | 是 | 完成 | M13.7、U.6b | |

## 6 关注（FAV）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-FAV-01 | 已开播、录播、未开播三组；平台栏；标签筛选 | `modules/favorite/favorite_page.dart:9`、`modules/favorite/favorite_controller.dart:20` | 是 | 完成 | `features/favorite/`（M13.2、U.4c） | K90 第一轮看过 |
| F-FAV-02 | 启动核验关注（“正在核验”“状态待确认”），启动页最多等 350 毫秒 | `modules/favorite/favorite_startup_policy.dart:10` | 是 | 完成 | `app/startup.dart`（M12.2） | |
| F-FAV-03 | 下拉、刷新按钮、再点“关注”刷新 | `modules/favorite/favorite_controller.dart` | 是 | 完成 | M13.2 | |
| F-FAV-04 | 定时刷新关注 | `modules/favorite/favorite_controller.dart:162` | 是 | 完成 | M13.2 | |
| F-FAV-05 | 回到前台刷新关注 | `modules/favorite/favorite_controller.dart:131` | 是 | 完成 | M13.2 | |
| F-FAV-06 | 刷新并发上限、单个 10 秒超时、失败冷却 | `modules/favorite/favorite_controller.dart:772` | 是 | 完成 | `features/favorite/` 的刷新器 | |
| F-FAV-07 | 紧凑关注卡片 | `modules/favorite/room_grid_view.dart:33` | 是 | 完成 | `Settings.enableDenseFavorites` 有读取 | |
| F-FAV-08 | 按主播关注的身份迁移（niconico、YouTube、抖音） | 3.x 没有（v4 迁移 3.x 旧关注） | 是 | 完成 | `app/platforms.dart`、`IdentityMigration`（M9、M12） | 联网解析没在真机跑过，随 F.9c 看 |

## 7 搜索（SRC）和观看历史（HIS）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-SRC-01 | “全部”和单个平台搜索、并发、翻页 | `modules/search/search_controller.dart:17` | 是 | 完成 | `features/search/`（M13.4、M13.16；U.5a 界面开发中） | K90 第一轮看过国内平台 |
| F-SRC-02 | 包含未开播、四种排序 | `modules/search/search_ranking.dart:5` | 是 | 完成 | M13.4 | |
| F-SRC-03 | 部分平台失败的提示、继续网页搜索 | `modules/search/search_controller.dart` | 是 | 完成 | M13.16 改为温和提示和“搜索范围” | |
| F-SRC-04 | 网页搜索（应用内浏览器，认出直播间后问是否进入） | `modules/search/web_search_controller.dart:19` | 是 | 没验证 | `shared/in_app_web.dart`（M12.3，flutter_inappwebview 预发布版） | |
| F-SRC-05 | 搜索结果的卡片菜单 | `common/widgets/room_card.dart:177` | 是 | 完成 | 同 F-CARD-02 | |
| F-HIS-01 | 进房成功后记观看历史 | `modules/live_play/controllers/live_play_controller.dart:752` | 是 | 完成 | M13.3 | |
| F-HIS-02 | 历史列表、条数上限、清空、删除、刷新状态 | `modules/history/history_page.dart:7`、`common/services/settings/history_controller.dart:52` | 是 | 完成 | `features/history/`（M13.6；U.5c 界面开发中） | |

## 8 直播间

### 8.1 播放和画面（ROOM）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-ROOM-01 | 进房取详情、合并卡片信息、更新关注快照 | `modules/live_play/controllers/live_play_controller.dart:249`、`:753` | 是 | 完成 | `features/live_play/logic/room_controller.dart`（M13.3） | K90 第一轮 7 个国内平台能播 |
| F-ROOM-02 | 默认清晰度（WLAN、移动数据各一个偏好） | `modules/live_play/controllers/player_controller.dart:594`、`:613` | 是 | 完成 | `shared/rooms/play_quality.dart`、`app/network.dart`（M12.3） | |
| F-ROOM-03 | 切换清晰度和线路（不重建播放器，旧流继续播） | `player_controller.dart:686`、`modules/live_play/widgets/resolution_selector/line_selector.dart:5` | 是 | 完成 | M13.3、U.2f | |
| F-ROOM-04 | 播放失败浮层、重试、自动恢复（刷新地址、换线、软解、延迟重试） | `modules/live_play/widgets/video_player/playback_failure_overlay.dart:5`、`player/core/player_manager.dart:213` | 是 | 完成 | `packages/live_player` 的 `PlaybackSession`（M7.2）、U.2g | 高通 HEVC 硬解的回退待真机 |
| F-ROOM-05 | 未开播、封禁、轮播的占位和刷新 | `modules/live_play/widgets/placeholder/not_living_video_widget.dart:9` | 是 | 完成 | U.2g；v4 另外每 60 秒刷新、开播自动播放 | |
| F-ROOM-06 | 刷新直播间 | `modules/live_play/widgets/video_player/video_controller.dart:1269` | 是 | 完成 | M13.3 | |
| F-ROOM-07 | 全屏、横屏、转向规则、默认全屏 | `video_controller.dart:1323`、`:1388`、`:626` | 是 | 完成 | U.2c | K90 第二轮看过全屏 |
| F-ROOM-08 | 单击显示/隐藏控制层、双击全屏 | `video_controller.dart:936` | 是 | 完成 | UI_PLAN 附录 A 第 1、3 条有测试 | |
| F-ROOM-09 | 左侧上下滑调亮度、右侧调音量 | `video_controller.dart:854` | 是 | 完成 | `features/live_play/player/player_gestures.dart`（M13.14） | K90 第二轮看过音量手势 |
| F-ROOM-10 | 锁定 | `modules/live_play/widgets/video_player/video_controller_panel.dart:247` | 是 | 完成 | U.2c | |
| F-ROOM-11 | 全屏顶栏的时间和电量 | `video_controller_panel.dart:33`、`video_controller.dart:761` | 是 | 完成 | `features/live_play/logic/device_battery.dart`（U.2c） | |
| F-ROOM-12 | 画面比例 | `video_controller.dart:1518` | 是 | 完成 | `features/live_play/dialogs/player_dialogs.dart` | |
| F-ROOM-13 | 屏幕常亮（可关） | `modules/live_play/controllers/live_play_controller.dart:177` | 是 | 有问题 | `Settings.enableScreenKeepOn` 没人读；`LiveVideoView` 用 media_kit 默认的常亮 | 关掉设置后仍常亮 |
| F-ROOM-14 | 默认音量、全局静音、进房不改设备音量 | `common/services/settings/volume_settings_controller.dart:8` | 是 | 完成 | M13.3 | |
| F-ROOM-15 | 房间音量（对话框、按房间记住） | `modules/live_play/dialogs/room_volume_dialog.dart:7`、`player/core/live_room_volume_manager.dart:7` | 是 | 完成 | `features/live_play/dialogs/room_dialogs.dart` | 3.x 键名照旧 |
| F-ROOM-16 | 关注按钮（取消前确认） | `modules/live_play/widgets/button/favorite_floating_button.dart:7` | 是 | 完成 | `features/live_play/buttons/follow_button.dart` | |
| F-ROOM-17 | 人数显示 | `modules/live_play/widgets/resolution_selector/audience_info.dart:4` | 是 | 完成 | 在线、热度、累计分开（M13.3） | |
| F-ROOM-18 | 标题栏信息、直播间详情（公告、简介） | `modules/live_play/widgets/layout/live_play_header.dart:8` | 是 | 完成 | U.2a | |
| F-ROOM-19 | 纯音频模式 | `video_controller.dart:1246` | 是 | 完成 | M13.14 | |
| F-ROOM-20 | 自动助眠（进房即纯音频并定时） | `live_play_controller.dart:118` | 是 | 完成 | M13.14 | 通知权限见 F-AND-03 |
| F-ROOM-21 | “退出时销毁播放器”（关时复用播放器给下一个房间） | `common/services/settings/player_settings_controller.dart:52` | 是 | 缺失 | `Settings.useHardStopOnExit` 没人读；v4 离开即释放或转小窗 | 要不要保留这个开关需要用户定 |
| F-ROOM-22 | 抖音竖屏流的画面比例预判（避免起播时跳） | `player/core/live_stream_geometry_hint.dart:8` | 是 | 缺失 | M7.1、M7.2 留下（要 `live_core` 抖音数据带宽高） | |
| F-ROOM-23 | 硬解、兼容模式、自定义输出（vo、ao、hwdec） | `common/services/settings/player_settings_controller.dart:39`、`modules/settings/pages/player_kernel_settings_page.dart:16` | 是 | 完成 | `MpvEngineConfig`（M13.3） | |
| F-ROOM-24 | 播放内核切换（fvp、exo、ijk） | `player_settings_controller.dart:34` | 否 | 不做 | v4 只用 mpv（PLAN 第 4 节） | |
| F-ROOM-25 | 键盘快捷键（空格、方向键、R、F、Esc、媒体键） | `modules/live_play/widgets/keyboard/video_keyboard.dart:56` | 部分（外接键盘） | 部分 | M13.3、M13.14 有空格、方向键、R、F、Esc；媒体键没有 | Android 上耳机按键走媒体通知 |

### 8.2 直播间菜单和工具（RT）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-RT-01 | 投屏（DLNA） | `modules/live_play/dialogs/live_dlna_dialog.dart:6`、`common/utils/live_url_tool.dart:405` | 是 | 没验证 | `packages/live_cast`（M10）、`features/live_play/dialogs/stream_dialogs.dart` | 没对真电视试过 |
| F-RT-02 | 获取直链（选清晰度、线路、复制） | `common/utils/live_url_tool.dart:388`、`modules/live_play/dialogs/known_room_link_dialog.dart:10` | 是 | 完成 | `stream_dialogs.dart`（M13.14） | |
| F-RT-03 | 分享直播间 | `modules/live_play/widgets/button/live_play_menu_button.dart:8` | 是 | 完成 | `features/live_play/buttons/room_menu_button.dart` | |
| F-RT-04 | 在平台 App 或浏览器打开（哔哩哔哩、斗鱼、抖音、虎牙、CC 有 App 跳转） | `modules/live_play/services/room_external_opener.dart:33` | 是 | 完成 | `room_menu_button.dart:30` | |
| F-RT-05 | 快手 App 跳转（按 `liveStreamId`） | `room_external_opener.dart:193` | 是 | 缺失 | `room_menu_button.dart` 没有快手分支，只开网页 | |
| F-RT-06 | 切换直播间（已开播的关注、关注的回放、历史） | `modules/live_play/dialogs/play_other.dart:11` | 是 | 完成 | `features/live_play/dialogs/room_switcher.dart` | |
| F-RT-07 | 切换直播间里的刷新按钮（刷新关注） | `modules/live_play/dialogs/play_other.dart:119` | 是 | 缺失 | `room_switcher.dart` 没有刷新 | |
| F-RT-08 | 直播间定时关闭 | `modules/live_play/dialogs/room_timer_dialog.dart:6` | 是 | 完成 | `room_dialogs.dart`（M13.14） | |
| F-RT-09 | 录制按钮和录制选项 | `modules/live_play/widgets/button/record_action_button.dart:11` | 是 | 完成 | `features/live_play/record/record_panel.dart`（U.2f） | |
| F-RT-10 | 网络电视节目单、回看、返回直播 | `modules/live_play/widgets/video_player/iptv_schedule_dialog.dart:10`、`iptv_programme_policy.dart:7` | 是 | 完成 | `features/live_play/dialogs/iptv_guide.dart`（M13.14） | |
| F-RT-11 | 网络电视播放带自定义 UA 和频道请求头 | `player/core/playback_header_resolver.dart:144` | 是 | 完成 | `room_controller.dart` 的 `iptvPlayHeaders` | |

### 8.3 竖屏直播（PORT）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-PORT-01 | 竖屏流自适应高度和布局模式 | `modules/live_play/widgets/content_first_panel_layout.dart:16`、`player/core/portrait_stream_support.dart:33` | 是 | 完成 | U.2b | |
| F-PORT-02 | 竖屏全屏（三档面板、上滑退出）和显示模式 | `modules/live_play/widgets/layout/portrait_fullscreen_interaction.dart:47`、`video_controller.dart:1417` | 是 | 完成 | U.2b | |
| F-PORT-03 | 方向选择、按房间记住 | `modules/live_play/widgets/video_player/portrait_playback_picker_dialog.dart:5` | 是 | 完成 | `features/live_play/logic/room_orientation.dart` | |
| F-PORT-04 | 竖屏时的弹幕模式 | `modules/settings/pages/portrait_live_settings_page.dart:6` | 是 | 完成 | M13.14 | |
| F-PORT-05 | 小窗跟随竖屏源的比例 | `modules/settings/pages/portrait_live_settings_page.dart:6` | 是 | 缺失 | `Settings.portraitPipFollowSource` 没人读 | |
| F-PORT-06 | 竖屏诊断信息 | `modules/settings/pages/portrait_live_settings_page.dart:154` | 是 | 缺失 | `Settings.showPortraitDiagnostics` 没人读 | |

### 8.4 小窗和后台（MINI）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-MINI-01 | 后台播放（离开应用 1.5 秒后暂停；开关打开时继续，持有唤醒锁和 Wi-Fi 锁） | `player/core/playback_lifecycle_coordinator.dart:25`、`player/core/background_playback_policy.dart:11` | 是 | 没验证 | `features/live_play/logic/background_playback.dart`（M13.14） | |
| F-MINI-02 | 离开直播间时应用内悬浮小窗 | `player/core/player_manager.dart:2970` | 是 | 完成 | `features/live_play/mini/floating_window.dart`、`logic/room_runtime.dart`（U.2j） | |
| F-MINI-03 | 小窗弹幕（13 项设置） | `modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart:6`、`modules/settings/pages/pip_danmaku_settings_page.dart:12` | 是 | 完成 | `features/live_play/mini/compact_danmaku.dart`（U.2j） | |
| F-MINI-04 | 小窗弹幕设置的实时预览 | `modules/settings/pages/pip_danmaku_settings_page.dart:31` | 是 | 完成 | `features/settings/playback_tiles.dart` 的 `PipDanmakuPreviewBinding`、`packages/live_ui` 的 `PipDanmakuPreview`（U.6c） | 清点时 U.6c 还没合并，F.1d 核对后改 |

## 9 弹幕（DM）和本地互动（LOC）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-DM-01 | 弹幕连接、状态行、断线重连 | `modules/live_play/controllers/danmaku_controller.dart:19` | 是 | 完成 | `packages/live_danmaku`（M5） | K90 第一轮 5 个国内平台有弹幕 |
| F-DM-02 | 飞行弹幕（显示开关、画面上显示） | `modules/live_play/widgets/video_player/video_controller.dart:179` | 是 | 完成 | `shared/danmaku/danmaku_overlay.dart` | |
| F-DM-03 | 区域、上下留白、透明度、速度、字号、粗细、描边 | `modules/live_play/pages/danmaku_settings_page.dart:9` | 是 | 完成 | `shared/danmaku/danmaku_settings.dart`（U.2f） | |
| F-DM-04 | 弹幕帧率（跟随屏幕或固定） | `video_controller.dart:90` | 是 | 有问题 | 设置面板有；主画面弹幕层不读 `danmakuFps`、`danmakuAutoFps`（只有小窗弹幕读帧率） | |
| F-DM-05 | 弹幕字体 | `video_controller.dart:91` | 是 | 缺失 | 字体能下载、注册（M12.4）；弹幕层不读 `danmakuFontFamilyName` | |
| F-DM-06 | 纯文字模式（不显示表情） | `video_controller.dart:76` | 是 | 有问题 | 开关只进模板（`shared/danmaku/danmaku_templates.dart:36`），弹幕层不读 `noEmojiMode` | |
| F-DM-07 | 观看模板（预设、保存、恢复） | `modules/live_play/widgets/danmaku/danmaku_viewing_preset.dart:3` | 是 | 完成 | `danmaku_templates.dart`（M13.14、U.2f） | 3.x 存的模板照旧可用 |
| F-DM-08 | 合并重复、相似过滤 | `modules/live_play/controllers/repeated_danmaku_filter.dart:11`、`danmaku_similarity_filter.dart:9` | 是 | 完成 | `packages/live_danmaku` 的 `DanmakuMessageFilter` | |
| F-DM-09 | 屏蔽关键词、屏蔽用户（直播间和设置页） | `modules/live_play/pages/keyword_block_page.dart:6`、`modules/shield/danmu_shield_page.dart:6` | 是 | 完成 | `shared/danmaku/block_manager.dart`、`features/shield/`（M13.9、U.2e） | |
| F-DM-10 | 斗鱼疑似机器弹幕过滤 | `core/danmaku/douyu_danmaku.dart:15` | 是 | 完成 | `app/platforms.dart:184` | |
| F-DM-11 | 弹幕列表（跟随到底、新消息提示） | `modules/live_play/widgets/danmaku/danmaku_list_view.dart:41` | 是 | 完成 | `features/live_play/danmaku/chat_list.dart`（U.2e） | |
| F-DM-12 | 弹幕列表长按：复制、屏蔽此用户、屏蔽关键词 | `modules/live_play/widgets/danmaku/danmaku_message_actions.dart:6`、`:48` | 是 | 完成 | `chat_list.dart:521`（U.2f） | |
| F-DM-13 | 画面上的弹幕点按、长按（同上三项） | `video_controller.dart:132` | 是 | 缺失 | 设置开关有（`enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction`），弹幕层没有命中检测 | U.2f 记录里写的“完成”只是设置项 |
| F-DM-14 | 醒目留言（进房拉取、到时移除） | `modules/live_play/pages/super_chat_page.dart:5` | 是 | 完成 | `features/live_play/danmaku/super_chats.dart` | |
| F-DM-15 | 聊天列表里的表情图片 | `plugins/emoji_manager.dart:7` | 是 | 完成 | `shared/danmaku/emotes.dart`（M13.16） | |
| F-DM-16 | 飞行弹幕里的表情图片 | `core/emoji/models/unified_emoji_model.dart:4` | 是 | 缺失 | M13.16 留给弹幕渲染层（U.2h） | |
| F-DM-17 | 播放器上的弹幕设置按钮（全屏也能调） | `video_controller_panel.dart:1843` | 是 | 完成 | U.2f | |
| F-LOC-01 | 本地弹幕输入（列表下、全屏） | `modules/live_play/widgets/local_interaction/local_interaction_controller.dart:3` | 是 | 完成 | `features/live_play/local_interaction/`（U.2k） | |
| F-LOC-02 | 本地礼物特效、体验币、等级、本地弹幕样式 | `modules/live_play/pages/live_play_page.dart:28`、`local_interaction/local_danmaku_style_editor.dart` | 是 | 完成 | U.2k | |
| F-LOC-03 | 本地互动设置页 | `modules/settings/pages/local_interaction_settings_page.dart:5` | 是 | 完成 | 设置总览入口已接（提交 `0eb94e4b1`） | |

## 10 多画面（MV）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-MV-01 | 四种布局、一大多小加格（手机最多 4 格） | `modules/multiview/multiview_controller.dart:49` | 是 | 完成 | `features/multiview/`（M13.12、U.8） | |
| F-MV-02 | 声音焦点、全部静音、每格音量 | `multiview_controller.dart:649` | 是 | 完成 | M13.12 | |
| F-MV-03 | 每格清晰度、线路、小格省流 | `multiview_controller.dart:414` | 是 | 完成 | M13.12 | |
| F-MV-04 | 选台（关注、历史、搜索） | `modules/multiview/widgets/multiview_room_picker.dart:31` | 是 | 完成 | M13.12、U.8 | |
| F-MV-05 | 多画面弹幕 | `modules/multiview/danmaku/multiview_danmaku_session.dart:26` | 是 | 完成 | M13.12 | |
| F-MV-06 | 4 路同时解码、沉浸、全屏和返回 | `modules/multiview/multiview_page.dart:36` | 是 | 没验证 | M13.12 留给真机 | |

## 11 录制（REC）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-REC-01 | 添加录制（立即录、等开播）、停止、删除 | `recorder/pages/recorder/recorder_controller.dart:693` | 是 | 完成 | `packages/live_record`（M8）、`features/live_play/record/record_panel.dart` | |
| F-REC-02 | 录制中心（状态筛选、任务卡片、操作） | `recorder/pages/recorder/recorder_page.dart:12` | 是 | 完成 | `features/recorder/`（M13.15、U.7a） | |
| F-REC-03 | FFmpeg 录制、分段、合并成 MP4 | `recorder/services/ffmpeg_service.dart:51`、`recorder/services/video_processor_service.dart:14` | 是 | 没验证 | M8、M13.15 | 没在真机录完一场 |
| F-REC-04 | 断线重连、重试、退避、开播轮询检测 | `recorder/services/recorder_continuation_policy.dart:1`、`recorder_controller.dart:87` | 是 | 完成 | M8 | |
| F-REC-05 | 启动时恢复任务 | `common/global/initial_services.dart:85` | 是 | 完成 | `app/recording.dart` | |
| F-REC-06 | 前台服务、通知、唤醒锁；划掉应用后继续录 | `android/.../RecorderForegroundService.kt:20`、`android/.../RecorderBackgroundPlugin.kt:21` | 是 | 没验证 | `RecorderForegroundService.kt`（M13.15、M8.1） | HyperOS 可能划掉即杀 |
| F-REC-07 | 存储权限（Android 11 起“所有文件访问”） | `recorder/pages/recorder/recorder_controller.dart:665` | 是 | 没验证 | `RecorderPlugin.requestStorage`（M13.15） | |
| F-REC-08 | 录制目录、缓存上限清理 | `recorder/services/cache_service.dart:19`、`recorder/consts/recorder_config.dart:135` | 是 | 完成 | `packages/live_record` 的 `RecordStorage` | |
| F-REC-09 | 录制设置（清晰度、分段、超时、并发、拼音目录等 19 项） | `recorder/pages/record_settings/record_settings_page.dart:10` | 是 | 完成 | `features/record_settings/`（M8.1；U.7b 界面待开发） | |
| F-REC-10 | 同时录制弹幕（XML） | `recorder/services/recording_danmaku_service.dart:11` | 是 | 没验证 | `packages/live_record` 的 `chat.dart`（M8.1） | |
| F-REC-11 | HLS 预取和保留窗口（减少漏段） | `recorder/services/hls_relay_prefetch.dart:182` | 是 | 没验证 | `packages/live_media` 的 `HlsMediaWindow`（M8.1） | 效果没在真机量 |
| F-REC-12 | 打开录制文件夹 | `recorder/pages/recorder/recorder_controller.dart:1599` | 是 | 完成 | M8.1（应用专属目录改为复制路径） | |
| F-REC-13 | 合并进度（v3 只发进度事件，界面没接） | `recorder/services/video_processor_service.dart:26` | 是 | 缺失 | M8 留给后续 | |

## 12 网络电视、账号、备份、工具、标签

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-IPTV-01 | 导入播放列表（网络、本地文件） | `core/iptv/services/iptv_import_manager.dart:24`、`modules/iptv/iptv_page.dart:13` | 是 | 完成 | `features/iptv/`（M13.11、U.9）；本地文件用系统选择器（M12.3） | |
| F-IPTV-02 | 导入节目单（网络、本地、默认节目单） | `core/iptv/services/epg_import_manager.dart:19`、`core/iptv/services/auto_sync_scheduler.dart:56` | 是 | 完成 | M13.11 | |
| F-IPTV-03 | 自动同步（按间隔）、手动同步 | `core/iptv/services/auto_sync_scheduler.dart:12` | 是 | 完成 | 启动 3 秒后自动同步（M12） | |
| F-IPTV-04 | 订阅源管理（删除、打开文件、切换节目单） | `modules/iptv/iptv_manage.dart:15` | 是 | 完成 | M13.11 | |
| F-IPTV-05 | 自定义请求头 | `common/services/settings/iptv_settings_controller.dart:26` | 是 | 完成 | M13.11、M13.14 | |
| F-ACC-01 | 账号列表（各平台状态、退出） | `modules/account/account_page.dart:9` | 是 | 完成 | `features/account/`（M13.8、U.10a） | |
| F-ACC-02 | 哔哩哔哩扫码登录 | `modules/account/bilibili/qr_login_page.dart:8` | 是 | 完成 | M13.8 | |
| F-ACC-03 | 哔哩哔哩网页（短信）登录；退出时清浏览器 Cookie | `modules/account/bilibili/web_login_page.dart:6` | 是 | 没验证 | `features/account/bilibili_web_login.dart`（M12.3） | |
| F-ACC-04 | 虎牙、抖音、快手、YY、Twitch、SOOP 的 Cookie 页 | `modules/account/widgets/account_cookie_editor.dart:34`、`modules/account/huya/huya_cookie_page.dart:5` | 是 | 完成 | M13.8、U.10b | |
| F-ACC-05 | 斗鱼 Cookie 和 LTP0 续期 | `modules/account/douyu/douyu_cookie_controller.dart:5` | 是 | 完成 | M13.8 | |
| F-ACC-06 | 启动时核验哔哩哔哩登录 | `common/services/settings/bilibili_account_service.dart:13` | 是 | 完成 | `app/startup.dart`（M12.2） | |
| F-ACC-07 | 登录后取流（高画质、受限房间） | `core/site/*`（Cookie 进请求） | 是 | 没验证 | 适配器经 `StoreCookieVault` 读 Cookie | 没用真实登录 Cookie 在真机看过画质 |
| F-ACC-08 | 云账号（Firebase 登录、云端配置） | `modules/auth/auth_controller.dart:8` | 否 | 不做 | 用户已决定（M12、U.10c） | |
| F-BAK-01 | 完整备份和恢复（3.x 格式） | `plugins/backup_recovery_service.dart:13`、`modules/backup/backup_page.dart:14` | 是 | 完成 | `features/backup/`（M13.10；U.11a 界面待开发） | |
| F-BAK-02 | 仅关注备份和恢复 | `plugins/backup_recovery_service.dart:46` | 是 | 完成 | M13.10 | |
| F-BAK-03 | 备份目录 | `plugins/backup_recovery_service.dart:14` | 是 | 没验证 | M13.10 | Android 11 起 `Download/PureLive` 免权限写入没在真机试 |
| F-BAK-04 | WebDAV（配置、浏览、上传、恢复、删除、帮助） | `modules/web_dav/web_dav_page.dart:12`、`modules/web_dav/web_dav_controller.dart:50` | 是 | 部分 | `features/web_dav/`（M13.10） | 只有 Basic 认证，v3 的 webdav_client 还支持 Digest |
| F-BAK-05 | 设备同步（局域网配对、收发、和 3.x 设备互相发现） | `modules/remote_receiver/remote_sync_service.dart:14`、`:45` | 是 | 没验证 | `features/remote_receiver/`（M13.13、M12.4） | |
| F-BAK-06 | 扫码（设备同步、同步到电视） | `modules/backup/scan_page.dart:50` | 是 | 没验证 | `shared/qr_scan.dart`（M12.3） | |
| F-BAK-07 | 同步到电视 | `plugins/backup_recovery_service.dart:123` | 是 | 完成 | `features/backup/tv_sync.dart` | |
| F-TOOL-01 | 工具箱：链接跳转、获取直链 | `modules/toolbox/toolbox_page.dart:7`、`modules/toolbox/toolbox_direct_link_flow.dart:9` | 是 | 完成 | `features/toolbox/`（M13.13） | |
| F-TOOL-02 | 工具箱打开时把剪贴板里的链接填进框 | `modules/toolbox/toolbox_controller.dart:250` | 是 | 完成 | M13.13 | |
| F-TOOL-03 | 关于（版本、许可证、项目主页、声明） | `modules/about/about_page.dart:8` | 是 | 完成 | `features/about/` | |
| F-TOOL-04 | 版本页、历史版本 | `modules/version/version_page.dart:16`、`modules/about/version_history.dart` | 是 | 完成 | `features/version/` | |
| F-TAG-01 | 标签管理（增删改、置顶、排序） | `modules/tags/tag_management_page.dart:9` | 是 | 完成 | `features/tags/`（M13.9） | |

## 13 Windows 专属（以后）

本阶段不做，列出以免以后漏掉。都是“Android：否”。

| 编号 | 功能 | v3 位置 |
|---|---|---|
| F-WIN-01 | 自绘标题栏（拖动时显示尺寸） | `common/global/platform/desktop_manager.dart:263` |
| F-WIN-02 | 窗口大小（立即应用）、位置 | `common/services/settings/window_size_controller.dart:6` |
| F-WIN-03 | 托盘（显示、隐藏、退出） | `common/global/platform/desktop_tray_service.dart:7` |
| F-WIN-04 | 关闭窗口时：询问、最小化到托盘、退出 | `plugins/utils.dart:7` |
| F-WIN-05 | 开机启动（注册表） | `common/global/win_auto_start.dart:8`、`common/services/settings/startup_controller.dart:12` |
| F-WIN-06 | 单实例、在新窗口打开直播间 | `common/utils/windows_multi_instance_launcher.dart:18` |
| F-WIN-07 | 桌面小窗（置顶、记住位置） | `player/utils/window_helper.dart` |
| F-WIN-08 | 窗口内全屏按钮 | `modules/live_play/widgets/video_player/video_controller_panel.dart:1882` |
| F-WIN-09 | 控制栏音量按钮（悬停出滑块、一键静音） | `modules/live_play/widgets/video_player/volume_control.dart:10` |
| F-WIN-10 | Windows 动态刷新率信息 | `modules/settings/pages/general_settings_page.dart:24` |
| F-WIN-11 | RTX 超分 | `common/services/settings/player_settings_controller.dart` |
| F-WIN-12 | Kick 的 WinHTTP 通道 | UPGRADES X-1 |
| F-WIN-13 | 鼠标悬停显示控制层、右键菜单 | `modules/live_play/widgets/layout/control_hover_region.dart` |
| F-WIN-14 | 退出前写盘（`didRequestAppExit`） | `common/global/platform/desktop_manager.dart:765` |

## 14 平台能力表（Android）

v4 的平台层（`packages/live_core`、`packages/live_danmaku`）在 M4、M4.U、M5 里一个平台一个记录做完，下表只写 Android 上的现状。“K90 看过”指 2026-10-01 两轮真机测试（`~/ref/notes/m13_notes.md` 的 DEVICE TEST）；其余“完成”是样本和探针测过、没在真机播放。海外平台在国内要代理。

图例：完成；无（v3 也没有）；新增（v3 没有、v4 加的）；受阻（UPGRADES 里写明原因）；— 不适用。

| 平台 | 播放 | 清晰度和线路 | 弹幕 | 登录（Cookie） | 搜索 | 分区 | 关注状态 | 备注 |
|---|---|---|---|---|---|---|---|---|
| 哔哩哔哩 | 完成，K90 看过 | 完成 | 完成，K90 看过 | 扫码、网页、Cookie | 直播和未开播、主播 | 完成 | 完成 | 1-1 登录后播放轮播没做（升级） |
| 斗鱼 | 完成，K90 看过 | 完成 | 完成，K90 看过 | Cookie、续期 | 直播和未开播、主播 | 完成 | 完成 | C-5 进房补拉超级弹幕待做（找不到网页接口） |
| 虎牙 | 完成，K90 看过 | 完成 | 完成，K90 看过 | Cookie | 只搜直播中、主播 | 完成 | 完成 | |
| 抖音 | 完成，K90 看过 | 完成 | 完成，K90 看过 | Cookie | 只搜直播中 | 完成（新增游戏分区） | 完成 | 竖屏比例预判缺（F-ROOM-22） |
| 快手 | 完成，K90 看过 | 完成 | 完成，K90 看过 | Cookie | 直播和未开播、主播 | 完成 | 完成 | App 跳转缺（F-RT-05）；登录后直播搜索 C-17 待做 |
| YY | 完成，K90 看过 | 完成 | 完成 | Cookie | 只搜直播中、主播 | 完成 | 完成 | |
| 网易 CC | 完成，K90 看过 | 完成 | 无（匿名加入不回应，C-22 待登录后试） | 只存，未用于请求 | 直播和未开播、主播 | 完成 | 完成 | |
| SOOP | 完成 | 完成 | 完成 | Cookie | 只搜直播中 | 完成 | 完成 | 7-8 密码房输入密码受阻 |
| Twitch | 完成（原生 TLS + 浏览器令牌，没验证） | 完成 | 完成 | Cookie | 直播和未开播 | 完成 | 完成 | B-7 Cookie 失效提示没做（升级） |
| AcFun | 完成 | 完成 | 新增 | — | 直播和未开播、主播 | 完成 | 完成 | |
| Picarto | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | 11-1 恢复时取最好一档没做（升级） |
| TwitCasting | 完成 | 完成 | 新增 | — | 只搜直播中 | 完成 | 完成 | |
| 猫耳 FM | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| 映客 | 完成 | 完成 | 无 | — | 推荐里筛选 | 完成 | 完成 | |
| 克拉克拉 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| 小红书 | 完成 | 完成 | 无 | — | 只能按房间号查 | 无（v3 同） | 只能按场次 | 16-5 按主播关注受阻 |
| niconico | 完成 | 完成 | 新增 | — | 只搜直播中 | 完成 | 完成（按主播） | |
| 微博直播 | 完成 | 完成 | 无 | — | 只能按房间号查 | 完成 | 只能按场次 | 18-10 按主播关注受阻 |
| SHOWROOM | 完成 | 完成 | 新增 | — | 只搜直播中 | 完成 | 完成 | 19-5 付费标注受阻 |
| CHZZK | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| LiveMe | 完成 | 完成 | 受阻（要登录 IM） | — | 直播和未开播 | 无（v3 同） | 完成 | |
| TikTok | 完成（受限房间说明原因） | 完成 | 受阻（要签名） | — | 只能精确查频道 | 受阻（无推荐和分区） | 完成 | |
| YouTube | 完成 | 完成 | 新增 | — | 只搜直播中 | 无（v3 同） | 完成（按频道） | |
| BIGO LIVE | 完成 | 完成 | 新增 | — | 推荐里筛选 | 完成 | 完成 | |
| PandaTV | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| FC2 LIVE | 完成 | 完成（三档） | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| Steam 直播 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | 27-3 国内 CDN 受阻 |
| 京东直播 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | 28-7 标题和店铺名受阻 |
| 酷狗直播 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | B-16 PK 对方聊天没做（升级） |
| 百度直播 | 完成 | 完成 | 新增 | — | 只能按房间号查 | 完成 | 完成 | |
| 六间房 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| LOOK 直播 | 完成 | 完成 | 新增 | — | 只能按房间号查 | 完成 | 完成 | |
| 17LIVE | 完成 | 完成 | 新增 | — | 只搜直播中 | 新增 | 完成 | |
| Kick（v3.2.11 已下线） | 新增，只在 Android（原生 HTTP），没验证 | 完成 | 新增 | — | 一页频道 | 完成 | 完成 | |
| 网络电视 | 完成 | 完成 | — | — | 本机频道 | 按播放列表 | — | |

依据：播放、清晰度、线路、分区、关注状态见 `docs/modules/M4.*`、`M4.U`；弹幕见 `M5.*`（登记表在 `app/platforms.dart`）；搜索能力见 `features/search/search_capability.dart`；登录平台见 `features/account/`；“受阻”“没做（升级）”见 [UPGRADES.md](../UPGRADES.md)。

## 15 设置项核对

方法：从 `packages/live_store/lib/src/settings/settings.dart` 取出全部设置（213 个），在 `apps/pure_live/lib` 和其他包里找设置页以外读取它的代码。除下表外都有读取它的地方（行为对不对由各功能点和真机验证判断）。

| 设置（键） | 3.x 的行为 | v4 | 对应功能点 |
|---|---|---|---|
| `enableScreenKeepOn` | 播放时屏幕常亮，可关 | 没人读，一直常亮 | F-ROOM-13 |
| `useHardStopOnExit` | 关时离开直播间保留播放器给下一个房间 | 没人读 | F-ROOM-21 |
| `portraitPipFollowSource` | 小窗跟随竖屏源比例 | 没人读 | F-PORT-05 |
| `showPortraitDiagnostics` | 显示竖屏诊断 | 没人读 | F-PORT-06 |
| `proxyPort`（和 `enableProxy`、`proxyHost`） | 播放代理 | 只有本地网络权限守卫读开关和主机，播放不走它 | F-NET-02 |
| `danmakuFps`、`danmakuAutoFps` | 弹幕帧率 | 只有设置面板和模板读 | F-DM-04 |
| `danmakuFontFamilyName` | 弹幕字体 | 只有字体服务注册，弹幕层不读 | F-DM-05 |
| `noEmojiMode` | 纯文字弹幕 | 只有模板读 | F-DM-06 |
| `enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction` | 画面弹幕点按、长按 | 只有设置面板读 | F-DM-13 |
| `videoPlayerKey` | 播放内核 | 只为备份往返保留 | F-ROOM-24（不做） |
| `autoRefreshTime`、`enableRotateScreen`、`m3uDirectory` | 3.x 里也没有读取的代码（只存、只进备份） | 同 3.x | 不是功能 |
