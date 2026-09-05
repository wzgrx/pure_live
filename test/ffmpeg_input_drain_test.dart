import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_service.dart';

void main() {
  test('EOF is requested before waiting for actual native completion', () async {
    final ended = Completer<void>();
    var inputEnded = false;
    final draining = FFmpegInputDrain.tryFinish(
      finishInput: () async {
        inputEnded = true;
      },
      completion: ended.future,
    );
    await Future<void>.delayed(Duration.zero);
    expect(inputEnded, true);
    var drained = false;
    unawaited(draining.then((_) => drained = true));
    expect(drained, false);
    ended.complete();
    expect(await draining, true);
  });

  test('stalled input shutdown is bounded without pretending native has ended', () async {
    final input = Completer<void>();
    final ended = Completer<void>();
    expect(
      await FFmpegInputDrain.tryFinish(
        finishInput: () => input.future,
        completion: ended.future,
        deadline: const Duration(milliseconds: 10),
      ),
      false,
    );
    expect(ended.isCompleted, false);
    input.complete();
    ended.complete();
  });

  test('stalled native drain is bounded even when EOF was already delivered', () async {
    final ended = Completer<void>();
    expect(
      await FFmpegInputDrain.tryFinish(
        finishInput: () async {},
        completion: ended.future,
        deadline: const Duration(milliseconds: 10),
      ),
      false,
    );
    expect(ended.isCompleted, false);
    ended.complete();
  });

  test('failed input shutdown falls back without an unhandled async error', () async {
    expect(
      await FFmpegInputDrain.tryFinish(
        finishInput: () => throw StateError('fixture'),
        completion: Future<void>.value(),
      ),
      false,
    );
  });
}
