import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// One option of [showChoiceDialog].
typedef SettingsChoice<T> = ({T value, String label, String? description});

/// A button at the bottom start of a dialog that does something without
/// closing it ("重新检测").
typedef SettingsDialogAction = ({String label, VoidCallback onPressed, Key? key});

/// The dialog frame of the settings: the one dialog of the app (live_ui
/// [AppDialog], docs/ui/compare/U.1d: the screen less 32 and at most 400
/// wide, the title and buttons fixed while the middle scrolls); the content
/// sits 12 in from the dialog's sides and adds its own 12 (3.x
/// `ThemeChoiceDialog`).
class SettingsDialogFrame extends StatelessWidget {
  /// Creates the frame.
  const new({
    required this.title,
    required this.child,
    this.actions = const [],
    this.leadingAction,
    this.onEnter,
    this.autofocus = true,
    super.key,
  });

  /// The title.
  final String title;

  /// The content.
  final Widget child;

  /// Buttons under the content.
  final List<Widget> actions;

  /// A button at the bottom start ("重新检测").
  final Widget? leadingAction;

  /// The main button's action for Enter.
  final VoidCallback? onEnter;

  /// Whether the dialog takes the focus (off when a field inside does).
  final bool autofocus;

  @override
  Widget build(BuildContext context) => AppDialog(
    title: title,
    content: child,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    leading: leadingAction,
    actions: actions,
    onEnter: onEnter,
    autofocus: autofocus,
  );
}

/// One option of a choice dialog: an optional picture, the label, a line of
/// explanation; the current one in the primary colour with a tick (UI_PLAN
/// §7, U.6c c7). A tap picks it. The shared [DialogOptionRow] inside the
/// 12 of [SettingsDialogFrame].
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
  Widget build(BuildContext context) => DialogOptionRow(
    label: label,
    description: description,
    leading: leading,
    selected: selected,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  );
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
}) => showAppOptionDialog<T>(
  context: context,
  title: title,
  message: hint,
  selected: selected,
  showCancel: showCancel,
  leading: action == null ? null : TextButton(key: action.key, onPressed: action.onPressed, child: Text(action.label)),
  options: [
    for (final option in options)
      AppDialogOption(
        key: ValueKey('settings-choice-${option.value}'),
        value: option.value,
        label: option.label,
        description: option.description,
        leading: leadingOf?.call(option.value),
      ),
  ],
);

/// A yes/no question; true when confirmed. The button says what it does
/// ([confirmLabel]), red when [destructive] (U.1d c6).
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) => showAppConfirmDialog(
  context: context,
  title: title,
  message: message,
  confirmLabel: confirmLabel,
  danger: destructive,
  confirmKey: const ValueKey('settings-confirm'),
);

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
}) => showAppDialog<int>(
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
      autofocus: false,
      actions: [
        const DialogCancelButton(),
        DialogActionButton(key: const ValueKey('settings-number-save'), label: i18n('save'), onPressed: _save),
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
              decoration: dialogFieldDecoration(
                context,
                label: widget.inputLabel ?? i18n('settings_custom_value'),
                suffix: widget.unit,
                helper: _range,
                error: _error,
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
  return showAppDialog<Color>(
    context: context,
    builder: (context) => SettingsDialogFrame(
      title: title,
      actions: [
        const DialogCancelButton(key: ValueKey('settings-color-cancel')),
        DialogActionButton(
          key: const ValueKey('settings-color-apply'),
          label: i18n('exit_yes'),
          onPressed: () {
            final color = picker.currentState?.commit();
            if (color != null) Navigator.of(context).pop(color);
          },
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
