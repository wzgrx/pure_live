@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/features/room/player_view.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

import 'shot_harness.dart';

/// The live room (principles §5.2: video on top at compact width, chat
/// beside it from expanded, fullscreen on a landscape phone) and multiview,
/// on the fake engine: the picture is black, the controls are showing.
/// The `-white` shots put a white picture under the controls: the scrims
/// must keep their text readable on the brightest frame (principles §2.2).
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

  group('room states', () {
    Future<void> room(ShotApp app) async {
      await app.push(roomLocation(app.world.roomDetail.ref));
      await app.play();
      await app.chat();
    }

    Future<void> white(ShotApp app) async {
      debugPictureBackground = Colors.white;
      addTearDown(() => debugPictureBackground = Colors.black);
      await room(app);
    }

    screenshot('room-white', ShotScreen.phone, white);
    // Fullscreen with the lock on the left edge.
    screenshot('room-white', ShotScreen.phoneLandscape, white);
    // The stream is still connecting: the spinner over the picture.
    screenshot('room-loading', ShotScreen.phone, (app) async {
      await app.push(roomLocation(app.world.roomDetail.ref));
      await app.chat();
    });
    // Every line refuses the stream; recovery gives up (REC-1) and the
    // picture offers the next steps.
    screenshot('room-failed', ShotScreen.phone, (app) async {
      await room(app);
      for (final engine in app.engines) {
        engine
          ..failEveryOpen = 'Failed to open https://cdn-a.example.com/live.m3u8.'
          ..endOfStream();
      }
      await app.frames(8, const Duration(seconds: 1));
    }, theme: ShotTheme.dark);
    // The chat floats over the right 40% of a landscape phone (principles §5.2).
    screenshot('room-chat', ShotScreen.phoneLandscape, (app) async {
      await room(app);
      await app.tester.tap(find.byTooltip(t.room.chat));
      await app.frames(3);
      await app.chat();
    }, theme: ShotTheme.dark);
    // A one-time tip sits at the picture's top left (principles §6.5).
    screenshot('room-tip', ShotScreen.large, (app) async {
      await room(app);
      app.tester.state<PlayerViewState>(find.byType(PlayerView)).showTip(t.room.tip.desktop);
      await app.frames(2);
    }, theme: ShotTheme.dark);
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
