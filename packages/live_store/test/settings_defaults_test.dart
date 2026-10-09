import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

// J01.2: every setting's default and range against 3.x (v3.2.11). The
// per-setting table with the 3.x file:line of each value is the task's
// settings.md (written by tools/docs/settings_audit.py). A setting added
// later must be added here, as carried over from 3.x or as new in v4.

/// What a fresh 3.x install on an Android phone gets for each key v4 kept,
/// with 3.x's constants and expressions worked out. Values are as 3.x stored
/// them (the per-room maps were JSON strings).
const Map<String, Object> v3Defaults = {
  'autoRefreshTime': 3,
  'enableDenseFavorites': true,
  'enableBackgroundPlay': false,
  'enableAsmrSleepMode': false,
  'asmrSleepMinutes': 60,
  'enableRotateScreen': false,
  'enableScreenKeepOn': true,
  'enableAutoCheckUpdate': true,
  'useGitHubOriginForUpdates': false,
  'enableFullScreenDefault': false,
  'showSplashPage': true,
  'refreshRateMode': 'powerSaving',
  'preferRealOnlineCounts': false,
  'realOnlinePlatforms': ['douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'acfun', 'picarto', 'twitcasting'],
  'savedMenuIds': ['favorites', 'popular', 'areas', 'record'],
  'enableMultiView': true,
  'enableNewWindowPlay': true,
  'hotAreasList': [
    'bilibili',
    'douyu',
    'huya',
    'douyin',
    'kuaishou',
    'cc',
    'twitch',
    'soop',
    'yy',
    'acfun',
    'picarto',
    'twitcasting',
    'missevan',
    'inke',
    'kilakila',
    'xiaohongshu',
    'niconico',
    'weibo',
    'showroom',
    'chzzk',
    'liveme',
    'tiktok',
    'youtube',
    'bigo',
    'pandalive',
    'fc2live',
    'steambroadcast',
    'jdlive',
    'kugoulive',
    'baidulive',
    'sixroom',
    'looklive',
    '17live',
    'iptv',
  ],
  'preferPlatform': 'bilibili',
  'historyLimit': 50,
  'themeMode': 'System',
  'enableDynamicTheme': false,
  'themeColorSwitch': 'FF2196F3',
  'language': '简体中文',
  'crossAxisSpacing': 6,
  'mainAxisSpacing': 6,
  'loadingStyle': 'default',
  'loadingStyleColorSwitch': '',
  'textScaleFactor': 1.0,
  'fontSizeBodySmall': 12.0,
  'fontSizeBodyMedium': 13.0,
  'fontSizeBodyLarge': 14.0,
  'fontSizeTitleMedium': 15.0,
  'fontSizeTitleLarge': 20.0,
  'fontFamilyName': 'Default',
  'fontFamilyFileName': '',
  'danmakuFontFamilyFileName': '',
  'videoFitIndex': 0,
  'videoPlayerKey': 'mpv',
  'preferResolution': '原画',
  'preferResolutionCellular': '原画',
  'enableCodec': true,
  'playerCompatMode': false,
  'customPlayerOutput': false,
  'videoOutputDriver': 'gpu',
  'audioOutputDriver': 'auto',
  'videoHardwareDecoder': 'auto',
  'floatPlay': false,
  'windowsPipAlwaysOnTop': false,
  'enableRtxVsr': false,
  'useHardStopOnExit': false,
  'enablePortraitStreamAdaptation': true,
  'portraitAdaptiveHeight': true,
  'portraitLayoutMode': 'balanced',
  'portraitFullscreenPolicy': 'followSource',
  'portraitFullscreenDisplayMode': 'ambient',
  'portraitPipFollowSource': true,
  'portraitDanmakuMode': 'followGlobal',
  'rememberPortraitRoomOverride': true,
  'showPortraitDiagnostics': false,
  'portraitRoomOverrides': '{}',
  'hideDanmaku': false,
  'noEmojiMode': false,
  'danmakuTopArea': 0.0,
  'danmakuArea': 1.0,
  'danmakuBottomArea': 0.5,
  'danmakuSpeed': 120.0,
  'danmakuFontSize': 16.0,
  'danmakuFontWeight': 500,
  'danmakuFontBorder': 1.5,
  'danmakuOpacity': 1.0,
  'enableDanmakuDisplay': true,
  'enableDanmakuStroke': true,
  'danmakuFps': 60,
  'danmakuAutoFps': true,
  'enableDanmakuTapInteraction': true,
  'enableDanmakuLongPressInteraction': true,
  'collapseRepeatedDanmaku': false,
  'repeatedDanmakuWindowSeconds': 5,
  'savedDanmakuTemplate': '',
  'danmakuFontFamilyName': 'Default',
  'enablePipDanmaku': true,
  'pipDanmakuAutoScale': true,
  'pipDanmaNoEmojiMode': false,
  'pipDanmakuUseOriginalColor': true,
  'pipDanmakuColor': 0xFFFFFFFF,
  'pipDanmakuFontSize': 12.0,
  'pipDanmakuFontWeight': 500,
  'pipDanmakuSpeed': 90.0,
  'pipDanmakuOpacity': 0.9,
  'pipDanmakuArea': 0.5,
  'pipDanmakuMaxVisibleCount': 6,
  'pipDanmakuEmitInterval': 0.35,
  'pipDanmakuFps': 30,
  'pipDanmakuAutoFps': true,
  'filterDouyuSuspectedAutomatedMessages': false,
  'enableDanmakuSimilarityFilter': false,
  'danmakuSimilarityThreshold': 85,
  'danmakuSimilarityCacheDuration': 3,
  'danmakuSimilarityMaxCacheSize': 100,
  'defaultMobileVolume': 0.5,
  'defaultDesktopVolume': 1.0,
  'globalVolumeMute': false,
  'roomVolumes': '{}',
  'room_card_mobile_preset': 'normal',
  'room_card_desktop_preset': 'normal',
  'room_card_mobile_config': <String, Object?>{},
  'room_card_desktop_config': <String, Object?>{},
  'page_show_size_selector': true,
  'page_show_goto_button': true,
  'page_show_scroll_top': true,
  'page_default_size': 12,
  'page_size_options_raw': '',
  'autoRefreshFavorite': false,
  'refreshFavoriteOnResume': true,
  'autoRefreshInterval': 30,
  'maxConcurrentRefresh': 4,
  'autoRefreshThumbnails': false,
  'thumbnailRefreshInterval': 30,
  'selectedSourceName': '',
  'selectedSourceId': '',
  'isAutoSyncEnabled': false,
  'autoSyncHoursInterval': 24,
  'customIptvUserAgent': '',
  'm3uDirectory': 'm3uDirectory',
  'enableProxy': false,
  'proxyHost': '',
  'proxyPort': 7897,
  'enableAppProxy': false,
  'appProxyHost': '',
  'appProxyPort': 7897,
  'window_width': 1280,
  'window_height': 720,
  'rememberPipPosition': true,
  'windows_pip_display_id': '',
  'windows_pip_width': 0.0,
  'windows_pip_height': 0.0,
  'windows_pip_x': 0.0,
  'windows_pip_y': 0.0,
  'dontAskExit': false,
  'exitChoose': 'exit',
  'autoShutDownTime': 120,
  'enableAutoShutDownTime': false,
  'enableStartUp': true,
  'segmentTime': 300,
  'maxTaskCount': 3,
  'autoReconnect': true,
  'maxCacheMB': 1024,
  'enableCacheLimit': false,
  'recordSavePath': '',
  'default_quality': '原画',
  'max_retry_count': 5,
  'retry_delay': 30,
  'enable_polling': false,
  'live_check_interval': 30,
  'enable_backoff': false,
  'max_check_interval': 300,
  'auto_start_on_boot': false,
  'recorder_prefer_best_stream': true,
  'recorder_rw_timeout': 15,
  'recorder_thread_queue_size': 2048,
  'recorder_folder_naming_strategy': false,
  'recorder_record_danmaku': false,
  'localInteraction.enabled': true,
  'localInteraction.userName': 'Pure Live',
  'localInteraction.title': 'listener',
  'localInteraction.showAsDanmaku': true,
  'localInteraction.showPlatformBadge': true,
  'localInteraction.showLevelBadge': true,
  'localInteraction.enableGiftEffects': true,
  'localInteraction.previewPlatform': 'bilibili',
  'localInteraction.coins': 1000,
  'localInteraction.experience': 0,
  'localInteraction.history': [],
  'localInteraction.danmakuPreset': 'clean',
  'localInteraction.danmakuColor': 0xFFFFFFFF,
  'localInteraction.danmakuFontSize': 19.0,
  'localInteraction.danmakuSpeed': 130.0,
  'localInteraction.danmakuFontWeight': 600,
  'localInteraction.danmakuShowStroke': true,
  'localInteraction.danmakuStrokeWidth': 1.5,
  'localInteraction.danmakuPlacement': 'scroll',
  'localInteraction.danmakuFontFamily': 'system',
  'localInteraction.danmakuItalic': false,
  'localInteraction.danmakuOpacity': 1.0,
  'localInteraction.danmakuLetterSpacing': 0.0,
  'localInteraction.danmakuStrokeColor': 0xFF000000,
  'localInteraction.danmakuShowShadow': false,
  'localInteraction.danmakuShadowColor': 0xFF000000,
  'localInteraction.danmakuShadowBlur': 2.0,
  'localInteraction.danmakuShadowOffset': 1.0,
  'localInteraction.danmakuFixedDurationMs': 4000,
  'backupDirectory': '',
  'downloadDirectoryPath': '',
  'downloadDirectoryDecisionMade': false,
  'bilibiliUid': 0,
  'douyuCookieSavedAt': 0,
  'remote_sync_device_id': '',
};

/// Confirmed changes from 3.x's default: key -> (v4 default, why).
const Map<String, (Object, String)> changedDefaults = {
  // UPGRADES X-1 (E group M4.34): Kick is supported again, after chzzk.
  'hotAreasList': (_withKick, 'UPGRADES X-1'),
  // A11.2 C-3: the brand blue; 3.x's default blue moves to it once.
  'themeColorSwitch': ('FF2E6FE0', 'A11.2 C-3'),
  // J02.1: 0 = by the screen width (12, or 20 above 960 px), as 3.x worked
  // out on its first start; a pure Dart package has no screen.
  'page_default_size': (0, 'J02.1'),
};

const List<String> _withKick = [
  'bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'yy', 'acfun', 'picarto', //
  'twitcasting', 'missevan', 'inke', 'kilakila', 'xiaohongshu', 'niconico', 'weibo', 'showroom', 'chzzk', //
  'kick', 'liveme', 'tiktok', 'youtube', 'bigo', 'pandalive', 'fc2live', 'steambroadcast', 'jdlive', //
  'kugoulive', 'baidulive', 'sixroom', 'looklive', '17live', 'iptv',
];

/// Settings v4 added (no 3.x key) and their defaults, with the task.
const Map<String, Object> newInV4 = {
  'skippedUpdateVersion': '', // A06.3
  'matchVideoFrameRate': true, // R02.1
  'showUnplayableInDiscover': false, // UPGRADES unified rule, J02.1
  'detectClipboardRooms': true, // O03.2 (3.x always looked)
  'douyuForceRenew': false, // UPGRADES 2-1
  'twitchLanguages': <String>[], // UPGRADES 8-3
  'pureBlackTheme': false, // A11.2 C-4
  'themeColorMigration': 0, // A11.2
  'preferH264': true, // UPGRADES 22-3
  'autoPipOnLeave': false, // A07.8
  'floatWindowSize': 'medium', // A07.22 (V01.5; A07.8 c6's size)
  'floatWindowLandscapeScale': 1.0, // A07.22: 1 = not resized
  'floatWindowPortraitScale': 1.0, // A07.22
  'portraitFullscreenSwipeSwitch': false, // A07.2, A07.3
  'livePlayChatCollapsed': false, // A07.5
  'roomSwitcherLayout': 'grid', // A07.13, D-022
  'danmakuListStyle': 'compact', // A07.1
  'showChatGifts': true, // A08.6
  'showChatNames': true, // A08.10: names shown, as 3.x
  'danmakuListFontSize': 0, // A08.15: the theme's body size, as before (D-040)
  'danmakuListLineSpacing': 'standard', // A08.15: the gaps as before
  'chatGiftsAboveTier': false, // A08.12 (every gift, as before; D-040)
  'giftValueInYuan': false, // A08.12 (the platform's units, as before)
  'danmakuShowGifts': false, // A08.12 (no gift flies, as before)
  'danmakuPausedBehavior': 'pause', // A07.10
  'danmakuMaxVisibleCount': 48, // D05.2 (V01.4; 3.x's fixed 48)
  'holdDanmakuOnPress': true, // D03.4 (V01.3), on by default (D-039)
  'liveAlertEnabled': false, // O01.1 (V01.1; off: no notification as before)
  'liveAlertTagIds': <String>[], // O01.1 (every follow)
  'blockEmoteOnlyDanmaku': false, // D02.2 (V03.6 E11; off as before, D-040)
  'blockLongDanmaku': false, // D02.2
  'blockLongDanmakuLength': 30, // D02.2
  'youtubeShowAllChat': false, // UPGRADES B-13
  'enableLocalLog': false, // I01.3
  'logLevel': 'info', // I01.3
  'uiMode': 'auto', // X03.1
  'tvFocusZoom': true, // A17.1
  'localInteraction.replayOnEnter': true, // D08.1 c6, on by default (D-040)
  'localInteraction.phrases': <String>[], // D08.2: none until one is saved (D-040)
  'recordDanmakuGifts': false, // H01.8: the chat file without gifts, as before (D-040)
};

/// The range of every number setting: 3.x's clamps on start and on a backup
/// import, which are also its settings pages' sliders. Null: no bound.
const Map<String, (num?, num?)> ranges = {
  'autoRefreshTime': (null, null), // 3.x never read it
  'asmrSleepMinutes': (1, 525600),
  'historyLimit': (0, null), // 0 keeps everything
  'themeColorMigration': (null, null),
  'crossAxisSpacing': (0, 64),
  'mainAxisSpacing': (0, 64),
  'textScaleFactor': (0.5, 2),
  'fontSizeBodySmall': (9, 15),
  'fontSizeBodyMedium': (11, 17),
  'fontSizeBodyLarge': (12, 18),
  'fontSizeTitleMedium': (13, 20),
  'fontSizeTitleLarge': (16, 26),
  'videoFitIndex': (0, 5),
  'floatWindowLandscapeScale': (0.25, 4), // A07.22: the window's own bounds apply on top
  'floatWindowPortraitScale': (0.25, 4),
  'danmakuTopArea': (0, 300),
  'danmakuArea': (0, 1),
  'danmakuBottomArea': (0, 300),
  'danmakuSpeed': (20, 400),
  'danmakuFontSize': (10, 30),
  'danmakuFontWeight': (100, 900),
  'danmakuFontBorder': (0, 4),
  'danmakuOpacity': (0, 1),
  'danmakuFps': (30, 240),
  'danmakuMaxVisibleCount': (10, 120), // D05.2: out of range reads as 48
  'danmakuListFontSize': (12, 22), // A08.15: out of range (and 0) reads as 0, the theme's size
  'repeatedDanmakuWindowSeconds': (1, 30),
  'pipDanmakuColor': (null, null),
  'pipDanmakuFontSize': (8, 24),
  'pipDanmakuFontWeight': (100, 900),
  'pipDanmakuSpeed': (20, 400),
  'pipDanmakuOpacity': (0.1, 1),
  'pipDanmakuArea': (0.1, 1),
  'pipDanmakuMaxVisibleCount': (1, 20),
  'pipDanmakuEmitInterval': (0.05, 2),
  'pipDanmakuFps': (15, 240),
  'danmakuSimilarityThreshold': (50, 100),
  'danmakuSimilarityCacheDuration': (1, 60),
  'danmakuSimilarityMaxCacheSize': (20, 1000),
  'blockLongDanmakuLength': (10, 100), // D02.2
  'defaultMobileVolume': (0, 1),
  'defaultDesktopVolume': (0, 1),
  'page_default_size': (0, 100), // 0 = by width (J02.1); 3.x 1..100
  'autoRefreshInterval': (5, 360),
  'maxConcurrentRefresh': (1, 20),
  'thumbnailRefreshInterval': (5, 360),
  'autoSyncHoursInterval': (2, 72),
  'proxyPort': (1, 65535),
  'appProxyPort': (1, 65535),
  'window_width': (400, 16384),
  'window_height': (300, 16384),
  'windows_pip_width': (0, 16384),
  'windows_pip_height': (0, 16384),
  'windows_pip_x': (null, null),
  'windows_pip_y': (null, null),
  'autoShutDownTime': (1, 525600),
  'segmentTime': (60, 3600),
  'maxTaskCount': (1, 10),
  'maxCacheMB': (1, null),
  'max_retry_count': (1, 20),
  'retry_delay': (5, 120),
  'live_check_interval': (10, 300),
  'max_check_interval': (300, 3600),
  'recorder_rw_timeout': (15, 60), // only 15, 30 or 60: live_record's RecordSettings
  'recorder_thread_queue_size': (512, 8192), // only powers of two: RecordSettings
  'localInteraction.coins': (0, null),
  'localInteraction.experience': (0, null),
  'localInteraction.danmakuColor': (null, null),
  'localInteraction.danmakuFontSize': (14, 32),
  'localInteraction.danmakuSpeed': (60, 260),
  'localInteraction.danmakuFontWeight': (400, 900),
  'localInteraction.danmakuStrokeWidth': (0, 4), // drawn at 0.5..4, as 3.x
  'localInteraction.danmakuOpacity': (0.35, 1),
  'localInteraction.danmakuLetterSpacing': (-0.5, 3),
  'localInteraction.danmakuStrokeColor': (null, null),
  'localInteraction.danmakuShadowColor': (null, null),
  'localInteraction.danmakuShadowBlur': (0, 6),
  'localInteraction.danmakuShadowOffset': (0, 4),
  'localInteraction.danmakuFixedDurationMs': (2000, 10000),
  'bilibiliUid': (null, null),
  'douyuCookieSavedAt': (null, null),
};

void main() {
  test('every setting is either carried over from 3.x or new in v4', () {
    final keys = {for (final setting in Settings.all) setting.key};
    expect(keys, hasLength(Settings.all.length));
    expect({...v3Defaults.keys, ...newInV4.keys}, keys);
    expect(v3Defaults.keys.toSet().intersection(newInV4.keys.toSet()), isEmpty);
  });

  test("a setting carried over from 3.x defaults to 3.x's value", () {
    for (final MapEntry(:key, :value) in v3Defaults.entries) {
      final setting = Settings.byKey(key)!;
      final v3 = setting.decode(value);
      expect(v3, isNotNull, reason: '$key: 3.x default $value does not fit');
      if (changedDefaults[key] case (final v4, _)) {
        expect(setting.defaultValue, isNot(v3), reason: '$key is listed as changed');
        expect(setting.defaultValue, v4, reason: key);
      } else {
        expect(setting.defaultValue, v3, reason: key);
      }
    }
  });

  test('a setting new in v4 defaults to what its task decided', () {
    for (final MapEntry(:key, :value) in newInV4.entries) {
      expect(Settings.byKey(key)!.defaultValue, value, reason: key);
    }
  });

  test('number settings are bounded as 3.x bounded them', () {
    final numbers = [
      for (final setting in Settings.all)
        if (setting is IntSetting || setting is DoubleSetting) setting.key,
    ];
    expect(ranges.keys.toSet(), numbers.toSet());
    for (final MapEntry(:key, value: (low, high)) in ranges.entries) {
      final setting = Settings.byKey(key)!;
      final (min, max) = switch (setting) {
        final IntSetting s => (s.min, s.max),
        final DoubleSetting s => (s.min, s.max),
        _ => throw StateError(key),
      };
      expect((min, max), (low, high), reason: key);
      expect(setting.read(setting.defaultValue), setting.defaultValue, reason: '$key: the default is in range');
    }
  });
}
