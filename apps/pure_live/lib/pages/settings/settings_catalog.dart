import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/settings/appearance_pages.dart';
import 'package:pure_live/pages/settings/data_tools.dart';
import 'package:pure_live/pages/settings/log_page.dart';
import 'package:pure_live/pages/settings/settings_dialogs.dart';
import 'package:pure_live/pages/settings/settings_editors.dart';
import 'package:pure_live/pages/settings/settings_model.dart';
import 'package:pure_live/pages/settings/settings_tiles.dart';
import 'package:pure_live/routes/route_path.dart';

/// "30 分钟", "1.5 小时", "2 小时" (3.x's refresh interval labels).
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes ${i18n('minute')}';
  if (minutes % 60 == 0) return '${minutes ~/ 60} ${i18n('hour')}';
  if (minutes % 30 == 0) return '${minutes / 60} ${i18n('hour')}';
  return '$minutes ${i18n('minute')}';
}

String _percent(double value) => '${(value * 100).round()}%';
String _whole(double value) => '${value.round()}';
String _pixels(double value) => '${value.round()} px';

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

List<SettingsChoice<String>> _keyed(Map<String, String> labels, [Map<String, String> descriptions = const {}]) => [
  for (final MapEntry(:key, :value) in labels.entries)
    (value: key, label: i18n(value), description: descriptions[key] == null ? null : i18n(descriptions[key]!)),
];

bool _wide(SettingsEnv env) => env.wide;
bool _android(SettingsEnv env) => env.isAndroid;
bool _windows(SettingsEnv env) => env.isWindows;
bool _mobile(SettingsEnv env) => env.isMobile;
bool _desktop(SettingsEnv env) => !env.isMobile;
bool _refreshRate(SettingsEnv env) => env.hasRefreshRate;

typedef _Build = Widget Function(BuildContext context, SettingsEntry entry);

/// A small builder for the catalogue: one section and group at a time.
final class _Catalog {
  final List<SettingsEntry> entries = [];

  /// The section of the entries added next.
  late SettingsSection section;

  /// The group title of the entries added next.
  late String group;

  void add(
    String id,
    String title,
    _Build build, {
    String? desc,
    List<Setting<Object>> settings = const [],
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
  }) => entries.add(
    SettingsEntry(
      id: id,
      section: section,
      group: group,
      title: title,
      description: desc,
      build: build,
      settings: settings,
      keywords: keywords,
      when: when ?? (_) => true,
    ),
  );

  void toggle(
    String id,
    String title,
    BoolSetting setting,
    IconData icon, {
    String? desc,
    bool inverted = false,
    BoolSetting? enabledBy,
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
  }) => add(
    id,
    title,
    (context, entry) =>
        SettingToggleTile(entry: entry, setting: setting, icon: icon, inverted: inverted, enabledBy: enabledBy),
    desc: desc,
    settings: [setting],
    keywords: keywords,
    when: when,
  );

  void slider(
    String id,
    String title,
    Setting<Object> setting,
    IconData icon, {
    required double min,
    required double max,
    required String Function(double value) format,
    double? step,
    String? desc,
    BoolSetting? enabledBy,
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
    ),
    desc: desc,
    settings: [setting],
    keywords: keywords,
    when: when,
  );

  void choice(
    String id,
    String title,
    StringSetting setting,
    IconData icon,
    List<SettingsChoice<String>> Function() options, {
    String? desc,
    String? hint,
    BoolSetting? enabledBy,
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
  }) => add(
    id,
    title,
    (context, entry) => SettingChoiceTile<String>(
      entry: entry,
      setting: setting,
      icon: icon,
      options: options,
      hint: hint == null ? null : i18n(hint),
      enabledBy: enabledBy,
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
    BoolSetting? enabledBy,
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
      enabledBy: enabledBy,
    ),
    desc: desc,
    settings: [setting],
    keywords: keywords,
    when: when,
  );

  void link(
    String id,
    String title,
    IconData icon, {
    String? route,
    WidgetBuilder? page,
    String? desc,
    List<Setting<Object>> settings = const [],
    List<String> keywords = const [],
    bool Function(SettingsEnv env)? when,
  }) => add(
    id,
    title,
    (context, entry) => SettingLinkTile(entry: entry, icon: icon, route: route, page: page),
    desc: desc,
    settings: settings,
    keywords: keywords,
    when: when,
  );
}

/// Every settings row, in display order (3.x's 20 settings pages, regrouped
/// by what a user looks for; see docs/modules/M13.7-settings.md).
final List<SettingsEntry> settingsCatalog = _build();

