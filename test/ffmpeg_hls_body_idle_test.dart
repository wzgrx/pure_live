import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

void main() {
  for (final recording in [true, false]) {
    test('only recording rewrites the loopback input budget; output options and original args remain intact', () async {
      const source = [
        '-rw_timeout',
        '10000000',
        '-rw_timeout',
        '15000000',
        '-i',
        'http://127.0.0.1:1/live.m3u8',
        '-rw_timeout',
        '1',
        'out.ts',
      ];
      final relay = (await FFmpegHlsInputRelay.startForArguments(source, force: true, drainOnStop: recording))!;
      addTearDown(relay.close);
      expect(relay.replaceFirstInput(source), [
        '-rw_timeout',
        recording ? '80000000' : '10000000',
        '-rw_timeout',
        recording ? '80000000' : '15000000',
        '-i',
        relay.inputUri.toString(),
        '-rw_timeout',
        '1',
        'out.ts',
      ]);
      expect(source[1], '10000000');
      expect(source[5], 'http://127.0.0.1:1/live.m3u8');
    });
  }
  test('recording without a supplied timeout installs a bounded loopback default', () async {
    const source = ['-i', 'http://127.0.0.1:1/live.m3u8', 'out.ts'];
    final relay = (await FFmpegHlsInputRelay.startForArguments(source, drainOnStop: true))!;
    addTearDown(relay.close);
    expect(relay.replaceFirstInput(source), ['-rw_timeout', '80000000', '-i', relay.inputUri.toString(), 'out.ts']);
  });
  for (final manifest in [false, true]) {
    test('recording retires a stalled ${manifest ? 'manifest' : 'spilled media'} body without stop', () async {
      final fixture = await _Fixture.create(stallManifest: manifest);
      addTearDown(fixture.close);
      final uri = manifest ? fixture.relay.inputUri : await fixture.media();
      final response = await (await fixture.client.getUrl(uri)).close().timeout(const Duration(seconds: 3));
      expect(response.statusCode, HttpStatus.gatewayTimeout);
      expect(await response.fold<int>(0, (n, bytes) => n + bytes.length), 0);
      await fixture.disconnected.future.timeout(const Duration(seconds: 3));
      await _until(() => fixture.relay.stagingBodyCount == 0);
      expect(await fixture.root.list().isEmpty, true);
      expect(fixture.relay.finishRequested, false);
      expect(fixture.relay.inputTailDiscarded, false);
      expect(fixture.allocations, manifest ? 0 : 1);
      // A single timed-out response must not close this relay's shared client.
      fixture.healthy = true;
      final next = await fixture.text(fixture.relay.inputUri);
      expect(next, contains('#EXTINF:1,'));
      expect(await fixture.text(await fixture.media()), 'healthy');
    });
  }

  test('continuous body delivery can exceed its idle budget and publishes exact bytes once complete', () async {
    final fixture = await _Fixture.create(continuous: true);
    addTearDown(fixture.close);
    final response = await (await fixture.client.getUrl(await fixture.media())).close();
    expect(response.statusCode, HttpStatus.ok);
    expect(await utf8.decoder.bind(response).join(), '01234567');
    expect(fixture.bodyWatch.elapsedMilliseconds, greaterThan(700));
    expect(fixture.relay.inputTailDiscarded, false);
    await _until(() => fixture.relay.stagingBodyCount == 0);
  });

  test('continuous trickle has a finite response deadline even while every read makes progress', () async {
    final fixture = await _Fixture.create(continuous: true, chunks: 64);
    addTearDown(fixture.close);
    final response = await (await fixture.client.getUrl(await fixture.media()))
        .close()
        .timeout(const Duration(seconds: 4));
    expect(response.statusCode, HttpStatus.gatewayTimeout);
    expect(await response.fold<int>(0, (n, bytes) => n + bytes.length), 0);
    await fixture.disconnected.future.timeout(const Duration(seconds: 3));
    await _until(() => fixture.relay.stagingBodyCount == 0);
    expect(fixture.relay.inputTailDiscarded, false);
  });

  for (final redirects in [0, 5]) {
    test('response budget covers ${redirects == 0 ? 'idle headers' : 'cumulative redirects'}', () async {
      final fixture = await _Fixture.create(
        headerDelay: Duration(milliseconds: redirects == 0 ? 1100 : 350),
        redirects: redirects,
      );
      addTearDown(fixture.close);
      final response = await (await fixture.client.getUrl(fixture.relay.inputUri))
          .close()
          .timeout(const Duration(seconds: 4));
      expect(response.statusCode, HttpStatus.gatewayTimeout);
      expect(await response.fold<int>(0, (n, bytes) => n + bytes.length), 0);
      await fixture.disconnected.future.timeout(const Duration(seconds: 3));
      fixture.healthy = true;
      expect(await fixture.text(await fixture.media()), 'healthy');
    });
  }
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), true);
}

