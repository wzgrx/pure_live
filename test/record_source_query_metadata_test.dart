import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_command_builder.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/services/ffmpeg_service.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/ffmpeg_flv_input_relay.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

void main() {
  final source = Uri.parse('https://cdn.example/a/master.m3u8?token=one');
  final policy = HlsSourceQueryPolicy.fromSource(source);
  final room = LiveRoom(roomId: '1', platform: 'bilibili', liveStatus: LiveStatus.live, status: true);
  final quality = LivePlayQuality(quality: '原画', id: 'high', sort: 1000);

  test('policy-bearing result owns immutable normalized inputs and quality acknowledgement', () {
    final urls = [' ', ' $source ', '$source'];
    final policies = {'$source': policy};
    final result = LivePlayUrlResolution.withSourcePolicies(
      urls: urls,
      sourceQueryPolicies: policies,
      appliedQualityData: 'low',
      qualityUnconfirmed: true,
    );
    urls.clear();
    policies.clear();
    expect(result.urls, ['$source']);
    expect(result.sourceQueryPolicies['$source'], same(policy));
    expect(() => result.urls.clear(), throwsUnsupportedError);
    expect(() => result.sourceQueryPolicies.clear(), throwsUnsupportedError);
    final copied = result.normalized();
    expect(copied.sourceQueryPolicies['$source'], same(policy));
    expect(copied.appliedQualityData, 'low');
    expect(copied.qualityUnconfirmed, isTrue);
  });

  test('policy map rejects unlisted URLs and old source signatures', () {
    for (final key in ['https://cdn.example/a/master.m3u8?token=two', ' $source ', 'not a URI']) {
      expect(
        () => LivePlayUrlResolution.withSourcePolicies(urls: [key], sourceQueryPolicies: {key: policy}),
        throwsFormatException,
      );
    }
    expect(
      () => LivePlayUrlResolution.withSourcePolicies(urls: [], sourceQueryPolicies: {'$source': policy}),
      throwsFormatException,
    );
  });

  test('normal and recovery adapters retain per-source policies and fresh identities', () async {
    final site = _PolicySite();
    final normal = await site.resolvePlayUrls(detail: room, quality: quality);
    final recovery = await site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
    for (final result in [normal, recovery]) {
      final url = result.urls.firstWhere((url) => url.startsWith('http'));
      expect(result.sourceQueryPolicies[url]?.matchesSource(Uri.parse(url)), isTrue);
      expect(result.appliedQualityData, 'low');
      expect(result.qualityUnconfirmed, isTrue);
    }
    final fresh = recovery.urls.firstWhere((url) => url.startsWith('http'));
    expect(normal.sourceQueryPolicies.values.first.matchesSource(Uri.parse(fresh)), isFalse);
  });

  test('legacy token-looking URLs do not implicitly opt in', () async {
    final site = _LegacySite();
    final result = await site.resolvePlayUrls(detail: room, quality: quality);
    expect(result.sourceQueryPolicies, isEmpty);
    expect(result.appliedQualityData, 'high');
    expect(const LivePlayUrlResolution(urls: []).sourceQueryPolicies, isEmpty);
  });

  test('an injected policy site does not bypass the registered-platform guard', () async {
    final resolver = StreamResolverService(siteResolver: (_) => _PolicySite());
    await expectLater(
      resolver.resolveStream(roomId: '1', platform: 'fixture', preferredQuality: '原画'),
      throwsA(isA<StreamException>().having((error) => error.retryable, 'retryable', isFalse)),
    );
  });

  test('actual FFmpeg manager forwards policy and exact arguments to its service', () async {
    final service = _Service();
    final manager = FFmpegManager.forTesting(service);
    final args = ['-i', '$source', 'output.ts'];
    await manager.start(taskId: 'fixture', arguments: args, liveRecording: true, sourceQueryPolicy: policy);
    expect(service.policy, same(policy));
    expect(service.arguments, same(args));
    expect(service.live, isTrue);
    expect(service.prefetch, isFalse);
  });

  test('manager forwards explicit retention and diagnostics without enabling offline jobs', () async {
    final service = _Service();
    final manager = FFmpegManager.forTesting(service);
    final diagnostics = HlsRelayDiagnostics();
    final args = ['-i', '$source', 'output.ts'];
    for (final enabled in [true, false]) {
      await manager.start(
        taskId: 'live',
        arguments: args,
        liveRecording: true,
        sourceQueryPolicy: policy,
        hlsPrefetch: enabled,
        hlsDiagnostics: diagnostics,
      );
      expect(service.prefetch, enabled);
      expect(service.diagnostics, same(diagnostics));
      expect(service.policy, same(policy));
      expect(service.arguments, same(args));
    }
    await manager.start(taskId: 'merge', arguments: ['-i', 'input.ts', 'output.mp4']);
    expect(service.live, isFalse);
    expect(service.prefetch, isFalse);
    expect(service.policy, isNull);
    expect(service.diagnostics, isNull);
  });

  for (final cursor in [false, true]) {
    test('recorder selects the matching policy after filtering and line rotation cursor=$cursor', () async {
      final site = cursor ? _CursorSite() : _PolicySite();
      final resolver = StreamResolverService(siteResolver: (_) => site);
      final first = await resolver.resolveStream(roomId: '1', platform: 'bilibili', preferredQuality: '原画');
      final next = await resolver.resolveStream(
        roomId: '1',
        platform: 'bilibili',
        preferredQuality: '原画',
        previousQualityId: first.qualityCursorId,
        previousLineIndex: first.lineIndex,
      );
      expect(first.lineIndex, 0);
      expect(next.lineIndex, 1);
      expect(first.sourceQueryPolicy?.matchesSource(Uri.parse(first.url)), isTrue);
      expect(next.sourceQueryPolicy?.matchesSource(Uri.parse(next.url)), isTrue);
      expect(first.sourceQueryPolicy?.matchesSource(Uri.parse(next.url)), isFalse);
      expect(next.quality.selectionId, 'low');
      expect(next.quality.isPlaybackUnconfirmed, isTrue);
      expect(next.qualityCursorId, 'high');
      final renewed = await resolver.resolveStream(
        roomId: '1',
        platform: 'bilibili',
        preferredQuality: '原画',
        previousQualityId: next.qualityCursorId,
        previousLineIndex: next.lineIndex,
        renewCurrent: true,
      );
      expect(renewed.lineIndex, 1);
      expect(renewed.sourceQueryPolicy?.matchesSource(Uri.parse(renewed.url)), isTrue);
      expect(next.sourceQueryPolicy?.matchesSource(Uri.parse(renewed.url)), isFalse);
    });
  }

  test('selected recorder source and actual command reach an opt-in HTTP relay', () async {
    final observed = <Uri>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      observed.add(request.uri);
      if (!request.uri.queryParameters.containsKey('token')) {
        request.response.statusCode = 403;
      } else if (request.uri.path.endsWith('.m3u8')) {
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nsegment.ts\n');
      } else {
        request.response.write('DATA');
      }
      await request.response.close();
    });
    final client = HttpClient();
    FFmpegHlsInputRelay? relay;
    try {
      final site = _PolicySite(origin: 'http://127.0.0.1:${server.port}');
      final resolver = StreamResolverService(siteResolver: (_) => site);
      final selected = await resolver.resolveStream(roomId: '1', platform: 'bilibili', preferredQuality: '原画');
      final args = FFmpegCommandBuilder.buildRecordArguments(
        headers: {},
        url: selected.url,
        outputDir: Directory.systemTemp.path,
        segmentTime: 60,
        preferBestStream: false,
        rwTimeout: 20000000,
        threadQueueSize: 512,
      );
      relay = (await FFmpegHlsInputRelay.startForArguments(
        args,
        drainOnStop: true,
        sourceQueryPolicy: selected.sourceQueryPolicy,
      ))!;
      final manifest = await (await (await client.getUrl(relay.inputUri)).close()).transform(utf8.decoder).join();
      final child = Uri.parse(const LineSplitter().convert(manifest).firstWhere((line) => !line.startsWith('#')));
      final response = await (await client.getUrl(child)).close();
      expect(response.statusCode, 200);
      expect(await response.transform(utf8.decoder).join(), 'DATA');
      expect(observed.length, 2);
      expect(observed.last.queryParameters['token'], Uri.parse(selected.url).queryParameters['token']);
    } finally {
      client.close(force: true);
      await relay?.close();
      await server.close(force: true);
      await subscription.cancel();
    }
  });
}

