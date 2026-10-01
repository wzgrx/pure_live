import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_section_view.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Stores [value] for [setting] (written in the background; the row
/// updates through the store's change stream).
void writeSetting<T extends Object>(WidgetRef ref, Setting<T> setting, T value) =>
    unawaited(ref.read(storeProvider).settings.set(setting, value));

/// The search results: a row that opens another page goes to its own page
/// instead and is highlighted there (U.6a c8).
class SettingsReveal extends InheritedWidget {
  /// Provides [reveal] to the rows of [child].
  const new({required this.reveal, required super.child, super.key});

  /// Shows the page of an entry with the entry highlighted.
  final void Function(SettingsEntry entry) reveal;

  /// The reveal in scope (search results), or null.
  static SettingsReveal? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsReveal>();

  @override
  bool updateShouldNotify(SettingsReveal oldWidget) => oldWidget.reveal != reveal;
}

/// [open] for a row that opens a page; in search results its page instead.
void openOrReveal(BuildContext context, SettingsEntry entry, VoidCallback open) {
  final reveal = SettingsReveal.maybeOf(context);
  if (reveal != null && entry.opens) {
    reveal.reveal(entry);
  } else {
    open();
  }
}

/// A switch bound to [setting]; [inverted] shows the opposite (`hideDanmaku`
/// as "danmaku on the video").
class SettingToggleTile extends ConsumerWidget {
  /// Creates the row.
  const new({
    required this.entry,
    required this.setting,
    required this.icon,
    this.inverted = false,
    this.enabledBy,
    this.onChanged,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// The stored switch.
  final BoolSetting setting;

  /// The icon.
  final IconData icon;

  /// Shows and stores the opposite value.
  final bool inverted;

  /// A switch that must be on for this one to apply.
  final BoolSetting? enabledBy;

  /// Called after the new value is stored.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = watchSetting(ref, setting);
    final enabled = enabledBy == null || watchSetting(ref, enabledBy!);
    return SettingsSwitchRow(
      key: entry.rowKey,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      icon: icon,
      value: inverted ? !stored : stored,
      enabled: enabled,
      onChanged: (value) {
        writeSetting(ref, setting, inverted ? !value : value);
        onChanged?.call(value);
      },
    );
  }
}

/// A slider bound to a number setting. The value follows the finger at once
/// and is stored 200 ms after the last move (3.x wrote on every frame of a
/// drag).
class SettingSliderTile extends ConsumerStatefulWidget {
  /// Creates the row.
  const new({
    required this.entry,
    required this.setting,
    required this.icon,
    required this.min,
    required this.max,
    required this.format,
    this.step,
    this.enabledBy,
    this.marks = const [],
    this.below,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// A [DoubleSetting] or [IntSetting].
  final Setting<Object> setting;

  /// The icon.
  final IconData icon;

  /// The slider's range.
  final double min;

  /// The slider's range.
  final double max;

  /// Values snap to multiples of this; null keeps any value (whole numbers
  /// for an [IntSetting]).
  final double? step;

  /// The pill's text of a value.
  final String Function(double value) format;

  /// A switch that must be on for this one to apply.
  final BoolSetting? enabledBy;

  /// Values marked on the track.
  final List<double> marks;

  /// Shown under the slider for the value shown (an example).
  final Widget Function(BuildContext context, double value)? below;

  @override
  ConsumerState<SettingSliderTile> createState() => _SettingSliderTileState();
}

class _SettingSliderTileState extends ConsumerState<SettingSliderTile> {
  double? _dragging;
  Timer? _write;

  @override
  void dispose() {
    _flush();
    super.dispose();
  }

  double _snap(double value) {
    final step = widget.step ?? (widget.setting is IntSetting ? 1 : null);
    if (step == null) return value;
    return double.parse(((value / step).round() * step).toStringAsFixed(4));
  }

  void _flush() {
    final pending = _write;
    final value = _dragging;
    if (pending == null || value == null) return;
    pending.cancel();
    _write = null;
    final settings = ref.read(storeProvider).settings;
    switch (widget.setting) {
      case final IntSetting setting:
        unawaited(settings.set(setting, value.round()));
      case final DoubleSetting setting:
        unawaited(settings.set(setting, value));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stored = switch (watchSetting(ref, widget.setting)) {
      final num value => value.toDouble(),
      _ => widget.min,
    };
    final value = _dragging ?? stored;
    final enabled = widget.enabledBy == null || watchSetting(ref, widget.enabledBy!);
    return SettingsSliderRow(
      key: widget.entry.rowKey,
      icon: widget.icon,
      title: widget.entry.titleText,
      subtitle: widget.entry.descriptionText,
      value: value,
      min: widget.min,
      max: widget.max,
      marks: widget.marks,
      enabled: enabled,
      label: widget.format(value),
      below: widget.below?.call(context, value),
      onChanged: (raw) {
        setState(() => _dragging = _snap(raw));
        _write?.cancel();
        _write = Timer(const Duration(milliseconds: 200), () {
          _flush();
          if (mounted) setState(() => _dragging = null);
        });
      },
    );
  }
}

/// A row that shows the current choice and opens [showChoiceDialog].
class SettingChoiceTile<T extends Object> extends ConsumerWidget {
  /// Creates the row.
  const new({
    required this.entry,
    required this.setting,
    required this.icon,
    required this.options,
    this.hint,
    this.enabledBy,
    this.subtitle,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// The line under the title; the entry's description when null.
  final String? subtitle;

  /// The stored choice.
  final Setting<T> setting;

  /// The icon.
  final IconData icon;

  /// The options (built when drawn, so labels follow the language).
  final List<SettingsChoice<T>> Function() options;

  /// A line above the options.
  final String? hint;

  /// A switch that must be on for this one to apply.
  final BoolSetting? enabledBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = watchSetting(ref, setting);
    final choices = options();
    final current = choices.where((choice) => choice.value == value).firstOrNull;
    final enabled = enabledBy == null || watchSetting(ref, enabledBy!);
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: icon,
      title: entry.titleText,
      subtitle: subtitle ?? entry.descriptionText,
      value: current?.label ?? '$value',
      enabled: enabled,
      onTap: () async {
        final picked = await showChoiceDialog<T>(
          context: context,
          title: entry.titleText,
          options: choices,
          selected: value,
          hint: hint,
        );
        if (picked != null && context.mounted) writeSetting(ref, setting, picked);
      },
    );
  }
}

/// A row that shows a whole number and opens [showNumberDialog].
class SettingNumberTile extends ConsumerWidget {
  /// Creates the row.
  const new({
    required this.entry,
    required this.setting,
    required this.icon,
    required this.presets,
    required this.label,
    this.unit,
    this.hint,
    this.enabledBy,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// The stored number (its `min`/`max` bound the custom value).
  final IntSetting setting;

  /// The icon.
  final IconData icon;

  /// Quick picks.
  final List<int> presets;

  /// How a value reads.
  final String Function(int value) label;

  /// The custom field's unit.
  final String? unit;

  /// A line above the quick picks.
  final String? hint;

  /// A switch that must be on for this one to apply.
  final BoolSetting? enabledBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = watchSetting(ref, setting);
    final enabled = enabledBy == null || watchSetting(ref, enabledBy!);
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: icon,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      value: label(value),
      enabled: enabled,
      onTap: () async {
        final picked = await showNumberDialog(
          context: context,
          title: entry.titleText,
          current: value,
          presets: presets,
          min: setting.min ?? 0,
          max: setting.max ?? 99999,
          label: label,
          unit: unit,
          hint: hint ?? entry.descriptionText,
        );
        if (picked != null && context.mounted) writeSetting(ref, setting, picked);
      },
    );
  }
}

/// The current value at the end of a row, in the secondary text colour
/// (rows that draw their own end, such as the proxy and refresh rate).
class SettingValueText extends StatelessWidget {
  /// Creates the text.
  const new(this.text, {super.key});

  /// The value.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: context.textStyles.t14.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// A row that opens another page: a route of the app (accounts, block list)
/// or a settings page.
class SettingLinkTile extends StatelessWidget {
  /// Creates the row; give [route], [page] or [subpage].
  const new({required this.entry, required this.icon, this.route, this.page, this.subpage, this.value, super.key})
    : assert(route != null || page != null || subpage != null, 'a link needs a target');

  /// The entry drawn.
  final SettingsEntry entry;

  /// The icon.
  final IconData icon;

  /// The app route opened.
  final String? route;

  /// The settings sub-page opened.
  final WidgetBuilder? page;

  /// A sub-page of the catalogue opened ([SettingsSubpagePage]).
  final SettingsSubpage? subpage;

  /// The current value before the chevron.
  final String? value;

  @override
  Widget build(BuildContext context) => SettingsLinkRow(
    key: entry.rowKey,
    icon: icon,
    title: entry.titleText,
    subtitle: entry.descriptionText,
    value: value,
    onTap: () => openOrReveal(context, entry, () {
      if (subpage case final subpage?) {
        unawaited(openSettingsSubpage(context, subpage));
      } else if (page case final page?) {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: page));
      } else {
        unawaited(AppNavigator.toNamed<void>(route!));
      }
    }),
  );
}

/// Opens [subpage], with the row [highlight] (an entry id) highlighted.
Future<void> openSettingsSubpage(BuildContext context, SettingsSubpage subpage, {String? highlight}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsSubpagePage(subpage: subpage, highlight: highlight),
      ),
    );

/// A row that runs [onTap] (clear the cache, reset), with a spinner while
/// [busy].
class SettingActionTile extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.entry,
    required this.icon,
    required this.onTap,
    this.busy = false,
    this.trailing,
    this.subtitle,
    this.destructive = false,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// The icon.
  final IconData icon;

  /// The action; null disables the row.
  final VoidCallback? onTap;

  /// Shows a spinner and ignores taps.
  final bool busy;

  /// The end of the row when not busy (a button).
  final Widget? trailing;

  /// Replaces the entry's explanation (a live status).
  final String? subtitle;

  /// Drawn in the error colour.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsRow(
      key: entry.rowKey,
      leading: destructive ? Icon(icon, size: 22, color: colors.error) : null,
      icon: icon,
      title: entry.titleText,
      subtitle: subtitle ?? entry.descriptionText,
      trailing: trailing,
      busy: busy,
      enabled: onTap != null || busy,
      onTap: onTap,
    );
  }
}

