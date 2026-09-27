# 存储与迁移（store）模块规格

第 1 阶段草案。只写行为和外部契约，不规定类名和函数拆分。对应包 `live_store`，方案依据 ADR 0004。

- 证据写法：`文件:行号` 相对仓库根目录，基于 master 检出 c28c17fb。提交哈希转引自 docs/rewrite/diagnosis/05-app-shell-data.md 和所注文档，编写时没有运行 git 复核。
- 标记：**[待确认]** 需要查证；**[决定]** 是本规格新定的 v4 行为（旧版没有，或有意改掉旧行为）。有长期影响的 [决定] 在第 3 阶段补 ADR。
- 录制任务和文件的行为见 `spec/modules/record.md`；本规格只定义它们的存储形态和迁移。

---

## 0. 原则

1. 用户数据一律不删、不改：旧文件只读，导入时读副本（ADR 0004 §5）。
2. 迁移可重试、可重复：同一来源导入两次，结果与导入一次相同。
3. 密钥（Cookie、密码）不以明文进入数据库、备份、日志和临时文件（宪法原则 8）。
4. 启动时只有需要迁移才做迁移；不需要时的检查只做少量文件状态查询。

## 1. 旧数据完整清单

### 1.1 数据根目录

| 平台 | 根目录 | 证据 |
|---|---|---|
| Android / iOS / macOS / Linux | `<应用文档目录>/PURE_LIVE` | app_path_manager.dart:20, 63-65 |
| Windows EXE / 便携版 | `{exe 所在目录}\AppData`；不可写时回退 `<应用支持目录>\PURE_LIVE` | :95-106；docs/WINDOWS_DATA_AND_UPGRADE.md:5-25 |
| Windows MSIX | 同上选择规则，但不替换系统 path provider | :85-91, 383-392 |
| Windows 多实例 | `<根>\<实例 id>`；新窗口的 id 为 `window_<pid>_<微秒>`，每开一个新窗口多一个目录 | :67-69；windows_multi_instance_launcher.dart:19-44, 140-157 |
| Android 旧路径 | 2026-05-13 之前 `<应用文档目录>/pure_live/app_settings.hive`（2a68e00d）。现行代码只在 Windows 查找旧路径。**[待确认]** 是否有正式版在 Android 用过 | 诊断 05 ③ |

### 1.2 根目录下的文件和目录

| 路径 | 内容 | v4 处理 | 证据 |
|---|---|---|---|
| `HIVE_DB/app_settings.hive`（+ `.lock`） | 唯一的 Hive box，见 §1.3–1.6 | 只读导入，保留原文件 | hive_pref_util.dart:40-46；initialized.dart:65-68 |
| `IPTV_CACHE/pure_live_tv/pure_live_tv.db` | IPTV drift 库，见 §1.7 | 只读导入到主库，不升级（iptv.md §9） | database.dart:631-647 |
| `IPTV_CACHE/pure_live_tv/playlists/` | 用户导入的播放列表文件（`<毫秒>_<uuid><扩展名>`） | 原样沿用 | playlist_storage.dart:9-26 |
| `IPTV_CACHE/categories.json`、`hot.m3u` | IPTV 分类、热门列表缓存 | 沿用，可重新下载 | app_path_manager.dart:38-40 |
| `DOWNLOADS/` | 下载的字体 `fonts/<id>/`、更新包；可由 `downloadDirectoryPath` 改到别处；Android 默认为系统下载目录下 | 原样保留，路径设置迁移 | :23, 374-381；cache_controller.dart:104-135 |
| `RECORDS/` 或 `<recordSavePath>/PureLiveRecords/` | 录制文件 | 见 record.md §14.3、§15 | cache_service.dart:13-39 |
| `LOGS/log/`（Android 在外部下载目录的 `LOGS/log/`） | 日志 | 不迁移 | log.dart:551-559 |
| `CERTIFICATES/` | FFmpeg TLS 信任库 | 不迁移，v4 不再需要 | ffmpeg_tls_trust_store.dart:48 |
| `MIGRATION_BACKUP/settings-v4/` | 旧版升级前备份：`settings_before_upgrade_N.hive` + `backup_manifest.json` | 保留；v4 用 `app-v4-<时间戳>` 避开 | app_path_manager.dart:246-270 |
| `MIGRATION_BACKUP/working/` | 旧版迁移临时副本 `settings_upgrade_source_N.hive` | 忽略 | :370；settings_upgrade_migration.dart:57-73 |
| `persistent_data_migration_v4.lock` | 旧版“IPTV 数据已从旧位置补齐”标记 | 读取，不修改 | app_path_manager.dart:272-293 |
| `previous_install_locations.txt` | Windows 搬迁账本，§1.9 | 读取 | :144-171；local_release.iss:131-135 |
| `PLUGIN_SUPPORT/shared_preferences.json` | Windows 便携版 SharedPreferences，§1.8 | 读取 | windows_portable_path_provider.dart:56-84 |
| `CACHE/`、`TEMP/`、`IMAGE_CACHE/`、`EMOJI_CACHE/`、图片缓存库 `pureLiveImagesV2` | 可丢弃的缓存 | 不迁移，不删除 | docs/WINDOWS_DATA_AND_UPGRADE.md:9-23；cache_manager.dart:7 |
| WebView 自带 Cookie 库 | B 站网页登录 | 不迁移（登录后已写入 `bilibiliCookie`） | web_login_controller.dart:176 |

### 1.3 Hive：数据集合键

Hive 中没有自定义 TypeAdapter，值只有 String、int、double、bool、List、Map（诊断 05 ③）。

| 键 | Hive 类型与格式 | 历史格式 | v4 去向 | 证据 |
|---|---|---|---|---|
| favoriteRooms | String：`{"list":[LiveRoom…]}` | ≤2.0：`List<String>`，每项一个 LiveRoom JSON | rooms + follows | favorite_room_controller.dart:26-35；settings_upgrade_migration.dart:22-28, 185-210 |
| favoriteAreas | String：`{"list":[LiveArea…]}` | 同上 | follow_areas | favorite_room_controller.dart:37-46；live_area.dart:14-50 |
| historyRooms | String：`{"list":[LiveRoom…]}`，每项带 `lastWatchedAt`（毫秒） | 同上；旧记录没有 lastWatchedAt | rooms + history | history_controller.dart:57-66 |
| historyLimit | int，默认 50，0 = 不限 | — | 设置 `history.limit` | history_controller.dart:8-15, 68 |
| user_custom_tags_v5 | List<Map>：`{id, name, description, order}` | 没找到 v1–v4 的读取代码 | tags | tag_management_controller.dart:9, 25-35 |
| room_to_tags_mapping_v1 | Map<String, List<String>>：键为 `平台:房间号`，旧键为纯房间号 | 纯房间号键 | room_tags | :10, 78-121 |
| shieldList | List<String> | — | block_rules（keyword） | favorite_room_controller.dart:16, 627-635 |
| blockedDanmakuUsers | List<String> | — | block_rules（user） | :18 |
| hotAreasList | List<String>：可见平台及顺序 | 可能含大写、空白、未知 id | 设置 `catalog.platforms` | :20, 122-142 |
| siteCatalogMigration | int，当前 38 | — | 用于 §6.4.8，不保存 | :22, 58-120 |
| preferPlatform | String 平台 id，默认 bilibili | 可能含大写 | 设置 `catalog.preferred` | :24, 139-148 |
| roomVolumes | String：JSON Map `{"room_vol_<平台>_<房间号>": 0..1}` | — | room_prefs（volume） | volume_settings_controller.dart:11；live_room_volume_manager.dart:8-33 |
| portraitRoomOverrides | String：JSON Map `{"<平台>:<房间号>": "<竖屏布局名>"}`，最多 300 条 | — | room_prefs（portraitLayout） | player_settings_controller.dart:71, 173-194 |
| webDavConfigs | String：`{"list":[{name, address, username, password}]}`，密码明文 | 可能是 List | webdav_profiles + 密钥库 | common/services/settings/web_dav_controller.dart:17-26；webdav_config.dart:1-45 |
| currentWebDavConfig | String：当前选中配置的完整 JSON，**含第二份明文密码** | — | webdav_profiles 的“当前”标记（按 name 匹配，忽略其中密码） | common/services/settings/web_dav_controller.dart:15, 59-65 |
| recorder_tasks | String：JSON List，任务 schemaVersion 1–9 | v1/v2 含签名 `currentUrl` | record_tasks（丢弃 URL） | recorder_controller.dart:75-77, 1470-1513；live_record_task.dart:324-471 |
| record_history | List<Map>（RecordFileItem） | 没有写入者，死数据 | 文件仍存在的登记到 record_files，否则丢弃 | recorder_config.dart:224-240；record_file_item.dart |
| localInteraction.history | List<String> | — | 设置 `localInteraction.history` | local_interaction_controller.dart:96 |

