import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/setting_rows.dart';

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

/// [text] typed as a colour: six hex digits (opaque) or eight, with or
/// without `#`; null when it is not one.
Color? parseDanmakuColor(String text) {
  var hex = text.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8 || !RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) return null;
  return Color(int.parse(hex, radix: 16));
}

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

/// A danmaku colour row that opens its palette under itself (A08.7 c1, c2):
/// tap the row to unfold [DanmakuColorPalette] (⌄ / ⌃ at the end), tap it
/// again to fold it. No dialog, so in the room's panels nothing covers the
/// picture. Greyed out and folded while [enabled] is false (A08.1 c10).
class DanmakuColorPickerRow extends StatefulWidget {
  /// Creates the row; [settingKey] names its keys (`danmaku-setting-…`).
  const new({
    required this.settingKey,
    required this.title,
    required this.color,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  /// The setting's name in the keys.
  final String settingKey;

  /// The title.
  final String title;

  /// The colour now.
  final Color color;

  /// A colour picked (at once, no "save").
  final ValueChanged<Color> onChanged;

  /// Greyed out (and folded) when false.
  final bool enabled;

  @override
  State<DanmakuColorPickerRow> createState() => _DanmakuColorPickerRowState();
}

class _DanmakuColorPickerRowState extends State<DanmakuColorPickerRow> {
  final GlobalKey _palette = GlobalKey();
  bool _open = false;

  @override
  void didUpdateWidget(DanmakuColorPickerRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _open = false;
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (!_open) return;
    // c2: bring the whole palette into view inside the panel's scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final palette = _palette.currentContext;
      if (palette == null || !palette.mounted) return;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      Scrollable.ensureVisible(
        palette,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
      ).ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = _open && widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Semantics(
            expanded: widget.enabled ? open : null,
            child: InkWell(
              onTap: widget.enabled ? _toggle : null,
              child: SettingRow(
                settingKey: widget.settingKey,
                title: widget.title,
                enabled: widget.enabled,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DanmakuColorChip(color: widget.color, enabled: widget.enabled),
                    const SizedBox(width: 4),
                    Icon(
                      open ? AppIcons.foldUp : AppIcons.dropDown,
                      key: ValueKey('danmaku-color-toggle-${widget.settingKey}'),
                      size: 20,
                      color: widget.enabled ? scheme.onSurfaceVariant : scheme.onSurface.withValues(alpha: 0.38),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            key: _palette,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DanmakuColorPalette(current: widget.color, onChanged: widget.onChanged),
          ),
      ],
    );
  }
}

/// The danmaku colours to pick from (A08.7 c1, c2): [danmakuColorSwatches]
/// as 48-point targets wrapping to the width (the current one ringed in the
/// primary colour with a tick, UI.md §7), then a "#" hex field that applies
/// on Enter or when it loses focus and says under itself what is wrong,
/// keeping the text. No opacity (3.x picked opaque colours).
class DanmakuColorPalette extends StatefulWidget {
  /// Creates the palette.
  const new({required this.current, required this.onChanged, super.key});

  /// The colour now.
  final Color current;

  /// A colour picked.
  final ValueChanged<Color> onChanged;

  @override
  State<DanmakuColorPalette> createState() => _DanmakuColorPaletteState();
}

class _DanmakuColorPaletteState extends State<DanmakuColorPalette> {
  late final TextEditingController _hex = TextEditingController(text: _hexOf(widget.current));
  final FocusNode _focus = FocusNode();
  String? _error;
  Color? _sent;

  static String _hexOf(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    return argb.startsWith('FF') ? argb.substring(2) : argb;
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _hex.text.trim().isNotEmpty && _error == null) _apply();
    });
  }

  @override
  void didUpdateWidget(DanmakuColorPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current && !_focus.hasFocus) {
      _hex.text = _hexOf(widget.current);
      _error = null;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _hex.dispose();
    super.dispose();
  }

  void _apply() {
    final color = parseDanmakuColor(_hex.text);
    if (color == null) {
      setState(() => _error = i18n('settings_color_invalid'));
      return;
    }
    setState(() => _error = null);
    // Enter, then the focus leaving: one change.
    if (color == widget.current || color == _sent) return;
    _sent = color;
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.current.toARGB32();
    return Column(
      key: const ValueKey('danmaku-color-palette'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          children: [
            for (final color in danmakuColorSwatches)
              _Swatch(color: color, selected: current == color.toARGB32(), onTap: () => widget.onChanged(color)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('danmaku-color-hex'),
          controller: _hex,
          focusNode: _focus,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
            LengthLimitingTextInputFormatter(9),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _apply(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          style: theme.textTheme.bodyMedium?.tabular,
          decoration: dialogFieldDecoration(
            context,
            label: i18n('settings_color_hex'),
            helper: 'RRGGBB',
            error: _error,
          ).copyWith(prefixText: '#', isDense: true),
        ),
      ],
    );
  }
}

/// One colour of [DanmakuColorPalette]: a 36-point disc in a 48-point
/// target; the hex shows on hover (desktop) and is its label; Tab reaches
/// it and Enter picks it.
class _Swatch extends StatelessWidget {
  const new({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = danmakuColorText(color);
    return Tooltip(
      message: text,
      child: Semantics(
        button: true,
        selected: selected,
        label: text,
        child: InkResponse(
          key: ValueKey('danmaku-color-${color.toARGB32().toRadixString(16)}'),
          onTap: onTap,
          radius: 24,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 3 : 1),
                ),
                child: selected
                    ? Icon(
                        AppIcons.selected,
                        key: const ValueKey('danmaku-color-selected'),
                        size: 20,
                        color: InkOnColor.on(color),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
