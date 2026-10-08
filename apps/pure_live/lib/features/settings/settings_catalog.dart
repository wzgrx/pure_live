import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/settings/appearance_pages.dart';
import 'package:pure_live/features/settings/audience_pages.dart';
import 'package:pure_live/features/settings/data_tools.dart';
import 'package:pure_live/features/settings/live_alert_tiles.dart';
import 'package:pure_live/features/settings/playback_tiles.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';

/// "30 分钟", "1.5 小时", "2 小时" (3.x's refresh interval labels).
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes ${i18n('minute')}';
  if (minutes % 60 == 0) return '${minutes ~/ 60} ${i18n('hour')}';
  if (minutes % 30 == 0) return '${minutes / 60} ${i18n('hour')}';
  return '$minutes ${i18n('minute')}';
}

/// [formatMinutes] with whole days ("1 天", 3.x's sleep timer).
String formatDuration(int minutes) =>
    minutes >= 1440 && minutes % 1440 == 0 ? '${minutes ~/ 1440} ${i18n('day')}' : formatMinutes(minutes);

String _percent(double value) => '${(value * 100).round()}%';
String _whole(double value) => '${value.round()}';

/// Video fit names, by the index `videoFitIndex` stores (3.x
/// `AppConsts.videoFitType`).
const List<String> videoFitKeys = [
  'video_fit_default',
  'video_fit_crop_center',
  'video_fit_fill_screen',
  'video_fit_fit_height',
  'video_fit_fit_width',
  'video_fit_scale_down',
];

/// Quality names and their labels (3.x `PlayerConsts.resolutionLabelKeys`).
const Map<String, String> resolutionKeys = {
  '原画': 'prefer_resolution_option_original',
  '蓝光8M': 'prefer_resolution_option_blu_ray_8m',
  '蓝光4M': 'prefer_resolution_option_blu_ray_4m',
  '超清': 'prefer_resolution_option_super_hd',
  '流畅': 'prefer_resolution_option_smooth',
};

/// The follow refresh intervals (3.x `refresh_settings.dart`, 12 steps).
const List<int> followRefreshMinutes = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360];

/// The cover refresh intervals (3.x, 8 steps).
const List<int> coverRefreshMinutes = [5, 10, 15, 30, 60, 120, 240, 360];

List<SettingsChoice<String>> _keyed(Map<String, String> labels, [Map<String, String> descriptions = const {}]) => [
  for (final MapEntry(:key, :value) in labels.entries)
    (value: key, label: i18n(value), description: descriptions[key] == null ? null : i18n(descriptions[key]!)),
];

List<SettingsChoice<int>> _minutes(List<int> values) => [
  for (final value in values) (value: value, label: formatMinutes(value), description: null),
];

bool _notIos(SettingsEnv env) => !env.isIOS;
bool _android(SettingsEnv env) => env.isAndroid;
bool _windows(SettingsEnv env) => env.isWindows;
bool _mobile(SettingsEnv env) => env.isMobile;
bool _desktop(SettingsEnv env) => !env.isMobile;
bool _refreshRate(SettingsEnv env) => env.hasRefreshRate;

/// Hardware decoding is taken over by the compatibility mode (Android) and
/// by custom mpv drivers (U.6c c5, P8).
List<SettingRequirement> _hardwareDecodingFree() => [
  if (defaultTargetPlatform == TargetPlatform.android)
    (setting: Settings.playerCompatMode, value: false, reason: i18n('settings_taken_over_by_compat')),
  (setting: Settings.customPlayerOutput, value: false, reason: i18n('settings_taken_over_by_custom_output')),
];

/// The custom drivers do nothing in the compatibility mode (Android).
List<SettingRequirement> _customOutputFree() => [
  if (defaultTargetPlatform == TargetPlatform.android)
    (setting: Settings.playerCompatMode, value: false, reason: i18n('settings_taken_over_by_compat')),
];

List<SettingRequirement> _pipOn() => [needsOn(Settings.enablePipDanmaku, 'pip_danmaku_enable')];

typedef _Build = Widget Function(BuildContext context, SettingsEntry entry);
typedef _Requires = List<SettingRequirement> Function();

/// A small builder for the catalogue: one section and group at a time.
final class _Catalog {
  final List<SettingsEntry> entries = [];

  /// The section of the entries added next.
  late SettingsSection section;

  /// The group title of the entries added next.
  late String group;

  /// The sub-page of the entries added next.
  SettingsSubpage? subpage;

  void add(
    String id,
    String title,
    _Build build, {
    String? desc,
    List<Setting<Object>> settings = const [],
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
    bool opens = false,
  }) => entries.add(
    SettingsEntry(
      id: id,
      section: section,
      subpage: subpage,
      group: group,
      title: title,
      description: desc,
      build: build,
      settings: settings,
      keywords: keywords,
      when: when ?? (_) => true,
      opens: opens,
    ),
  );

  void toggle(
    String id,
    String title,
    BoolSetting setting,
    IconData? icon, {
    String? desc,
    bool inverted = false,
    BoolSetting? enabledBy,
    _Requires? requires,
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
  }) => add(
    id,
    title,
    (context, entry) => SettingToggleTile(
      entry: entry,
      setting: setting,
      icon: icon,
      inverted: inverted,
      enabledBy: enabledBy,
      requires: requires?.call() ?? const [],
    ),
    desc: desc,
    settings: [setting],
    keywords: keywords,
    when: when,
  );

  void slider(
    String id,
    String title,
    Setting<Object> setting,
    IconData? icon, {
    required double min,
    required double max,
    required String Function(double value) format,
    double? step,
    String? desc,
    BoolSetting? enabledBy,
    _Requires? requires,
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
  }) => add(
    id,
    title,
    (context, entry) => SettingSliderTile(
      entry: entry,
      setting: setting,
      icon: icon,
      min: min,
      max: max,
      step: step,
      format: format,
      enabledBy: enabledBy,
      requires: requires?.call() ?? const [],
    ),
    desc: desc,
    settings: [setting],
    keywords: keywords,
    when: when,
  );

  void choice<T extends Object>(
    String id,
    String title,
    Setting<T> setting,
    IconData? icon,
    List<SettingsChoice<T>> Function() options, {
    String? desc,
    String? hint,
    BoolSetting? enabledBy,
    _Requires? requires,
    bool valueBelow = false,
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
  }) => add(
    id,
    title,
    (context, entry) => SettingChoiceTile<T>(
      entry: entry,
      setting: setting,
      icon: icon,
      options: options,
      hint: hint == null ? null : i18n(hint),
      enabledBy: enabledBy,
      requires: requires?.call() ?? const [],
      valueBelow: valueBelow,
    ),
    desc: desc,
    settings: [setting],
    keywords: keywords,
    when: when,
  );

  void number(
    String id,
    String title,
    IntSetting setting,
    IconData icon, {
    required List<int> presets,
    required String Function(int value) label,
    String? desc,
    String? unit,
    String? hint,
    String? inputLabel,
    String? rangeText,
    BoolSetting? enabledBy,
    _Requires? requires,
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
  }) => add(
    id,
    title,
    (context, entry) => SettingNumberTile(
      entry: entry,
      setting: setting,
      icon: icon,
      presets: presets,
      label: label,
      unit: unit == null ? null : i18n(unit),
      hint: hint == null ? null : i18n(hint),
      inputLabel: inputLabel == null ? null : i18n(inputLabel),
      rangeText: rangeText == null ? null : i18n(rangeText),
      enabledBy: enabledBy,
      requires: requires?.call() ?? const [],
    ),
    desc: desc,
    settings: [setting],
    keywords: keywords,
    when: when,
  );

  void link(
    String id,
    String title,
    IconData? icon, {
    String? route,
    WidgetBuilder? page,
    SettingsSubpage? subpage,
    String? desc,
    _Requires? requires,
    List<Setting<Object>> settings = const [],
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
  }) => add(
    id,
    title,
    (context, entry) => SettingLinkTile(
      entry: entry,
      icon: icon,
      route: route,
      page: page,
      subpage: subpage,
      requires: requires?.call() ?? const [],
    ),
    desc: desc,
    settings: settings,
    keywords: keywords,
    when: when,
    opens: true,
  );
}