**LiveRoom 字段**（live_room.dart:357-405, 559-596）：roomId、userId、title、nick、avatar、cover、area、watching、audienceMetricType（名字）、popularity、onlineViewers、totalViewers、followers、platform、tagIds、liveStatus（下标：0 直播中 / 1 未开播 / 2 回放 / 3 未知 / 4 封禁，live_room.dart:4）、isRecord、status（旧布尔，`liveStatus` 缺失时才用）、notice、introduction、IPTV 专用（epgId、currentProgramme、currentProgrammeDescription、catchUpUrl、isCatchUp、catchUpStart、catchUpEnd、catchUpMode、catchUpSource、catchUpDays、catchUpCorrectionHours、httpHeaders）、lastWatchedAt。`link`、`data`、`danmakuData` 不持久化。

**LiveArea 字段**（live_area.dart:3-50）：platform、areaType、typeName、areaId、areaName、areaPic、shortName。身份是 JSON 三元组 `[平台小写, 命名空间, areaId]`，命名空间只有猫耳（missevan）取 areaType，其它为空。

### 1.4 Hive：账号与密钥键

| 键 | 类型 | 默认 | v4 去向 | 证据 |
|---|---|---|---|---|
| bilibiliCookie | String | '' | 密钥 `cookie/bilibili` | cookie_settings_controller.dart:10 |
| bilibiliUid | int | 0 | 设置 `account.bilibili.uid`（不是密钥） | :11 |
| huyaCookie | String | '' | 密钥 `cookie/huya` | :12 |
| douyuCookie | String | '' | 密钥 `cookie/douyu` | :13 |
| douyuCookieSavedAt | int（Unix 秒，0 = 未知） | 0 | 设置 `account.douyu.cookieSavedAt` | :15-22 |
| douyuLtp0 | String | '' | 密钥 `cookie/douyu.ltp0` | :24-29 |
| douyuDid | String | '' | 密钥 `cookie/douyu.did` | :30 |
| douyinCookie、kuaishouCookie、twitchCookie、soopCookie、yyCookie | String | '' | 密钥 `cookie/<平台>` | :31-35 |
| taobaoCookie | String | — | 丢弃（旧版启动时删除） | :41-42 |

导入前按旧规则规范化 Cookie 文本（cookie_settings_controller.dart:45-59；cookie_value.dart）。

### 1.5 Hive：设置键

v4 设置 id 的默认规则：`<分组>.<旧键>`，旧键里的 `_` 改为驼峰；下表只写例外。类型是 Hive 中存的类型。

**应用（app，app_settings_controller.dart:42-69）**

| 键 | 类型 | 默认 | v4 |
|---|---|---|---|
| autoRefreshTime | int | 3 | 丢弃（设置页之外没有使用者） |
| enableDenseFavorites | bool | true | app.denseFavorites |
| enableBackgroundPlay | bool | false | |
| enableAsmrSleepMode / asmrSleepMinutes | bool / int | false / 60 | |
| enableRotateScreen | bool | false | |
| enableScreenKeepOn | bool | true | |
| enableAutoCheckUpdate | bool | true | |
| useGitHubOriginForUpdates | bool | false | |
| enableFullScreenDefault | bool | false | |
| showSplashPage | bool | true | 丢弃（v4 用原生启动页，诊断 05 ④-13） |
| refreshRateMode | String：`powerSaving` / `balanced` / … | 新装 powerSaving | 枚举；缺失时由旧键 enableHighRefreshRate 推出（§6.4.3） |
| preferRealOnlineCounts | bool | false | |
| realOnlinePlatforms | List<String> | douyin、kuaishou、cc、twitch… | 平台 id 列表（§6.4.8） |
| audienceMetricMigration | int，当前 7 | 0 | 只用于 §6.4.8 |
| enableMultiView / enableNewWindowPlay | bool | 缺键时 true | |
| savedMenuIds | List<String> | favorites、popular、areas、record | 规范化为已知菜单 id（app_settings_controller.dart:73-74） |

**主题与字体（theme_settings_controller.dart:8-24；font_settings_controller.dart:15-47）**

| 键 | 类型 | 默认 | v4 |
|---|---|---|---|
| themeMode | String 显示名：`System` / `Dark` / `Light` | System | theme.mode 枚举 system / dark / light |
| enableDynamicTheme | bool | false | |
| themeColorSwitch | String 十六进制色 | 蓝色 | 规范化（:97） |
| language | String 显示名：`简体中文` / `English` | 简体中文 | theme.locale（§6.4.2） |
| crossAxisSpacing / mainAxisSpacing | double | 6 / 6 | |
| loadingStyle / loadingStyleColorSwitch | String | `default` / '' | 未知样式回退 default（:99-107） |
| textScaleFactor | double | 1.0 | |
| fontSizeBodySmall / fontSizeBodyMedium / fontSizeBodyLarge / fontSizeTitleMedium / fontSizeTitleLarge | double | 12 / 13 / 14 / 15 / 20 | |
| fontFamilyName / fontFamilyFileName | String | Default / '' | 本机（字体文件在本机） |
| danmakuFontFamilyFileName | String | '' | 本机 |

**播放（player_settings_controller.dart:33-71）**

| 键 | 类型 | 默认 | v4 |
|---|---|---|---|
| videoFitIndex | int：下标 → contain、cover、fill、fitHeight、fitWidth、scaleDown | 0 | player.fit 枚举（app_consts.dart:39-48） |
| videoPlayerKey | String：mpv / ijk / exo / fvp | iOS 为 ijk，其它 mpv | 丢弃，全平台 mpv（§6.4.4） |
| preferResolution / preferResolutionCellular | String 显示名：原画 / 蓝光8M / 蓝光4M / 超清 / 流畅 | 原画 | 画质枚举（§6.4.1） |
| enableCodec | bool | true | player.hardwareDecoding |
| playerCompatMode、customPlayerOutput | bool | false | 本机 |
| videoOutputDriver / audioOutputDriver / videoHardwareDecoder | String | gpu / auto / auto | 本机 |
| floatPlay、windowsPipAlwaysOnTop、enableRtxVsr、useHardStopOnExit | bool | false | 本机 |
| enablePortraitStreamAdaptation、portraitAdaptiveHeight、portraitPipFollowSource、rememberPortraitRoomOverride | bool | true | |
| portraitLayoutMode / portraitFullscreenPolicy / portraitFullscreenDisplayMode / portraitDanmakuMode | String 枚举名 | balanced / followSource / ambient / followGlobal | 枚举 |
| showPortraitDiagnostics | bool | false | |

**音量（volume_settings_controller.dart:8-11）**：defaultMobileVolume double 0.5、defaultDesktopVolume double 1.0、globalVolumeMute bool false；roomVolumes 见 §1.3。

**弹幕（danmaku_settings_controller.dart:7-39, 58-111），共 40 个**

| 键 | 类型 | 默认 |
|---|---|---|
| hideDanmaku、noEmojiMode、collapseRepeatedDanmaku、filterDouyuSuspectedAutomatedMessages、enableDanmakuSimilarityFilter | bool | false |
| enableDanmakuDisplay、enableDanmakuStroke、enableDanmakuTapInteraction、enableDanmakuLongPressInteraction、danmakuAutoFps | bool | true |
| danmakuTopArea / danmakuArea / danmakuBottomArea | double | 0.0 / 1.0 / 0.5 |
| danmakuSpeed / danmakuFontSize / danmakuFontBorder / danmakuOpacity | double | 120 / 16 / 1.5 / 1.0 |
| danmakuFontWeight / danmakuFps | int | 500 / 60 |
| repeatedDanmakuWindowSeconds | int | 5 |
| danmakuSimilarityThreshold / danmakuSimilarityCacheDuration / danmakuSimilarityMaxCacheSize | int | 85 / 3 / 100（后两个夹在 1–60、20–1000：:126-127） |
| danmakuInteractionMigration | int，当前 1 | 只用于 §6.4.8 |
| savedDanmakuTemplate | String | '' |
| danmakuFontFamilyName | String | Default |
| enablePipDanmaku、pipDanmakuAutoScale、pipDanmakuUseOriginalColor、pipDanmakuAutoFps | bool | true |
| pipDanmaNoEmojiMode（键名拼写如此，备份里叫 pipDanmakuNoEmojiMode） | bool | false |
| pipDanmakuColor / pipDanmakuFontWeight / pipDanmakuMaxVisibleCount / pipDanmakuFps | int | 0xFFFFFFFF / 500 / 6 / 30 |
| pipDanmakuFontSize / pipDanmakuSpeed / pipDanmakuOpacity / pipDanmakuArea / pipDanmakuEmitInterval | double | 12 / 90 / 0.9 / 0.5 / 0.35 |

