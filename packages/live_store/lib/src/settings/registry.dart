import 'package:live_store/src/settings/setting.dart';
import 'package:live_store/src/settings/values.dart';

/// The settings registry (spec/modules/store.md §5).
///
/// Ids follow `<group>.<name>`; each entry lists the 3.x Hive keys and old
/// backup field names it imports from (§1.5, §7.4). To add a setting, declare
/// a constant here and append it to [all]; backup, reset and import pick it
/// up from there.
abstract final class Settings {
  // Appearance.

  /// Theme mode.
  static const themeMode = EnumSetting<AppThemeMode>(
    'theme.mode',
    AppThemeMode.system,
    AppThemeMode.values,
    legacy: [LegacyKey('themeMode', convert: _themeMode)],
  );

  /// Pure black surfaces whenever the theme is dark (principles.md §2).
  static const pureBlack = BoolSetting('theme.pureBlack', false);

  /// Wallpaper / accent colour theming.
  static const dynamicColor = BoolSetting('theme.dynamicColor', false, legacy: [LegacyKey('enableDynamicTheme')]);

  /// UI language: `system`, `zh-Hans`, `zh-Hant` or `en` (store.md §6.4.2).
  static const locale = StringSetting(
    'theme.locale',
    'system',
    allowed: {'system', 'zh-Hans', 'zh-Hant', 'en'},
    legacy: [
      LegacyKey('language', convert: _locale),
      LegacyKey('languageName', convert: _locale),
    ],
  );

  /// In-app text size on top of the system scale (principles.md §2).
  static const textScale = DoubleSetting(
    'theme.textScale',
    1,
    min: 0.85,
    max: 1.3,
    legacy: [LegacyKey('textScaleFactor')],
  );

  /// Compact cards on the follow page (principles.md §4.3; 3.x default on).
  static const denseFollows = BoolSetting('app.denseFavorites', true, legacy: [LegacyKey('enableDenseFavorites')]);

  /// 3.x room card preset on phones; kept for import, v4 derives density.
  static const cardPresetMobile = EnumSetting<CardPreset>(
    'roomCard.mobilePreset',
    CardPreset.normal,
    CardPreset.values,
    legacy: [LegacyKey('room_card_mobile_preset')],
  );

  /// 3.x room card preset on desktops.
  static const cardPresetDesktop = EnumSetting<CardPreset>(
    'roomCard.desktopPreset',
    CardPreset.normal,
    CardPreset.values,
    legacy: [LegacyKey('room_card_desktop_preset')],
  );

  // General.

  /// First page after launch.
  static const startPage = EnumSetting<StartPage>('app.startPage', StartPage.follows, StartPage.values);

  /// Keep the screen on while playing.
  static const screenKeepOn = BoolSetting('app.screenKeepOn', true, legacy: [LegacyKey('enableScreenKeepOn')]);

  /// Check for updates automatically.
  static const autoCheckUpdate = BoolSetting('app.autoCheckUpdate', true, legacy: [LegacyKey('enableAutoCheckUpdate')]);

  /// Refresh-rate policy.
  static const refreshRateMode = EnumSetting<RefreshRateMode>(
    'app.refreshRateMode',
    RefreshRateMode.powerSaving,
    RefreshRateMode.values,
    scope: SettingScope.device,
    legacy: [
      LegacyKey('refreshRateMode'),
      LegacyKey('enableHighRefreshRate', convert: _highRefreshRate),
    ],
  );

  /// Prefer real online counts over popularity where a platform offers both.
  static const preferRealOnlineCounts = BoolSetting(
    'app.preferRealOnlineCounts',
    false,
    legacy: [LegacyKey('preferRealOnlineCounts')],
  );

  // Playback.

  /// Preferred quality on Wi-Fi and wired networks.
  static const qualityWifi = EnumSetting<QualityPreference>(
    'player.preferResolution',
    QualityPreference.original,
    QualityPreference.values,
    legacy: [LegacyKey('preferResolution', convert: _quality)],
  );

