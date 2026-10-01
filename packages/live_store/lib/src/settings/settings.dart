import 'package:live_core/live_core.dart';
import 'package:live_store/src/settings/setting.dart';

/// Every setting the app stores, with 3.x's keys and defaults
/// (`lib/common/services/settings/*_controller.dart` at v3.2.11) plus the
/// settings added by approved upgrades (docs/UPGRADES.md).
///
/// Accounts (cookies, WebDAV passwords) are not settings: they live in the
/// encrypted `SecretStore`. Follows, history, tags and block lists have their
/// own stores.
abstract final class Settings {
  // ---- app (app_settings_controller.dart:42-69) ----

  /// 3.x stored it but nothing outside the settings page read it.
  static const autoRefreshTime = IntSetting('autoRefreshTime', section: 'app', defaultValue: 3);

  /// Compact cards on the follow page.
  static const enableDenseFavorites = BoolSetting('enableDenseFavorites', section: 'app', defaultValue: true);

  /// Keep playing in the background.
  static const enableBackgroundPlay = BoolSetting('enableBackgroundPlay', section: 'app', defaultValue: false);

  /// Sleep timer for audio streams.
  static const enableAsmrSleepMode = BoolSetting('enableAsmrSleepMode', section: 'app', defaultValue: false);

  /// Sleep timer length in minutes (1 minute .. 1 year).
  static const asmrSleepMinutes = IntSetting('asmrSleepMinutes', section: 'app', defaultValue: 60, min: 1, max: 525600);

  /// Follow the device orientation in the player.
  static const enableRotateScreen = BoolSetting('enableRotateScreen', section: 'app', defaultValue: false);

  /// Keep the screen on while playing.
  static const enableScreenKeepOn = BoolSetting('enableScreenKeepOn', section: 'app', defaultValue: true);

  /// Check for updates on start.
  static const enableAutoCheckUpdate = BoolSetting('enableAutoCheckUpdate', section: 'app', defaultValue: true);

  /// Download updates from GitHub instead of the mirror.
  static const useGitHubOriginForUpdates = BoolSetting(
    'useGitHubOriginForUpdates',
    section: 'app',
    defaultValue: false,
  );

  /// Enter full screen when a room opens.
  static const enableFullScreenDefault = BoolSetting('enableFullScreenDefault', section: 'app', defaultValue: false);

  /// Show the splash page.
  static const showSplashPage = BoolSetting('showSplashPage', section: 'app', defaultValue: true);

  /// Display refresh-rate policy. A 3.x install without it derives it from
  /// the retired `enableHighRefreshRate` switch (see the migration).
  static const refreshRateMode = StringSetting(
    'refreshRateMode',
    section: 'app',
    defaultValue: 'powerSaving',
    allowed: {'powerSaving', 'balanced', 'performance'},
  );

  /// Prefer real online counts over popularity where a platform has both.
  static const preferRealOnlineCounts = BoolSetting('preferRealOnlineCounts', section: 'app', defaultValue: false);

  /// Platforms whose real online count is preferred.
  static const realOnlinePlatforms = StringListSetting(
    'realOnlinePlatforms',
    section: 'app',
    defaultValue: [
      SiteIds.douyin,
      SiteIds.kuaishou,
      SiteIds.cc,
      SiteIds.twitch,
      SiteIds.soop,
      SiteIds.acfun,
      SiteIds.picarto,
      SiteIds.twitcasting,
    ],
  );

  /// Bottom-menu entries, in order.
  static const savedMenuIds = StringListSetting(
    'savedMenuIds',
    section: 'app',
    defaultValue: ['favorites', 'popular', 'areas', 'record'],
  );

  /// Multi-view entry.
  static const enableMultiView = BoolSetting('enableMultiView', section: 'app', defaultValue: true);

  /// "Open in new window" entry (Windows).
  static const enableNewWindowPlay = BoolSetting('enableNewWindowPlay', section: 'app', defaultValue: true);

  /// New (unified rule "受限……"): discovery pages hide rooms that cannot
  /// be played; on shows them. Follows and search always show them.
  static const showUnplayableInDiscover = BoolSetting('showUnplayableInDiscover', section: 'app', defaultValue: false);

  /// New (UPGRADES 2-1): renew the Douyu cookie every 5 minutes after login.
  static const douyuForceRenew = BoolSetting('douyuForceRenew', section: 'app', defaultValue: false);

  /// New (UPGRADES 8-3): Twitch directory languages; empty = no filter.
  /// [twitchLegacyLanguages] is 3.x's fixed filter, offered as a preset.
  static const twitchLanguages = StringListSetting('twitchLanguages', section: 'app', defaultValue: []);

  /// 3.x's Twitch language filter (Chinese and Korean streams only).
  static const List<String> twitchLegacyLanguages = ['zh', 'ko'];

  // ---- favorite (favorite_room_controller.dart:16-24) ----

  /// Platforms shown on the home tabs, in order.
  static const hotAreasList = StringListSetting('hotAreasList', section: 'favorite', defaultValue: SiteIds.supported);

  /// The platform opened first.
  static const preferPlatform = StringSetting('preferPlatform', section: 'favorite', defaultValue: SiteIds.bilibili);

  // ---- history (history_controller.dart:8-15) ----

  /// History entries kept; 0 keeps everything.
  static const historyLimit = IntSetting('historyLimit', section: 'history', defaultValue: 50, min: 0);

  // ---- theme (theme_settings_controller.dart:17-24) ----

  /// `System`, `Dark` or `Light` (3.x's stored names).
  static const themeMode = StringSetting(
    'themeMode',
    section: 'theme',
    defaultValue: 'System',
    allowed: {'System', 'Dark', 'Light'},
  );

  /// Material You colours.
  static const enableDynamicTheme = BoolSetting('enableDynamicTheme', section: 'theme', defaultValue: false);

  /// Seed colour, `AARRGGBB` hex.
  static const themeColorSwitch = StringSetting('themeColorSwitch', section: 'theme', defaultValue: 'FF2196F3');

  /// Language display name (`简体中文`, `English`); 3.x's backups also used
  /// `languageName`.
  static const language = StringSetting(
    'language',
    section: 'theme',
    defaultValue: '简体中文',
    legacyKeys: ['languageName'],
  );

  /// Grid spacing.
  static const crossAxisSpacing = DoubleSetting('crossAxisSpacing', section: 'theme', defaultValue: 6, min: 0, max: 64);

