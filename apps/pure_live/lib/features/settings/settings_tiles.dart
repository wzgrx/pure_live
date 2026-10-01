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

/// A condition for a row to apply (U.6c c5): `setting` must be `value`;
/// otherwise the row is greyed out and `reason` replaces its explanation
/// ("打开“自定义驱动与硬件加速”后生效").
typedef SettingRequirement = ({BoolSetting setting, bool value, String reason});

/// "打开“[titleKey]”后生效": [setting] must be on.
SettingRequirement needsOn(BoolSetting setting, String titleKey) =>
    (setting: setting, value: true, reason: i18n('settings_needs_on', args: {'name': i18n(titleKey)}));

/// "关闭“[titleKey]”后可选": [setting] must be off.
SettingRequirement needsOff(BoolSetting setting, String titleKey) =>
    (setting: setting, value: false, reason: i18n('settings_needs_off', args: {'name': i18n(titleKey)}));

/// Why the row cannot be used now: the reason of the first unmet
/// requirement (watched, so the row follows), '' when [enabledBy] is off,
/// or null when it can be used.
String? watchUnmet(WidgetRef ref, Iterable<SettingRequirement> requires, {BoolSetting? enabledBy}) {
  String? unmet;
  if (enabledBy != null && !watchSetting(ref, enabledBy)) unmet = '';
  for (final requirement in requires) {
    if (watchSetting(ref, requirement.setting) != requirement.value) unmet ??= requirement.reason;
  }
  return unmet;
}

/// The reason to show for [unmet] (none for an empty one).
String? unmetReason(String? unmet) => unmet == null || unmet.isEmpty ? null : unmet;

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
    this.requires = const [],
    this.onChanged,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// The stored switch.
  final BoolSetting setting;

  /// The icon; none in rows that had none in 3.x.
  final IconData? icon;

  /// Conditions for it to apply.
  final List<SettingRequirement> requires;

  /// Shows and stores the opposite value.
  final bool inverted;

  /// A switch that must be on for this one to apply.
  final BoolSetting? enabledBy;

  /// Called after the new value is stored.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = watchSetting(ref, setting);
    final unmet = watchUnmet(ref, requires, enabledBy: enabledBy);
    return SettingsSwitchRow(
      key: entry.rowKey,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      icon: icon,
      value: inverted ? !stored : stored,
      enabled: unmet == null,
      disabledReason: unmetReason(unmet),
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
    this.requires = const [],
    this.marks = const [],
    this.below,
    this.shown,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// A [DoubleSetting] or [IntSetting].
  final Setting<Object> setting;

  /// The icon; none in rows that had none in 3.x.
  final IconData? icon;

  /// Conditions for it to apply.
  final List<SettingRequirement> requires;

  /// The value shown while the row cannot be used (the frame rate the
  /// automatic policy picks); null shows the stored one.
  final double? shown;

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
    final unmet = watchUnmet(ref, widget.requires, enabledBy: widget.enabledBy);
    final enabled = unmet == null;
    final value = _dragging ?? (enabled ? null : widget.shown) ?? stored;
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
      disabledReason: unmetReason(unmet),
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
    this.requires = const [],
    this.subtitle,
    this.valueBelow = false,
    this.leadingOf,
    this.valueText,
    this.valueWidget,
    this.action,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// The line under the title; the entry's description when null.
  final String? subtitle;

  /// The stored choice.
  final Setting<T> setting;

  /// The icon.
  final IconData? icon;

  /// Conditions for it to apply.
  final List<SettingRequirement> requires;

  /// Shows the current value under the explanation (long values, U.6c c6).
  final bool valueBelow;

  /// A picture before each option (platform logos).
  final Widget? Function(T value)? leadingOf;

  /// The row's value for the current option; its label when null.
  final String Function(SettingsChoice<T>? current, T value)? valueText;

  /// A picture before the row's value (the platform's logo).
  final Widget? Function(T value)? valueWidget;

  /// A button at the bottom start of the dialog ("重新检测").
  final SettingsDialogAction? action;

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
    final unmet = watchUnmet(ref, requires, enabledBy: enabledBy);
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: icon,
      title: entry.titleText,
      subtitle: subtitle ?? entry.descriptionText,
      value: valueText?.call(current, value) ?? current?.label ?? '$value',
      valueWidget: valueWidget?.call(value),
      valueBelow: valueBelow,
      enabled: unmet == null,
      disabledReason: unmetReason(unmet),
      onTap: () async {
        final picked = await showChoiceDialog<T>(
          context: context,
          title: entry.titleText,
          options: choices,
          selected: value,
          hint: hint,
          leadingOf: leadingOf,
          action: action,
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
    this.requires = const [],
    this.inputLabel,
    this.rangeText,
    this.subtitle,
    super.key,
  });

  /// The line under the title; the entry's description when null (the
  /// time left of the exit countdown).
  final String? subtitle;

  /// The entry drawn.
  final SettingsEntry entry;

  /// The stored number (its `min`/`max` bound the custom value).
  final IntSetting setting;

  /// The icon.
  final IconData icon;

  /// Conditions for it to apply.
  final List<SettingRequirement> requires;

  /// The custom field's label ("自定义时长").
  final String? inputLabel;

  /// The allowed range in words ("输入 1～525600 分钟").
  final String? rangeText;

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
    final unmet = watchUnmet(ref, requires, enabledBy: enabledBy);
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: icon,
      title: entry.titleText,
      subtitle: subtitle ?? entry.descriptionText,
      value: label(value),
      enabled: unmet == null,
      disabledReason: unmetReason(unmet),
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
          inputLabel: inputLabel,
          rangeText: rangeText,
        );
        if (picked != null && context.mounted) writeSetting(ref, setting, picked);
      },
    );
  }
}