**卡片、分页、刷新（room_card_settings_controller.dart:13-21, 251-265；page_settings_controller.dart:14-19；refresh_config_controller.dart:6-30）**

| 键 | 类型 | 默认 | v4 |
|---|---|---|---|
| room_card_mobile_preset / room_card_desktop_preset | String：compact / normal / rich / custom | normal | roomCard.mobilePreset / desktopPreset 枚举 |
| room_card_mobile_config / room_card_desktop_config | String JSON（卡片外观） | 按预设 | 原样 JSON，经外观解析校验 |
| page_show_size_selector / page_show_goto_button / page_show_scroll_top | bool | true | page.* |
| page_default_size | int | 按屏幕宽度计算 | page.defaultSize（设备相关默认） |
| page_size_options_raw | String | '' | page.sizeOptions |
| autoRefreshFavorite / autoRefreshThumbnails | bool | false | refresh.autoRefreshFavorite / refresh.autoRefreshThumbnails（封面定时刷新，F-FAV-04） |
| refreshFavoriteOnResume | bool | true | refresh.refreshFavoriteOnResume |
| autoRefreshInterval / thumbnailRefreshInterval / maxConcurrentRefresh | int | 30 / 30 / 4 | refresh.autoRefreshInterval / refresh.thumbnailRefreshInterval（两个间隔都夹紧到 5–360 分钟，同旧版 `normalizeRefreshInterval`）/ refresh.maxConcurrentRefresh（1–16） |

**网络、窗口、退出、启动（proxy_settings_controller.dart:9-18；window_size_controller.dart:8-107；exit_settings_controller.dart:10-26；startup_controller.dart:25）**

| 键 | 类型 | 默认 | v4 |
|---|---|---|---|
| enableProxy / proxyHost / proxyPort | bool / String / int | false / '' / 7897 | 本机 |
| enableAppProxy / appProxyHost / appProxyPort | bool / String / int | false / '' / 7897 | 本机 |
| windows_pip_display_id / windows_pip_width / windows_pip_height / windows_pip_x / windows_pip_y | String / double | '' / 0 | 本机 |
| window_width / window_height | double | 1280 / 720 | 本机 |
| rememberPipPosition | bool | true | 本机（旧备份里曾在 player 分区：backup_controller.dart:271-273） |
| dontAskExit / exitChoose / autoShutDownTime / enableAutoShutDownTime | bool / String（exit、minimize）/ int / bool | false / exit / 120 / false | 本机 |
| enableStartUp | bool | **true** | 本机。**[待确认]** 默认 true 会让 Windows 首次启动就注册开机自启，是否有意 |

**IPTV 设置（iptv_settings_controller.dart:7-27）**：selectedSourceName String ''、selectedSourceId String ''、isAutoSyncEnabled bool false、autoSyncHoursInterval int 24、customIptvUserAgent String ''、m3uDirectory String（默认值就是字符串 `m3uDirectory`，本机）。

**备份、下载（backup_controller.dart:37；cache_controller.dart:108-112）**：backupDirectory String ''、downloadDirectoryPath String ''、downloadDirectoryDecisionMade bool false，均为本机。

**本地互动（local_interaction_controller.dart:86-114），共 29 个，全部本机**：`localInteraction.` 前缀的 enabled（true）、userName（Pure Live）、title（listener）、showAsDanmaku / showPlatformBadge / showLevelBadge / enableGiftEffects（true）、previewPlatform（bilibili）、coins（1000）、experience（0）、history（List<String>）、danmakuPreset（clean）、danmakuColor（0xFFFFFFFF）、danmakuFontSize（19.0）、danmakuSpeed（130.0）、danmakuFontWeight（600）、danmakuShowStroke（true）、danmakuStrokeWidth（1.5）、danmakuPlacement（scroll）、danmakuFontFamily（system）、danmakuItalic（false）、danmakuOpacity（1.0）、danmakuLetterSpacing（0.0）、danmakuStrokeColor（0xFF000000）、danmakuShowShadow（false）、danmakuShadowColor（0xFF000000）、danmakuShadowBlur（2.0）、danmakuShadowOffset（1.0）、danmakuFixedDurationMs（4000）。

**录制（recorder_keys.dart:1-61；recorder_config.dart:12-69）**：19 个设置键的去向见 record.md §20；另有 §1.3 的 recorder_tasks、record_history。

### 1.6 Hive：内部、迁移、缓存、遗留键

| 键 | 类型 | 含义 | v4 处理 | 证据 |
|---|---|---|---|---|
| settingsUpgradeSchema | int，当前 4 | 旧版迁移版本 | 只读 | settings_upgrade_migration.dart:30-31 |
| settingsUpgradeImportedSources | String：JSON 数组，每项 `绝对路径\|字节数\|修改时间毫秒` | 旧版指纹账本 | 并入 v4 账本（§6.3） | :32, 83-85, 246-258 |
| legacy_settings_migrated_to_v2 | bool | 旧标记 | 忽略 | :86 |
| migration.room_scoped_audio_only.v231 | bool | audioOnly 已清除 | 只用于 §6.4.3 | initial_services.dart:67-75 |
| remote_sync_device_id | String：`<系统>-<微秒>` | 局域网设备 id | meta `device.lanId`，保持不变 | remote_sync_service.dart:134-143 |
| cached_area_pics | String | 分区图片缓存 | 丢弃 | area_pic_mapper.dart:42 |
| audioOnly | bool | 已废弃的全局纯音频 | 丢弃 | initial_services.dart:72 |
| enableHighRefreshRate | bool | 已废弃的高刷开关 | 只用于推出 refreshRateMode | app_settings_controller.dart:25-40 |
| settings_upgrade_source_N | 临时 box | 旧迁移用完即删 | 忽略 | settings_upgrade_migration.dart:57-73 |

### 1.7 IPTV drift 库

- 路径 `IPTV_CACHE/pure_live_tv/pure_live_tv.db`，schemaVersion 9，每次升级在事务里执行并写 `PRAGMA user_version`；**遇到更高版本直接抛错**（database.dart:47-109）。
- 13 张表（tables.dart:6-184）：Providers（type 为 m3u / xtream；url、username、**password 明文**）、Channels（含 catchup 字段和 httpHeadersJson）、EpgSources、EpgChannels、EpgProgrammes、EpgMappings、ChannelGroups、FavoriteLists、FavoriteListChannels、EpgReminders、FailoverGroups、FailoverGroupChannels、ScheduledRecordings。
- 升级历史：v2 收藏列表；v3 提醒和定时录制；v4 节目副标题、集数；v5 备用组；v6 自动更新开关；v7 EPG 频道身份迁移；v8 回看字段；v9 频道请求头（database.dart:57-104）。
- `_openConnection` 里的“旧路径回退”与新路径相同，是无效代码（database.dart:631-647）。

### 1.8 SharedPreferences

- 只有 easy_localization 保存的 `locale`（值如 `zh`、`en`），与 Hive 的 `language` 是两份（main.dart:36-41；theme_settings_controller.dart:159-164）。
- Windows 便携版和 EXE 版重定向到 `<根>\PLUGIN_SUPPORT\shared_preferences.json`；更早的版本在系统应用支持目录，旧版启动时复制过来（windows_portable_path_provider.dart:56-84；app_path_manager.dart:315-322）。

### 1.9 Windows 旧数据来源与搬迁账本

旧版每次启动都会查找以下位置（app_path_manager.dart:108-171, 218-233）：

