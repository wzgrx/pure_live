// The quality a recording is labelled with is the one the platform served,
// not the one requested (F.0b: a Bilibili guest asking for 原画 recorded
// 720p labelled 原画), and a limited quality is said once per recording.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

const _bilibili = '../../fixtures/bilibili';
const _ignored = {'wts', 'w_rid', 'w_webid'};

/// `getRoomPlayInfo` at qn=0 as a room offering 原画 only answers it: every
/// codec lists 10000 alone and is served at 10000.
ReplaySample _onlyOriginalListed() {
  final sample = ReplaySample.load('$_bilibili/S07-guest-qn0');
  final body = jsonDecode(utf8.decode(sample.bytes)) as Map<String, dynamic>;
  final playurl = ((body['data'] as Map)['playurl_info'] as Map)['playurl'] as Map;
  for (final stream in playurl['stream'] as List) {
    for (final format in (stream as Map)['format'] as List) {
      for (final codec in (format as Map)['codec'] as List) {
        (codec as Map)
          ..['accept_qn'] = [10000]
          ..['current_qn'] = 10000;
      }
    }
  }
  return ReplaySample(
    method: sample.method,
    url: sample.url,
    status: sample.status,
    headers: sample.headers,
    bytes: utf8.encode(jsonEncode(body)),
  );
}

/// Bilibili over the recorded guest responses of room 42062: its qualities
/// (qn=0) are 原画, 蓝光 and 超清 — or 原画 alone with [onlyOriginal] — and
/// a request at 10000 is served 250 (`current_qn`).
BilibiliSite _bilibiliGuest({bool onlyOriginal = false}) => BilibiliSite(
  ReplayHttp([
    if (onlyOriginal) _onlyOriginalListed(),
    for (final name in ['S06-live', 'S07-guest-qn0', 'S07-guest-qn10000', 'S10-guest', 'S11-guest', 'S12-guest'])
      ReplaySample.load('$_bilibili/$name'),
  ], ignoredQuery: _ignored),
  now: () => DateTime.utc(2026, 9, 27, 10, 16, 23),
  sleep: (_) async {},
);

Future<ResolvedRecordStream> _resolve(LiveSite site, {String platform = 'bilibili', String roomId = '42062'}) =>
    RecordStreamResolver((_) => site).resolve(roomId: roomId, platform: platform, preferredQuality: '原画');

/// A live room offering 原画 and 超清 whose answers say which quality was
/// applied: [applied] for every request, or the request itself; none when
/// [unconfirmed] (a confirmation was expected but missing).
final class _ConfirmingSite extends LiveSite implements LivePlayUrlResolver {
  new({this.applied, this.unconfirmed = false});

  final String? applied;
  final bool unconfirmed;

  @override
  String get id => 'fake';

  @override
  String get name => 'Fake';

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async =>
      LiveRoom(roomId: roomId, platform: id, nick: '主播', liveStatus: LiveStatus.live);

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => const [
    LivePlayQuality(quality: '原画', id: 'origin', sort: 2),
    LivePlayQuality(quality: '超清', id: 'hd', sort: 1),
  ];

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution(
    urls: ['rtmp://cdn-a.example/live/${applied ?? quality.selectionId}'],
    appliedQualityData: unconfirmed ? null : applied ?? quality.selectionId,
    qualityUnconfirmed: unconfirmed,
  );
}

void main() {
  group('resolver', () {
    test('a Bilibili guest asking for 原画 is labelled with the 超清 it is served', () async {
      final stream = await _resolve(_bilibiliGuest());
      expect(stream.quality.id, 250);
      expect(stream.quality.isPlaybackUnconfirmed, isFalse);
      expect(stream.qualityLabel, '超清');
      expect(stream.qualityCursorId, '10000', reason: 'retries keep asking for the requested tier');
      expect(stream.qualityLimited, isTrue);
    });

    test('a served quality the room did not list is named by the platform (F.0b)', () async {
      final stream = await _resolve(_bilibiliGuest(onlyOriginal: true));
      expect(stream.qualityLabel, '超清');
      expect(stream.quality.id, 250);
      expect(stream.qualityLimited, isTrue);
    });

    test('the requested quality served as asked is not limited', () async {
      final stream = await _resolve(_ConfirmingSite(), platform: 'fake', roomId: '1');
      expect(stream.qualityLabel, '原画');
      expect(stream.qualityLimited, isFalse);
    });

    test('a quality the platform did not confirm is marked like the player marks it', () async {
      final stream = await _resolve(_ConfirmingSite(unconfirmed: true), platform: 'fake', roomId: '1');
      expect(stream.qualityLabel, '原画?');
      expect(stream.qualityLimited, isFalse, reason: 'nothing is known to be limited');
    });
  });

  group('recorder', () {
    late Directory root;
    late FakeFfmpeg ffmpeg;
    late List<Recorder> recorders;

    setUp(() {
      root = Directory.systemTemp.createTempSync('live_record_quality');
      ffmpeg = FakeFfmpeg();
      recorders = [];
    });

    tearDown(() async {
      for (final recorder in recorders) {
        await recorder.dispose();
      }
      root.deleteSync(recursive: true);
    });

    Recorder recorderOf(LiveSite site) {
      final recorder = Recorder(
        sites: (id) => id == site.id ? site : null,
        ffmpeg: ffmpeg,
        storage: RecordStorage(defaultDirectory: () async => root.path, configuredPath: () => ''),
        settings: RecordSettings.new,
        persist: (json) async {},
        startGap: Duration.zero,
      );
      recorders.add(recorder);
      return recorder;
    }

    Future<void> until(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('timed out');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('the task, its notification and the centre read the served quality (F.0b)', () async {
      final recorder = recorderOf(_bilibiliGuest(onlyOriginal: true));
      final notices = <RecordNotice>[];
      final subscription = recorder.notices.listen(notices.add);
      addTearDown(subscription.cancel);
      final task = (await recorder.addTask(
        LiveRoom(roomId: '42062', platform: 'bilibili', nick: '主播', liveStatus: LiveStatus.live),
      ))!;
      await until(() => task.status == RecordStatus.running);
      expect(task.selectedQuality, '超清');
      await until(() => notices.isNotEmpty);
      expect(notices.single.kind, RecordNoticeKind.qualityLimited);
      expect(notices.single.quality, '超清');
    });

    test('a limited quality is said once per recording, not on every reconnect', () async {
      ffmpeg
        ..captureExit = 0
        ..captureSeconds = const Duration(seconds: 1);
      final recorder = recorderOf(_ConfirmingSite(applied: 'hd'));
      final limited = <RecordNotice>[];
      final subscription = recorder.notices
          .where((notice) => notice.kind == RecordNoticeKind.qualityLimited)
          .listen(limited.add);
      addTearDown(subscription.cancel);
      final task = (await recorder.addTask(
        LiveRoom(roomId: '1', platform: 'fake', nick: '主播', liveStatus: LiveStatus.live),
      ))!;
      await until(() => ffmpeg.runs.where((run) => !run.contains('concat')).length >= 2);
      expect(task.selectedQuality, '超清');
      expect(limited, hasLength(1));
      ffmpeg.captureExit = null;
      await recorder.stopTask(task);
      final runs = ffmpeg.runs.length;
      await recorder.startTask(task);
      await until(() => ffmpeg.runs.length > runs && task.status == RecordStatus.running);
      await until(() => limited.length == 2);
      expect(limited.last.quality, '超清', reason: 'a new recording says it again');
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
