import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

void main() {
  test('relay rewrites nested HLS resources and preserves input headers', () async {
    final seenUserAgents = <String?>[];
    final seenReferers = <String?>[];
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final originSubscription = origin.listen((request) async {
      seenUserAgents.add(request.headers.value(HttpHeaders.userAgentHeader));
      seenReferers.add(request.headers.value('referer'));
      switch (request.uri.path) {
        case '/master.m3u8':
          request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
          request.response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nvariant/live.m3u8\n');
        case '/variant/live.m3u8':
          request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-KEY:METHOD=AES-128,URI="../key.bin"\n'
            '#EXTINF:2.0,\n'
            'seg.ts?token=one\n',
          );
        case '/key.bin':
          request.response.add(List<int>.generate(16, (index) => index));
        case '/variant/seg.ts':
          expect(request.uri.queryParameters['token'], 'one');
          request.response.add(const <int>[1, 2, 3, 4]);
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final upstream = Uri.parse('http://${origin.address.address}:${origin.port}/master.m3u8');
    final relay = await FFmpegHlsInputRelay.startForArguments(<String>[
      '-user_agent',
      'PureLiveRelayTest/1.0',
      '-headers',
      'Referer: https://platform.example/live\r\nHost: ignored.example\r\n',
      '-i',
      upstream.toString(),
      '-c',
      'copy',
    ], force: true);
    expect(relay, isNotNull);

    final client = HttpClient();
    try {
      final rootManifest = await _readText(client, relay!.inputUri);
      expect(rootManifest, startsWith('#EXTM3U'));
      expect(rootManifest, isNot(contains('variant/live.m3u8')));
      final variantUri = Uri.parse(_mediaLines(rootManifest).single);
      expect(variantUri.host, InternetAddress.loopbackIPv4.address);
      expect(variantUri.port, relay.inputUri.port);

      final variantManifest = await _readText(client, variantUri);
      final keyUri = Uri.parse(RegExp(r'URI="([^"]+)"').firstMatch(variantManifest)!.group(1)!);
      final segmentUri = Uri.parse(_mediaLines(variantManifest).single);
      expect(keyUri.host, InternetAddress.loopbackIPv4.address);
      expect(segmentUri.host, InternetAddress.loopbackIPv4.address);
      expect(keyUri.path, endsWith('.ts'));
      expect(segmentUri.path, endsWith('.ts'));
      expect(await _readBytes(client, keyUri), List<int>.generate(16, (index) => index));
      expect(await _readBytes(client, segmentUri), const <int>[1, 2, 3, 4]);

      expect(seenUserAgents, everyElement('PureLiveRelayTest/1.0'));
      expect(seenReferers, everyElement('https://platform.example/live'));
    } finally {
      client.close(force: true);
      await relay?.close();
      await originSubscription.cancel();
      await origin.close(force: true);
    }
  });

  test('relay leaves missing and non-HLS inputs untouched', () async {
    expect(await FFmpegHlsInputRelay.startForArguments(const <String>['-c', 'copy'], force: true), isNull);
    expect(
      await FFmpegHlsInputRelay.startForArguments(const <String>[
        '-i',
        'https://example.invalid/live.flv',
      ], force: true),
      isNull,
    );
  });

  test('live recording opts into HLS drain on desktop without changing other HTTP inputs', () async {
    final arguments = ['-i', 'http://127.0.0.1:1/live.m3u8'];
    final relay = await FFmpegHlsInputRelay.startForArguments(arguments, drainOnStop: true);
    try {
      expect(relay, isNotNull);
      expect(relay!.drainOnStop, true);
      expect(relay.drainTimeout, const Duration(seconds: 4));
    } finally {
      await relay?.close();
    }
    expect(await FFmpegHlsInputRelay.startForArguments(arguments), isNull);
  });

  test('stop freezes nested playlists without ending master or breaking segment ranges', () async {
    var variantRequests = 0;
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = origin.listen((request) async {
      switch (request.uri.path) {
        case '/master.m3u8':
          request.response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nvariant.m3u8\n');
        case '/variant.m3u8':
          variantRequests++;
          request.response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:3\n'
            '#EXT-X-MAP:URI="init.mp4"\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
            '#EXTINF:6,\n#EXT-X-BYTERANGE:2@1\nmedia.m4s\n',
          );
        case '/media.m4s':
          expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=1-2');
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 1-2/4');
          request.response.add([2, 3]);
        default:
          request.response.add([0, 1, 2, 3]);
      }
      await request.response.close();
    });
    final relay = await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:${origin.port}/master.m3u8',
    ], drainOnStop: true);
    final client = HttpClient();
    try {
      final master = await _readText(client, relay!.inputUri);
      final variant = Uri.parse(_mediaLines(master).single);
      final live = await _readText(client, variant);
      expect(live, isNot(contains('#EXT-X-ENDLIST')));
      expect(relay.drainTimeout, const Duration(seconds: 14));
      await Future.wait([relay.finish(), relay.finish()]);
      expect(await _readText(client, relay.inputUri), master);
      final ended = await _readText(client, variant);
      expect(ended, '$live#EXT-X-ENDLIST\n');
      expect(await _readText(client, variant), ended);
      expect(variantRequests, 1);
      final request = await client.getUrl(Uri.parse(_mediaLines(ended).single));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=1-2');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers.value(HttpHeaders.contentRangeHeader), 'bytes 1-2/4');
      expect(await response.fold<List<int>>([], (all, bytes) => all..addAll(bytes)), [2, 3]);
      final resources = RegExp(r'URI="([^"]+)"').allMatches(ended);
      for (final resource in resources) {
        expect(await _readBytes(client, Uri.parse(resource.group(1)!)), [0, 1, 2, 3]);
      }
    } finally {
      client.close(force: true);
      await relay?.close();
      await origin.close(force: true);
      await subscription.cancel();
    }
  });

  test('an in-flight refresh cannot publish new segments after stop', () async {
    final pending = Completer<void>();
    final release = Completer<void>();
    var requests = 0;
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = origin.listen((request) async {
      final number = ++requests;
      if (number == 2) {
        pending.complete();
        await release.future;
      }
      request.response.write(
        '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:$number\n'
        '#EXTINF:2,\nsegment$number.ts\n',
      );
      await request.response.close();
    });
    final relay = await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:${origin.port}/live.m3u8',
    ], drainOnStop: true);
    final client = HttpClient();
    try {
      final first = await _readText(client, relay!.inputUri);
      final refreshing = _readText(client, relay.inputUri);
      await pending.future;
      await relay.finish();
      release.complete();
      expect(await refreshing, '$first#EXT-X-ENDLIST\n');
      expect(await _readText(client, relay.inputUri), '$first#EXT-X-ENDLIST\n');
      expect(requests, 2);
    } finally {
      if (!release.isCompleted) release.complete();
      client.close(force: true);
      await relay?.close();
      await origin.close(force: true);
      await subscription.cancel();
    }
  });

  test('rolling playlists retain two generations instead of lifetime segment addresses', () async {
    var sequence = 0;
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = origin.listen((request) async {
      if (request.uri.path == '/live.m3u8') {
        request.response.write(
          '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:$sequence\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="key$sequence.bin"\n'
          '#EXTINF:2,\nsegment$sequence.ts\n',
        );
        sequence++;
      } else {
        request.response.add([1, 2, 3]);
      }
      await request.response.close();
    });
    final relay = await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:${origin.port}/live.m3u8',
    ], force: true);
    final client = HttpClient();
    try {
      Uri? first;
      Uri? previous;
      Uri? latest;
      for (var i = 0; i < 200; i++) {
        previous = latest;
        final text = await _readText(client, relay!.inputUri);
        latest = Uri.parse(_mediaLines(text).single);
        first ??= latest;
        expect(relay.resourceCount, lessThanOrEqualTo(5));
      }
      expect(await _readBytes(client, previous!), [1, 2, 3]);
      expect(await _readBytes(client, latest!), [1, 2, 3]);
      final old = await (await client.getUrl(first!)).close();
      expect(old.statusCode, HttpStatus.notFound);
      await old.drain<void>();
      await Future.wait([relay!.close(), relay.close()]);
      expect(relay.resourceCount, 0);
    } finally {
      client.close(force: true);
      await relay?.close();
      await origin.close(force: true);
      await subscription.cancel();
    }
  });

  test('stop before the first playlist avoids opening upstream', () async {
    final relay = await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:1/live.m3u8',
    ], drainOnStop: true);
    final client = HttpClient();
    try {
      await relay!.finish();
      expect(await _readText(client, relay.inputUri), contains('#EXT-X-ENDLIST'));
    } finally {
      client.close(force: true);
      await relay?.close();
    }
  });

  test('an active old segment survives playlist pruning and then releases its address', () async {
    var sequence = 0;
    final release = Completer<void>();
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = origin.listen((request) async {
      if (request.uri.path == '/live.m3u8') {
        request.response.write(
          '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:$sequence\n'
          '#EXTINF:2,\nsegment${sequence++}.ts\n',
        );
        await request.response.close();
      } else {
        request.response.bufferOutput = false;
        request.response.add([1, 2]);
        await request.response.flush();
        await release.future;
        request.response.add([3, 4]);
        await request.response.close();
      }
    });
    final relay = await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:${origin.port}/live.m3u8',
    ], drainOnStop: true);
    final client = HttpClient();
    try {
      final first = Uri.parse(_mediaLines(await _readText(client, relay!.inputUri)).single);
      final response = await (await client.getUrl(first)).close();
      final started = Completer<void>();
      final received = response.fold<List<int>>([], (all, bytes) {
        if (!started.isCompleted) started.complete();
        return all..addAll(bytes);
      });
      await started.future.timeout(const Duration(seconds: 2));
      for (var i = 0; i < 5; i++) {
        await _readText(client, relay.inputUri);
      }
      expect(relay.resourceCount, 4); // root + two generations + active old segment
      await relay.finish();
      release.complete();
      expect(await received, [1, 2, 3, 4]);
      // A further request runs only after the old response has finished.
      await _readText(client, relay.inputUri);
      expect(relay.resourceCount, 3);
    } finally {
      if (!release.isCompleted) release.complete();
      client.close(force: true);
      await relay?.close();
      await origin.close(force: true);
      await subscription.cancel();
    }
  });

  test('close while waiting for headers settles and does not resurrect resources', () async {
    final accepted = Completer<void>();
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = origin.listen((request) => accepted.complete());
    final relay = await FFmpegHlsInputRelay.startForArguments([
      '-i',
      'http://127.0.0.1:${origin.port}/live.m3u8',
    ], drainOnStop: true);
    final client = HttpClient();
    try {
      final request = await client.getUrl(relay!.inputUri);
      final response = request.close().then<void>((response) => response.drain<void>(), onError: (Object _) {});
      await accepted.future.timeout(const Duration(seconds: 2));
      await Future.wait([relay.close(), relay.close()]).timeout(const Duration(seconds: 2));
      await response.timeout(const Duration(seconds: 2));
      expect(relay.resourceCount, 0);
    } finally {
      client.close(force: true);
      await relay?.close();
      await origin.close(force: true);
      await subscription.cancel();
    }
  });
}

Iterable<String> _mediaLines(String manifest) => const LineSplitter()
    .convert(manifest)
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty && !line.startsWith('#'));

Future<String> _readText(HttpClient client, Uri uri) async => utf8.decode(await _readBytes(client, uri));

Future<List<int>> _readBytes(HttpClient client, Uri uri) async {
  final response = await (await client.getUrl(uri)).close();
  expect(response.statusCode, HttpStatus.ok);
  return response.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
}
