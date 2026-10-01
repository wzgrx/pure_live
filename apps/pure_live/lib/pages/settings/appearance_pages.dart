import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/settings/loading_style_names.dart';
import 'package:pure_live/pages/settings/settings_dialogs.dart';
import 'package:pure_live/pages/settings/settings_model.dart';
import 'package:pure_live/pages/settings/settings_tiles.dart';
import 'package:pure_live/routes/app_navigator.dart';

Widget _noRow(BuildContext context, SettingsEntry entry) => const SizedBox.shrink();

/// An entry for a row of a sub-page (not in the catalogue, not searched).
SettingsEntry subEntry(String id, String title, {String? description}) => SettingsEntry(
  id: id,
  section: SettingsSection.appearance,
  group: '',
  title: title,
  description: description,
  build: _noRow,
);

/// Theme mode as three buttons on the row (3.x opened a dialog for it).
class ThemeModeTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = watchSetting(ref, Settings.themeMode);
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: Remix.contrast_2_line,
        title: entry.titleText,
        subtitle: entry.descriptionText,
        isLong: true,
        stackTrailingOnNarrow: true,
        trailing: SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(value: 'System', icon: const Icon(Remix.computer_line), tooltip: i18n('theme_mode_system')),
            ButtonSegment(value: 'Light', icon: const Icon(Remix.sun_line), tooltip: i18n('theme_mode_light')),
            ButtonSegment(value: 'Dark', icon: const Icon(Remix.moon_line), tooltip: i18n('theme_mode_dark')),
          ],
          selected: {mode},
          onSelectionChanged: (selected) => writeSetting(ref, Settings.themeMode, selected.single),
        ),
      ),
    );
  }
}

/// The theme colour: a swatch on the row, the palette in a dialog.
class ThemeColorTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = parseColorHex(watchSetting(ref, Settings.themeColorSwitch)) ?? const Color(0xFF2196F3);
    final dynamicOn = watchSetting(ref, Settings.enableDynamicTheme);
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: Remix.palette_line,
        title: entry.titleText,
        subtitle: dynamicOn ? i18n('settings_theme_color_dynamic_note') : entry.descriptionText,
        isLong: true,
        trailing: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        onTap: () async {
          final picked = await showColorDialog(context: context, title: entry.titleText, current: color);
          final chosen = picked?.color;
          if (chosen != null && context.mounted) writeSetting(ref, Settings.themeColorSwitch, colorHex(chosen));
        },
      ),
    );
  }
}

/// The language, with "follow the system" (3.x had only the two languages,
/// though it followed the system until one was picked).
class LanguageTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  static const _system = 'system';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    final stored = watchSetting(ref, Settings.language);
    final current = settings.isSet(Settings.language) && AppLanguage.fromName(stored) != null
        ? AppLanguage.fromName(stored)!.displayName
        : _system;
    final options = <SettingsChoice<String>>[
      (value: _system, label: i18n('settings_language_system'), description: null),
      for (final language in AppLanguage.values)
        (value: language.displayName, label: language.displayName, description: null),
    ];
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: Remix.translate_2,
        title: entry.titleText,
        subtitle: entry.descriptionText,
        isLong: true,
        stackTrailingOnNarrow: true,
        trailing: SettingValueText(options.firstWhere((option) => option.value == current).label),
        onTap: () async {
          final picked = await showChoiceDialog<String>(
            context: context,
            title: entry.titleText,
            options: options,
            selected: current,
          );
          if (picked == null || picked == current) return;
          if (picked == _system) {
            await settings.reset(Settings.language);
          } else {
            await settings.set(Settings.language, picked);
          }
        },
      ),
    );
  }
}

