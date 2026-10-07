import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/fonts.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/settings/font_manager_page.dart';
import 'package:pure_live/features/settings/loading_style_names.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

// The appearance page and the pages it opens (3.x theme_settings_page.dart
// and its sub-pages; docs/A-界面设计/A11-设置界面/A11.2-外观).

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

/// 3.x's theme modes in its order (`AppConsts.themeModes`).
const List<(String value, String label)> themeModes = [
  ('System', 'theme_mode_system'),
  ('Dark', 'theme_mode_dark'),
  ('Light', 'theme_mode_light'),
];

/// Theme mode: the current mode on the row, the three in a dialog (3.x
/// `ThemeChoiceDialog`; v4 had put three buttons on the row).
class ThemeModeTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = watchSetting(ref, Settings.themeMode);
    final options = [for (final (value, label) in themeModes) (value: value, label: i18n(label), description: null)];
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: AppIcons.themeMode,
      title: entry.titleText,
      choice: true,
      subtitle: entry.descriptionText,
      value: options.where((option) => option.value == mode).firstOrNull?.label,
      onTap: () async {
        final picked = await showChoiceDialog<String>(
          context: context,
          title: entry.titleText,
          options: options,
          selected: mode,
          showCancel: false,
        );
        if (picked != null && context.mounted) writeSetting(ref, Settings.themeMode, picked);
      },
    );
  }
}

/// Black backgrounds in the dark theme (U.6b C-4); no effect in the light
/// theme, which says so.
class PureBlackTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final light = watchSetting(ref, Settings.themeMode) == 'Light';
    return SettingsSwitchRow(
      key: entry.rowKey,
      icon: AppIcons.pureBlack,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      value: watchSetting(ref, Settings.pureBlackTheme),
      enabled: !light,
      disabledReason: i18n('settings_pure_black_light'),
      onChanged: (value) => writeSetting(ref, Settings.pureBlackTheme, value),
    );
  }
}

/// The colour of [hex], or the brand blue.
Color themeColorOf(String hex) => parseColorHex(hex) ?? LiveTheme.brandBlue;

/// The theme colour: a swatch on the row, the picker in a dialog. While
/// dynamic colour is on the wallpaper decides, so the row says so and
/// cannot be used (3.x let it be picked to no effect).
class ThemeColorTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = watchSetting(ref, Settings.themeColorSwitch);
    final color = themeColorOf(stored);
    final dynamicOn = watchSetting(ref, Settings.enableDynamicTheme) && defaultTargetPlatform != TargetPlatform.iOS;
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: AppIcons.themeColor,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      valueWidget: SettingsSwatch(color),
      enabled: !dynamicOn,
      disabledReason: i18n('settings_theme_color_dynamic'),
      onTap: () async {
        final settings = ref.read(storeProvider).settings;
        // The page behind follows the picker; cancel puts the colour back.
        final picked = await showColorDialog(
          context: context,
          title: i18n('theme_color'),
          current: color,
          onPreview: (preview) => unawaited(settings.set(Settings.themeColorSwitch, colorHex(preview))),
        );
        await settings.set(Settings.themeColorSwitch, picked == null ? stored : colorHex(picked));
      },
    );
  }
}

/// The language: English or 简体中文 (3.x); until one is picked the app
/// follows the system, and the row shows the language in use.
class LanguageTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    final stored = watchSetting(ref, Settings.language);
    final current = settings.isSet(Settings.language) && AppLanguage.fromName(stored) != null
        ? AppLanguage.fromName(stored)!
        : (currentStrings?.language ?? AppLanguage.zh);
    final options = <SettingsChoice<String>>[
      for (final language in AppLanguage.values)
        (value: language.displayName, label: language.displayName, description: null),
    ];
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: AppIcons.settingsLanguage,
      title: entry.titleText,
      choice: true,
      subtitle: entry.descriptionText,
      value: current.displayName,
      onTap: () async {
        final picked = await showChoiceDialog<String>(
          context: context,
          title: entry.titleText,
          options: options,
          selected: current.displayName,
          showCancel: false,
        );
        if (picked == null || (picked == current.displayName && settings.isSet(Settings.language))) return;
        await settings.set(Settings.language, picked);
      },
    );
  }
}

