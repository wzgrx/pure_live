import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// One option of [showChoiceDialog].
typedef SettingsChoice<T> = ({T value, String label, String? description});

/// The dialog frame of the settings: at most 420 wide, scrolls when the
/// screen is short, tighter margins on narrow or large-text screens (3.x
/// `ThemeChoiceDialog`).
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
/// `ThemeChoiceDialog`, plus a line of explanation per option).
Future<T?> showChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required List<SettingsChoice<T>> options,
  required T selected,
  String? hint,
}) => showDialog<T>(
  context: context,
  builder: (context) => SettingsDialogFrame(
    title: title,
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel')))],
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

/// 3.x's theme colours (`AppConsts.themeColors`), in its order.
const List<(String name, Color color)> themePalette = [
  ('Crimson', Color.fromARGB(255, 220, 20, 60)),
  ('Orange', Color(0xFFFF9800)),
  ('Chrome', Color.fromARGB(255, 230, 184, 0)),
  ('Grass', Color(0xFF8BC34A)),
  ('Teal', Color(0xFF009688)),
  ('SeaFoam', Color.fromARGB(255, 112, 193, 207)),
  ('Ice', Color.fromARGB(255, 115, 155, 208)),
  ('Blue', Color(0xFF2196F3)),
  ('Indigo', Color(0xFF3F51B5)),
  ('Violet', Color(0xFF673AB7)),
  ('Primary', Color(0xFF6200EE)),
  ('Orchid', Color.fromARGB(255, 218, 112, 214)),
  ('Variant', Color(0xFF3700B3)),
  ('Secondary', Color(0xFF03DAC6)),
];

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

/// The result of [showColorDialog]: a null `color` means "follow the theme".
typedef ColorChoice = ({Color? color});

/// A colour: 3.x's palette swatches and a hex field (3.x used
/// flex_color_picker's wheel; the swatches and hex cover what it was used
/// for). With [allowThemeColor] the first choice follows the theme colour.
Future<ColorChoice?> showColorDialog({
  required BuildContext context,
  required String title,
  required Color? current,
  bool allowThemeColor = false,
}) => showDialog<ColorChoice>(
  context: context,
  builder: (context) => _ColorDialog(title: title, current: current, allowThemeColor: allowThemeColor),
);

class _ColorDialog extends StatefulWidget {
  const new({required this.title, required this.current, required this.allowThemeColor});

  final String title;
  final Color? current;
  final bool allowThemeColor;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late final TextEditingController _hex = TextEditingController(
    text: widget.current == null ? '' : colorHex(widget.current!).substring(2),
  );
  String? _error;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _applyHex() {
    final color = parseColorHex(_hex.text);
    if (color == null) {
      setState(() => _error = i18n('settings_color_invalid'));
      return;
    }
    Navigator.of(context).pop((color: color));
  }

  Widget _swatch(Color color, {required bool selected, required VoidCallback onTap, Key? key, Widget? child}) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? colors.onSurface : colors.outlineVariant, width: selected ? 3 : 1),
        ),
        child: child ?? (selected ? const Icon(Icons.check_rounded, color: Colors.white) : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current?.toARGB32();
    final primary = Theme.of(context).colorScheme.primary;
    return SettingsDialogFrame(
      title: widget.title,
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
        FilledButton(key: const ValueKey('settings-color-apply'), onPressed: _applyHex, child: Text(i18n('confirm'))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (widget.allowThemeColor)
                  Tooltip(
                    message: i18n('settings_color_follow_theme'),
                    child: _swatch(
                      primary,
                      key: const ValueKey('settings-color-theme'),
                      selected: current == null,
                      onTap: () => Navigator.of(context).pop((color: null)),
                      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                for (final (name, color) in themePalette)
                  Tooltip(
                    message: name,
                    child: _swatch(
                      color,
                      key: ValueKey('settings-color-$name'),
                      selected: current == color.toARGB32(),
                      onTap: () => Navigator.of(context).pop((color: color)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('settings-color-hex'),
              controller: _hex,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                LengthLimitingTextInputFormatter(9),
              ],
              onSubmitted: (_) => _applyHex(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: i18n('settings_color_hex'),
                prefixText: '#',
                helperText: 'RRGGBB',
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
