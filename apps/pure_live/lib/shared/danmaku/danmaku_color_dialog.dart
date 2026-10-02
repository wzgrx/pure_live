import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The colours offered for danmaku (the usual danmaku colours of the
/// platforms; any other is typed as hex).
const List<Color> danmakuColorSwatches = [
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFFE0302),
  Color(0xFFFF7204),
  Color(0xFFFFAA02),
  Color(0xFFFFD302),
  Color(0xFF00CD00),
  Color(0xFF00A2FF),
  Color(0xFF4266BE),
  Color(0xFFCC0273),
];

/// `#FFFFFFFF` (3.x's form of a danmaku colour).
String danmakuColorText(Color color) => '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// The colour a row shows (3.x `ColorIndicator` and the hex): a round swatch
/// and its value, greyed out with [enabled] false.
class DanmakuColorChip extends StatelessWidget {
  /// Creates the chip.
  const new({required this.color, this.enabled = true, super.key});

  /// The colour.
  final Color color;

  /// Greyed out when false.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: const SizedBox.square(dimension: 28),
          ),
          const SizedBox(width: 8),
          Text(
            danmakuColorText(color),
            style: theme.textTheme.labelMedium?.emphasis.tabular.copyWith(color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

/// Picks a danmaku colour: [danmakuColorSwatches] or a hex value. Null when
/// cancelled.
Future<Color?> showDanmakuColorDialog({required BuildContext context, required String title, required Color current}) =>
    showAppDialog<Color>(
      context: context,
      builder: (context) => _ColorDialog(title: title, current: current),
    );

class _ColorDialog extends StatefulWidget {
  const new({required this.title, required this.current});

  final String title;
  final Color current;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late final TextEditingController _hex = TextEditingController(
    text: widget.current.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(),
  );
  String? _error;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _apply() {
    var hex = _hex.text.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final value = hex.length == 8 ? int.tryParse(hex, radix: 16) : null;
    if (value == null) {
      setState(() => _error = i18n('settings_color_invalid'));
      return;
    }
    Navigator.of(context).pop(Color(value));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = widget.current.toARGB32();
    return AppDialog(
      title: widget.title,
      autofocus: false,
      onEnter: _apply,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in danmakuColorSwatches)
                InkWell(
                  key: ValueKey('danmaku-color-${color.toARGB32().toRadixString(16)}'),
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(color),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: current == color.toARGB32() ? scheme.primary : scheme.outlineVariant,
                        width: current == color.toARGB32() ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('danmaku-color-hex'),
            controller: _hex,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
              LengthLimitingTextInputFormatter(9),
            ],
            onSubmitted: (_) => _apply(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: dialogFieldDecoration(
              context,
              label: i18n('settings_color_hex'),
              helper: 'RRGGBB',
              error: _error,
            ).copyWith(prefixText: '#'),
          ),
        ],
      ),
      actions: [
        const DialogCancelButton(),
        DialogActionButton(key: const ValueKey('danmaku-color-apply'), label: i18n('confirm'), onPressed: _apply),
      ],
    );
  }
}
