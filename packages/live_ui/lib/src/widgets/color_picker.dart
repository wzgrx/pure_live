import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/metrics.dart';

/// The words of [LiveColorPicker] (the app passes the current language's).
@immutable
final class LiveColorPickerLabels {
  /// Creates the words.
  const new({
    required this.recommended,
    required this.primary,
    required this.accent,
    required this.wheel,
    required this.shades,
    required this.opacity,
    required this.code,
    required this.invalidCode,
  });

  /// The app's colours tab ("推荐").
  final String recommended;

  /// Material's primary colours tab ("常用色").
  final String primary;

  /// Material's accent colours tab ("鲜艳色").
  final String accent;

  /// The wheel tab ("调色盘").
  final String wheel;

  /// Above the shades ("选择色阶").
  final String shades;

  /// Above the opacity slider ("选择透明度").
  final String opacity;

  /// The code field's label ("RGB 颜色代码").
  final String code;

  /// The code field's error.
  final String invalidCode;
}

/// `RRGGBB`, `AARRGGBB`, `#…` or `0x…` as a colour (3.x
/// `parseAppColorCode`); without [opacity] the alpha is dropped.
Color? parseColorCode(String input, {bool opacity = false}) {
  var value = input.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.toLowerCase().startsWith('0x')) value = value.substring(2);
  if (value.length != 6 && value.length != 8) return null;
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) return null;
  if (value.length == 6) value = 'FF$value';
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  final color = Color(parsed);
  return opacity ? color : color.withValues(alpha: 1);
}

/// [color] as the code field shows it: `#RRGGBB`, or `0xAARRGGBB` with
/// [opacity] (3.x `formatAppColorCode`).
String formatColorCode(Color color, {bool opacity = false}) {
  final argb = color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
  return opacity ? '0x$argb' : '#${argb.substring(2)}';
}

/// The colour picker of the theme and loading colours (3.x used
/// flex_color_picker; U.6b c10): tabs of round swatches ("推荐" first, then
/// Material's primary and accent colours, a hue and saturation wheel), the
/// shades of the chosen colour, an optional opacity slider and the colour
/// code. Every change is reported at once ([onChanged]) so the page behind
/// can preview it.
class LiveColorPicker extends StatefulWidget {
  /// Creates the picker.
  const new({
    required this.color,
    required this.onChanged,
    required this.labels,
    this.opacity = false,
    this.recommended = LivePalettes.recommended,
    super.key,
  });

  /// The colour it starts with.
  final Color color;

  /// Every change.
  final ValueChanged<Color> onChanged;

  /// The words.
  final LiveColorPickerLabels labels;

  /// Whether the alpha can be chosen (the loading colour).
  final bool opacity;

  /// The first tab's colours.
  final List<(String name, Color color)> recommended;

  @override
  State<LiveColorPicker> createState() => LiveColorPickerState();
}

/// The state of [LiveColorPicker]; [commit] checks the code field.
class LiveColorPickerState extends State<LiveColorPicker> {
  late Color _color = widget.opacity ? widget.color : widget.color.withValues(alpha: 1);
  late final TextEditingController _code = TextEditingController(
    text: formatColorCode(_color, opacity: widget.opacity),
  );
  late int _tab = _initialTab();
  String? _error;

  /// The colour now chosen.
  Color get color => _color;

  int _initialTab() {
    final rgb = _color.withValues(alpha: 1).toARGB32();
    if (widget.recommended.any((entry) => entry.$2.toARGB32() == rgb)) return 0;
    if (_swatchOf(LivePalettes.primaries, rgb) != null) return 1;
    if (_swatchOf(LivePalettes.accents, rgb) != null) return 2;
    return 0;
  }