  /// Grid spacing.
  static const mainAxisSpacing = DoubleSetting('mainAxisSpacing', section: 'theme', defaultValue: 6, min: 0, max: 64);

  /// Loading indicator style key.
  static const loadingStyle = StringSetting('loadingStyle', section: 'theme', defaultValue: 'default');

  /// Loading indicator colour; empty follows the theme.
  static const loadingStyleColorSwitch = StringSetting('loadingStyleColorSwitch', section: 'theme', defaultValue: '');

  // ---- font (font_settings_controller.dart:39-47) ----

  /// Text scale (0.5..2, font_settings_controller.dart:17-18).
  static const textScaleFactor = DoubleSetting('textScaleFactor', section: 'font', defaultValue: 1, min: 0.5, max: 2);

  /// Small text size (9..15, font_settings_controller.dart:19-33 gives
  /// every size's range).
  static const fontSizeBodySmall = DoubleSetting(
    'fontSizeBodySmall',
    section: 'font',
    defaultValue: 12,
    min: 9,
    max: 15,
  );

  /// Body text size (11..17).
  static const fontSizeBodyMedium = DoubleSetting(
    'fontSizeBodyMedium',
    section: 'font',
    defaultValue: 13,
    min: 11,
    max: 17,
  );

  /// Large body text size (12..18).
  static const fontSizeBodyLarge = DoubleSetting(
    'fontSizeBodyLarge',
    section: 'font',
    defaultValue: 14,
    min: 12,
    max: 18,
  );

  /// Heading size (13..20).
  static const fontSizeTitleMedium = DoubleSetting(
    'fontSizeTitleMedium',
    section: 'font',
    defaultValue: 15,
    min: 13,
    max: 20,
  );

  /// Large heading size (16..26).
  static const fontSizeTitleLarge = DoubleSetting(
    'fontSizeTitleLarge',
    section: 'font',
    defaultValue: 20,
    min: 16,
    max: 26,
  );

  /// App font id.
  static const fontFamilyName = StringSetting('fontFamilyName', section: 'font', defaultValue: 'Default');

  /// App font file (downloaded on this device).
  static const fontFamilyFileName = StringSetting('fontFamilyFileName', section: 'font', defaultValue: '');

  /// Danmaku font file (downloaded on this device).
  static const danmakuFontFamilyFileName = StringSetting(
    'danmakuFontFamilyFileName',
    section: 'font',
    defaultValue: '',
  );

  // ---- player (player_settings_controller.dart:33-71) ----

  /// Index into contain, cover, fill, fitHeight, fitWidth, scaleDown.
  static const videoFitIndex = IntSetting('videoFitIndex', section: 'player', defaultValue: 0, min: 0, max: 5);

  /// 3.x's player engine; v4 plays everything with mpv, kept for backups.
  static const videoPlayerKey = StringSetting('videoPlayerKey', section: 'player', defaultValue: 'mpv');

  /// Preferred quality name on Wi-Fi (`原画`, `蓝光8M`, `蓝光4M`, `超清`, `流畅`).
  static const preferResolution = StringSetting(
    'preferResolution',
    section: 'player',
    defaultValue: '原画',
    allowed: resolutions,
  );

  /// Preferred quality name on mobile data.
  static const preferResolutionCellular = StringSetting(
    'preferResolutionCellular',
    section: 'player',
    defaultValue: '原画',
    allowed: resolutions,
  );

  /// 3.x's quality names (player_consts.dart:25).
  static const Set<String> resolutions = {'原画', '蓝光8M', '蓝光4M', '超清', '流畅'};

  /// Hardware decoding.
  static const enableCodec = BoolSetting('enableCodec', section: 'player', defaultValue: true);

  /// New (UPGRADES unified rule, 22-3, 14-5, 33-2, 8-8): H.264 qualities
  /// first so HEVC is only played when chosen by hand.
  static const preferH264 = BoolSetting('preferH264', section: 'player', defaultValue: true);

  /// Compatibility output.
  static const playerCompatMode = BoolSetting('playerCompatMode', section: 'player', defaultValue: false);

  /// Custom mpv outputs.
  static const customPlayerOutput = BoolSetting('customPlayerOutput', section: 'player', defaultValue: false);

  /// mpv `vo`.
  static const videoOutputDriver = StringSetting('videoOutputDriver', section: 'player', defaultValue: 'gpu');

  /// mpv `ao`.
  static const audioOutputDriver = StringSetting('audioOutputDriver', section: 'player', defaultValue: 'auto');

  /// mpv `hwdec`.
  static const videoHardwareDecoder = StringSetting('videoHardwareDecoder', section: 'player', defaultValue: 'auto');

  /// Picture-in-picture on leaving.
  static const floatPlay = BoolSetting('floatPlay', section: 'player', defaultValue: false);

  /// Windows PiP on top.
  static const windowsPipAlwaysOnTop = BoolSetting('windowsPipAlwaysOnTop', section: 'player', defaultValue: false);

  /// Leaving the app from a playing room enters picture-in-picture (U.2j,
  /// choice J1). New in v4, off by default; 3.x only had the button.
  static const autoPipOnLeave = BoolSetting('autoPipOnLeave', section: 'player', defaultValue: false);

  /// NVIDIA RTX video super resolution.
  static const enableRtxVsr = BoolSetting('enableRtxVsr', section: 'player', defaultValue: false);

  /// Hard stop on exit.
  static const useHardStopOnExit = BoolSetting('useHardStopOnExit', section: 'player', defaultValue: false);

  /// Portrait stream adaptation.
  static const enablePortraitStreamAdaptation = BoolSetting(
    'enablePortraitStreamAdaptation',
    section: 'player',
    defaultValue: true,
  );

  /// Portrait adaptive height.
  static const portraitAdaptiveHeight = BoolSetting('portraitAdaptiveHeight', section: 'player', defaultValue: true);

  /// Portrait layout.
  static const portraitLayoutMode = StringSetting('portraitLayoutMode', section: 'player', defaultValue: 'balanced');

  /// Portrait full-screen policy.
  static const portraitFullscreenPolicy = StringSetting(
    'portraitFullscreenPolicy',
    section: 'player',
    defaultValue: 'followSource',
  );

  /// Portrait full-screen display mode.
  static const portraitFullscreenDisplayMode = StringSetting(
    'portraitFullscreenDisplayMode',
    section: 'player',
    defaultValue: 'ambient',
  );

  /// Portrait PiP follows the source.
  static const portraitPipFollowSource = BoolSetting('portraitPipFollowSource', section: 'player', defaultValue: true);

