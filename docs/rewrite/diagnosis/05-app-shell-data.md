# 第 0 阶段诊断：应用骨架与数据（master@49ceccb0，只读）

## ① 规模与结构

| 范围 | 文件 / 行 |
|---|---|
| lib/get（内置 GetX） | 99 / 15,677 |
| lib/common | 111 / 19,968（services 32/6,821，widgets 22/4,551，base 12/2,154，global 9/1,969） |
| lib/routes · main.dart | 5 / 631 · 210 |
| 页面模块（本范围） | settings 23/7,573 · auth 13/2,786 · search 10/2,331 · account 31/2,280 · iptv 2/1,845 · remote_receiver 6/1,758 · web_dav 6/1,656 · favorite 4/1,427 · areas 8/1,069 · backup 2/637 · version 3/587 · home 3/554 · popular 4/541 · history 1/407 · splash 1/172 |
| IPTV drift（core/iptv/local） | 4 / 10,331（其中生成代码 9,487） |

设置层的结构：`SettingsService`（GetxService）聚合 21 个延迟创建的设置控制器（settings_service.dart:26-83）。每个设置项都是 `hiveXxx(key, 默认值)` 生成的 Rx，再用一个 `ever` 写回存储（hive_rx.dart:9-114）。所有数据都存在同一个 Hive box `app_settings` 里。

## ② GetX 使用面

统计命令：`rg -c <模式> lib --glob '!lib/get/**'`

| 指标 | 数值 |
|---|---|
| 引用 GetX 的文件 | 直接引用 26 个；经 `common/index.dart:33` 重新导出间接引用 260 个；合计 285 个，占 lib 中 GetX 以外 664 个文件的 43% |
| 类型 | GetxController 56 · GetxService 7 · GetView 35 |
| 状态 | `Obx(` 219（84 个文件）· `.obs` 211 · Rx 类型 319 · ever/debounce 59 |
| 依赖注入 | Get.find 201（68 个文件）· isRegistered 44 · lazyPut 33 · put 13 · `SettingsService.to` 515（118 个文件） |
| 导航 | toNamed 39 · Get.to 28（多为无名设置子页）· GetPage 40 · Bindings 66 个文件 |
| 隐式上下文 | Get.theme 27 · width 15 · context 11 · locale 10 · dialog 10 · snackbar 7 · changeTheme 5 |
| 测试耦合 | 165 个测试文件共 902 次 Get.put/lazyPut/reset/delete；123 个测试文件直接操作 Hive |

模块分布（命中 GetX API 的次数，共 1,832）：common/services 393 · settings 273 · live_play 264 · account 68 · favorite 47 · app_pages 45 · iptv 37 · areas 36 · search 35 · auth 34 · popular 29 · web_dav 22 · home/remote_receiver 19 · version 16 · history 13 · backup 12。

代表位置：
- 最重的文件：backup_controller.dart（73 处；56-88 行导出时 19 次 Get.find）、settings_service.dart（46）、app_pages.dart（45）。
- main.dart:137-205：用一个 `Obx` 包住整个 GetMaterialApp，改主题、字号或启动页开关都会重建整棵树。
- backup_page.dart:82：在 `Obx` 里调用 `Get.find<AuthController>()`，打开页面就会触发 Firebase 初始化。
- home_page.dart:118,162：用 `Get.width > 680` 判断平板布局。

内置 GetX 有 4 处本地补丁，对应的行为 v4 必须保留：
- 1343f3e6：页面转场动画使用应用主题。
- ee85ed8d：画中画之后广播流需要重新挂接。
- b24fa1d2：浮层取上下文的方式。
- 6a02975b：小窗关闭流程串行化。

## ③ 旧数据清单

持久化的 Hive box 只有一个：`HIVE_DB/app_settings.hive`（hive_pref_util.dart:40-46）。迁移过程中会临时打开 `settings_upgrade_source_N`，用完即删。代码里没有注册任何自定义 TypeAdapter（`registerAdapter` 命中 0 次），值都是原始类型、List 或 Map。