  /// Preferred quality on mobile networks.
  static const qualityMobile = EnumSetting<QualityPreference>(
    'player.preferResolutionCellular',
    QualityPreference.original,
    QualityPreference.values,
    legacy: [LegacyKey('preferResolutionCellular', convert: _quality)],
  );

  /// Hardware decoding (device scope: decoders differ per machine).
  static const hardwareDecoding = BoolSetting(
    'player.hardwareDecoding',
    true,
    scope: SettingScope.device,
    legacy: [LegacyKey('enableCodec')],
  );

  /// Video fit.
  static const videoFit = EnumSetting<VideoFit>(
    'player.fit',
    VideoFit.contain,
    VideoFit.values,
    legacy: [LegacyKey('videoFitIndex', convert: _videoFit)],
  );

  /// Keep playing audio in the background.
  static const backgroundPlay = BoolSetting('app.backgroundPlay', false, legacy: [LegacyKey('enableBackgroundPlay')]);

  /// Enter full screen when a room opens.
  static const fullScreenDefault = BoolSetting(
    'app.fullScreenDefault',
    false,
    legacy: [LegacyKey('enableFullScreenDefault')],
  );

  /// Default volume on phones and tablets (0–1).
  static const defaultMobileVolume = DoubleSetting(
    'volume.defaultMobileVolume',
    0.5,
    min: 0,
    max: 1,
    legacy: [LegacyKey('defaultMobileVolume')],
  );

  /// Default volume on desktops (0–1).
  static const defaultDesktopVolume = DoubleSetting(
    'volume.defaultDesktopVolume',
    1,
    min: 0,
    max: 1,
    legacy: [LegacyKey('defaultDesktopVolume')],
  );

  /// Mute every room.
  static const globalMute = BoolSetting('volume.globalVolumeMute', false, legacy: [LegacyKey('globalVolumeMute')]);

  // Danmaku.

  /// Danmaku enabled at all; off hides the button and skips the connection.
  static const danmakuEnabled = BoolSetting('danmaku.display', true, legacy: [LegacyKey('enableDanmakuDisplay')]);

  /// The player's show/hide toggle, remembered between rooms.
  static const danmakuHidden = BoolSetting('danmaku.hidden', false, legacy: [LegacyKey('hideDanmaku')]);

  /// Font size in logical pixels.
  static const danmakuFontSize = DoubleSetting(
    'danmaku.fontSize',
    16,
    min: 10,
    max: 30,
    legacy: [LegacyKey('danmakuFontSize')],
  );

  /// Font weight (100–900).
  static const danmakuFontWeight = IntSetting(
    'danmaku.fontWeight',
    500,
    min: 100,
    max: 900,
    legacy: [LegacyKey('danmakuFontWeight')],
  );

  /// Opacity (0–1).
  static const danmakuOpacity = DoubleSetting(
    'danmaku.opacity',
    1,
    min: 0,
    max: 1,
    legacy: [LegacyKey('danmakuOpacity')],
  );

  /// Scroll speed in logical pixels per second; larger is faster (as 3.2.x
  /// used it, ADR 0020).
  static const danmakuSpeed = DoubleSetting(
    'danmaku.speed',
    120,
    min: 20,
    max: 400,
    legacy: [LegacyKey('danmakuSpeed')],
  );

  /// Share of the video height danmaku may use (0–1).
  static const danmakuArea = DoubleSetting('danmaku.area', 1, min: 0, max: 1, legacy: [LegacyKey('danmakuArea')]);

  /// Top margin in logical pixels.
  static const danmakuTopArea = DoubleSetting(
    'danmaku.topArea',
    0,
    min: 0,
    max: 300,
    legacy: [LegacyKey('danmakuTopArea')],
  );