  static ColorSwatch<int>? _swatchOf(List<ColorSwatch<int>> swatches, int rgb) {
    for (final swatch in swatches) {
      if (LivePalettes.swatchShades(swatch).any((shade) => shade.toARGB32() == rgb)) return swatch;
    }
    return null;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// The colour of the code field, or null after showing the error.
  Color? commit() {
    final parsed = parseColorCode(_code.text, opacity: widget.opacity);
    if (parsed == null) {
      setState(() => _error = widget.labels.invalidCode);
      return null;
    }
    return parsed;
  }

  void _pick(Color color, {bool updateCode = true}) {
    final next = widget.opacity ? color.withValues(alpha: _color.a) : color.withValues(alpha: 1);
    setState(() {
      _color = next;
      _error = null;
      if (updateCode) {
        final text = formatColorCode(next, opacity: widget.opacity);
        _code.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    });
    widget.onChanged(next);
  }

  List<Color> _shades() {
    final rgb = _color.withValues(alpha: 1).toARGB32();
    final swatch = _swatchOf(LivePalettes.primaries, rgb) ?? _swatchOf(LivePalettes.accents, rgb);
    if (swatch != null) return LivePalettes.swatchShades(swatch);
    for (final (_, base) in widget.recommended) {
      final shades = LivePalettes.shadesOf(base);
      if (shades.any((shade) => shade.toARGB32() == rgb)) return shades;
    }
    return LivePalettes.shadesOf(_color.withValues(alpha: 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labels = widget.labels;
    final rgb = _color.withValues(alpha: 1).toARGB32();
    final heading = (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(fontWeight: FontWeight.w600);
    final page = switch (_tab) {
      0 => _Swatches(
        colors: [for (final (_, color) in widget.recommended) color],
        names: [for (final (name, _) in widget.recommended) name],
        selected: rgb,
        onPick: _pick,
        keyPrefix: 'color-recommended',
      ),
      1 => _Swatches(
        colors: [for (final swatch in LivePalettes.primaries) Color(swatch.toARGB32())],
        selected: rgb,
        onPick: _pick,
        matches: (index) =>
            LivePalettes.swatchShades(LivePalettes.primaries[index]).any((shade) => shade.toARGB32() == rgb),
        keyPrefix: 'color-primary',
      ),
      2 => _Swatches(
        colors: [for (final swatch in LivePalettes.accents) Color(swatch.toARGB32())],
        selected: rgb,
        onPick: _pick,
        matches: (index) =>
            LivePalettes.swatchShades(LivePalettes.accents[index]).any((shade) => shade.toARGB32() == rgb),
        keyPrefix: 'color-accent',
      ),
      _ => _Wheel(color: _color.withValues(alpha: 1), onChanged: _pick),
    };
    final shades = _shades();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tabs(
          labels: [labels.recommended, labels.primary, labels.accent, labels.wheel],
          selected: _tab,
          onSelected: (tab) => setState(() => _tab = tab),
        ),
        const SizedBox(height: 12),
        page,
        if (_tab != 3) ...[
          const SizedBox(height: 16),
          Text(labels.shades, style: heading),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (index, shade) in shades.indexed)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: index == shades.length - 1 ? 0 : 4),
                    child: AspectRatio(
                      aspectRatio: 0.8,
                      child: InkWell(
                        key: ValueKey('color-shade-$index'),
                        borderRadius: const BorderRadius.all(Radius.circular(6)),
                        onTap: () => _pick(shade),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: shade,
                            borderRadius: const BorderRadius.all(Radius.circular(6)),
                            border: shade.toARGB32() == rgb ? Border.all(color: colors.onSurface, width: 2.5) : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (widget.opacity) ...[
          const SizedBox(height: 16),
          Text(labels.opacity, style: heading),
          Slider(
            key: const ValueKey('color-opacity'),
            value: _color.a,
            onChanged: (alpha) {
              final next = _color.withValues(alpha: alpha);
              setState(() {
                _color = next;
                _code.text = formatColorCode(next, opacity: true);
              });
              widget.onChanged(next);
            },
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('color-code'),
          controller: _code,
          maxLength: widget.opacity ? 10 : 9,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-FxX#]'))],
          decoration: InputDecoration(
            labelText: labels.code,
            helperText: widget.opacity ? '0xAARRGGBB / #AARRGGBB / RRGGBB' : '#RRGGBB / 0xRRGGBB',
            errorText: _error,
            counterText: '',
          ),
          onChanged: (text) {
            final parsed = parseColorCode(text, opacity: widget.opacity);
            if (parsed == null) {
              if (_error != null) setState(() => _error = null);
              return;
            }
            setState(() {
              _color = parsed;
              _error = null;
            });
            widget.onChanged(parsed);
          },
        ),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const new({required this.labels, required this.selected, required this.onSelected});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final (index, label) in labels.indexed)
              Expanded(
                child: InkWell(
                  key: ValueKey('color-tab-$index'),
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  onTap: () => onSelected(index),
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index == selected ? colors.surface : Colors.transparent,
                      borderRadius: const BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                        fontWeight: index == selected ? FontWeight.w600 : FontWeight.w400,
                        color: index == selected ? colors.onSurface : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const new({
    required this.colors,
    required this.selected,
    required this.onPick,
    required this.keyPrefix,
    this.names,
    this.matches,
  });

  final List<Color> colors;
  final List<String>? names;
  final int selected;
  final ValueChanged<Color> onPick;
  final bool Function(int index)? matches;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Five a row on a phone (3.x), more on a wide dialog.
        final columns = (constraints.maxWidth / 60).floor().clamp(5, 8);
        final size = ((constraints.maxWidth - (columns - 1) * 8) / columns).clamp(32.0, 52.0);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, color) in colors.indexed)
              Builder(
                builder: (context) {
                  final on = matches?.call(index) ?? color.toARGB32() == selected;
                  final swatch = InkWell(
                    key: ValueKey('$keyPrefix-$index'),
                    customBorder: const CircleBorder(),
                    onTap: () => onPick(color),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: on ? Border.all(color: scheme.onSurface, width: 3) : null,
                      ),
                      child: on ? Icon(AppIcons.selected, color: InkOnColor.on(color), size: size * 0.5) : null,
                    ),
                  );
                  final name = names?[index];
                  return name == null ? swatch : Tooltip(message: name, child: swatch);
                },
              ),
          ],
        );
      },
    );
  }
}

