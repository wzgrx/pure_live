import 'package:flutter/material.dart';

/// The fixed colours of the TV interface (docs/ui/compare/U.15a). Everything
/// else on the TV comes from the phone's dark colour roles, seeded with the
/// user's theme colour (U.15a choice A2).
abstract final class TvColors {
  /// The focus ring: near white, 3 px, the same on every theme colour, so a
  /// focused item never reads as a selected one (selected items are filled
  /// with the primary container; U.15a c2, c3).
  static const Color focusRing = Color(0xFFF1F3F9);

  /// The scrim behind a dialog (60 % black, U.15a c16).
  static const Color scrim = Color(0x99000000);

  /// The heart of a followed room or area on a cover (pure_live_TV's pink,
  /// kept: it reads on any picture).
  static const Color followed = Color(0xFFFF5C7A);
}
