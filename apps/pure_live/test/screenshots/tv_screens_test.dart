@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/features/room/player_view.dart';

import 'shot_harness.dart';

/// TV mode (principles §5.3): the 960×540 canvas with the collapsed rail,
/// dark and pure black only, focus that reads from the sofa.
void main() {
  screenshotSetUp();

  Future<void> press(ShotApp app, List<LogicalKeyboardKey> keys) async {
    for (final key in keys) {
      await app.tester.sendKeyEvent(key);
      await app.frames(3);
    }
  }

  // The remote starts on the rail (the first destination has focus).
  screenshot('tv-follows', ShotScreen.tv, (app) => app.go('/follows'), theme: ShotTheme.dark);
  // Right into the page, down onto the first card: it grows and gets the ring.
  screenshot('tv-follows-card', ShotScreen.tv, (app) async {
    await app.go('/follows');
    await press(app, [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowDown]);
  }, theme: ShotTheme.black);
  screenshot('tv-discover', ShotScreen.tv, (app) async {
    await app.go('/discover');
    await press(app, [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowDown]);
  }, theme: ShotTheme.dark);
  // Two panes; right leaves the rail for the group list.
  screenshot('tv-settings', ShotScreen.tv, (app) async {
    await app.go('/me/settings');
    await press(app, [LogicalKeyboardKey.arrowRight]);
  }, theme: ShotTheme.dark);
  Future<void> room(ShotApp app) async {
    await app.push(roomLocation(app.world.roomDetail.ref));
    await app.play();
    await app.chat();
  }

  // OK shows the info bar and the control row over the picture.
  screenshot('tv-room', ShotScreen.tv, (app) async {
    await room(app);
    await press(app, [LogicalKeyboardKey.select]);
  }, theme: ShotTheme.dark);
  // The same on a white picture: the bar's scrim keeps the text readable.
  screenshot('tv-room-white', ShotScreen.tv, (app) async {
    debugPictureBackground = Colors.white;
    addTearDown(() => debugPictureBackground = Colors.black);
    await room(app);
    await press(app, [LogicalKeyboardKey.select]);
  }, theme: ShotTheme.dark);
  // Left: the rooms of the list; right: the playback settings (principles §6.3).
  screenshot('tv-room-list', ShotScreen.tv, (app) async {
    await room(app);
    await press(app, [LogicalKeyboardKey.arrowLeft]);
  }, theme: ShotTheme.dark);
  screenshot('tv-room-settings', ShotScreen.tv, (app) async {
    await room(app);
    await press(app, [LogicalKeyboardKey.arrowRight]);
  }, theme: ShotTheme.dark);
}