/// The app or danmaku font. Only the system font can be chosen until the
/// font downloads come back (3.x's font manager downloaded fonts from a
/// cloud list; see the module record); a 3.x choice shows as not installed
/// and can be reset.
class FontFamilyTile extends ConsumerWidget {
  /// Creates the row for [setting] (`fontFamilyName` or
  /// `danmakuFontFamilyName`).
  const new({required this.entry, required this.setting, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// The stored font name.
  final StringSetting setting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = watchSetting(ref, setting);
    final isDefault = name.isEmpty || name == setting.defaultValue;
    final systemName = !kIsWeb && Platform.isWindows ? 'Microsoft YaHei' : i18n('font_system_default');
    final label = isDefault ? systemName : name;
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: Remix.font_family,
        title: entry.titleText,
        subtitle: isDefault ? entry.descriptionText : i18n('settings_font_not_installed', args: {'name': name}),
        isLong: true,
        stackTrailingOnNarrow: true,
        trailing: SettingValueText(label),
        onTap: () async {
          final picked = await showChoiceDialog<String>(
            context: context,
            title: entry.titleText,
            hint: i18n('settings_font_hint'),
            options: [
              (value: setting.defaultValue, label: systemName, description: i18n('factory_default_desc')),
              if (!isDefault)
                (value: name, label: name, description: i18n('settings_font_not_installed', args: {'name': name})),
            ],
            selected: isDefault ? setting.defaultValue : name,
          );
          if (picked == setting.defaultValue && !isDefault && context.mounted) {
            final settings = ref.read(storeProvider).settings;
            await settings.reset(setting);
            await settings.reset(
              setting == Settings.fontFamilyName ? Settings.fontFamilyFileName : Settings.danmakuFontFamilyFileName,
            );
            AppNavigator.toast(i18n('font_reset_default'));
          }
        },
      ),
    );
  }
}