1. `<文档>\PURE_LIVE`、`<文档>\pure_live`、应用支持目录、缓存目录、`<应用支持目录>\PURE_LIVE` 和 `pure_live`。
2. 安装目录的上级目录中，名字去掉 `_`、空格、`-` 后等于 `purelive` 的兄弟目录下的 `AppData`。
3. 注册表 HKCU 和 HKLM 两个根 × 普通和 WOW6432Node 两个视图的 Uninstall 项里，DisplayName 匹配 `纯粹直播|pure[ _-]?live` 的 InstallLocation（没有则从 UninstallString 推出）下的 `AppData`。
4. 以上每个位置的 `previous_install_locations.txt`（每行一个旧安装目录的绝对路径），沿账本链继续查，最多检查 32 个位置。账本由安装器在用户选择新目录时写入（local_release.iss:131-135）。
5. 每个位置检查 `app_settings.hive` 和 `HIVE_DB\app_settings.hive`；与当前文件相同的跳过；按不区分大小写的路径去重。

### 1.10 旧版自己的迁移机制（供对照）

- 启动时把所有来源复制到工作目录再打开；损坏或被锁的来源跳过且不记指纹，下次重试（settings_upgrade_migration.dart:51-74）。
- 合并：当前数据优先；只在当前数据是旧格式时，用“最丰富”的来源覆盖标量；集合按身份取并集，空字段互补，关注的 tagIds 取并集（:102-183）。
- 集合身份：关注和历史按 `平台|房间号`（未小写）；分区按三元组；WebDAV 按 `name|url`（配置里其实没有 url 字段）（:212-228）。
- 首次迁移前把所有来源备份到 `MIGRATION_BACKUP/settings-v4`（app_path_manager.dart:246-270）；IPTV 只补缺失文件，数据库最大的来源优先（:272-302）。

## 2. 房间身份规范（RoomRef）

- **平台**：去空白，转小写，不能为空（live_room.dart:486）。
- **房间号**：只去空白，**区分大小写**（:488）。以下值无效（比较时不区分大小写）：空、`0`、`null`、`undefined`、`nan`、`none`（favorite_room_controller.dart:162-180；c22ae2f4；favorite_room_validity_test.dart）。
- **字符串形式**：`<平台>:<房间号>`，在第一个 `:` 处拆分（平台 id 不含 `:`）。用于标签映射、房间偏好、备份和分享（live_room.dart:525-533）。
- **旧格式解析**：

| 旧格式 | 出现在 | 解析 |
|---|---|---|
| `平台:房间号` | 标签映射、竖屏覆盖 | 按上面规则 |
| `room_vol_<平台>_<房间号>` | roomVolumes | 去前缀后在第一个 `_` 处拆分；所有平台 id（含退役的）都不含 `_`（sites.dart:40-74, 118-131） |
| 纯房间号 | 旧标签映射 | §6.4.6 |
| `<平台>_<房间号>` | 录制 taskId | 优先用任务里的 platform、roomId 字段（live_record_task.dart:180, 381-384） |

- 平台自己的归一（例如斗鱼别名换数字房间号）属于平台规格；存储层迁移时不访问网络，按上面规则原样保存。
- 平台状态在运行时计算，不存库：已支持 / 已退役（sites.dart:114-134）/ v4 暂不支持 / 未知。任何状态的房间都保留。
- 分区身份：`(平台小写, 命名空间, areaId 去空白)`，命名空间只有 missevan 取 areaType 小写，其它为空（live_area.dart:31-40；favorite_area_identity_test.dart:84）。

## 3. v4 数据模型

主库用 drift（最新稳定版），文件 `<根>/DB/pure_live.db` **[决定]**；IPTV 数据也在主库（schema 2 的 `iptv_*` 表，见 [iptv.md](iptv.md) §7），旧 IPTV 库只读导入（§1.7）**[决定]**（2026-09-28 修订，原为“原位沿用”）。所有时间用 UTC 毫秒。

| 表 | 关键列 | 约束与说明 |
|---|---|---|
| rooms | id、platform、room_id、nick、title、avatar、cover、area、user_id、audience_type、popularity、online_viewers、total_viewers、followers、last_status、extra（JSON：IPTV 字段、notice、introduction）、updated_at | 唯一 (platform, room_id)，room_id 区分大小写。last_status 只作缓存，启动时一律显示未知（§6.4.10） |
| follows | room_id（外键）、sort_order、followed_at、source（user / import / backup） | 每房间最多一行 |
| follow_areas | platform、namespace、area_id、area_name、type_name、area_pic、short_name、sort_order | 唯一 (platform, namespace, area_id) |
| tags | id（保留旧 id）、name、description、sort_order | 名称不区分大小写唯一（tag_management_controller.dart:183-192） |
| room_tags | room_id、tag_id | 唯一对；以此为准，不用 LiveRoom.tagIds |
| history | room_id、last_watched_at（可空） | 每房间一行；条数上限由 `history.limit` 决定，0 = 不限 |
| block_rules | kind（keyword / user）、value、value_folded、created_at | 唯一 (kind, value_folded)；value_folded = 去空白后小写（favorite_room_controller.dart:627-635） |
| room_prefs | room_id、key（volume、portraitLayout、liveAlert、…）、value（JSON） | 唯一 (room_id, key)。liveAlert 只存 `false`（该房间不开播提醒），没有则跟随全局开关 `alerts.live`（ADR 草稿 ADR 0028） |
| record_tasks | id、room_id、status、auto_reconnect、quality_pref、quality_cursor、line_cursor、stopped_by_user、retry_count、last_error_kind、last_error_text、last_error_stage、session_started_at、session_dir、bytes、media_ms、created_at | 每房间一个任务；**不含 URL、请求头、Cookie**（record.md §13） |
| record_files | id、task_id（可空）、room_id、path、kind（flv / hls / ts / mp4 / xml / gaps / legacy_ts）、state（writing / complete / interrupted / remuxing / remuxed / remux_failed / missing）、bytes、media_ms、started_at、ended_at、gap_count、source_file_id | 删除任务不删记录 |
| webdav_profiles | id、name、base_url、username、secret_ref、is_current、remote_dir | name 唯一；密码只在密钥库 |
| settings | key、value（JSON）、updated_at | 键必须在设置注册表里（§5） |
| meta | key、value | schema 版本、导入账本、设备 id、首启标记、开播提醒记录（`alerts.liveRecords`）、节目提醒列表（`alerts.programmeReminders`）等 |

- 所有写入等待完成才算成功；失败回滚内存状态（旧版关注、历史已这样做：favorite_room_controller.dart:404-436；69e5b80b）。退出前把未完成的写入刷盘，最多等 2 s（plugins/utils.dart:19-23）。
- 历史清空只删除“清空时刻的快照”里的行，期间新增的记录保留（history_controller.dart:43-47；db3ef116；history_metadata_test.dart:31）。

## 4. 密钥存储

| 密钥 | 引用名 | 来源 |
|---|---|---|
| 平台 Cookie | `cookie/<平台>` | §1.4 |
| 斗鱼 LTP0、DID | `cookie/douyu.ltp0`、`cookie/douyu.did` | §1.4 |
| WebDAV 密码 | `webdav/<profile id>` | §1.3 |
| Xtream 密码 | `iptv/xtream/<provider id>` | §1.7 Providers.password |
| 备份口令 | 不保存 | §7.3 |

- Android：用 Android Keystore 里的不可导出密钥做 AES-GCM 加密；Windows：DPAPI（当前用户）。密文放在独立的密钥存储里，主库只存引用名（ADR 0004 §3）。**[待确认]** Linux（libsecret 不可用时）、macOS / iOS（Keychain）的做法。
- 密文与设备绑定：换设备、重装后无法解密，不进备份；备份的密钥部分见 §7.3。
- 读不到或解不开的密钥按“未登录”处理并提示重新登录，不崩溃。
- 旧 IPTV 库里 Xtream 密码的迁出要改 IPTV 库结构，会影响回退（§6.7）。**[待确认]** 放在 v4 正式切换时执行还是更早。
- IPTV 频道和收藏房间的 `httpHeaders` 可能含 Authorization / Cookie。**[待确认]** 是否也按密钥处理。

## 5. 设置注册表

每个设置在注册表里有一条定义（ADR 0004 §4）：