  /// Portrait danmaku mode.
  static const portraitDanmakuMode = StringSetting(
    'portraitDanmakuMode',
    section: 'player',
    defaultValue: 'followGlobal',
  );

  /// Remember per-room portrait overrides.
  static const rememberPortraitRoomOverride = BoolSetting(
    'rememberPortraitRoomOverride',
    section: 'player',
    defaultValue: true,
  );

  /// Portrait diagnostics overlay.
  static const showPortraitDiagnostics = BoolSetting('showPortraitDiagnostics', section: 'player', defaultValue: false);

  /// Per-room portrait layout, `{"platform:roomId": "<layout>"}`.
  static const portraitRoomOverrides = JsonSetting('portraitRoomOverrides', section: 'player', defaultValue: {});

  // ---- danmaku (danmaku_settings_controller.dart:58-111) ----

  /// Hide danmaku.
  static const hideDanmaku = BoolSetting('hideDanmaku', section: 'danmaku', defaultValue: false);

  /// Hide emoji danmaku.
  static const noEmojiMode = BoolSetting('noEmojiMode', section: 'danmaku', defaultValue: false);

  /// Space kept free above the danmaku, in logical pixels (0..300 as 3.x's
  /// `_boundedDouble`, danmaku_settings_controller.dart:115; it was clamped
  /// to 0..1 here before, which turned a 3.x value of 40 into 1).
  static const danmakuTopArea = DoubleSetting('danmakuTopArea', section: 'danmaku', defaultValue: 0, min: 0, max: 300);

  /// Display area.
  static const danmakuArea = DoubleSetting('danmakuArea', section: 'danmaku', defaultValue: 1, min: 0, max: 1);

  /// Space kept free below the danmaku, in logical pixels (0..300, see
  /// [danmakuTopArea]; 3.x's default is 0.5).
  static const danmakuBottomArea = DoubleSetting(
    'danmakuBottomArea',
    section: 'danmaku',
    defaultValue: 0.5,
    min: 0,
    max: 300,
  );

  /// Scroll speed.
  static const danmakuSpeed = DoubleSetting('danmakuSpeed', section: 'danmaku', defaultValue: 120);

  /// Font size.
  static const danmakuFontSize = DoubleSetting('danmakuFontSize', section: 'danmaku', defaultValue: 16);

  /// Font weight.
  static const danmakuFontWeight = IntSetting('danmakuFontWeight', section: 'danmaku', defaultValue: 500);

  /// Stroke width.
  static const danmakuFontBorder = DoubleSetting(
    'danmakuFontBorder',
    section: 'danmaku',
    defaultValue: 1.5,
    min: 0,
    max: 4,
  );

  /// Opacity.
  static const danmakuOpacity = DoubleSetting('danmakuOpacity', section: 'danmaku', defaultValue: 1, min: 0, max: 1);

  /// Show danmaku.
  static const enableDanmakuDisplay = BoolSetting('enableDanmakuDisplay', section: 'danmaku', defaultValue: true);

  /// Stroke.
  static const enableDanmakuStroke = BoolSetting('enableDanmakuStroke', section: 'danmaku', defaultValue: true);

  /// The chat list's look in the room (U.2a): `compact` lines ("用户名：" in
  /// a secondary colour, then the message) or 3.x's `card` per message.
  /// New in v4; 3.x always drew cards.
  static const danmakuListStyle = StringSetting(
    'danmakuListStyle',
    section: 'danmaku',
    defaultValue: 'compact',
    allowed: {'compact', 'card'},
  );

  /// Frame rate.
  static const danmakuFps = IntSetting('danmakuFps', section: 'danmaku', defaultValue: 60, min: 30, max: 240);

  /// Automatic frame rate.
  static const danmakuAutoFps = BoolSetting('danmakuAutoFps', section: 'danmaku', defaultValue: true);

  /// Tap a danmaku for actions.
  static const enableDanmakuTapInteraction = BoolSetting(
    'enableDanmakuTapInteraction',
    section: 'danmaku',
    defaultValue: true,
  );

  /// Long-press a danmaku for actions.
  static const enableDanmakuLongPressInteraction = BoolSetting(
    'enableDanmakuLongPressInteraction',
    section: 'danmaku',
    defaultValue: true,
  );

  /// Collapse repeats.
  static const collapseRepeatedDanmaku = BoolSetting(
    'collapseRepeatedDanmaku',
    section: 'danmaku',
    defaultValue: false,
  );

  /// Repeat window, seconds.
  static const repeatedDanmakuWindowSeconds = IntSetting(
    'repeatedDanmakuWindowSeconds',
    section: 'danmaku',
    defaultValue: 5,
    min: 1,
  );

  /// Saved danmaku template.
  static const savedDanmakuTemplate = StringSetting('savedDanmakuTemplate', section: 'danmaku', defaultValue: '');

  /// Danmaku font id.
  static const danmakuFontFamilyName = StringSetting(
    'danmakuFontFamilyName',
    section: 'danmaku',
    defaultValue: 'Default',
  );

  /// Danmaku in PiP.
  static const enablePipDanmaku = BoolSetting('enablePipDanmaku', section: 'danmaku', defaultValue: true);

  /// PiP danmaku scaling.
  static const pipDanmakuAutoScale = BoolSetting('pipDanmakuAutoScale', section: 'danmaku', defaultValue: true);

  /// PiP: hide emoji (3.x's Hive key is misspelt; backups use the right name).
  static const pipDanmakuNoEmojiMode = BoolSetting(
    'pipDanmaNoEmojiMode',
    section: 'danmaku',
    defaultValue: false,
    backupKey: 'pipDanmakuNoEmojiMode',
  );

  /// PiP: original colours.
  static const pipDanmakuUseOriginalColor = BoolSetting(
    'pipDanmakuUseOriginalColor',
    section: 'danmaku',
    defaultValue: true,
  );

  /// PiP colour, ARGB.
  static const pipDanmakuColor = IntSetting('pipDanmakuColor', section: 'danmaku', defaultValue: 0xFFFFFFFF);

  /// PiP font size.
  static const pipDanmakuFontSize = DoubleSetting('pipDanmakuFontSize', section: 'danmaku', defaultValue: 12);

  /// PiP font weight.
  static const pipDanmakuFontWeight = IntSetting('pipDanmakuFontWeight', section: 'danmaku', defaultValue: 500);

