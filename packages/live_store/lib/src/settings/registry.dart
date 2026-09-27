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

  /// TV mode: automatic by device, or forced on or off (principles.md §5.1).
  /// Device scope: a TV's choice must not follow a backup onto a phone of
  /// another family; 3.x had no TV mode.
  static const tvMode = EnumSetting<TvMode>('app.tvMode', TvMode.auto, TvMode.values, scope: SettingScope.device);

  /// TV performance mode: focus shows the ring only, without the 1.05× growth
  /// and lift (principles.md §5.3, for low-end boxes).
  static const tvPerformanceMode = BoolSetting('app.tvPerformanceMode', false, scope: SettingScope.device);

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

  /// mpv's hardware decoder (F-SET-06; device scope: decoders differ per
  /// machine). 3.x's `auto` becomes the safe list.
  static const hardwareDecoder = StringSetting(
    'player.hardwareDecoder',
    'auto-safe',
    allowed: {
      'auto-safe',
      'auto',
      'auto-copy',
      'mediacodec',
      'mediacodec-copy',
      'd3d11va',
      'd3d11va-copy',
      'dxva2',
      'nvdec',
      'vulkan',
    },
    scope: SettingScope.device,
    legacy: [LegacyKey('videoHardwareDecoder', convert: _hardwareDecoder)],
  );

  /// Android compatibility output (F-SET-06, SURF-6): mediacodec_embed.
  static const androidCompatibility = BoolSetting(
    'player.androidCompatibility',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('playerCompatMode')],
  );

  /// Smaller caches and probes for a lower delay (F-SET-06, PERF-4).
  static const lowLatency = BoolSetting('player.lowLatency', false, scope: SettingScope.device);

  /// mpv audio output; empty is the platform default (F-SET-06).
  static const audioOutput = StringSetting(
    'player.audioOutput',
    '',
    allowed: {'', 'aaudio', 'opensles', 'audiotrack', 'wasapi', 'openal', 'pulse', 'alsa', 'pipewire'},
    scope: SettingScope.device,
    legacy: [LegacyKey('audioOutputDriver', convert: _audioOutput)],
  );

  /// Lower the quality by one step when playback keeps stalling (F-NEW-10).
  static const autoLowerQuality = BoolSetting('player.autoLowerQuality', true);

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

  /// Vertical swipes in portrait fullscreen switch to the previous or next
  /// live room of the list the room was opened from (F-NEW-04). Off by
  /// default: it replaces the brightness and volume swipes there
  /// (principles.md §6.1).
  static const switchRoomGesture = BoolSetting('player.switchRoomGesture', false);

  /// Portrait stream adaptation (F-ROOM-06, GEO-7): off treats every source
  /// as landscape.
  static const portraitAdaptation = BoolSetting(
    'player.portraitAdaptation',
    true,
    legacy: [LegacyKey('enablePortraitStreamAdaptation')],
  );

  /// Fullscreen orientation on phones (F-ROOM-06).
  static const portraitFullscreenPolicy = EnumSetting<PortraitFullscreenPolicy>(
    'player.portraitFullscreenPolicy',
    PortraitFullscreenPolicy.followSource,
    PortraitFullscreenPolicy.values,
    legacy: [LegacyKey('portraitFullscreenPolicy')],
  );

  /// How portrait sources fill portrait fullscreen (F-ROOM-06; 3.x's four
  /// display modes become fit or fill).
  static const portraitFit = EnumSetting<PortraitFit>(
    'player.portraitFit',
    PortraitFit.contain,
    PortraitFit.values,
    legacy: [LegacyKey('portraitFullscreenDisplayMode', convert: _portraitFit)],
  );

  /// Danmaku area in portrait fullscreen (F-ROOM-06).
  static const portraitDanmakuArea = EnumSetting<PortraitDanmakuArea>(
    'player.portraitDanmakuArea',
    PortraitDanmakuArea.followGlobal,
    PortraitDanmakuArea.values,
    legacy: [LegacyKey('portraitDanmakuMode')],
  );

  /// Remember each room's orientation override (GEO-7).
  static const rememberPortraitOverride = BoolSetting(
    'player.rememberPortraitOverride',
    true,
    legacy: [LegacyKey('rememberPortraitRoomOverride')],
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

  /// Leaving a playing room shrinks it to the in-app mini window (F-PIP-03,
  /// principles.md §6.1; 3.x default off).
  static const miniPlayerOnLeave = BoolSetting(
    'player.miniPlayerOnLeave',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('floatPlay')],
  );

  /// Enter system picture-in-picture when the user leaves the app from a
  /// playing room (Android; new in v4, default off, principles.md §6.1).
  static const autoPip = BoolSetting('player.autoPip', false, scope: SettingScope.device);

  /// Keep the Windows picture-in-picture window above other windows (F-PIP-02).
  static const pipAlwaysOnTop = BoolSetting(
    'player.pipAlwaysOnTop',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('windowsPipAlwaysOnTop')],
  );

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

  /// The user's saved danmaku style (F-DM-02): 3.x's JSON template, kept in
  /// its format so 3.x backups restore it as is; empty when none.
  static const danmakuTemplate = StringSetting('danmaku.template', '', legacy: [LegacyKey('savedDanmakuTemplate')]);

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

  // Alerts (spec/product.md F-NEW-01).

  /// Notify when a followed streamer goes live; off by default. Rooms can opt
  /// out one by one (room preference `liveAlert`). Device scope: the
  /// notification permission belongs to the device (ADR ADR 0028).
  static const liveAlerts = BoolSetting('alerts.live', false, scope: SettingScope.device);

  // Data.

  /// History size limit; 0 means unlimited (store.md §3).
  static const historyLimit = IntSetting('history.limit', 50, min: 0, legacy: [LegacyKey('historyLimit')]);

  /// Visible platforms in discover, in order (store.md §6.4.8); IPTV shows as
  /// the "网络电视" platform (iptv.md §5), as it did in 3.x.
  static const catalogPlatforms = StringListSetting(
    'catalog.platforms',
    ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'yy', 'soop', 'acfun', 'twitch', 'iptv'],
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

  // IPTV (spec/modules/iptv.md §6).

  /// Sync URL playlists and guides automatically (F-IPTV-03; off by default).
  static const iptvAutoSync = BoolSetting('iptv.autoSync', false, legacy: [LegacyKey('isAutoSyncEnabled')]);

  /// Hours between automatic syncs.
  static const iptvAutoSyncHours = IntSetting(
    'iptv.autoSyncHours',
    24,
    min: 1,
    max: 168,
    legacy: [LegacyKey('autoSyncHoursInterval')],
  );

  /// User-Agent for IPTV downloads and streams (F-IPTV-04); empty for none.
  static const iptvUserAgent = StringSetting(
    'iptv.userAgent',
    '',
    maxLength: 512,
    legacy: [LegacyKey('customIptvUserAgent')],
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

  // Network proxy (spec/modules/store.md §1.5 "网络"; product F-SET-07). 3.x kept
  // an app proxy and a player proxy; v4 has one, applied to adapters, chat,
  // playback and recording, optionally only for some platforms.

  /// Use the proxy.
  static const proxyEnabled = BoolSetting(
    'network.proxyEnabled',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('enableAppProxy'), LegacyKey('enableProxy')],
  );

  /// Proxy host.
  static const proxyHost = StringSetting(
    'network.proxyHost',
    '',
    maxLength: 255,
    scope: SettingScope.device,
    legacy: [LegacyKey('appProxyHost'), LegacyKey('proxyHost')],
  );

  /// Proxy port.
  static const proxyPort = IntSetting(
    'network.proxyPort',
    7897,
    min: 1,
    max: 65535,
    scope: SettingScope.device,
    legacy: [LegacyKey('appProxyPort'), LegacyKey('proxyPort')],
  );

  /// Platforms that go through the proxy; empty means every platform.
  static const proxyPlatforms = StringListSetting(
    'network.proxyPlatforms',
    [],
    lowerCase: true,
    scope: SettingScope.device,
  );

  // Recording (spec/modules/record.md §20); device scope, never synced.

  /// Default recording quality.
  static const recordDefaultQuality = EnumSetting<QualityPreference>(
    'record.defaultQuality',
    QualityPreference.original,
    QualityPreference.values,
    scope: SettingScope.device,
    legacy: [LegacyKey('default_quality', convert: _quality)],
  );

  /// Recordings that run at once.
  static const recordMaxConcurrent = IntSetting(
    'record.maxConcurrent',
    3,
    min: 1,
    max: 10,
    scope: SettingScope.device,
    legacy: [LegacyKey('maxTaskCount')],
  );

  /// Reconnect after a dropped connection.
  static const recordAutoReconnect = BoolSetting(
    'record.autoReconnect',
    true,
    scope: SettingScope.device,
    legacy: [LegacyKey('autoReconnect')],
  );

  /// Retries before a recording fails.
  static const recordMaxRetries = IntSetting(
    'record.maxRetries',
    5,
    min: 1,
    max: 20,
    scope: SettingScope.device,
    legacy: [LegacyKey('max_retry_count')],
  );

  /// Seconds between retries.
  static const recordRetryDelay = IntSetting(
    'record.retryDelay',
    30,
    min: 5,
    max: 120,
    scope: SettingScope.device,
    legacy: [LegacyKey('retry_delay')],
  );

  /// Watch offline rooms and record when they go live.
  static const recordPolling = BoolSetting(
    'record.polling',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('enable_polling')],
  );

  /// Seconds between live checks while waiting.
  static const recordLiveCheckInterval = IntSetting(
    'record.liveCheckInterval',
    30,
    min: 10,
    max: 300,
    scope: SettingScope.device,
    legacy: [LegacyKey('live_check_interval')],
  );

  /// Double the wait after each failed check.
  static const recordBackoff = BoolSetting(
    'record.backoff',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('enable_backoff')],
  );

  /// Longest wait between checks with backoff, in seconds.
  static const recordMaxCheckInterval = IntSetting(
    'record.maxCheckInterval',
    300,
    min: 300,
    max: 3600,
    scope: SettingScope.device,
    legacy: [LegacyKey('max_check_interval')],
  );

  /// Resume unfinished recordings when the app starts.
  static const recordResumeOnLaunch = BoolSetting(
    'record.resumeOnLaunch',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('auto_start_on_boot')],
  );

  /// Read timeout in seconds: 15, 30 or 60.
  static const recordReadTimeout = IntSetting(
    'record.readTimeout',
    15,
    min: 15,
    max: 60,
    scope: SettingScope.device,
    legacy: [LegacyKey('recorder_rw_timeout')],
  );

  /// Folder names in pinyin.
  static const recordPinyinFolders = BoolSetting(
    'record.pinyinFolders',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('recorder_folder_naming_strategy', convert: _truthy)],
  );

  /// Save chat next to the video.
  static const recordDanmaku = BoolSetting(
    'record.danmaku',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('recorder_record_danmaku')],
  );

  /// Limit the recording folder size.
  static const recordCacheLimitEnabled = BoolSetting(
    'record.cacheLimitEnabled',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('enableCacheLimit')],
  );

  /// Recording folder limit in MB.
  static const recordCacheLimitMb = IntSetting(
    'record.cacheLimitMB',
    1024,
    min: 1,
    max: 16777216,
    scope: SettingScope.device,
    legacy: [LegacyKey('maxCacheMB')],
  );

  /// Chosen parent folder for recordings; empty means the app data folder.
  static const recordDirectory = StringSetting(
    'record.directory',
    '',
    scope: SettingScope.device,
    legacy: [LegacyKey('recordSavePath')],
  );

  /// New segment after this many minutes; 0 = off.
  static const recordSplitMinutes = IntSetting('record.splitMinutes', 0, min: 0, max: 1440, scope: SettingScope.device);

  /// New segment after this many MB; 0 = off.
  static const recordSplitMegabytes = IntSetting(
    'record.splitMegabytes',
    0,
    min: 0,
    max: 1048576,
    scope: SettingScope.device,
  );

  /// Remux finished FLV files to MP4.
  static const recordRemuxToMp4 = BoolSetting('record.remuxToMp4', true, scope: SettingScope.device);

  /// Keep the FLV after a successful remux.
  static const recordKeepSourceAfterRemux = BoolSetting(
    'record.keepSourceAfterRemux',
    false,
    scope: SettingScope.device,
  );

  /// Main window position as `x,y` in logical pixels; empty until the window
  /// first moves (F-WIN-06).
  static const windowPosition = StringSetting('window.position', '', maxLength: 64, scope: SettingScope.device);

  /// The main window was maximised when last used (F-WIN-06).
  static const windowMaximized = BoolSetting('window.maximized', false, scope: SettingScope.device);

  /// Closing the main window does [closeAction] without asking (F-WIN-04).
  static const closeDontAsk = BoolSetting(
    'exit.dontAsk',
    false,
    scope: SettingScope.device,
    legacy: [LegacyKey('dontAskExit')],
  );

  /// What closing the main window does once the user chose "不再询问".
  static const closeAction = EnumSetting<CloseAction>(
    'exit.choice',
    CloseAction.exit,
    CloseAction.values,
    scope: SettingScope.device,
    legacy: [LegacyKey('exitChoose')],
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
    tvMode,
    tvPerformanceMode,
    qualityWifi,
    qualityMobile,
    autoLowerQuality,
    hardwareDecoder,
    androidCompatibility,
    lowLatency,
    audioOutput,
    hardwareDecoding,
    videoFit,
    backgroundPlay,
    fullScreenDefault,
    switchRoomGesture,
    portraitAdaptation,
    portraitFullscreenPolicy,
    portraitFit,
    portraitDanmakuArea,
    rememberPortraitOverride,
    defaultMobileVolume,
    defaultDesktopVolume,
    globalMute,
    miniPlayerOnLeave,
    autoPip,
    pipAlwaysOnTop,
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
    danmakuTemplate,
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
    liveAlerts,
    historyLimit,
    catalogPlatforms,
    catalogPreferred,
    iptvAutoSync,
    iptvAutoSyncHours,
    iptvUserAgent,
    bilibiliUid,
    douyuCookieSavedAt,
    launchAtStartup,
    windowWidth,
    windowHeight,
    recordDefaultQuality,
    recordMaxConcurrent,
    recordAutoReconnect,
    recordMaxRetries,
    recordRetryDelay,
    recordPolling,
    recordLiveCheckInterval,
    recordBackoff,
    recordMaxCheckInterval,
    recordResumeOnLaunch,
    recordReadTimeout,
    recordPinyinFolders,
    recordDanmaku,
    recordCacheLimitEnabled,
    recordCacheLimitMb,
    recordDirectory,
    recordSplitMinutes,
    recordSplitMegabytes,
    recordRemuxToMp4,
    recordKeepSourceAfterRemux,
    proxyEnabled,
    proxyHost,
    proxyPort,
    proxyPlatforms,
    windowPosition,
    windowMaximized,
    closeDontAsk,
    closeAction,
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

Object? _portraitFit(Object? value) => value == 'cover' ? 'cover' : 'contain';

Object? _hardwareDecoder(Object? value) => value == 'auto' || value is! String ? 'auto-safe' : value;

Object? _audioOutput(Object? value) => value == 'auto' || value is! String ? '' : value;

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

Object? _truthy(Object? value) => value == true || value == 'pinyin' || value == 1;
