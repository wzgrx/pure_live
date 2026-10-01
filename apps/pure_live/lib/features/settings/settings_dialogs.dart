import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// One option of [showChoiceDialog].
typedef SettingsChoice<T> = ({T value, String label, String? description});

/// A button at the bottom start of a dialog that does something without
/// closing it ("重新检测").
typedef SettingsDialogAction = ({String label, VoidCallback onPressed, Key? key});

/// The dialog frame of the settings: at most 420 wide, scrolls when the
/// screen is short, tighter margins on narrow or large-text screens (3.x
/// `ThemeChoiceDialog`); 24 px corners like every other dialog (3.x used 16
/// here, U.6b Q14).
class SettingsDialogFrame extends StatelessWidget {
  /// Creates the frame.
  const new({required this.title, required this.child, this.actions = const [], this.leadingAction, super.key});

  /// The title.
  final String title;

  /// The content.
  final Widget child;

  /// Buttons under the content.
  final List<Widget> actions;

  /// A button at the bottom start ("重新检测").
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 420 || media.textScaler.scale(13) > 18;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: compact ? 12 : 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: media.size.height - 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 20 : 24, 20, compact ? 20 : 24, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                child: child,
              ),
            ),
            if (actions.isNotEmpty || leadingAction != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    ?leadingAction,
                    Expanded(
                      child: OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: actions),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// One option of a choice dialog: an optional picture, the label, a line of
/// explanation; the current one in the primary colour with a tick (UI_PLAN
/// §7, U.6c c7). A tap picks it.
class SettingsChoiceRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.description,
    this.leading,
    super.key,
  });

  /// The option's name.
  final String label;

  /// Its explanation.
  final String? description;

  /// A picture before the name (a platform's logo).
  final Widget? leading;

  /// Whether it is the current option.
  final bool selected;

  /// Picks it.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (leading case final leading?) ...[leading, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: base.copyWith(
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? colors.primary : colors.onSurface,
                        ),
                      ),
                      if (description case final description?)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            description,
                            style: base.copyWith(fontSize: 12, height: 1.45, color: colors.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 24, child: selected ? Icon(AppIcons.selected, size: 22, color: colors.primary) : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single-choice list; picking an option closes it with that value (3.x
/// `ThemeChoiceDialog`, plus a line of explanation per option); the current
/// one in the primary colour with a tick (U.6c c7). "取消", a tap outside,
/// back or Esc close it unchanged. Without [showCancel] (theme mode,
/// language: 3.x had no buttons) there is no button. [action] adds a button
/// at the bottom start that keeps the dialog open ("重新检测").
Future<T?> showChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required List<SettingsChoice<T>> options,
  required T selected,
  String? hint,
  bool showCancel = true,
  Widget? Function(T value)? leadingOf,
  SettingsDialogAction? action,
}) => showDialog<T>(
  context: context,
  builder: (context) => SettingsDialogFrame(
    title: title,
    leadingAction: action == null
        ? null
        : TextButton(key: action.key, onPressed: action.onPressed, child: Text(action.label)),
    actions: [if (showCancel) TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel')))],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              hint,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        for (final option in options)
          SettingsChoiceRow(
            key: ValueKey('settings-choice-${option.value}'),
            label: option.label,
            description: option.description,
            leading: leadingOf?.call(option.value),
            selected: option.value == selected,
            onTap: () => Navigator.of(context).pop(option.value),
          ),
      ],
    ),
  ),
);