  /// PiP speed.
  static const pipDanmakuSpeed = DoubleSetting('pipDanmakuSpeed', section: 'danmaku', defaultValue: 90);

  /// PiP opacity.
  static const pipDanmakuOpacity = DoubleSetting(
    'pipDanmakuOpacity',
    section: 'danmaku',
    defaultValue: 0.9,
    min: 0,
    max: 1,
  );

  /// PiP area.
  static const pipDanmakuArea = DoubleSetting('pipDanmakuArea', section: 'danmaku', defaultValue: 0.5, min: 0, max: 1);

  /// PiP visible count.
  static const pipDanmakuMaxVisibleCount = IntSetting(
    'pipDanmakuMaxVisibleCount',
    section: 'danmaku',
    defaultValue: 6,
    min: 1,
  );

  /// PiP emit interval, seconds.
  static const pipDanmakuEmitInterval = DoubleSetting('pipDanmakuEmitInterval', section: 'danmaku', defaultValue: 0.35);

  /// PiP frame rate.
  static const pipDanmakuFps = IntSetting('pipDanmakuFps', section: 'danmaku', defaultValue: 30);

  /// PiP automatic frame rate.
  static const pipDanmakuAutoFps = BoolSetting('pipDanmakuAutoFps', section: 'danmaku', defaultValue: true);

  /// Drop Douyu's suspected bot messages.
  static const filterDouyuSuspectedAutomatedMessages = BoolSetting(
    'filterDouyuSuspectedAutomatedMessages',
    section: 'danmaku',
    defaultValue: false,
  );

  /// Similarity filter.
  static const enableDanmakuSimilarityFilter = BoolSetting(
    'enableDanmakuSimilarityFilter',
    section: 'danmaku',
    defaultValue: false,
  );

  /// Similarity threshold, percent (50..100).
  static const danmakuSimilarityThreshold = IntSetting(
    'danmakuSimilarityThreshold',
    section: 'danmaku',
    defaultValue: 85,
    min: 50,
    max: 100,
  );

  /// Similarity cache duration (1..60, danmaku_settings_controller.dart:126).
  static const danmakuSimilarityCacheDuration = IntSetting(
    'danmakuSimilarityCacheDuration',
    section: 'danmaku',
    defaultValue: 3,
    min: 1,
    max: 60,
  );

  /// Similarity cache size (20..1000, danmaku_settings_controller.dart:127).
  static const danmakuSimilarityMaxCacheSize = IntSetting(
    'danmakuSimilarityMaxCacheSize',
    section: 'danmaku',
    defaultValue: 100,
    min: 20,
    max: 1000,
  );

  /// New (UPGRADES B-13): YouTube "Live chat" (every message) instead of
  /// the web page's default "Top chat".
  static const youtubeShowAllChat = BoolSetting('youtubeShowAllChat', section: 'danmaku', defaultValue: false);

  // ---- volume (volume_settings_controller.dart:8-11) ----

  /// Default volume on phones.
  static const defaultMobileVolume = DoubleSetting(
    'defaultMobileVolume',
    section: 'volume',
    defaultValue: 0.5,
    min: 0,
    max: 1,
  );

  /// Default volume on desktops.
  static const defaultDesktopVolume = DoubleSetting(
    'defaultDesktopVolume',
    section: 'volume',
    defaultValue: 1,
    min: 0,
    max: 1,
  );

  /// Mute everything.
  static const globalVolumeMute = BoolSetting('globalVolumeMute', section: 'volume', defaultValue: false);

  /// Per-room volume, `{"room_vol_<platform>_<roomId>": 0..1}`.
  static const roomVolumes = JsonSetting('roomVolumes', section: 'volume', defaultValue: {});

  // ---- room card (room_card_settings_controller.dart:251-265) ----

  /// Phone card preset (`compact`, `normal`, `rich`, `custom`).
  static const roomCardMobilePreset = StringSetting(
    'room_card_mobile_preset',
    section: 'roomCard',
    defaultValue: 'normal',
    allowed: {'compact', 'normal', 'rich', 'custom'},
    backupKey: 'mobilePreset',
  );

  /// Desktop card preset.
  static const roomCardDesktopPreset = StringSetting(
    'room_card_desktop_preset',
    section: 'roomCard',
    defaultValue: 'normal',
    allowed: {'compact', 'normal', 'rich', 'custom'},
    backupKey: 'desktopPreset',
  );

  /// Phone card appearance; empty uses the preset.
  static const roomCardMobileConfig = JsonSetting(
    'room_card_mobile_config',
    section: 'roomCard',
    defaultValue: {},
    backupKey: 'mobileConfig',
  );

  /// Desktop card appearance; empty uses the preset.
  static const roomCardDesktopConfig = JsonSetting(
    'room_card_desktop_config',
    section: 'roomCard',
    defaultValue: {},
    backupKey: 'desktopConfig',
  );

  // ---- page (page_settings_controller.dart:14-19) ----

  /// Page-size selector.
  static const pageShowSizeSelector = BoolSetting(
    'page_show_size_selector',
    section: 'page',
    defaultValue: true,
    backupKey: 'showPageSizeSelector',
  );

  /// "Go to page" button.
  static const pageShowGotoButton = BoolSetting(
    'page_show_goto_button',
    section: 'page',
    defaultValue: true,
    backupKey: 'showGotoButton',
  );

  /// Scroll-to-top button.
  static const pageShowScrollTop = BoolSetting(
    'page_show_scroll_top',
    section: 'page',
    defaultValue: true,
    backupKey: 'showScrollToTopBtn',
  );

  /// Rooms per page; 0 = by screen width (20 above 960 logical px, else 12,
  /// page_settings_controller.dart:23-32), decided by the UI.
  static const pageDefaultSize = IntSetting(
    'page_default_size',
    section: 'page',
    defaultValue: 0,
    min: 0,
    max: 100,
    backupKey: 'defaultPageSize',
  );

  /// Page-size choices, comma separated (a list of numbers in backups).
  static const pageSizeOptions = StringSetting(
    'page_size_options_raw',
    section: 'page',
    defaultValue: '',
    backupKey: 'pageSizeOptions',
  );

  // ---- refresh (refresh_config_controller.dart:21-30) ----

  /// Refresh follows on a timer.
  static const autoRefreshFavorite = BoolSetting('autoRefreshFavorite', section: 'refresh', defaultValue: false);

  /// Refresh follows when the app returns.
  static const refreshFavoriteOnResume = BoolSetting('refreshFavoriteOnResume', section: 'refresh', defaultValue: true);