/// 3.x's row builders (`buildTile`, `buildSwitchTile`) drawn with the shared
/// settings row, for the rows that draw their own end (proxy, window size,
/// refresh rate, folders).
extension SettingsRowBuilders on BuildContext {
  /// A row: icon, title, explanation, [trailing] (a chevron when there is
  /// none and the row opens something).
  Widget settingsTile({
    required String title,
    Key? key,
    IconData? icon,
    Widget? iconWidget,
    String? subtitle,
    Color? subtitleColor,
    Widget? trailing,
    VoidCallback? onTap,
    bool busy = false,
    bool enabled = true,
  }) => SettingsRow(
    key: key,
    title: title,
    icon: icon,
    leading: iconWidget,
    subtitle: subtitle,
    subtitleColor: subtitleColor,
    busy: busy,
    enabled: enabled,
    trailing:
        trailing ??
        (onTap == null
            ? null
            : Icon(Icons.chevron_right_rounded, size: 22, color: Theme.of(this).colorScheme.onSurfaceVariant)),
    onTap: onTap,
  );

  /// A switch row.
  Widget settingsSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
    Key? key,
    IconData? icon,
    String? subtitle,
    Color? subtitleColor,
    bool enabled = true,
    bool busy = false,
  }) => SettingsSwitchRow(
    key: key,
    title: title,
    value: value,
    onChanged: onChanged,
    icon: icon,
    subtitle: subtitle,
    subtitleColor: subtitleColor,
    enabled: enabled,
    busy: busy,
  );
}

