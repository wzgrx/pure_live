// Opt-in real-network check. Reads manifests, not media segments or native IO.
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
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/tting/tting_api.dart';
import 'package:pure_live/core/site/tting/tting_link.dart';
import 'package:pure_live/core/site/tting/tting_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/player/core/playback_header_resolver.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

Iterable<Uri> _references(String manifest) sync* {
  for (final line in const LineSplitter().convert(manifest)) {
    if (line.trim().isEmpty) continue;
    if (!line.startsWith('#')) {
      yield Uri.parse(line.trim());
    } else {
      for (final match in RegExp('URI="([^"]+)"').allMatches(line)) {
        yield Uri.parse(match.group(1)!);
      }
    }
  }
}

Future<String> _readManifest(io.HttpClient client, Uri uri) async {
  // Caller has already checked a private loopback URL, not an arbitrary link.
  final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
  try {
    final response = await request.close().timeout(const Duration(seconds: 25));
    if (response.statusCode != io.HttpStatus.ok) {
      await response.listen((_) {}).cancel();
      throw StateError('Manifest HTTP ${response.statusCode}');
    }
    return await TtingApi.readBody(response);
  } finally {
    request.abort();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'registered TTing API, every quality manifest and production relay children',
    () async {
      final route = io.Platform.environment['PURELIVE_TTING_ROUTE'];
      expect(route, 'PROXY 127.0.0.1:7897');
      final output = io.Platform.environment['PURELIVE_TTING_OUTPUT'];
      final report = <String, Object?>{
        'utc': DateTime.now().toUtc().toIso8601String(),
        'route': route,
        'registeredAdapter': true,
        'productionDioTransport': true,
        'mediaSegmentsFetched': false,
        'nativePlaybackOrRecording': false,
        'contract': 'failed',
        'stage': 'initialization',
        'http': <Map<String, Object?>>[],
        'qualityManifests': <Map<String, Object?>>[],
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
                final headers = response.requestOptions.headers.map((key, value) => MapEntry(key.toLowerCase(), value));
                (report['http'] as List).add({
                  'host': uri.host,
                  'kind': uri.path.endsWith('/profile')
                      ? 'profile'
                      : uri.path.endsWith('/stream')
                      ? 'stream'
                      : 'directory',
                  'status': response.statusCode,
                  'apiHeadersMatch':
                      headers['x-site-code'] == 'flex' &&
                      headers['origin'] == TtingApi.webOrigin &&
                      headers['referer'] == '${TtingApi.webOrigin}/',
                });
                handler.next(response);
              },
            ),
          );
          HttpClient.instance.dio = dio;
          final local = io.HttpClient()..findProxy = (_) => 'DIRECT';
          try {
            final site = Sites.of('ttinglive').liveSite as TtingSite;
            report['stage'] = 'directory';
            final page = await site.getDirectoryPage();
            report['directoryCards'] = page.rooms.length;
            expect(page.hasMore, isFalse);
            expect(page.rooms, isNotEmpty, reason: 'No public live sample in current homepage snapshot');
            final selected = page.rooms.first;
            final channelId = selected.roomId!;
            report['stage'] = 'room-and-quality';
            final detail = await site.getRoomDetail(roomId: channelId, platform: site.id);
            expect(detail.isLiveNow, isTrue);
            expect(detail.roomId == channelId, isTrue);
            final broadcast = detail.data as TtingBroadcast;
            report['channelId'] = broadcast.channel.id;
            report['broadcastId'] = broadcast.id;
            report['sourceFamily'] = broadcast.sources.first.family;
            final qualities = await site.getPlayQualites(detail: detail);
            expect(qualities, isNotEmpty);
            expect(
              qualities.length,
              lessThanOrEqualTo(8),
              reason: 'Bounded probe requires review of larger quality sets',
            );
            final headers = await PlaybackHeaderResolver.resolve(platform: site.id, roomId: channelId);
            expect(await FFmpegHeaderFactory.build(platform: site.id, roomId: channelId), headers);
            expect(headers.containsKey('x-site-code'), isFalse);
            for (final quality in qualities) {
              report['stage'] = 'quality-${quality.selectionId}-relay';
              final resolution = await site.resolvePlayUrls(detail: detail, quality: quality);
              expect(resolution.urls, hasLength(1));
              final source = resolution.urls.single;
              final policy = resolution.sourceQueryPolicies[source]!;
              expect(policy.matchesSource(Uri.parse(source)), isTrue);
              expect(site.getPlayUrlInvalidAt(source)!.isAfter(DateTime.now().toUtc()), isTrue);
              final relay = (await FFmpegHlsInputRelay.startForArguments(
                ['-headers', headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join(), '-i', source],
                sourceQueryPolicy: policy,
                findProxy: (_) => route!,
              ))!;
              final counts = <String, Object?>{
                'quality': quality.selectionId,
                'manifestCount': 0,
                'rollingMediaCount': 0,
                'externalAudioDeclaration': false,
                'lowLatencyParts': false,
                'initializationMap': false,
                'localReferenceCount': 0,
                'cleanupComplete': false,
              };
              (report['qualityManifests'] as List).add(counts);
              try {
                final queue = <Uri>[relay.inputUri];
                final seen = <Uri>{};
                while (queue.isNotEmpty) {
                  final next = queue.removeAt(0);
                  if (!seen.add(next)) continue;
                  expect(seen.length, lessThanOrEqualTo(8), reason: 'Manifest traversal budget reached');
                  final manifest = await _readManifest(local, next);
                  expect(manifest.startsWith('#EXTM3U'), isTrue);
                  expect(manifest.contains('token='), isFalse, reason: 'Relay should hide remote source signatures');
                  counts['manifestCount'] = seen.length;
                  if (manifest.contains('#EXTINF:')) {
                    expect(manifest.contains('#EXT-X-ENDLIST'), isFalse, reason: 'Expected a current rolling stream');
                    counts['rollingMediaCount'] = (counts['rollingMediaCount'] as int) + 1;
                  }
                  if (manifest.contains('#EXT-X-MEDIA:TYPE=AUDIO')) counts['externalAudioDeclaration'] = true;
                  if (manifest.contains('#EXT-X-PART:')) counts['lowLatencyParts'] = true;
                  if (manifest.contains('#EXT-X-MAP:')) counts['initializationMap'] = true;
                  for (final reference in _references(manifest)) {
                    expect(
                      reference.scheme == 'http' &&
                          reference.host == '127.0.0.1' &&
                          reference.port == relay.inputUri.port,
                      isTrue,
                      reason: 'Each manifest reference must use this private relay',
                    );
                    counts['localReferenceCount'] = (counts['localReferenceCount'] as int) + 1;
                    // Never fetch map, key, part, preload or full media payload.
                    if (reference.path.endsWith('.m3u8') && !seen.contains(reference)) queue.add(reference);
                  }
                }
                expect(counts['rollingMediaCount'] as int, greaterThan(0));
              } finally {
                await relay.close();
                // Opt-in test lives under tool/probes, outside analyzer's test/ convention.
                // ignore: invalid_use_of_visible_for_testing_member
                expect(relay.resourceCount, 0);
                counts['cleanupComplete'] = true;
              }
            }
            report['stage'] = 'recording-and-renewal';
            final quality = qualities.first;
            final recorded = await StreamResolverService().resolveStream(
              roomId: channelId,
              platform: site.id,
              preferredQuality: quality.quality,
            );
            expect(recorded.quality.selectionId, quality.selectionId);
            expect(recorded.sourceQueryPolicy!.matchesSource(Uri.parse(recorded.url)), isTrue);
            expect(recorded.invalidAt!.isAfter(DateTime.now().toUtc()), isTrue);
            final renewed = await site.resolvePlayUrlsForRecovery(detail: detail, quality: quality);
            expect(renewed.appliedQualityData, quality.selectionId);
            expect(
              renewed.sourceQueryPolicies[renewed.urls.single]!.matchesSource(Uri.parse(renewed.urls.single)),
              isTrue,
            );
            report['stage'] = 'share-and-refresh';
            final url = TtingLink.url(broadcast.channel.id);
            for (final share in [url, url.replaceFirst('www.flextv.co.kr', 'www.ttinglive.com')]) {
              expect(await LiveUrlTool.parseLiveUrl(share), [channelId, site.id]);
            }
            final refreshed = await site.getRoomDetailForRefresh(roomId: channelId, platform: site.id);
            expect(refreshed.roomId == channelId && refreshed.userId == detail.userId, isTrue);
            expect(refreshed.data, isNull);
            report.addAll({
              'contract': 'passed',
              'stage': 'complete',
              'qualityCount': qualities.length,
              'recordingResolutionMatch': true,
              'recoveryPolicyMatch': true,
              'shareIdentityMatch': true,
              'metadataIdentityMatch': true,
              'playerRecorderHeadersMatch': true,
            });
          } on TtingException catch (error) {
            report['failure'] = error.kind.name;
            rethrow;
          } catch (_) {
            // Never emit exception messages which could include a signed URI.
            report['failure'] = 'probeInvariantOrTransport';
            throw StateError('TTing probe failed at ${report['stage']}; see sanitized report');
          } finally {
            HttpClient.instance.dio = previous;
            dio.close(force: true);
            local.close(force: true);
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
    skip: io.Platform.environment['PURELIVE_TTING_APP_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _RealNetwork extends io.HttpOverrides {}
