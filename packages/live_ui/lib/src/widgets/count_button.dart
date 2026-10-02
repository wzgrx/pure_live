import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/widgets/settings_row.dart';

/// The − value + control (docs/A-界面设计/A02-组件/A02.1-通用组件 c10, the outlined style U.2f
/// confirmed): 36 high in a 1-point `outlineVariant` frame with 12-point
/// corners, each half 48 to tap; − and + in the variant ink, the value in
/// the primary colour, semi-bold, tabular. The half that cannot step
/// further ([onDecrease] or [onIncrease] null) is greyed out; the whole
/// control greys out when not [enabled]. Holding − or + repeats the step
/// every 100 ms after half a second; with the focus on it ← and → step too.
class CounterControl extends StatefulWidget {
  /// Creates the control.
  const new({
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    this.decreaseTooltip,
    this.increaseTooltip,
    this.onValueTap,
    this.enabled = true,
    this.semanticLabel,
    this.valueKey,
    this.decreaseKey,
    this.increaseKey,
    super.key,
  });

  /// The value as shown ("6", "6 px").
  final String value;

  /// One step down; null at the lower limit.
  final VoidCallback? onDecrease;

  /// One step up; null at the upper limit.
  final VoidCallback? onIncrease;

  /// The − button's name.
  final String? decreaseTooltip;

  /// The + button's name.
  final String? increaseTooltip;

  /// A tap on the value (type it in).
  final VoidCallback? onValueTap;

  /// False greys the control out and ignores it.
  final bool enabled;

  /// What the value is, for screen readers ("顶部留白").
  final String? semanticLabel;

  /// Key of the value.
  final Key? valueKey;

  /// Key of −.
  final Key? decreaseKey;

  /// Key of +.
  final Key? increaseKey;

  @override
  State<CounterControl> createState() => _CounterControlState();
}

class _CounterControlState extends State<CounterControl> {
  Timer? _repeat;

  // The release after a held repeat is not one more tap.
  bool _skipTap = false;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  /// After half a second held, repeats the − or + of the latest build every
  /// 100 ms until released or at the limit (raw pointer events, so the
  /// button's own tap and tooltip keep working).
  void _hold({required bool increase}) {
    _repeat?.cancel();
    _skipTap = false;
    _repeat = Timer(const Duration(milliseconds: 500), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        final step = increase ? widget.onIncrease : widget.onDecrease;
        if (!mounted || step == null || !widget.enabled) {
          timer.cancel();
          return;
        }
        _skipTap = true;
        step();
      });
    });
  }

  void Function()? _tap(VoidCallback? step) => step == null
      ? null
      : () {
          if (_skipTap) {
            _skipTap = false;
            return;
          }
          step();
        };

  void _release() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.enabled;
    final tv = SettingsRowStyle.tvOf(context);
    final decrease = enabled ? widget.onDecrease : null;
    final increase = enabled ? widget.onIncrease : null;
    Widget half(IconData glyph, String? tooltip, VoidCallback? onPressed, Key? key, {required bool up}) => Listener(
      onPointerDown: onPressed == null ? null : (_) => _hold(increase: up),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: _tap(onPressed),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(36),
          minimumSize: const Size.square(36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.padded,
          foregroundColor: scheme.onSurfaceVariant,
          disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.38),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        icon: Icon(glyph, size: 20),
      ),
    );
    final valueStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).tabular.copyWith(
      fontSize: tv ? 16 : 14,
      fontWeight: FontWeight.w600,
      color: enabled ? scheme.primary : scheme.onSurface.withValues(alpha: 0.38),
      decoration: widget.onValueTap == null ? null : TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: scheme.outline,
    );
    Widget number = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
      child: Center(
        widthFactor: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(widget.value, style: valueStyle),
        ),
      ),
    );
    if (widget.onValueTap case final tap? when enabled) {
      number = InkWell(
        key: widget.valueKey,
        onTap: tap,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: number,
      );
    } else {
      number = KeyedSubtree(key: widget.valueKey, child: number);
    }
    // 48 high to tap; the frame is drawn 36 high behind the halves.
    final control = SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            top: 6,
            bottom: 6,
            child: DecoratedBox(
              key: const ValueKey('counter-frame'),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: const BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              half(Icons.remove_rounded, widget.decreaseTooltip, decrease, widget.decreaseKey, up: false),
              Semantics(
                label: widget.semanticLabel,
                value: widget.value,
                excludeSemantics: widget.semanticLabel != null,
                child: number,
              ),
              half(Icons.add_rounded, widget.increaseTooltip, increase, widget.increaseKey, up: true),
            ],
          ),
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => decrease?.call(),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => increase?.call(),
      },
      child: control,
    );
  }
}

/// A − value + stepper over whole numbers (3.x `CountButton`, the outlined
/// look of [CounterControl]): − greys out at [minValue], + at [maxValue];
/// holding repeats the step every 100 ms, from the last value it sent even
/// when the parent rebuilds late (3.x sent the same value again).
class CountButton extends StatefulWidget {
  /// Creates the stepper.
  const new({
    required this.minValue,
    required this.maxValue,
    required this.selectedValue,
    required this.onChanged,
    this.step = 1,
    this.enabled = true,
    this.semanticLabel,
    this.incrementSemanticLabel,
    this.decrementSemanticLabel,
    this.valueBuilder,
    super.key,
  }) : assert(maxValue > minValue, 'maxValue must be above minValue'),
       assert(selectedValue >= minValue && selectedValue <= maxValue, 'selectedValue out of range'),
       assert(step > 0, 'step must be positive');

  /// Lowest value.
  final int minValue;

  /// Highest value.
  final int maxValue;

  /// Current value.
  final int selectedValue;

  /// Change per press.
  final int step;

  /// False greys it out.
  final bool enabled;

  /// Accessibility label of the value.
  final String? semanticLabel;

  /// Name of + (tooltip, screen readers).
  final String? incrementSemanticLabel;

  /// Name of − (tooltip, screen readers).
  final String? decrementSemanticLabel;

  /// Receives the new value.
  final ValueChanged<int> onChanged;

  /// The value as shown; null shows the number.
  final String Function(int value)? valueBuilder;

  @override
  State<CountButton> createState() => _CountButtonState();
}

class _CountButtonState extends State<CountButton> {
  late int _value = widget.selectedValue;

  @override
  void didUpdateWidget(CountButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue || _value < widget.minValue || _value > widget.maxValue) {
      _value = widget.selectedValue;
    }
  }

  void _stepBy(int delta) {
    final next = (_value + delta).clamp(widget.minValue, widget.maxValue);
    if (next == _value) return;
    setState(() => _value = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => CounterControl(
    value: widget.valueBuilder?.call(_value) ?? '$_value',
    enabled: widget.enabled,
    semanticLabel: widget.semanticLabel,
    decreaseTooltip: widget.decrementSemanticLabel,
    increaseTooltip: widget.incrementSemanticLabel,
    onDecrease: _value > widget.minValue ? () => _stepBy(-widget.step) : null,
    onIncrease: _value < widget.maxValue ? () => _stepBy(widget.step) : null,
  );
}
