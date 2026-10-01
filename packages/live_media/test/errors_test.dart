import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

// Ported from 3.x's player_error_classifier_test.dart.
void main() {
  group('NativeDiagnostic.classify', () {
    test('does not classify the letters io inside video/audio as network', () {
      final result = NativeDiagnostic.classify('Video decoder rejected this audio/video codec');
      expect(result.type, PlayerErrorType.codec);
      expect(result.immediatelyTerminal, isFalse);
    });

    test('lets hardware initialization recover but fails an unsupported codec', () {
      final hardware = NativeDiagnostic.classify('MediaCodec decoder initialization failed');
      final terminal = NativeDiagnostic.classify('No decoder found for codec av1');
      final packet = NativeDiagnostic.classify('Error while decoding frame: invalid NAL unit');
      expect((hardware.type, hardware.immediatelyTerminal), (PlayerErrorType.codec, false));
      expect((terminal.type, terminal.immediatelyTerminal), (PlayerErrorType.codec, true));
      expect((packet.type, packet.immediatelyTerminal), (PlayerErrorType.codec, false));
    });

    test('uses concrete transport and source markers', () {
      expect(NativeDiagnostic.classify('Input/output error').type, PlayerErrorType.network);
      expect(NativeDiagnostic.classify('Server returned 403 Forbidden').type, PlayerErrorType.source);
      expect(NativeDiagnostic.classify('Error opening input').type, PlayerErrorType.source);
      expect(NativeDiagnostic.classify('Could not find codec parameters').type, PlayerErrorType.source);
    });

    test('recognizes DNS diagnostics and HTTP 5xx as terminal transport failures', () {
      for (final diagnostic in [
        'Error opening input: java.net.UnknownHostException: Unable to resolve host "cdn.example"',
        'getaddrinfo failed: EAI_AGAIN',
        'No such host is known',
        'Server returned 500 Internal Server Error',
        'Failed to open input: Server returned 503 Service Unavailable',
        'HTTP error 504 Gateway Timeout',
      ]) {
        final result = NativeDiagnostic.classify(diagnostic);
        expect(
          (result.type, result.code, result.immediatelyTerminal),
          (PlayerErrorType.network, 'transport', true),
          reason: diagnostic,
        );
      }
    });

    test('keeps audio and video decoder diagnostics in separate recovery lanes', () {
      final audio = NativeDiagnostic.classify('Decoder initialization failed', nativePrefix: 'ad');
      final video = NativeDiagnostic.classify(
        'Error while decoding frame: invalid NAL unit',
        nativePrefix: 'ffmpeg/video',
      );
      expect((audio.component, audio.code), (NativeDiagnosticComponent.audio, 'audio_decoder_runtime'));
      expect((video.component, video.code), (NativeDiagnosticComponent.video, 'video_decoder_runtime'));
    });
  });

  group('classifySourceFailure', () {
    test('stream and account refusals are terminal, transport trouble is transient', () {
      expect(classifySourceFailure(const StreamUnavailable('douyu', 'offline')), SourceFailureKind.terminal);
      expect(classifySourceFailure(const NeedsLogin('bilibili')), SourceFailureKind.terminal);
      expect(classifySourceFailure(const NetworkFailure('douyu', 'reset')), SourceFailureKind.transient);
      expect(classifySourceFailure(const FormatException('bad')), SourceFailureKind.transient);
      expect(
        classifySourceFailure(const TransportFailure('douyu', TransportReason.cancelled)),
        SourceFailureKind.cancelled,
      );
    });
  });

  // Ported from 3.x's player_error_classifier_test.dart (SourceEventFence).
  group('SourceEventFence', () {
    test('accepts events only after the replacement open completes', () {
      final fence = SourceEventFence();
      final generation = fence.begin('https://cdn.example/live.flv');
      expect(fence.accepts(generation), isFalse);
      fence.finishOpen(const [], authorizeSuccessfulOpen: true);
      expect(fence.accepts(generation), isTrue);
      expect(fence.isNativeSourceConfirmed, isFalse, reason: 'the native path is diagnostic only');
    });

    test('a later generation invalidates earlier callbacks; a failed open authorizes nothing', () {
      final fence = SourceEventFence();
      final old = fence.begin('https://cdn.example/live.flv');
      fence.finishOpen(const ['https://cdn.example/live.flv'], authorizeSuccessfulOpen: true);
      final next = fence.begin('https://cdn.example/live.flv');
      fence.finishOpen(const [], authorizeSuccessfulOpen: false);
      expect(fence.accepts(old), isFalse);
      expect(fence.accepts(next), isFalse);
    });

    test('preparation and the final URL keep one generation', () {
      final fence = SourceEventFence();
      final generation = fence.begin(null);
      fence
        ..retargetOpening('https://cdn.example/final.flv')
        ..finishOpen(const ['https://cdn.example/final.flv'], authorizeSuccessfulOpen: true);
      expect(fence.generation, generation);
      expect(fence.isNativeSourceConfirmed, isTrue);
    });
  });
}