  /// Bottom margin in logical pixels.
  static const danmakuBottomArea = DoubleSetting(
    'danmaku.bottomArea',
    0.5,
    min: 0,
    max: 300,
    legacy: [LegacyKey('danmakuBottomArea')],
  );

  /// Draw an outline around text.
  static const danmakuStroke = BoolSetting('danmaku.stroke', true, legacy: [LegacyKey('enableDanmakuStroke')]);

  /// Outline width.
  static const danmakuStrokeWidth = DoubleSetting(
    'danmaku.strokeWidth',
    1.5,
    min: 0,
    max: 4,
    legacy: [LegacyKey('danmakuFontBorder')],
  );

  /// Hide emoji-only messages.
  static const danmakuNoEmoji = BoolSetting('danmaku.noEmoji', false, legacy: [LegacyKey('noEmojiMode')]);

  /// Frame rate follows the display.
  static const danmakuAutoFps = BoolSetting('danmaku.autoFps', true, legacy: [LegacyKey('danmakuAutoFps')]);

  /// Fixed frame rate when [danmakuAutoFps] is off.
  static const danmakuFps = IntSetting('danmaku.fps', 60, min: 30, max: 240, legacy: [LegacyKey('danmakuFps')]);

  /// Tapping a danmaku opens its actions.
  static const danmakuTapInteraction = BoolSetting(
    'danmaku.tapInteraction',
    true,
    legacy: [LegacyKey('enableDanmakuTapInteraction')],
  );

  /// Long-pressing a danmaku opens its actions.
  static const danmakuLongPressInteraction = BoolSetting(
    'danmaku.longPressInteraction',
    true,
    legacy: [LegacyKey('enableDanmakuLongPressInteraction')],
  );

  /// Merge repeated messages.
  static const danmakuCollapseRepeated = BoolSetting(
    'danmaku.collapseRepeated',
    false,
    legacy: [LegacyKey('collapseRepeatedDanmaku')],
  );

  /// Window for [danmakuCollapseRepeated], in seconds.
  static const danmakuRepeatedWindowSeconds = IntSetting(
    'danmaku.repeatedWindowSeconds',
    5,
    min: 1,
    max: 30,
    legacy: [LegacyKey('repeatedDanmakuWindowSeconds')],
  );

  /// Drop messages similar to recent ones.
  static const danmakuSimilarityFilter = BoolSetting(
    'danmaku.similarityFilter',
    false,
    legacy: [LegacyKey('enableDanmakuSimilarityFilter')],
  );

  /// Similarity threshold in percent.
  static const danmakuSimilarityThreshold = IntSetting(
    'danmaku.similarityThreshold',
    85,
    min: 50,
    max: 100,
    legacy: [LegacyKey('danmakuSimilarityThreshold')],
  );

  /// How long messages stay in the similarity cache, in seconds.
  static const danmakuSimilarityCacheDuration = IntSetting(
    'danmaku.similarityCacheDuration',
    3,
    min: 1,
    max: 60,
    legacy: [LegacyKey('danmakuSimilarityCacheDuration')],
  );

  /// Size of the similarity cache.
  static const danmakuSimilarityMaxCacheSize = IntSetting(
    'danmaku.similarityMaxCacheSize',
    100,
    min: 20,
    max: 1000,
    legacy: [LegacyKey('danmakuSimilarityMaxCacheSize')],
  );

  /// Hide Douyu messages that look automated.
  static const danmakuFilterDouyuAutomated = BoolSetting(
    'danmaku.filterDouyuAutomated',
    false,
    legacy: [LegacyKey('filterDouyuSuspectedAutomatedMessages')],
  );

  /// Danmaku in picture-in-picture.
  static const danmakuPipEnabled = BoolSetting('danmaku.pipEnabled', true, legacy: [LegacyKey('enablePipDanmaku')]);

