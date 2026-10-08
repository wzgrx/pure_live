"""The hand-written part of the J01.2 settings table (see settings_audit.py).

NOTES maps a storage key to what the script cannot find by itself:

- v3: 3.x's default on a fresh Android phone, as a Dart literal, when 3.x
  computed it (a constant from another file, an expression);
- v3src: where 3.x reads it (`lib/` relative), when not a `hive*` call;
- v3range: 3.x's range and repair (file:line under `lib/`);
- ui: the settings page's range when the row is not a catalogue slider,
  counter or number box;
- reads / when: overrides of the found readers and the timing;
- kind: same / approved / fixed / open (default: compared by the script);
- verdict: the reason, the task or decision;
- new: True for settings v4 added (no 3.x key).

Paths under 3.x's `lib/` drop the prefix `common/services/settings/` for
the settings controllers.
"""

_D = 'danmaku_settings_controller.dart'
_REC = 'recorder/consts/recorder_config.dart'
_LOCAL = 'modules/live_play/widgets/local_interaction/local_interaction_controller.dart'
_RECORD_PAGE = '录制设置页 `record_settings_page.dart`'
_LOCAL_PANEL = '本地互动样式面板 `local_style_panel.dart`'
_BLOCK = '屏蔽页 `block_manager.dart`'
_FILTER_WHEN = '立即（直播间和多画面监听它，重建过滤器）'
_RESET = 'J01.3 改成和 3.x 一样回到默认值（`IntSetting` 的 `resetOutOfRange`）'
_FIXED_RANGE = '注册表原来不限，3.x 存的值和导入的备份都夹到这个范围；改成同样的 `min`/`max`'


def _new(task: str) -> dict:
    return {'new': True, 'kind': 'same', 'verdict': f'v4 新加（{task}），默认值照来源任务'}


def _danmaku(line: str, low: str, high: str, *, fixed: bool = False, note: str = '') -> dict:
    entry = {'v3range': f'{low}～{high}（`{_D}:{line}`）'}
    if fixed:
        entry['kind'] = 'fixed'
        entry['verdict'] = _FIXED_RANGE + (f'；{note}' if note else '')
    elif note:
        entry['verdict'] = note
    return entry


