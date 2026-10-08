import 'package:flutter/painting.dart';

// The corner radii and animation durations of docs/specs/UI.md §8.3 and
// §8.6, named once here (A01.2) instead of written at each use. The
// springs and fling thresholds of drags are `AppMotion` (motion.dart).

/// The corner radii (3.x `lib/common/style/theme.dart:113-184`, UI.md §8.3).
///
/// Room cards follow the "卡片设置" (`RoomCardAppearance.cornerRadius`,
/// default 20) and are not here; badges, swatches and other small marks keep
/// their own radius next to their size.
abstract final class AppRadii {
  /// Cards other than room cards, setting groups, framed blocks (16).
  static const BorderRadius card = BorderRadius.all(Radius.circular(16));

  /// Filled, outlined and elevated buttons, and other button-like blocks (12).
  static const BorderRadius button = BorderRadius.all(Radius.circular(12));

  /// Text buttons (8, 3.x `TextButton`).
  static const BorderRadius textButton = BorderRadius.all(Radius.circular(8));

  /// List and settings rows (12).
  static const BorderRadius listRow = BorderRadius.all(Radius.circular(12));

  /// Text fields (12).
  static const BorderRadius input = BorderRadius.all(Radius.circular(12));

  /// Dialogs (24).
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(24));

  /// Small menus beside their button, toasts and a tab's highlight (8).
  static const BorderRadius menu = BorderRadius.all(Radius.circular(8));

  /// Chips (8).
  static const BorderRadius chip = BorderRadius.all(Radius.circular(8));

  /// The top corners of a panel from the bottom (16).
  static const BorderRadius panelTop = BorderRadius.vertical(top: Radius.circular(16));

  /// The start corners of a panel from the side (16).
  static const BorderRadius panelSide = BorderRadius.horizontal(left: Radius.circular(16));
}

/// How long animations take (UI.md §8.6): instant feedback 100–150 ms, a
/// state change 150–250 ms, pages and panels 250–350 ms; leaving is faster
/// than entering. Pages follow the system's "remove animations" with
/// `MediaQuery.disableAnimations` themselves (a zero duration).
abstract final class AppDurations {
  /// The quickest feedback, and a small menu closing (100).
  static const Duration instant = Duration(milliseconds: 100);

  /// Feedback to a press or a hover, a small menu opening (150).
  static const Duration fast = Duration(milliseconds: 150);

  /// A state change: something fading or sliding in place (200).
  static const Duration normal = Duration(milliseconds: 200);

  /// A page part or panel coming in (300).
  static const Duration slow = Duration(milliseconds: 300);
}
