import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_prefetch_plan.dart';
import 'package:pure_live/recorder/services/hls_prefetch_scheduler.dart';
import 'package:pure_live/recorder/services/hls_retained_window.dart';
import 'package:pure_live/recorder/services/hls_prefetch_pool.dart';

const master =
    '#EXTM3U\n#EXT-X-VERSION:7\n'
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="main",DEFAULT=YES,URI="audio/index.m3u8"\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=800000,CODECS="avc1.42c00d,mp4a.40.2",AUDIO="aud"\nvideo/index.m3u8\n';
final base = Uri.parse('https://fixture.invalid/live/master.m3u8');
HlsMediaSnapshot media(Uri source, {bool supported = true}) => HlsMediaSnapshot.parse(
  '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nbody.ts\n#EXT-X-ENDLIST\n'
  '${supported ? '' : '#EXT-X-UNSUPPORTED-FIXTURE\n'}',
  source,
);

void main() {
  test('one explicit video/audio group is resolved without selecting a different quality', () {
    final plan = HlsPrefetchPlan.fromMaster(master, base)!;
    expect(plan.sources, [base.resolve('video/index.m3u8'), base.resolve('audio/index.m3u8')]);
    expect(() => plan.sources.clear(), throwsUnsupportedError);
    expect(HlsPrefetchPlan.fromMaster('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv.m3u8\n', base)!.sources, [
      base.resolve('v.m3u8'),
    ]);
  });
  final rejected = <String, String>{
    'multiple variants': '$master#EXT-X-STREAM-INF:BANDWIDTH=2\nother.m3u8\n',
    'alternate audio': master.replaceFirst(
      '#EXT-X-STREAM-INF:',
      '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="other",URI="b.m3u8"\n#EXT-X-STREAM-INF:',
    ),
    'unmatched group': master.replaceFirst('AUDIO="aud"', 'AUDIO="missing"'),
    'unreferenced audio': master.replaceFirst(',AUDIO="aud"', ''),
    'duplicate field': master.replaceFirst('BANDWIDTH=800000', 'BANDWIDTH=800000,BANDWIDTH=1'),
    'dangling stream': master.replaceFirst('video/index.m3u8\n', ''),
    'empty uri': master.replaceFirst('URI="audio/index.m3u8"', 'URI=""'),
    'credentials': master.replaceFirst('audio/index.m3u8', 'https://user:pass@fixture.invalid/a.m3u8'),
    'downgrade': master.replaceFirst('audio/index.m3u8', 'http://fixture.invalid/a.m3u8'),
    'fragment': master.replaceFirst('audio/index.m3u8', 'a.m3u8#x'),
    'same source twice': master.replaceFirst('audio/index.m3u8', 'video/index.m3u8'),
    'session keys': '$master#EXT-X-SESSION-KEY:METHOD=AES-128,URI="k"\n',
    'subtitles': master.replaceFirst(',AUDIO="aud"', ',AUDIO="aud",SUBTITLES="s"'),
    'media not master': '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\ns.ts\n',
    'caption group': master.replaceFirst(',AUDIO="aud"', ',AUDIO="aud",CLOSED-CAPTIONS="cc"'),
    'invalid bandwidth': master.replaceFirst('BANDWIDTH=800000', 'BANDWIDTH=0'),
  };
  for (final entry in rejected.entries) {
    test('ambiguous or unsupported master keeps original path: ${entry.key}', () {
      expect(HlsPrefetchPlan.fromMaster(entry.value, base), isNull);
    });
  }
  test('batch validation is atomic including unsupported second feed, duplicate ids and capacity', () async {
    final pool = HlsPrefetchPool(createDirectory: () => throw StateError('Unexpected disk'));
    var downloads = 0;
    var observedFeedsAtFirstDownload = 0;
    late HlsPrefetchScheduler scheduler;
    scheduler = HlsPrefetchScheduler(
      pool: pool,
      fetchSnapshot: (_, _) => throw StateError('Ended feed refreshed'),
      loadResource: (_, _) async {
        observedFeedsAtFirstDownload = scheduler.feedCount;
        downloads++;
        return HlsPrefetchResponse(Stream.value([1]));
      },
    );
    final video = base.resolve('video.m3u8');
    final audio = base.resolve('audio.m3u8');
    final v = (id: 'v', source: video, snapshot: media(video));
    final a = (id: 'a', source: audio, snapshot: media(audio));
    try {
      expect(scheduler.selectAll([v, (id: 'a', source: audio, snapshot: media(audio, supported: false))]), false);
      expect(scheduler.selectAll([v, v]), false);
      expect(scheduler.selectAll([v, a, (id: 'third', source: audio, snapshot: media(audio))]), false);
      expect(scheduler.selectAll([v, (id: '', source: audio, snapshot: media(audio))]), false);
      expect(scheduler.selectAll([v, (id: 'a', source: Uri.parse('file:///tmp/x'), snapshot: media(audio))]), false);
      expect(scheduler.selectAll([]), false);
      expect(scheduler.feedCount, 0);
      expect(downloads, 0);
      expect(pool.ownedEntries, 0);
      expect(scheduler.selectAll([v, a]), true);
      expect(observedFeedsAtFirstDownload, 2);
      expect(scheduler.feedCount, 2);
      expect(scheduler.selectAll([v]), false);
      expect(scheduler.feedCount, 2);
    } finally {
      await scheduler.close();
    }
    expect(pool.ownedEntries, 0);
  });
}