| 属性 | 说明 |
|---|---|
| id | v4 键，如 `player.fit` |
| 类型与默认值 | 默认值可按平台或屏幕计算（例：page.defaultSize、旧 videoPlayerKey） |
| 校验 | 范围夹紧或枚举集合；非法值回退默认并记日志 |
| 编解码 | 值与 JSON 互转 |
| 旧键 | 旧 Hive 键 + 旧备份中的字段名（例：theme.locale ← `language`、`languageName`；danmaku.pipNoEmojiMode ← `pipDanmaNoEmojiMode`、`pipDanmakuNoEmojiMode`），各带一个旧值转换 |
| 作用域 | `synced`：备份和跨设备同步都包含；`device`：只在完整备份里，且只在同一平台家族（Android / Windows / …）之间恢复 **[决定]**；`internal`：不备份、不重置；`secret`：不在 settings 表，走 §4 |

由注册表派生：设置页的重置、备份范围、导入映射、同步范围、未知键的处理（导入时忽略并写进报告）。

作用域分配 **[决定]**：弹幕、主题（字体文件名除外）、卡片、分页、刷新、播放的通用项、目录平台为 `synced`；窗口、代理、路径类、退出、开机自启、播放输出驱动和硬解选项、字体文件名、本地互动、录制为 `device`；迁移计数、设备 id、缓存为 `internal`；Cookie 和密码为 `secret`。TV 模式（`app.tvMode` 自动 / 开启 / 关闭，`app.tvPerformanceMode`）是 v4 新增、没有旧键的 `device` 设置：电视上的选择不能随备份跑到手机上；竖屏全屏上下滑换台（`player.switchRoomGesture`，默认关）属于播放的通用项，为 `synced`（2026-09-28，ADR 0026）。关注页排序（`follows.sort`：人数 / 开播时间 / 平台 / 自定义，默认人数，与旧版固定按人数一致）是 v4 新增、没有旧键的 `synced` 设置（2026-09-28，F-FAV-01）。

## 6. 旧数据导入（迁移）

### 6.1 何时迁移

- 启动时读 meta：已记录“导入完成”且没有新的候选来源 → 跳过。候选检查只对已知路径做文件状态查询（大小、修改时间）；Windows 的注册表和兄弟目录扫描只在首次或 exe 所在目录变化时做，结果记在 meta **[决定]**。旧版每次启动都全量检查（settings_upgrade_migration.dart:45-99；app_path_manager.dart:73-83；诊断 05 ④-3、④-6）。
- 需要迁移时，runApp 后先显示迁移页，导入完成再进首页。存储就绪是界面构建的硬前提，界面不能先于数据构建（842fe3a3；initialized.dart:81-86）。
- 同包名覆盖安装的 v4.0.0 才会自动迁移；`.next` 预览包读不到旧沙盒，只能从文件、WebDAV 或局域网导入（§11）。

### 6.2 来源发现

- 主来源：当前数据根的 `HIVE_DB/app_settings.hive`。
- 附加来源：Android 旧路径（§1.1，[待确认]）；Windows 按 §1.9 的全部位置。
- 不作为来源：`window_*` 等多实例子目录（它们的数据来自交接文件）**[决定]**；`MIGRATION_BACKUP` 下的任何文件。
- IPTV：当前根的 IPTV 库不存在、而旧位置有时，复制数据库最大的那个到当前根，只补缺失文件，与旧版一致（app_path_manager.dart:272-302）。

### 6.3 导入流程

1. 迁移前备份：把所有来源 Hive 文件、当前 IPTV 库、SharedPreferences 文件复制到 `MIGRATION_BACKUP/app-v4-<yyyyMMdd_HHmmss>/`，附清单（原路径、大小、修改时间、SHA-256）。不用旧版已占用的 `settings-v4` 和 `*_v4.lock`（ADR 0004 §5）。
2. 读取：在后台 isolate 用仅迁移用的 `hive_ce` 打开**副本**（先复制到工作目录），源文件永不打开、永不修改。
3. 指纹：v4 指纹 = 副本内容的 SHA-256；同时计算旧格式指纹 `绝对路径|字节数|修改时间毫秒`。旧账本 `settingsUpgradeImportedSources` 里的指纹视为已导入（旧版已合并过）。
4. 解析 → 规范化（§6.4）→ 合并（§6.5）→ 生成完整导入计划 → 整体校验。
5. 一次事务写入主库和密钥库；成功后在 meta 记录：导入版本、每个来源的两种指纹、导入时间、报告摘要。
6. 迁移报告：每类数据的读入数、写入数、丢弃数和原因（无效房间、重复、未知键、无法解析的值），可在设置页查看和导出（脱敏）。

### 6.4 规范化规则

**6.4.1 显示文案转枚举**

| 设置 | 旧值 → v4 |
|---|---|
| preferResolution、preferResolutionCellular、record 的 default_quality | 原画 → original；蓝光8M → bluRay8M；蓝光4M → bluRay4M；超清 → superHigh；流畅 → smooth；其它 → original（player_consts.dart:25；recorder_config.dart:91-92） |
| themeMode | System / Dark / Light → system / dark / light；其它 → system（app_consts.dart:25-28） |
| videoFitIndex | 下标 → 枚举；越界 → contain |
| room card preset | compact / normal / rich / custom → 同名枚举 |

**6.4.2 语言**：Hive `language` 存在时优先：`简体中文` → `zh-Hans`，`English` → `en`；不存在时用 SharedPreferences `locale`：`zh*` → `zh-Hans`，`en*` → `en`；都没有 → 跟随系统（新装默认）**[决定]**（app_consts.dart:37；theme_settings_controller.dart:9, 159-164, 186）。导入后两处以同一个值为准，v4 只保存一份。

**6.4.3 废弃键**：`audioOnly` 丢弃（纯音频改为房间级，initial_services.dart:67-75）；缺少 `refreshRateMode` 时，`enableHighRefreshRate == true` → balanced，否则 powerSaving（app_settings_controller.dart:25-40, 110-112）；缺少 `enableMultiView`、`enableNewWindowPlay` → true（:57-61）；`taobaoCookie`、`autoRefreshTime`、`showSplashPage`、`cached_area_pics` 丢弃。

**6.4.4 播放内核**：`videoPlayerKey` 为 ijk / exo / fvp / mpv 都丢弃，v4 全平台 mpv（宪法“已确认的决定”；ADR 0006）。

**6.4.5 集合格式**：`favoriteRooms`、`favoriteAreas`、`historyRooms`、`webDavConfigs` 同时识别 String `{"list":[…]}`、List<String>（每项一个 JSON）、List<Map>；单项可以是 Map 或 JSON 字符串；解析失败的单项丢弃并记报告（settings_upgrade_migration.dart:185-210；backup_migration_util.dart:4-22；6d086e2f；settings_upgrade_migration_test.dart:17, 49）。

**6.4.6 标签**：以 `room_to_tags_mapping_v1` 为准，忽略 LiveRoom.tagIds（4d8ed292；tag_management_controller.dart:78-121；room_card_tag_assignment_test.dart:46-83）。
- 键为 `平台:房间号` → 直接映射。
- 键为纯房间号 → 复制给所有房间号相同的关注和历史房间（旧版只处理关注，favorite_controller.dart:86）**[决定]**；没有匹配房间的旧键不导入，写进报告 **[待确认]** 是否需要保留。
- 映射中不存在的标签 id 丢弃；标签 id 为空或重复时重新分配（:318-331）；名称不区分大小写重复时合并为同一标签 **[决定]**。

**6.4.7 关注和历史的清理与去重**：按 §2 规范化；无效房间丢弃；按 RoomRef 去重，保留首次出现的位置，后出现的只补空字段（favorite_room_controller.dart:182-214；settings_upgrade_migration.dart:158-183）。关注顺序保持旧列表顺序。历史按旧列表顺序（旧版新记录插在最前）；`history.limit` 不为 0 时截断到上限，为 0 时一条不删（history_controller.dart:8-37, 76-80）。

**6.4.8 平台 id 版本表与计数器**

- `hotAreasList` 先规范化（去空白、小写、去重），再按 `siteCatalogMigration` 补齐之后版本新增的平台：版本 < 2 时一次加入当时全部平台；之后每个版本只追加一个平台；**已退役的 id 保留版本槽位、永不重新加入**（favorite_room_controller.dart:58-120；1495f56b；18 个 `*_catalog_migration_test.dart`）。
- 版本表（:58-96）：

