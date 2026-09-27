import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

final Uri _base = Uri.parse('https://cdn.test/live/stream/index.m3u8?token=abc');

M3u8Media _media(String text) => M3u8Playlist.parse(text, _base) as M3u8Media;

void main() {
  test('a live media playlist: numbering, durations, absolute URIs', () {
    final playlist = _media('''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:1041
#EXT-X-DISCONTINUITY-SEQUENCE:7
#EXT-X-PROGRAM-DATE-TIME:2026-09-28T02:17:33.120Z
#EXTINF:2.002,live
1041.ts?x=1
#EXTINF:1.998,
/abs/1042.ts
#EXT-X-DISCONTINUITY
#EXTINF:2.000,Amazon|ad
https://ads.test/1043.ts
''');
    expect(playlist.targetDuration, 2);
    expect(playlist.mediaSequence, 1041);
    expect([for (final s in playlist.segments) s.sequence], [1041, 1042, 1043]);
    expect(playlist.segments.first.uri, Uri.parse('https://cdn.test/live/stream/1041.ts?x=1'));
    expect(playlist.segments[1].uri, Uri.parse('https://cdn.test/abs/1042.ts'));
    expect(playlist.segments[2].uri.host, 'ads.test');
    expect(playlist.segments.first.durationMs, 2002);
    expect(playlist.segments.first.title, 'live');
    expect([for (final s in playlist.segments) s.discontinuity], [false, false, true]);
    expect([for (final s in playlist.segments) s.discontinuitySequence], [7, 7, 8]);
    expect(playlist.endList, isFalse);
    expect(playlist.lastSequence, 1043);
  });

  test('a VOD playlist ends with EXT-X-ENDLIST; missing TARGETDURATION falls back to the longest EXTINF', () {
    final playlist = _media('#EXTM3U\n#EXTINF:5.5,\na.ts\n#EXTINF:4,\nb.ts\n#EXT-X-ENDLIST\n');
    expect(playlist.endList, isTrue);
    expect(playlist.targetDuration, 6);
    expect(playlist.mediaSequence, 0);
  });

  test('byte ranges: implicit offsets become absolute when parsed (REG-RECORD-029)', () {
    final playlist = _media('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:9
#EXTINF:2,
#EXT-X-BYTERANGE:1000@500
all.ts
#EXTINF:2,
#EXT-X-BYTERANGE:800
all.ts
#EXTINF:2,
#EXT-X-BYTERANGE:700
all.ts
''');
    expect(
      [for (final s in playlist.segments) s.range],
      [const M3u8ByteRange(500, 1000), const M3u8ByteRange(1500, 800), const M3u8ByteRange(2300, 700)],
    );
    expect(playlist.segments.last.range!.header, 'bytes=2300-2999');
    expect(
      () => _media('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n#EXT-X-BYTERANGE:10\na.ts\n'),
      throwsFormatException,
      reason: 'an implicit offset needs a previous range of the same resource',
    );
  });

  test('keys: AES-128 with and without IV, NONE clears, SAMPLE-AES and DRM formats are unsupported', () {
    final playlist = _media('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2,
clear.ts
#EXT-X-KEY:METHOD=AES-128,URI="key1",IV=0x000102030405060708090A0B0C0D0E0F
#EXTINF:2,
a.ts
#EXT-X-KEY:METHOD=AES-128,URI="https://keys.test/k2"
#EXTINF:2,
b.ts
#EXT-X-KEY:METHOD=NONE
#EXTINF:2,
c.ts
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://x",KEYFORMAT="com.apple.streamingkeydelivery"
#EXTINF:2,
d.ts
#EXT-X-KEY:METHOD=NONE
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="k3"
#EXTINF:2,
e.ts
''');
    final keys = [for (final s in playlist.segments) s.key];
    expect(keys[0].method, M3u8KeyMethod.none);
    expect(keys[1].method, M3u8KeyMethod.aes128);
    expect(keys[1].uri, Uri.parse('https://cdn.test/live/stream/key1'));
    expect(keys[1].iv, List.generate(16, (i) => i));
    expect(keys[2].iv, isNull, reason: 'the media sequence number is the IV');
    expect(keys[3].method, M3u8KeyMethod.none);
    expect(keys[4].method, M3u8KeyMethod.unsupported);
    expect(keys[5].method, M3u8KeyMethod.unsupported);
    expect(keys[5].detail, 'SAMPLE-AES');
  });

  test('EXT-X-MAP applies to the following segments and remembers its key', () {
    final playlist = _media('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXT-X-MAP:URI="init-1.mp4",BYTERANGE="720@0"
#EXTINF:2,
s1.m4s
#EXT-X-KEY:METHOD=AES-128,URI="k",IV=0x1
#EXT-X-MAP:URI="init-2.mp4"
#EXTINF:2,
s2.m4s
''');
    final first = playlist.segments.first.map!;
    expect(first.uri.path, '/live/stream/init-1.mp4');
    expect(first.range, const M3u8ByteRange(0, 720));
    final second = playlist.segments.last.map!;
    expect(second.key.method, M3u8KeyMethod.aes128);
    expect(second.key.iv!.last, 1);
    expect(first == second, isFalse);
  });

  test('LL-HLS: parts and preload hints are not segments (REG-RECORD-028)', () {
    final playlist = _media('''
#EXTM3U
#EXT-X-TARGETDURATION:4
#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,CAN-SKIP-UNTIL=24
#EXT-X-PART-INF:PART-TARGET=1.0
#EXT-X-MEDIA-SEQUENCE:50
#EXT-X-PART:DURATION=1,URI="50.0.m4s",INDEPENDENT=YES
#EXT-X-PART:DURATION=1,URI="50.1.m4s"
#EXTINF:4,
50.m4s
#EXT-X-PART:DURATION=1,URI="51.0.m4s"
#EXT-X-PRELOAD-HINT:TYPE=PART,URI="51.1.m4s"
''');
    expect(playlist.hasParts, isTrue);
    expect([for (final s in playlist.segments) s.uri.pathSegments.last], ['50.m4s']);
    expect(playlist.segments.single.sequence, 50);
  });

  test('a delta update (EXT-X-SKIP) is refused: its segments cannot be numbered (REG-RECORD-027)', () {
    expect(
      () => _media('#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-SKIP:SKIPPED-SEGMENTS=10\n#EXTINF:4,\na.m4s\n'),
      throwsFormatException,
    );
  });

  test('EXT-X-GAP marks a segment the server does not have', () {
    final playlist = _media('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\na.ts\n#EXT-X-GAP\n#EXTINF:2,\nb.ts\n');
    expect([for (final s in playlist.segments) s.gap], [false, true]);
  });

  test('a master playlist: variants, renditions, the best variant and separate audio', () {
    final master = M3u8Playlist.parse('''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="English",DEFAULT=YES,URI="audio/en.m3u8"
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="chunked",NAME="1080p60 (source)",AUTOSELECT=YES
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS="avc1.64002A,mp4a.40.2",VIDEO="chunked"
chunked/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=640x360,CODECS="avc1.4D401E,mp4a.40.2",AUDIO="aac"
low/index.m3u8
#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=100000,URI="iframes.m3u8"
''', _base) as M3u8Master;
    expect(master.variants, hasLength(2));
    expect(master.best!.uri, Uri.parse('https://cdn.test/live/stream/chunked/index.m3u8'));
    expect(master.best!.codecs, 'avc1.64002A,mp4a.40.2');
    expect(master.separateAudio(master.best!), isEmpty, reason: 'muxed audio');
    expect(master.separateAudio(master.variants.last).single.uri!.path, '/live/stream/audio/en.m3u8');
    expect(master.renditions.where((r) => r.type == 'VIDEO').single.uri, isNull);
  });

  test('not a playlist', () {
    expect(() => M3u8Playlist.parse('<html>403</html>', _base), throwsFormatException);
    expect(() => M3u8Playlist.parse('', _base), throwsFormatException);
    expect(() => _media('#EXTM3U\n#EXT-X-TARGETDURATION:x\n'), throwsFormatException);
  });

  test('a byte order mark and CRLF line ends are accepted', () {
    final playlist = _media('﻿#EXTM3U\r\n#EXT-X-TARGETDURATION:2\r\n#EXTINF:2,\r\na.ts\r\n');
    expect(playlist.segments.single.uri.path, '/live/stream/a.ts');
  });
}