/// A whole number changed one step at a time (− and +, held to repeat; a
/// tap on the number types it): the parallel refresh tasks, the mini
/// windows' danmaku count (U.6d d12, U.6c).
class SettingCounterTile extends ConsumerWidget {
  /// Creates the row.
  const new({
    required this.entry,
    required this.setting,
    required this.min,
    required this.max,
    this.icon,
    this.requires = const [],
    this.label,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// The stored number.
  final IntSetting setting;

  /// The range.
  final int min;

  /// The range.
  final int max;

  /// The icon.
  final IconData? icon;

  /// Conditions for it to apply.
  final List<SettingRequirement> requires;

  /// How a value reads; the number when null.
  final String Function(int value)? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = watchSetting(ref, setting).clamp(min, max);
    final unmet = watchUnmet(ref, requires);
    final settings = ref.read(storeProvider).settings;
    // A held button repeats: read the stored value on every step, not the
    // one this row was built with.
    void step(int delta) => unawaited(settings.set(setting, (settings.get(setting) + delta).clamp(min, max)));
    return SettingsCounterRow(
      key: entry.rowKey,
      icon: icon,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      value: label?.call(value) ?? '$value',
      enabled: unmet == null,
      disabledReason: unmetReason(unmet),
      decreaseTooltip: settingsDecrease,
      increaseTooltip: settingsIncrease,
      valueKey: ValueKey('${entry.rowKey.value}-value'),
      decreaseKey: ValueKey('${entry.rowKey.value}-decrease'),
      increaseKey: ValueKey('${entry.rowKey.value}-increase'),
      onDecrease: value > min ? () => step(-1) : null,
      onIncrease: value < max ? () => step(1) : null,
      onValueTap: () async {
        final picked = await showNumberDialog(
          context: context,
          title: entry.titleText,
          current: value,
          presets: const [],
          min: min,
          max: max,
          label: (value) => '$value',
        );
        if (picked != null && context.mounted) writeSetting(ref, setting, picked.clamp(min, max));
      },
    );
  }
}

/// A row that opens another page: a route of the app (accounts, block list)
/// or a settings page.
class SettingLinkTile extends ConsumerWidget {
  /// Creates the row; give [route], [page] or [subpage].
  const new({
    required this.entry,
    required this.icon,
    this.route,
    this.page,
    this.subpage,
    this.value,
    this.requires = const [],
    super.key,
  }) : assert(route != null || page != null || subpage != null, 'a link needs a target');

  /// Conditions for it to apply.
  final List<SettingRequirement> requires;

  /// The entry drawn.
  final SettingsEntry entry;

  /// The icon.
  final IconData? icon;

  /// The app route opened.
  final String? route;

  /// The settings sub-page opened.
  final WidgetBuilder? page;

  /// A sub-page of the catalogue opened ([SettingsSubpagePage]).
  final SettingsSubpage? subpage;

  /// The current value before the chevron.
  final String? value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unmet = watchUnmet(ref, requires);
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: icon,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      value: value,
      enabled: unmet == null,
      disabledReason: unmetReason(unmet),
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
    this.disabledReason,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// The icon.
  final IconData? icon;

  /// Why the row cannot be used while [onTap] is null.
  final String? disabledReason;

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
      icon: icon,
      titleColor: destructive ? colors.error : null,
      title: entry.titleText,
      subtitle: subtitle ?? entry.descriptionText,
      trailing: trailing,
      busy: busy,
      busyColor: destructive ? colors.error : null,
      enabled: onTap != null || busy,
      disabledReason: disabledReason,
      onTap: onTap,
    );
  }
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