| 版本 | 平台 | 版本 | 平台 | 版本 | 平台 |
|---|---|---|---|---|---|
| 3 | acfun | 16 | chzzk | 29 | rumble（退役） |
| 4 | picarto | 17 | kick（退役） | 30 | goodgame（退役） |
| 5 | twitcasting | 18 | 17live | 31 | fc2live |
| 6 | missevan | 19 | liveme | 32 | steambroadcast |
| 7 | inke | 20 | tiktok | 33 | jdlive |
| 8 | kilakila | 21 | youtube | 34 | taobaolive（退役） |
| 9 | huajiao（退役） | 22 | bigo | 35 | kugoulive |
| 10 | openrec（退役） | 23 | pandalive | 36 | baidulive |
| 11 | ttinglive（退役） | 24 | popkontv（退役） | 37 | sixroom |
| 12 | xiaohongshu | 25 | shopeelive（退役） | 38 | looklive |
| 13 | niconico | 26 | vkvideolive（退役） | | |
| 14 | weibo | 27 | nimotv（退役） | | |
| 15 | showroom | 28 | dailymotion（退役） | | |

- v4 从 39 起继续编号，同样每版只追加一个平台 **[决定]**。
- 平台可见列表里保留 v4 暂不支持的平台 id（首批只做 5 个平台不能成为删除理由），界面只显示已支持的；`preferPlatform` 不在可见列表里时改为列表第一个（:139-148）。
- `realOnlinePlatforms` 按 `audienceMetricMigration` 补齐：1 twitch、2 soop、3 acfun、4 picarto、5 twitcasting、6 和 7 为退役平台的空操作（app_settings_controller.dart:75-100）。
- `danmakuInteractionMigration` < 1 时，点按和长按互动都设为开（danmaku_settings_controller.dart:128-132）。
- 以上计数器应用后不再保存。

**6.4.9 房间偏好**：`roomVolumes` 的值夹在 0–1、非有限值丢弃（live_room_volume_manager.dart:19, 28-31）；`portraitRoomOverrides` 只保留合法布局名。两者都按 §2 解析为 RoomRef，写入 room_prefs；房间不在 rooms 表时新建只有身份的房间行。

**6.4.10 直播状态**：导入的 last_status 只作缓存；启动时关注的状态一律显示“未知”，由刷新一次性发布结果（d6c3d8df；favorite_controller.dart:652-665；favorite_startup_policy_test.dart:18, 113）。

**6.4.11 人气字段**：虎牙旧记录的 onlineViewers 实际是人气，读入时移到 popularity（live_room.dart:395-405；db3ef116）。

**6.4.12 WebDAV**：配置按 name 去重（旧版合并用了不存在的 url 字段，实际也只按名字：settings_upgrade_migration.dart:224）；地址按旧规则校验（http/https、无用户信息、无查询和片段，webdav_config.dart:14-35），不合法的保留但标为无效；密码进密钥库；`currentWebDavConfig` 只用来确定哪个是当前配置，其中的密码忽略。

**6.4.13 录制任务**：按 record.md §13 的字段导入；活跃态一律改为停止；`currentUrl` 丢弃（live_record_task.dart:418-419）；时长 >1 年归零；pendingAttempts 交给 record.md §14.3 一次性收尾。

**6.4.14 其它设置**：按注册表校验、夹紧后写入；未知键写进报告。

### 6.5 多来源合并

- 主来源（当前根）的标量设置优先；附加来源只补主来源缺少的键。
- 集合（关注、分区、历史、屏蔽规则、WebDAV、标签映射）按身份取并集，重复项只补空字段。
- 已有 v4 数据时（例如先用了一段时间再导入），v4 已有的值优先，导入只补缺 **[决定]**。

### 6.6 失败与重试

- 某个来源打不开（损坏、被锁）→ 跳过，不记指纹，下次启动重试（settings_upgrade_migration.dart:65-67；settings_upgrade_migration_test.dart:94）。
- 导入计划校验失败或事务失败 → 什么都不写；迁移页显示“重试 / 稍后再说 / 导出诊断”。选“稍后”时应用以空库启动，meta 记“待导入”；之后导入按 §6.5 合并，不覆盖用户在此期间的新数据。
- 迁移中进程被杀 → 下次启动从头重做（事务未提交即无影响）。

### 6.7 回退保障

- 旧 Hive 文件、旧 SharedPreferences 一律不改，回退到 3.3.x 时旧版读到的是迁移时刻的数据（v4 期间的新改动不会回写）。
- IPTV 库：旧版遇到更高的 schemaVersion 会直接报错（database.dart:54-56）。v4 不修改旧 IPTV 库（数据在主库，旧库只读导入），回退后旧版照常读到迁移时的 IPTV 数据 **[决定]**（2026-09-28 修订，原为“升级前先备份库文件”）。

## 7. 备份格式 v4 与旧格式兼容

### 7.1 v4 格式

```json
{
  "format": "pure_live.backup",
  "version": 4,
  "createdAt": "2026-09-27T02:00:00Z",
  "app": {"version": "4.0.0", "platform": "android"},
  "scope": "full",
  "sections": {
    "settings": {"danmaku.speed": 120, "theme.mode": "system"},
    "follows": [{"platform": "douyu", "roomId": "5526219", "nick": "…", "followedAt": 0, "order": 0}],
    "followAreas": [],
    "tags": [], "roomTags": [],
    "history": [],
    "blockRules": [],
    "roomPrefs": [],
    "recordTasks": [],
    "webdavProfiles": [{"name": "…", "baseUrl": "…", "username": "…"}],
    "iptv": {"playlists": [{"name": "…", "url": "…", "autoSync": true, "order": 0}], "epgSources": [{"name": "…", "url": "…", "autoSync": true, "selected": true, "order": 0}]}
  },
  "secrets": null
}
```

- `scope`：`full`（完整备份）或 `follows`（只有 follows 和 followAreas）。
- 房间以 `platform` + `roomId` 表示，附展示快照；不写内部行 id。
- settings 只含注册表中 `synced` 和 `device` 作用域的键；`device` 只在同一平台家族之间恢复。
- 不含：签名 URL、Cookie、密码（除非 §7.3）、EPG 节目数据、缓存、录制文件本身。
- iptv 分区包含网址来源的播放列表和节目单源（名称、地址、播放列表 UA、自动同步、当前节目单、顺序）**[决定]**（旧备份没有 IPTV 数据：诊断 05 ⑦-7）。文件来源、频道和节目不进备份，换设备后重新同步；收藏列表、备用组已合并进关注和线路（product F-IPTV-08、F-IPTV-11），节目单匹配每次自动计算，都不需要备份（2026-09-28 修订，见 iptv.md §7）。读取时 `providers` 是 `playlists` 的别名；Xtream 以后加入时密码仍不进备份。
- 文件名：`purelive_v4_<yyyy-MM-ddTHH_mm_ss>_<uuid>.json`，关注专用为 `purelive_v4_follows_…json` **[决定]**。写 `.part` 后改名，替换已有文件时先保留 `.previous`，与旧版一致（backup_controller.dart:363-405）。
- 旧版遇到 v4 文件会因为找不到已识别的分区而拒绝，不会写坏数据（backup_controller.dart:146-168）。

### 7.2 导入规则

- 先整体解析和校验，生成完整导入计划，再一次事务写入；任一错误 → 什么都不写（旧版逐个控制器写入，失败再按快照回滚：backup_controller.dart:435-455；backup_roundtrip_test.dart:128-255）。
- 同一时间只允许一个恢复（:34, 436）。
- `version` > 4 → 拒绝并提示更新应用。
- 完整恢复：文件里有的分区整体替换本机对应数据；**文件里没有的分区保持本机不变** **[决定]**（旧版缺少的分区会被重置为默认值：backup_controller.dart:241-281）。
- 仅关注恢复：只替换 follows 和 followAreas，其它全部不动（ISSUE_865 审计；backup_controller.dart:414-433）。
- 完整恢复入口选到关注专用文件 → 在写入前报格式错误（backup_controller.dart:171-173, 408-410）。

### 7.3 密钥部分