| 数据 | 键 · 类型/格式 | 位置 | 迁移要点 |
|---|---|---|---|
| 关注直播间 | `favoriteRooms`：String，内容为 `{"list":[LiveRoom]}`；2.0 及以前为 `List<String>`（每项一个 JSON 字符串） | favorite_room_controller.dart:26-35,428-444；live_room.dart:357-405,559-596 | 身份键 = 平台（小写、去空格）+ `:` + 房间号（去空格、保留大小写）。`liveStatus` 存枚举下标（0 直播中 / 1 未开播 / 2 回放 / 3 未知 / 4 封禁）。`link`、`data` 不持久化 |
| 关注分区 | `favoriteAreas`：同上格式，LiveArea 共 7 个字段 | live_area.dart:14-50 | 身份键为 JSON 三元组 [平台, 命名空间（仅猫耳 missevan 使用 areaType）, areaId] |
| 历史 | `historyRooms`（LiveRoom + `lastWatchedAt` 毫秒）；`historyLimit` int，默认 50，0 表示不限 | history_controller.dart:8,52-68 | 升级时不能截断“不限”的历史 |
| 标签 | `user_custom_tags_v5`：List<Map>{id,name,description,order}；`room_to_tags_mapping_v1`：Map<String,List<String>> | tag_management_controller.dart:9-10,25-51,78-121 | 映射表是权威来源，旧键只有房间号；`LiveRoom.tagIds` 是陈旧副本，不能信 |
| 屏蔽 / 平台排序 | `shieldList`、`blockedDanmakuUsers`、`hotAreasList`（均为 List<String>）；`preferPlatform`；`siteCatalogMigration`=38 | favorite_room_controller.dart:16-24,58-120 | 平台 id 版本表：v2 一次加入全部平台，v3–v38 每版只追加一个平台；已退役的 id 保留槽位、永不重新加入 |
| Cookie（明文） | bilibiliCookie、bilibiliUid(int)、huyaCookie、douyuCookie、douyuCookieSavedAt(秒)、douyuLtp0、douyuDid、douyinCookie、kuaishouCookie、twitchCookie、soopCookie、yyCookie | cookie_settings_controller.dart:10-43 | 迁入加密存储。`taobaoCookie` 在启动时被删除 |
| WebDAV | `webDavConfigs` `{"list":[{name,address,username,password}]}`（密码明文）；`currentWebDavConfig`（JSON 字符串） | common/services/settings/web_dav_controller.dart:15-26 | 密码迁入加密存储 |
| 录制 | `recorder_tasks`（JSON 字符串）、`record_history`（List<Map>），外加 19 个录制设置键 | recorder_keys.dart:1-61；recorder_config.dart:99-296；recorder_controller.dart:76,1471 | 不在现有备份范围内 |
| 房间级偏好 | `roomVolumes`：JSON Map，键 `room_vol_{平台}_{房间号}`；`portraitRoomOverrides`：JSON Map，键 `平台:房间号` | live_room_volume_manager.dart:9；player_settings_controller.dart:71,173 | 键格式不统一 |
| 本地互动 | `localInteraction.*` 共 29 个键 | local_interaction_controller.dart:86-114 | 不在现有备份范围内 |
| 普通设置 | 约 180 个标量键（见 ⑤） | services/settings/*.dart | 部分值存的是显示文案：`language`='简体中文'，`preferResolution`='原画'，`themeMode`='System'；`videoPlayerKey` 可能是 ijk/exo（v4 已删除这两个内核） |
| 迁移标记 / 内部 | `settingsUpgradeSchema`=4、`settingsUpgradeImportedSources`（指纹账本）、`legacy_settings_migrated_to_v2`、`migration.room_scoped_audio_only.v231`、`audienceMetricMigration`=7、`danmakuInteractionMigration`=1、`remote_sync_device_id`、`cached_area_pics`（缓存）；遗留键 `audioOnly`、`enableHighRefreshRate` | settings_upgrade_migration.dart:30-32,84-86；initial_services.dart:70；app_settings_controller.dart:56,78-106 | 只需读取，不必搬到新库 |
| IPTV（drift） | `IPTV_CACHE/pure_live_tv/pure_live_tv.db`，schemaVersion 9，共 13 张表：Providers（含 Xtream 账号密码，明文）、Channels、Epg×4、ChannelGroups、FavoriteLists/Channels、EpgReminders、ScheduledRecordings、FailoverGroups/Channels；另有 `playlists/` 目录、categories.json、hot.m3u | database.dart:25-105,631-647；tables.dart:6-184；playlist_storage.dart:10-24 | 原库原样沿用、继续编号升级，不要重建。_openConnection 里的“旧路径回退”与新路径相同，是无效代码 |
| SharedPreferences | 只有 easy_localization 保存的 `locale`，与 Hive 的 `language` 是两份；Windows 上重定向到 `AppData/PLUGIN_SUPPORT/shared_preferences.json` | windows_portable_path_provider.dart:56-80；app_path_manager.dart:315-322 | 两者冲突时需要定一个优先级 |
| WebView Cookie | flutter_inappwebview 自带的 Cookie 库（B 站网页登录） | web_login_controller.dart:176 | 不迁移 |
| 文件目录 | 根目录：`<应用文档目录>/PURE_LIVE`；Windows 为 `{exe}\AppData`（只读时回退），带 `--instance` 时再加子目录。子目录：HIVE_DB、IPTV_CACHE、DOWNLOADS（fonts/<id>、更新包；安卓默认下载目录/pure_live，可通过 `downloadDirectoryPath` 自定义）、RECORDS（或 `recordSavePath`）、LOGS（安卓在外部 Downloads 下）、CERTIFICATES、MIGRATION_BACKUP/settings-v4、`persistent_data_migration_v4.lock`、`previous_install_locations.txt`；可丢弃：IMAGE_CACHE、EMOJI_CACHE、图片缓存 `pureLiveImagesV2` | app_path_manager.dart:19-40,246-293,355-370；cache_controller.dart:44-54,108-135；log.dart:551-559 | 用户数据一律不删 |

备份格式：`backupVersion`=3，按分区组织，文件名 `purelive_<日期>.txt` / `purelive_favorites_<日期>_<uuid>.txt`。导入时兼容无版本号的扁平格式、v2、v3 和“仅关注”备份（backup_controller.dart:33,56-233；backup_recovery_service.dart:28,59）。

安卓旧路径：2026-05-13 之前的数据在 `<应用文档目录>/pure_live/app_settings.hive`（2a68e00d）。目前只有 Windows 会查找旧路径，安卓不查 [待确认：是否有正式版用过这个路径]。

## ④ 启动流程

| # | 步骤 | 位置 | 性质 | 能否延迟 |
|---|---|---|---|---|
| 1 | 错误钩子、ensureInitialized、图片解码缓存上限 | main.dart:29-33；initialized.dart:57-58 | 轻 | 否 |
| 2 | Windows 单实例检查 | initialized.dart:61,152-160 | 平台通道 | 否 |
| 3 | 路径初始化：path_provider 调用 3 次；Windows 每次启动都枚举注册表（2 个根 × 2 个视图）、扫描安装目录的上级目录和搬迁记录链；首次还会复制迁移备份、补齐 IPTV | app_path_manager.dart:47-93,108-171 | 同步 IO（Windows 较重） | 查找旧数据只需做一次（加完成标记） |
| 4 | EasyLocalization 初始化（读 SharedPreferences） | initialized.dart:64 | IO | 否 |
| 5 | 打开 Hive box，整个 box 载入内存 | initialized.dart:67-68 | IO + 解码 | v4 改用 drift |
| 6 | 设置升级检查：每次启动都把全部键转成 map、jsonEncode 比较两遍、解码关注和历史 | settings_upgrade_migration.dart:45-99 | CPU | 应只在未迁移时运行 |
| 7 | InitialServices：数据库对象（延迟打开）；注册 21 个延迟控制器；立即创建 IPTV、本地互动、路由控制器；读字体清单、检查字体文件；audioOnly 迁移；3 秒后按需恢复录制 | initial_services.dart:50-92 | 资产 IO | 字体只在选了自定义字体时才需要 |
| 8 | Windows 新窗口导入交接的设置文件 | initialized.dart:87-93 | IO | 否 |
| 9 | 配置代理路由和图片缓存；安卓预热 FFmpegKit（不等待） | initialized.dart:94-124 | — | v4 去掉 FFmpegKit，此步删除 |
| 10 | 桌面窗口（mica 效果）和托盘 | desktop_manager.dart:48-99 | 平台通道 | 托盘可延后 |
| 11 | 开机自启设置 → 创建 StartupController → 其 onInit 从上游仓库拉取 GitHub 上的 play_config.json（虎牙 UA） | initialized.dart:134-136；startup_controller.dart:36-50；huya_site.dart:361-367 | 网络 | 可延后或按需 |
| 12 | runApp；首帧后创建 FavoriteController，校验全部关注（网络）；启动分享接收；初始化全局播放器 | main.dart:57-92；favorite_controller.dart:121-125 | 网络 | 已在首帧后 |
| 13 | 启动页固定 1 秒，再最多等 350 ms 关注校验，然后跳首页 | app_pages.dart:189-235 | 固定延时 | 删除，改用原生启动页 |
| 14 | 首页首帧后处理命令行传入的房间；2 秒后检查更新；开启自动同步时 3 秒后同步 IPTV | home_page.dart:72-104；iptv_settings_controller.dart:31-39 | 网络 | 已延后 |

## ⑤ 路由、入口与设置

路由共 44 个常量、40 个已注册页面，另有 28 处用 Get.to 打开的无名页面。

| 分组 | 路由 · 参数 |
|---|---|
| 主框架 | `/splash`；`/home`（内含关注、热门、分区、录制四个标签，宽度 > 680 时隐藏录制标签） |
| 浏览 | `/favorite` `/favoriteAreas` `/popular` `/areas` `/area_rooms`（参数 `[Site, LiveArea]`）`/hot_areas` `/history` `/search` `/web_search`（参数 `{url, platform}`）`/iptv` |
| 播放 | `/live_play`（参数 LiveRoom + `?site=`，允许重复入栈）`/multiview` |
| 设置 | `/settings`（14 个 Get.to 子页）`/shield` `/settingTags` `/settings_account` `/tool_box` |
| 账号 | `/bilibili_qr_login` `/bilibili_web_login` `/huya_cookie` `/douyu_account_cookie` `/douyin_cookie` `/douyu_cookie`（历史别名，实际打开抖音页）`/kuaishou_cookie` `/twitch_cookie` `/yy_cookie` `/soop` |
| 备份同步 | `/backup` `/web_dav_page` `/remote_sync`；扫码页用 Get.to 打开 |
| Firebase | `/sign_in` `/mine` `/user_manage` |
| 关于、更新、录制 | `/about` `/version_page` `/version_history` `/record_mannager` `/record_settings` |
| 死常量 | `/donate` `/update_password` `/webview_all` `/record_history`（route_path.dart:50,62,78,109） |

| 入口 | 说明 · 位置 |
|---|---|
| 安卓分享（SEND） | 文本或文件，依次识别分享口令、直播链接、播放列表、EPG（main.dart:105-131） |
| 剪贴板口令 | 每次回到前台 1 秒后读剪贴板（desktop_manager.dart:611-625）。口令格式为 base64url(msgpack{m:'pure_live',p,r,ti,n,l,c,a})，v4 必须兼容（plugins/share_command_handler.dart:4-47） |
| 安卓 VIEW | `purelive://`、`mystyle://`、m3u 在 Manifest 里声明了（AndroidManifest.xml:66-76），但 Dart 侧没有处理代码 [待确认] |
| Windows 命令行 | `--instance=`、`--open-room=`（base64url 编码的 JSON）、`--config-file=`（windows_multi_instance_launcher.dart:19-66）；`purelive://` 协议只用于 Firebase 回调 |
| 局域网 / 电视 | 二维码 `purelive://ip:port/sync?code=`（remote_sync_protocol.dart:39）；旧电视接口 `/api/setSettings?settings=<JSON>`（backup_recovery_service.dart:119-127） |
| 应用内更新 | 首页自动检查、关于页、更新弹窗；version.json 从 raw GitHub 或 14 个第三方镜像获取（version_util.dart:33-39）；未见安装包哈希校验 [待确认] |

设置项约 230 个键：Rx 绑定的 203 个，另有约 25 个直接读写。

| 类别 | 键数 | 代表项 = 默认值 |
|---|---|---|
| 弹幕 | 40 | danmakuSpeed=120、FontSize=16、Area=1.0、Fps=60（自动）；画中画弹幕 15 项（字号 12、速度 90、最多 6 条）；相似度过滤 关（85 / 3 / 100） |
| 本地互动 | 29 | localInteraction.enabled=true，coins=1000 |
| 播放 | 24+4 | videoPlayerKey=平台默认；preferResolution='原画'；enableCodec=true；floatPlay=false；竖屏相关 10 项；音量 手机 0.5 / 桌面 1.0 |
| 应用 | 18 | showSplashPage=true、enableAutoCheckUpdate=true、enableScreenKeepOn=true、refreshRateMode（新装为省电）、savedMenuIds=4 个标签 |
| 外观 | 8+9+4+5 | themeMode='System'、themeColor=蓝、language='简体中文'、间距 6、字体 'Default'、卡片预设 standard |
| 账号 / 平台 | 12+7 | 8 个 Cookie；hotAreasList=全部平台；preferPlatform=bilibili |
| 录制 | 21 | 分段时长、并发数、重试、轮询、保存路径 |
| 行为 | 1+4+6+8 | enableStartUp=**true**（Windows 首次启动就注册开机自启 [待确认是否有意]）、exitChoose='exit'、autoShutDownTime=120、自动刷新 关（间隔 30、并发 4）、窗口 1280×720 |
| 网络 / IPTV / 数据 | 6+6+4 | 代理端口 7897；IPTV 自动同步 关（24 小时）；historyLimit=50 |

## ⑥ Firebase

| 用途 | 实现与位置 | v4 替代 |
|---|---|---|
| 初始化 | 打开备份页时才懒初始化，先探测 firebase.google.com 是否可达（backup_page.dart:82；auth_controller.dart:11-26,90-129） | 删除 |
| 账号 | 邮箱注册/登录/找回密码；GitHub 登录，Windows 经托管中转页后让用户手动粘贴 `purelive://auth?credential=`（firebase_email_auth.dart:15-47,302-345） | 不再需要账号 |
| 云端备份 | `users/{uid}.config` = exportAllSettings（不含 Cookie），事务写入（firebase_manager.dart:215-264） | WebDAV（全量或仅关注，已实现） |
| 登录自动恢复 | 本地关注为空时自动下载并恢复（auth_controller.dart:32-45；firebase_manager.dart:266-318） | 首次启动向导：从文件、WebDAV 或局域网导入 |
| 权限与用户目录 | `permissions`、`roles`、`users` 集合；管理员可提权、禁止上传、删除用户、预览他人配置（firebase_manager.dart:138-193,321-345；user_server_remote_controller.dart:28-177） | 直接删除 |
| 远程配置 | 不用 Firebase Remote Config；远程数据实际来自 GitHub 镜像：虎牙 UA（上游 liuchuancong 仓库）、version.json、字体 | 迁到自有仓库，并加签名或哈希校验 |
| 构建产物 | 3 个 pubspec 依赖、google-services 插件与 json、plist、firebase.json、firebase_options.dart、4 个测试、firebase_* 翻译键 | 全部删除 |

注意：只存在 Firestore 上的用户配置，v4 无法读取。需要在旧版 3.3.x 里提示用户导出。

## ⑦ 技术债（8 条）

| # | 问题 | 位置 |
|---|---|---|
| 1 | 所有数据挤在一个 Hive box：关注和历史每改一次就整串 JSON 重写；Cookie、WebDAV 密码、Xtream 密码都是明文 | favorite_room_controller.dart:428-444；cookie_settings_controller.dart:10-35；tables.dart:11-12 |
| 2 | 约 230 个无类型字符串键，每键一个 `ever` 写回，写入不等待结果、错误被吞；键名风格混杂；部分值存的是显示文案 | hive_rx.dart:72-114；player_settings_controller.dart:36 |
| 3 | 房间身份有 4 种格式并存，外加一份冗余的 `tagIds` | live_room.dart:527；live_room_volume_manager.dart:9；tag_management_controller.dart:121；live_area.dart:34-40 |
| 4 | 全局定位器 515 处；设置控制器的构造期带网络副作用 | startup_controller.dart:36-50 |
| 5 | 启动全程串行：迁移检查每次全量运行，Windows 每次扫注册表，根 Obx 包住整个 app，默认 1 秒启动页 | settings_upgrade_migration.dart:45,88；app_path_manager.dart:73-83；main.dart:137；app_pages.dart:233 |
| 6 | 路由用对象参数，无法深链；播放器生命周期挂在路由名观察者上；有死路由常量和未处理的 VIEW 过滤器 | app_pages.dart:92；app_navigation.dart:66；navigation_observer.dart:14-60 |
| 7 | 备份不含录制设置/任务、本地互动和 IPTV；旧电视接口把设置放在 URL 里；局域网同步走明文 HTTP，勾选后可带 Cookie；更新文件无哈希校验 [待确认] | backup_controller.dart:114-140；remote_sync_service.dart:546 |
| 8 | 测试与 GetX/Hive 深度耦合（902 次注入调用，123 个文件操作 Hive） | test/ |

## ⑧ 必须继承的行为与坑

| 现象 | 根因 | 正确做法 | 提交 / 测试 |
|---|---|---|---|
| 升级后首次启动界面异常，第二次启动才正常 | 设置注册未等待完成，界面先于设置服务构建 | 存储与设置就绪是 runApp 前的硬依赖 | initialized.dart:81-86；842fe3a3 |
| 冷启动迁移时首帧卡住 | 在 SettingsService.onInit 里注册 IPTV 控制器，依赖注入重入 | 显式注册顺序，构造期不做副作用 | initial_services.dart:22-27；c5072259；settings_service_lifecycle_test.dart:35 |
| 直接复制旧 Hive 文件后关注显示为空 | 集合格式变过：旧 `List<String>` 与新 `{"list":[...]}` | 两种格式都识别；按平台 + 房间号取并集；空字段互补、tagIds 取并集 | settings_upgrade_migration.dart:22-28,158-210；6d086e2f；settings_upgrade_migration_test.dart:17,49 |
| Windows 换盘重装后数据“丢失” | 数据在安装目录下，注册表只记最新位置 | 注册表、同级目录、搬迁记录链一起查；先备份；指纹账本防重复导入；被锁的文件下次重试；源目录只读不改 | app_path_manager.dart:108-293；settings_upgrade_migration_test.dart:94 |
| 关注里有打不开或重复的房间 | 房间号为 0、null、undefined、nan、none，或平台大小写不一致 | 读入、导入、写入三处统一校验并去重；平台转小写，房间号保留大小写 | favorite_room_controller.dart:162-214；c22ae2f4；favorite_room_validity_test.dart:7；favorite_area_identity_test.dart:84 |
| 标签串到别的房间或丢失 | 旧映射只用房间号作键 | 迁到“平台:房间号”，以映射表为准 | tag_management_controller.dart:78-105；4d8ed292；room_card_tag_assignment_test.dart:46-83 |
| 启动时已下播的房间显示“直播中”，卡片跳动 | 持久化了上次的直播状态；多次刷新互相取消 | 启动时状态一律显示未知；校验结果一次性发布；刷新串行执行 | favorite_controller.dart:652-706；d6c3d8df；favorite_startup_policy_test.dart:18,113 |
| 快速修改或退出后关注丢失 | 写入不等待完成 | 等待写入并 flush，失败回滚；退出前 flush（2 秒超时） | favorite_room_controller.dart:404-436；plugins/utils.dart:20；69e5b80b |
| 恢复失败后设置半新半旧 | 各控制器逐个写入 | 先整体校验，再批量写入；失败按快照回滚；禁止并发恢复 | backup_controller.dart:435-455；backup_roundtrip_test.dart:128-255 |
| 新平台老用户看不到；已退役平台又出现 | 平台列表按用户自定义顺序保存 | 版本表每版只追加一个平台；退役平台保留槽位；其关注和历史仍可读 | favorite_room_controller.dart:58-120；1495f56b；18 个 *_catalog_migration_test |
| 深色模式下“新窗口”打开后是空配置 | 每个窗口实例使用独立数据目录 | 用临时文件交接设置，只接受启动器自己写入的路径，导入后删除 | windows_multi_instance_launcher.dart:47-66；ef5f05c0；windows_multi_instance_launcher_test.dart:51 |
| 旧键导致新行为错误 | 全局 audioOnly、布尔型高刷开关已废弃 | 一次性迁移：true 映射为 balanced；老用户缺键时，多画面和新窗口开关默认 true | initial_services.dart:67-75；app_settings_controller.dart:25-40,57-61,106-112 |
| 备份或同步泄露 Cookie | — | 默认不含敏感数据；局域网需要配对码并在本机确认；不开 CORS | backup_controller.dart:56-110；backup_privacy_test.dart:5；remote_sync_test.dart:64-95 |
| 冷启动时分享的链接无效；安卓停在原生启动页 | 导航器尚未挂载；字体初始化时访问了 Get.context | 等导航器就绪再打开；首帧前不碰上下文 | 1836953e；font_settings_controller.dart:143-151 |
| 虎牙旧记录人数含义错；清空历史时误删新记录 | 旧版字段混用；按身份清空 | 读取时转换为人气；只删除快照中的对象 | live_room.dart:394-405；db3ef116；history_metadata_test.dart:31 |

## ⑨ 建议

| live_store 建议 | 说明 |
|---|---|
| 分层 | `legacy/`（只读导入：Hive v3、备份 v1–v3、IPTV 库）→ `migration/`（有序步骤 + 报告）→ `db/` → `settings/` → `secrets/` → `backup/` |
| 读取旧 Hive | 以 hive_ce 作为仅迁移用的依赖，在后台 isolate 打开文件副本；源文件永不修改；结果写入 drift 的 `meta` 表（导入版本、指纹）；失败可重试。备份目录改名为 `app-v4-<时间戳>`，避开已有的 `settings-v4` 和 `*_v4.lock` |
| 预览包限制 | 安卓 `.next` 包名读不到旧沙盒，只能通过文件、WebDAV 或局域网导入；自动迁移只在 v4.0.0 同包名覆盖安装时生效。换签名密钥后若需重装（Android 8），数据会一起丢失，所以 3.3.x 必须先加“导出 v4 备份”（也用于 Firebase 用户导出） |
| 表结构 | `rooms(平台, 房间号 区分大小写, 唯一)`、follows、follow_areas、tags/room_tags、history、block_rules、room_prefs、record_tasks/files、webdav_profiles、settings；IPTV 保留原库 |
| 未支持的平台 | 关注和历史原样保留，标记为“未支持”，并随备份导出。首批只做 5 个平台，不能成为删数据的理由 |
| 规范化 | 显示文案转枚举；语言转 locale 代码并与 `locale` 取一致；播放器 ijk/exo 转 mpv；房间级键统一成 RoomRef |
| 设置注册表 | `SettingKey<T>(id, 默认值, 编解码, 旧键, scope)`；备份范围、重置、导入都从注册表派生 |
| 备份 v4 | `{format, version:4, sections, secrets?}`；兼容旧版全部格式；先校验再一次事务写入；Cookie 只在用户设了口令时加密导出 |

应用骨架：
- runApp 前只打开 drift（后台 isolate）并读主题、语言等少量键；只有需要迁移时才显示迁移页。
- 其余全部用懒 provider：关注校验、更新检查、托盘、虎牙 UA 都放到首帧之后。
- go_router 使用类型化路由，例如 `/room/:platform/:roomId`。分享口令、分享链接、`--open-room` 和 `purelive://` 统一经 redirect 处理。
- 播放会话由 provider 管理，不再依赖路由名观察者。
- 根组件只 `select` 主题、字号和语言，避免整棵树重建。
- 读剪贴板改为可关闭。
