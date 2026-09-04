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