class _Fixture {
  _Fixture(this.stallManifest, this.continuous, this.chunks, this.headerDelay, this.redirects);
  final bool stallManifest;
  final bool continuous;
  final int chunks;
  final Duration headerDelay;
  final int redirects;
  final client = HttpClient();
  final disconnected = Completer<void>();
  final sockets = <Socket>{};
  final closedByServer = <Socket>{};
  final handlers = <Future<void>>{};
  final bodyWatch = Stopwatch();
  late ServerSocket origin;
  late StreamSubscription<Socket> subscription;
  late FFmpegHlsInputRelay relay;
  late Directory root;
  bool healthy = false;
  int allocations = 0;

  static Future<_Fixture> create({
    bool stallManifest = false,
    bool continuous = false,
    int chunks = 8,
    Duration headerDelay = Duration.zero,
    int redirects = 0,
  }) async {
    final fixture = _Fixture(stallManifest, continuous, chunks, headerDelay, redirects);
    fixture.root = await Directory.systemTemp.createTemp('hls-body-idle-');
    fixture.origin = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    fixture.subscription = fixture.origin.listen(fixture.accept);
    fixture.relay = (await FFmpegHlsInputRelay.startForArguments(
      [
        '-rw_timeout', '500000', '-i', 'http://127.0.0.1:${fixture.origin.port}/live.m3u8',
        // Output-side options must not become the first input's timeout.
        '-rw_timeout', '1', 'output.ts',
      ],
      drainOnStop: true,
      createStagingDirectory: () async {
        fixture.allocations++;
        return fixture.root.createTemp('owned-');
      },
    ))!;
    return fixture;
  }

  Future<String> text(Uri uri) async => utf8.decoder.bind(await (await client.getUrl(uri)).close()).join();
  Future<Uri> media() async =>
      Uri.parse(const LineSplitter().convert(await text(relay.inputUri)).lastWhere((line) => !line.startsWith('#')));

  void accept(Socket socket) {
    sockets.add(socket);
    var headers = '';
    var served = false;
    var stalled = false;
    socket.listen(
      (bytes) {
        if (served) return;
        headers += latin1.decode(bytes);
        if (!headers.contains('\r\n\r\n')) return;
        served = true;
        final path = headers.split(' ')[1];
        stalled = !healthy && (Uri.parse(path).path.endsWith('.m3u8') ? stallManifest : !continuous);
        late Future<void> work;
        work = serve(socket, path, stalled).whenComplete(() => handlers.remove(work));
        handlers.add(work);
      },
      onError: (Object _) {},
      onDone: () {
        if (!closedByServer.contains(socket) &&
            (stalled || continuous || headerDelay > Duration.zero) &&
            !disconnected.isCompleted) {
          disconnected.complete();
        }
        sockets.remove(socket);
        socket.destroy();
      },
    );
  }

  Future<void> serve(Socket socket, String path, bool stalled) async {
    try {
      final manifest = Uri.parse(path).path.endsWith('.m3u8');
      if (!healthy && headerDelay > Duration.zero) await Future<void>.delayed(headerDelay);
      if (!sockets.contains(socket)) return;
      final step = int.tryParse(Uri.parse(path).queryParameters['step'] ?? '') ?? 0;
      if (!healthy && step < redirects) {
        socket.write(
          'HTTP/1.1 302 Found\r\nConnection: close\r\nLocation: /live.m3u8?step=${step + 1}\r\nContent-Length: 0\r\n\r\n',
        );
        await socket.flush();
        closedByServer.add(socket);
        await socket.close();
        return;
      }
      final text = manifest ? '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nbody.m4s\n' : 'healthy';
      final body = stalled && !manifest ? Uint8List(3 * 1024 * 1024) : utf8.encode(text);
      final drip = continuous && !manifest && !healthy;
      socket.write(
        'HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: ${drip ? chunks : body.length + (stalled ? 1 : 0)}\r\n\r\n',
      );
      if (drip) {
        bodyWatch.start();
        for (var i = 0; i < chunks && sockets.contains(socket); i++) {
          socket.add([48 + i % 10]);
          await socket.flush();
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        bodyWatch.stop();
      } else {
        socket.add(body);
        await socket.flush();
      }
      if (!stalled) {
        closedByServer.add(socket);
        await socket.close();
      }
    } on Object {
      // Peer cancellation is observed independently by the read-side onDone.
    }
  }

  Future<void> close() async {
    client.close(force: true);
    await relay.close();
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    await origin.close();
    await subscription.cancel();
    await Future.wait(handlers.toList());
    await root.delete(recursive: true);
  }
}
