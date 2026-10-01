import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_interaction.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_room_session.dart';

export 'package:pure_live/features/live_play/local_interaction/logic/local_interaction.dart';
export 'package:pure_live/features/live_play/local_interaction/logic/local_room_session.dart';

/// The app's local interaction (one for every room and the settings page).
///
/// Creating it also takes over 3.x values an earlier import parked in
/// `legacy_values` (the recorder's start does the same; it runs once per key)
/// and lists the emoji font's licence.
final Provider<LocalInteraction> localInteractionProvider = Provider((ref) {
  final store = ref.watch(storeProvider);
  final interaction = LocalInteraction(store.settings);
  unawaited(LegacyMigration.adoptLegacyValues(store).catchError((Object _) => 0));
  registerLocalEmojiLicense();
  ref.onDispose(interaction.dispose);
  return interaction;
});

/// Whether the local interaction is on (U.2k): the composers, the room menu's
/// "本地互动体验" and the local danmaku exist only then. The fullscreen bar
/// (U.2c) reads it to make room for the local danmaku composer.
bool localInteractionAvailable(WidgetRef ref) => watchSetting(ref, Settings.localInteractionEnabled);

/// Gives a live room's widgets its [LocalRoomSession] (the page owns it).
class LocalRoomScope extends InheritedWidget {
  /// Creates the scope.
  const new({required this.session, required super.child, super.key});

  /// The room's session.
  final LocalRoomSession session;

  /// The session around [context], or null outside a live room. Does not
  /// rebuild [context].
  static LocalRoomSession? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LocalRoomScope>()?.session;

  @override
  bool updateShouldNotify(LocalRoomScope oldWidget) => !identical(session, oldWidget.session);
}

/// The bundled emoji font (U.2k K4: a Noto Color Emoji subset holding the
/// gifts' and badges' emoji).
const String localEmojiFontFamily = 'PureLiveEmoji';

/// Apple systems draw the emoji with their own font (they do not read the
/// subset's COLRv1 glyphs); everything else uses the bundled one.
bool get _bundledEmoji => defaultTargetPlatform != TargetPlatform.iOS && defaultTargetPlatform != TargetPlatform.macOS;

/// [style] with the bundled emoji font tried before the system's fallback
/// fonts, so an emoji looks the same on every platform and never falls to a
/// box (Linux without a colour emoji font).
TextStyle localEmojiStyle(TextStyle? style) {
  final base = style ?? const TextStyle();
  if (!_bundledEmoji) return base;
  return base.copyWith(fontFamilyFallback: [localEmojiFontFamily, ...?base.fontFamilyFallback]);
}

/// [text] for [localEmojiStyle]: without the emoji presentation selector
/// (U+FE0F), which the subset does not hold and which its glyphs do not need.
String localEmojiText(String text) => _bundledEmoji ? text.replaceAll('️', '') : text;

bool _licenseAdded = false;

/// Lists the emoji font's licence (SIL OFL 1.1) on the licences page.
void registerLocalEmojiLicense() {
  if (_licenseAdded) return;
  _licenseAdded = true;
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/emoji/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Noto Color Emoji'], text);
  });
}

/// The colour of a platform's words on the theme's surface: [accent] made
/// dark enough on light surfaces and light enough on dark ones (the badge
/// chip, the identity card).
Color localAccentInk(int accent, Brightness brightness) {
  final hsl = HSLColor.fromColor(Color(accent));
  return hsl.withLightness(brightness == Brightness.dark ? 0.75 : 0.3).toColor();
}

/// [color] of a gift's name in the chat list, readable on the surface.
Color localGiftInk(LiveMessageColor color, Brightness brightness) {
  final hsl = HSLColor.fromColor(Color.fromARGB(255, color.r, color.g, color.b));
  return hsl.withLightness(brightness == Brightness.dark ? 0.72 : 0.5).toColor();
}
