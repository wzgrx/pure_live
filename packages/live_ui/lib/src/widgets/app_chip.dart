import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/widgets/focus_ring.dart';

/// The chip's height (docs/A-界面设计/A02-组件/A02.1-通用组件 c13); 48 to tap.
const double appChipHeight = 36;

/// The one chip of the app (U.1c c13; 3.x had three looks): 36 high, 8-point
/// corners, 14-point words; the chosen one on the secondary container with a
/// tick and semi-bold words, the others outlined in `outlineVariant` (the
/// colours and the outline come from [appChipTheme]). An optional `leading`
/// picture (a platform's logo) gives way to the tick when chosen. Used for
/// the follows' groups (U.4c), the search's platforms (U.5a), the viewing
/// presets (U.2f), the history's and the settings' presets (U.5c, U.6d).
class AppChip extends ChoiceChip {
  /// Creates the chip; [onSelected] null greys it out.
  new({
    required String label,
    required super.selected,
    required VoidCallback? onSelected,
    Widget? leading,
    bool showCheckmark = true,
    super.tooltip,
    super.key,
  }) : super(
         label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
         // The tick takes the picture's place (Material would paint it over
         // a darkened logo).
         avatar: selected && showCheckmark ? const Icon(AppIcons.selected, size: 18) : leading,
         showCheckmark: false,
         labelStyle: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
         onSelected: onSelected == null ? null : (_) => onSelected(),
       );
}

/// The theme of every chip ([AppChip] and Material's chips, U.1c c13): the
/// shape, the outline (none when chosen; the primary frame while the
/// keyboard focus is on it), the colours and the size.
ChipThemeData appChipTheme(ColorScheme scheme, TextTheme textTheme) => ChipThemeData(
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
  side: AppChipSide(
    outline: scheme.outlineVariant,
    focus: scheme.primary,
    disabled: scheme.onSurface.withValues(alpha: 0.12),
  ),
  selectedColor: scheme.secondaryContainer,
  checkmarkColor: scheme.onSecondaryContainer,
  iconTheme: IconThemeData(color: scheme.onSecondaryContainer, size: 18),
  // A 20-point line and 8 above and below: 36 high.
  labelStyle: textTheme.bodyLarge?.copyWith(fontSize: 14, height: 20 / 14),
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
);

/// A chip's outline by state (U.1c c13): [outline], none when chosen,
/// [focus] 2 points wide while the keyboard focus is on it, [disabled] when
/// it cannot be used. Equal sides compare equal (a rebuilt theme does not
/// animate).
@immutable
final class AppChipSide extends WidgetStateBorderSide {
  /// Creates the side.
  const new({required this.outline, required this.focus, required this.disabled});

  /// The outline of a chip that is not chosen.
  final Color outline;

  /// The keyboard focus frame.
  final Color focus;

  /// The outline of a chip that cannot be used.
  final Color disabled;

  @override
  BorderSide? resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.focused) && focusFramesShown) return BorderSide(color: focus, width: 2);
    if (states.contains(WidgetState.selected)) return const BorderSide(color: Colors.transparent, width: 0);
    if (states.contains(WidgetState.disabled)) return BorderSide(color: disabled);
    return BorderSide(color: outline);
  }

  @override
  bool operator ==(Object other) =>
      other is AppChipSide && other.outline == outline && other.focus == focus && other.disabled == disabled;

  @override
  int get hashCode => Object.hash(outline, focus, disabled);
}