NOTES: dict[str, dict] = {
    # ---- app ----
    'autoRefreshTime': {
        'v3range': '不限',
        'verdict': '3.x 也没有读取它的代码，只存、只进备份（功能清点第 15 节）',
    },
    'asmrSleepMinutes': {'v3range': '1～525600（`app_settings_controller.dart:227`）'},
    'enableRotateScreen': {'verdict': '3.x 也没有读取它的代码，只存、只进备份'},
    'enableDenseFavorites': {'verdict': '3.x 也没有改它的界面（只有备份能改），v4 同样'},
    'skippedUpdateVersion': _new('A06.3 c4，本机记录'),
    'refreshRateMode': {
        'v3': "'powerSaving'",
        'v3src': 'app_settings_controller.dart:36-40、:53',
        'verdict': '3.x 新装没有旧开关 `enableHighRefreshRate`，`_initialRefreshRateMode()` 得 `powerSaving`；'
        '旧开关为真的老用户迁移成 `balanced`（`legacy_snapshot.dart`）',
    },
    'matchVideoFrameRate': _new('R02.1，U.2i'),
    'realOnlinePlatforms': {
        'v3': "['douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'acfun', 'picarto', 'twitcasting']",
        'v3src': 'app_settings_controller.dart:11-20、:55',
        'verdict': '`defaultRealOnlinePlatforms` 展开后一样；3.x 的 `audienceMetricMigration` 补的平台都已在列表里',
    },
    'savedMenuIds': {
        'v3': "['favorites', 'popular', 'areas', 'record']",
        'v3src': '`app_settings_controller.dart:69`，`HomeMenu` 在 `common/consts/app_consts.dart:6-10`',
    },
    'showUnplayableInDiscover': _new('UPGRADES 统一原则“受限”，J02.1'),
    'detectClipboardRooms': {
        **_new('O03.2'),
        'verdict': 'v4 新加（O03.2）；3.x 一直检测剪贴板、没有开关，默认开和 3.x 的行为一样',
    },
    'douyuForceRenew': _new('UPGRADES 2-1'),
    'twitchLanguages': {
        **_new('UPGRADES 8-3'),
        'verdict': 'v4 新加（UPGRADES 8-3）；空 = 不筛语言（3.x 固定只看中文和韩语，作为预设 `twitchLegacyLanguages` 提供）',
    },
    # ---- favorite ----
    'hotAreasList': {
        'v3': "['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'yy', 'acfun', 'picarto', "
        "'twitcasting', 'missevan', 'inke', 'kilakila', 'xiaohongshu', 'niconico', 'weibo', 'showroom', 'chzzk', "
        "'liveme', 'tiktok', 'youtube', 'bigo', 'pandalive', 'fc2live', 'steambroadcast', 'jdlive', 'kugoulive', "
        "'baidulive', 'sixroom', 'looklive', '17live', 'iptv']",
        'v3src': '`favorite_room_controller.dart:20`，`AppConsts.supportSites` = `core/sites.dart:217-251`',
        'kind': 'approved',
        'verdict': 'v4 多了 Kick（排在 chzzk 后面）：Kick 重新支持（UPGRADES X-1，E 组 M4.34）；其余 34 个和顺序一样',
    },
    'preferPlatform': {'v3': "'bilibili'", 'v3src': 'favorite_room_controller.dart:24'},
    'historyLimit': {
        'v3range': '≥ 0，负数回到 50（`history_controller.dart:8-15`）',
        'kind': 'fixed',
        'verdict': f'默认值和范围一样；存了负数时 3.x 回到 50，v4 原来夹成 0（不限），{_RESET}',
    },
    # ---- theme ----
    'themeColorSwitch': {
        'v3': "'FF2196F3'",
        'v3src': '`theme_settings_controller.dart:13、:19`（`Colors.blue`）',
        'kind': 'approved',
        'verdict': '品牌蓝 `FF2E6FE0`（A11.2 C-3）；3.x 默认的蓝色存过的老用户迁移一次（`themeColorMigration`）',
    },
    'pureBlackTheme': _new('A11.2 C-4'),
    'themeColorMigration': _new('A11.2，本机记录'),
    'crossAxisSpacing': {'v3range': '0～64（`theme_settings_controller.dart:10-12`、:109-113）', 'ui': '加减 0～64'},
    'mainAxisSpacing': {'v3range': '0～64（同上）', 'ui': '加减 0～64'},
    'loadingStyle': {'v3': "'default'", 'v3src': '`theme_settings_controller.dart:23`，`common/consts/app_consts.dart:21`'},
    # ---- font ----
    'textScaleFactor': {'v3range': '0.5～2（`font_settings_controller.dart:16-18`）', 'ui': '滑块 0.5～2，步长 0.05'},
    'fontSizeBodySmall': {'v3range': '9～15（`font_settings_controller.dart:19-21`）', 'ui': '滑块 9～15，步长 1'},
    'fontSizeBodyMedium': {'v3range': '11～17（`font_settings_controller.dart:22-24`）', 'ui': '滑块 11～17，步长 1'},
    'fontSizeBodyLarge': {'v3range': '12～18（`font_settings_controller.dart:25-27`）', 'ui': '滑块 12～18，步长 1'},
    'fontSizeTitleMedium': {'v3range': '13～20（`font_settings_controller.dart:28-30`）', 'ui': '滑块 13～20，步长 1'},
    'fontSizeTitleLarge': {'v3range': '16～26（`font_settings_controller.dart:31-33`）', 'ui': '滑块 16～26，步长 1'},
    # ---- player ----
    'videoFitIndex': {
        'v3range': '0～5，越界回到 0（`player_settings_controller.dart:135-139`）',
        'kind': 'fixed',
        'verdict': f'默认值和范围一样；越界时 3.x 回到 0（适应），v4 原来夹到 0 或 5，{_RESET}',
    },
    'videoPlayerKey': {
        'v3': "'mpv'",
        'v3src': 'player_settings_controller.dart:11、:27、:34（iOS 是 ijk）',
        'verdict': 'v4 只用 mpv，这个键只为备份往返保留（J02.1 有意差异，F-ROOM-24 不做），没有读取',
    },
    'preferResolution': {'v3': "'原画'", 'v3src': '`player_settings_controller.dart:36`，`player/utils/player_consts.dart:25`'},
    'preferResolutionCellular': {'v3': "'原画'", 'v3src': 'player_settings_controller.dart:37'},
    'preferH264': _new('UPGRADES 统一原则、22-3'),
    'autoPipOnLeave': _new('A07.8，选择 J1'),
    'portraitLayoutMode': {'v3': "'balanced'", 'v3src': '`player_settings_controller.dart:58`，`player/core/portrait_stream_support.dart:9`'},
    'portraitFullscreenPolicy': {'v3': "'followSource'", 'v3src': 'player_settings_controller.dart:59-62'},
    'portraitFullscreenDisplayMode': {'v3': "'ambient'", 'v3src': 'player_settings_controller.dart:63-66'},
    'portraitDanmakuMode': {'v3': "'followGlobal'", 'v3src': 'player_settings_controller.dart:68'},
    'portraitFullscreenSwipeSwitch': _new('A07.2 c14、A07.3'),
    'portraitRoomOverrides': {
        'kind': 'same',
        'verdict': '3.x 在 Hive 里存 JSON 字符串 `\'{}\'`，v4 存映射；读 3.x 的字符串时解码（`JsonSetting`）',
    },
    'livePlayChatCollapsed': _new('A07.5 第 7 条，直播间里记住'),
    'roomSwitcherLayout': _new('A07.13 c4，D-022'),
    # ---- danmaku ----
    'danmakuTopArea': _danmaku('115', '0', '300'),
    'danmakuArea': _danmaku('116', '0', '1'),
    'danmakuBottomArea': _danmaku('117', '0', '300'),
    'danmakuSpeed': _danmaku('118', '20', '400', fixed=True),
    'danmakuFontSize': _danmaku('119', '10', '30', fixed=True),
    'danmakuFontWeight': _danmaku(
        '41-44、:120',
        '100',
        '900',
        fixed=True,
        note='3.x 还取整到整百（550 → 600），J01.3 加了同样的取整（`IntSetting` 的 `step: 100`）',
    ),
    'danmakuFontBorder': _danmaku('121', '0', '4'),
    'danmakuOpacity': _danmaku('122', '0', '1'),
    'danmakuListStyle': _new('A07.1，U.2a'),
    'showChatGifts': _new('A08.6 c3，B-21'),
    'danmakuPausedBehavior': _new('A07.10 c3'),
    'danmakuFps': _danmaku('123', '30', '240'),
    'holdDanmakuOnPress': {
        **_new('D03.4，V01.3'),
        'verdict': 'v4 新加（D03.4，V01.3，D-036）：默认关，画面弹幕和以前一样；开了以后按住一条飞行弹幕时它停住',
    },
    'danmakuMaxVisibleCount': {
        **_new('D05.2，V01.4'),
        'v3range': '3.x 没有这个设置，直播间和多画面写死 48',
        'verdict': 'v4 新加（D05.2，V01.4，D-036）：默认 48 和 3.x 一样；10～120，超出范围（上游电视版存 0 表示按设备）读成 48',
    },
    'repeatedDanmakuWindowSeconds': {
        'v3range': f'1～30（`{_D}:259-261`，导入备份时）',
        'kind': 'fixed',
        'verdict': '注册表原来只有下限 1，3.x 导入时夹到 1～30、设置页滑块也是 1～30；补上 `max: 30`',
        'when': _FILTER_WHEN,
    },
    'collapseRepeatedDanmaku': {'when': _FILTER_WHEN},
    'enableDanmakuSimilarityFilter': {'v3': 'false', 'v3src': f'{_D}:39、:105-108', 'when': _FILTER_WHEN},
    'savedDanmakuTemplate': {
        'reads': '弹幕设置的“模板”本身（`shared/danmaku/danmaku_settings_content.dart`、`danmaku_templates.dart`）',
        'when': '立即',
    },
    'enablePipDanmaku': {'v3': 'true', 'v3src': f'{_D}:17、:79'},
    'pipDanmakuColor': {'v3range': '不限'},
    'pipDanmakuFontSize': _danmaku('272-274', '8', '24', fixed=True, note='3.x 在导入备份时夹，设置页滑块同样 8～24'),
    'pipDanmakuFontWeight': _danmaku('124、:275', '100', '900', fixed=True, note='取整到整百同上（J01.3）'),
    'pipDanmakuSpeed': _danmaku('276-278', '20', '400', fixed=True),
    'pipDanmakuOpacity': {
        'v3range': f'0.1～1（`{_D}:279-281`）',
        'kind': 'fixed',
        'verdict': '注册表原来是 0～1，3.x 导入时和设置页滑块都是 0.1～1；下限改成 0.1（0 会让小窗弹幕完全看不见）',
    },
    'pipDanmakuArea': {
        'v3range': f'0.1～1（`{_D}:282-284`）',
        'kind': 'fixed',
        'verdict': '注册表原来是 0～1，3.x 导入时和设置页滑块都是 0.1～1；下限改成 0.1',
    },
    'pipDanmakuMaxVisibleCount': {
        'v3range': f'1～20（`{_D}:285-287`）',
        'kind': 'fixed',
        'verdict': '注册表原来只有下限 1，3.x 导入时和设置页加减都是 1～20；补上 `max: 20`',
    },
    'pipDanmakuEmitInterval': _danmaku('288-290', '0.05', '2', fixed=True),
    'pipDanmakuFps': {
        **_danmaku('291', '15', '240', fixed=True),
        'ui': '滑块 15～240（`playback_tiles.dart` 的 `PipFpsTile`）',
    },
    'filterDouyuSuspectedAutomatedMessages': {
        'v3': 'false',
        'v3src': f'{_D}:35、:99-102',
        'when': '立即（斗鱼弹幕每条消息都读）',
    },
    'danmakuSimilarityThreshold': {'v3range': f'50～100（`{_D}:125`）', 'ui': f'滑块 50～100（{_BLOCK}）', 'when': _FILTER_WHEN},
    'danmakuSimilarityCacheDuration': {'v3range': f'1～60（`{_D}:126`）', 'ui': f'滑块 1～60（{_BLOCK}）', 'when': _FILTER_WHEN},
    'danmakuSimilarityMaxCacheSize': {'v3range': f'20～1000（`{_D}:127`）', 'ui': f'滑块 20～1000（{_BLOCK}）', 'when': _FILTER_WHEN},
    'youtubeShowAllChat': _new('UPGRADES B-13'),
    # ---- volume ----
    'defaultMobileVolume': {
        'v3range': '0～1（`volume_settings_controller.dart:103-106`）',
        'verdict': '直播间里手机音量固定 1、只有多画面读它，和 3.x 一样（3.x 的适配器在手机上强制 1.0，见 G05 说明）',
    },
    'defaultDesktopVolume': {'v3range': '0～1（同上）'},
    'roomVolumes': {
        'kind': 'same',
        'verdict': '3.x 在 Hive 里存 JSON 字符串 `\'{}\'`，v4 存映射；每个房间的值读出时夹到 0～1（`live_player` 的 `roomVolume`）',
    },
    # ---- room card ----
    'room_card_mobile_preset': {'v3': "'normal'", 'v3src': 'room_card_settings_controller.dart:15、:251'},
    'room_card_desktop_preset': {'v3': "'normal'", 'v3src': 'room_card_settings_controller.dart:252'},
    'room_card_mobile_config': {
        'v3': {},
        'v3src': 'room_card_settings_controller.dart:253-259',
        'kind': 'same',
        'verdict': '3.x 没存时用预设的外观（`_storedPresetFallback`），v4 的空映射同样表示“用预设”',
    },
    'room_card_desktop_config': {
        'v3': {},
        'v3src': 'room_card_settings_controller.dart:260-266',
        'kind': 'same',
        'verdict': '同上',
    },
    # ---- page ----
    'page_default_size': {
        'v3': '12',
        'v3src': 'page_settings_controller.dart:17、:23-34（宽于 960 逻辑像素是 20）',
        'v3range': '1～100 且必须是可选的条数之一，否则取第一个（`page_settings_controller.dart:9-10`、:51-62）',
        'kind': 'approved',
        'verdict': 'v4 默认 0 = 由界面按宽度定（`shared/rooms/paging.dart` 的 `pageSizesOf`，结果和 3.x 一样是 12 或 20），'
        'J02.1 有意差异（纯 Dart 包拿不到屏幕宽度）；3.x 读到 v4 备份里的 0 时取可选条数的第一个，同样是 12 或 20',
    },
    'page_size_options_raw': {
        'verdict': '空 = 按宽度用 3.x 的默认可选条数（12/24/36/48 或 20/40/60/80），和 3.x 一样',
    },
    # ---- refresh ----
    'autoRefreshInterval': {
        'v3range': '5～360（`refresh_config_controller.dart:6-14`）',
        'ui': '选项 5～360 分钟，12 档',
        'when': '立即（重排定时器）',
    },
    'autoRefreshFavorite': {'when': '立即（重排定时器）'},
    'maxConcurrentRefresh': {'v3range': '1～20（`refresh_config_controller.dart:9-18`）'},
    'thumbnailRefreshInterval': {
        'v3range': '5～360（`refresh_config_controller.dart:6-14`）',
        'ui': '选项 5～360 分钟，8 档',
        'reads': '封面刷新定时器 `features/settings/data_tools.dart` 的 `CoverRefreshTimer`（启动时接上，F-APP-20）',
        'when': '立即',
    },
    'autoRefreshThumbnails': {
        'reads': '同上（`CoverRefreshTimer`）',
        'when': '立即',
    },
    # ---- iptv ----
    'autoSyncHoursInterval': {'v3range': '2～72（`iptv_settings_controller.dart:7-12`）', 'ui': '网络电视页的选项'},
    'm3uDirectory': {'verdict': '3.x 的默认值就是这个字面量；3.x 也没有读取它的代码'},
    # ---- proxy ----
    'proxyPort': {
        'v3': '7897',
        'v3src': '`proxy_settings_controller.dart:9、:13`，`core/common/proxy_routing.dart:1`',
        'v3range': '1～65535，越界回到 7897（`core/common/proxy_routing.dart:2-9`）',
        'ui': '代理对话框的数字框',
        'kind': 'fixed',
        'verdict': f'默认值和范围一样；越界时 3.x 回到 7897，v4 原来夹到 1 或 65535，{_RESET}',
        'when': '下一个请求（每个请求都读）',
    },
    'appProxyPort': {
        'v3': '7897',
        'v3src': 'proxy_settings_controller.dart:18',
        'v3range': '同上',
        'ui': '代理对话框的数字框',
        'kind': 'fixed',
        'verdict': f'同上，{_RESET}',
        'when': '下一个请求（每个请求都读）',
    },
    'enableProxy': {'when': '下一个请求（每个请求都读）'},
    'proxyHost': {'when': '下一个请求（每个请求都读）'},
    'enableAppProxy': {'when': '下一个请求（每个请求都读）'},
    'appProxyHost': {'when': '下一个请求（每个请求都读）'},
    # ---- window ----
    'window_width': {'v3range': '400～16384（`window_size_controller.dart:97-101`、:320-324）', 'ui': '窗口大小对话框'},
    'window_height': {'v3range': '300～16384（同上）', 'ui': '窗口大小对话框'},
    'windows_pip_width': {
        'v3range': '0～16384；宽或高 ≤ 0 时四个都归零（`window_size_controller.dart:277-313`）',
        'kind': 'fixed',
        'verdict': '注册表原来不限；补上 3.x 的 0～16384（只有 Windows 用）。“宽或高 ≤ 0 时都归零”在读的地方做（`mini_window.dart` 只在宽高都大于 0 时恢复）',
    },
    'windows_pip_height': {
        'v3range': '同上',
        'kind': 'fixed',
        'verdict': '同上',
    },
    'windows_pip_x': {'v3range': '不限'},
    'windows_pip_y': {'v3range': '不限'},
    # ---- exit ----
    'exitChoose': {'v3': "'exit'", 'v3src': 'exit_settings_controller.dart:10、:24'},
    'autoShutDownTime': {
        'v3': '120',
        'v3src': 'exit_settings_controller.dart:13、:25',
        'v3range': '1～525600（`exit_settings_controller.dart:13-17`）',
        'ui': '数字对话框',
        'reads': '定时退出 `features/settings/settings_editors.dart` 的 `AutoExitTimer`（设置页打开时接上，F-APP-21）',
        'when': '立即（重新计时）',
    },
    'enableAutoShutDownTime': {
        'reads': '同上（`AutoExitTimer`）',
        'when': '立即',
    },
    # ---- recorder ----
    'segmentTime': {'v3range': f'60～3600（`{_REC}:56-57`）', 'ui': f'滑块 1～60 分钟（{_RECORD_PAGE}）'},
    'maxTaskCount': {'v3range': f'1～10（`{_REC}:58-59`）', 'ui': f'加减 1～10（{_RECORD_PAGE}）'},
    'maxCacheMB': {'v3range': f'≥ 1（`{_REC}:60`、:76）', 'ui': f'数字对话框（{_RECORD_PAGE}）'},
    'recordSavePath': {'v3': "''", 'v3src': f'{_REC}:142'},
    'default_quality': {'v3': "'原画'", 'v3src': f'{_REC}:151-152'},
    'max_retry_count': {'v3range': f'1～20（`{_REC}:61-62`）', 'ui': f'滑块 1～20（{_RECORD_PAGE}）'},
    'retry_delay': {'v3range': f'5～120（`{_REC}:63-64`）', 'ui': f'滑块 5～120（{_RECORD_PAGE}）'},
    'live_check_interval': {'v3range': f'10～300（`{_REC}:65-66`）', 'ui': f'滑块 10～300（{_RECORD_PAGE}）'},
    'max_check_interval': {'v3range': f'300～3600（`{_REC}:67-68`）', 'ui': f'滑块 5～60 分钟（{_RECORD_PAGE}）'},
    'recorder_rw_timeout': {
        'v3range': f'15 / 30 / 60，别的值回到 15（`{_REC}:69`、:86）',
        'ui': f'选项 15 / 30 / 60（{_RECORD_PAGE}）',
        'verdict': '注册表夹到 15～60，`live_record` 的 `RecordSettings` 再按 3.x 只认 15 / 30 / 60（`packages/live_record/lib/src/settings.dart:45`），结果一样',
    },
    'recorder_thread_queue_size': {
        'v3range': f'512 / 1024 / 2048 / 4096 / 8192，别的值回到 2048（`{_REC}:70`、:88-89）',
        'ui': f'选项（{_RECORD_PAGE}）',
        'verdict': '同上，`RecordSettings` 按 3.x 只认这 5 个（`settings.dart:46`）',
    },
    # ---- local interaction ----
    'localInteraction.userName': {'v3range': f'最多 20 个字（`{_LOCAL}:821-824`）', 'verdict': 'v4 保存时同样截到 20 个字'},
    'localInteraction.previewPlatform': {'v3': "'bilibili'", 'v3src': f'{_LOCAL}:93'},
    'localInteraction.coins': {'v3range': '不限', 'verdict': 'v4 下限 0（3.x 送礼前检查余额，不会存负数），没有实际差别'},
    'localInteraction.experience': {'v3range': '不限', 'verdict': '同上'},
    'localInteraction.history': {'v3range': f'最多 30 条（`{_LOCAL}:907`）'},
    'localInteraction.danmakuFontSize': {'v3range': f'14～32（`{_LOCAL}:745`）', 'ui': f'滑块 14～32（{_LOCAL_PANEL}）'},
    'localInteraction.danmakuSpeed': {'v3range': f'60～260（`{_LOCAL}:746`）', 'ui': f'滑块 60～260（{_LOCAL_PANEL}）'},
    'localInteraction.danmakuFontWeight': {'v3range': f'400～900（`{_LOCAL}:747`）'},
    'localInteraction.danmakuStrokeWidth': {
        'v3range': f'画的时候 0.5～4（`{_LOCAL}:749`）',
        'ui': f'滑块 0.5～4（{_LOCAL_PANEL}）',
        'verdict': '存的值 3.x 不限、画的时候夹到 0.5～4；v4 存的值夹到 0～4，画的时候同样夹到 0.5～4（`local_interaction.dart` 的样式）',
    },
    'localInteraction.danmakuOpacity': {'v3range': f'0.35～1（`{_LOCAL}:753`）', 'ui': f'滑块 0.35～1（{_LOCAL_PANEL}）'},
    'localInteraction.danmakuLetterSpacing': {'v3range': f'-0.5～3（`{_LOCAL}:754`）', 'ui': f'滑块 -0.5～3（{_LOCAL_PANEL}）'},
    'localInteraction.danmakuShadowBlur': {'v3range': f'0～6（`{_LOCAL}:758`）', 'ui': f'滑块 0～6（{_LOCAL_PANEL}）'},
    'localInteraction.danmakuShadowOffset': {'v3range': f'0～4（`{_LOCAL}:759`）', 'ui': f'滑块 0～4（{_LOCAL_PANEL}）'},
    'localInteraction.danmakuFixedDurationMs': {
        'v3range': f'2000～10000（`{_LOCAL}:760`）',
        'ui': f'滑块 2000～10000（{_LOCAL_PANEL}）',
    },
    # ---- backup, cache, log, accounts, meta ----
    'downloadDirectoryPath': {
        'v3': "''",
        'v3src': 'cache_controller.dart:108、:124-130',
    },
    'downloadDirectoryDecisionMade': {
        'v3': 'false',
        'v3src': 'cache_controller.dart:112、:132-138',
    },
    'enableLocalLog': _new('I01.3；3.x 的开关只管当次运行、默认关'),
    'logLevel': _new('I01.3'),
    'bilibiliUid': {'v3range': '不限'},
    'douyuCookieSavedAt': {'v3range': '不限'},
    'remote_sync_device_id': {
        'v3': "''",
        'v3src': 'modules/remote_receiver/remote_sync_service.dart:134-143（第一次用时生成）',
    },
    'uiMode': _new('X03.1（M14.1），本机记录'),
    'tvFocusZoom': _new('A17.1 c2'),
}

V3_ONLY_NOTE = (
    '3.x 用 `hive*` 存、v4 不作为设置的键共 20 个：8 个 `<平台>Cookie` 和 `douyuLtp0`、`douyuDid` '
    '进加密的 `SecretStore`；`favoriteRooms`、`favoriteAreas`、`historyRooms`、`shieldList`、`blockedDanmakuUsers`、'
    '`webDavConfigs`、`currentWebDavConfig` 进各自的存储；`audienceMetricMigration`、`danmakuInteractionMigration`、'
    '`siteCatalogMigration` 是 3.x 的迁移标记。另有 `enableHighRefreshRate`（换成 `refreshRateMode`）、`recorder_tasks`、'
    '`record_history`、`cached_area_pics` 等不经 `hive*` 的键，见功能清点（`docs/inventory/FEATURES.md`）第 15 节，'
    '都在 `packages/live_store/lib/src/legacy/legacy_snapshot.dart` 导入到别处或有意丢掉。'
)