/// [value] as the spacing rows write it: whole pixels without decimals.
String spacingLabel(double value) {
  final text = value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);
  return i18n('settings_spacing_value', args: {'value': text});
}

/// Column or row spacing as a counter: − and + change it by 1 px (0–64),
/// the number opens 3.x's spacing dialog (U.6b c4).
class SpacingTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, required this.setting, required this.icon, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// `crossAxisSpacing` or `mainAxisSpacing`.
  final DoubleSetting setting;

  /// The icon.
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = watchSetting(ref, setting);
    final min = setting.min ?? 0;
    final max = setting.max ?? 64;
    return SettingsCounterRow(
      key: entry.rowKey,
      icon: icon,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      value: spacingLabel(value),
      decreaseTooltip: settingsDecrease,
      increaseTooltip: settingsIncrease,
      valueKey: ValueKey('settings-spacing-value-${setting.key}'),
      decreaseKey: ValueKey('settings-spacing-minus-${setting.key}'),
      increaseKey: ValueKey('settings-spacing-plus-${setting.key}'),
      onDecrease: value <= min ? null : () => writeSetting(ref, setting, (value.ceil() - 1).clamp(min, max).toDouble()),
      onIncrease: value >= max
          ? null
          : () => writeSetting(ref, setting, (value.floor() + 1).clamp(min, max).toDouble()),
      onValueTap: () async {
        final picked = await showAppDialog<double>(
          context: context,
          builder: (_) => _SpacingDialog(
            title: entry.titleText,
            description: entry.descriptionText,
            current: value,
            min: min,
            max: max,
          ),
        );
        if (picked != null && context.mounted) writeSetting(ref, setting, picked);
      },
    );
  }
}

class _SpacingDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.description,
    required this.current,
    required this.min,
    required this.max,
  });

  final String title;
  final String? description;
  final double current;
  final double min;
  final double max;

  @override
  State<_SpacingDialog> createState() => _SpacingDialogState();
}

class _SpacingDialogState extends State<_SpacingDialog> {
  static const List<double> _presets = [0, 4, 6, 8, 12, 16];
  late final TextEditingController _input = TextEditingController(text: _format(widget.current));
  String? _error;