List<SettingsEntry> _build() {
  final c = _Catalog()
    // ---- appearance ----
    ..section = SettingsSection.appearance
    ..group = 'settings_group_theme'
    ..add(
      'theme_mode',
      'change_theme_mode',
      (context, entry) => ThemeModeTile(entry: entry),
      desc: 'settings_theme_mode_desc',
      settings: [Settings.themeMode],
      keywords: ['dark', 'light', '深色', '浅色', '夜间'],
    )
    ..add(
      'theme_color',
      'change_theme_color',
      (context, entry) => ThemeColorTile(entry: entry),
      desc: 'settings_theme_color_desc',
      settings: [Settings.themeColorSwitch],
      keywords: ['color', '颜色'],
    )
    ..toggle(
      'dynamic_color',
      'enable_dynamic_color',
      Settings.enableDynamicTheme,
      Remix.magic_line,
      desc: 'settings_dynamic_color_desc',
      keywords: ['Material You', 'monet'],
    )
    ..add(
      'language',
      'change_language',
      (context, entry) => LanguageTile(entry: entry),
      desc: 'settings_language_desc',
      settings: [Settings.language],
      keywords: ['language', '语言', 'English', '中文'],
    )
    ..group = 'settings_group_text'
    ..slider(
      'text_scale',
      'text_size_title',
      Settings.textScaleFactor,
      Remix.text_spacing,
      min: 0.5,
      max: 2,
      step: 0.05,
      format: (value) => '${value.toStringAsFixed(2)}×',
      desc: 'settings_text_scale_desc',
      keywords: ['font', '字号', '缩放'],
    )
    ..link(
      'font_sizes',
      'font_settings_title',
      Remix.font_size,
      page: (_) => const FontSizesPage(),
      desc: 'settings_font_sizes_desc',
      settings: [
        Settings.fontSizeBodySmall,
        Settings.fontSizeBodyMedium,
        Settings.fontSizeBodyLarge,
        Settings.fontSizeTitleMedium,
        Settings.fontSizeTitleLarge,
      ],
      keywords: ['字号', 'font size'],
    )
    ..add(
      'app_font',
      'change_font_family',
      (context, entry) => FontFamilyTile(entry: entry, setting: Settings.fontFamilyName),
      desc: 'settings_app_font_desc',
      settings: [Settings.fontFamilyName, Settings.fontFamilyFileName],
      keywords: ['font', '字体'],
    )
    ..group = 'settings_group_layout'
    ..add(
      'loading_style',
      'change_loading_style',
      (context, entry) => LoadingStyleTile(entry: entry),
      desc: 'settings_loading_style_desc',
      settings: [Settings.loadingStyle, Settings.loadingStyleColorSwitch],
      keywords: ['loading', '加载'],
    )
    ..link(
      'room_card',
      'room_card_settings',
      Remix.layout_grid_line,
      page: (_) => const RoomCardSettingsPage(),
      desc: 'settings_room_card_desc',
      settings: [
        Settings.roomCardMobilePreset,
        Settings.roomCardDesktopPreset,
        Settings.roomCardMobileConfig,
        Settings.roomCardDesktopConfig,
      ],
      keywords: ['card', '卡片', '封面'],
    )
    ..slider(
      'cross_spacing',
      'cross_axis_spacing',
      Settings.crossAxisSpacing,
      Remix.arrow_left_right_line,
      min: 0,
      max: 64,
      format: _pixels,
      desc: 'settings_cross_spacing_desc',
      keywords: ['间距', 'spacing'],
    )
    ..slider(
      'main_spacing',
      'main_axis_spacing',
      Settings.mainAxisSpacing,
      Remix.arrow_up_down_line,
      min: 0,
      max: 64,
      format: _pixels,
      desc: 'settings_main_spacing_desc',
      keywords: ['间距', 'spacing'],
    )
    ..group = 'page_settings'
    ..toggle(
      'page_size_selector',
      'show_page_size_selector',
      Settings.pageShowSizeSelector,
      Remix.list_settings_line,
      desc: 'settings_page_size_selector_desc',
      when: _wide,
    )
    ..toggle(
      'page_goto',
      'show_goto_button',
      Settings.pageShowGotoButton,
      Remix.skip_forward_line,
      desc: 'settings_page_goto_desc',
      when: _wide,
    )
    ..toggle(
      'page_scroll_top',
      'show_scroll_to_top',
      Settings.pageShowScrollTop,
      Remix.arrow_up_circle_line,
      desc: 'settings_page_scroll_top_desc',
      when: _wide,
    )
    ..number(
      'page_default_size',
      'settings_page_default_size',
      Settings.pageDefaultSize,
      Remix.file_list_3_line,
      presets: const [0, 12, 20, 30, 40, 60],
      label: (value) => value == 0 ? i18n('settings_page_size_auto') : '$value',
      desc: 'settings_page_default_size_desc',
      unit: 'items_per_page',
      when: _wide,
    )
    ..add(
      'page_size_options',
      'page_size_options_manage',
      (context, entry) => PageSizeOptionsTile(entry: entry),
      desc: 'settings_page_size_options_desc',
      settings: [Settings.pageSizeOptions],
      when: _wide,
    )
    // ---- playback ----
    ..section = SettingsSection.playback
    ..group = 'video_quality_settings'
    ..choice(
      'prefer_resolution',
      'prefer_resolution',
      Settings.preferResolution,
      Remix.hd_line,
      () => _keyed(resolutionKeys),
      desc: 'settings_prefer_resolution_desc',
      keywords: ['画质', 'quality', 'Wi-Fi'],
    )
    ..choice(
      'prefer_resolution_cellular',
      'mobile_quality',
      Settings.preferResolutionCellular,
      Remix.signal_tower_line,
      () => _keyed(resolutionKeys),
      desc: 'settings_prefer_resolution_cellular_desc',
      keywords: ['画质', 'quality', '流量', '4G', '5G'],
      when: _mobile,
    )
    ..toggle(
      'prefer_h264',
      'settings_prefer_h264',
      Settings.preferH264,
      Remix.film_line,
      desc: 'settings_prefer_h264_desc',
      keywords: ['HEVC', 'H.265', 'H264', '编码'],
    )
    ..add(
      'video_fit',
      'settings_video_fit',
      (context, entry) => SettingChoiceTile<int>(
        entry: entry,
        setting: Settings.videoFitIndex,
        icon: Remix.aspect_ratio_line,
        options: () => [
          for (var i = 0; i < videoFitKeys.length; i++) (value: i, label: i18n(videoFitKeys[i]), description: null),
        ],
      ),
      desc: 'settings_video_fit_desc',
      settings: [Settings.videoFitIndex],
      keywords: ['比例', '裁剪', 'fit', 'crop'],
    )
    ..group = 'audio_settings'
    ..toggle(
      'global_mute',
      'global_mute',
      Settings.globalVolumeMute,
      Remix.volume_mute_line,
      desc: 'settings_global_mute_desc',
      keywords: ['静音', 'mute'],
    )
    ..slider(
      'mobile_volume',
      'mobile_default_volume',
      Settings.defaultMobileVolume,
      Remix.smartphone_line,
      min: 0,
      max: 1,
      step: 0.01,
      format: _percent,
      desc: 'settings_default_volume_desc',
      keywords: ['音量', 'volume'],
      when: _mobile,
    )
    ..slider(
      'desktop_volume',
      'desktop_default_volume',
      Settings.defaultDesktopVolume,
      Remix.computer_line,
      min: 0,
      max: 1,
      step: 0.01,
      format: _percent,
      desc: 'settings_default_volume_desc',
      keywords: ['音量', 'volume'],
      when: _desktop,
    )
    ..group = 'playback_behavior_settings'
    ..toggle(
      'fullscreen_default',
      'enable_fullscreen_default',
      Settings.enableFullScreenDefault,
      Remix.fullscreen_line,
      desc: 'settings_fullscreen_default_desc',
    )
    ..toggle(
      'screen_keep_on',
      'enable_screen_keep_on',
      Settings.enableScreenKeepOn,
      Remix.lightbulb_line,
      desc: 'settings_screen_keep_on_desc',
      when: _android,
    )
    ..toggle(
      'background_play',
      'enable_background_play',
      Settings.enableBackgroundPlay,
      Remix.music_2_line,
      desc: 'settings_background_play_desc',
      keywords: ['后台', 'background'],
      when: _android,
    )
    ..toggle(
      'asmr_sleep',
      'asmr_sleep_mode',
      Settings.enableAsmrSleepMode,
      Remix.moon_clear_line,
      desc: 'settings_asmr_sleep_desc',
      keywords: ['睡眠', '定时', 'sleep'],
      when: _android,
    )
    ..number(
      'asmr_minutes',
      'asmr_sleep_timer',
      Settings.asmrSleepMinutes,
      Remix.timer_2_line,
      presets: const [15, 30, 45, 60, 90, 120, 240, 480, 720, 1440],
      label: formatMinutes,
      unit: 'minute',
      desc: 'settings_asmr_minutes_desc',
      enabledBy: Settings.enableAsmrSleepMode,
      keywords: ['睡眠', '定时', 'sleep'],
      when: _android,
    )
    ..toggle(
      'float_play',
      'exit_float_window',
      Settings.floatPlay,
      Remix.picture_in_picture_2_line,
      desc: 'settings_float_play_desc',
      keywords: ['画中画', '小窗', 'PiP'],
    )
    ..toggle(
      'pip_on_top',
      'windows_pip_always_on_top',
      Settings.windowsPipAlwaysOnTop,
      Remix.pushpin_line,
      desc: 'windows_pip_always_on_top_subtitle',
      keywords: ['画中画', '小窗', 'PiP'],
      when: _windows,
    )
    ..toggle(
      'pip_remember_position',
      'windows_pip_remember_position',
      Settings.rememberPipPosition,
      Remix.drag_move_line,
      desc: 'windows_pip_remember_position_subtitle',
      keywords: ['画中画', '小窗', 'PiP'],
      when: _windows,
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
      when: _windows,
    )
    ..group = 'portrait_live_settings'
    ..toggle(
      'portrait_detect',
      'portrait_smart_detection',
      Settings.enablePortraitStreamAdaptation,
      Remix.smartphone_line,
      desc: 'portrait_smart_detection_desc',
      keywords: ['竖屏', 'portrait'],
    )
    ..toggle(
      'portrait_height',
      'portrait_adaptive_height',
      Settings.portraitAdaptiveHeight,
      Remix.expand_height_line,
      desc: 'portrait_adaptive_height_desc',
      enabledBy: Settings.enablePortraitStreamAdaptation,
      keywords: ['竖屏', 'portrait'],
    )
    ..choice(
      'portrait_layout',
      'portrait_layout_mode',
      Settings.portraitLayoutMode,
      Remix.layout_line,
      () => _keyed({
        'balanced': 'portrait_layout_balanced',
        'immersive': 'portrait_layout_immersive',
        'compatibility': 'portrait_layout_compatibility',
      }),
      desc: 'portrait_layout_mode_desc',
      enabledBy: Settings.enablePortraitStreamAdaptation,
      keywords: ['竖屏', 'portrait'],
    )
    ..choice(
      'portrait_fullscreen',
      'portrait_fullscreen_policy',
      Settings.portraitFullscreenPolicy,
      Remix.fullscreen_line,
      () => _keyed({
        'followSource': 'portrait_fullscreen_follow_source',
        'followSystem': 'portrait_fullscreen_follow_system',
        'landscape': 'portrait_fullscreen_landscape',
      }),
      desc: 'portrait_fullscreen_policy_desc',
      enabledBy: Settings.enablePortraitStreamAdaptation,
      keywords: ['竖屏', 'portrait'],
    )
    ..choice(
      'portrait_display',
      'portrait_fullscreen_display_mode',
      Settings.portraitFullscreenDisplayMode,
      Remix.aspect_ratio_line,
      () => _keyed({
        'complete': 'portrait_fullscreen_display_complete',
        'ambient': 'portrait_fullscreen_display_ambient',
        'balanced': 'portrait_fullscreen_display_balanced',
        'cover': 'portrait_fullscreen_display_cover',
      }),
      desc: 'portrait_fullscreen_display_mode_desc',
      enabledBy: Settings.enablePortraitStreamAdaptation,
      keywords: ['竖屏', 'portrait'],
    )
    ..toggle(
      'portrait_pip',
      'portrait_pip_follow_source',
      Settings.portraitPipFollowSource,
      Remix.picture_in_picture_line,
      desc: 'portrait_pip_follow_source_desc',
      enabledBy: Settings.enablePortraitStreamAdaptation,
      keywords: ['竖屏', 'portrait'],
    )
    ..choice(
      'portrait_danmaku',
      'portrait_danmaku_mode',
      Settings.portraitDanmakuMode,
      Remix.chat_3_line,
      () => _keyed({
        'followGlobal': 'portrait_danmaku_follow_global',
        'upperQuarter': 'portrait_danmaku_upper_quarter',
        'reduced': 'portrait_danmaku_reduced',
        'hidden': 'portrait_danmaku_hidden',
      }),
      desc: 'portrait_danmaku_mode_desc',
      enabledBy: Settings.enablePortraitStreamAdaptation,
      keywords: ['竖屏', 'portrait', '弹幕'],
    )
    ..toggle(
      'portrait_remember',
      'portrait_remember_room_override',
      Settings.rememberPortraitRoomOverride,
      Remix.bookmark_line,
      desc: 'portrait_remember_room_override_desc',
      keywords: ['竖屏', 'portrait'],
    )
    ..toggle(
      'portrait_diagnostics',
      'portrait_show_diagnostics',
      Settings.showPortraitDiagnostics,
      Remix.bug_line,
      desc: 'portrait_show_diagnostics_desc',
      keywords: ['竖屏', 'portrait'],
    )
    ..group = 'settings_group_decoding'
    ..toggle(
      'hardware_decoding',
      'enable_codec',
      Settings.enableCodec,
      Remix.cpu_line,
      desc: 'settings_hardware_decoding_desc',
      keywords: ['硬解', 'decode', 'GPU'],
    )
    ..toggle(
      'compat_mode',
      'compat_mode',
      Settings.playerCompatMode,
      Remix.shield_check_line,
      desc: 'settings_compat_mode_desc',
      keywords: ['黑屏', 'MediaCodec'],
      when: _android,
    )
    ..toggle(
      'rtx_vsr',
      'enable_rtx_vsr',
      Settings.enableRtxVsr,
      Remix.sparkling_line,
      desc: 'enable_rtx_vsr_subtitle',
      keywords: ['NVIDIA', 'RTX', '超分'],
      when: _windows,
    )
    ..toggle(
      'hard_stop',
      'force_destroy_player',
      Settings.useHardStopOnExit,
      Remix.stop_circle_line,
      desc: 'settings_hard_stop_desc',
    )
    ..toggle(
      'custom_output',
      'custom_output_hwdec',
      Settings.customPlayerOutput,
      Remix.equalizer_line,
      desc: 'settings_custom_output_desc',
      keywords: ['mpv', 'vo', 'ao', 'hwdec'],
    )
    ..add(
      'video_output',
      'video_output_driver',
      (context, entry) => MpvOptionTile(entry: entry, kind: MpvOptionKind.video),
      settings: [Settings.videoOutputDriver],
      keywords: ['mpv', 'vo'],
    )
    ..add(
      'audio_output',
      'audio_output_driver',
      (context, entry) => MpvOptionTile(entry: entry, kind: MpvOptionKind.audio),
      settings: [Settings.audioOutputDriver],
      keywords: ['mpv', 'ao'],
    )
    ..add(
      'hardware_decoder',
      'hardware_decoder',
      (context, entry) => MpvOptionTile(entry: entry, kind: MpvOptionKind.decoder),
      settings: [Settings.videoHardwareDecoder],
      keywords: ['mpv', 'hwdec'],
    )
    // ---- danmaku ----
    ..section = SettingsSection.danmaku
    ..group = 'settings_group_danmaku_display'
    ..toggle(
      'danmaku_show',
      'show_danmaku',
      Settings.enableDanmakuDisplay,
      Remix.chat_smile_2_line,
      desc: 'settings_danmaku_show_desc',
    )
    ..toggle(
      'danmaku_on_video',
      'live_play_danmaku_on_video',
      Settings.hideDanmaku,
      Remix.stack_line,
      inverted: true,
      desc: 'settings_danmaku_on_video_desc',
    )
    ..toggle(
      'danmaku_no_emoji',
      'danmaku_no_emoji',
      Settings.noEmojiMode,
      Remix.emotion_unhappy_line,
      desc: 'settings_danmaku_no_emoji_desc',
      keywords: ['表情', 'emoji'],
    )
    ..slider(
      'danmaku_area',
      'live_play_danmaku_area',
      Settings.danmakuArea,
      Remix.layout_top_line,
      min: 0.1,
      max: 1,
      step: 0.05,
      format: _percent,
      desc: 'settings_danmaku_area_desc',
    )
    ..slider(
      'danmaku_top',
      'settings_danmaku_top_margin',
      Settings.danmakuTopArea,
      Remix.align_top,
      min: 0,
      max: 300,
      step: 1,
      format: _pixels,
      desc: 'settings_danmaku_top_margin_desc',
    )
    ..slider(
      'danmaku_bottom',
      'settings_danmaku_bottom_margin',
      Settings.danmakuBottomArea,
      Remix.align_bottom,
      min: 0,
      max: 300,
      step: 1,
      format: _pixels,
      desc: 'settings_danmaku_bottom_margin_desc',
    )
    ..slider(
      'danmaku_opacity',
      'opacity',
      Settings.danmakuOpacity,
      Remix.contrast_drop_line,
      min: 0.1,
      max: 1,
      step: 0.05,
      format: _percent,
      keywords: ['透明', 'opacity', '弹幕'],
    )
    ..slider(
      'danmaku_speed',
      'speed',
      Settings.danmakuSpeed,
      Remix.speed_line,
      min: 30,
      max: 400,
      step: 1,
      format: _whole,
      desc: 'settings_danmaku_speed_desc',
      keywords: ['速度', 'speed', '弹幕'],
    )
    ..slider(
      'danmaku_font_size',
      'font_size',
      Settings.danmakuFontSize,
      Remix.font_size_2,
      min: 10,
      max: 40,
      step: 1,
      format: _whole,
      keywords: ['字号', 'size', '弹幕'],
    )
    ..slider(
      'danmaku_font_weight',
      'font_weight',
      Settings.danmakuFontWeight,
      Remix.bold,
      min: 100,
      max: 900,
      step: 100,
      format: _whole,
      keywords: ['粗细', 'weight', '弹幕'],
    )
    ..toggle(
      'danmaku_stroke',
      'danmaku_stroke',
      Settings.enableDanmakuStroke,
      Remix.font_color,
      desc: 'settings_danmaku_stroke_desc',
    )
    ..slider(
      'danmaku_stroke_width',
      'stroke',
      Settings.danmakuFontBorder,
      Remix.pen_nib_line,
      min: 0,
      max: 4,
      step: 0.5,
      format: (value) => value.toStringAsFixed(1),
      enabledBy: Settings.enableDanmakuStroke,
      keywords: ['描边', 'stroke', '弹幕'],
    )
    ..toggle(
      'danmaku_auto_fps',
      'settings_danmaku_auto_fps',
      Settings.danmakuAutoFps,
      Remix.speed_up_line,
      desc: 'settings_danmaku_auto_fps_desc',
      keywords: ['帧率', 'fps'],
    )
    ..slider(
      'danmaku_fps',
      'danmaku_fps',
      Settings.danmakuFps,
      Remix.dashboard_3_line,
      min: 30,
      max: 240,
      step: 1,
      format: (value) => '${value.round()} FPS',
      keywords: ['帧率', 'fps'],
    )
    ..add(
      'danmaku_font',
      'change_danmaku_font_family',
      (context, entry) => FontFamilyTile(entry: entry, setting: Settings.danmakuFontFamilyName),
      desc: 'settings_app_font_desc',
      settings: [Settings.danmakuFontFamilyName, Settings.danmakuFontFamilyFileName],
      keywords: ['字体', 'font'],
    )
    ..group = 'danmaku_filter'
    ..link(
      'block_list',
      'settings_block_list',
      Remix.forbid_line,
      route: RoutePath.kSettingsDanmuShield,
      desc: 'settings_block_list_desc',
      keywords: ['屏蔽', '关键词', 'block'],
    )
    ..toggle(
      'collapse_repeated',
      'collapse_repeated_danmaku',
      Settings.collapseRepeatedDanmaku,
      Remix.filter_2_line,
      desc: 'collapse_repeated_danmaku_desc',
      keywords: ['重复', '刷屏'],
    )
    ..slider(
      'repeat_window',
      'settings_repeat_window',
      Settings.repeatedDanmakuWindowSeconds,
      Remix.timer_line,
      min: 1,
      max: 30,
      format: (value) => '${value.round()} s',
      enabledBy: Settings.collapseRepeatedDanmaku,
      desc: 'settings_repeat_window_desc',
    )
    ..toggle(
      'similarity_filter',
      'danmaku_similarity_filter_enable',
      Settings.enableDanmakuSimilarityFilter,
      Remix.git_merge_line,
      desc: 'danmaku_similarity_filter_desc',
      keywords: ['相似', '刷屏'],
    )
    ..slider(
      'similarity_threshold',
      'danmaku_similarity_threshold',
      Settings.danmakuSimilarityThreshold,
      Remix.equalizer_line,
      min: 50,
      max: 100,
      format: (value) => '${value.round()}%',
      desc: 'danmaku_similarity_threshold_desc',
      enabledBy: Settings.enableDanmakuSimilarityFilter,
    )
    ..slider(
      'similarity_duration',
      'danmaku_similarity_cache_duration',
      Settings.danmakuSimilarityCacheDuration,
      Remix.time_line,
      min: 1,
      max: 60,
      format: (value) => '${value.round()} s',
      desc: 'danmaku_similarity_cache_duration_desc',
      enabledBy: Settings.enableDanmakuSimilarityFilter,
    )
    ..slider(
      'similarity_size',
      'danmaku_similarity_max_cache_size',
      Settings.danmakuSimilarityMaxCacheSize,
      Remix.stack_line,
      min: 20,
      max: 1000,
      step: 10,
      format: _whole,
      desc: 'danmaku_similarity_max_cache_size_desc',
      enabledBy: Settings.enableDanmakuSimilarityFilter,
    )
    ..toggle(
      'douyu_bots',
      'settings_douyu_bots',
      Settings.filterDouyuSuspectedAutomatedMessages,
      Remix.robot_2_line,
      desc: 'settings_douyu_bots_desc',
      keywords: ['斗鱼', 'douyu', '机器人'],
    )
    ..toggle(
      'youtube_all_chat',
      'settings_youtube_all_chat',
      Settings.youtubeShowAllChat,
      Remix.youtube_line,
      desc: 'settings_youtube_all_chat_desc',
      keywords: ['YouTube', '聊天'],
    )
    ..group = 'danmaku_screen_interaction'
    ..toggle(
      'danmaku_tap',
      'settings_danmaku_tap',
      Settings.enableDanmakuTapInteraction,
      Remix.cursor_line,
      desc: 'settings_danmaku_tap_desc',
    )
    ..toggle(
      'danmaku_long_press',
      'settings_danmaku_long_press',
      Settings.enableDanmakuLongPressInteraction,
      Remix.hand,
      desc: 'settings_danmaku_long_press_desc',
    )
    ..group = 'pip_danmaku'
    ..toggle(
      'pip_danmaku',
      'pip_danmaku_enable',
      Settings.enablePipDanmaku,
      Remix.picture_in_picture_2_line,
      desc: 'settings_pip_danmaku_desc',
      keywords: ['画中画', '小窗', 'PiP'],
    )
    ..link(
      'pip_danmaku_style',
      'settings_pip_danmaku_style',
      Remix.palette_line,
      page: (_) => const PipDanmakuPage(),
      desc: 'settings_pip_danmaku_style_desc',
      settings: pipDanmakuSettings,
      keywords: ['画中画', '小窗', 'PiP'],
    )
    // ---- platforms ----
    ..section = SettingsSection.platforms
    ..group = 'platform_settings'
    ..link(
      'platform_list',
      'platform_display',
      Remix.apps_2_line,
      route: RoutePath.kSettingsHotAreas,
      desc: 'settings_platform_list_desc',
      settings: [Settings.hotAreasList],
      keywords: ['平台', 'platform'],
    )
    ..add(
      'prefer_platform',
      'prefer_platform',
      (context, entry) => PreferPlatformTile(entry: entry),
      desc: 'settings_prefer_platform_desc',
      settings: [Settings.preferPlatform],
      keywords: ['平台', 'platform'],
    )
    ..link(
      'accounts',
      'settings_accounts',
      Remix.account_circle_line,
      route: RoutePath.kSettingsAccount,
      desc: 'settings_accounts_desc',
      keywords: ['Cookie', '登录', 'login', '账号'],
    )
    ..link(
      'tags',
      'tag_management',
      Remix.price_tag_3_line,
      route: RoutePath.kSettingsTags,
      desc: 'settings_tags_desc',
      keywords: ['分组', 'tag'],
    )
    ..link(
      'iptv',
      'iptv_settings',
      Remix.tv_2_line,
      route: RoutePath.kIptv,
      desc: 'settings_iptv_desc',
      keywords: ['IPTV', 'M3U', '电视'],
    )
    ..group = 'settings_group_discover'
    ..toggle(
      'show_unplayable',
      'settings_show_unplayable',
      Settings.showUnplayableInDiscover,
      Remix.lock_line,
      desc: 'settings_show_unplayable_desc',
      keywords: ['付费', '加锁', '受限'],
    )
    ..add(
      'audience_mode',
      'audience_display_mode',
      (context, entry) => SettingChoiceTile<bool>(
        entry: entry,
        setting: Settings.preferRealOnlineCounts,
        icon: Remix.group_line,
        hint: i18n('audience_ranking_rule_desc'),
        options: () => [
          (value: false, label: i18n('audience_mode_heat'), description: i18n('audience_mode_heat_desc')),
          (value: true, label: i18n('audience_mode_online'), description: i18n('audience_mode_online_desc')),
        ],
      ),
      desc: 'settings_audience_mode_desc',
      settings: [Settings.preferRealOnlineCounts],
      keywords: ['人数', '热度', '在线', 'viewers'],
    )
    ..link(
      'audience_platforms',
      'audience_online_platforms',
      Remix.list_check_2,
      page: (_) => const AudiencePlatformsPage(),
      desc: 'settings_audience_platforms_desc',
      settings: [Settings.realOnlinePlatforms],
      keywords: ['人数', '在线', 'viewers'],
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
      Remix.refresh_line,
      desc: 'settings_douyu_renew_desc',
      keywords: ['斗鱼', 'douyu', 'Cookie'],
    )
    // ---- follows ----
    ..section = SettingsSection.follows
    ..group = 'auto_refresh_settings'
    ..toggle(
      'refresh_on_resume',
      'refresh_follow_on_resume',
      Settings.refreshFavoriteOnResume,
      Remix.restart_line,
      desc: 'settings_refresh_on_resume_desc',
      keywords: ['刷新', 'refresh'],
    )
    ..toggle(
      'auto_refresh',
      'auto_refresh_follow',
      Settings.autoRefreshFavorite,
      Remix.refresh_line,
      desc: 'settings_auto_refresh_desc',
      keywords: ['刷新', 'refresh'],
    )
    ..number(
      'refresh_interval',
      'auto_refresh_interval',
      Settings.autoRefreshInterval,
      Remix.timer_line,
      presets: const [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360],
      label: formatMinutes,
      unit: 'minute',
      enabledBy: Settings.autoRefreshFavorite,
      keywords: ['刷新', 'refresh'],
    )
    ..number(
      'refresh_concurrency',
      'max_concurrent_refresh',
      Settings.maxConcurrentRefresh,
      Remix.stack_line,
      presets: const [1, 2, 3, 4, 6, 8, 10, 12, 16, 20],
      label: (value) => value == 4 ? '$value · ${i18n('recommended')}' : '$value',
      desc: 'settings_refresh_concurrency_desc',
      keywords: ['刷新', 'refresh'],
    )
    ..toggle(
      'refresh_covers',
      'auto_refresh_thumbnails',
      Settings.autoRefreshThumbnails,
      Remix.image_line,
      desc: 'auto_refresh_thumbnails_subtitle',
      keywords: ['封面', 'cover'],
    )
    ..number(
      'cover_interval',
      'thumbnail_refresh_interval',
      Settings.thumbnailRefreshInterval,
      Remix.timer_2_line,
      presets: const [5, 10, 15, 30, 60, 120, 240, 360],
      label: formatMinutes,
      unit: 'minute',
      enabledBy: Settings.autoRefreshThumbnails,
      keywords: ['封面', 'cover'],
    )
    ..group = 'history'
    ..number(
      'history_limit',
      'history_limit',
      Settings.historyLimit,
      Remix.history_line,
      presets: const [0, 20, 50, 100, 200, 500],
      label: (value) => value == 0 ? i18n('settings_no_limit') : '$value',
      desc: 'settings_history_limit_desc',
      keywords: ['历史', 'history'],
    )
    // ---- network ----
    ..section = SettingsSection.network
    ..group = 'settings_group_app_proxy'
    ..add(
      'app_proxy',
      'enable_app_proxy',
      (context, entry) => ProxyTile(entry: entry, proxy: ProxySettings.app),
      desc: 'settings_app_proxy_desc',
      settings: [Settings.enableAppProxy, Settings.appProxyHost, Settings.appProxyPort],
      keywords: ['代理', 'proxy', 'HTTP'],
    )
    ..group = 'settings_group_player_proxy'
    ..add(
      'player_proxy',
      'enable_player_proxy',
      (context, entry) => ProxyTile(entry: entry, proxy: ProxySettings.player),
      desc: 'settings_player_proxy_desc',
      settings: [Settings.enableProxy, Settings.proxyHost, Settings.proxyPort],
      keywords: ['代理', 'proxy', 'HTTP'],
    )
    // ---- recording ----
    ..section = SettingsSection.recording
    ..group = 'settings_section_recording'
    ..link(
      'record_settings',
      'record_settings',
      Remix.settings_3_line,
      route: RoutePath.kRecordSettings,
      desc: 'settings_record_settings_desc',
      keywords: ['录制', 'record'],
    )
    ..link(
      'record_center',
      'record_center',
      Remix.download_2_line,
      route: RoutePath.kRecordPage,
      desc: 'settings_record_center_desc',
      keywords: ['录制', 'record'],
    )
    // ---- general ----
    ..section = SettingsSection.general
    ..group = 'settings_group_startup'
    ..toggle(
      'splash',
      'splash_animation',
      Settings.showSplashPage,
      Remix.rocket_2_line,
      desc: 'splash_animation_subtitle',
    )
    ..toggle(
      'auto_update',
      'enable_auto_check_update',
      Settings.enableAutoCheckUpdate,
      Remix.refresh_line,
      desc: 'settings_auto_update_desc',
      keywords: ['更新', 'update'],
    )
    ..toggle(
      'github_updates',
      'use_github_origin_for_updates',
      Settings.useGitHubOriginForUpdates,
      Remix.github_line,
      desc: 'use_github_origin_for_updates_desc',
      keywords: ['更新', 'update', 'GitHub'],
    )
    ..add(
      'startup',
      'startup',
      (context, entry) => StartupTile(entry: entry),
      desc: 'settings_startup_desc',
      settings: [Settings.enableStartUp],
      keywords: ['开机', 'startup'],
      when: _windows,
    )
    ..group = 'navigation_display_settings'
    ..link(
      'home_menus',
      'settings_home_menus',
      Remix.menu_line,
      page: (_) => const HomeMenusPage(),
      desc: 'settings_home_menus_desc',
      settings: [Settings.savedMenuIds],
      keywords: ['菜单', '底栏', 'menu', 'tab'],
    )
    ..toggle(
      'multiview',
      'multiview_title',
      Settings.enableMultiView,
      Remix.layout_grid_line,
      desc: 'settings_multiview_desc',
      keywords: ['多画面', 'multi'],
    )
    ..toggle(
      'new_window',
      'open_new_window',
      Settings.enableNewWindowPlay,
      Remix.window_line,
      desc: 'open_new_window_subtitle',
      when: _windows,
    )
    ..add(
      'refresh_rate',
      'refresh_rate_mode',
      (context, entry) => RefreshRateTile(
        entry: entry,
        hint: i18n('refresh_rate_mode_hint'),
        options: () => _keyed(
          {
            'powerSaving': 'refresh_rate_power_saving',
            'balanced': 'refresh_rate_balanced',
            'performance': 'refresh_rate_performance',
          },
          {
            'powerSaving': 'refresh_rate_power_saving_desc',
            'balanced': 'refresh_rate_balanced_desc',
            'performance': 'refresh_rate_performance_desc',
          },
        ),
      ),
      desc: 'settings_refresh_rate_desc',
      settings: [Settings.refreshRateMode],
      keywords: ['Hz', '高刷', 'refresh rate'],
      when: _refreshRate,
    )
    ..add(
      'windows_display',
      'windows_dynamic_refresh_rate',
      (context, entry) => WindowsDisplayTile(entry: entry),
      desc: 'windows_dynamic_refresh_rate_subtitle',
      keywords: ['Hz', '刷新率', 'refresh rate', '显示器'],
      when: _windows,
    )
    ..group = 'settings_group_window'
    ..add(
      'window_size',
      'window_size',
      (context, entry) => WindowSizeTile(entry: entry),
      desc: 'settings_window_size_desc',
      settings: [Settings.windowWidth, Settings.windowHeight],
      when: _windows,
    )
    ..choice(
      'exit_action',
      'settings_exit_action',
      Settings.exitChoose,
      Remix.logout_box_r_line,
      () => _keyed({'exit': 'settings_exit_action_exit', 'minimize': 'settings_exit_action_minimize'}),
      desc: 'settings_exit_action_desc',
      keywords: ['托盘', '关闭', 'close'],
      when: _windows,
    )
    ..toggle(
      'dont_ask_exit',
      'no_exit_confirm',
      Settings.dontAskExit,
      Remix.error_warning_line,
      desc: 'settings_dont_ask_exit_desc',
      keywords: ['关闭', 'close'],
      when: _windows,
    )
    ..group = 'settings_group_timer'
    ..add(
      'auto_exit',
      'enable_countdown_close',
      (context, entry) => AutoExitTile(entry: entry),
      desc: 'enable_countdown_close_subtitle',
      settings: [Settings.enableAutoShutDownTime],
      keywords: ['定时', '关闭', 'timer'],
    )
    ..number(
      'auto_exit_minutes',
      'countdown_duration',
      Settings.autoShutDownTime,
      Remix.timer_line,
      presets: const [15, 30, 45, 60, 90, 120, 180],
      label: formatMinutes,
      unit: 'minute',
      desc: 'app_exit_timer_explain',
      keywords: ['定时', '关闭', 'timer'],
    )
    // ---- data ----
    ..section = SettingsSection.data
    ..group = 'backup_manage'
    ..link(
      'backup',
      'backup_recover',
      Remix.save_3_line,
      route: RoutePath.kBackup,
      desc: 'settings_backup_desc',
      keywords: ['备份', '恢复', 'backup'],
    )
    ..link(
      'webdav',
      'webdav',
      Remix.cloud_line,
      route: RoutePath.kWebDavPage,
      desc: 'settings_webdav_desc',
      keywords: ['云', '同步', 'WebDAV'],
    )
    ..link(
      'config_preview',
      'config_preview',
      Remix.file_text_line,
      page: (_) => const ConfigPreviewPage(),
      desc: 'settings_config_preview_desc',
      keywords: ['JSON', '配置'],
    )
    ..group = 'cache_and_data'
    ..add(
      'image_cache',
      'settings_image_cache',
      (context, entry) => ImageCacheTile(entry: entry),
      desc: 'settings_image_cache_desc',
      keywords: ['缓存', 'cache', '清理'],
    )
    ..add(
      'refresh_covers_now',
      'refresh_thumbnails',
      (context, entry) => RefreshCoversTile(entry: entry),
      desc: 'refresh_thumbnails_desc',
      keywords: ['封面', '缩略图', 'cover', 'thumbnail'],
    )
    ..add(
      'download_directory',
      'download_directory',
      (context, entry) => DownloadDirectoryTile(entry: entry),
      desc: 'download_directory_desc',
      settings: [Settings.downloadDirectoryPath],
      keywords: ['下载', '更新', 'download'],
    )
    ..link(
      'log',
      'log_manage',
      Remix.file_list_3_line,
      page: (_) => const LogPage(),
      desc: 'settings_log_desc',
      settings: [Settings.enableLocalLog, Settings.logLevel],
      keywords: ['日志', '错误', 'log', 'debug'],
    )
    ..add(
      'reset_all',
      'settings_reset_all',
      (context, entry) => ResetAllTile(entry: entry),
      desc: 'settings_reset_all_desc',
      keywords: ['默认', 'reset'],
    )
    // ---- about ----
    ..section = SettingsSection.about
    ..group = 'settings_section_about'
    ..link('about', 'about', Remix.information_line, route: RoutePath.kAbout, desc: 'settings_about_desc')
    ..link(
      'check_update',
      'check_update',
      Remix.download_cloud_2_line,
      route: RoutePath.kVersionPage,
      desc: 'settings_check_update_desc',
      keywords: ['版本', 'version', '更新'],
    );
  return List.unmodifiable(c.entries);
}

/// Settings of the picture-in-picture danmaku page (its reset).
const List<Setting<Object>> pipDanmakuSettings = [
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