/// Lines above and under a group, by group title key: (above, under).
const Map<String, (String?, String?)> settingsGroupNotes = {
  'settings_nav_group_bar': ('settings_nav_hint', 'settings_nav_footer'),
  'settings_group_pager': (null, 'settings_paging_scroll_top_note'),
  'audience_display_mode': (null, 'audience_ranking_rule_desc'),
  'settings_group_audience_heat_only': (null, 'audience_metric_fallback_desc'),
  'settings_group_download': (null, 'settings_download_note'),
};

/// Something under a group other than a line of text, by group title key
/// (the MPV warning with its link, U.6c c10).
final Map<String, WidgetBuilder> settingsGroupFooters = {'mpv_advanced_settings': (context) => const MpvDocsNote()};

/// Group title keys that draw no title (a lone switch at the top of a page,
/// the "restore defaults" row at its end).
bool settingsUntitledGroup(String group) => group.startsWith('_');

/// A line at the top of a page, by section or sub-page name.
const Map<String, String> settingsPageIntros = {};

/// Every settings row, in display order: the pages of the overview (3.x's
/// settings pages, U.6a) and their rows. Appearance and navigation follow
/// U.6b; playback U.6c; general, platforms, refresh and network U.6d; data
/// U.6e. The danmaku page is the live room's component (F02 c1); its rows
/// here are for search.
final List<SettingsEntry> settingsCatalog = _build();