  /// Hide emoji-only messages in picture-in-picture.
  static const danmakuPipNoEmoji = BoolSetting(
    'danmaku.pipNoEmojiMode',
    false,
    legacy: [LegacyKey('pipDanmakuNoEmojiMode'), LegacyKey('pipDanmaNoEmojiMode')],
  );

  /// Picture-in-picture font size.
  static const danmakuPipFontSize = DoubleSetting(
    'danmaku.pipFontSize',
    12,
    min: 8,
    max: 24,
    legacy: [LegacyKey('pipDanmakuFontSize')],
  );

  /// Picture-in-picture speed.
  static const danmakuPipSpeed = DoubleSetting(
    'danmaku.pipSpeed',
    90,
    min: 20,
    max: 400,
    legacy: [LegacyKey('pipDanmakuSpeed')],
  );

  /// Picture-in-picture opacity.
  static const danmakuPipOpacity = DoubleSetting(
    'danmaku.pipOpacity',
    0.9,
    min: 0.1,
    max: 1,
    legacy: [LegacyKey('pipDanmakuOpacity')],
  );

  /// Picture-in-picture area share.
  static const danmakuPipArea = DoubleSetting(
    'danmaku.pipArea',
    0.5,
    min: 0.1,
    max: 1,
    legacy: [LegacyKey('pipDanmakuArea')],
  );

  /// Picture-in-picture visible message limit.
  static const danmakuPipMaxVisibleCount = IntSetting(
    'danmaku.pipMaxVisibleCount',
    6,
    min: 1,
    max: 20,
    legacy: [LegacyKey('pipDanmakuMaxVisibleCount')],
  );

  // Refresh.

  /// Refresh follow states periodically.
  static const autoRefreshFollows = BoolSetting(
    'refresh.autoRefreshFavorite',
    false,
    legacy: [LegacyKey('autoRefreshFavorite')],
  );

  /// Refresh follow states when the app returns to the foreground.
  static const refreshFollowsOnResume = BoolSetting(
    'refresh.refreshFavoriteOnResume',
    true,
    legacy: [LegacyKey('refreshFavoriteOnResume')],
  );

  /// Interval of [autoRefreshFollows], in minutes.
  static const autoRefreshInterval = IntSetting(
    'refresh.autoRefreshInterval',
    30,
    min: 1,
    max: 1440,
    legacy: [LegacyKey('autoRefreshInterval')],
  );

  /// Parallel requests while refreshing follows.
  static const maxConcurrentRefresh = IntSetting(
    'refresh.maxConcurrentRefresh',
    4,
    min: 1,
    max: 16,
    legacy: [LegacyKey('maxConcurrentRefresh')],
  );

  // Data.

  /// History size limit; 0 means unlimited (store.md §3).
  static const historyLimit = IntSetting('history.limit', 50, min: 0, legacy: [LegacyKey('historyLimit')]);

  /// Visible platforms in discover, in order (store.md §6.4.8).
  static const catalogPlatforms = StringListSetting(
    'catalog.platforms',
    ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'],
    lowerCase: true,
    legacy: [LegacyKey('hotAreasList')],
  );

  /// Platform discover opens first.
  static const catalogPreferred = StringSetting(
    'catalog.preferred',
    'bilibili',
    maxLength: 64,
    legacy: [LegacyKey('preferPlatform', convert: _lowerTrim)],
  );

  // Accounts (not secrets; the cookies live in the secret store).

  /// Bilibili user id of the signed-in account; 0 when signed out.
  static const bilibiliUid = IntSetting('account.bilibili.uid', 0, min: 0, legacy: [LegacyKey('bilibiliUid')]);

  /// When the Douyu cookie was saved (Unix seconds); 0 when unknown.
  static const douyuCookieSavedAt = IntSetting(
    'account.douyu.cookieSavedAt',
    0,
    min: 0,
    legacy: [LegacyKey('douyuCookieSavedAt')],
  );

  // Desktop.