  static String _format(double value) => value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_input.text.trim());
    if (value == null || !value.isFinite || value < widget.min || value > widget.max) {
      setState(() => _error = i18n('spacing_value_invalid'));
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final typed = double.tryParse(_input.text.trim());
    return SettingsDialogFrame(
      title: widget.title,
      actions: [
        const DialogCancelButton(),
        DialogActionButton(key: const ValueKey('settings-spacing-save'), label: i18n('save'), onPressed: _save),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.description case final description?) ...[
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],
            SettingsChoiceChips<double>(
              options: [
                for (final value in _presets)
                  (
                    value: value,
                    label: i18n('settings_spacing_value', args: {'value': '${value.round()}'}),
                    key: ValueKey('settings-spacing-preset-${value.round()}'),
                  ),
              ],
              selected: typed,
              onSelected: (value) => setState(() {
                _input.text = _format(value);
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('settings-spacing-input'),
              controller: _input,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.]'))],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(),
              decoration: dialogFieldDecoration(
                context,
                suffix: 'px',
                helper: i18n('settings_spacing_range'),
                error: _error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The system's text size without the app's factor.
TextScaler systemTextScaler(BuildContext context) => switch (MediaQuery.textScalerOf(context)) {
  final AppTextScaler scaler => scaler.system,
  final other => other,
};

/// "文字大小" (3.x "全局字体缩放比例"): 50–200 % on top of the system's
/// text size, with an example at the size chosen (U.6b c5, C-7).
class TextScaleTile extends StatelessWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context) => SettingSliderTile(
    entry: entry,
    setting: Settings.textScaleFactor,
    icon: AppIcons.textSize,
    min: 0.5,
    max: 2,
    step: 0.05,
    marks: const [0.5, 0.75, 1, 1.25, 1.5, 2],
    format: (value) => '${(value * 100).round()}%',
    below: (context, value) {
      final colors = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.surface, borderRadius: const BorderRadius.all(Radius.circular(12))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: AppTextScaler(systemTextScaler(context), value)),
              child: Text(
                i18n('text_size_preview'),
                key: const ValueKey('settings-text-size-preview'),
                style: context.textStyles.t14.copyWith(height: 1.5),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The app font: the chosen family's name (or the system font) and a tap
/// opens the font page ([FontManagerPage]). A choice whose files are not on
/// this device (3.x's choice on a new install) says so in red.
class FontFamilyTile extends ConsumerWidget {
  /// Creates the row for [setting] (`fontFamilyName` or
  /// `danmakuFontFamilyName`).
  const new({required this.entry, required this.setting, this.icon = AppIcons.appFont, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// The stored font name.
  final StringSetting setting;

  /// The icon (the danmaku font's row on the video page has 3.x's
  /// `font_size`).
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = watchSetting(ref, setting);
    final library = ref.watch(fontLibraryProvider);
    final isDefault = id.isEmpty || id == setting.defaultValue;
    final systemName = !kIsWeb && Platform.isWindows ? 'Microsoft YaHei' : i18n('font_system_default');
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => FutureBuilder<FontFamily?>(
        future: isDefault ? null : library.family(id),
        builder: (context, snapshot) {
          final name = isDefault ? systemName : (snapshot.data?.name ?? id);
          final missing = !isDefault && !library.isDownloaded(id);
          return SettingsLinkRow(
            key: entry.rowKey,
            icon: icon,
            title: entry.titleText,
            subtitle: missing ? i18n('settings_font_not_installed', args: {'name': name}) : entry.descriptionText,
            subtitleColor: missing ? Theme.of(context).colorScheme.error : null,
            value: name,
            onTap: () => openOrReveal(
              context,
              entry,
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FontManagerPage(danmaku: setting == Settings.danmakuFontFamilyName),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The five text sizes, each with an example in its size (3.x
/// `FontSettingsPage`; U.6b c15).
class FontSizesPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  static const List<(String, DoubleSetting, IconData, String, FontWeight)> _sizes = [
    ('font_body_small', Settings.fontSizeBodySmall, AppIcons.fontSizes, 'settings_font_sample_small', FontWeight.w400),
    ('font_body_medium', Settings.fontSizeBodyMedium, AppIcons.fontBody, 'change_language_subtitle', FontWeight.w400),
    ('font_body_large', Settings.fontSizeBodyLarge, AppIcons.fontBodyLarge, 'cross_axis_spacing', FontWeight.w600),
    (
      'font_title_medium',
      Settings.fontSizeTitleMedium,
      AppIcons.fontTitle,
      'settings_font_sample_title',
      FontWeight.w600,
    ),
    ('font_title_large', Settings.fontSizeTitleLarge, AppIcons.fontTitleLarge, 'font_settings_title', FontWeight.w600),
  ];

  Widget _slider(int index) {
    final (key, setting, icon, sample, weight) = _sizes[index];
    return SettingSliderTile(
      entry: subEntry(key, '${key}_title', description: '${key}_desc'),
      setting: setting,
      icon: icon,
      min: setting.min!,
      max: setting.max!,
      step: 1,
      format: (value) => '${value.round()}px',
      below: (context, value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          i18n(sample),
          key: ValueKey('settings-font-sample-$key'),
          style: TextStyle(
            fontSize: value,
            fontWeight: weight,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: settingsAppBar(
      context,
      title: i18n('font_settings_title'),
      embedded: SettingsPane.of(context),
      actions: [
        IconButton(
          key: const ValueKey('settings-font-sizes-reset'),
          tooltip: i18n('reset'),
          icon: const Icon(AppIcons.resetFontSizes),
          onPressed: () async {
            final confirmed = await showConfirmDialog(
              context: context,
              title: i18n('reset'),
              message: i18n('font_settings_reset_confirm'),
              confirmLabel: i18n('reset'),
              destructive: true,
            );
            if (!confirmed) return;
            final settings = ref.read(storeProvider).settings;
            for (final (_, setting, _, _, _) in _sizes) {
              await settings.reset(setting);
            }
            AppNavigator.toast(i18n('restore_default'));
          },
        ),
      ],
    ),
    body: SettingsPageBody(
      start: SettingsPane.of(context),
      children: [
        SettingsNote(i18n('settings_font_sizes_intro'), padding: const EdgeInsets.fromLTRB(4, 4, 4, 0)),
        SettingsGroup(title: i18n('body_typography_group'), children: [_slider(0), _slider(1), _slider(2)]),
        SettingsGroup(title: i18n('header_typography_group'), children: [_slider(3), _slider(4)]),
      ],
    ),
  );
}

/// The name of a loading style in the current language.
String loadingStyleName(String key) {
  final names = loadingStyleNames[key];
  if (names == null) return key;
  return currentStrings?.language == AppLanguage.en ? names.$2 : names.$1;
}

/// The loading animation: a still preview at the start of the row, the
/// style's name at the end, the gallery on a page.
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
    return SettingsLinkRow(
      key: entry.rowKey,
      // A still frame: an endless animation on every settings visit costs
      // battery; the gallery plays them.
      leading: TickerMode(
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
      value: loadingStyleName(style),
      onTap: () => openOrReveal(
        context,
        entry,
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LoadingStylePage())),
      ),
    );
  }
}

/// Every loading animation, playing, to pick from; and its colour (3.x
/// `LoadingStyleSettingsPage`; U.6b c11).
class LoadingStylePage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: i18n('settings_loading_restore_title'),
      message: i18n('settings_loading_restore_message'),
      confirmLabel: i18n('restore_default'),
    );
    if (!confirmed) return;
    final settings = ref.read(storeProvider).settings;
    await settings.reset(Settings.loadingStyle);
    await settings.reset(Settings.loadingStyleColorSwitch);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = LoadingStyles.normalize(watchSetting(ref, Settings.loadingStyle));
    final stored = watchSetting(ref, Settings.loadingStyleColorSwitch);
    final custom = parseColorHex(stored);
    final theme = Theme.of(context);
    final color = custom ?? theme.colorScheme.primary;
    final now = custom == null ? i18n('settings_color_follow_theme') : formatColorCode(custom, opacity: true);
    final start = SettingsPane.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return Scaffold(
      appBar: settingsAppBar(
        context,
        title: i18n('change_loading_style'),
        embedded: start,
        actions: [
          IconButton(
            key: const ValueKey('settings-loading-restore'),
            tooltip: i18n('restore_default'),
            icon: const Icon(AppIcons.restoreDefault),
            onPressed: () => unawaited(_restore(context, ref)),
          ),
        ],
      ),
      body: Align(
        alignment: start ? Alignment.topLeft : Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CustomScrollView(
            physics: const PureLiveScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(start ? 24 : 16, 8, start ? 24 : 16, 12),
                sliver: SliverToBoxAdapter(
                  child: SettingsGroup(
                    children: [
                      SettingsLinkRow(
                        key: const ValueKey('settings-loading-color'),
                        icon: AppIcons.themeColor,
                        title: i18n('change_loading_color'),
                        subtitle:
                            '${i18n('change_loading_color_subtitle')}\n${i18n('settings_loading_current', args: {'value': now})}',
                        valueWidget: SettingsSwatch(color),
                        onTap: () async {
                          final settings = ref.read(storeProvider).settings;
                          final picked = await showColorDialog(
                            context: context,
                            title: i18n('change_loading_color'),
                            current: color,
                            opacity: true,
                            onPreview: (preview) =>
                                unawaited(settings.set(Settings.loadingStyleColorSwitch, colorHex(preview))),
                          );
                          await settings.set(
                            Settings.loadingStyleColorSwitch,
                            picked == null ? stored : colorHex(picked),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(start ? 24 : 16, 0, start ? 24 : 16, 32),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    // Each cell at least 104 wide (more with large text),
                    // by the room this page has, not the screen (U.6b c11).
                    final minCell = 104 * (scale > 1.2 ? scale / 1.2 : 1);
                    final columns = ((constraints.crossAxisExtent + 8) / (minCell + 8)).floor().clamp(1, 8);
                    return SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 96 + 20 * scale,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: LoadingStyles.keys.length,
                      itemBuilder: (context, index) {
                        final key = LoadingStyles.keys[index];
                        return _LoadingCell(
                          styleKey: key,
                          selected: key == selected,
                          color: color,
                          onTap: () => writeSetting(ref, Settings.loadingStyle, key),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCell extends StatelessWidget {
  const new({required this.styleKey, required this.selected, required this.color, required this.onTap});

  final String styleKey;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('settings-loading-style-$styleKey'),
      color: selected
          ? Color.alphaBlend(colors.primaryContainer.withValues(alpha: 0.25), colors.surface)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: selected ? BorderSide(color: colors.primary, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Each animation repaints on its own; some (three dots)
                  // are wider than tall.
                  RepaintBoundary(
                    child: SizedBox(
                      width: 72,
                      height: 40,
                      child: Center(
                        child: LoadingStyles.build(styleKey, color: color, size: 36, colors: colors),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loadingStyleName(styleKey),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.t12.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? colors.primary : colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              PositionedDirectional(top: 6, end: 6, child: Icon(AppIcons.chosen, size: 20, color: colors.primary)),
          ],
        ),
      ),
    );
  }
}

/// Card appearance per screen kind, with a live preview (3.x
/// `RoomCardSettingsPage`; U.6b c12).
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

  Future<void> _reset() async {
    final target = i18n(_mobile ? 'settings_room_card_mobile' : 'settings_room_card_desktop');
    final confirmed = await showConfirmDialog(
      context: context,
      title: i18n('settings_room_card_reset_title'),
      message: i18n('settings_room_card_reset_message', args: {'target': target}),
      confirmLabel: i18n('reset'),
    );
    if (!confirmed) return;
    final settings = ref.read(storeProvider).settings;
    await settings.reset(_presetSetting);
    await settings.reset(_configSetting);
    AppNavigator.toast(i18n('settings_reset_done'));
  }

  @override
  Widget build(BuildContext context) {
    final appearance = _appearance(watchSetting(ref, _presetSetting), watchSetting(ref, _configSetting));
    final preset = RoomCardAppearance.presetOf(appearance);
    void update(RoomCardAppearance next) => unawaited(_store(next));
    final sample = RoomCardData(
      platformId: 'bilibili',
      title: 'Pure Live · ${i18n('room_card_preview_title')}',
      anchorName: i18n('room_card_preview_anchor'),
      isLive: true,
      audience: const RoomAudience(kind: RoomAudienceKind.popularity, value: '1.2万'),
    );
    return Scaffold(
      appBar: settingsAppBar(
        context,
        title: i18n('room_card_settings'),
        embedded: SettingsPane.of(context),
        actions: [
          IconButton(
            key: const ValueKey('settings-room-card-reset'),
            tooltip: i18n('room_card_reset_current'),
            icon: const Icon(AppIcons.resetLayout),
            onPressed: () => unawaited(_reset()),
          ),
        ],
      ),
      body: SettingsPageBody(
        start: SettingsPane.of(context),
        children: [
          SettingsGroup(
            first: true,
            card: false,
            title: i18n('room_card_target'),
            children: [
              SettingsChoiceChips<RoomCardViewport>(
                options: [
                  (
                    value: RoomCardViewport.mobile,
                    label: i18n('settings_room_card_mobile'),
                    key: const ValueKey('settings-room-card-mobile'),
                  ),
                  (
                    value: RoomCardViewport.desktop,
                    label: i18n('settings_room_card_desktop'),
                    key: const ValueKey('settings-room-card-desktop'),
                  ),
                ],
                selected: _viewport,
                onSelected: (value) => setState(() => _viewport = value),
              ),
            ],
          ),
          SettingsGroup(
            card: false,
            title: i18n('room_card_preview'),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth.clamp(0.0, 420.0);
                  // The card the lists show (U.4a's LiveRoomCard, U.1c c3).
                  final height = LiveRoomCardMetrics.extent(
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
                      child: LiveRoomCard(
                        key: const ValueKey('settings-room-card-preview'),
                        data: sample,
                        appearance: appearance,
                        dense: false,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          SettingsGroup(
            card: false,
            title: i18n('room_card_presets'),
            footer: i18n(
              preset == RoomCardPreset.custom ? 'settings_room_card_custom_now' : 'settings_room_card_preset_note',
            ),
            children: [
              SettingsChoiceChips<RoomCardPreset>(
                options: [
                  for (final (value, label) in [
                    (RoomCardPreset.compact, 'room_card_preset_compact'),
                    (RoomCardPreset.standard, 'room_card_preset_standard'),
                    (RoomCardPreset.detailed, 'room_card_preset_detailed'),
                  ])
                    (value: value, label: i18n(label), key: ValueKey('settings-room-card-preset-${value.name}')),
                ],
                selected: preset,
                onSelected: (value) => update(RoomCardAppearance.fromPreset(value)),
              ),
            ],
          ),
          SettingsGroup(
            title: i18n('room_card_visible_content'),
            children: [
              SettingsSwitchRow(
                key: const ValueKey('settings-room-card-avatar'),
                title: i18n('room_card_show_avatar'),
                subtitle: i18n('room_card_show_avatar_subtitle'),
                icon: AppIcons.cardAvatar,
                value: appearance.showAvatar,
                onChanged: (value) => update(appearance.copyWith(showAvatar: value)),
              ),
              SettingsSwitchRow(
                key: const ValueKey('settings-room-card-anchor'),
                title: i18n('room_card_show_anchor'),
                subtitle: i18n('room_card_show_anchor_subtitle'),
                icon: AppIcons.cardAnchor,
                value: appearance.showAnchorName,
                onChanged: (value) => update(appearance.copyWith(showAnchorName: value)),
              ),
              SettingsChipsRow<RoomCardPlatformBadgeMode>(
                key: const ValueKey('settings-room-card-platform'),
                title: i18n('room_card_show_platform'),
                subtitle: i18n('room_card_show_platform_subtitle'),
                icon: AppIcons.roomCardSettings,
                options: [
                  for (final (mode, label) in [
                    (RoomCardPlatformBadgeMode.automatic, 'room_card_platform_automatic'),
                    (RoomCardPlatformBadgeMode.always, 'room_card_platform_always'),
                    (RoomCardPlatformBadgeMode.hidden, 'room_card_platform_hidden'),
                  ])
                    (value: mode, label: i18n(label), key: ValueKey('settings-room-card-platform-${mode.name}')),
                ],
                selected: appearance.platformBadgeMode,
                onSelected: (value) => update(appearance.withPlatformBadgeMode(value)),
              ),
              SettingsSwitchRow(
                key: const ValueKey('settings-room-card-audience'),
                title: i18n('room_card_show_audience'),
                subtitle: i18n('room_card_show_audience_subtitle'),
                icon: AppIcons.cardAudience,
                value: appearance.showAudience,
                onChanged: (value) => update(appearance.copyWith(showAudience: value)),
              ),
              SettingsSwitchRow(
                key: const ValueKey('settings-room-card-replay'),
                title: i18n('room_card_show_replay'),
                subtitle: i18n('room_card_show_replay_subtitle'),
                icon: AppIcons.cardReplay,
                value: appearance.showReplayBadge,
                onChanged: (value) => update(appearance.copyWith(showReplayBadge: value)),
              ),
            ],
          ),
          SettingsGroup(
            title: i18n('room_card_appearance'),
            footer: i18n('room_card_settings_scope_hint'),
            children: [
              SettingsChipsRow<RoomCardLayout>(
                key: const ValueKey('settings-room-card-layout'),
                title: i18n('room_card_layout'),
                subtitle: i18n('room_card_layout_subtitle'),
                icon: AppIcons.cardLayout,
                options: [
                  (value: RoomCardLayout.cover, label: i18n('room_card_layout_cover'), key: null),
                  (value: RoomCardLayout.compact, label: i18n('room_card_layout_compact'), key: null),
                ],
                selected: appearance.layout,
                onSelected: (value) => update(appearance.copyWith(layout: value)),
              ),
              SettingsSliderRow(
                key: const ValueKey('settings-room-card-radius'),
                title: i18n('room_card_corner_radius'),
                subtitle: i18n('room_card_corner_radius_subtitle'),
                icon: AppIcons.cornerRadius,
                value: appearance.cornerRadius,
                min: RoomCardAppearance.minCornerRadius,
                max: RoomCardAppearance.maxCornerRadius,
                label: '${appearance.cornerRadius.round()}',
                onChanged: (value) => update(appearance.copyWith(cornerRadius: value.roundToDouble())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The recommended page sizes for a window [width] (3.x: 20/40/60/80 wider
/// than 960, else 12/24/36/48).
List<int> recommendedPageSizes(double width) => width > 960 ? const [20, 40, 60, 80] : const [12, 24, 36, 48];

/// The page-size choices of the pager (3.x's options dialog): chips to
/// remove, a field to add, "恢复推荐" to go back to the screen-width rule.
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
    final recommended = recommendedPageSizes(MediaQuery.sizeOf(context).width);
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: AppIcons.pageSizeOptions,
      title: entry.titleText,
      subtitle: (options.isEmpty ? recommended : options).join(', '),
      onTap: () async {
        final result = await showAppDialog<List<int>>(
          context: context,
          builder: (context) => _PageSizeDialog(initial: options, recommended: recommended),
        );
        if (result != null && context.mounted) {
          writeSetting(ref, Settings.pageSizeOptions, (List.of(result)..sort()).join(','));
        }
      },
    );
  }
}

class _PageSizeDialog extends StatefulWidget {
  const new({required this.initial, required this.recommended});

  final List<int> initial;
  final List<int> recommended;

  @override
  State<_PageSizeDialog> createState() => _PageSizeDialogState();
}

class _PageSizeDialogState extends State<_PageSizeDialog> {
  /// Empty means "recommended" (stored as an empty list).
  late List<int> _options = List.of(widget.initial);
  final _input = TextEditingController();
  String? _error;

  List<int> get _shown => _options.isEmpty ? widget.recommended : _options;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final value = int.tryParse(_input.text.trim());
    if (value == null || value < 1 || value > 100) {
      setState(() => _error = i18n('page_size_value_range'));
      return;
    }
    if (_shown.contains(value)) {
      setState(() => _error = i18n('page_size_value_duplicate'));
      return;
    }
    setState(() {
      _options = [..._shown, value]..sort();
      _input.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsDialogFrame(
      title: i18n('page_size_options_manage'),
      actions: [
        const DialogCancelButton(),
        DialogActionButton(
          key: const ValueKey('settings-page-sizes-save'),
          label: i18n('save'),
          onPressed: () => Navigator.of(context).pop(_options),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(i18n('current_options'), style: context.textStyles.t13)),
                TextButton.icon(
                  key: const ValueKey('settings-page-sizes-recommended'),
                  onPressed: () => setState(() => _options = []),
                  icon: const Icon(AppIcons.pageSizeRecommended, size: 18),
                  label: Text(i18n('settings_page_size_restore')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in _shown)
                  InputChip(
                    key: ValueKey('settings-page-size-$value'),
                    label: Text('$value'),
                    side: BorderSide(color: colors.outlineVariant),
                    // At least one stays (3.x).
                    onDeleted: _shown.length == 1 ? null : () => setState(() => _options = [..._shown]..remove(value)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('settings-page-size-input'),
                    controller: _input,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _add(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: dialogFieldDecoration(
                      context,
                      hint: i18n('settings_page_size_input'),
                      suffix: i18n('items_per_page'),
                      error: _error,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  key: const ValueKey('settings-page-size-add'),
                  onPressed: _add,
                  child: Text(i18n('add')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The bottom navigation bar's pages (3.x `NavigationSettingsPage`; U.6b
/// c14): shown ones first in their order with a switch and a handle to
/// drag, hidden ones last ("已隐藏", no handle); at least one stays.
class HomeMenusList extends ConsumerWidget {
  /// Creates the rows.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = HomeMenu.fromIds(watchSetting(ref, Settings.savedMenuIds));
    final order = [...shown, ...HomeMenu.values.where((menu) => !shown.contains(menu))];
    final colors = Theme.of(context).colorScheme;
    void save(List<HomeMenu> menus) => writeSetting(ref, Settings.savedMenuIds, [for (final menu in menus) menu.id]);
    void toggle(HomeMenu menu, {required bool on}) {
      if (!on && shown.length == 1) {
        AppNavigator.toast(i18n('at_least_one_menu_required'));
        return;
      }
      save([
        for (final item in order)
          if (item == menu ? on : shown.contains(item)) item,
      ]);
    }

    return KeyedSubtree(
      key: entry.rowKey,
      child: ReorderableListView(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        physics: const NeverScrollableScrollPhysics(),
        proxyDecorator: (child, _, _) => Material(color: colors.surfaceContainerHigh, elevation: 2, child: child),
        onReorderItem: (from, to) {
          final next = List.of(order);
          final moved = next.removeAt(from);
          next.insert(to.clamp(0, shown.length - (shown.contains(moved) ? 1 : 0)), moved);
          save([
            for (final menu in next)
              if (shown.contains(menu)) menu,
          ]);
        },
        children: [
          for (final (index, menu) in order.indexed)
            Column(
              key: ValueKey('settings-menu-${menu.id}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (index > 0)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 56),
                    child: Divider(height: 1, thickness: 1, color: colors.outlineVariant.withValues(alpha: 0.7)),
                  ),
                SettingsRow(
                  icon: menu.icon,
                  title: i18n(menu.titleKey),
                  subtitle: shown.contains(menu) ? null : i18n('settings_nav_hidden'),
                  stackTrailing: false,
                  onTap: () => toggle(menu, on: !shown.contains(menu)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeFocus(
                        child: IgnorePointer(
                          child: Switch(value: shown.contains(menu), onChanged: (_) {}),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: shown.contains(menu)
                            ? ReorderableDragStartListener(
                                index: index,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {},
                                  child: Tooltip(
                                    message: i18n('settings_nav_drag'),
                                    child: SizedBox(
                                      key: ValueKey('settings-menu-handle-${menu.id}'),
                                      height: 48,
                                      child: Icon(AppIcons.dragHandle, color: colors.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