List<SettingsEntry> _build() {
  final c = _Catalog()
    // ---- appearance (U.6b) ----
    ..section = SettingsSection.appearance
    ..group = 'settings_group_theme'
    ..add(
      'theme_mode',
      'change_theme_mode',
      (context, entry) => ThemeModeTile(entry: entry),
      desc: 'change_theme_mode_subtitle',
      settings: [Settings.themeMode],
      keywords: ['dark', 'light', '深色', '浅色', '夜间', '暗色'],
    )
    ..add(
      'pure_black',
      'settings_pure_black',
      (context, entry) => PureBlackTile(entry: entry),
      desc: 'settings_pure_black_desc',
      settings: [Settings.pureBlackTheme],
      keywords: ['black', 'OLED', 'AMOLED', '黑色', '夜间'],
    )
    ..add(
      'theme_color',
      'change_theme_color',
      (context, entry) => ThemeColorTile(entry: entry),
      desc: 'change_theme_color_subtitle',
      settings: [Settings.themeColorSwitch],
      keywords: ['color', 'colour', '颜色', '主题色'],
    )
    ..toggle(
      'dynamic_color',
      'enable_dynamic_color',
      Settings.enableDynamicTheme,
      AppIcons.dynamicColor,
      desc: 'enable_dynamic_color_subtitle',
      keywords: ['Material You', 'monet', '壁纸'],
      when: _notIos,
    )
    ..add(
      'loading_style',
      'change_loading_style',
      (context, entry) => LoadingStyleTile(entry: entry),
      desc: 'change_loading_style_subtitle',
      settings: [Settings.loadingStyle, Settings.loadingStyleColorSwitch],
      keywords: ['loading', '加载', '动画'],
      opens: true,
    )
    ..group = 'settings_group_cards_lists'
    ..link(
      'room_card',
      'room_card_settings',
      AppIcons.roomCardSettings,
      page: (_) => const RoomCardSettingsPage(),
      desc: 'room_card_settings_subtitle',
      settings: [
        Settings.roomCardMobilePreset,
        Settings.roomCardDesktopPreset,
        Settings.roomCardMobileConfig,
        Settings.roomCardDesktopConfig,
      ],
      keywords: ['card', '卡片', '封面', '圆角'],
    )
    ..add(
      'cross_spacing',
      'cross_axis_spacing',
      (context, entry) => SpacingTile(entry: entry, setting: Settings.crossAxisSpacing, icon: AppIcons.columnSpacing),
      desc: 'cross_axis_spacing_subtitle',
      settings: [Settings.crossAxisSpacing],
      keywords: ['间距', 'spacing', '网格'],
    )
    ..add(
      'main_spacing',
      'main_axis_spacing',
      (context, entry) => SpacingTile(entry: entry, setting: Settings.mainAxisSpacing, icon: AppIcons.rowSpacing),
      desc: 'main_axis_spacing_subtitle',
      settings: [Settings.mainAxisSpacing],
      keywords: ['间距', 'spacing', '网格'],
    )
    ..toggle(
      'page_scroll_top',
      'show_scroll_to_top',
      Settings.pageShowScrollTop,
      AppIcons.scrollToTop,
      desc: 'show_scroll_to_top_subtitle',
      keywords: ['置顶', 'top'],
    )
    ..link(
      'page_settings',
      'page_settings',
      AppIcons.pageSettings,
      subpage: SettingsSubpage.paging,
      desc: 'settings_page_settings_desc',
      keywords: ['分页', 'page'],
      when: _desktop,
    )
    ..group = 'settings_group_language_ui'
    ..add(
      'language',
      'change_language',
      (context, entry) => LanguageTile(entry: entry),
      desc: 'change_language_subtitle',
      settings: [Settings.language],
      keywords: ['language', '语言', 'English', '中文'],
    )
    // M14.1: the TV interface. The app follows a change at once (it builds
    // the other interface's routes), so no restart is needed.
    ..choice(
      'ui_mode',
      'ui_mode',
      Settings.uiMode,
      AppIcons.uiMode,
      () => _keyed(
        const {'auto': 'ui_mode_auto', 'phone': 'ui_mode_phone', 'tv': 'ui_mode_tv'},
        const {'auto': 'ui_mode_auto_desc'},
      ),
      desc: 'ui_mode_desc',
      keywords: ['TV', '电视', '遥控器', 'remote', 'phone', '手机', '界面'],
    )
    ..group = 'settings_group_fonts'
    ..add(
      'app_font',
      'settings_font',
      (context, entry) => FontFamilyTile(entry: entry, setting: Settings.fontFamilyName, icon: AppIcons.appFont),
      desc: 'settings_font_desc',
      settings: [Settings.fontFamilyName, Settings.fontFamilyFileName],
      keywords: ['font', '字体'],
      opens: true,
    )
    ..add(
      'text_scale',
      'settings_text_size',
      (context, entry) => TextScaleTile(entry: entry),
      desc: 'settings_text_size_desc',
      settings: [Settings.textScaleFactor],
      keywords: ['font', '字号', '缩放', '文字', 'text size'],
    )
    ..link(
      'font_sizes',
      'font_settings_title',
      AppIcons.fontSizes,
      page: (_) => const FontSizesPage(),
      desc: 'settings_font_sizes_row_desc',
      settings: [
        Settings.fontSizeBodySmall,
        Settings.fontSizeBodyMedium,
        Settings.fontSizeBodyLarge,
        Settings.fontSizeTitleMedium,
        Settings.fontSizeTitleLarge,
      ],
      keywords: ['字号', 'font size'],
    )
    // The pager of computers (3.x showed it on any screen wider than 680,
    // where phones have no pager; U.6b c6).
    ..subpage = SettingsSubpage.paging
    ..group = 'settings_group_pager'
    ..toggle(
      'page_size_selector',
      'show_page_size_selector',
      Settings.pageShowSizeSelector,
      AppIcons.pageSizeSelector,
      desc: 'show_page_size_selector_subtitle',
      keywords: ['分页', 'page'],
      when: _desktop,
    )
    ..toggle(
      'page_goto',
      'show_goto_button',
      Settings.pageShowGotoButton,
      AppIcons.pageGoto,
      desc: 'show_goto_button_subtitle',
      keywords: ['分页', '跳转', 'page'],
      when: _desktop,
    )
    ..add(
      'page_size_options',
      'page_size_options_manage',
      (context, entry) => PageSizeOptionsTile(entry: entry),
      settings: [Settings.pageSizeOptions],
      keywords: ['分页', 'page'],
      when: _desktop,
    )
    ..number(
      'page_default_size',
      'settings_page_default_size_title',
      Settings.pageDefaultSize,
      AppIcons.pageDefaultSize,
      presets: const [0, 12, 20, 30, 40, 60],
      label: (value) => value == 0 ? i18n('settings_page_size_auto') : '$value',
      desc: 'settings_page_default_size_hint',
      unit: 'items_per_page',
      keywords: ['分页', 'page'],
      when: _desktop,
    )
    ..subpage = null
    // ---- navigation (U.6b) ----
    ..section = SettingsSection.navigation
    ..group = 'settings_nav_group_home'
    ..toggle(
      'multiview',
      'multiview_title',
      Settings.enableMultiView,
      AppIcons.multiview,
      desc: 'settings_nav_multiview_desc',
      keywords: ['多画面', 'multi'],
    )
    ..group = 'settings_nav_group_bar'
    ..add(
      'home_menus',
      'settings_home_menus',
      (context, entry) => HomeMenusList(entry: entry),
      settings: [Settings.savedMenuIds],
      keywords: ['菜单', '底栏', '导航', 'menu', 'tab', '关注', '热门', '分区', '录制中心'],
    )
    // ---- platforms (U.6d d8) ----
    ..section = SettingsSection.platforms
    ..group = 'settings_group_platforms'
    ..link(
      'platform_list',
      'platform_display',
      AppIcons.settingsPlatformList,
      route: RoutePath.kSettingsHotAreas,
      desc: 'platform_display_subtitle',
      settings: [Settings.hotAreasList],
      keywords: ['平台', 'platform'],
    )
    ..add(
      'prefer_platform',
      'prefer_platform',
      (context, entry) => PreferPlatformTile(entry: entry),
      desc: 'prefer_platform_subtitle',
      settings: [Settings.preferPlatform],
      keywords: ['平台', 'platform'],
    )
    ..group = 'settings_group_accounts_tags'
    ..link(
      'accounts',
      'settings_accounts',
      AppIcons.platformAccounts,
      route: RoutePath.kSettingsAccount,
      desc: 'settings_accounts_desc',
      keywords: ['Cookie', '登录', 'login', '账号', '三方认证'],
    )
    ..link(
      'tags',
      'tag_management',
      AppIcons.tag,
      route: RoutePath.kSettingsTags,
      desc: 'tag_management_subtitle',
      keywords: ['分组', 'tag'],
    )
    // v4's own platform options (UPGRADES 2-1, 8-3, 不可播放).
    ..group = 'settings_group_discover'
    ..toggle(
      'show_unplayable',
      'settings_show_unplayable',
      Settings.showUnplayableInDiscover,
      AppIcons.settingsUnplayable,
      desc: 'settings_show_unplayable_desc',
      keywords: ['付费', '加锁', '受限'],
    )
    ..add(
      'twitch_languages',
      'settings_twitch_languages',
      (context, entry) => TwitchLanguagesTile(entry: entry),
      desc: 'settings_twitch_languages_desc',
      settings: [Settings.twitchLanguages],
      keywords: ['Twitch', '语言', 'language'],
    )
    ..toggle(
      'douyu_renew',
      'settings_douyu_renew',
      Settings.douyuForceRenew,
      AppIcons.settingsDouyuRenew,
      desc: 'settings_douyu_renew_desc',
      keywords: ['斗鱼', 'douyu', 'Cookie'],
    )
    // ---- refresh (U.6d d10–d12) ----
    ..section = SettingsSection.refresh
    ..group = 'settings_group_follow_list'
    ..toggle(
      'auto_refresh',
      'auto_refresh_follow',
      Settings.autoRefreshFavorite,
      AppIcons.settingsAutoRefresh,
      desc: 'auto_refresh_follow_subtitle',
      keywords: ['刷新', 'refresh'],
    )
    ..choice<int>(
      'refresh_interval',
      'auto_refresh_interval',
      Settings.autoRefreshInterval,
      AppIcons.settingsInterval,
      () => _minutes(followRefreshMinutes),
      requires: () => [needsOn(Settings.autoRefreshFavorite, 'auto_refresh_follow')],
      keywords: ['刷新', 'refresh'],
    )
    ..toggle(
      'refresh_on_resume',
      'settings_refresh_on_resume',
      Settings.refreshFavoriteOnResume,
      AppIcons.settingsRefreshOnResume,
      desc: 'settings_refresh_on_resume_desc',
      keywords: ['刷新', 'refresh', '收藏'],
    )
    ..add(
      'refresh_concurrency',
      'max_concurrent_refresh',
      (context, entry) => SettingCounterTile(
        entry: entry,
        setting: Settings.maxConcurrentRefresh,
        icon: AppIcons.settingsConcurrency,
        min: 1,
        max: 20,
      ),
      desc: 'settings_refresh_concurrency_desc',
      settings: [Settings.maxConcurrentRefresh],
      keywords: ['刷新', 'refresh', '并发'],
    )
    // O01.1 (V01.1): "开播提醒", a system notification, so Android only.
    ..group = 'settings_group_live_alert'
    ..add(
      'live_alert',
      'live_alert',
      (context, entry) => GatedToggleTile(
        entry: entry,
        setting: Settings.liveAlertEnabled,
        icon: AppIcons.settingsLiveAlert,
        failedKey: 'live_alert_apply_failed',
      ),
      desc: 'live_alert_desc',
      settings: [Settings.liveAlertEnabled],
      keywords: ['开播', '提醒', '通知', 'notification'],
      when: _android,
    )
    ..add(
      'live_alert_tags',
      'live_alert_tags',
      (context, entry) => LiveAlertTagsTile(entry: entry),
      desc: 'live_alert_tags_desc',
      settings: [Settings.liveAlertTagIds],
      keywords: ['开播', '提醒', '标签', 'tag'],
      when: _android,
    )
    ..group = 'settings_group_covers'
    ..toggle(
      'refresh_covers',
      'auto_refresh_thumbnails',
      Settings.autoRefreshThumbnails,
      AppIcons.settingsAutoCovers,
      desc: 'auto_refresh_thumbnails_subtitle',
      keywords: ['封面', 'cover'],
    )
    ..choice<int>(
      'cover_interval',
      'thumbnail_refresh_interval',
      Settings.thumbnailRefreshInterval,
      AppIcons.settingsInterval,
      () => _minutes(coverRefreshMinutes),
      requires: () => [needsOn(Settings.autoRefreshThumbnails, 'auto_refresh_thumbnails')],
      keywords: ['封面', 'cover'],
    )
    // 3.x kept the history size on the history page; v4 put it here.
    ..group = 'history'
    ..number(
      'history_limit',
      'history_limit',
      Settings.historyLimit,
      AppIcons.settingsHistoryLimit,
      presets: const [0, 20, 50, 100, 200, 500],
      label: (value) => value == 0 ? i18n('settings_no_limit') : '$value',
      desc: 'settings_history_limit_desc',
      keywords: ['历史', 'history'],
    )
    // ---- video (U.6c c2) ----
    ..section = SettingsSection.video
    ..group = 'audio_settings'
    ..add(
      'global_mute',
      'global_mute',
      (context, entry) => GlobalMuteTile(entry: entry),
      desc: 'global_mute_subtitle',
      settings: [Settings.globalVolumeMute],
      keywords: ['静音', 'mute'],
    )
    ..slider(
      'mobile_volume',
      'mobile_default_volume',
      Settings.defaultMobileVolume,
      AppIcons.settingsPhoneVolume,
      min: 0,
      max: 1,
      step: 0.01,
      format: _percent,
      keywords: ['音量', 'volume'],
      when: _mobile,
    )
    ..slider(
      'desktop_volume',
      'desktop_default_volume',
      Settings.defaultDesktopVolume,
      AppIcons.settingsDesktopVolume,
      min: 0,
      max: 1,
      step: 0.01,
      format: _percent,
      keywords: ['音量', 'volume'],
      when: _desktop,
    )
    ..group = 'video_quality_settings'
    ..choice<String>(
      'prefer_resolution',
      'prefer_resolution',
      Settings.preferResolution,
      AppIcons.settingsQuality,
      () => _keyed(resolutionKeys),
      desc: 'prefer_resolution_subtitle',
      keywords: ['画质', 'quality', 'Wi-Fi'],
    )
    ..choice<String>(
      'prefer_resolution_cellular',
      'mobile_quality',
      Settings.preferResolutionCellular,
      AppIcons.settingsCellularQuality,
      () => _keyed(resolutionKeys),
      desc: 'mobile_quality_subtitle',
      keywords: ['画质', 'quality', '流量', '4G', '5G'],
      when: _mobile,
    )
    ..toggle(
      'prefer_h264',
      'settings_prefer_h264',
      Settings.preferH264,
      AppIcons.settingsH264,
      desc: 'settings_prefer_h264_desc',
      keywords: ['HEVC', 'H.265', 'H264', '编码'],
    )
    ..choice<int>(
      'video_fit',
      'settings_video_fit',
      Settings.videoFitIndex,
      AppIcons.settingsVideoFit,
      () => [for (var i = 0; i < videoFitKeys.length; i++) (value: i, label: i18n(videoFitKeys[i]), description: null)],
      desc: 'settings_video_fit_desc',
      keywords: ['比例', '裁剪', 'fit', 'crop'],
    )
    ..group = 'playback_behavior_settings'
    ..toggle(
      'fullscreen_default',
      'enable_fullscreen_default',
      Settings.enableFullScreenDefault,
      AppIcons.settingsFullscreenDefault,
      desc: 'enable_fullscreen_default_subtitle',
      keywords: ['全屏', 'fullscreen'],
    )
    ..toggle(
      'screen_keep_on',
      'enable_screen_keep_on',
      Settings.enableScreenKeepOn,
      AppIcons.settingsScreenKeepOn,
      desc: 'enable_screen_keep_on_subtitle',
      when: _android,
    )
    ..link(
      'portrait',
      'portrait_live_settings',
      AppIcons.settingsPortrait,
      subpage: SettingsSubpage.portrait,
      desc: 'portrait_live_settings_desc',
      keywords: ['竖屏', 'portrait'],
    )
    ..link(
      'audience',
      'audience_metric_settings',
      AppIcons.settingsAudience,
      subpage: SettingsSubpage.audience,
      desc: 'audience_metric_settings_desc',
      keywords: ['人数', '热度', '在线', 'viewers'],
    )
    ..group = 'settings_group_background_sleep'
    ..add(
      'background_play',
      'enable_background_play',
      (context, entry) => GatedToggleTile(
        entry: entry,
        setting: Settings.enableBackgroundPlay,
        icon: AppIcons.settingsBackgroundPlay,
        failedKey: 'background_play_apply_failed',
      ),
      desc: 'enable_background_play_subtitle',
      settings: [Settings.enableBackgroundPlay],
      keywords: ['后台', 'background'],
      // iOS too (U.17a).
      when: _mobile,
    )
    ..add(
      'asmr_sleep',
      'asmr_sleep_mode',
      (context, entry) => GatedToggleTile(
        entry: entry,
        setting: Settings.enableAsmrSleepMode,
        icon: AppIcons.settingsAutoSleep,
        failedKey: 'asmr_sleep_mode_apply_failed',
      ),
      desc: 'asmr_sleep_mode_desc',
      settings: [Settings.enableAsmrSleepMode],
      keywords: ['睡眠', '定时', 'sleep', '助眠'],
      when: _android,
    )
    ..number(
      'asmr_minutes',
      'asmr_sleep_timer',
      Settings.asmrSleepMinutes,
      AppIcons.settingsSleepMinutes,
      presets: const [15, 30, 45, 60, 90, 120, 240, 480, 720, 1440],
      label: formatDuration,
      unit: 'minute',
      desc: 'asmr_sleep_timer_desc',
      hint: 'settings_asmr_timer_hint',
      inputLabel: 'custom_sleep_minutes',
      rangeText: 'custom_sleep_minutes_range',
      requires: () => [needsOn(Settings.enableAsmrSleepMode, 'asmr_sleep_mode')],
      keywords: ['睡眠', '定时', 'sleep', '助眠'],
      when: _android,
    )
    ..group = 'settings_group_mini_window'
    ..toggle(
      'float_play',
      'settings_leave_room_mini',
      Settings.floatPlay,
      AppIcons.settingsLeaveRoomMini,
      desc: 'settings_leave_room_mini_desc',
      keywords: ['画中画', '小窗', 'PiP', '悬浮窗'],
    )
    // A07.22 (V01.5): how big the in-app floating window is.
    ..add(
      'float_window_size',
      'mini_window_size',
      (context, entry) => MiniWindowSizeTile(entry: entry),
      desc: 'mini_window_size_desc',
      settings: [Settings.floatWindowSize, Settings.floatWindowLandscapeScale, Settings.floatWindowPortraitScale],
      keywords: ['小窗', '大小', '尺寸', '悬浮窗', '画中画'],
    )
    ..toggle(
      'auto_pip',
      'auto_pip_on_leave',
      Settings.autoPipOnLeave,
      AppIcons.settingsAutoPip,
      desc: 'auto_pip_on_leave_desc',
      keywords: ['画中画', '小窗', 'PiP'],
      when: _mobile,
    )
    ..add(
      'pip_on_top',
      'settings_pip_on_top',
      (context, entry) => PipOnTopTile(entry: entry),
      desc: 'windows_pip_always_on_top_subtitle',
      settings: [Settings.windowsPipAlwaysOnTop],
      keywords: ['画中画', '小窗', 'PiP', '置顶'],
      when: _desktop,
    )
    ..toggle(
      'pip_remember_position',
      'windows_pip_remember_position',
      Settings.rememberPipPosition,
      AppIcons.settingsPipRemember,
      desc: 'windows_pip_remember_position_subtitle',
      keywords: ['画中画', '小窗', 'PiP'],
      when: _desktop,
    )
    ..add(
      'pip_reset_position',
      'windows_pip_reset_position',
      (context, entry) => PipPositionResetTile(entry: entry),
      desc: 'windows_pip_reset_position_subtitle',
      settings: [
        Settings.windowsPipDisplayId,
        Settings.windowsPipWidth,
        Settings.windowsPipHeight,
        Settings.windowsPipX,
        Settings.windowsPipY,
      ],
      keywords: ['画中画', '小窗', 'PiP'],
      when: _desktop,
    )
    ..group = 'danmaku_settings'
    ..toggle(
      'video_danmaku_show',
      'show_danmaku',
      Settings.enableDanmakuDisplay,
      AppIcons.settingsShowDanmaku,
      desc: 'show_danmaku_subtitle',
      keywords: ['弹幕', 'danmaku'],
    )
    ..link(
      'danmaku_style',
      'settings_danmaku_style',
      AppIcons.settingsDanmakuStyle,
      page: (_) => const DanmakuStylePage(),
      desc: 'settings_danmaku_style_desc',
      keywords: ['弹幕', '字号', '速度', '透明度', 'danmaku'],
    )
    ..add(
      'video_danmaku_font',
      'change_danmaku_font_family',
      // The app font's icon (A01.4 c4: a font, whichever text it sets).
      (context, entry) =>
          FontFamilyTile(entry: entry, setting: Settings.danmakuFontFamilyName, icon: AppIcons.settingsDanmakuFont),
      settings: [Settings.danmakuFontFamilyName, Settings.danmakuFontFamilyFileName],
      keywords: ['字体', 'font', '弹幕'],
      opens: true,
    )
    ..link(
      'video_block_list',
      'settings_danmaku_block',
      AppIcons.settingsDanmakuBlock,
      route: RoutePath.kSettingsDanmuShield,
      // The block page also holds the platform's and the similarity filter
      // (the danmaku page's rows until F02); the row carries them (J01.2).
      settings: [
        Settings.filterDouyuSuspectedAutomatedMessages,
        Settings.enableDanmakuSimilarityFilter,
        Settings.danmakuSimilarityThreshold,
        Settings.danmakuSimilarityCacheDuration,
        Settings.danmakuSimilarityMaxCacheSize,
      ],
      keywords: ['屏蔽', '关键词', '过滤', 'block', '相似', '刷屏', '斗鱼', '机器人'],
    )
    // ---- portrait streams (U.6c, a page of the video page) ----
    ..subpage = SettingsSubpage.portrait
    ..group = 'portrait_detection_group'
    ..toggle(
      'portrait_detect',
      'portrait_smart_detection',
      Settings.enablePortraitStreamAdaptation,
      AppIcons.portraitDetect,
      desc: 'portrait_smart_detection_desc',
      keywords: ['竖屏', 'portrait'],
    )
    ..toggle(
      'portrait_height',
      'portrait_adaptive_height',
      Settings.portraitAdaptiveHeight,
      AppIcons.portraitHeight,
      desc: 'portrait_adaptive_height_desc',
      requires: () => [needsOn(Settings.enablePortraitStreamAdaptation, 'portrait_smart_detection')],
      keywords: ['竖屏', 'portrait'],
    )
    ..choice<String>(
      'portrait_layout',
      'portrait_layout_mode',
      Settings.portraitLayoutMode,
      AppIcons.portraitLayout,
      () => _keyed({
        'balanced': 'portrait_layout_balanced',
        'immersive': 'portrait_layout_immersive',
        'compatibility': 'portrait_layout_compatibility',
      }),
      desc: 'portrait_layout_mode_desc',
      hint: 'portrait_layout_mode_desc',
      valueBelow: true,
      requires: () => [needsOn(Settings.enablePortraitStreamAdaptation, 'portrait_smart_detection')],
      keywords: ['竖屏', 'portrait'],
    )
    ..group = 'portrait_presentation_group'
    ..choice<String>(
      'portrait_fullscreen',
      'portrait_fullscreen_policy',
      Settings.portraitFullscreenPolicy,
      AppIcons.portraitFullscreen,
      () => _keyed({
        'followSource': 'portrait_fullscreen_follow_source',
        'followSystem': 'portrait_fullscreen_follow_system',
        'landscape': 'portrait_fullscreen_landscape',
      }),
      desc: 'portrait_fullscreen_policy_desc',
      hint: 'portrait_fullscreen_policy_desc',
      valueBelow: true,
      keywords: ['竖屏', 'portrait', '全屏'],
    )
    ..choice<String>(
      'portrait_display',
      'portrait_fullscreen_display_mode',
      Settings.portraitFullscreenDisplayMode,
      AppIcons.portraitDisplay,
      () => _keyed({
        'complete': 'portrait_fullscreen_display_complete',
        'ambient': 'portrait_fullscreen_display_ambient',
        'balanced': 'portrait_fullscreen_display_balanced',
        'cover': 'portrait_fullscreen_display_cover',
      }),
      desc: 'portrait_fullscreen_display_mode_desc',
      hint: 'portrait_fullscreen_display_mode_desc',
      valueBelow: true,
      keywords: ['竖屏', 'portrait', '全屏'],
    )
    // U.2b2 (U.2b c14, X1 A): new, off by default; phones only.
    ..toggle(
      'portrait_swipe',
      'portrait_fullscreen_swipe_switch',
      Settings.portraitFullscreenSwipeSwitch,
      AppIcons.switchRoom,
      desc: 'portrait_fullscreen_swipe_switch_desc',
      keywords: ['竖屏', 'portrait', '全屏', '换台', '上下滑', 'swipe'],
      when: _mobile,
    )
    ..toggle(
      'portrait_pip',
      'portrait_pip_follow_source',
      Settings.portraitPipFollowSource,
      AppIcons.portraitPip,
      desc: 'portrait_pip_follow_source_desc',
      keywords: ['竖屏', 'portrait', '小窗'],
      when: _android,
    )
    ..choice<String>(
      'portrait_danmaku',
      'portrait_danmaku_mode',
      Settings.portraitDanmakuMode,
      AppIcons.portraitDanmaku,
      () => _keyed({
        'followGlobal': 'portrait_danmaku_follow_global',
        'upperQuarter': 'portrait_danmaku_upper_quarter',
        'reduced': 'portrait_danmaku_reduced',
        'hidden': 'portrait_danmaku_hidden',
      }),
      desc: 'portrait_danmaku_mode_desc',
      hint: 'portrait_danmaku_mode_desc',
      valueBelow: true,
      keywords: ['竖屏', 'portrait', '弹幕'],
    )
    ..toggle(
      'portrait_remember',
      'portrait_remember_room_override',
      Settings.rememberPortraitRoomOverride,
      AppIcons.portraitRemember,
      desc: 'portrait_remember_room_override_desc',
      keywords: ['竖屏', 'portrait'],
    )
    ..group = 'portrait_diagnostics_group'
    ..toggle(
      'portrait_diagnostics',
      'portrait_show_diagnostics',
      Settings.showPortraitDiagnostics,
      AppIcons.portraitDiagnostics,
      desc: 'portrait_show_diagnostics_desc',
      keywords: ['竖屏', 'portrait'],
    )
    ..add(
      'portrait_reset',
      'portrait_reset_settings',
      (context, entry) => RestoreDefaultsTile(
        entry: entry,
        settings: portraitSettings,
        confirmTitle: 'portrait_reset_settings',
        confirmMessage: 'settings_portrait_reset_confirm',
      ),
      desc: 'portrait_reset_settings_desc',
      settings: portraitSettings,
      keywords: ['竖屏', 'portrait', '默认', 'reset'],
    )
    // ---- audience counts (U.6c c15, a page of the video page) ----
    ..subpage = SettingsSubpage.audience
    ..group = 'audience_display_mode'
    ..add(
      'audience_heat',
      'audience_mode_heat',
      (context, entry) => AudienceModeTile(entry: entry, online: false),
      desc: 'audience_mode_heat_desc',
      settings: [Settings.preferRealOnlineCounts],
      keywords: ['人数', '热度', 'viewers'],
    )
    ..add(
      'audience_online',
      'audience_mode_online',
      (context, entry) => AudienceModeTile(entry: entry, online: true),
      desc: 'audience_mode_online_desc',
      settings: [Settings.preferRealOnlineCounts],
      keywords: ['人数', '在线', 'viewers'],
    )
    ..group = 'audience_online_platforms'
    ..add(
      'audience_platforms',
      'audience_online_platforms',
      (context, entry) => AudiencePlatformsTile(entry: entry),
      settings: [Settings.realOnlinePlatforms],
      keywords: ['人数', '在线', 'viewers', '平台'],
    )
    ..group = 'settings_group_audience_heat_only'
    ..add(
      'audience_heat_only',
      'settings_group_audience_heat_only',
      (context, entry) => AudienceHeatOnlyTile(entry: entry),
      keywords: ['人数', '热度', '累计'],
    )
    ..link(
      'audience_info',
      'settings_audience_info',
      null,
      page: (_) => const AudienceInfoPage(),
      desc: 'settings_audience_info_desc',
      keywords: ['人数', '口径', '来源'],
    )
    ..subpage = null
    // ---- floating-window danmaku (U.6c c14; the page has a preview) ----
    ..section = SettingsSection.pipDanmaku
    ..group = '_pip_switch'
    ..toggle('pip_danmaku', 'pip_danmaku_enable', Settings.enablePipDanmaku, null, keywords: ['画中画', '小窗', 'PiP', '弹幕'])
    ..group = 'settings_group_style'
    ..slider(
      'pip_opacity',
      'opacity',
      Settings.pipDanmakuOpacity,
      null,
      min: 0.1,
      max: 1,
      step: 0.05,
      format: _percent,
      requires: _pipOn,
      keywords: ['小窗', '透明', 'opacity'],
    )
    ..slider(
      'pip_speed',
      'speed',
      Settings.pipDanmakuSpeed,
      null,
      min: 20,
      max: 400,
      step: 1,
      format: (value) => '${value.round()} px/s',
      requires: _pipOn,
      keywords: ['小窗', '速度', 'speed'],
    )
    ..slider(
      'pip_size',
      'font_size',
      Settings.pipDanmakuFontSize,
      null,
      min: 8,
      max: 24,
      step: 0.5,
      format: (value) => '${value.toStringAsFixed(1)} px',
      requires: _pipOn,
      keywords: ['小窗', '字号', 'size'],
    )
    ..slider(
      'pip_weight',
      'font_weight',
      Settings.pipDanmakuFontWeight,
      null,
      min: 100,
      max: 900,
      step: 100,
      format: (value) => i18n(danmakuFontWeightNames[value.round()] ?? 'font_weight_normal'),
      requires: _pipOn,
      keywords: ['小窗', '粗细', 'weight'],
    )
    ..toggle(
      'pip_auto_scale',
      'pip_danmaku_auto_scale',
      Settings.pipDanmakuAutoScale,
      null,
      desc: 'settings_pip_auto_scale_desc',
      requires: _pipOn,
      keywords: ['小窗', '缩放'],
    )
    ..toggle(
      'pip_no_emoji',
      'danmaku_no_emoji',
      Settings.pipDanmakuNoEmojiMode,
      null,
      requires: _pipOn,
      keywords: ['小窗', '表情', 'emoji'],
    )
    ..toggle(
      'pip_original_color',
      'pip_danmaku_original_color',
      Settings.pipDanmakuUseOriginalColor,
      null,
      requires: _pipOn,
      keywords: ['小窗', '颜色', 'color'],
    )
    ..add(
      'pip_color',
      'pip_danmaku_color',
      (context, entry) => PipColorTile(entry: entry),
      settings: [Settings.pipDanmakuColor],
      keywords: ['小窗', '颜色', 'color'],
    )
    ..group = 'settings_group_display_range'
    ..slider(
      'pip_area',
      'danmaku_area',
      Settings.pipDanmakuArea,
      null,
      min: 0.1,
      max: 1,
      step: 0.05,
      format: _percent,
      requires: _pipOn,
      keywords: ['小窗', '区域', 'area'],
    )
    ..add(
      'pip_max_visible',
      'pip_danmaku_max_visible',
      (context, entry) => SettingCounterTile(
        entry: entry,
        setting: Settings.pipDanmakuMaxVisibleCount,
        min: 1,
        max: 20,
        requires: _pipOn(),
      ),
      settings: [Settings.pipDanmakuMaxVisibleCount],
      keywords: ['小窗', '数量'],
    )
    ..slider(
      'pip_interval',
      'pip_danmaku_interval',
      Settings.pipDanmakuEmitInterval,
      null,
      min: 0.05,
      max: 2,
      step: 0.05,
      format: (value) => i18n('pip_danmaku_interval_seconds', args: {'seconds': value.toStringAsFixed(2)}),
      requires: _pipOn,
      keywords: ['小窗', '间隔'],
    )
    ..group = 'settings_group_smoothness'
    ..toggle(
      'pip_auto_fps',
      'settings_pip_fps_follow',
      Settings.pipDanmakuAutoFps,
      null,
      desc: 'pip_danmaku_fps_policy_desc',
      requires: _pipOn,
      keywords: ['小窗', '帧率', 'fps'],
    )
    ..add(
      'pip_fps',
      'danmaku_fps',
      (context, entry) => PipFpsTile(entry: entry),
      settings: [Settings.pipDanmakuFps],
      keywords: ['小窗', '帧率', 'fps'],
    )
    ..group = '_pip_reset'
    ..add(
      'pip_reset',
      'pip_danmaku_reset',
      (context, entry) => RestoreDefaultsTile(
        entry: entry,
        settings: pipDanmakuSettings,
        confirmTitle: 'pip_danmaku_reset',
        confirmMessage: 'pip_danmaku_reset_confirm',
      ),
      settings: pipDanmakuSettings,
      keywords: ['小窗', '默认', 'reset'],
    )
    // ---- player (U.6c c9–c11) ----
    ..section = SettingsSection.playerKernel
    ..group = 'settings_group_kernel'
    ..add(
      'kernel',
      'kernel_switch',
      (context, entry) => KernelTile(entry: entry),
      desc: 'kernel_switch_subtitle',
      keywords: ['mpv', '播放器', '内核'],
    )
    ..toggle(
      'hard_stop',
      'force_destroy_player',
      Settings.useHardStopOnExit,
      AppIcons.settingsHardStop,
      desc: 'force_destroy_player_subtitle',
    )
    ..group = 'settings_group_decode'
    ..toggle(
      'hardware_decoding',
      'enable_codec',
      Settings.enableCodec,
      AppIcons.settingsHardwareDecoding,
      desc: 'gpu_decode',
      requires: _hardwareDecodingFree,
      keywords: ['硬解', 'decode', 'GPU'],
    )
    ..toggle(
      'compat_mode',
      'compat_mode',
      Settings.playerCompatMode,
      AppIcons.settingsCompatMode,
      desc: 'settings_compat_mode_takeover',
      keywords: ['黑屏', 'MediaCodec', '卡顿'],
      when: _android,
    )
    ..toggle(
      'rtx_vsr',
      'enable_rtx_vsr',
      Settings.enableRtxVsr,
      AppIcons.settingsRtxVsr,
      desc: 'enable_rtx_vsr_subtitle',
      keywords: ['NVIDIA', 'RTX', '超分'],
      when: _windows,
    )
    ..group = 'settings_group_network'
    ..add(
      'player_proxy_link',
      'network_proxy',
      (context, entry) => PlayerProxyLinkTile(entry: entry),
      desc: 'settings_player_proxy_link_desc',
      settings: [Settings.enableProxy],
      keywords: ['代理', 'proxy'],
      opens: true,
    )
    ..group = 'mpv_advanced_settings'
    ..toggle(
      'custom_output',
      'custom_output_hwdec',
      Settings.customPlayerOutput,
      AppIcons.settingsCustomOutput,
      desc: 'settings_custom_output_takeover',
      requires: _customOutputFree,
      keywords: ['mpv', 'vo', 'ao', 'hwdec'],
    )
    ..add(
      'video_output',
      'video_output_driver',
      (context, entry) => MpvOptionTile(entry: entry, kind: MpvOptionKind.video),
      settings: [Settings.videoOutputDriver],
      keywords: ['mpv', 'vo'],
      opens: true,
    )
    ..add(
      'audio_output',
      'audio_output_driver',
      (context, entry) => MpvOptionTile(entry: entry, kind: MpvOptionKind.audio),
      settings: [Settings.audioOutputDriver],
      keywords: ['mpv', 'ao'],
      opens: true,
    )
    ..add(
      'hardware_decoder',
      'hardware_decoder',
      (context, entry) => MpvOptionTile(entry: entry, kind: MpvOptionKind.decoder),
      settings: [Settings.videoHardwareDecoder],
      keywords: ['mpv', 'hwdec'],
      opens: true,
    )
    ..group = '_kernel_reset'
    ..add(
      'kernel_reset',
      'settings_restore_defaults',
      (context, entry) => RestoreDefaultsTile(
        entry: entry,
        settings: kernelSettings,
        confirmTitle: 'settings_kernel_reset_title',
        confirmMessage: 'settings_kernel_reset_confirm',
      ),
      desc: 'settings_kernel_reset_desc',
      settings: kernelSettings,
      keywords: ['默认', 'reset', 'mpv'],
    )
    // ---- general (U.6d d2–d7) ----
    ..section = SettingsSection.general
    ..group = 'settings_group_display'
    ..add(
      'refresh_rate',
      'refresh_rate_mode',
      (context, entry) => RefreshRateTile(entry: entry),
      settings: [Settings.refreshRateMode],
      keywords: ['Hz', '高刷', 'refresh rate', '刷新率', '显示器'],
      when: _refreshRate,
    )
    // U.2i c2, c6: under the refresh rate; greyed out on a display with one rate.
    ..add(
      'match_video_frame_rate',
      'match_video_frame_rate',
      (context, entry) => ValueListenableBuilder(
        valueListenable: DisplayMode.info,
        builder: (context, info, _) => switch (info?.supportedRefreshRates) {
          [final only] => SettingsSwitchRow(
            key: entry.rowKey,
            title: entry.titleText,
            subtitle: entry.descriptionText,
            icon: AppIcons.matchFrameRate,
            value: false,
            enabled: false,
            disabledReason: i18n('match_video_frame_rate_single', args: {'rate': '${only.round()}'}),
            onChanged: null,
          ),
          _ => SettingToggleTile(entry: entry, setting: Settings.matchVideoFrameRate, icon: AppIcons.matchFrameRate),
        },
      ),
      desc: 'match_video_frame_rate_desc',
      settings: [Settings.matchVideoFrameRate],
      keywords: ['Hz', '帧率', 'frame rate'],
      when: _android,
    )
    ..group = 'settings_group_launch'
    ..add(
      'startup',
      'startup',
      (context, entry) => StartupTile(entry: entry),
      desc: 'settings_startup_desc',
      settings: [Settings.enableStartUp],
      keywords: ['开机', 'startup'],
      when: _windows,
    )
    ..add(
      'window_size',
      'window_size',
      (context, entry) => WindowSizeTile(entry: entry),
      settings: [Settings.windowWidth, Settings.windowHeight],
      keywords: ['窗口', 'window'],
      when: _windows,
    )
    ..toggle(
      'splash',
      'splash_animation',
      Settings.showSplashPage,
      AppIcons.settingsSplash,
      desc: 'splash_animation_subtitle',
    )
    ..group = 'settings_group_updates'
    ..toggle(
      'auto_update',
      'enable_auto_check_update',
      Settings.enableAutoCheckUpdate,
      AppIcons.settingsAutoUpdate,
      keywords: ['更新', 'update'],
    )
    ..toggle(
      'github_updates',
      'use_github_origin_for_updates',
      Settings.useGitHubOriginForUpdates,
      AppIcons.settingsGitHub,
      desc: 'use_github_origin_for_updates_desc',
      keywords: ['更新', 'update', 'GitHub'],
    )
    ..group = 'settings_group_window'
    ..add(
      'close_window',
      'settings_close_window',
      (context, entry) => CloseWindowTile(entry: entry),
      desc: 'settings_close_window_desc',
      settings: [Settings.dontAskExit, Settings.exitChoose],
      keywords: ['托盘', '关闭', 'close', '退出', '不再询问'],
      when: _windows,
    )
    ..toggle(
      'new_window',
      'open_new_window',
      Settings.enableNewWindowPlay,
      AppIcons.newPlayerWindow,
      desc: 'settings_new_window_desc',
      keywords: ['窗口', 'window'],
      when: _windows,
    )
    ..group = 'settings_group_exit_timer'
    ..add(
      'auto_exit',
      'enable_countdown_close',
      (context, entry) => AutoExitTile(entry: entry),
      desc: 'enable_countdown_close_subtitle',
      settings: [Settings.enableAutoShutDownTime],
      keywords: ['定时', '关闭', 'timer'],
    )
    ..add(
      'auto_exit_minutes',
      'countdown_duration',
      (context, entry) => AutoExitMinutesTile(entry: entry),
      settings: [Settings.autoShutDownTime],
      keywords: ['定时', '关闭', 'timer'],
    )
    // F.0a: the clipboard's share codes (3.x always looked).
    ..group = 'settings_group_share'
    ..toggle(
      'clipboard_rooms',
      'settings_clipboard_rooms',
      Settings.detectClipboardRooms,
      AppIcons.settingsClipboardRooms,
      desc: 'settings_clipboard_rooms_desc',
      keywords: ['剪贴板', '口令', '分享', 'clipboard', 'share'],
    )
    // ---- network (U.6d d13, d14) ----
    ..section = SettingsSection.network
    ..group = 'app_proxy_group_title'
    ..add(
      'app_proxy',
      'enable_app_proxy',
      (context, entry) => ProxyEditorTile(entry: entry, proxy: ProxySettings.app),
      desc: 'enable_app_proxy_desc',
      settings: [Settings.enableAppProxy, Settings.appProxyHost, Settings.appProxyPort],
      keywords: ['代理', 'proxy', 'HTTP'],
    )
    ..group = 'player_proxy_group_title'
    ..add(
      'player_proxy',
      'enable_player_proxy',
      (context, entry) => ProxyEditorTile(entry: entry, proxy: ProxySettings.player),
      desc: 'enable_player_proxy_desc',
      settings: [Settings.enableProxy, Settings.proxyHost, Settings.proxyPort],
      keywords: ['代理', 'proxy', 'HTTP'],
    )
    // ---- cache and data (U.6e e2–e7) ----
    ..section = SettingsSection.cache
    ..group = 'settings_group_cache'
    ..add(
      'cache_size',
      'current_cache_size',
      (context, entry) => CacheSizeTile(entry: entry),
      desc: 'settings_cache_size_desc',
      keywords: ['缓存', 'cache'],
    )
    ..add(
      'refresh_covers_now',
      'refresh_thumbnails',
      (context, entry) => RefreshCoversTile(entry: entry),
      desc: 'refresh_thumbnails_desc',
      keywords: ['封面', '缩略图', 'cover', 'thumbnail'],
    )
    ..add(
      'clear_cache',
      'clear_local_cache',
      (context, entry) => ClearCacheTile(entry: entry),
      desc: 'clear_local_cache_desc',
      keywords: ['缓存', 'cache', '清理', '清除'],
    )
    ..group = 'settings_group_download'
    ..add(
      'download_directory',
      'download_directory',
      (context, entry) => DownloadDirectoryTile(entry: entry),
      settings: [Settings.downloadDirectoryPath],
      keywords: ['下载', '更新', 'download', '目录'],
    )
    ..add(
      'download_reset',
      'settings_download_reset',
      (context, entry) => DownloadResetTile(entry: entry),
      settings: [Settings.downloadDirectoryPath],
      keywords: ['下载', 'download', '默认'],
    )
    // ---- danmaku (F02 c1) ----
    // The page is the live room's danmaku settings (DanmakuSettingsPage);
    // these rows only let search find its settings, in its groups and with
    // its ranges. Its templates are not settings of their own; the font and
    // the block list are found on the video page.
    ..section = SettingsSection.danmaku
    ..group = 'danmaku_group_range'
    ..slider(
      'danmaku_area',
      'danmaku_area',
      Settings.danmakuArea,
      null,
      min: 0,
      max: 1,
      step: 0.01,
      format: _percent,
      desc: 'settings_danmaku_area_desc',
      keywords: ['范围', '弹幕'],
    )
    ..slider(
      'danmaku_top',
      'margin_top',
      Settings.danmakuTopArea,
      null,
      min: 0,
      max: 300,
      step: 1,
      format: _whole,
      desc: 'settings_danmaku_top_margin_desc',
      keywords: ['边距', '弹幕'],
    )
    ..slider(
      'danmaku_bottom',
      'margin_bottom',
      Settings.danmakuBottomArea,
      null,
      min: 0,
      max: 300,
      step: 1,
      format: _whole,
      desc: 'settings_danmaku_bottom_margin_desc',
      keywords: ['边距', '弹幕'],
    )
    ..choice(
      'danmaku_paused',
      'danmaku_paused_behavior',
      Settings.danmakuPausedBehavior,
      null,
      () => _keyed({
        DanmakuPausedBehavior.pause: 'danmaku_paused_pause',
        DanmakuPausedBehavior.fly: 'danmaku_paused_fly',
      }),
      desc: 'danmaku_paused_behavior_desc',
      keywords: ['暂停', '弹幕'],
    )
    ..group = 'style'
    ..slider(
      'danmaku_opacity',
      'opacity',
      Settings.danmakuOpacity,
      null,
      min: 0,
      max: 1,
      step: 0.01,
      format: _percent,
      keywords: ['透明', 'opacity', '弹幕'],
    )
    ..slider(
      'danmaku_speed',
      'speed',
      Settings.danmakuSpeed,
      null,
      min: 20,
      max: 400,
      step: 1,
      format: (value) => '${value.round()} px/s',
      desc: 'settings_danmaku_speed_desc',
      keywords: ['速度', 'speed', '弹幕'],
    )
    ..slider(
      'danmaku_font_size',
      'font_size',
      Settings.danmakuFontSize,
      null,
      min: 10,
      max: 30,
      step: 0.5,
      format: (value) => '${value.toStringAsFixed(1)} px',
      keywords: ['字号', 'size', '弹幕'],
    )
    ..slider(
      'danmaku_font_weight',
      'font_weight',
      Settings.danmakuFontWeight,
      null,
      min: 100,
      max: 900,
      step: 100,
      format: (value) => i18n(danmakuFontWeightNames[value.round()] ?? 'font_weight_medium'),
      keywords: ['粗细', 'weight', '弹幕'],
    )
    ..toggle(
      'danmaku_stroke',
      'danmaku_stroke',
      Settings.enableDanmakuStroke,
      null,
      desc: 'settings_danmaku_stroke_desc',
      keywords: ['描边', '弹幕'],
    )
    ..slider(
      'danmaku_stroke_width',
      'stroke',
      Settings.danmakuFontBorder,
      null,
      min: 0,
      max: 4,
      step: 0.1,
      format: (value) => '${value.toStringAsFixed(1)} px',
      requires: () => [needsOn(Settings.enableDanmakuStroke, 'danmaku_stroke')],
      keywords: ['描边', 'stroke', '弹幕'],
    )
    ..toggle(
      'danmaku_no_emoji',
      'danmaku_no_emoji',
      Settings.noEmojiMode,
      null,
      desc: 'settings_danmaku_no_emoji_desc',
      keywords: ['表情', 'emoji', '弹幕'],
    )
    ..group = 'danmaku_group_repeat'
    ..toggle(
      'collapse_repeated',
      'collapse_repeated_danmaku',
      Settings.collapseRepeatedDanmaku,
      null,
      desc: 'collapse_repeated_danmaku_desc',
      keywords: ['重复', '刷屏'],
    )
    ..slider(
      'repeat_window',
      'repeated_danmaku_window',
      Settings.repeatedDanmakuWindowSeconds,
      null,
      min: 1,
      max: 30,
      step: 1,
      format: _whole,
      requires: () => [needsOn(Settings.collapseRepeatedDanmaku, 'collapse_repeated_danmaku')],
      desc: 'settings_repeat_window_desc',
      keywords: ['重复', '刷屏'],
    )
    ..group = 'danmaku_group_interaction'
    ..toggle(
      'danmaku_tap',
      'danmaku_tap_action',
      Settings.enableDanmakuTapInteraction,
      null,
      desc: 'settings_danmaku_tap_desc',
      keywords: ['点击', '弹幕'],
    )
    ..toggle(
      'danmaku_long_press',
      'danmaku_long_press_action',
      Settings.enableDanmakuLongPressInteraction,
      null,
      desc: 'settings_danmaku_long_press_desc',
      keywords: ['长按', '弹幕'],
    )
    ..toggle(
      'danmaku_hold_on_press',
      'danmaku_hold_on_press',
      Settings.holdDanmakuOnPress,
      null,
      desc: 'danmaku_hold_on_press_desc',
      keywords: ['按住', '停住', '定住', '弹幕'],
    )
    ..group = 'danmaku_group_smoothness'
    ..toggle(
      'danmaku_auto_fps',
      'settings_danmaku_auto_fps',
      Settings.danmakuAutoFps,
      null,
      desc: 'danmaku_auto_fps_desc',
      keywords: ['帧率', 'fps', '弹幕'],
    )
    ..slider(
      'danmaku_fps',
      'danmaku_fps',
      Settings.danmakuFps,
      null,
      min: 30,
      max: 240,
      step: 1,
      format: (value) => '${value.round()} FPS',
      requires: () => [needsOff(Settings.danmakuAutoFps, 'settings_danmaku_auto_fps')],
      keywords: ['帧率', 'fps', '弹幕'],
    )
    ..slider(
      'danmaku_max_visible',
      'danmaku_max_visible',
      Settings.danmakuMaxVisibleCount,
      null,
      min: 10,
      max: 120,
      step: 2,
      format: (value) => i18n('danmaku_max_visible_value', args: {'count': '${value.round()}'}),
      desc: 'danmaku_max_visible_desc',
      keywords: ['同屏', '条数', '数量', '密度', '弹幕'],
    )
    // A08.6 c2: the room's chat list group, on the page before "更多".
    ..group = 'danmaku_list'
    ..choice(
      'danmaku_list_style',
      'danmaku_list_style',
      Settings.danmakuListStyle,
      null,
      () => _keyed({
        ChatListStyle.compact.name: 'danmaku_list_style_compact',
        ChatListStyle.card.name: 'danmaku_list_style_card',
      }),
      desc: 'danmaku_list_style_desc',
      keywords: ['聊天', '列表', '卡片', '紧凑'],
    )
    ..toggle(
      'danmaku_show_names',
      'danmaku_list_show_names',
      Settings.showChatNames,
      null,
      desc: 'danmaku_list_show_names_desc',
      keywords: ['用户名', '昵称', '名字', '聊天', '列表'],
    )
    ..toggle(
      'danmaku_show_gifts',
      'live_play_show_gifts',
      Settings.showChatGifts,
      null,
      desc: 'live_play_show_gifts_desc',
      keywords: ['礼物', '聊天', 'gift'],
    )
    ..group = 'more'
    ..toggle(
      'danmaku_show',
      'show_danmaku',
      Settings.enableDanmakuDisplay,
      null,
      desc: 'settings_danmaku_show_desc',
      keywords: ['弹幕'],
    )
    ..toggle(
      'danmaku_on_video',
      'live_play_danmaku_on_video',
      Settings.hideDanmaku,
      null,
      inverted: true,
      desc: 'settings_danmaku_on_video_desc',
      keywords: ['弹幕'],
    )
    ..toggle(
      'youtube_all_chat',
      'settings_youtube_all_chat',
      Settings.youtubeShowAllChat,
      null,
      desc: 'settings_youtube_all_chat_desc',
      keywords: ['YouTube', '聊天', '弹幕'],
    );
  return List.unmodifiable(c.entries);
}

