import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

Future<(int, String)> _read(HttpClient client, Uri uri) async {
  final response = await (await client.getUrl(uri)).close();
  return (response.statusCode, await response.transform(utf8.decoder).join());
}

List<Uri> _links(String manifest) => [
  for (final line in const LineSplitter().convert(manifest))
    if (line.isNotEmpty && !line.startsWith('#')) Uri.parse(line),
];

List<Uri> _attributes(String manifest) => [
  for (final match in RegExp('URI="([^"]+)"').allMatches(manifest)) Uri.parse(match.group(1)!),
];

void main() {
  for (final profile in [(scoped: false, drain: false), (scoped: true, drain: false), (scoped: true, drain: true)]) {
    final scoped = profile.scoped;
    test('nested master/media/key/map/range contract opt-in=$scoped drain=${profile.drain}', () async {
      final seen = <(Uri, String?)>[];
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = origin.listen((request) async {
        seen.add((request.uri, request.headers.value(HttpHeaders.rangeHeader)));
        if (request.uri.queryParameters['token'] != 'source/a+b=') {
          request.response.statusCode = HttpStatus.forbidden;
        } else if (request.uri.path.endsWith('master.m3u8')) {
          request.response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\nnested/child.m3u8\n');
        } else if (request.uri.path.endsWith('child.m3u8')) {
          request.response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:2\n'
            '#EXT-X-KEY:METHOD=AES-128,URI="../key.bin"\n'
            '#EXT-X-MAP:URI="../init.mp4"\n'
            '#EXTINF:2,\n../segment.ts?sig=own%2Fvalue&x=1&x=2\n',
          );
        } else {
          if (request.headers.value(HttpHeaders.rangeHeader) != null) {
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-3/4');
          }
          request.response.write('DATA');
        }
        await request.response.close();
      });
      final source = Uri.parse(
        'http://127.0.0.1:${origin.port}/live/channel/master.m3u8?token=source%2Fa%2Bb%3D&rootOnly=1',
      );
      final relay = (await FFmpegHlsInputRelay.startForArguments(
        ['-i', '$source'],
        force: !scoped,
        drainOnStop: profile.drain,
        sourceQueryPolicy: scoped ? HlsSourceQueryPolicy.fromSource(source) : null,
      ))!;
      final client = HttpClient();
      try {
        final master = await _read(client, relay.inputUri);
        expect(master.$1, HttpStatus.ok);
        expect(master.$2, isNot(contains('source%2F')));
        final childUri = _links(master.$2).single;
        final child = await _read(client, childUri);
        expect(child.$1, scoped ? HttpStatus.ok : HttpStatus.forbidden);
        if (scoped) {
          final segment = _links(child.$2).single;
          for (final uri in _attributes(child.$2)) {
            expect(await _read(client, uri), (HttpStatus.ok, 'DATA'));
          }
          final request = await client.getUrl(segment);
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
          final response = await request.close();
          expect(response.statusCode, HttpStatus.partialContent);
          expect(response.headers.value(HttpHeaders.contentRangeHeader), 'bytes 0-3/4');
          expect(await response.transform(utf8.decoder).join(), 'DATA');
          expect(seen.length, 5);
          for (final (uri, _) in seen.skip(1)) {
            expect(uri.queryParametersAll['token'], ['source/a+b=']);
            expect(uri.queryParameters.containsKey('rootOnly'), isFalse);
          }
          expect(seen.last.$1.query, 'sig=own%2Fvalue&x=1&x=2&token=source%2Fa%2Bb%3D');
          expect(seen.last.$2, 'bytes=0-3');
          if (profile.drain) {
            final requestsBeforeStop = seen.length;
            await relay.finish();
            final ended = await _read(client, childUri);
            expect(ended.$2, '${child.$2}#EXT-X-ENDLIST\n');
            expect(seen.length, requestsBeforeStop);
            expect(relay.inputTailDiscarded, isFalse);
          }
        } else {
          expect(seen.last.$1.hasQuery, isFalse, reason: 'ordinary HLS retains standard URI semantics');
        }
      } finally {
        client.close(force: true);
        await relay.close();
        await origin.close(force: true);
        await subscription.cancel();
      }
      expect(relay.resourceCount, 0);
      await relay.close();
    });
  }

  test('redirects and URI attributes preserve token ownership and scope', () async {
    final seen = <Uri>[];
    final foreignSeen = <Uri>[];
    final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final foreignSubscription = foreign.listen((request) async {
      foreignSeen.add(request.uri);
      request.response.write('FOREIGN');
      await request.response.close();
    });
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = origin.listen((request) async {
      seen.add(request.uri);
      switch (request.uri.path) {
        case '/live/channel/master.m3u8':
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader, 'next.m3u8');
        case '/live/channel/next.m3u8':
          request.response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:1\n'
            '#EXT-X-KEY:METHOD=AES-128,URI="key.bin?token=key-own"\n'
            '#EXTINF:1,\nredirect.ts\n#EXTINF:1,\nforeign.ts\n',
          );
        case '/live/channel/redirect.ts':
          request.response.statusCode = 307;
          request.response.headers.set(HttpHeaders.locationHeader, '../other/segment.ts');
        case '/live/channel/foreign.ts':
          request.response.statusCode = 302;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${foreign.port}/live/channel/segment.ts',
          );
        default:
          request.response.write('DATA');
      }
      await request.response.close();
    });
    final source = Uri.parse('http://127.0.0.1:${origin.port}/live/channel/master.m3u8?token=source-token');
    final relay = (await FFmpegHlsInputRelay.startForArguments([
      '-i',
      '$source',
    ], sourceQueryPolicy: HlsSourceQueryPolicy.fromSource(source)))!;
    final client = HttpClient();
    try {
      final manifest = (await _read(client, relay.inputUri)).$2;
      expect(await _read(client, _attributes(manifest).single), (200, 'DATA'));
      final links = _links(manifest);
      expect(await _read(client, links.first), (200, 'DATA'));
      expect(await _read(client, links.last), (200, 'FOREIGN'));
      expect(seen.first.queryParameters['token'], 'source-token');
      expect(seen[1].queryParameters['token'], 'source-token');
      expect(seen.singleWhere((uri) => uri.path.endsWith('key.bin')).queryParameters['token'], 'key-own');
      expect(seen.singleWhere((uri) => uri.path == '/live/other/segment.ts').hasQuery, isFalse);
      expect(foreignSeen.single.hasQuery, isFalse);
    } finally {
      client.close(force: true);
      await relay.close();
      await origin.close(force: true);
      await subscription.cancel();
      await foreign.close(force: true);
      await foreignSubscription.cancel();
    }
  });

  test('two source sessions and closing one never share or retire the other token', () async {
    final tokens = <String?>[];
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = origin.listen((request) async {
      tokens.add(request.uri.queryParameters['token']);
      request.response.write(
        request.uri.path.endsWith('.m3u8') ? '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nsegment.ts\n' : 'DATA',
      );
      await request.response.close();
    });
    Future<FFmpegHlsInputRelay> start(String token) async {
      final source = Uri.parse('http://127.0.0.1:${origin.port}/live/master.m3u8?token=$token');
      return (await FFmpegHlsInputRelay.startForArguments([
        '-i',
        '$source',
      ], sourceQueryPolicy: HlsSourceQueryPolicy.fromSource(source)))!;
    }

    final first = await start('first');
    final second = await start('second');
    final firstInput = first.inputUri;
    final secondInput = second.inputUri;
    final client = HttpClient();
    try {
      final a = _links((await _read(client, first.inputUri)).$2).single;
      final b = _links((await _read(client, second.inputUri)).$2).single;
      await _read(client, a);
      await first.close();
      expect(first.resourceCount, 0);
      expect(await _read(client, b), (200, 'DATA'));
      expect(tokens, ['first', 'second', 'first', 'second']);
      expect(firstInput.port, isNot(secondInput.port));
    } finally {
      client.close(force: true);
      await first.close();
      await second.close();
      await origin.close(force: true);
      await subscription.cancel();
    }
  });

  test('policy mismatches fail before a relay can silently use a different input', () async {
    final source = Uri.parse('https://cdn.example/live/master.m3u8?token=one');
    final policy = HlsSourceQueryPolicy.fromSource(source);
    for (final arguments in <List<String>>[
      [],
      ['-i'],
      ['-i', '$source&new=1'],
      ['-i', 'https://cdn.example/live/other.m3u8?token=one'],
      ['-i', 'https://cdn.example/live/master.m3u8?token=two'],
    ]) {
      await expectLater(
        FFmpegHlsInputRelay.startForArguments(arguments, sourceQueryPolicy: policy),
        throwsFormatException,
      );
    }
  });
}
