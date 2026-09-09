import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

void main() {
  test('capacity rejection cancels the unread upstream body before stopping other requests', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final peerClosed = <int>{};
    final subscription = server.listen((socket) {
      sockets.add(socket);
      var header = '';
      var replied = false;
      int? index;
      socket.listen(
        (bytes) {
          if (replied) return;
          header += ascii.decode(bytes);
          if (!header.contains('\r\n\r\n')) return;
          replied = true;
          final path = header.split(' ')[1];
          if (path == '/live.m3u8') {
            final manifest =
                '#EXTM3U\n#EXT-X-TARGETDURATION:1\n'
                '${List.generate(9, (i) => '#EXTINF:1,\n$i.m4s\n').join()}';
            socket.add(
              ascii.encode(
                'HTTP/1.1 200 OK\r\nContent-Length: ${manifest.length}\r\nConnection: close\r\n\r\n$manifest',
              ),
            );
            unawaited(socket.flush().then((_) => socket.close()));
          } else {
            index = int.parse(path.substring(1).split('.').first);
            socket.add(ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\na'));
            unawaited(socket.flush());
          }
        },
        onDone: () {
          if (index != null) peerClosed.add(index!);
        },
        onError: (Object _) {
          if (index != null) peerClosed.add(index!);
        },
      );
    });
    final client = HttpClient()..maxConnectionsPerHost = 16;
    final relay = (await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:${server.port}/live.m3u8',
    ], drainOnStop: true))!;
    final requests = <Future<int>>[];
    try {
      final manifest = await (await (await client.getUrl(relay.inputUri)).close()).transform(utf8.decoder).join();
      final media = const LineSplitter()
          .convert(manifest)
          .where((line) => line.startsWith('http'))
          .map(Uri.parse)
          .toList();
      for (var i = 0; i < 8; i++) {
        requests.add(() async {
          try {
            final response = await (await client.getUrl(media[i])).close();
            await response.drain<void>();
            return response.statusCode;
          } on Object {
            return -1;
          }
        }());
      }
      await _until(() => relay.stagingBodyCount == 8, 'eight active bodies');
      final rejected = await (await client.getUrl(media[8])).close();
      expect(rejected.statusCode, 503);
      expect(await rejected.fold<int>(0, (sum, bytes) => sum + bytes.length), 0);
      await _until(() => peerClosed.contains(8), 'ninth body TCP cancellation before finish');
      expect(relay.finishRequested, false);
      expect(relay.stagingBodyCount, 8);
      expect(peerClosed.where((i) => i < 8), isEmpty);
      await relay.finish();
      expect(await Future.wait(requests), everyElement(410));
    } finally {
      await relay.close();
      client.close(force: true);
      await Future.wait(requests);
      for (final socket in sockets) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
    }
  });
}

Future<void> _until(bool Function() predicate, String transition) async {
  final watch = Stopwatch()..start();
  while (!predicate() && watch.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(predicate(), true, reason: transition);
}