- 只有用户选择“包含账号信息”并设置口令时才写 `secrets`；默认不含（backup_privacy_test.dart:5）。
- 格式 **[决定]**：`{"kdf":"pbkdf2-sha256","iterations":600000,"salt":"<16 字节 base64>","cipher":"aes-256-gcm","nonce":"<12 字节 base64>","data":"<base64>"}`；明文是 `{引用名: 值}`；附加认证数据为 `format|version|createdAt`。
- 口令错误 → 其余部分照常导入，密钥部分跳过并提示。

### 7.4 旧格式兼容

| 格式 | 识别 | 映射 | 证据 |
|---|---|---|---|
| 无版本扁平 | 没有 `backupVersion`；根上有已知设置键、`favoriteRooms`、`custom_tags_data` 或 `pipDanmaNoEmojiMode` | 根上的键按注册表旧键映射；标签在 `custom_tags_data{tags, roomTagsMap}` | backup_controller.dart:146-168, 326-353 |
| v2、v3 | `backupVersion` 为 2 或 3；分区 app、theme、roomCard、font、player、danmaku、volume、favorite、history、webdav、iptv、cookie、proxy、windowSize、exit、startup、tags、refresh、page；v3 有 `sensitiveDataIncluded` | 分区字段名按注册表旧键映射（如 theme 的 `languageName`）；windowSize 兼容旧的扁平 PiP 矩形和 player 里的 rememberPipPosition；v3 的 webdav、cookie 分区是明文，导入时 Cookie、密码进密钥库 | :33, 56-88, 223-324 |
| 仅关注 | `backupVersion` 3 + `backupScope: favorites` + `favorite{favoriteRooms, favoriteAreas}` | 只导入关注 | :90-101, 407-433；ISSUE_874 审计 |
| 其它版本号 | `backupVersion` 不是正整数 | 拒绝 | :146-150 |
| 局域网旧包 | `{type:'pure_live_sync', version:1, settings:<v3 完整导出>}` | 按 v3 导入 | remote_sync_protocol.dart:59-61 |
| 旧电视接口 | `POST /api/setSettings?settings=<扁平 JSON：弹幕 + 关注 + 历史 + UA，可带 Cookie>` | v4 不发送也不接收（设置放在 URL 里）**[待确认]** 还有没有旧电视端在用 | backup_recovery_service.dart:119-130；backup_controller.dart:505-521 |
| Windows 新窗口交接文件 | 系统临时目录 `pure_live_instance_*/<实例 id>.json` = v3 完整导出（含 Cookie 明文） | v4 改用 v4 格式且不含密钥明文，新窗口直接读同一用户的密钥库 **[决定]**；只接受启动器写的路径，导入后删除 | windows_multi_instance_launcher.dart:46-66, 119-131；ef5f05c0；windows_multi_instance_launcher_test.dart:51 |

- 旧格式里的关注、历史、分区按 §6.4 同样规范化；导入报告同 §6.3。

## 8. 分享口令

- 格式：base64url（去掉 `=` 填充）编码的 MessagePack Map `{m:'pure_live', p:平台, r:房间号, ti:标题, n:主播名, l:链接, c:封面, a:头像}`（share_command_handler.dart:4-48）。
- 解码：补齐填充、`-`/`_` 换回 `+`/`/`；`m` 不是 `pure_live` 或解析失败 → 不是口令；结果按 §2 得到 RoomRef。
- v4 编码格式不变，与 3.x 互通 **[决定]**。
- 入口：剪贴板（回到前台 1 s 后读取，v4 可关闭）、Android 分享文本（desktop_manager.dart:611-638；main.dart:105-131；share_command_handler_test.dart）。

## 9. 局域网同步

- 端口：HTTP 39888，发现 UDP 39889；二维码 `purelive://<ip>:<端口>/sync?code=<6 位数字>`（remote_sync_protocol.dart:3-41）。
- 每个设置请求带 `x-purelive-pairing` 头，配对码常数时间比较，错误返回 403；目标设备上要用户确认；不加 CORS 头（:13-35；remote_sync_service.dart:440-450, 499-530, 626；remote_sync_test.dart:64-95）。
- v4 包：`{type:'pure_live_sync', version:2, backup:<§7.1 文档>}` **[决定]**；接收端同时接受 version 1（按 v3 导入），与 3.3.x 设备互通。
- 密钥：旧版勾选“包含账号”后 Cookie 明文经 HTTP 发送（remote_sync_service.dart:546, 995）；v4 只能以 §7.3 的口令加密方式携带 **[决定]**。
- 设备 id 沿用旧的 `remote_sync_device_id`（§1.6）。

## 10. WebDAV

- 配置：name（唯一）、地址（校验规则同 §6.4.12）、用户名、密码（密钥库）、远端目录（common/services/settings/web_dav_controller.dart:28-51）。
- 上传：完整备份或仅关注，v4 格式（§7.1）；文件名带 uuid，避免同一秒覆盖（modules/web_dav/web_dav_controller.dart:325-346）。默认不含密钥，要带必须设口令（§7.3）。
- 列表里同时显示 v4 文件和旧的 `purelive_*.txt`、`purelive_favorites_*.txt`；按文件内容识别格式，不靠文件名。
- 恢复前要用户确认；提供“恢复全部”和“仅恢复关注”两个入口；操作期间切换服务或目录时丢弃过期结果（modules/web_dav/web_dav_controller.dart:392-440）。

## 11. 预览包与签名切换的保底

- 预览包包名为 `.next`，读不到正式版沙盒；Android 8 用户换签名后需要重装，沙盒也会丢（ADR 0004 §8；PLAN §12）。自动迁移只在 v4.0.0 同包名覆盖安装时生效。
- 3.3.x 增加“导出 v4 备份”：直接写 §7.1 格式，包含录制设置和任务、本地互动、IPTV 源等旧备份不含的数据；可选口令加密密钥。
- 3.3.x 提示：只在 Firestore 上有配置的用户，先在 3.3.x 里从云端恢复，再导出 v4 备份（v4 没有 Firebase：诊断 05 ⑥）。
- v4 首次启动（空库）提供导入向导：文件、WebDAV、局域网。

## 12. 验收

| 项 | 方法 | 通过条件 |
|---|---|---|
| 真实旧数据 | 用真实旧版数据副本做样本（含 2.0 以前的 List<String> 格式、多来源 Windows 目录、含退役平台和无效房间的关注） | 关注、分区、历史、标签、屏蔽、房间偏好、WebDAV、Cookie、设置全部按本规格落库；报告的丢弃项与预期一致 |
| 源文件不改 | 迁移前后对所有来源文件算 SHA-256 | 完全一致 |
| 幂等 | 同一来源导入两次 | 第二次无任何写入，数据不重复 |
| 失败可重试 | 注入：来源被锁、中途杀进程、事务失败 | 下次启动重试成功；没有半截数据 |
| 启动开销 | 已迁移状态下冷启动 | 迁移检查只有文件状态查询，≤5 ms（K90）**[决定]** |
| 备份往返 | v4 导出 → 导入；v3、无版本、仅关注、局域网 v1 包 → 导入 | 数据等价；旧格式按映射落库；错误文件什么都不写 |
| 隐私 | 扫描数据库、备份（无口令）、日志、交接文件 | 没有 Cookie、密码、签名 URL 明文 |
| 回退 | 迁移后装回 3.3.x | 旧版正常启动并读到迁移时的数据；按说明还原 IPTV 库后 IPTV 正常 |

## 13. 待确认汇总

1. Android 旧路径 `<文档>/pure_live/app_settings.hive` 是否需要作为来源（§1.1、§6.2）。
2. `enableStartUp` 默认 true 是否有意（§1.5）。
3. Linux、macOS、iOS 的密钥存储方案（§4）。
4. Xtream 密码迁出的时机；`httpHeaders` 是否按密钥处理（§4）。
5. 没有匹配房间的旧标签映射是否保留（§6.4.6）。
6. 旧电视接口是否还有使用者（§7.4）。

