import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart' show FFmpegSession;
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_flv_input_relay.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/ffmpeg_service.dart';

void main() {
  FFmpegRecordSession create({bool live = true, FFmpegHlsInputRelay? hls, FFmpegFlvInputRelay? flv}) =>
      FFmpegRecordSession(
        taskId: 'fixture',
        sessionId: 1,
        session: _NativeSession(),
        liveRecording: live,
        inputRelay: hls,
        flvInputRelay: flv,
      );

  test('natural terminal evidence does not invent a stop or a drain', () {
    final evidence = create().terminalEvidence();
    expect(evidence, {
      'manualStop': false,
      'leaseRefresh': false,
      'stopRequested': false,
      'stopElapsedMs': null,
      'inputDrainKind': 'none',
      'inputDrainBudgetMs': 0,
      'inputFinishRequested': false,
      'forcedCancel': false,
      'inputDrained': false,
      'inputIntegrityError': false,
    });
    expect(() => evidence['manualStop'] = true, throwsUnsupportedError);
  });

  test('cancel without a relay remains distinct from a completed input drain', () {
    final session = create()
      ..manualStop = true
      ..forcedCancel = true;
    session.markStopRequested();
    final evidence = session.terminalEvidence();
    expect(evidence['stopRequested'], true);
    expect(evidence['stopElapsedMs'], greaterThanOrEqualTo(0));
    expect(evidence['manualStop'], true);
    expect(evidence['forcedCancel'], true);
    expect(evidence['inputDrained'], false);
    expect(evidence['inputDrainKind'], 'none');
  });

  test('HLS finished input and packet integrity stay independent in frozen snapshots', () async {
    final relay = (await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:1/fixture.m3u8',
    ], drainOnStop: true))!;
    addTearDown(relay.close);
    final session = create(hls: relay)..manualStop = true;
    session.markStopRequested();
    await relay.finish();
    session.appendDiagnostic('PES packet size mismatch');
    final first = session.terminalEvidence();
    expect(first['inputDrainKind'], 'hls');
    expect(first['inputDrainBudgetMs'], relay.drainTimeout.inMilliseconds);
    expect(first['inputFinishRequested'], true);
    expect(first['inputDrained'], true);
    expect(first['inputIntegrityError'], true);
    session.forcedCancel = true;
    expect(session.terminalEvidence()['inputDrained'], false);
    expect(first['forcedCancel'], false);
    expect(first['inputDrained'], true);
  });

  test('FLV lease drain is observable without being labelled a user stop', () async {
    final relay = (await FFmpegFlvInputRelay.startForArguments(['-i', 'http://127.0.0.1:1/fixture.flv']))!;
    addTearDown(relay.close);
    final session = create(flv: relay)..leaseRefresh = true;
    session.markStopRequested();
    await relay.finish();
    final evidence = session.terminalEvidence();
    expect(evidence['manualStop'], false);
    expect(evidence['leaseRefresh'], true);
    expect(evidence['inputDrainKind'], 'flv');
    expect(evidence['inputDrainBudgetMs'], 3000);
    expect(evidence['inputDrained'], true);
  });

  test('fallback diagnostics disclose only the verdict, never source credentials', () {
    const logs = 'packet corrupt (stream = 1) https://fixture.invalid/live?token=secret Cookie: private';
    expect(create().terminalEvidence(fallbackLogs: logs)['inputIntegrityError'], true);
    expect(create(live: false).terminalEvidence(fallbackLogs: logs)['inputIntegrityError'], false);
    expect(create().terminalEvidence(fallbackLogs: logs).toString(), isNot(contains('secret')));
    expect(create().terminalEvidence(fallbackLogs: logs).toString(), isNot(contains('private')));
  });
}

class _NativeSession implements FFmpegSession {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
