import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

void main() {
  test('forced landscape fullscreen restores portrait exactly once', () {
    final state = FullscreenOrientationRestoreState();

    state.begin(restorePortraitOnExit: true);

    expect(state.takePortraitRestore(), isTrue);
    expect(state.takePortraitRestore(), isFalse);
  });

  test('fullscreen exit restores portrait after releasing immersive mode', () async {
    final calls = <String>[];
    final state = FullscreenOrientationRestoreState()..begin(restorePortraitOnExit: true);

    await exitFullscreenWithOrientationRestore(
      state: state,
      exitFullscreen: () async => calls.add('exit'),
      restorePortrait: () async => calls.add('portrait'),
      releaseOrientation: () async => calls.add('release'),
      portraitSettleDelay: Duration.zero,
    );

    expect(calls, ['exit', 'portrait', 'release']);
    expect(state.takePortraitRestore(), isFalse);
  });

  test('a later ordinary fullscreen entry clears an unfinished portrait restore', () {
    final state = FullscreenOrientationRestoreState();
    state.begin(restorePortraitOnExit: true);

    state.begin(restorePortraitOnExit: false);

    expect(state.takePortraitRestore(), isFalse);
  });
}