  /// Minutes between follow refreshes (5..360).
  static const autoRefreshInterval = IntSetting(
    'autoRefreshInterval',
    section: 'refresh',
    defaultValue: 30,
    min: 5,
    max: 360,
  );

  /// Parallel refresh requests (1..20).
  static const maxConcurrentRefresh = IntSetting(
    'maxConcurrentRefresh',
    section: 'refresh',
    defaultValue: 4,
    min: 1,
    max: 20,
  );

  /// Refresh covers on a timer.
  static const autoRefreshThumbnails = BoolSetting('autoRefreshThumbnails', section: 'refresh', defaultValue: false);

  /// Minutes between cover refreshes (5..360).
  static const thumbnailRefreshInterval = IntSetting(
    'thumbnailRefreshInterval',
    section: 'refresh',
    defaultValue: 30,
    min: 5,
    max: 360,
  );

  // ---- iptv (iptv_settings_controller.dart:22-27) ----

  /// Selected source name.
  static const selectedSourceName = StringSetting('selectedSourceName', section: 'iptv', defaultValue: '');

  /// Selected source id.
  static const selectedSourceId = StringSetting('selectedSourceId', section: 'iptv', defaultValue: '');

  /// Automatic sync.
  static const isAutoSyncEnabled = BoolSetting('isAutoSyncEnabled', section: 'iptv', defaultValue: false);

  /// Sync interval in hours (2..72).
  static const autoSyncHoursInterval = IntSetting(
    'autoSyncHoursInterval',
    section: 'iptv',
    defaultValue: 24,
    min: 2,
    max: 72,
  );

  /// IPTV User-Agent.
  static const customIptvUserAgent = StringSetting('customIptvUserAgent', section: 'iptv', defaultValue: '');

  /// Playlist folder (3.x's default is the literal key).
  static const m3uDirectory = StringSetting('m3uDirectory', section: 'iptv', defaultValue: 'm3uDirectory');

  // ---- proxy (proxy_settings_controller.dart:11-18) ----

  /// Player proxy.
  static const enableProxy = BoolSetting('enableProxy', section: 'proxy', defaultValue: false);

  /// Player proxy host.
  static const proxyHost = StringSetting('proxyHost', section: 'proxy', defaultValue: '');

  /// Player proxy port.
  static const proxyPort = IntSetting('proxyPort', section: 'proxy', defaultValue: 7897, min: 1, max: 65535);

  /// App (request) proxy.
  static const enableAppProxy = BoolSetting('enableAppProxy', section: 'proxy', defaultValue: false);

  /// App proxy host.
  static const appProxyHost = StringSetting('appProxyHost', section: 'proxy', defaultValue: '');

  /// App proxy port.
  static const appProxyPort = IntSetting('appProxyPort', section: 'proxy', defaultValue: 7897, min: 1, max: 65535);

  // ---- window, exit, startup (window_size_controller.dart, exit_settings_controller.dart, startup_controller.dart) ----

  /// Window width.
  static const windowWidth = DoubleSetting(
    'window_width',
    section: 'windowSize',
    defaultValue: 1280,
    min: 400,
    max: 16384,
  );

  /// Window height.
  static const windowHeight = DoubleSetting(
    'window_height',
    section: 'windowSize',
    defaultValue: 720,
    min: 300,
    max: 16384,
  );

  /// Remember the PiP window position.
  static const rememberPipPosition = BoolSetting('rememberPipPosition', section: 'windowSize', defaultValue: true);

  /// PiP display.
  static const windowsPipDisplayId = StringSetting(
    'windows_pip_display_id',
    section: 'windowSize',
    defaultValue: '',
    backupKey: 'displayId',
  );

  /// PiP geometry.
  static const windowsPipWidth = DoubleSetting(
    'windows_pip_width',
    section: 'windowSize',
    defaultValue: 0,
    backupKey: 'windowsPipWidth',
  );

  /// PiP geometry.
  static const windowsPipHeight = DoubleSetting(
    'windows_pip_height',
    section: 'windowSize',
    defaultValue: 0,
    backupKey: 'windowsPipHeight',
  );

  /// PiP geometry.
  static const windowsPipX = DoubleSetting(
    'windows_pip_x',
    section: 'windowSize',
    defaultValue: 0,
    backupKey: 'windowsPipX',
  );

  /// PiP geometry.
  static const windowsPipY = DoubleSetting(
    'windows_pip_y',
    section: 'windowSize',
    defaultValue: 0,
    backupKey: 'windowsPipY',
  );

  /// Do not ask on exit.
  static const dontAskExit = BoolSetting('dontAskExit', section: 'exit', defaultValue: false);

  /// `exit` or `minimize`.
  static const exitChoose = StringSetting(
    'exitChoose',
    section: 'exit',
    defaultValue: 'exit',
    allowed: {'exit', 'minimize'},
  );

  /// Shutdown timer, minutes.
  static const autoShutDownTime = IntSetting(
    'autoShutDownTime',
    section: 'exit',
    defaultValue: 120,
    min: 1,
    max: 525600,
  );

  /// Shutdown timer.
  static const enableAutoShutDownTime = BoolSetting('enableAutoShutDownTime', section: 'exit', defaultValue: false);

  /// Start with Windows (3.x's default is on).
  static const enableStartUp = BoolSetting('enableStartUp', section: 'startup', defaultValue: true);

  // ---- recorder (lib/recorder/consts/recorder_keys.dart, recorder_config.dart) ----
  //
  // 3.x kept these in the same Hive box but never put them in backups (M8.1:
  // v4 backups carry them in a `recorder` section, which 3.x ignores). The
  // recorder (live_record `RecordSettings`) applies its own finer rules on
  // top (rw timeout and queue size are choices).

  /// Segment length, seconds.
  static const recordSegmentTime = IntSetting(
    'segmentTime',
    section: 'recorder',
    defaultValue: 300,
    min: 60,
    max: 3600,
  );

  /// Concurrent recordings.
  static const recordMaxTaskCount = IntSetting('maxTaskCount', section: 'recorder', defaultValue: 3, min: 1, max: 10);

  /// Retry an interrupted recording.
  static const recordAutoReconnect = BoolSetting('autoReconnect', section: 'recorder', defaultValue: true);

  /// Size limit of the recording folder, MiB.
  static const recordMaxCacheMB = IntSetting('maxCacheMB', section: 'recorder', defaultValue: 1024, min: 1);

