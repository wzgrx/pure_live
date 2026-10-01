import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Stores [value] for [setting] (written in the background; the row
/// updates through the store's change stream).
void writeSetting<T extends Object>(WidgetRef ref, Setting<T> setting, T value) =>
    unawaited(ref.read(storeProvider).settings.set(setting, value));

/// A row that is greyed out and ignores taps while [enabled] is false
/// (options that only apply when another switch is on).
class SettingsDependent extends StatelessWidget {
  /// Wraps [child].
  const new({required this.enabled, required this.child, super.key});

  /// Whether the row can be used.
  final bool enabled;

  /// The row.
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: enabled ? 1 : 0.45,
    duration: const Duration(milliseconds: 150),
    child: IgnorePointer(ignoring: !enabled, child: child),
  );
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
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildSwitchTile(
        title: entry.titleText,
        subtitle: entry.descriptionText,
        isLong: true,
        icon: icon,
        value: inverted ? !stored : stored,
        enabled: enabled,
        onChanged: (value) {
          writeSetting(ref, setting, inverted ? !value : value);
          onChanged?.call(value);
        },
      ),
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

  /// The badge text of a value.
  final String Function(double value) format;

  /// A switch that must be on for this one to apply.
  final BoolSetting? enabledBy;

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
    return KeyedSubtree(
      key: widget.entry.rowKey,
      child: SettingsDependent(
        enabled: enabled,
        child: context.buildSliderTile(
          icon: widget.icon,
          title: widget.entry.titleText,
          subtitle: widget.entry.descriptionText,
          value: value,
          min: widget.min,
          max: widget.max,
          displayValue: widget.format(value),
          onChanged: (raw) {
            setState(() => _dragging = _snap(raw));
            _write?.cancel();
            _write = Timer(const Duration(milliseconds: 200), () {
              _flush();
              if (mounted) setState(() => _dragging = null);
            });
          },
        ),
      ),
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
    return KeyedSubtree(
      key: entry.rowKey,
      child: SettingsDependent(
        enabled: enabled,
        child: context.buildTile(
          icon: icon,
          title: entry.titleText,
          subtitle: subtitle ?? entry.descriptionText,
          isLong: true,
          stackTrailingOnNarrow: true,
          trailing: SettingValueText(current?.label ?? '$value'),
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
        ),
      ),
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
    return KeyedSubtree(
      key: entry.rowKey,
      child: SettingsDependent(
        enabled: enabled,
        child: context.buildTile(
          icon: icon,
          title: entry.titleText,
          subtitle: entry.descriptionText,
          isLong: true,
          stackTrailingOnNarrow: true,
          trailing: SettingValueText(label(value)),
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
        ),
      ),
    );
  }
}

/// The current value at the end of a row, in the primary colour.
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
        style: context.textStyles.t13.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A row that opens another page: a route of the app (accounts, block list)
/// or a settings sub-page.
class SettingLinkTile extends StatelessWidget {
  /// Creates the row; give [route] or [page].
  const new({required this.entry, required this.icon, this.route, this.page, this.trailing, super.key})
    : assert(route != null || page != null, 'a link needs a target');

  /// The entry drawn.
  final SettingsEntry entry;

  /// The icon.
  final IconData icon;

  /// The app route opened.
  final String? route;

  /// The settings sub-page opened.
  final WidgetBuilder? page;

  /// Shown before the chevron (the current value).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: entry.rowKey,
    child: context.buildTile(
      icon: icon,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      isLong: true,
      trailing: trailing == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: trailing!),
                Icon(Icons.chevron_right_rounded, color: Theme.of(context).hintColor.withValues(alpha: 0.4), size: 20),
              ],
            ),
      onTap: () {
        if (page case final page?) {
          Navigator.of(context).push(MaterialPageRoute<void>(builder: page));
        } else {
          unawaited(AppNavigator.toNamed<void>(route!));
        }
      },
    ),
  );
}

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

  /// The trailing widget when not busy.
  final Widget? trailing;

  /// Replaces the entry's explanation (a live status).
  final String? subtitle;

  /// Drawn in the error colour.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: icon,
        iconColor: destructive ? colors.error : null,
        title: entry.titleText,
        subtitle: subtitle ?? entry.descriptionText,
        isLong: true,
        trailing: busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : trailing ?? const SizedBox.shrink(),
        onTap: busy ? null : onTap,
      ),
    );
  }
}