  /// Launch at login (Windows); off for new installs (principles.md §4.4).
  static const launchAtStartup = BoolSetting(
    'startup.enabled',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('enableStartUp')],
  );

  /// Main window width.
  static const windowWidth = DoubleSetting(
    'window.width',
    1280,
    min: 320,
    max: 16384,
    scope: SettingScope.device,
    legacy: [LegacyKey('window_width')],
  );

  /// Main window height.
  static const windowHeight = DoubleSetting(
    'window.height',
    720,
    min: 240,
    max: 16384,
    scope: SettingScope.device,
    legacy: [LegacyKey('window_height')],
  );

  /// Every registered setting.
  static const List<Setting<Object>> all = [
    themeMode,
    pureBlack,
    dynamicColor,
    locale,
    textScale,
    denseFollows,
    cardPresetMobile,
    cardPresetDesktop,
    startPage,
    screenKeepOn,
    autoCheckUpdate,
    refreshRateMode,
    preferRealOnlineCounts,
    qualityWifi,
    qualityMobile,
    hardwareDecoding,
    videoFit,
    backgroundPlay,
    fullScreenDefault,
    defaultMobileVolume,
    defaultDesktopVolume,
    globalMute,
    danmakuEnabled,
    danmakuHidden,
    danmakuFontSize,
    danmakuFontWeight,
    danmakuOpacity,
    danmakuSpeed,
    danmakuArea,
    danmakuTopArea,
    danmakuBottomArea,
    danmakuStroke,
    danmakuStrokeWidth,
    danmakuNoEmoji,
    danmakuAutoFps,
    danmakuFps,
    danmakuTapInteraction,
    danmakuLongPressInteraction,
    danmakuCollapseRepeated,
    danmakuRepeatedWindowSeconds,
    danmakuSimilarityFilter,
    danmakuSimilarityThreshold,
    danmakuSimilarityCacheDuration,
    danmakuSimilarityMaxCacheSize,
    danmakuFilterDouyuAutomated,
    danmakuPipEnabled,
    danmakuPipNoEmoji,
    danmakuPipFontSize,
    danmakuPipSpeed,
    danmakuPipOpacity,
    danmakuPipArea,
    danmakuPipMaxVisibleCount,
    autoRefreshFollows,
    refreshFollowsOnResume,
    autoRefreshInterval,
    maxConcurrentRefresh,
    historyLimit,
    catalogPlatforms,
    catalogPreferred,
    bilibiliUid,
    douyuCookieSavedAt,
    launchAtStartup,
    windowWidth,
    windowHeight,
  ];

  static final Map<String, Setting<Object>> _byId = {for (final setting in all) setting.id: setting};

  /// The setting registered as [id], or null.
  static Setting<Object>? byId(String id) => _byId[id];
}

// 3.x value conversions (store.md §6.4).

Object? _themeMode(Object? value) => switch (value is String ? value.trim().toLowerCase() : null) {
  'dark' => 'dark',
  'light' => 'light',
  _ => 'system',
};

Object? _locale(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text == '简体中文' || text.toLowerCase().startsWith('zh')) return 'zh-Hans';
  if (text == 'English' || text.toLowerCase().startsWith('en')) return 'en';
  return null;
}

Object? _quality(Object? value) => switch (value is String ? value.trim() : null) {
  '蓝光8M' => 'bluRay8M',
  '蓝光4M' => 'bluRay4M',
  '超清' => 'superHigh',
  '流畅' => 'smooth',
  _ => 'original',
};

Object? _videoFit(Object? value) {
  final index = value is num && value.isFinite ? value.toInt() : -1;
  return index >= 0 && index < VideoFit.values.length ? VideoFit.values[index].name : VideoFit.contain.name;
}

Object? _highRefreshRate(Object? value) => value == true ? 'balanced' : 'powerSaving';

Object? _lowerTrim(Object? value) => value is String ? value.trim().toLowerCase() : null;
