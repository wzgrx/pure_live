import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../tool/probes/tting_hls_admission_summary.dart';

void main() {
  final source = Uri.parse('https://fixture.invalid/root.m3u8');
  test('qualification retains dimensions/order, not URI or arbitrary attribute text', () {
    const secret = 'private_fixture_token';
    final summary = ttingHlsAdmissionSummary(
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=200,RESOLUTION=1280x720,CODECS="$secret"\n'
      'https://fixture.invalid/a.m3u8?token=$secret\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=640x360\nb.m3u8\n',
      source,
    );
    expect(summary['unambiguousPlanAccepted'], false);
    expect(summary['variants'], [
      {'width': 1280, 'height': 720, 'bandwidth': 200},
      {'width': 640, 'height': 360, 'bandwidth': 100},
    ]);
    expect(jsonEncode(summary), isNot(contains(secret)));
    expect(jsonEncode(summary), isNot(contains('fixture.invalid')));
  });
  test('LL-HLS metadata admits complete parents without exposing partial resource names', () {
    final summary = ttingHlsAdmissionSummary(
      '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-PART-INF:PART-TARGET=0.5\n'
      '#EXT-X-SERVER-CONTROL:PART-HOLD-BACK=1.5\n'
      '#EXTINF:2,\nsegment.m4s\n#EXT-X-PART:DURATION=0.5,URI="secret-part.m4s"\n'
      '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="secret-next.m4s"\n',
      source,
    );
    expect(summary['snapshotParsed'], true);
    expect(summary['retentionAccepted'], true);
    expect(summary['partialSegmentCount'], 1);
    expect(summary['pendingPartialCount'], 1);
    expect(summary['preloadHintCount'], 1);
    expect(summary['recordingMode'], 'complete-parent-media');
    expect(summary['unhandledTags'], isEmpty);
    expect(jsonEncode(summary), isNot(contains('secret-')));
  });
  test('supported media and ambiguous malformed inputs have distinct results', () {
    final supported = ttingHlsAdmissionSummary('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\ns.ts\n', source);
    expect(supported['retentionAccepted'], true);
    expect(supported['segmentCount'], 1);
    final malformed = ttingHlsAdmissionSummary('#EXTM3U\n#EXTINF:2,\ns.ts\n', source);
    expect(malformed['snapshotParsed'], false);
    expect(malformed['retentionAccepted'], false);
  });
}