/// Settings of the floating-window danmaku page, its switch included (its
/// restore, 3.x `pip_danmaku_reset_confirm`).
const List<Setting<Object>> pipDanmakuSettings = [
  Settings.enablePipDanmaku,
  Settings.pipDanmakuAutoScale,
  Settings.pipDanmakuNoEmojiMode,
  Settings.pipDanmakuUseOriginalColor,
  Settings.pipDanmakuColor,
  Settings.pipDanmakuFontSize,
  Settings.pipDanmakuFontWeight,
  Settings.pipDanmakuSpeed,
  Settings.pipDanmakuOpacity,
  Settings.pipDanmakuArea,
  Settings.pipDanmakuMaxVisibleCount,
  Settings.pipDanmakuEmitInterval,
  Settings.pipDanmakuFps,
  Settings.pipDanmakuAutoFps,
];

/// Settings of the portrait page; the restore also forgets the rooms'
/// remembered orientations (3.x `portrait_reset_settings_desc`).
const List<Setting<Object>> portraitSettings = [
  Settings.enablePortraitStreamAdaptation,
  Settings.portraitAdaptiveHeight,
  Settings.portraitLayoutMode,
  Settings.portraitFullscreenPolicy,
  Settings.portraitFullscreenDisplayMode,
  Settings.portraitPipFollowSource,
  Settings.portraitDanmakuMode,
  Settings.rememberPortraitRoomOverride,
  Settings.portraitFullscreenSwipeSwitch,
  Settings.showPortraitDiagnostics,
  Settings.portraitRoomOverrides,
];

/// Settings of the player page's restore: only that page (3.x also reset
/// the preferred qualities, U.6c P9).
const List<Setting<Object>> kernelSettings = [
  Settings.enableCodec,
  Settings.playerCompatMode,
  Settings.useHardStopOnExit,
  Settings.customPlayerOutput,
  Settings.videoOutputDriver,
  Settings.audioOutputDriver,
  Settings.videoHardwareDecoder,
  Settings.enableRtxVsr,
];
