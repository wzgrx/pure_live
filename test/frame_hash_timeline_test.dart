import 'package:flutter_test/flutter_test.dart';

import '../tool/probes/frame_hash_timeline.dart';

String fixture(List<int> pts, {List<int>? content}) =>
    '#tb 0: 1/1000\n${[for (var i = 0; i < pts.length; i++) '0, ${pts[i]}, ${pts[i]}, 50, 100, ${(content?[i] ?? i).toRadixString(16).padLeft(32, '0')}'].join('\n')}\n';

void main() {
  test('constant start offset is separate from a seam step', () {
    final source = FrameHashTimeline.parse(fixture([0, 50, 100, 150]));
    final normal = source.compare(FrameHashTimeline.parse(fixture([500, 550, 600, 650])));
    expect(normal['orderedContentEqual'], true);
    expect(normal['offsetSpreadSeconds'], closeTo(0, 1e-10));
    final drift = source.compare(FrameHashTimeline.parse(fixture([500, 550, 690, 740])));
    expect(drift['orderedContentEqual'], true);
    expect(drift['offsetSpreadSeconds'], closeTo(0.09, 1e-10));
  });
  test('VFR source gaps are retained rather than repaired to nominal FPS', () {
    final source = FrameHashTimeline.parse(fixture([0, 50, 200, 250]));
    expect(
      source.compare(FrameHashTimeline.parse(fixture([1000, 1050, 1200, 1250])))['offsetSpreadSeconds'],
      closeTo(0, 1e-10),
    );
    expect(
      source.compare(FrameHashTimeline.parse(fixture([0, 50, 100, 150])))['offsetSpreadSeconds'],
      closeTo(0.1, 1e-10),
    );
  });
  test('loss, duplicate and reordering suppress misleading timestamp agreement', () {
    final source = FrameHashTimeline.parse(fixture([0, 50, 100]));
    for (final other in [
      fixture([0, 50]),
      fixture([0, 50, 100], content: [0, 0, 2]),
      fixture([0, 50, 100], content: [0, 2, 1]),
    ]) {
      final result = source.compare(FrameHashTimeline.parse(other));
      expect(result['orderedContentEqual'], false);
      expect(result['firstContentMismatch'], isNotNull);
      expect(result['offsetSpreadSeconds'], isNull);
    }
  });
  test('different rational time bases compare in seconds without guessing FPS', () {
    final source = FrameHashTimeline.parse(fixture([0, 50]));
    final other = fixture([0, 4500]).replaceFirst('1/1000', '1/90000');
    expect(source.compare(FrameHashTimeline.parse(other))['offsetSpreadSeconds'], closeTo(0, 1e-10));
  });
  for (final text in [
    '',
    '#tb 0: 1/0\n',
    fixture([0]).replaceFirst('0, 0,', '1, 0,'),
    fixture([0]).replaceFirst('1/1000', 'bad'),
    fixture([0]).replaceFirst('100,', '-1,'),
    fixture([0]).replaceFirst('#tb 0: 1/1000', '#tb 0: 1/1000\n#tb 0: 1/1000'),
  ]) {
    test('rejects malformed frame hash ${text.hashCode}', () {
      expect(() => FrameHashTimeline.parse(text), throwsFormatException);
    });
  }
}
