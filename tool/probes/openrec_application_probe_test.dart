// Opt-in registered-adapter probe; no media segments or native player are run.
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/openrec/openrec_api.dart';
import 'package:pure_live/core/site/openrec/openrec_link.dart';
import 'package:pure_live/core/site/openrec/openrec_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/player/core/playback_header_resolver.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'registered Openrec directory, shares, quality and recording resolution',
    () async {
      final route = io.Platform.environment['PURELIVE_OPENREC_ROUTE'];
      expect(route, isIn(['DIRECT', 'PROXY 127.0.0.1:7897']));
      final output = io.Platform.environment['PURELIVE_OPENREC_OUTPUT'];
      final report = <String, Object?>{
        'utc': DateTime.now().toUtc().toIso8601String(),
        'route': route,
        'registeredAdapter': true,
        'mediaSegmentsFetched': false,
        'nativePlaybackOrRecording': false,
        'contract': 'failed',
        'stage': 'initialization',
        'http': <Map<String, Object?>>[],
      };
      await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
      await HivePrefUtil.init();
      Get.testMode = true;
      Get.put(SettingsService());
      try {
        await io.HttpOverrides.runWithHttpOverrides(() async {
          final previous = HttpClient.instance.dio;
          final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)))
            ..httpClientAdapter = IOHttpClientAdapter(
              createHttpClient: () => io.HttpClient()..findProxy = (_) => route!,
            );
          dio.interceptors.add(
            InterceptorsWrapper(
              onResponse: (response, handler) {
                final uri = response.requestOptions.uri;
                final requestHeaders = response.requestOptions.headers.map(
                  (key, value) => MapEntry(key.toLowerCase(), value),
                );
                (report['http'] as List).add({
                  'host': uri.host,
                  'kind': uri.path.endsWith('/movies')
                      ? 'directory'
                      : uri.path.contains('/channels/')
                      ? 'channel'
                      : uri.path.contains('/movies/')
                      ? 'movie'
                      : 'manifest',
                  'status': response.statusCode,
                  'originHeadersMatch':
                      requestHeaders['referer'] == '${OpenrecApi.webOrigin}/' &&
                      requestHeaders['origin'] == OpenrecApi.webOrigin,
                });
                handler.next(response);
              },
            ),
          );
          HttpClient.instance.dio = dio;
          try {
            final site = Sites.of('openrec').liveSite as OpenrecSite;
            report['stage'] = 'directory';
            final page = await site.getDirectoryPage();
            report['directoryCards'] = page.rooms.length;
            final candidates = page.rooms.where((r) => r.isLiveNow && r.notice == null).toList();
            expect(candidates, isNotEmpty, reason: 'No current public single-broadcast sample');
            final selected = candidates.first;
            final key = OpenrecRoomKey.parse(selected.roomId!);
            report['stage'] = 'playback-resolution';
            final detail = await site.getRoomDetail(roomId: key.value, platform: 'openrec');
            expect(detail.isLiveNow, isTrue);
            expect(detail.roomId, key.value);
            final qualities = await site.getPlayQualites(detail: detail);
            expect(qualities, isNotEmpty);
            final quality = qualities.first;
            final urls = await site.getPlayUrls(detail: detail, quality: quality);
            report['stage'] = 'selected-child';
            final manifest = await OpenrecApi().manifest(urls.first);
            expect(manifest, startsWith('#EXTM3U'));
            expect(manifest, contains('#EXTINF:'));
            expect(manifest, isNot(contains('#EXT-X-ENDLIST')));
            final headers = await PlaybackHeaderResolver.resolve(platform: 'openrec', roomId: key.value);
            expect(headers['referer'], '${OpenrecApi.webOrigin}/');
            expect(headers['origin'], OpenrecApi.webOrigin);
            expect(await FFmpegHeaderFactory.build(platform: 'openrec', roomId: key.value), headers);
            report['stage'] = 'recording-resolution';
            final recorded = await StreamResolverService().resolveStream(
              roomId: key.value,
              platform: 'openrec',
              preferredQuality: quality.selectionId.toString(),
            );
            expect(recorded.quality.selectionId, quality.selectionId);
            expect(Uri.parse(recorded.url).scheme, 'https');
            report['stage'] = 'share-import';
            for (final url in [key.url, key.url.replaceFirst('www.mellow-fan.com', 'www.openrec.tv')]) {
              expect(await LiveUrlTool.parseLiveUrl(url), [key.value, 'openrec']);
            }
            final refreshed = await site.getRoomDetailForRefresh(roomId: key.value, platform: 'openrec');
            expect(refreshed.roomId, key.value);
            expect(refreshed.userId, detail.userId);
            report.addAll({
              'contract': 'passed',
              'stage': 'complete',
              'pinnedIdentityMatch': true,
              'oldAndNewShareMatch': true,
              'metadataRefreshMatch': true,
              'qualityCount': qualities.length,
              'qualityLabels': qualities.map((q) => q.quality).toList(),
              'selectedMediaHost': Uri.parse(urls.first).host,
              'rollingChildPlaylist': true,
              'recordingResolutionMatch': true,
              'playerAndRecordingHeadersMatch': true,
              'partialFamilyNotice': detail.notice,
            });
          } on OpenrecException catch (error) {
            report['failure'] = error.kind.name;
            rethrow;
          } finally {
            HttpClient.instance.dio = previous;
            dio.close(force: true);
          }
        }, _RealNetwork());
      } finally {
        Get.reset();
        await Hive.close();
        if (output != null) {
          await io.File(output).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
        }
        // ignore: avoid_print
        print(jsonEncode(report));
      }
    },
    skip: io.Platform.environment['PURELIVE_OPENREC_APP_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

class _RealNetwork extends io.HttpOverrides {}
