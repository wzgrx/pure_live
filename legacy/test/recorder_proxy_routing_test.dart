import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_flv_input_relay.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/recorder_proxy_routing.dart';

void main() {
  tearDown(() => configureRecorderProxyRouting(null));

  test('recorder routing defaults to direct and reads live settings', () {
    final uri = Uri.parse('https://media.example/live.m3u8');
    expect(resolveRecorderProxyDirective(uri), 'DIRECT');
    var directive = 'PROXY 127.0.0.1:7890';
    configureRecorderProxyRouting((_) => directive);
    expect(resolveRecorderProxyDirective(uri), directive);
    directive = 'DIRECT';
    expect(resolveRecorderProxyDirective(uri), 'DIRECT');
  });

  for (final hls in [true, false]) {
    test('${hls ? 'HLS manifest and segment' : 'FLV'} upstream uses configured proxy', () async {
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      final seen = <String>[];
      const flv = [0x46, 0x4c, 0x56, 1, 5, 0, 0, 0, 9, 0, 0, 0, 0];
      proxy.listen((request) async {
        seen.add(request.uri.toString());
        request.response.add(
          hls
              ? utf8.encode(
                  request.uri.path.endsWith('.m3u8')
                      ? '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n'
                      : 'segment-data',
                )
              : flv,
        );
        await request.response.close();
      });
      configureRecorderProxyRouting((_) => 'PROXY 127.0.0.1:${proxy.port}');
      // Port 1 is not an origin: success requires the configured HTTP proxy.
      final args = ['-i', 'http://127.0.0.1:1/live.${hls ? 'm3u8' : 'flv'}'];
      final hlsRelay = hls ? await FFmpegHlsInputRelay.startForArguments(args, force: true) : null;
      final flvRelay = hls ? null : await FFmpegFlvInputRelay.startForArguments(args);
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() async {
        client.close(force: true);
        await hlsRelay?.close();
        await flvRelay?.close();
      });
      final input = hlsRelay?.inputUri ?? flvRelay!.inputUri;
      final response = await (await client.getUrl(input)).close();
      final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      expect(response.statusCode, HttpStatus.ok);
      if (hls) {
        final segment = utf8.decode(bytes).split('\n').firstWhere((line) => line.isNotEmpty && !line.startsWith('#'));
        final media = await (await client.getUrl(input.resolve(segment))).close();
        expect(await utf8.decoder.bind(media).join(), 'segment-data');
        expect(seen, ['http://127.0.0.1:1/live.m3u8', 'http://127.0.0.1:1/segment.ts']);
      } else {
        expect(bytes, flv);
        expect(seen, ['http://127.0.0.1:1/live.flv']);
      }
    });
  }
}