/// The five text sizes with a live preview (3.x `FontSettingsPage`).
class FontSizesPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  static const List<(String, DoubleSetting, IconData)> _sizes = [
    ('font_body_small', Settings.fontSizeBodySmall, Remix.font_size),
    ('font_body_medium', Settings.fontSizeBodyMedium, Remix.font_size),
    ('font_body_large', Settings.fontSizeBodyLarge, Remix.font_size_2),
    ('font_title_medium', Settings.fontSizeTitleMedium, Remix.heading),
    ('font_title_large', Settings.fontSizeTitleLarge, Remix.heading),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final styles = context.textStyles;
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('font_settings_title')),
        actions: [
          IconButton(
            key: const ValueKey('settings-font-sizes-reset'),
            tooltip: i18n('reset'),
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () async {
              final settings = ref.read(storeProvider).settings;
              for (final (_, setting, _) in _sizes) {
                await settings.reset(setting);
              }
              AppNavigator.toast(i18n('settings_reset_done'));
            },
          ),
        ],
      ),
      body: SettingsListView(
        children: [
          context.buildGroupTitle(i18n('settings_preview')),
          context.buildModernCard([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i18n('settings_preview_title'), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(i18n('settings_preview_heading'), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(i18n('text_size_preview'), style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(i18n('settings_preview_body'), style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(i18n('settings_preview_caption'), style: styles.t12.copyWith(color: theme.hintColor)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('font_settings_title')),
          context.buildModernCard([
            for (final (key, setting, icon) in _sizes)
              CardTile(
                child: SettingSliderTile(
                  entry: subEntry(key, '${key}_title', description: '${key}_desc'),
                  setting: setting,
                  icon: icon,
                  min: setting.min!,
                  max: setting.max!,
                  step: 1,
                  format: (value) => '${value.round()} px',
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

/// The name of a loading style in the current language.
String loadingStyleName(String key) {
  final names = loadingStyleNames[key];
  if (names == null) return key;
  return currentStrings?.language == AppLanguage.en ? names.$2 : names.$1;
}

/// The loading animation: a live preview on the row, the gallery on a page.
class LoadingStyleTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = LoadingStyles.normalize(watchSetting(ref, Settings.loadingStyle));
    final color = parseColorHex(watchSetting(ref, Settings.loadingStyleColorSwitch));
    final theme = Theme.of(context);
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        // A still frame: an endless animation on every settings visit costs
        // battery; the gallery plays them.
        iconWidget: TickerMode(
          enabled: false,
          child: SizedBox.square(
            key: ValueKey('settings-loading-preview-$style'),
            dimension: 22,
            child: LoadingStyles.build(
              style,
              color: color ?? theme.colorScheme.primary,
              size: 22,
              colors: theme.colorScheme,
            ),
          ),
        ),
        title: entry.titleText,
        subtitle: entry.descriptionText,
        isLong: true,
        stackTrailingOnNarrow: true,
        trailing: SettingValueText(loadingStyleName(style)),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LoadingStylePage())),
      ),
    );
  }
}

/// Every loading animation, playing, to pick from; and its colour (3.x
/// `LoadingStyleSettingsPage`).
class LoadingStylePage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = LoadingStyles.normalize(watchSetting(ref, Settings.loadingStyle));
    final stored = watchSetting(ref, Settings.loadingStyleColorSwitch);
    final custom = parseColorHex(stored);
    final theme = Theme.of(context);
    final color = custom ?? theme.colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text(i18n('change_loading_style'))),
      body: CustomScrollView(
        physics: const PureLiveScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            sliver: SliverToBoxAdapter(
              child: context.buildModernCard([
                context.buildTile(
                  icon: Remix.palette_line,
                  title: i18n('settings_loading_color'),
                  subtitle: custom == null ? i18n('settings_color_follow_theme') : '#${colorHex(custom).substring(2)}',
                  trailing: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                  ),
                  onTap: () async {
                    final picked = await showColorDialog(
                      context: context,
                      title: i18n('settings_loading_color'),
                      current: custom,
                      allowThemeColor: true,
                    );
                    if (picked == null || !context.mounted) return;
                    writeSetting(
                      ref,
                      Settings.loadingStyleColorSwitch,
                      picked.color == null ? '' : colorHex(picked.color!),
                    );
                  },
                ),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 132,
                mainAxisExtent: 112,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: LoadingStyles.keys.length,
              itemBuilder: (context, index) {
                final key = LoadingStyles.keys[index];
                final isSelected = key == selected;
                return Material(
                  key: ValueKey('settings-loading-style-$key'),
                  color: isSelected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: isSelected ? theme.colorScheme.primary : Colors.transparent, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => writeSetting(ref, Settings.loadingStyle, key),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox.square(
                            dimension: 40,
                            child: Center(
                              child: LoadingStyles.build(key, color: color, size: 36, colors: theme.colorScheme),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            loadingStyleName(key),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.t12,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Card appearance per screen kind, with a live preview (3.x
/// `RoomCardSettingsPage`).
class RoomCardSettingsPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  ConsumerState<RoomCardSettingsPage> createState() => _RoomCardSettingsPageState();
}

class _RoomCardSettingsPageState extends ConsumerState<RoomCardSettingsPage> {
  late RoomCardViewport _viewport = switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => RoomCardViewport.mobile,
    _ => RoomCardViewport.desktop,
  };

  bool get _mobile => _viewport == RoomCardViewport.mobile;
  StringSetting get _presetSetting => _mobile ? Settings.roomCardMobilePreset : Settings.roomCardDesktopPreset;
  JsonSetting get _configSetting => _mobile ? Settings.roomCardMobileConfig : Settings.roomCardDesktopConfig;

  RoomCardAppearance _appearance(String presetKey, Map<String, Object?> config) {
    final preset = RoomCardPreset.values.firstWhere(
      (value) => value.storageKey == presetKey,
      orElse: () => RoomCardPreset.standard,
    );
    final fallback = RoomCardAppearance.fromPreset(preset);
    if (config.isEmpty) return fallback;
    return RoomCardAppearance.fromJson(Map<String, dynamic>.of(config), fallback: fallback);
  }

  Future<void> _store(RoomCardAppearance appearance) async {
    final preset = RoomCardAppearance.presetOf(appearance);
    await ref.read(storeProvider).settings.setAll({
      _presetSetting: preset.storageKey,
      _configSetting: preset == RoomCardPreset.custom ? appearance.toJson() : const <String, Object?>{},
    });
  }

  @override
  Widget build(BuildContext context) {
    final appearance = _appearance(watchSetting(ref, _presetSetting), watchSetting(ref, _configSetting));
    final preset = RoomCardAppearance.presetOf(appearance);
    final colors = Theme.of(context).colorScheme;
    void update(RoomCardAppearance next) => unawaited(_store(next));
    Widget chip<T>(T value, T current, String label, ValueChanged<T> onSelected, {Key? key}) => ChoiceChip(
      key: key,
      label: Text(label),
      selected: value == current,
      selectedColor: colors.primaryContainer,
      onSelected: (_) => onSelected(value),
    );
    final sample = RoomCardData(
      platformId: 'bilibili',
      title: 'Pure Live · ${i18n('room_card_preview_title')}',
      anchorName: i18n('room_card_preview_anchor'),
      isLive: true,
      audience: const RoomAudience(kind: RoomAudienceKind.popularity, value: '1.2万'),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('room_card_settings')),
        actions: [
          IconButton(
            key: const ValueKey('settings-room-card-reset'),
            tooltip: i18n('room_card_reset_current'),
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () async {
              final settings = ref.read(storeProvider).settings;
              await settings.reset(_presetSetting);
              await settings.reset(_configSetting);
              AppNavigator.toast(i18n('settings_reset_done'));
            },
          ),
        ],
      ),
      body: SettingsListView(
        children: [
          context.buildGroupTitle(i18n('room_card_target')),
          Center(
            child: SegmentedButton<RoomCardViewport>(
              segments: [
                ButtonSegment(
                  value: RoomCardViewport.mobile,
                  icon: const Icon(Remix.smartphone_line),
                  label: Text(i18n('room_card_mobile')),
                ),
                ButtonSegment(
                  value: RoomCardViewport.desktop,
                  icon: const Icon(Remix.computer_line),
                  label: Text(i18n('room_card_desktop')),
                ),
              ],
              selected: {_viewport},
              onSelectionChanged: (value) => setState(() => _viewport = value.single),
            ),
          ),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('room_card_preview')),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.clamp(0.0, 300.0);
              final height = RoomCardLayoutMetrics.gridMainAxisExtent(
                itemWidth: width,
                appearance: appearance,
                dense: false,
                textScaler: MediaQuery.textScalerOf(context),
                fontSizes: LiveFontSizes.of(Theme.of(context).textTheme),
              );
              return Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: RoomCard(
                    key: const ValueKey('settings-room-card-preview'),
                    data: sample,
                    appearance: appearance,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('room_card_presets')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in [
                (RoomCardPreset.compact, 'room_card_preset_compact'),
                (RoomCardPreset.standard, 'room_card_preset_standard'),
                (RoomCardPreset.detailed, 'room_card_preset_detailed'),
              ])
                chip(
                  value,
                  preset,
                  i18n(label),
                  (value) => update(RoomCardAppearance.fromPreset(value)),
                  key: ValueKey('settings-room-card-preset-${value.name}'),
                ),
              if (preset == RoomCardPreset.custom)
                Chip(label: Text(i18n('room_card_preset_custom')), backgroundColor: colors.primaryContainer),
            ],
          ),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('room_card_layout')),
          Wrap(
            spacing: 8,
            children: [
              chip(
                RoomCardLayout.cover,
                appearance.layout,
                i18n('room_card_layout_cover'),
                (value) => update(appearance.copyWith(layout: value)),
              ),
              chip(
                RoomCardLayout.compact,
                appearance.layout,
                i18n('room_card_layout_compact'),
                (value) => update(appearance.copyWith(layout: value)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('room_card_visible_content')),
          context.buildModernCard([
            context.buildSwitchTile(
              title: i18n('room_card_show_avatar'),
              subtitle: i18n('room_card_show_avatar_subtitle'),
              icon: Remix.user_3_line,
              value: appearance.showAvatar,
              onChanged: (value) => update(appearance.copyWith(showAvatar: value)),
            ),
            context.buildSwitchTile(
              title: i18n('room_card_show_anchor'),
              subtitle: i18n('room_card_show_anchor_subtitle'),
              icon: Remix.user_star_line,
              value: appearance.showAnchorName,
              onChanged: (value) => update(appearance.copyWith(showAnchorName: value)),
            ),
            context.buildSwitchTile(
              title: i18n('room_card_show_audience'),
              subtitle: i18n('room_card_show_audience_subtitle'),
              icon: Remix.group_line,
              value: appearance.showAudience,
              onChanged: (value) => update(appearance.copyWith(showAudience: value)),
            ),
            context.buildSwitchTile(
              title: i18n('room_card_show_replay'),
              subtitle: i18n('room_card_show_replay_subtitle'),
              icon: Remix.history_line,
              value: appearance.showReplayBadge,
              onChanged: (value) => update(appearance.copyWith(showReplayBadge: value)),
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('room_card_show_platform')),
          Wrap(
            spacing: 8,
            children: [
              for (final (mode, label) in [
                (RoomCardPlatformBadgeMode.automatic, 'room_card_platform_automatic'),
                (RoomCardPlatformBadgeMode.always, 'room_card_platform_always'),
                (RoomCardPlatformBadgeMode.hidden, 'room_card_platform_hidden'),
              ])
                chip(
                  mode,
                  appearance.platformBadgeMode,
                  i18n(label),
                  (value) => update(appearance.withPlatformBadgeMode(value)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n('room_card_appearance')),
          context.buildModernCard([
            context.buildSliderTile(
              icon: Remix.shape_line,
              title: i18n('room_card_corner_radius'),
              subtitle: i18n('room_card_corner_radius_subtitle'),
              value: appearance.cornerRadius,
              min: RoomCardAppearance.minCornerRadius,
              max: RoomCardAppearance.maxCornerRadius,
              displayValue: '${appearance.cornerRadius.round()}',
              onChanged: (value) => update(appearance.copyWith(cornerRadius: value.roundToDouble())),
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(i18n('room_card_settings_scope_hint'), style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// The page-size choices of the pager (3.x's options dialog): chips to
/// remove, a field to add, "adaptive" to go back to the screen-width rule.
class PageSizeOptionsTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// The stored text as numbers (comma separated, 1..100, no repeats).
  static List<int> parse(String raw) => [
    ...{
      for (final part in raw.split(','))
        if (int.tryParse(part.trim()) case final value? when value >= 1 && value <= 100) value,
    },
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = parse(watchSetting(ref, Settings.pageSizeOptions));
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: Remix.list_ordered,
        title: entry.titleText,
        subtitle: options.isEmpty ? i18n('adaptive_recommend') : options.join(', '),
        isLong: true,
        onTap: () async {
          final result = await showDialog<List<int>>(
            context: context,
            builder: (context) => _PageSizeDialog(initial: options),
          );
          if (result != null && context.mounted) {
            writeSetting(ref, Settings.pageSizeOptions, (List.of(result)..sort()).join(','));
          }
        },
      ),
    );
  }
}

class _PageSizeDialog extends StatefulWidget {
  const new({required this.initial});

  final List<int> initial;

  @override
  State<_PageSizeDialog> createState() => _PageSizeDialogState();
}

class _PageSizeDialogState extends State<_PageSizeDialog> {
  late final List<int> _options = List.of(widget.initial);
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final value = int.tryParse(_input.text.trim());
    if (value == null || value < 1 || value > 100) {
      setState(() => _error = i18n('settings_number_range', args: {'min': '1', 'max': '100'}));
      return;
    }
    setState(() {
      if (!_options.contains(value)) _options.add(value);
      _options.sort();
      _input.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => SettingsDialogFrame(
    title: i18n('page_size_options_manage'),
    actions: [
      TextButton(onPressed: () => setState(_options.clear), child: Text(i18n('adaptive_recommend'))),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
      FilledButton(onPressed: () => Navigator.of(context).pop(_options), child: Text(i18n('confirm'))),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n('current_options'), style: context.textStyles.t12),
          const SizedBox(height: 8),
          if (_options.isEmpty)
            Text(i18n('adaptive_recommend'), style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in _options)
                  InputChip(label: Text('$value'), onDeleted: () => setState(() => _options.remove(value))),
              ],
            ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    labelText: i18n('custom_input'),
                    suffixText: i18n('items_per_page'),
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _add, icon: const Icon(Icons.add_rounded), tooltip: i18n('add')),
            ],
          ),
        ],
      ),
    ),
  );
}
