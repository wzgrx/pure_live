import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/services/settings/log_controller.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

void main() {
  test('invalid outgoing header aborts its allocated upstream request before relay close', () async {
    Get.testMode = true;
    Get.put<LogController>(_QuietLog());
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<void>();
    final closed = Completer<void>();
    final sockets = <Socket>[];
    final subscription = server.listen((socket) {
      sockets.add(socket);
      if (!accepted.isCompleted) accepted.complete();
      void ended() {
        if (!closed.isCompleted) closed.complete();
      }

      socket.listen((_) {}, onDone: ended, onError: (Object _) => ended());
    });
    final relay = (await FFmpegHlsInputRelay.startForArguments([
      '-headers',
      'X-Fixture: invalid\u0000value\r\n',
      '-i',
      'http://127.0.0.1:${server.port}/live.m3u8',
    ], drainOnStop: true))!;
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(relay.inputUri)).close();
      expect(response.statusCode, 502);
      await response.drain<void>();
      await accepted.future.timeout(const Duration(seconds: 2));
      await closed.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('Rejected request TCP still open before relay.close'),
      );
      expect(relay.finishRequested, false);
    } finally {
      client.close(force: true);
      await relay.close();
      for (final socket in sockets) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
      Get.reset();
    }
  });
}

class _QuietLog extends GetxController implements LogController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  bool get enableLog => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
