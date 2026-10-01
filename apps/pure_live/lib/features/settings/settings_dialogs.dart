import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// One option of [showChoiceDialog].
typedef SettingsChoice<T> = ({T value, String label, String? description});

/// The dialog frame of the settings: at most 420 wide, scrolls when the
/// screen is short, tighter margins on narrow or large-text screens (3.x
/// `ThemeChoiceDialog`); 24 px corners like every other dialog (3.x used 16
/// here, U.6b Q14).
class SettingsDialogFrame extends StatelessWidget {
  /// Creates the frame.
  const new({required this.title, required this.child, this.actions = const [], super.key});

  /// The title.
  final String title;

  /// The content.
  final Widget child;

  /// Buttons under the content.
  final List<Widget> actions;

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
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: actions),
              )
            else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// A single-choice list; picking an option closes it with that value (3.x
/// `ThemeChoiceDialog`, plus a line of explanation per option). Without
/// [showCancel] (theme mode, language: 3.x had no buttons) it closes by a
/// tap outside, back or Esc.
Future<T?> showChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required List<SettingsChoice<T>> options,
  required T selected,
  String? hint,
  bool showCancel = true,
}) => showDialog<T>(
  context: context,
  builder: (context) => SettingsDialogFrame(
    title: title,
    actions: [if (showCancel) TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel')))],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ),
        RadioGroup<T>(
          groupValue: selected,
          onChanged: (value) {
            if (value != null) Navigator.of(context).pop(value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                RadioListTile<T>(
                  key: ValueKey('settings-choice-${option.value}'),
                  value: option.value,
                  title: Text(option.label),
                  subtitle: option.description == null ? null : Text(option.description!),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
            ],
          ),
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
  });

  final String title;
  final int current;
  final List<int> presets;
  final int min;
  final int max;
  final String Function(int value) label;
  final String? hint;
  final String? unit;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _input = TextEditingController(
    text: widget.presets.contains(widget.current) ? '' : '${widget.current}',
  );
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    final value = int.tryParse(_input.text.trim());
    if (value == null || value < widget.min || value > widget.max) {
      setState(() => _error = i18n('settings_number_range', args: {'min': '${widget.min}', 'max': '${widget.max}'}));
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
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in widget.presets)
                  ChoiceChip(
                    key: ValueKey('settings-number-$value'),
                    label: Text(widget.label(value)),
                    selected: value == widget.current,
                    selectedColor: colors.primaryContainer,
                    onSelected: (_) => Navigator.of(context).pop(value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
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
                labelText: i18n('custom_input'),
                suffixText: widget.unit,
                helperText: i18n('settings_number_range', args: {'min': '${widget.min}', 'max': '${widget.max}'}),
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

/// The section of a settings sub-page: a padded, width-limited list.
class SettingsListView extends StatelessWidget {
  /// Creates the list.
  const new({required this.children, super.key});

  /// The rows.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const PureLiveScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
    children: children,
  );
}
