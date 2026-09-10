import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_master_selection.dart';
import 'package:pure_live/recorder/services/hls_prefetch_plan.dart';

const selectedFixtureMaster =
    '#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-INDEPENDENT-SEGMENTS\n'
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="main",NAME="Main Audio",DEFAULT=YES,URI="audio.m3u8"\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=3000000,CODECS="avc1.640C1F,mp4a.40.2",RESOLUTION=1280x720,FRAME-RATE=30.000,AUDIO="main"\n'
    'high.m3u8\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=1500000,CODECS="avc1.4D401F,mp4a.40.2",RESOLUTION=854x480,FRAME-RATE=30.000,AUDIO="main"\n'
    'medium.m3u8\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=480000,CODECS="avc1.4D4015,mp4a.40.2",RESOLUTION=512x288,FRAME-RATE=30.000,AUDIO="main"\n'
    'low.m3u8\n';

void main() {
  final source = Uri.parse('https://media.test/session/master.m3u8?grant=fixture');
  test('each explicit variant retains its associated audio and enables unambiguous planning', () {
    final master = HlsMasterPlaylist.parse(source, selectedFixtureMaster);
    expect(master.variants.length, 3);
    expect(() => master.variants.clear(), throwsUnsupportedError);
    expect(() => master.variants.first.attributes.clear(), throwsUnsupportedError);
    expect(HlsPrefetchPlan.fromMaster(selectedFixtureMaster, source), isNull);
    for (final variant in master.variants) {
      final selection = HlsMasterSelection.fromMaster(selectedFixtureMaster, source: source, video: variant.uri);
      final text = selection.rewrite(source, selectedFixtureMaster);
      expect(RegExp('#EXT-X-STREAM-INF:').allMatches(text).length, 1);
      expect(text, contains(variant.line));
      expect(text, contains('#EXT-X-INDEPENDENT-SEGMENTS'));
      expect(text, contains('NAME="Main Audio"'));
      expect(HlsPrefetchPlan.fromMaster(text, source)!.sources, [variant.uri, source.resolve('audio.m3u8')]);
    }
  });
  test('selection remains exact rather than an index after variant reorder', () {
    final selection = HlsMasterSelection.fromMaster(
      selectedFixtureMaster,
      source: source,
      video: source.resolve('low.m3u8'),
    );
    final blocks = selectedFixtureMaster.split('#EXT-X-STREAM-INF:');
    final reordered = blocks.first + blocks.skip(1).toList().reversed.map((block) => '#EXT-X-STREAM-INF:$block').join();
    expect(selection.rewrite(source, reordered), contains('BANDWIDTH=480000'));
    expect(selection.rewrite(source, reordered), isNot(contains('BANDWIDTH=3000000')));
  });
  test('another master session or removed selected media is an explicit failure', () {
    final selection = HlsMasterSelection.fromMaster(
      selectedFixtureMaster,
      source: source,
      video: source.resolve('high.m3u8'),
    );
    expect(() => selection.rewrite(source.replace(query: 'grant=other'), selectedFixtureMaster), throwsFormatException);
    expect(
      () => selection.rewrite(source, selectedFixtureMaster.replaceAll('high.m3u8', 'new.m3u8')),
      throwsFormatException,
    );
    expect(
      () => selection.rewrite(source, selectedFixtureMaster.replaceAll('audio.m3u8', 'new-audio.m3u8')),
      throwsFormatException,
    );
  });
  test('multiple languages require an explicit audio choice; default is not user intent', () {
    final text = selectedFixtureMaster.replaceFirst(
      '#EXT-X-STREAM-INF:',
      '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="main",NAME="Other",URI="other.m3u8"\n#EXT-X-STREAM-INF:',
    );
    expect(
      () => HlsMasterSelection.fromMaster(text, source: source, video: source.resolve('high.m3u8')),
      throwsFormatException,
    );
    final selection = HlsMasterSelection.fromMaster(
      text,
      source: source,
      video: source.resolve('high.m3u8'),
      audio: source.resolve('other.m3u8'),
    );
    final output = selection.rewrite(source, text);
    expect(output, contains('NAME="Other"'));
    expect(output, isNot(contains('NAME="Main Audio"')));
    expect(HlsPrefetchPlan.fromMaster(output, source)!.sources.last, source.resolve('other.m3u8'));
  });
  test('muxed video does not acquire unrelated external audio', () {
    const text = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nmedia.m3u8\n';
    final selection = HlsMasterSelection.fromMaster(text, source: source, video: source.resolve('media.m3u8'));
    expect(selection.audio, isNull);
    expect(HlsPrefetchPlan.fromMaster(selection.rewrite(source, text), source)!.sources, [
      source.resolve('media.m3u8'),
    ]);
    expect(
      () => HlsMasterSelection.fromMaster(
        text,
        source: source,
        video: source.resolve('media.m3u8'),
        audio: source.resolve('audio.m3u8'),
      ),
      throwsFormatException,
    );
  });
  final invalid = <String, String>{
    'media playlist': '#EXTM3U\n#EXTINF:3,\nmedia.ts\n',
    'missing header': selectedFixtureMaster.replaceFirst('#EXTM3U', '#comment'),
    'duplicate version': selectedFixtureMaster.replaceFirst('#EXT-X-VERSION:6', '#EXT-X-VERSION:6\n#EXT-X-VERSION:6'),
    'duplicate variant URI': selectedFixtureMaster.replaceAll('low.m3u8', 'high.m3u8'),
    'video root cycle': selectedFixtureMaster.replaceFirst('high.m3u8', source.toString()),
    'audio root cycle': selectedFixtureMaster.replaceFirst('audio.m3u8', source.toString()),
    'overlapping audio and video': selectedFixtureMaster.replaceFirst('high.m3u8', 'audio.m3u8'),
    'duplicate attribute': selectedFixtureMaster.replaceFirst('BANDWIDTH=3000000', 'BANDWIDTH=3000000,BANDWIDTH=1'),
    'dangling attributes': '$selectedFixtureMaster#EXT-X-STREAM-INF:BANDWIDTH=1\n',
    'missing audio group': selectedFixtureMaster.replaceFirst('GROUP-ID="main"', 'GROUP-ID="other"'),
    'subtitles': selectedFixtureMaster.replaceFirst('TYPE=AUDIO', 'TYPE=SUBTITLES'),
    'session key': '$selectedFixtureMaster#EXT-X-SESSION-KEY:METHOD=AES-128,URI="key"\n',
    'start policy': '$selectedFixtureMaster#EXT-X-START:TIME-OFFSET=-3\n',
    'downgrade': selectedFixtureMaster.replaceFirst('high.m3u8', 'http://media.test/high.m3u8'),
    'userinfo': selectedFixtureMaster.replaceFirst('high.m3u8', 'https://user@media.test/high.m3u8'),
    'fragment': selectedFixtureMaster.replaceFirst('high.m3u8', 'high.m3u8#wrong'),
    'bandwidth': selectedFixtureMaster.replaceFirst('BANDWIDTH=3000000', 'BANDWIDTH=-1'),
    'average bandwidth': selectedFixtureMaster.replaceFirst(
      'BANDWIDTH=3000000',
      'BANDWIDTH=3000000,AVERAGE-BANDWIDTH=NaN',
    ),
    'frame rate': selectedFixtureMaster.replaceFirst('FRAME-RATE=30.000', 'FRAME-RATE=NaN'),
    'resolution': selectedFixtureMaster.replaceFirst('RESOLUTION=1280x720', 'RESOLUTION=0x720'),
    'empty codec': selectedFixtureMaster.replaceFirst('CODECS="avc1.640C1F,mp4a.40.2"', 'CODECS=""'),
    'too many variants': '#EXTM3U\n${List.generate(33, (i) => '#EXT-X-STREAM-INF:BANDWIDTH=1\nv$i.m3u8\n').join()}',
    'oversized': '#EXTM3U\n#${'x' * (4 * 1024 * 1024)}',
  };
  for (final entry in invalid.entries) {
    test('selection rejects ${entry.key} rather than silently dropping semantics', () {
      expect(() => HlsMasterPlaylist.parse(source, entry.value), throwsFormatException);
    });
  }
}
