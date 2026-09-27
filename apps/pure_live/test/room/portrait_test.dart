import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart' show VideoOrientation;
import 'package:live_store/live_store.dart' show PortraitFullscreenPolicy, PortraitOverride;
import 'package:pure_live_app/features/room/presentation.dart';

void main() {
  group('F-ROOM-06 / GEO-7: the source shape', () {
    test('automatic follows the geometry; unknown is neither', () {
      for (final (geometry, portrait, landscape) in [
        (VideoOrientation.portrait, true, false),
        (VideoOrientation.landscape, false, true),
        (VideoOrientation.unknown, false, false),
      ]) {
        final shape = sourceShape(adaptation: true, override: PortraitOverride.automatic, geometry: geometry);
        expect(shape.portrait, portrait, reason: '$geometry');
        expect(shape.landscape, landscape, reason: '$geometry');
      }
    });

    test('a room override wins over the geometry', () {
      expect(
        sourceShape(
          adaptation: true,
          override: PortraitOverride.landscape,
          geometry: VideoOrientation.portrait,
        ).portrait,
        isFalse,
      );
      expect(
        sourceShape(
          adaptation: true,
          override: PortraitOverride.portrait,
          geometry: VideoOrientation.landscape,
        ).portrait,
        isTrue,
      );
    });

    test('adaptation off treats every source as landscape', () {
      final shape = sourceShape(
        adaptation: false,
        override: PortraitOverride.portrait,
        geometry: VideoOrientation.portrait,
      );
      expect(shape.portrait, isFalse);
      expect(shape.landscape, isTrue);
    });
  });

  group('F-ROOM-06: fullscreen orientation', () {
    test('follow the source: landscape sources lock landscape, portrait ones portrait', () {
      final landscape = orientationLocks(
        policy: PortraitFullscreenPolicy.followSource,
        next: RoomPresentation.fullscreen,
        portraitSource: false,
      );
      expect((landscape.landscape, landscape.portrait), (true, false));
      final portrait = orientationLocks(
        policy: PortraitFullscreenPolicy.followSource,
        next: RoomPresentation.portraitFullscreen,
        portraitSource: true,
      );
      expect((portrait.landscape, portrait.portrait), (false, true));
      expect(
        orientationLocks(
          policy: PortraitFullscreenPolicy.followSource,
          next: RoomPresentation.fullscreen,
          portraitSource: false,
          byRotation: true,
        ).landscape,
        isFalse,
        reason: 'T-09: turning the phone never locks',
      );
    });

    test('follow the phone never locks unless landscape is forced', () {
      for (final next in [RoomPresentation.fullscreen, RoomPresentation.portraitFullscreen]) {
        final locks = orientationLocks(policy: PortraitFullscreenPolicy.followSystem, next: next, portraitSource: true);
        expect((locks.landscape, locks.portrait), (false, false), reason: '$next');
      }
      expect(
        orientationLocks(
          policy: PortraitFullscreenPolicy.followSystem,
          next: RoomPresentation.fullscreen,
          portraitSource: true,
          forceLandscape: true,
        ).landscape,
        isTrue,
      );
    });

    test('always landscape locks landscape for portrait sources too', () {
      expect(
        orientationLocks(
          policy: PortraitFullscreenPolicy.landscape,
          next: RoomPresentation.fullscreen,
          portraitSource: true,
        ).landscape,
        isTrue,
      );
    });
  });
}