## 14. 必须继承的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-STORE-001 | 升级后首次启动界面异常，第二次启动才正常 | 设置注册没等完成，界面先于设置服务构建 | 存储和设置就绪是界面构建的硬前提 | 842fe3a3；initialized.dart:81-86 |
| REG-STORE-002 | 冷启动迁移时首帧卡住 | 在设置服务初始化里注册 IPTV 控制器，依赖注入重入 | 显式初始化顺序，构造期不做副作用 | c5072259；initial_services.dart:22-27；settings_service_lifecycle_test.dart:35 |
| REG-STORE-003 | 直接复制旧 Hive 文件后关注显示为空 | 集合格式变过：旧 `List<String>`，新 `{"list":[…]}` | 两种格式都识别；按身份取并集，空字段互补 | 6d086e2f；settings_upgrade_migration.dart:22-28, 158-210；settings_upgrade_migration_test.dart:17, 49 |
| REG-STORE-004 | Windows 换盘重装后数据“丢失” | 数据在安装目录下，注册表只记最新位置 | 注册表、兄弟目录、搬迁账本链一起查；先备份；指纹账本防重复导入；被锁文件下次重试；源目录只读 | app_path_manager.dart:108-293；settings_upgrade_migration_test.dart:94；docs/WINDOWS_DATA_AND_UPGRADE.md |
| REG-STORE-005 | 关注里有打不开或重复的房间 | 房间号为 0、null、undefined、nan、none，或平台大小写不一致 | 读入、导入、写入三处统一校验去重；平台小写，房间号保留大小写 | c22ae2f4；favorite_room_controller.dart:162-214；favorite_room_validity_test.dart:7；favorite_area_identity_test.dart:84 |
| REG-STORE-006 | 标签串到别的房间或丢失 | 旧映射只用房间号作键；LiveRoom.tagIds 是陈旧副本 | 映射改为 `平台:房间号`，以映射表为准 | 4d8ed292；tag_management_controller.dart:78-121；room_card_tag_assignment_test.dart:46-83 |
| REG-STORE-007 | 启动时已下播的房间显示“直播中”，卡片跳动 | 持久化了上次的直播状态；多次刷新互相取消 | 启动时一律显示未知；校验结果一次性发布；刷新串行 | d6c3d8df；favorite_controller.dart:652-665；favorite_startup_policy_test.dart:18, 113 |
| REG-STORE-008 | 快速修改或退出后关注丢失 | 写入不等待完成 | 等待写入并刷盘，失败回滚；退出前刷盘（最多 2 s） | 69e5b80b；favorite_room_controller.dart:404-436；plugins/utils.dart:19-23 |
| REG-STORE-009 | 恢复失败后设置半新半旧 | 各控制器逐个写入 | 先整体校验，再一次事务写入；禁止并发恢复 | backup_controller.dart:435-455；backup_roundtrip_test.dart:128-255 |
| REG-STORE-010 | 老用户看不到新平台；已退役的平台又出现 | 平台列表按用户自定义顺序保存 | 版本表每版只追加一个平台；退役平台保留槽位、不再加入；其关注和历史仍保留 | 1495f56b；favorite_room_controller.dart:58-120；*_catalog_migration_test.dart |
| REG-STORE-011 | Windows “新窗口”打开后是空配置 | 每个窗口实例用独立数据目录 | 用临时文件交接，只接受启动器写的路径，导入后删除 | ef5f05c0；windows_multi_instance_launcher.dart:46-66；windows_multi_instance_launcher_test.dart:51 |
| REG-STORE-012 | 旧键导致新行为错误 | 全局 audioOnly、布尔型高刷开关已废弃 | 一次性转换：高刷 true → balanced；缺键时多画面、新窗口默认 true；audioOnly 丢弃 | initial_services.dart:67-75；app_settings_controller.dart:25-40, 57-61, 106-112 |
| REG-STORE-013 | 备份或同步泄露 Cookie | 敏感数据和普通设置一起导出 | 默认不含；要带必须口令加密；局域网要配对码并在本机确认；不开 CORS | backup_controller.dart:56-110；backup_privacy_test.dart:5；remote_sync_test.dart:64-95 |
| REG-STORE-014 | 冷启动时分享的链接无效；Android 停在原生启动页 | 导航器没挂载；字体初始化时访问了上下文 | 等导航器就绪再打开；首帧前不碰上下文 | 1836953e；font_settings_controller.dart:143-151 |
| REG-STORE-015 | 虎牙旧记录的人数含义错；清空历史误删新记录 | 旧版字段混用；按身份清空 | 读入时把虎牙 onlineViewers 移到人气；只删除清空时刻快照里的记录 | db3ef116；live_room.dart:394-405；history_controller.dart:43-47；history_metadata_test.dart:31 |
| REG-STORE-016 | 删了 WebDAV 配置，密码仍留在存储里 [代码推断] | 当前配置以完整 JSON（含密码）另存一份 | 只按 name 标记当前配置；密码只在密钥库一处 | common/services/settings/web_dav_controller.dart:15, 59-65 |
| REG-STORE-017 | WebDAV 配置合并时同名不同地址被当成一个 [代码推断] | 合并身份用了配置里不存在的 url 字段，实际只按名字 | 明确以 name 为唯一键，冲突写进报告 | settings_upgrade_migration.dart:221-227；webdav_config.dart:1-45 |
| REG-STORE-018 | 启动慢 | 每次启动都全量做迁移检查（整个 box 转 map、两次 jsonEncode 比较、解码关注和历史）；Windows 每次都扫注册表 | 只在需要时迁移；发现结果记在 meta | settings_upgrade_migration.dart:45-99；app_path_manager.dart:73-83 |
| REG-STORE-019 | 语言设置时好时坏 | Hive `language` 和 SharedPreferences `locale` 两份存储，恢复备份只改前者 | 导入时定优先级合成一份；v4 只存一处 | theme_settings_controller.dart:159-164；main.dart:36-41 |
| REG-STORE-020 | 改翻译或界面文案后设置失配 | 设置里存的是显示文案（`简体中文`、`原画`、`System`） | 存枚举，显示文案只在界面层 | theme_settings_controller.dart:8-9；player_settings_controller.dart:36-37；recorder_config.dart:151-155 |
| REG-STORE-021 | 回退旧版后 IPTV 全部失效 [代码推断] | 旧版遇到更高的 IPTV schemaVersion 直接抛错 | 升级 IPTV 库结构前先备份库文件，并提供还原说明 | database.dart:54-56 |
| REG-STORE-022 | 设了“不限”的历史可能在升级时被截到 50 条 [代码推断] | 旧文档写的升级规则是“历史保留最新 50 条”，按默认上限而不是用户设置截断 | 按用户的 historyLimit 截断，0 = 不限 | history_controller.dart:8-22, 76-80；docs/WINDOWS_DATA_AND_UPGRADE.md:36 |
| REG-STORE-023 | 恢复只含部分分区的备份后，其它设置被重置 [代码推断] | 缺少的分区按空 Map 导入，得到默认值 | 缺少的分区保持本机不变 | backup_controller.dart:241-281 |
| REG-STORE-024 | Cookie 明文留在系统临时目录 [代码推断] | 新窗口交接文件是含敏感数据的完整导出 | 交接文件不含密钥明文；新窗口读同一用户的密钥库 | windows_multi_instance_launcher.dart:119-131 |
| REG-STORE-025 | 局域网同步时 Cookie 以明文 HTTP 发出 | 勾选“包含账号”后随设置一起发送 | 只能以口令加密方式携带 | remote_sync_service.dart:546, 995 |
| REG-STORE-026 | 设置被放进 URL | 旧电视接口用查询参数传完整设置 | 不再使用该接口 | backup_recovery_service.dart:119-130 |
| REG-STORE-027 | 只在云端有配置的用户升级后配置全无 | v4 移除 Firebase，读不到 Firestore | 3.3.x 提示先从云端恢复，再导出 v4 备份 | 诊断 05 ⑥；ADR 0004 §8 |
| REG-STORE-028 | 预览版或换签名重装后数据全无 | `.next` 包名和重装都读不到旧沙盒 | 3.3.x 导出 v4 备份；v4 首启提供文件、WebDAV、局域网导入 | ADR 0004 §8；PLAN §12 |
| REG-STORE-029 | Windows 便携版升级后语言等插件设置丢失 [代码推断] | 更早版本的 SharedPreferences 在系统应用支持目录 | 首次启动从旧位置复制到 `PLUGIN_SUPPORT`（只补不覆盖） | app_path_manager.dart:315-322；windows_portable_path_provider.dart:56-84 |
| REG-STORE-030 | 风险：首批只支持 5 个平台，其它平台的关注被当成无效清掉 | 把“暂不支持”当成“无效” | 未支持和已退役平台的关注、历史原样保留并随备份导出 | sites.dart:114-134；诊断 05 ⑨ |
