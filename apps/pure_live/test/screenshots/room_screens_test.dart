@Tags(['screenshots'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

import 'shot_harness.dart';

/// The live room (principles §5.2: video on top at compact width, chat
/// beside it from expanded, fullscreen on a landscape phone) and multiview,
/// on the fake engine: the picture is black, the controls are showing.
void main() {
  screenshotSetUp();

  group('room', () {
    Future<void> room(ShotApp app) async {
      await app.push(roomLocation(app.world.roomDetail.ref));
      await app.play();
      await app.chat();
    }

    screenshot('room', ShotScreen.phone, room);
    screenshot('room', ShotScreen.phone, room, theme: ShotTheme.dark);
    screenshot('room', ShotScreen.phone, room, locale: AppLocale.en);
    screenshot('room', ShotScreen.phoneLandscape, room);
    screenshot('room', ShotScreen.medium, room);
    screenshot('room', ShotScreen.expanded, room, theme: ShotTheme.dark);
    screenshot('room', ShotScreen.large, room);
    screenshot('room', ShotScreen.extraLarge, room, theme: ShotTheme.dark);
  });

  group('multiview', () {
    Future<void> multiview(ShotApp app) async {
      await app.push('/multiview', extra: [for (final room in shotRooms.take(4)) RoomRef(room.platform, room.id)]);
      await app.play();
    }

    screenshot('multiview', ShotScreen.phone, multiview, theme: ShotTheme.dark);
    screenshot('multiview', ShotScreen.expanded, multiview);
    screenshot('multiview', ShotScreen.large, multiview, theme: ShotTheme.dark);
    screenshot('multiview', ShotScreen.extraLarge, multiview);
  });
}