  /// Delete the oldest recordings above [recordMaxCacheMB].
  static const recordEnableCacheLimit = BoolSetting('enableCacheLimit', section: 'recorder', defaultValue: false);

  /// Parent folder of the recordings ('' = the app's default). A path of
  /// this device, so backups do not carry it (like [backupDirectory]).
  static const recordSavePath = StringSetting(
    'recordSavePath',
    section: 'recorder',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  /// The recording quality preference, best first (3.x
  /// `PlayerConsts.resolutions`; the stored values are 3.x's).
  static const recordQualityChoices = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];

  /// Default recording quality, one of [recordQualityChoices].
  static const recordDefaultQuality = StringSetting(
    'default_quality',
    section: 'recorder',
    defaultValue: '原画',
    allowed: {'原画', '蓝光8M', '蓝光4M', '超清', '流畅'},
  );

  /// Retries before waiting for the room again.
  static const recordMaxRetryCount = IntSetting(
    'max_retry_count',
    section: 'recorder',
    defaultValue: 5,
    min: 1,
    max: 20,
  );

  /// Retry delay, seconds.
  static const recordRetryDelay = IntSetting('retry_delay', section: 'recorder', defaultValue: 30, min: 5, max: 120);

  /// Check waiting rooms until they go live.
  static const recordEnablePolling = BoolSetting('enable_polling', section: 'recorder', defaultValue: false);

  /// Live check interval, seconds.
  static const recordLiveCheckInterval = IntSetting(
    'live_check_interval',
    section: 'recorder',
    defaultValue: 30,
    min: 10,
    max: 300,
  );

  /// Double the delays after each failure.
  static const recordEnableBackoff = BoolSetting('enable_backoff', section: 'recorder', defaultValue: false);

  /// Upper bound of backed-off delays, seconds.
  static const recordMaxCheckInterval = IntSetting(
    'max_check_interval',
    section: 'recorder',
    defaultValue: 300,
    min: 300,
    max: 3600,
  );

  /// Resume waiting and interrupted recordings when the app starts.
  static const recordAutoStartOnBoot = BoolSetting('auto_start_on_boot', section: 'recorder', defaultValue: false);

  /// Record only the first video and audio stream.
  static const recordPreferBestStream = BoolSetting(
    'recorder_prefer_best_stream',
    section: 'recorder',
    defaultValue: true,
  );

  /// FFmpeg read/write timeout, seconds (15, 30 or 60).
  static const recordRwTimeout = IntSetting(
    'recorder_rw_timeout',
    section: 'recorder',
    defaultValue: 15,
    min: 15,
    max: 60,
  );

  /// FFmpeg input thread queue size (512 to 8192).
  static const recordThreadQueueSize = IntSetting(
    'recorder_thread_queue_size',
    section: 'recorder',
    defaultValue: 2048,
    min: 512,
    max: 8192,
  );

  /// Name the platform and streamer folders in pinyin.
  static const recordPinyinFolders = BoolSetting(
    'recorder_folder_naming_strategy',
    section: 'recorder',
    defaultValue: false,
  );

  /// Save the chat beside each recording.
  static const recordDanmaku = BoolSetting('recorder_record_danmaku', section: 'recorder', defaultValue: false);

  /// The recorder's settings, in 3.x's key order.
  static const List<Setting<Object>> recorder = [
    recordSegmentTime,
    recordMaxTaskCount,
    recordAutoReconnect,
    recordMaxCacheMB,
    recordEnableCacheLimit,
    recordSavePath,
    recordDefaultQuality,
    recordMaxRetryCount,
    recordRetryDelay,
    recordEnablePolling,
    recordLiveCheckInterval,
    recordEnableBackoff,
    recordMaxCheckInterval,
    recordAutoStartOnBoot,
    recordPreferBestStream,
    recordRwTimeout,
    recordThreadQueueSize,
    recordPinyinFolders,
    recordDanmaku,
  ];

  // ---- local interaction (modules/live_play/widgets/local_interaction/
  // local_interaction_controller.dart:86-114) ----
  //
  // 3.x kept these in the same Hive box and never put them in backups; the
  // 3.x import parks them in `legacy_values` until they are registered here
  // (U.2k), and v4 backups carry them in a `localInteraction` section, which
  // 3.x ignores. Ranges are the ones 3.x's style editor and
  // `buildDanmakuStyle` allowed.

