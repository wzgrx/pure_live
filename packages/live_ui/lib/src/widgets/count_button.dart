import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/text_styles.dart';

/// A − value + stepper (3.x `CountButton`). Holding a button repeats the
/// step every 100 ms until it is released or the limit is reached.
class CountButton extends StatefulWidget {
  /// Creates the stepper.
  const new({
    required this.minValue,
    required this.maxValue,
    required this.selectedValue,
    required this.onChanged,
    this.step = 1,
    this.backgroundColor,
    this.foregroundColor,
    this.buttonSize = const Size(kMinInteractiveDimension, kMinInteractiveDimension),
    this.incrementIcon,
    this.decrementIcon,
    this.semanticLabel,
    this.incrementSemanticLabel,
    this.decrementSemanticLabel,
    this.borderRadius = 12.0,
    this.valueBuilder,
    this.textStyle,
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

  /// Button colour; null is the primary colour.
  final Color? backgroundColor;

  /// Icon colour; null is white.
  final Color? foregroundColor;

  /// Size of each button.
  final Size buttonSize;

  /// The + icon.
  final Widget? incrementIcon;

  /// The − icon.
  final Widget? decrementIcon;

  /// Accessibility label of the value.
  final String? semanticLabel;

  /// Accessibility label of +.
  final String? incrementSemanticLabel;

  /// Accessibility label of −.
  final String? decrementSemanticLabel;

  /// Outer corner radius.
  final double borderRadius;

  /// Receives the new value.
  final ValueChanged<int> onChanged;

  /// Builds the value; null shows it as text.
  final Widget Function(int value)? valueBuilder;

  /// Style of the value; null is the card title style in white.
  final TextStyle? textStyle;

  @override
  State<CountButton> createState() => _CountButtonState();
}

class _CountButtonState extends State<CountButton> {
  Timer? _repeat;

  // The value the last step produced. 3.x stepped from widget.selectedValue,
  // so a parent that rebuilt later than 100 ms (or kept the value) made a
  // held button send the same value again and again.
  late int _value = widget.selectedValue;

  @override
  void didUpdateWidget(CountButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue) _value = widget.selectedValue;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  bool _stepBy(int delta) {
    final next = _value + delta;
    if (next < widget.minValue || next > widget.maxValue) return false;
    _value = next;
    widget.onChanged(next);
    return true;
  }

  void _startRepeat(int delta) {
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_stepBy(delta)) _stopRepeat();
    });
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  Widget _button({required int delta, required Widget icon, required String? label, required BorderRadius radius}) {
    final background = widget.backgroundColor ?? Theme.of(context).colorScheme.primary;
    final foreground = widget.foregroundColor ?? Colors.white;
    return SizedBox(
      width: widget.buttonSize.width,
      height: widget.buttonSize.height,
      child: GestureDetector(
        onLongPress: () => _startRepeat(delta),
        onLongPressEnd: (_) => _stopRepeat(),
        onLongPressCancel: _stopRepeat,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: radius),
          ),
          onPressed: () => _stepBy(delta),
          child: label == null
              ? icon
              : Semantics(
                  label: label,
                  child: ExcludeSemantics(child: icon),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.backgroundColor ?? Theme.of(context).colorScheme.primary;
    final foreground = widget.foregroundColor ?? Colors.white;
    final style = widget.textStyle ?? AppTextStyles.of(context).t15.copyWith(color: Colors.white);
    final radius = Radius.circular(widget.borderRadius);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            delta: -widget.step,
            icon: widget.decrementIcon ?? Icon(Icons.remove, color: foreground),
            label: widget.decrementSemanticLabel,
            radius: BorderRadius.only(topLeft: radius, bottomLeft: radius),
          ),
          Semantics(
            label: widget.semanticLabel == null ? null : '${widget.semanticLabel}, ${widget.selectedValue}',
            excludeSemantics: widget.semanticLabel != null,
            child: Container(
              height: widget.buttonSize.height,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.symmetric(horizontal: BorderSide(color: background, width: 2)),
              ),
              child: widget.valueBuilder?.call(widget.selectedValue) ?? Text('${widget.selectedValue}', style: style),
            ),
          ),
          _button(
            delta: widget.step,
            icon: widget.incrementIcon ?? Icon(Icons.add, color: foreground),
            label: widget.incrementSemanticLabel,
            radius: BorderRadius.only(topRight: radius, bottomRight: radius),
          ),
        ],
      ),
    );
  }
}
