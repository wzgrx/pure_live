import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

// Regression promoted after owned network cancellation fixes the stalled TLS
// path. A prompt input result alone never substitutes for peer disconnection.

void main() {
  test('stop retires a stalled TLS handshake before an upstream request exists', () async {
    final handshake = Completer<void>();
    final disconnected = Completer<void>();
    final sockets = <Socket>[];
    final blackhole = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final blackholeSubscription = blackhole.listen((socket) {
      sockets.add(socket);
      socket.listen(
        (bytes) {
          if (bytes.isNotEmpty && !handshake.isCompleted) handshake.complete();
          // Read ClientHello, but deliberately never send ServerHello.
        },
        onError: (Object _) {},
        onDone: () {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
    });
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final originSubscription = origin.listen((request) async {
      if (request.uri.path == '/healthy.m3u8') {
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nhealthy.ts\n');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/healthy.ts') {
        request.response.write('healthy');
        await request.response.close();
        return;
      }
      request.response.write(
        '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\n'
        'https://127.0.0.1:${blackhole.port}/media.m4s\n',
      );
      await request.response.close();
    });
    final relay = (await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:${origin.port}/live.m3u8',
    ], drainOnStop: true))!;
    final other = (await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:${origin.port}/healthy.m3u8',
    ], drainOnStop: true))!;
    final client = HttpClient();
    try {
      final otherManifest = await _text(client, other.inputUri);
      final otherMedia = Uri.parse(
        const LineSplitter().convert(otherManifest).lastWhere((line) => !line.startsWith('#')),
      );
      expect(await _text(client, otherMedia), 'healthy');
      final manifest = await _text(client, relay.inputUri);
      final media = Uri.parse(const LineSplitter().convert(manifest).lastWhere((line) => !line.startsWith('#')));
      final pending = (await client.getUrl(media)).close();
      await handshake.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw StateError('ClientHello not observed'),
      );
      await relay.finish();
      final response = await pending.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Stop budget expired after ClientHello was observed'),
      );
      expect(response.statusCode, HttpStatus.gone);
      expect(await response.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      expect(relay.inputTailDiscarded, true);
      expect(await _text(client, relay.inputUri), contains('#EXT-X-ENDLIST'));
      await disconnected.future.timeout(const Duration(seconds: 3));
      expect(await _text(client, otherMedia), 'healthy');
      expect(other.finishRequested, false);
      expect(other.inputTailDiscarded, false);
    } finally {
      for (final socket in sockets) {
        socket.destroy();
      }
      client.close(force: true);
      await relay.close().timeout(const Duration(seconds: 3));
      await other.close();
      await origin.close(force: true);
      await originSubscription.cancel();
      await blackhole.close();
      await blackholeSubscription.cancel();
    }
  });
}

Future<String> _text(HttpClient client, Uri uri) async =>
    utf8.decoder.bind(await (await client.getUrl(uri)).close()).join();