/// A yes/no question; true when confirmed.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(i18n('cancel'))),
          FilledButton(
            key: const ValueKey('settings-confirm'),
            style: destructive ? FilledButton.styleFrom(backgroundColor: colors.error) : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// A whole number: quick picks plus a checked custom value (3.x's refresh
/// interval, countdown and sleep timer dialogs, which each had their own
/// copy). Returns null when cancelled.
Future<int?> showNumberDialog({
  required BuildContext context,
  required String title,
  required int current,
  required List<int> presets,
  required int min,
  required int max,
  required String Function(int value) label,
  String? hint,
  String? unit,
  String? inputLabel,
  String? rangeText,
}) => showDialog<int>(
  context: context,
  builder: (context) => _NumberDialog(
    title: title,
    current: current,
    presets: presets,
    min: min,
    max: max,
    label: label,
    hint: hint,
    unit: unit,
    inputLabel: inputLabel,
    rangeText: rangeText,
  ),
);

class _NumberDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.current,
    required this.presets,
    required this.min,
    required this.max,
    required this.label,
    required this.hint,
    required this.unit,
    required this.inputLabel,
    required this.rangeText,
  });

  final String title;
  final int current;
  final List<int> presets;
  final int min;
  final int max;
  final String Function(int value) label;
  final String? hint;
  final String? unit;
  final String? inputLabel;
  final String? rangeText;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  // The current value is in the field (U.6c 对话框 2), so typing starts
  // from it.
  late final TextEditingController _input = TextEditingController(text: '${widget.current}');
  String? _error;

  String get _range =>
      widget.rangeText ?? i18n('settings_number_range', args: {'min': '${widget.min}', 'max': '${widget.max}'});

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    final value = int.tryParse(_input.text.trim());
    if (value == null || value < widget.min || value > widget.max) {
      setState(() => _error = _range);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsDialogFrame(
      title: widget.title,
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
        FilledButton(key: const ValueKey('settings-number-save'), onPressed: _save, child: Text(i18n('save'))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.hint case final hint?) ...[
              Text(
                hint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.presets.isNotEmpty) ...[
              // A quick pick takes effect at once and closes (U.6d Y2).
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in widget.presets)
                    ChoiceChip(
                      key: ValueKey('settings-number-$value'),
                      label: Text(widget.label(value)),
                      selected: value == widget.current,
                      showCheckmark: false,
                      selectedColor: colors.primaryContainer,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                      onSelected: (_) => Navigator.of(context).pop(value),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              key: const ValueKey('settings-number-input'),
              controller: _input,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: widget.inputLabel ?? i18n('settings_custom_value'),
                suffixText: widget.unit,
                helperText: _range,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `AARRGGBB` of [color] (3.x stored colours as this hex).
String colorHex(Color color) => color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

/// The colour of `RRGGBB` or `AARRGGBB` (an optional `#`), or null.
Color? parseColorHex(String text) {
  var hex = text.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(value);
}

/// The colour picker dialog of the theme, loading and floating-window
/// danmaku colours (3.x `showAppColorPickerDialog`; U.6b c10): tabs
/// "推荐 / 常用色 / 鲜艳色 / 调色盘", shades, the code, with [opacity] an
/// alpha slider. [onPreview] gets every change (the page behind follows);
/// returns the colour on "确定", null when cancelled.
Future<Color?> showColorDialog({
  required BuildContext context,
  required String title,
  required Color current,
  bool opacity = false,
  ValueChanged<Color>? onPreview,
}) {
  final picker = GlobalKey<LiveColorPickerState>();
  return showDialog<Color>(
    context: context,
    builder: (context) => SettingsDialogFrame(
      title: title,
      actions: [
        TextButton(
          key: const ValueKey('settings-color-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n('cancel')),
        ),
        FilledButton(
          key: const ValueKey('settings-color-apply'),
          onPressed: () {
            final color = picker.currentState?.commit();
            if (color != null) Navigator.of(context).pop(color);
          },
          child: Text(i18n('exit_yes')),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: LiveColorPicker(
          key: picker,
          color: current,
          opacity: opacity,
          onChanged: (color) => onPreview?.call(color),
          labels: LiveColorPickerLabels(
            recommended: i18n('settings_color_recommended'),
            primary: i18n('settings_color_primary'),
            accent: i18n('settings_color_accent'),
            wheel: i18n('settings_color_wheel'),
            shades: i18n('select_color_shade'),
            opacity: i18n('select_opacity'),
            code: i18n(opacity ? 'argb_color_code' : 'rgb_color_code'),
            invalidCode: i18n('invalid_color_code'),
          ),
        ),
      ),
    ),
  );
}
