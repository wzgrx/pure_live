import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';
import 'package:pure_live/recorder/services/niconico_hls_input.dart';

void main() {
  Future<void> serverTest(Future<void> Function(HttpServer server, Uri source) body) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      await body(server, Uri.parse('http://127.0.0.1:${server.port}/master.m3u8'));
    } finally {
      await server.close(force: true);
    }
  }

  for (final mode in ['ok', 'status', 'oversize', 'utf8', 'redirect']) {
    test(
      'master response $mode has strict bounded body ownership',
      () => serverTest((server, source) async {
        var requests = 0;
        final sub = server.listen((request) async {
          requests++;
          expect(request.headers.value(HttpHeaders.cookieHeader), 'session=fixture');
          if (mode == 'status') request.response.statusCode = 403;
          if (mode == 'redirect' && request.uri.path == '/master.m3u8') {
            request.response.statusCode = 302;
            request.response.headers.set('location', '/other.m3u8');
          } else {
            final bytes = mode == 'oversize'
                ? List<int>.filled(4 * 1024 * 1024 + 1, 32)
                : mode == 'utf8'
                ? <int>[255]
                : utf8.encode('#EXTM3U\n');
            request.response.add(bytes);
          }
          try {
            await request.response.close();
          } catch (_) {
            /* reader may reject before drain */
          }
        });
        try {
          final result = readNiconicoMaster(source, (_) => 'session=fixture', CancelToken(), (_) => 'DIRECT');
          if (mode == 'ok') {
            expect(await result, '#EXTM3U\n');
          } else {
            await expectLater(result, mode == 'utf8' ? throwsFormatException : throwsA(isA<NiconicoException>()));
          }
          expect(requests, mode == 'redirect' ? 2 : 1);
        } finally {
          await sub.cancel();
        }
      }),
    );
  }
  for (final stage in ['headers', 'body']) {
    test(
      'cancellation during $stage retires pending HTTP response',
      () => serverTest((server, source) async {
        final arrived = Completer<HttpRequest>();
        final sub = server.listen(arrived.complete);
        final cancel = CancelToken();
        final result = expectLater(
          readNiconicoMaster(source, (_) => null, cancel, (_) => 'DIRECT'),
          throwsA(isA<NiconicoException>().having((e) => e.kind, 'kind', NiconicoFailure.cancelled)),
        );
        try {
          final request = await arrived.future;
          if (stage == 'body') {
            request.response.write('#EXTM3U\n');
            await request.response.flush();
          }
          cancel.cancel();
          await result.timeout(const Duration(seconds: 3));
          // Socket retirement, rather than waiting for the body idle deadline.
          try {
            await request.response.close();
          } catch (_) {
            /* canceled peer */
          }
        } finally {
          await sub.cancel();
        }
      }),
    );
  }
  test('pre-cancel does not invoke proxy or grant callbacks', () async {
    await expectLater(
      readNiconicoMaster(
        Uri.parse('https://example.test/master.m3u8'),
        (_) => throw StateError('cookie callback'),
        CancelToken()..cancel(),
        (_) => throw StateError('proxy callback'),
      ),
      throwsA(isA<NiconicoException>().having((e) => e.kind, 'kind', NiconicoFailure.cancelled)),
    );
  });
}
