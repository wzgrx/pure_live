import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_cast/live_cast.dart';
import 'package:test/test.dart';

/// A loopback server that hands every raw request to [reply].
Future<ServerSocket> _server(FutureOr<void> Function(String request, Socket socket) reply) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    final buffer = BytesBuilder();
    var answered = false;
    socket.listen((data) {
      buffer.add(data);
      final text = latin1.decode(buffer.toBytes());
      final end = text.indexOf('\r\n\r\n');
      if (answered || end < 0) return;
      final length =
          int.tryParse(
            RegExp(r'^content-length:\s*(\d+)', caseSensitive: false, multiLine: true).firstMatch(text)?.group(1) ??
                '0',
          ) ??
          0;
      if (buffer.length < end + 4 + length) return;
      answered = true;
      unawaited(Future.sync(() => reply(utf8.decode(buffer.toBytes()), socket)));
    }, onError: (Object _) {});
  });
  return server;
}

void main() {
  late IoCastHttp http;

  setUp(() => http = IoCastHttp(maxBody: 1024));
  tearDown(() => http.close());

  test('sends the body and keeps header case; reads status and UTF-8 body', () async {
    String? seen;
    final server = await _server((request, socket) async {
      seen = request;
      const body = '<ok>好</ok>';
      socket.add(
        utf8.encode(
          'HTTP/1.1 500 Internal Server Error\r\nContent-Length: ${utf8.encode(body).length}\r\n'
          'Connection: close\r\n\r\n$body',
        ),
      );
      await socket.close();
    });
    addTearDown(server.close);
    final response = await http.send(
      'POST',
      Uri.parse('http://127.0.0.1:${server.port}/ctl'),
      timeout: const Duration(seconds: 5),
      headers: {'SOAPAction': '"urn:x#Play"', 'Content-Type': 'text/xml; charset="utf-8"'},
      body: '<Play>播放</Play>',
    );
    expect(response.statusCode, 500);
    expect(response.isSuccess, isFalse);
    expect(response.body, '<ok>好</ok>');
    expect(seen, startsWith('POST /ctl HTTP/1.1\r\n'));
    expect(seen, contains('\r\nSOAPAction: "urn:x#Play"\r\n'));
    expect(seen, contains('\r\nContent-Type: text/xml; charset="utf-8"\r\n'));
    expect(seen, endsWith('\r\n\r\n<Play>播放</Play>'));
  });

  test('a device that never answers times out', () async {
    final server = await _server((request, socket) {});
    addTearDown(server.close);
    await expectLater(
      http.send('GET', Uri.parse('http://127.0.0.1:${server.port}/d.xml'), timeout: const Duration(milliseconds: 200)),
      throwsA(
        isA<CastTimeoutFailure>().having((failure) => failure.timeout, 'timeout', const Duration(milliseconds: 200)),
      ),
    );
  });

  test('an oversized body is a protocol failure', () async {
    final server = await _server((request, socket) async {
      socket.add(ascii.encode('HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n${'x' * 4096}'));
      await socket.close();
    });
    addTearDown(server.close);
    await expectLater(
      http.send('GET', Uri.parse('http://127.0.0.1:${server.port}/d.xml'), timeout: const Duration(seconds: 5)),
      throwsA(isA<CastProtocolFailure>()),
    );
  });

  test('a refused connection is a network failure; a closed client refuses', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    await expectLater(
      http.send('GET', Uri.parse('http://127.0.0.1:$port/d.xml'), timeout: const Duration(seconds: 5)),
      throwsA(isA<CastNetworkFailure>()),
    );
    http.close();
    await expectLater(
      http.send('GET', Uri.parse('http://127.0.0.1:$port/d.xml'), timeout: const Duration(seconds: 5)),
      throwsA(isA<CastNetworkFailure>()),
    );
  });
}
