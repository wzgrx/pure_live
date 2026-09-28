// 3.x's test/hls_master_selection_test.dart, without its prefetch-plan
// assertions (the recorder's HlsPrefetchPlan moves with M8).
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

const _master =
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

  test('each explicit variant keeps its associated audio', () {
    final master = HlsMasterPlaylist.parse(source, _master);
    expect(master.variants, hasLength(3));
    expect(master.variants.clear, throwsUnsupportedError);
    expect(master.variants.first.attributes.clear, throwsUnsupportedError);
    expect(master.variants.first.attributes['RESOLUTION'], '1280x720');
    expect(master.variants.first.attributes['CODECS'], 'avc1.640C1F,mp4a.40.2', reason: 'quotes removed');
    for (final variant in master.variants) {
      final selection = HlsMasterSelection.fromMaster(_master, source: source, video: variant.uri);
      expect(selection.audio, source.resolve('audio.m3u8'));
      final text = selection.rewrite(source, _master);
      expect(RegExp('#EXT-X-STREAM-INF:').allMatches(text), hasLength(1));
      expect(text, contains(variant.line));
      expect(text, contains('#EXT-X-INDEPENDENT-SEGMENTS'));
      expect(text, contains('NAME="Main Audio"'));
      expect(text.trim().split('\n').last, variant.uri.toString());
    }
  });

  test('the selection is exact rather than an index after the variants are reordered', () {
    final selection = HlsMasterSelection.fromMaster(_master, source: source, video: source.resolve('low.m3u8'));
    final blocks = _master.split('#EXT-X-STREAM-INF:');
    final reordered = blocks.first + blocks.skip(1).toList().reversed.map((block) => '#EXT-X-STREAM-INF:$block').join();
    expect(selection.rewrite(source, reordered), contains('BANDWIDTH=480000'));
    expect(selection.rewrite(source, reordered), isNot(contains('BANDWIDTH=3000000')));
  });

  test('another master session or removed selected media is an explicit failure', () {
    final selection = HlsMasterSelection.fromMaster(_master, source: source, video: source.resolve('high.m3u8'));
    expect(() => selection.rewrite(source.replace(query: 'grant=other'), _master), throwsFormatException);
    expect(() => selection.rewrite(source, _master.replaceAll('high.m3u8', 'new.m3u8')), throwsFormatException);
    expect(() => selection.rewrite(source, _master.replaceAll('audio.m3u8', 'new-audio.m3u8')), throwsFormatException);
  });

  test("several audio renditions need an explicit choice; the default is not the user's", () {
    final text = _master.replaceFirst(
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
  });

  test('muxed video does not acquire unrelated external audio', () {
    const text = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nmedia.m3u8\n';
    final selection = HlsMasterSelection.fromMaster(text, source: source, video: source.resolve('media.m3u8'));
    expect(selection.audio, isNull);
    expect(
      selection.rewrite(source, text),
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n${source.resolve('media.m3u8')}\n',
    );
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
    'missing header': _master.replaceFirst('#EXTM3U', '#comment'),
    'duplicate version': _master.replaceFirst('#EXT-X-VERSION:6', '#EXT-X-VERSION:6\n#EXT-X-VERSION:6'),
    'duplicate variant URI': _master.replaceAll('low.m3u8', 'high.m3u8'),
    'video root cycle': _master.replaceFirst('high.m3u8', source.toString()),
    'audio root cycle': _master.replaceFirst('audio.m3u8', source.toString()),
    'overlapping audio and video': _master.replaceFirst('high.m3u8', 'audio.m3u8'),
    'duplicate attribute': _master.replaceFirst('BANDWIDTH=3000000', 'BANDWIDTH=3000000,BANDWIDTH=1'),
    'dangling attributes': '$_master#EXT-X-STREAM-INF:BANDWIDTH=1\n',
    'missing audio group': _master.replaceFirst('GROUP-ID="main"', 'GROUP-ID="other"'),
    'subtitles': _master.replaceFirst('TYPE=AUDIO', 'TYPE=SUBTITLES'),
    'session key': '$_master#EXT-X-SESSION-KEY:METHOD=AES-128,URI="key"\n',
    'start policy': '$_master#EXT-X-START:TIME-OFFSET=-3\n',
    'downgrade': _master.replaceFirst('high.m3u8', 'http://media.test/high.m3u8'),
    'userinfo': _master.replaceFirst('high.m3u8', 'https://user@media.test/high.m3u8'),
    'fragment': _master.replaceFirst('high.m3u8', 'high.m3u8#wrong'),
    'bandwidth': _master.replaceFirst('BANDWIDTH=3000000', 'BANDWIDTH=-1'),
    'average bandwidth': _master.replaceFirst('BANDWIDTH=3000000', 'BANDWIDTH=3000000,AVERAGE-BANDWIDTH=NaN'),
    'frame rate': _master.replaceFirst('FRAME-RATE=30.000', 'FRAME-RATE=NaN'),
    'resolution': _master.replaceFirst('RESOLUTION=1280x720', 'RESOLUTION=0x720'),
    'empty codec': _master.replaceFirst('CODECS="avc1.640C1F,mp4a.40.2"', 'CODECS=""'),
    'closed captions': _master.replaceFirst('FRAME-RATE=30.000,', 'FRAME-RATE=30.000,CLOSED-CAPTIONS="cc",'),
    'unknown variant attribute': _master.replaceFirst('FRAME-RATE=30.000,', 'FRAME-RATE=30.000,HDCP-LEVEL=NONE,'),
    'too many variants': '#EXTM3U\n${List.generate(33, (i) => '#EXT-X-STREAM-INF:BANDWIDTH=1\nv$i.m3u8\n').join()}',
    'oversized': '#EXTM3U\n#${'x' * (4 * 1024 * 1024)}',
    'oversized in UTF-8': '#EXTM3U\n#${'配' * (2 * 1024 * 1024)}',
    'no variants': '#EXTM3U\n#EXT-X-VERSION:6\n',
  };
  for (final MapEntry(:key, :value) in invalid.entries) {
    test('rejects $key rather than silently dropping semantics', () {
      expect(() => HlsMasterPlaylist.parse(source, value), throwsFormatException);
    });
  }

  test('an insecure or credentialed master source is rejected', () {
    for (final bad in ['ftp://media.test/master.m3u8', 'https://user@media.test/master.m3u8', 'https:///m.m3u8']) {
      expect(() => HlsMasterPlaylist.parse(Uri.parse(bad), _master), throwsFormatException, reason: bad);
    }
  });
}
