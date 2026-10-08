import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

// The rows of the danmaku settings (docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗) shared by the
// room's danmaku settings, its block list (U.2e c16: "行样式和弹幕设置组件统
// 一") and the settings page's block list (U.12d, choice E4).

/// A group title inside a panel: 13 points in the primary colour (U.2f),
/// with an optional note on the right ("改动立即生效", U.2e c8).
class PanelGroupTitle extends StatelessWidget {
  /// Creates the title.
  const new(this.text, {this.trailing, super.key});

  /// The words.
  final String text;

  /// A note on the right of the title.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(
      text,
      style: theme.textTheme.labelLarge?.emphasis.copyWith(
        fontSize: theme.textTheme.bodyMedium?.fontSize,
        color: theme.colorScheme.primary,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: trailing == null
          ? title
          : Row(
              children: [
                Expanded(child: title),
                Text(
                  trailing!,
                  key: const ValueKey('panel-group-note'),
                  style: theme.textTheme.bodyMedium?.regular.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
    );
  }
}

/// A rounded group of rows inside a panel.
class PanelCard extends StatelessWidget {
  /// Creates the card.
  const new({required this.children, super.key});

  /// The rows.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

TextStyle? _titleStyle(ThemeData theme, {required bool enabled}) => theme.textTheme.bodyLarge?.regular.copyWith(
  fontSize: theme.textTheme.titleMedium?.fontSize,
  color: enabled ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.38),
);

/// A row with a title (and a line under it) and a control on the right.
class SettingRow extends StatelessWidget {
  /// Creates the row; [settingKey] names its keys (`danmaku-setting-…`).
  const new({
    required this.settingKey,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.enabled = true,
    super.key,
  });

  /// The setting's name in the keys.
  final String settingKey;

  /// The title.
  final String title;

  /// The line under the title.
  final String? subtitle;

  /// The control.
  final Widget trailing;

  /// Greyed out when false.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: ValueKey('danmaku-setting-$settingKey'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle(theme, enabled: enabled)),
                if (subtitle case final text?)
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: enabled ? scheme.onSurfaceVariant : scheme.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// A switch row; the whole row switches (3.x's `SwitchListTile`); a null
/// [onChanged] greys it out.
class SettingSwitchRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.settingKey,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  /// The setting's name in the keys.
  final String settingKey;

  /// The title.
  final String title;

  /// The line under the title.
  final String? subtitle;

  /// On or off.
  final bool value;

  /// Switches; null greys it out.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: SettingRow(
        settingKey: settingKey,
        title: title,
        subtitle: subtitle,
        enabled: onChanged != null,
        trailing: Switch(key: ValueKey('danmaku-switch-$settingKey'), value: value, onChanged: onChanged),
      ),
    ),
  );
}

/// A title with its value on the right and a slider under it (3.x
/// `_slider`); a null [onChanged] greys it out.
class SettingSliderRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.settingKey,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
    super.key,
  });

  /// The setting's name in the keys.
  final String settingKey;

  /// The title.
  final String title;

  /// The value.
  final double value;

  /// The lowest value.
  final double min;

  /// The highest value.
  final double max;

  /// Steps, or null for any value.
  final int? divisions;

  /// The value as shown ("16.0 px").
  final String display;

  /// Changes the value; null greys it out.
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onChanged != null;
    return Padding(
      key: ValueKey('danmaku-setting-$settingKey'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Greyed out, a screen reader says it is unavailable too (A05.1).
          Semantics(
            container: true,
            enabled: enabled,
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: _titleStyle(theme, enabled: enabled)),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: enabled ? 0.1 : 0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Text(
                      display,
                      key: ValueKey('danmaku-value-$settingKey'),
                      style: theme.textTheme.labelMedium?.emphasis.tabular.copyWith(
                        color: enabled ? scheme.primary : scheme.onSurface.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Slider(
            key: ValueKey('danmaku-slider-$settingKey'),
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            semanticFormatterCallback: (_) => '$title, $display',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A title with a − value + stepper (3.x `_counter`, `CountButton`); a null
/// [onChanged] greys it out.
class SettingCounterRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.settingKey,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    super.key,
  });

  /// The setting's name in the keys.
  final String settingKey;

  /// The title.
  final String title;

  /// The value.
  final int value;

  /// The lowest value.
  final int min;

  /// The highest value.
  final int max;

  /// Changes the value; null greys it out.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    // The outlined counter (U.1c c10): greyed out, not hidden, when off.
    return SettingRow(
      settingKey: settingKey,
      title: title,
      enabled: enabled,
      trailing: IgnorePointer(
        ignoring: !enabled,
        child: CountButton(
          key: ValueKey('danmaku-counter-$settingKey'),
          minValue: min,
          maxValue: max,
          selectedValue: value,
          enabled: enabled,
          semanticLabel: title,
          decrementSemanticLabel: i18n('decrease_value', args: {'label': title}),
          incrementSemanticLabel: i18n('increase_value', args: {'label': title}),
          onChanged: (next) => onChanged?.call(next),
        ),
      ),
    );
  }
}