/// The app bar of the settings pages: the title centred on phones (3.x
/// `MyTheme`), at the start in the wide layout's right pane; a compact
/// height when the window is short (a phone held sideways).
PreferredSizeWidget settingsAppBar(
  BuildContext context, {
  required String title,
  List<Widget> actions = const [],
  Widget? leading,
  bool embedded = false,
}) {
  final short = MediaQuery.sizeOf(context).height < 480;
  return AppBar(
    title: Text(
      title,
      style: context.textStyles.t18.copyWith(fontSize: embedded ? 18 : 20, fontWeight: FontWeight.w600),
    ),
    centerTitle: !embedded,
    leading: leading,
    automaticallyImplyLeading: leading == null,
    toolbarHeight: short ? 48 : kToolbarHeight,
    scrolledUnderElevation: 0,
    actions: [...actions, if (actions.isNotEmpty) const SizedBox(width: 4)],
  );
}

/// The body of a settings page: at most 720 wide, centred (the right pane
/// keeps it at the start); [children] are groups.
class SettingsPageBody extends StatelessWidget {
  /// Creates the body.
  const new({required this.children, this.controller, this.start = false, super.key});

  /// The groups and notes.
  final List<Widget> children;

  /// The scroll position.
  final ScrollController? controller;

  /// Keeps the content at the start (the right pane) instead of centring it.
  final bool start;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    physics: const PureLiveScrollPhysics(),
    padding: EdgeInsets.fromLTRB(start ? 24 : 16, 0, start ? 24 : 16, 32),
    child: Align(
      alignment: start ? Alignment.topLeft : Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ),
  );
}

/// Shows a page's title as the right pane's heading: the pages read it to
/// lay out their body at the start (U.6a c9).
class SettingsPane extends InheritedWidget {
  /// Marks [child] as inside the right pane.
  const new({required super.child, super.key});

  /// Whether [context] is inside the wide layout's right pane.
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsPane>() != null;

  @override
  bool updateShouldNotify(SettingsPane oldWidget) => false;
}

/// The words of the counter buttons.
String get settingsDecrease => i18n('settings_decrease');

/// The words of the counter buttons.
String get settingsIncrease => i18n('settings_increase');
