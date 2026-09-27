import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart' show VideoFit;
import 'package:pure_live_app/features/room/gestures.dart';
import 'package:pure_live_app/features/room/presentation.dart';

void main() {
  group('T-01 / D-01 tap', () {
    TapOutcome tap({
      bool locked = false,
      bool visible = false,
      bool band = false,
      bool hit = false,
      bool playing = true,
      bool touch = true,
    }) => tapOutcome(
      locked: locked,
      controlsVisible: visible,
      inControlBand: band,
      hitDanmaku: hit,
      playing: playing,
      touch: touch,
    );

    test('the lock wins over everything', () {
      expect(tap(locked: true, visible: true, band: true, hit: true), TapOutcome.toggleLockButton);
    });

    test('INV-ROOM-01: a tap in a visible control band only keeps the controls, no danmaku hit', () {
      expect(tap(visible: true, band: true, hit: true), TapOutcome.keepControls);
      // Hidden controls: the band is ordinary picture.
      expect(tap(band: true, hit: true), TapOutcome.danmakuActions);
    });

    test('a danmaku hit opens its actions', () {
      expect(tap(visible: true, hit: true), TapOutcome.danmakuActions);
    });

    test('REG-ROOM-003: touch hides visible controls while playing, shows them otherwise', () {
      expect(tap(visible: true), TapOutcome.hideControls);
      expect(tap(visible: true, playing: false), TapOutcome.showControls);
      expect(tap(), TapOutcome.showControls);
    });

    test('D-01: a mouse click only shows', () {
      expect(tap(visible: true, touch: false), TapOutcome.showControls);
    });
  });

  group('T-07 long press', () {
    test('locked does nothing; the band keeps the controls; a hit opens actions; else the quick panel', () {
      expect(
        longPressOutcome(locked: true, controlsVisible: false, inControlBand: false, hitDanmaku: true),
        LongPressOutcome.none,
      );
      expect(
        longPressOutcome(locked: false, controlsVisible: true, inControlBand: true, hitDanmaku: true),
        LongPressOutcome.keepControls,
      );
      expect(
        longPressOutcome(locked: false, controlsVisible: true, inControlBand: false, hitDanmaku: true),
        LongPressOutcome.danmakuActions,
      );
      expect(
        longPressOutcome(locked: false, controlsVisible: false, inControlBand: false, hitDanmaku: false),
        LongPressOutcome.quickPanel,
      );
    });
  });

  group('T-02 double tap', () {
    test('locked: nothing', () {
      expect(doubleTapTarget(current: RoomPresentation.inline, locked: true, portraitCondition: false), isNull);
    });

    test('portrait source on touch enters portrait fullscreen; others fullscreen', () {
      expect(
        doubleTapTarget(current: RoomPresentation.inline, locked: false, portraitCondition: true),
        RoomPresentation.portraitFullscreen,
      );
      expect(
        doubleTapTarget(current: RoomPresentation.inline, locked: false, portraitCondition: false),
        RoomPresentation.fullscreen,
      );
      expect(
        doubleTapTarget(current: RoomPresentation.theater, locked: false, portraitCondition: false),
        RoomPresentation.fullscreen,
      );
    });

    test('leaving goes back where fullscreen came from', () {
      expect(
        doubleTapTarget(
          current: RoomPresentation.fullscreen,
          locked: false,
          portraitCondition: false,
          returnTo: RoomPresentation.theater,
        ),
        RoomPresentation.theater,
      );
      expect(
        doubleTapTarget(current: RoomPresentation.portraitFullscreen, locked: false, portraitCondition: true),
        RoomPresentation.inline,
      );
    });
  });

  test('ZN-1 control bands are the top and bottom 56 dp', () {
    expect(inControlBand(10, 300), isTrue);
    expect(inControlBand(150, 300), isFalse);
    expect(inControlBand(250, 300), isTrue);
  });

  test('ZN-3 swipe zones: left brightness, right volume; desktops have no brightness', () {
    expect(swipeTarget(x: 10, width: 400, touch: true), SwipeTarget.brightness);
    expect(swipeTarget(x: 300, width: 400, touch: true), SwipeTarget.volume);
    expect(swipeTarget(x: 10, width: 400, touch: false), SwipeTarget.none);
    expect(swipeTarget(x: 300, width: 400, touch: false), SwipeTarget.volume);
  });

  test('T-03: half the picture height is 25%, up raises', () {
    expect(swipeChange(-150, 300), closeTo(0.25, 1e-9));
    expect(swipeChange(75, 300), closeTo(-0.125, 1e-9));
    expect(swipeChange(10, 0), 0);
  });

  test('T-06: spreading fills, pinching fits, one step per gesture', () {
    expect(pinchFit(VideoFit.contain, 1.3), VideoFit.cover);
    expect(pinchFit(VideoFit.cover, 1.3), isNull);
    expect(pinchFit(VideoFit.cover, 0.7), VideoFit.contain);
    expect(pinchFit(VideoFit.fill, 0.7), VideoFit.contain);
    expect(pinchFit(VideoFit.contain, 1.05), isNull);
  });

  test('ZN-2 / T-04: portrait fullscreen exit from the bottom 96 dp', () {
    expect(startsInPortraitExitZone(720, 800), isTrue);
    expect(startsInPortraitExitZone(600, 800), isFalse);
    expect(exitsPortraitFullscreen(upward: 64, velocity: 0), isTrue);
    expect(exitsPortraitFullscreen(upward: 30, velocity: -900), isTrue);
    expect(exitsPortraitFullscreen(upward: 20, velocity: -900), isFalse);
    expect(exitsPortraitFullscreen(upward: 40, velocity: -300), isFalse);
  });

  group('PS-4 portrait panel', () {
    test('heights on an 800 dp phone', () {
      final metrics = PortraitPanelMetrics(800);
      expect(metrics.low, 216);
      expect(metrics.mid, closeTo(352, 1e-9));
      expect(metrics.high, closeTo(544, 1e-9));
      expect(metrics.fullscreenPull, closeTo(72, 1e-9));
    });

    test('low is kept within 190–250 dp and the video keeps 120 dp', () {
      expect(PortraitPanelMetrics(600).low, 190);
      expect(PortraitPanelMetrics(1200).low, 250);
      final tiny = PortraitPanelMetrics(260);
      expect(tiny.low, 140);
      expect(tiny.high, 140);
    });

    test('release snaps to the nearest height', () {
      final metrics = PortraitPanelMetrics(800);
      expect(metrics.nearest(260), metrics.low);
      expect(metrics.nearest(400), metrics.mid);
      expect(metrics.nearest(700), metrics.high);
    });

    test('pulling 30% below the lowest, or a fast short pull, enters portrait fullscreen', () {
      final metrics = PortraitPanelMetrics(800);
      expect(metrics.entersFullscreen(metrics.low - 72, 0), isTrue);
      expect(metrics.entersFullscreen(metrics.low - 60, 0), isFalse);
      expect(metrics.entersFullscreen(metrics.low - 30, 950), isTrue);
      expect(metrics.entersFullscreen(metrics.low - 20, 950), isFalse);
    });
  });
}
