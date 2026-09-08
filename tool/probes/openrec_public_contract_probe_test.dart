// Opt-in metadata-only probe. Route is explicit; no hidden direct fallback.
import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/openrec/openrec_api.dart';

void main() {
  test(
    'production Openrec metadata contract with an explicit route',
    () async {
      final route = io.Platform.environment['PURELIVE_OPENREC_ROUTE'];
      expect(route, isIn(['DIRECT', 'PROXY 127.0.0.1:7897']));
      final channelId = io.Platform.environment['PURELIVE_OPENREC_CHANNEL']!;
      final output = io.Platform.environment['PURELIVE_OPENREC_OUTPUT'];
      await io.HttpOverrides.runWithHttpOverrides(() async {
        final previous = HttpClient.instance.dio;
        final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)))
          ..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => io.HttpClient()..findProxy = (_) => route!);
        HttpClient.instance.dio = dio;
        final report = <String, Object?>{
          'utc': DateTime.now().toUtc().toIso8601String(),
          'route': route,
          'registered': false,
          'mediaFetched': false,
          'nativePlaybackOrRecording': false,
        };
        try {
          final api = OpenrecApi();
          final page = await api.directory();
          final next = page.hasMore ? await api.directory(page: page.nextPage) : null;
          expect(page.movies, isNotEmpty, reason: 'No live sample; this does not prove a complete directory contract');
          final room = await api.room(channelId);
          expect(room.channel.isLive, isTrue, reason: 'Explicit public sample is no longer live');
          final broadcast = room.broadcast!;
          expect(broadcast.movie.channelId, channelId);
          expect(broadcast.movie.numericChannelId, room.channel.numericId);
          expect(broadcast.media, isNotEmpty);
          final refreshed = await api.room(channelId, expectedNumericId: room.channel.numericId);
          expect(refreshed.broadcast, isNotNull);
          report.addAll({
            'contract': 'passed',
            'requestedLimit': 30,
            'rawRows': page.rawCount,
            'cards': page.movies.length,
            'nextPageRawRows': next?.rawCount,
            'hasMore': page.hasMore,
            'channelAndBroadcastIdentityMatch': true,
            'refreshIdentityMatch': true,
            'sourceFamilies': broadcast.media.map((m) => m.id).toList(),
            'sourceHosts': broadcast.media.map((m) => Uri.parse(m.url).host).toSet().toList(),
          });
        } on OpenrecException catch (error) {
          report['contract'] = 'failed';
          report['failure'] = error.kind.name;
          rethrow;
        } finally {
          HttpClient.instance.dio = previous;
          dio.close(force: true);
          if (output != null) {
            await io.File(output).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
          }
          // ignore: avoid_print
          print(jsonEncode(report));
        }
      }, _RealNetwork());
    },
    skip: io.Platform.environment['PURELIVE_OPENREC_CHANNEL'] == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _RealNetwork extends io.HttpOverrides {}
