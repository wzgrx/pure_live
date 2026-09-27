import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_master_selection.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

import 'hls_master_selection_test.dart' show selectedFixtureMaster;

Future<String> read(HttpClient client, Uri uri) async {
  final response = await (await client.getUrl(uri)).close();
  expect(response.statusCode, 200);
  return response.transform(utf8.decoder).join();
}

List<Uri> media(String text) => const LineSplitter()
    .convert(text)
    .where((line) => line.isNotEmpty && !line.startsWith('#'))
    .map(Uri.parse)
    .toList();

Uri sequenceUri(String text, int sequence) {
  final first = int.parse(RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)').firstMatch(text)!.group(1)!);
  return media(text)[sequence - first];
}

void main() {
  for (final selected in [false, true]) {
    test(
      'fixed 3888→3893 window ${selected ? 'retains missing 3892 for the explicit pair' : 'reproduces unavailable 3892 without ABR retention'}',
      () async {
        final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final source = Uri.parse('http://127.0.0.1:${origin.port}/master.m3u8');
        var advanced = false;
        final paths = <String>[];
        final fetched = <String>{};
        final cached = Completer<void>();
        final jobs = <Future<void>>{};
        final sub = origin.listen((request) {
          late Future<void> job;
          job = () async {
            final path = request.uri.path;
            paths.add(path);
            expect(request.headers.value('cookie'), 'session=fixture');
            if (path == '/master.m3u8') {
              request.response.write(selectedFixtureMaster);
            } else if (path.endsWith('.m3u8')) {
              final kind = path == '/audio.m3u8' ? 'audio' : 'video';
              final first = advanced ? 3893 : 3888;
              request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:3\n#EXT-X-MEDIA-SEQUENCE:$first\n');
              for (var i = first; i < first + 5; i++) {
                request.response.write('#EXTINF:3,\n$kind-$i.ts\n');
              }
            } else {
              final sequence = int.parse(RegExp(r'-(\d+)\.ts$').firstMatch(path)!.group(1)!);
              if (advanced && sequence < 3893) {
                request.response.statusCode = 410;
              } else {
                request.response.write(path);
                fetched.add(path);
              }
            }
            await request.response.close();
            if (!cached.isCompleted &&
                List.generate(
                  5,
                  (i) => 3888 + i,
                ).every((i) => fetched.contains('/audio-$i.ts') && fetched.contains('/video-$i.ts'))) {
              cached.complete();
            }
          }().whenComplete(() => jobs.remove(job));
          jobs.add(job);
        });
        final selection = HlsMasterSelection.fromMaster(
          selectedFixtureMaster,
          source: source,
          video: source.resolve('high.m3u8'),
        );
        final relay = (await FFmpegHlsInputRelay.startForArguments(
          ['-i', source.toString()],
          masterSelection: selected ? selection : null,
          requestCookies: (uri) => uri.origin == source.origin ? 'session=fixture' : null,
          drainOnStop: true,
          enablePrefetch: true,
          findProxy: (_) => 'DIRECT',
        ))!;
        final client = HttpClient();
        try {
          final master = await read(client, relay.inputUri);
          expect(media(master).length, selected ? 1 : 3);
          expect(relay.prefetchFeedCount, selected ? 2 : 0);
          final audio = Uri.parse(RegExp(r'URI="([^"]+)"').firstMatch(master)!.group(1)!);
          final initial = await read(client, audio);
          final missing = sequenceUri(initial, 3892);
          expect(await read(client, sequenceUri(initial, 3891)), '/audio-3891.ts');
          if (selected) await cached.future.timeout(const Duration(seconds: 3));
          advanced = true;
          var refreshed = await read(client, audio);
          if (selected) {
            final clock = Stopwatch()..start();
            while (media(refreshed).length <= media(initial).length && clock.elapsed < const Duration(seconds: 5)) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              refreshed = await read(client, audio);
            }
            expect(await read(client, missing), '/audio-3892.ts');
            expect(sequenceUri(refreshed, 3892), missing);
            expect(
              paths.where((path) => path == '/audio-3892.ts').length,
              1,
              reason: 'the expired origin was not retried',
            );
            expect(paths, isNot(contains('/medium.m3u8')));
            expect(paths, isNot(contains('/low.m3u8')));
            expect(relay.prefetchBodyCount, lessThanOrEqualTo(32));
          } else {
            expect(refreshed, contains('#EXT-X-MEDIA-SEQUENCE:3893'));
            final response = await (await client.getUrl(missing)).close();
            await response.drain<void>();
            expect(response.statusCode, 410);
            expect(paths.where((path) => path == '/audio-3892.ts').length, 1);
          }
        } finally {
          client.close(force: true);
          await relay.close();
          await origin.close(force: true);
          await sub.cancel();
          await Future.wait(jobs.toList());
        }
        expect(relay.prefetchBodyCount, 0);
        expect(relay.resourceCount, 0);
      },
    );
  }
  test('selection-bound relay rejects another root before opening any connection', () async {
    final source = Uri.parse('https://media.test/master.m3u8');
    final selection = HlsMasterSelection.fromMaster(
      selectedFixtureMaster,
      source: source,
      video: source.resolve('high.m3u8'),
    );
    for (final args in <List<String>>[
      [],
      ['-i', 'https://other.test/master.m3u8'],
    ]) {
      await expectLater(FFmpegHlsInputRelay.startForArguments(args, masterSelection: selection), throwsFormatException);
    }
  });
}
