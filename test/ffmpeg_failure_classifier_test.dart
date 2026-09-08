import 'package:flutter_test/flutter_test.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart' show FFmpegSession;
import 'package:pure_live/recorder/services/ffmpeg_service.dart';

void main() {
  test('missing picture access units are packet and output integrity failures', () {
    for (final message in [
      '[h264] missing picture in access unit with size 36',
      '[HEVC] MISSING PICTURE IN ACCESS UNIT WITH SIZE 37',
    ]) {
      expect(FFmpegMediaIntegrity.hasError(message), true, reason: message);
      expect(FFmpegMediaIntegrity.hasPacketError(message), true, reason: message);
    }
  });

  test('missing picture verdict survives log eviction without contaminating next session', () {
    final broken = FFmpegRecordSession(taskId: 'broken', sessionId: 1, session: _NativeSession(), liveRecording: true);
    broken.appendDiagnostic('[h264] missing picture in access unit with size 36', maxLines: 1);
    broken.appendDiagnostic('frame=256', maxLines: 1);
    expect(broken.diagnosticTail, 'frame=256');
    expect(broken.hasMediaIntegrityError, true);
    expect(broken.terminalEvidence()['inputIntegrityError'], true);
    final fresh = FFmpegRecordSession(taskId: 'fresh', sessionId: 2, session: _NativeSession(), liveRecording: true);
    expect(fresh.hasMediaIntegrityError, false);
    expect(fresh.terminalEvidence()['inputIntegrityError'], false);
  });

  test('live packet damage is latched separately from ordinary stop IO', () {
    final session = FFmpegRecordSession(
      taskId: 'picarto_fixture',
      sessionId: 1,
      session: _NativeSession(),
      liveRecording: true,
    );
    session.appendDiagnostic('[in#0/hls] Error during demuxing: I/O error', maxLines: 1);
    expect(session.hasMediaIntegrityError, true);
    expect(session.hasInputPacketError, false);
    session.appendDiagnostic('[mpegts] packet corrupt (stream = 1, dts = 3092510880), dropping it.', maxLines: 1);
    session.appendDiagnostic('frame=661', maxLines: 1);
    expect(session.diagnosticTail, 'frame=661');
    expect(session.hasInputPacketError, true);
    expect(
      FFmpegRecordSession(
        taskId: 'next',
        sessionId: 2,
        session: _NativeSession(),
        liveRecording: true,
      ).hasInputPacketError,
      false,
    );
    expect(FFmpegMediaIntegrity.hasPacketError('Non-monotonic DTS corrected'), false);
    expect(FFmpegMediaIntegrity.hasPacketError('PES packet size mismatch'), true);
    expect(FFmpegMediaIntegrity.hasPacketError('error while decoding MB 59 40, bytestream -25'), true);
  });
  test('integrity verdict survives bounded log eviction and stays session-local', () {
    FFmpegRecordSession create(int id) =>
        FFmpegRecordSession(taskId: 'fixture', sessionId: id, session: _NativeSession(), liveRecording: false);
    final damaged = create(1);
    damaged.appendDiagnostic('[mpegts] PES packet size mismatch', maxLines: 1);
    damaged.appendDiagnostic('frame=1000', maxLines: 1);
    expect(damaged.diagnosticTail, 'frame=1000');
    expect(damaged.hasMediaIntegrityError, true);
    expect(create(2).hasMediaIntegrityError, false);
  });
  test('strict output integrity failure overrides a zero native result', () {
    for (final stopped in [false, true]) {
      final decision = FFmpegTerminalDecision.forSession(
        code: 0,
        manuallyStopped: stopped,
        liveRecording: false,
        corruptOutput: true,
      );
      expect(decision.isComplete, false);
      expect(decision.retryable, false);
    }
  });

  test('integrity guard recognises actual packet/trailer errors but not ordinary warnings', () {
    for (final log in [
      '[mpegts] PES packet size mismatch',
      '[mpegts] Packet corrupt (stream = 1, dts = 2722007).',
      '[concat] corrupt input packet in stream 1',
      '[segment] Error writing trailer: Immediate exit requested',
    ]) {
      expect(FFmpegMediaIntegrity.hasError(log), true);
    }
    for (final log in [
      'task_stop: pthread_join esrch; task completion observed through scheduler signal',
      'deprecated pixel format used',
      'Non-monotonic DTS corrected',
      'frame=600 time=00:00:10',
    ]) {
      expect(FFmpegMediaIntegrity.hasError(log), false);
    }
  });
  test('FFmpeg diagnostics distinguish output configuration from retryable input failures', () {
    final output = FFmpegFailureClassifier.classify(
      code: 1,
      logs: 'Error opening output /storage/emulated/0/PureLive/segment.ts: Permission denied',
    );
    final input = FFmpegFailureClassifier.classify(code: 1, logs: 'Error opening input https://cdn.example/live.flv');

    expect(output.kind, FFmpegFailureKind.outputPath);
    expect(output.retryable, isFalse);
    expect(input.kind, FFmpegFailureKind.inputOpen);
    expect(input.retryable, isTrue);
  });

  test('HTTP, transport, format and decoder failures remain separately observable', () {
    expect(
      FFmpegFailureClassifier.classify(code: 1, logs: 'Server returned 403 Forbidden').kind,
      FFmpegFailureKind.httpAccess,
    );
    expect(FFmpegFailureClassifier.classify(code: 1, logs: 'TLS handshake failed').kind, FFmpegFailureKind.transport);
    expect(
      FFmpegFailureClassifier.classify(code: 1, logs: 'Invalid data found when processing input').kind,
      FFmpegFailureKind.inputFormat,
    );
    expect(
      FFmpegFailureClassifier.classify(code: 1, logs: 'Decoder failed for codec h264').kind,
      FFmpegFailureKind.decoder,
    );
  });

  test('a native minus-two exit is not assumed to be an output path failure', () {
    final unknown = FFmpegFailureClassifier.classify(code: -2, logs: 'native session returned ENOENT');
    final input = FFmpegFailureClassifier.classify(code: -2, logs: 'Error opening input: No such file or directory');

    expect(unknown.kind, FFmpegFailureKind.native);
    expect(unknown.retryable, isTrue);
    expect(input.kind, FFmpegFailureKind.inputOpen);
    expect(input.retryable, isTrue);
  });

  test('input Invalid argument remains retryable unless option parsing proves a command defect', () {
    final input = FFmpegFailureClassifier.classify(
      code: 1,
      logs: 'Error opening input https://cdn.example/live: Invalid argument',
    );
    final ambiguous = FFmpegFailureClassifier.classify(code: 1, logs: 'live input failed: Invalid argument');
    final command = FFmpegFailureClassifier.classify(code: 1, logs: 'Unrecognized option rw_timeout');

    expect(input.kind, FFmpegFailureKind.inputOpen);
    expect(input.retryable, isTrue);
    expect(ambiguous.kind, FFmpegFailureKind.native);
    expect(ambiguous.retryable, isTrue);
    expect(command.kind, FFmpegFailureKind.command);
    expect(command.retryable, isFalse);
  });

  test('live recorder accepts only an explicit stop as successful completion', () {
    final userStop = FFmpegTerminalDecision.forSession(code: 255, manuallyStopped: true, liveRecording: true);
    final cleanEof = FFmpegTerminalDecision.forSession(code: 0, manuallyStopped: false, liveRecording: true);
    final avEof = FFmpegTerminalDecision.forSession(code: -541478725, manuallyStopped: false, liveRecording: true);
    final nativeFailure = FFmpegTerminalDecision.forSession(code: 1, manuallyStopped: false, liveRecording: true);
    final completedMerge = FFmpegTerminalDecision.forSession(code: 0, manuallyStopped: false, liveRecording: false);
    final leaseRotation = FFmpegTerminalDecision.forSession(
      code: 255,
      manuallyStopped: false,
      liveRecording: true,
      leaseRefresh: true,
    );

    expect(userStop.isComplete, isTrue);
    expect(userStop.unexpectedEof, isFalse);
    expect(cleanEof.isComplete, isFalse);
    expect(cleanEof.unexpectedEof, isTrue);
    expect(cleanEof.retryable, isTrue);
    expect(avEof.unexpectedEof, isTrue);
    expect(nativeFailure.isComplete, isFalse);
    expect(nativeFailure.unexpectedEof, isFalse);
    expect(completedMerge.isComplete, isTrue);
    expect(completedMerge.unexpectedEof, isFalse);
    expect(leaseRotation.isComplete, isFalse);
    expect(leaseRotation.retryable, isTrue);
    expect(leaseRotation.unexpectedEof, isTrue);
  });
}

class _NativeSession implements FFmpegSession {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
