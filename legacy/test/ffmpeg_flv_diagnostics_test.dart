import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_flv_input_relay.dart';

const header = <int>[0x46, 0x4c, 0x56, 1, 5, 0, 0, 0, 9, 0, 0, 0, 0];
const tag = <int>[9, 0, 0, 3, 0, 0, 1, 0, 0, 0, 0, 1, 2, 3, 0, 0, 0, 14];

void main() {
  test('capture budget is explicit and bounded', () {
    expect(() => FlvRelayDiagnostics(maxCaptureBytes: -1), throwsRangeError);
    expect(() => FlvRelayDiagnostics(maxCaptureBytes: 64 * 1024 * 1024 + 1), throwsRangeError);
  });

  for (final budget in [0, header.length - 1, header.length, header.length + tag.length, 100]) {
    test('budget $budget preserves forwarding and complete-record capture prefix', () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = [...header, ...tag, ...tag];
      final subscription = origin.listen((request) async {
        request.response.add([...bytes, ...tag.take(12)]);
        await request.response.close();
      });
      final diagnostics = FlvRelayDiagnostics(maxCaptureBytes: budget);
      final relay = await FFmpegFlvInputRelay.startForArguments([
        '-i',
        'http://127.0.0.1:${origin.port}/live.flv',
      ], diagnostics: diagnostics);
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(relay!.inputUri)).close();
        final received = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
        expect(received, bytes);
        expect(diagnostics.submittedBytes, bytes.length);
        expect(diagnostics.submittedBytes, relay.forwardedBytes);
        expect(diagnostics.submittedPackets, 3);
        final retained = budget < header.length
            ? 0
            : header.length + ((budget - header.length) ~/ tag.length).clamp(0, 2) * tag.length;
        expect(diagnostics.capturedBytes, bytes.take(retained));
        expect(diagnostics.truncated, retained != bytes.length);
        final copy = diagnostics.capturedBytes;
        if (copy.isNotEmpty) {
          copy[0] = 0;
          expect(diagnostics.capturedBytes.first, 0x46);
        }
        await expectLater(
          FFmpegFlvInputRelay.startForArguments(['-i', 'http://127.0.0.1:1/live.flv'], diagnostics: diagnostics),
          throwsStateError,
        );
      } finally {
        client.close(force: true);
        await relay?.close();
        await subscription.cancel();
        await origin.close(force: true);
      }
    });
  }

  test('non-FLV input does not consume diagnostic ownership; pre-connect stop captures nothing', () async {
    final diagnostics = FlvRelayDiagnostics(maxCaptureBytes: 100);
    expect(
      await FFmpegFlvInputRelay.startForArguments(['-i', 'http://127.0.0.1:1/live.m3u8'], diagnostics: diagnostics),
      isNull,
    );
    final relay = await FFmpegFlvInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:1/live.flv',
    ], diagnostics: diagnostics);
    try {
      await relay!.finish();
      expect(diagnostics.capturedBytes, isEmpty);
      expect(diagnostics.submittedPackets, 0);
      expect(diagnostics.truncated, false);
    } finally {
      await relay?.close();
    }
  });
}
