import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';

void main() {
  late List<PlayerException> errors;
  late NativeDiagnosticGate gate;

  void setUpGate() {
    errors = [];
    gate = NativeDiagnosticGate(onError: errors.add);
  }

  test('only the prefixes 3.x acted on count', () {
    expect(NativeDiagnosticGate.isActionable('ffmpeg', 'tcp: Connection refused'), isTrue);
    expect(NativeDiagnosticGate.isActionable('ffmpeg', 'hls: skipping'), isFalse);
    expect(NativeDiagnosticGate.isActionable('vd', 'x'), isTrue);
    expect(NativeDiagnosticGate.isActionable('osd/libass', 'x'), isFalse);
  });

  test('terminal failures are reported at once, once per text within two seconds', () {
    fakeAsync((async) {
      setUpGate();
      gate
        ..log('stream', 'error', 'Server returned 404 Not Found')
        ..log('stream', 'error', 'Server returned 404 Not Found')
        ..log('cplayer', 'warn', 'connection refused');
      expect(errors.single.code, 'source_open');
      async.elapse(const Duration(seconds: 3));
      gate.log('stream', 'error', 'Server returned 404 Not Found');
      expect(errors, hasLength(2));
    });
  });

  test('a recoverable decoder error is cancelled by a frame of that decoder', () {
    fakeAsync((async) {
      setUpGate();
      gate
        ..log('vd', 'error', 'Error while decoding frame')
        ..audioFrame();
      async.elapse(const Duration(milliseconds: 500));
      gate.videoFrame();
      async.elapse(const Duration(seconds: 2));
      expect(errors, isEmpty);

      gate.log('vd', 'error', 'Error while decoding frame');
      async.elapse(const Duration(seconds: 2));
      expect(errors.single.code, 'video_decoder_runtime');
    });
  });

  test('a line logged while opening is dropped when its decoder already produced output', () {
    fakeAsync((async) {
      setUpGate();
      gate
        ..beginOpen()
        ..log('ad', 'error', 'Error decoding audio')
        ..audioFrame()
        ..finishOpen();
      async.elapse(const Duration(seconds: 2));
      expect(errors, isEmpty);

      gate
        ..beginOpen()
        ..log('stream', 'error', 'Failed to open https://a.example/live.flv')
        ..finishOpen();
      expect(errors, isEmpty, reason: 'a recoverable failure waits for progress');
      async.elapse(const Duration(seconds: 2));
      expect(errors.single.code, 'source_runtime');
    });
  });
}
