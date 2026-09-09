import 'package:flutter_test/flutter_test.dart';

import '../tool/probes/media_packet_timeline.dart';

void main() {
  Map packet(int stream, Object? pts, Object? duration, {Object? dts}) => {
    'stream_index': stream,
    'pts_time': pts,
    'duration_time': duration,
    'dts_time': dts ?? pts,
  };
  Map<String, Object?> inspect(List<Map> packets, {List<Map>? streams}) => inspectMediaPacketTimeline({
    'streams':
        streams ??
        [
          {'index': 0, 'codec_type': 'video'},
          {'index': 1, 'codec_type': 'audio'},
        ],
    'packets': packets,
  });
  Map track(Map report, int index) => (report['tracks'] as List)[index] as Map;

  test('duration changes last PTS comparison into actual packet end comparison', () {
    final report = inspect([packet(0, 0, 1), packet(0, 1, 1), packet(1, 0, 2)]);
    expect(track(report, 0)['lastPts'], 1);
    expect(track(report, 1)['lastPts'], 0);
    expect((report['av'] as Map)['audioMinusVideoEndSeconds'], 0);
    expect((report['av'] as Map)['commonCoveredSeconds'], 2);
  });

  test('different tail lengths are not internal holes', () {
    final report = inspect([packet(0, 0, 2), packet(1, 0, 3)]);
    expect((report['av'] as Map)['audioMinusVideoEndSeconds'], 1);
    expect(track(report, 0)['knownInternalGapCount'], 0);
    expect(track(report, 1)['knownInternalGapCount'], 0);
  });

  test('same outer boundaries can hide interior gaps and shorter common coverage', () {
    final report = inspect([packet(0, 0, 1), packet(0, 2, 1), packet(1, 0, 3)]);
    expect((report['av'] as Map)['audioMinusVideoEndSeconds'], 0);
    expect((report['av'] as Map)['commonCoveredSeconds'], 2);
    expect(track(report, 0)['knownMaxInternalGapSeconds'], 1);
  });

  test('presentation reordering is not decode-order reversal', () {
    final report = inspect([packet(0, 0, 1, dts: -1), packet(0, 2, 1, dts: 0), packet(0, 1, 1, dts: 1)]);
    expect(track(report, 0)['observedDtsRegressions'], 0);
    expect(track(report, 0)['knownInternalGapCount'], 0);
    expect(track(report, 0)['knownPresentationEnd'], 3);
  });

  test('DTS reversal survives PTS sorting and missing DTS stays explicit', () {
    final report = inspect([packet(0, 0, 1, dts: 2), packet(0, 1, 1, dts: 'N/A'), packet(0, 2, 1, dts: 1)]);
    expect(track(report, 0)['observedDtsRegressions'], 1);
    expect(track(report, 0)['missingDtsPackets'], 1);
  });

  test('overlapping and duplicate packets do not inflate covered duration', () {
    final report = inspect([packet(0, 0, 2), packet(0, 1, 2), packet(0, 1, 1), packet(1, 0, 3)]);
    expect(track(report, 0)['packets'], 3);
    expect(track(report, 0)['knownCoveredSeconds'], 3);
    expect((report['av'] as Map)['commonCoveredSeconds'], 3);
  });

  test('negative timestamps remain signed and disjoint tracks have zero intersection', () {
    final report = inspect([packet(0, -2, 1), packet(1, 0, 1)]);
    expect((report['av'] as Map)['commonCoveredSeconds'], 0);
    expect((report['av'] as Map)['audioMinusVideoStartSeconds'], 2);
  });

  for (final invalid in [null, 'N/A', 'NaN', 'Infinity', -1, 0]) {
    test('unknown or invalid duration $invalid prevents an A/V boundary verdict', () {
      final report = inspect([packet(0, 0, invalid), packet(1, 0, 1)]);
      expect(report['av'], isNull);
      expect(track(report, 0)['completePresentationTimestamps'], false);
      expect(track(report, 0)['missingOrInvalidDurationPackets'], 1);
    });
  }

  test('unknown PTS counts packets without inventing presentation bounds', () {
    final report = inspect([packet(0, 'N/A', 1), packet(1, 0, 1)]);
    expect(track(report, 0)['packets'], 1);
    expect(track(report, 0)['firstPts'], isNull);
    expect(track(report, 0)['missingPtsPackets'], 1);
    expect(report['av'], isNull);
  });

  test('microsecond rounding seams coalesce but 10 ms holes remain', () {
    final report = inspect([
      packet(0, '0', '0.033333'),
      packet(0, '0.033334', '0.033333'),
      packet(0, '0.076667', '0.033333'),
    ]);
    expect(track(report, 0)['knownInternalGapCount'], 1);
    expect(track(report, 0)['knownMaxInternalGapSeconds'], closeTo(0.01, 0.000001));
  });

  test('multiple tracks and video-only inputs do not guess an A/V pair', () {
    for (final streams in [
      [
        {'index': 0, 'codec_type': 'video'},
      ],
      [
        {'index': 0, 'codec_type': 'video'},
        {'index': 1, 'codec_type': 'audio'},
        {'index': 2, 'codec_type': 'audio'},
      ],
    ]) {
      final report = inspect([for (final stream in streams) packet(stream['index'] as int, 0, 1)], streams: streams);
      expect(report['av'], isNull);
      expect(report['avUnavailableReason'], 'requires-one-video-and-one-audio-stream');
    }
  });

  test('empty tracks have no complete timestamp evidence', () {
    final report = inspect([]);
    expect(report['av'], isNull);
    expect(track(report, 0)['knownPresentationEnd'], isNull);
  });

  test('malformed descriptors and unowned packets fail explicitly', () {
    expect(() => inspect([packet(5, 0, 1)]), throwsFormatException);
    expect(
      () => inspect(
        [],
        streams: [
          {'index': 0, 'codec_type': 'video'},
          {'index': 0, 'codec_type': 'audio'},
        ],
      ),
      throwsFormatException,
    );
    expect(() => inspectMediaPacketTimeline({'streams': [], 'packets': 'invalid'}), throwsFormatException);
    expect(() => inspect(List.filled(100001, packet(0, 0, 1))), throwsFormatException);
  });
}
