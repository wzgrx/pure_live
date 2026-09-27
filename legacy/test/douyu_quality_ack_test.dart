import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/douyu/douyu_site.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

void main() {
  final room = LiveRoom(roomId: '123', platform: 'douyu');
  late Dio previous;
  late Dio fixture;
  late Map<String, Object?> rates;
  late List<Map<String, String>> requests;
  late Set<String> failures;

  LivePlayQuality quality([List<String> cdns = const ['main', 'backup']]) =>
      LivePlayQuality(quality: '原画', id: 0, data: DouyuPlayData(0, cdns));

  setUp(() {
    previous = HttpClient.instance.dio;
    rates = {'main': 2, 'backup': '2'};
    failures = {};
    requests = [];
    fixture = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/getEncryption')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'data': {
                      'key': 'fixture',
                      'rand_str': 'fixture',
                      'enc_data': 'fixture',
                      'enc_time': 1,
                      'expire_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                    },
                  },
                ),
              );
              return;
            }
            expect(options.path, endsWith('/getH5PlayV1/123'));
            final form = Uri.splitQueryString(options.data as String);
            requests.add(form);
            final cdn = form['cdn']!;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'error': failures.contains(cdn) ? 102 : 0,
                  'data': {
                    if (rates.containsKey(cdn)) 'rate': rates[cdn],
                    'rtmp_url': 'https://$cdn.example.test/live',
                    'rtmp_live': 'stream.flv',
                  },
                },
              ),
            );
          },
        ),
      );
    HttpClient.instance.dio = fixture;
  });

  tearDown(() {
    HttpClient.instance.dio = previous;
    fixture.close(force: true);
  });

  test('full playback propagates server downgrade to the visible quality', () async {
    final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality());
    expect(result.appliedQualityData, 2);
    expect(result.urls.length, 2);
    expect(requests.map((request) => request['rate']), ['0', '0']);
    expect(
      resolveAppliedQualityIndex(
        qualities: [
          quality(),
          LivePlayQuality(quality: '高清', id: 2),
        ],
        requestedIndex: 0,
        appliedQualityData: result.appliedQualityData,
      ),
      1,
    );
  });

  test('prefer a CDN acknowledging the requested quality over a downgraded line', () async {
    rates['backup'] = 0;
    final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality());
    expect(result.appliedQualityData, 0);
    expect(result.urls, ['https://backup.example.test/live/stream.flv']);
  });

  test('fallback lines all acknowledge the same quality without sorting opaque codes', () async {
    rates = {'main': 3, 'backup': 2, 'third': '3'};
    final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality(['main', 'backup', 'third']));
    expect(result.appliedQualityData, 3);
    expect(result.urls, ['https://main.example.test/live/stream.flv', 'https://third.example.test/live/stream.flv']);
  });

  test('recording cursor reports the one requested line acknowledgement', () async {
    final result = await DouyuSite().resolvePlayUrlAtRaw(detail: room, quality: quality(), lineIndex: 1);
    expect(result.appliedQualityData, 2);
    expect(requests.map((request) => request['cdn']), ['backup']);
  });

  test('missing or malformed acknowledgement is unknown, not fabricated source quality', () async {
    for (final value in [null, -1, 1.5, 'bad', '']) {
      rates = {'main': value};
      final result = await DouyuSite().resolvePlayUrlAtRaw(detail: room, quality: quality(['main']), lineIndex: 0);
      expect(result.appliedQualityData, isNull, reason: 'rate=$value');
      expect(result.qualityUnconfirmed, isTrue);
      expect(result.urls, hasLength(1));
    }
  });

  test('zero string is an acknowledged source quality', () async {
    rates = {'main': '0'};
    final result = await DouyuSite().resolvePlayUrlAtRaw(detail: room, quality: quality(['main']), lineIndex: 0);
    expect(result.appliedQualityData, 0);
  });

  test('a failed CDN does not discard another CDN with confirmed quality', () async {
    failures.add('backup');
    final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality());
    expect(result.appliedQualityData, 2);
    expect(result.urls, ['https://main.example.test/live/stream.flv']);
  });

  test('unknown acknowledgements remain playable without claiming a confirmed rate', () async {
    rates = {};
    final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality());
    expect(result.appliedQualityData, isNull);
    expect(result.qualityUnconfirmed, isTrue);
    expect(result.urls, hasLength(2));
  });

  test('known fallback is not mixed with a CDN missing the rate field', () async {
    rates = {'backup': 2};
    final result = await DouyuSite().resolvePlayUrls(detail: room, quality: quality());
    expect(result.appliedQualityData, 2);
    expect(result.urls, ['https://backup.example.test/live/stream.flv']);
  });

  test('all failed CDNs preserve the platform error', () async {
    failures.addAll(['main', 'backup']);
    await expectLater(
      DouyuSite().resolvePlayUrls(detail: room, quality: quality()),
      throwsA(isA<DouyuPlayApiException>()),
    );
    expect(requests, hasLength(4), reason: 'the existing one retry per CDN stays bounded');
  });

  test('legacy URL API also excludes lines that acknowledge a different quality', () async {
    rates['backup'] = 0;
    expect(await DouyuSite().getPlayUrls(detail: room, quality: quality()), [
      'https://backup.example.test/live/stream.flv',
    ]);
  });

  test('recorder displays applied quality while keeping the requested retry cursor', () async {
    final site = _RecordingDouyuSite([
      quality(),
      LivePlayQuality(quality: '高清', id: 2, data: DouyuPlayData(2, const ['main', 'backup'])),
    ]);
    final resolver = StreamResolverService(siteResolver: (_) => site);
    final first = await resolver.resolveStream(roomId: '123', platform: 'douyu', preferredQuality: '原画');
    expect(first.quality.selectionId, 2);
    expect(first.qualityCursorId, '0');
    expect(first.lineIndex, 0);
    expect(requests.map((request) => request['cdn']), ['main']);
    final next = await resolver.resolveStream(
      roomId: '123',
      platform: 'douyu',
      preferredQuality: '原画',
      previousQualityId: first.qualityCursorId,
      previousLineIndex: first.lineIndex,
    );
    expect(next.quality.selectionId, 2);
    expect(next.qualityCursorId, '0');
    expect(next.lineIndex, 1);
    expect(requests.map((request) => request['cdn']), ['main', 'backup']);
    expect(requests.map((request) => request['rate']), ['0', '0']);
  });

  test('recorder missing or unmapped rate keeps playback and marks its visible label', () async {
    for (final rate in [null, 'bad', 99]) {
      rates = {'main': rate};
      final resolver = StreamResolverService(
        siteResolver: (_) => _RecordingDouyuSite([
          quality(['main']),
        ]),
      );
      final stream = await resolver.resolveStream(roomId: '123', platform: 'douyu', preferredQuality: '原画');
      expect(stream.quality.isPlaybackUnconfirmed, isTrue);
      expect(stream.quality.quality, '原画', reason: 'the request option is not renamed');
      expect(stream.qualityCursorId, '0');
      expect(stream.url, 'https://main.example.test/live/stream.flv');
    }
  });

  test('an out of bounds cursor issues no requests and makes no quality claim', () async {
    final result = await DouyuSite().resolvePlayUrlAtRaw(detail: room, quality: quality(), lineIndex: 2);
    expect(result.urls, isEmpty);
    expect(result.appliedQualityData, isNull);
    expect(requests, isEmpty);
  });
}

class _RecordingDouyuSite extends DouyuSite {
  _RecordingDouyuSite(this.qualities);
  final List<LivePlayQuality> qualities;

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async => qualities;

  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) async =>
      LiveRoom(roomId: roomId, platform: platform, liveStatus: LiveStatus.live);
}