  /// The local interaction (local danmaku, gifts) is on.
  static const localInteractionEnabled = BoolSetting(
    'localInteraction.enabled',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The local nickname (at most 20 characters).
  static const localInteractionUserName = StringSetting(
    'localInteraction.userName',
    section: 'localInteraction',
    defaultValue: 'Pure Live',
  );

  /// The local title's id.
  static const localInteractionTitle = StringSetting(
    'localInteraction.title',
    section: 'localInteraction',
    defaultValue: 'listener',
    allowed: {'listener', 'night_owl', 'supporter', 'guardian'},
  );

  /// Local danmaku fly over the picture (they always join the chat list).
  static const localInteractionShowAsDanmaku = BoolSetting(
    'localInteraction.showAsDanmaku',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The platform's badge before the local name.
  static const localInteractionShowPlatformBadge = BoolSetting(
    'localInteraction.showPlatformBadge',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The local level in the badge.
  static const localInteractionShowLevelBadge = BoolSetting(
    'localInteraction.showLevelBadge',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The banner over the picture when a local gift is sent.
  static const localInteractionEnableGiftEffects = BoolSetting(
    'localInteraction.enableGiftEffects',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The platform pack previewed in the settings.
  static const localInteractionPreviewPlatform = StringSetting(
    'localInteraction.previewPlatform',
    section: 'localInteraction',
    defaultValue: SiteIds.bilibili,
  );

  /// Local coins.
  static const localInteractionCoins = IntSetting(
    'localInteraction.coins',
    section: 'localInteraction',
    defaultValue: 1000,
    min: 0,
  );

  /// Local experience (a level per 500).
  static const localInteractionExperience = IntSetting(
    'localInteraction.experience',
    section: 'localInteraction',
    defaultValue: 0,
    min: 0,
  );

  /// Gifts and coins added, newest first (at most 30).
  static const localInteractionHistory = StringListSetting(
    'localInteraction.history',
    section: 'localInteraction',
    defaultValue: [],
  );

  /// The local danmaku template's id, or `custom`.
  static const localDanmakuPreset = StringSetting(
    'localInteraction.danmakuPreset',
    section: 'localInteraction',
    defaultValue: 'clean',
  );

  /// The local danmaku colour, ARGB.
  static const localDanmakuColor = IntSetting(
    'localInteraction.danmakuColor',
    section: 'localInteraction',
    defaultValue: 0xFFFFFFFF,
  );

  /// The local danmaku font size.
  static const localDanmakuFontSize = DoubleSetting(
    'localInteraction.danmakuFontSize',
    section: 'localInteraction',
    defaultValue: 19,
    min: 14,
    max: 32,
  );

  /// The local danmaku speed, pixels per second.
  static const localDanmakuSpeed = DoubleSetting(
    'localInteraction.danmakuSpeed',
    section: 'localInteraction',
    defaultValue: 130,
    min: 60,
    max: 260,
  );

  /// The local danmaku font weight.
  static const localDanmakuFontWeight = IntSetting(
    'localInteraction.danmakuFontWeight',
    section: 'localInteraction',
    defaultValue: 600,
    min: 400,
    max: 900,
  );

  /// The local danmaku outline.
  static const localDanmakuShowStroke = BoolSetting(
    'localInteraction.danmakuShowStroke',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The outline width.
  static const localDanmakuStrokeWidth = DoubleSetting(
    'localInteraction.danmakuStrokeWidth',
    section: 'localInteraction',
    defaultValue: 1.5,
    min: 0,
    max: 4,
  );

  /// Where local danmaku fly: `scroll`, `top` or `bottom`.
  static const localDanmakuPlacement = StringSetting(
    'localInteraction.danmakuPlacement',
    section: 'localInteraction',
    defaultValue: 'scroll',
    allowed: {'scroll', 'top', 'bottom'},
  );

  /// The local danmaku font: `system`, `rounded`, `serif` or `mono`.
  static const localDanmakuFontFamily = StringSetting(
    'localInteraction.danmakuFontFamily',
    section: 'localInteraction',
    defaultValue: 'system',
    allowed: {'system', 'rounded', 'serif', 'mono'},
  );

  /// Italic local danmaku.
  static const localDanmakuItalic = BoolSetting(
    'localInteraction.danmakuItalic',
    section: 'localInteraction',
    defaultValue: false,
  );

  /// The local danmaku opacity.
  static const localDanmakuOpacity = DoubleSetting(
    'localInteraction.danmakuOpacity',
    section: 'localInteraction',
    defaultValue: 1,
    min: 0.35,
    max: 1,
  );

  /// The local danmaku letter spacing.
  static const localDanmakuLetterSpacing = DoubleSetting(
    'localInteraction.danmakuLetterSpacing',
    section: 'localInteraction',
    defaultValue: 0,
    min: -0.5,
    max: 3,
  );

  /// The outline colour, ARGB.
  static const localDanmakuStrokeColor = IntSetting(
    'localInteraction.danmakuStrokeColor',
    section: 'localInteraction',
    defaultValue: 0xFF000000,
  );

  /// The shadow (glow) of local danmaku.
  static const localDanmakuShowShadow = BoolSetting(
    'localInteraction.danmakuShowShadow',
    section: 'localInteraction',
    defaultValue: false,
  );

  /// The shadow colour, ARGB.
  static const localDanmakuShadowColor = IntSetting(
    'localInteraction.danmakuShadowColor',
    section: 'localInteraction',
    defaultValue: 0xFF000000,
  );

  /// The shadow blur.
  static const localDanmakuShadowBlur = DoubleSetting(
    'localInteraction.danmakuShadowBlur',
    section: 'localInteraction',
    defaultValue: 2,
    min: 0,
    max: 6,
  );

  /// The shadow offset.
  static const localDanmakuShadowOffset = DoubleSetting(
    'localInteraction.danmakuShadowOffset',
    section: 'localInteraction',
    defaultValue: 1,
    min: 0,
    max: 4,
  );

  /// How long a fixed (top or bottom) local danmaku stays, milliseconds.
  static const localDanmakuFixedDurationMs = IntSetting(
    'localInteraction.danmakuFixedDurationMs',
    section: 'localInteraction',
    defaultValue: 4000,
    min: 2000,
    max: 10000,
  );

  /// The local interaction's settings, in 3.x's order.
  static const List<Setting<Object>> localInteraction = [
    localInteractionEnabled,
    localInteractionUserName,
    localInteractionTitle,
    localInteractionShowAsDanmaku,
    localInteractionShowPlatformBadge,
    localInteractionShowLevelBadge,
    localInteractionEnableGiftEffects,
    localInteractionPreviewPlatform,
    localInteractionCoins,
    localInteractionExperience,
    localInteractionHistory,
    localDanmakuPreset,
    localDanmakuColor,
    localDanmakuFontSize,
    localDanmakuSpeed,
    localDanmakuFontWeight,
    localDanmakuShowStroke,
    localDanmakuStrokeWidth,
    localDanmakuPlacement,
    localDanmakuFontFamily,
    localDanmakuItalic,
    localDanmakuOpacity,
    localDanmakuLetterSpacing,
    localDanmakuStrokeColor,
    localDanmakuShowShadow,
    localDanmakuShadowColor,
    localDanmakuShadowBlur,
    localDanmakuShadowOffset,
    localDanmakuFixedDurationMs,
  ];

  // ---- backup (backup_controller.dart:37) ----

  /// Last backup folder (this device).
  static const backupDirectory = StringSetting(
    'backupDirectory',
    section: 'backup',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  /// Where update packages are downloaded (3.x `CacheController`'s
  /// `downloadDirectoryPath`); empty is the platform default. A path of this
  /// device, so backups do not carry it.
  static const downloadDirectoryPath = StringSetting(
    'downloadDirectoryPath',
    section: 'cache',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  // ---- log (new; 3.x's switch lasted one session) ----

  /// Write the app log to a file.
  static const enableLocalLog = BoolSetting('enableLocalLog', section: 'log', defaultValue: false);

  /// The lowest level the log keeps: `debug`, `info`, `warning` or `error`.
  static const logLevel = StringSetting(
    'logLevel',
    section: 'log',
    defaultValue: 'info',
    allowed: {'debug', 'info', 'warning', 'error'},
  );

  // ---- accounts, outside the cookie secrets ----

  /// Bilibili user id of the stored cookie (not secret).
  static const bilibiliUid = IntSetting(
    'bilibiliUid',
    section: 'cookie',
    defaultValue: 0,
    scope: SettingScope.internal,
  );

  /// When the Douyu cookie was saved (epoch seconds, 0 = unknown).
  static const douyuCookieSavedAt = IntSetting(
    'douyuCookieSavedAt',
    section: 'cookie',
    defaultValue: 0,
    scope: SettingScope.internal,
  );

  // ---- interface mode (M14.1) ----

  /// New (M14.1): which interface the app shows — `auto` (the TV interface on
  /// an Android TV, the phone/desktop one elsewhere), `phone` or `tv`. Kept
  /// on this device only: a phone's backup must not switch a TV to the phone
  /// interface, so it is never exported (and a settings reset keeps it).
  static const uiMode = StringSetting(
    'uiMode',
    section: 'app',
    defaultValue: 'auto',
    allowed: {'auto', 'phone', 'tv'},
    scope: SettingScope.internal,
  );

  /// New (docs/ui/compare/U.15a c2): the TV interface grows the focused card,
  /// button or tab by 5 %; a slow box can switch it off and keep only the
  /// focus ring.
  static const tvFocusZoom = BoolSetting('tvFocusZoom', section: 'app', defaultValue: true);

  // ---- internal ----

  /// The LAN-sync device id 3.x generated (remote_sync_service.dart:134).
  static const remoteSyncDeviceId = StringSetting(
    'remote_sync_device_id',
    section: 'meta',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  /// Every setting, in registry order.
  static const List<Setting<Object>> all = [
    autoRefreshTime,
    enableDenseFavorites,
    enableBackgroundPlay,
    enableAsmrSleepMode,
    asmrSleepMinutes,
    enableRotateScreen,
    enableScreenKeepOn,
    enableAutoCheckUpdate,
    useGitHubOriginForUpdates,
    enableFullScreenDefault,
    showSplashPage,
    refreshRateMode,
    preferRealOnlineCounts,
    realOnlinePlatforms,
    savedMenuIds,
    enableMultiView,
    enableNewWindowPlay,
    showUnplayableInDiscover,
    douyuForceRenew,
    twitchLanguages,
    hotAreasList,
    preferPlatform,
    historyLimit,
    themeMode,
    enableDynamicTheme,
    themeColorSwitch,
    language,
    crossAxisSpacing,
    mainAxisSpacing,
    loadingStyle,
    loadingStyleColorSwitch,
    textScaleFactor,
    fontSizeBodySmall,
    fontSizeBodyMedium,
    fontSizeBodyLarge,
    fontSizeTitleMedium,
    fontSizeTitleLarge,
    fontFamilyName,
    fontFamilyFileName,
    danmakuFontFamilyFileName,
    videoFitIndex,
    videoPlayerKey,
    preferResolution,
    preferResolutionCellular,
    enableCodec,
    preferH264,
    playerCompatMode,
    customPlayerOutput,
    videoOutputDriver,
    audioOutputDriver,
    videoHardwareDecoder,
    floatPlay,
    windowsPipAlwaysOnTop,
    autoPipOnLeave,
    enableRtxVsr,
    useHardStopOnExit,
    enablePortraitStreamAdaptation,
    portraitAdaptiveHeight,
    portraitLayoutMode,
    portraitFullscreenPolicy,
    portraitFullscreenDisplayMode,
    portraitPipFollowSource,
    portraitDanmakuMode,
    rememberPortraitRoomOverride,
    showPortraitDiagnostics,
    portraitRoomOverrides,
    hideDanmaku,
    noEmojiMode,
    danmakuTopArea,
    danmakuArea,
    danmakuBottomArea,
    danmakuSpeed,
    danmakuFontSize,
    danmakuFontWeight,
    danmakuFontBorder,
    danmakuOpacity,
    enableDanmakuDisplay,
    enableDanmakuStroke,
    danmakuListStyle,
    danmakuFps,
    danmakuAutoFps,
    enableDanmakuTapInteraction,
    enableDanmakuLongPressInteraction,
    collapseRepeatedDanmaku,
    repeatedDanmakuWindowSeconds,
    savedDanmakuTemplate,
    danmakuFontFamilyName,
    enablePipDanmaku,
    pipDanmakuAutoScale,
    pipDanmakuNoEmojiMode,
    pipDanmakuUseOriginalColor,
    pipDanmakuColor,
    pipDanmakuFontSize,
    pipDanmakuFontWeight,
    pipDanmakuSpeed,
    pipDanmakuOpacity,
    pipDanmakuArea,
    pipDanmakuMaxVisibleCount,
    pipDanmakuEmitInterval,
    pipDanmakuFps,
    pipDanmakuAutoFps,
    filterDouyuSuspectedAutomatedMessages,
    enableDanmakuSimilarityFilter,
    danmakuSimilarityThreshold,
    danmakuSimilarityCacheDuration,
    danmakuSimilarityMaxCacheSize,
    youtubeShowAllChat,
    defaultMobileVolume,
    defaultDesktopVolume,
    globalVolumeMute,
    roomVolumes,
    roomCardMobilePreset,
    roomCardDesktopPreset,
    roomCardMobileConfig,
    roomCardDesktopConfig,
    pageShowSizeSelector,
    pageShowGotoButton,
    pageShowScrollTop,
    pageDefaultSize,
    pageSizeOptions,
    autoRefreshFavorite,
    refreshFavoriteOnResume,
    autoRefreshInterval,
    maxConcurrentRefresh,
    autoRefreshThumbnails,
    thumbnailRefreshInterval,
    selectedSourceName,
    selectedSourceId,
    isAutoSyncEnabled,
    autoSyncHoursInterval,
    customIptvUserAgent,
    m3uDirectory,
    enableProxy,
    proxyHost,
    proxyPort,
    enableAppProxy,
    appProxyHost,
    appProxyPort,
    windowWidth,
    windowHeight,
    rememberPipPosition,
    windowsPipDisplayId,
    windowsPipWidth,
    windowsPipHeight,
    windowsPipX,
    windowsPipY,
    dontAskExit,
    exitChoose,
    autoShutDownTime,
    enableAutoShutDownTime,
    enableStartUp,
    ...recorder,
    ...localInteraction,
    backupDirectory,
    downloadDirectoryPath,
    enableLocalLog,
    logLevel,
    bilibiliUid,
    douyuCookieSavedAt,
    remoteSyncDeviceId,
    uiMode,
    tvFocusZoom,
  ];

  static final Map<String, Setting<Object>> _byKey = {for (final setting in all) setting.key: setting};

  /// The setting stored under [key], if any.
  static Setting<Object>? byKey(String key) => _byKey[key];
}