/// Hue on a bar, saturation and brightness on a square.
class _Wheel extends StatefulWidget {
  const new({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.onChanged(hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const height = 160.0;
            void at(Offset local) => _set(
              _hsv.withSaturation((local.dx / width).clamp(0, 1)).withValue(1 - (local.dy / height).clamp(0, 1)),
            );
            return GestureDetector(
              key: const ValueKey('color-wheel-square'),
              onPanDown: (details) => at(details.localPosition),
              onPanUpdate: (details) => at(details.localPosition),
              child: CustomPaint(size: Size(width, height), painter: _SquarePainter(_hsv, outline)),
            );
          },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            void at(Offset local) => _set(_hsv.withHue((local.dx / width).clamp(0, 1) * 360));
            return GestureDetector(
              key: const ValueKey('color-wheel-hue'),
              onPanDown: (details) => at(details.localPosition),
              onPanUpdate: (details) => at(details.localPosition),
              child: CustomPaint(size: Size(width, 28), painter: _HuePainter(_hsv.hue, outline)),
            );
          },
        ),
      ],
    );
  }
}

class _SquarePainter extends CustomPainter {
  new(this.hsv, this.outline);

  final HSVColor hsv;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas
      ..save()
      ..clipRRect(rounded)
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [const Color(0xFFFFFFFF), HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()])
              .createShader(rect),
      )
      ..drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xFF000000)],
          ).createShader(rect),
      )
      ..restore()
      ..drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = outline,
      );
    final point = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas
      ..drawCircle(
        point,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFFFFFFF),
      )
      ..drawCircle(
        point,
        10.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x66000000),
      );
  }

  @override
  bool shouldRepaint(_SquarePainter oldDelegate) => oldDelegate.hsv != hsv || oldDelegate.outline != outline;
}

class _HuePainter extends CustomPainter {
  new(this.hue, this.outline);

  final double hue;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rounded = RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    canvas
      ..drawRRect(
        rounded,
        Paint()
          ..shader = LinearGradient(
            colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()],
          ).createShader(rect),
      )
      ..drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = outline,
      );
    final x = (hue / 360) * size.width;
    canvas.drawCircle(
      Offset(x.clamp(size.height / 2, size.width - size.height / 2), size.height / 2),
      size.height / 2 - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_HuePainter oldDelegate) => oldDelegate.hue != hue || oldDelegate.outline != outline;
}