class _PolicySite extends LiveSite implements LivePlayUrlResolver, LivePlayRecoveryResolver {
  _PolicySite({this.origin = 'https://cdn.example'});
  final String origin;
  int generation = 0;

  LivePlayUrlResolution build({int? line}) {
    final version = ++generation;
    final sources = [
      for (final index in line == null ? [0, 1] : [line]) '$origin/line$index/master.m3u8?token=$version-$index',
    ];
    return LivePlayUrlResolution.withSourcePolicies(
      urls: ['javascript:discard', ...sources, sources.first],
      sourceQueryPolicies: {for (final url in sources) url: HlsSourceQueryPolicy.fromSource(Uri.parse(url))},
      appliedQualityData: 'low',
      qualityUnconfirmed: true,
    );
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) async =>
      LiveRoom(roomId: roomId, platform: platform, liveStatus: LiveStatus.live, status: true);
  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async => [
    LivePlayQuality(quality: '原画', id: 'high', sort: 1000),
    LivePlayQuality(quality: '高清', id: 'low', sort: 500),
  ];
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => build();
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => build();
}

class _CursorSite extends _PolicySite implements LivePlayUrlCursorResolver {
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlAtRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
    required int lineIndex,
  }) async => lineIndex > 1 ? const LivePlayUrlResolution(urls: []) : build(line: lineIndex);
}

class _LegacySite extends LiveSite {
  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'https://cdn.example/a/master.m3u8?token=one',
  ];
}

class _Service implements FFmpegService {
  HlsSourceQueryPolicy? policy;
  List<String>? arguments;
  bool? live;
  bool? prefetch;
  HlsRelayDiagnostics? diagnostics;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<void> initialize() async {}
  @override
  Future<void> start({
    required String taskId,
    required List<String> arguments,
    required void Function(FFmpegEvent event) onEvent,
    bool liveRecording = false,
    HlsSourceQueryPolicy? sourceQueryPolicy,
    HlsRelayDiagnostics? hlsDiagnostics,
    FlvRelayDiagnostics? flvDiagnostics,
    bool hlsPrefetch = false,
  }) async {
    policy = sourceQueryPolicy;
    this.arguments = arguments;
    live = liveRecording;
    prefetch = hlsPrefetch;
    diagnostics = hlsDiagnostics;
  }
}
