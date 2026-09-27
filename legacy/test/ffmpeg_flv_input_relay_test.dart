import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_flv_input_relay.dart';

const _header = <int>[0x46, 0x4c, 0x56, 1, 5, 0, 0, 0, 9, 0, 0, 0, 0];
List<int> _tag(List<int> payload) => [
  9,
  payload.length >> 16,
  (payload.length >> 8) & 255,
  payload.length & 255,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  ...payload,
  0,
  0,
  (11 + payload.length) >> 8,
  (11 + payload.length) & 255,
];

void main() {
  test('framing preserves every header/tag byte across arbitrary network boundaries', () {
    final bytes = [
      ..._header,
      ..._tag([1, 2, 3]),
      ..._tag([]),
      ..._tag(List.generate(1000, (i) => i % 256)),
    ];
    for (final step in [1, 2, 7, 11, 13, 97, bytes.length]) {
      final framer = FlvInputFramer();
      final packets = <Uint8List>[];
      for (var i = 0; i < bytes.length; i += step) {
        packets.addAll(framer.add(bytes.sublist(i, (i + step).clamp(0, bytes.length))));
      }
      expect(packets, hasLength(4));
      expect(packets.expand((bytes) => bytes), bytes);
      expect(framer.pendingBytes, 0);
    }
  });

  test('an incomplete tag is retained, never forwarded as recorded media', () {
    final framer = FlvInputFramer();
    final tag = _tag([1, 2, 3, 4]);
    expect(framer.add([..._header, ...tag.take(14)]).expand((p) => p), _header);
    expect(framer.pendingBytes, 14);
    expect(framer.add(tag.skip(14).toList()).single, tag);
    expect(framer.pendingBytes, 0);
  });

  test('framing rejects invalid headers and unbounded header lengths', () {
    for (final bytes in [
      [0, ..._header.skip(1)],
      [..._header.take(5), 255, 255, 255, 255],
    ]) {
      expect(() => FlvInputFramer().add(bytes).toList(), throwsFormatException);
    }
  });

  test('long input has no accumulation after complete tags', () {
    final framer = FlvInputFramer();
    framer.add(_header).toList();
    for (var i = 0; i < 10000; i++) {
      expect(framer.add(_tag([1, 2, 3])).length, 1);
      expect(framer.pendingBytes, 0);
    }
  });

  test('legacy previous-tag-size values are preserved for the native demuxer', () {
    final tag = _tag([1, 2, 3]);
    final legacy = [...tag.take(tag.length - 4), 0, 0, 0, 0];
    final framer = FlvInputFramer();
    expect(framer.add([..._header, ...legacy]).expand((p) => p), [..._header, ...legacy]);
    expect(framer.pendingBytes, 0);
  });

  test('loopback retries are removed while timeout and output settings are retained', () async {
    final args = [
      '-reconnect',
      '1',
      '-reconnect_streamed',
      '1',
      '-rw_timeout',
      '5000000',
      '-i',
      'http://127.0.0.1:1/live.flv',
      '-c',
      'copy',
      '-f',
      'segment',
      'output.ts',
    ];
    final relay = await FFmpegFlvInputRelay.startForArguments(args);
    try {
      expect(relay!.replaceFirstInput(args), [
        '-rw_timeout',
        '5000000',
        '-i',
        relay.inputUri.toString(),
        '-c',
        'copy',
        '-f',
        'segment',
        'output.ts',
      ]);
      expect(args.first, '-reconnect');
    } finally {
      await relay?.close();
    }
  });

  test('two relays have isolated lifetimes and HTTP errors remain errors', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var calls = 0;
    final subscription = origin.listen((request) async {
      calls++;
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    });
    final args = ['-i', 'http://127.0.0.1:${origin.port}/live.flv'];
    final first = await FFmpegFlvInputRelay.startForArguments(args);
    final second = await FFmpegFlvInputRelay.startForArguments(args);
    final client = HttpClient();
    try {
      await first!.finish();
      final rejected = await (await client.getUrl(second!.inputUri.replace(path: '/wrong/live.flv'))).close();
      expect(rejected.statusCode, HttpStatus.notFound);
      await rejected.drain<void>();
      expect(calls, 0);
      final response = await (await client.getUrl(second.inputUri)).close();
      expect(response.statusCode, HttpStatus.forbidden);
      await response.drain<void>();
      expect(calls, 1);
      expect(second.finishRequested, false);
    } finally {
      client.close(force: true);
      await first?.close();
      await second?.close();
      await origin.close(force: true);
      await subscription.cancel();
    }
  });

  test('relay ends at the last complete tag when stopping a stalled partial input', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final prefix = [
      ..._header,
      ..._tag([1, 2, 3]),
    ];
    final partial = _tag(List.filled(30, 9)).take(20).toList();
    String? userAgent;
    String? referer;
    final sourceSubscription = origin.listen((request) async {
      userAgent = request.headers.value('user-agent');
      referer = request.headers.value('referer');
      request.response.bufferOutput = false;
      request.response.add([...prefix, ...partial]);
      await request.response.flush();
    });
    final relay = await FFmpegFlvInputRelay.startForArguments([
      '-user_agent',
      'fixture-native',
      '-headers',
      'Referer: https://fixture.example/\r\nHost: invalid.example\r\n',
      '-i',
      'http://127.0.0.1:${origin.port}/live.flv',
    ]);
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(relay!.inputUri)).close().timeout(const Duration(seconds: 2));
      final received = <int>[];
      final first = Completer<void>();
      final done = Completer<void>();
      response.listen(
        (bytes) {
          received.addAll(bytes);
          if (!first.isCompleted) first.complete();
        },
        onDone: done.complete,
        onError: done.completeError,
      );
      await first.future.timeout(const Duration(seconds: 2));
      await Future.wait([relay.finish(), relay.finish()]).timeout(const Duration(seconds: 2));
      await done.future.timeout(const Duration(seconds: 2));
      expect(received, prefix);
      expect(userAgent, 'fixture-native');
      expect(referer, 'https://fixture.example/');
      final second = await (await client.getUrl(relay.inputUri)).close();
      expect(second.statusCode, HttpStatus.gone);
      await second.drain<void>();
    } finally {
      client.close(force: true);
      await relay?.close().timeout(const Duration(seconds: 2));
      await sourceSubscription.cancel();
      await origin.close(force: true);
    }
  });

  test('relay handles stop before native connects without opening upstream', () async {
    final relay = await FFmpegFlvInputRelay.startForArguments(['-i', 'http://127.0.0.1:1/live.flv']);
    final client = HttpClient();
    try {
      await relay!.finish();
      final response = await (await client.getUrl(relay.inputUri)).close();
      expect(response.statusCode, HttpStatus.gone);
      await response.drain<void>();
    } finally {
      client.close(force: true);
      await relay?.close();
    }
  });

  test('stop unblocks an upstream request still waiting for response headers', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<void>();
    final subscription = origin.listen((request) {
      // Keep the response open without headers or media, as a stalled CDN can.
      accepted.complete();
    });
    final relay = await FFmpegFlvInputRelay.startForArguments(['-i', 'http://127.0.0.1:${origin.port}/live.flv']);
    final client = HttpClient();
    try {
      final request = await client.getUrl(relay!.inputUri);
      final received = request.close().then((response) => response.drain<void>());
      await accepted.future.timeout(const Duration(seconds: 2));
      await relay.finish().timeout(const Duration(seconds: 2));
      await received.timeout(const Duration(seconds: 2));
      expect(relay.finishRequested, true);
      await Future.wait([relay.close(), relay.close()]).timeout(const Duration(seconds: 2));
    } finally {
      client.close(force: true);
      await relay?.close();
      await origin.close(force: true);
      await subscription.cancel();
    }
  });

  test('unsupported inputs are untouched', () async {
    for (final args in [
      <String>[],
      ['-i'],
      ['-i', 'https://example/live.m3u8'],
      ['-i', '/local/file.flv'],
    ]) {
      expect(await FFmpegFlvInputRelay.startForArguments(args), isNull);
    }
  });
}
