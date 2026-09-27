import 'dart:typed_data';

import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

import 'support/synthetic_flv.dart';

void main() {
  const flv = SyntheticFlv();

  List<int> stream() => [
    ...FlvTag.fileHeader(),
    ...SyntheticFlv.script(0),
    ...flv.videoConfig(0),
    ...SyntheticFlv.audioConfig(0),
    for (final tag in flv.tags(0, 2000)) ...tag,
  ];

  test('frames a stream split at every possible chunk boundary', () {
    final bytes = stream();
    final expected = FlvFramer().add(bytes);
    expect(expected.first, FlvTag.fileHeader());
    expect(expected.length, 4 + flv.tags(0, 2000).length);
    for (final size in [1, 3, 11, 13, 17, 4096]) {
      final framer = FlvFramer();
      final packets = <Uint8List>[];
      for (var i = 0; i < bytes.length; i += size) {
        packets.addAll(framer.add(bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size)));
      }
      expect(packets, expected, reason: 'chunk size $size');
      expect(framer.pending, 0);
    }
  });

  test('rejects data that is not FLV and tags with an invalid type', () {
    expect(() => FlvFramer().add('<html>not media</html>'.codeUnits), throwsFormatException);
    final framer = FlvFramer()..add(FlvTag.fileHeader());
    expect(() => framer.add(List.filled(15, 0x33)), throwsFormatException);
  });

  test('reads and rewrites timestamps including the extension byte', () {
    final tag = SyntheticFlv.video(0x01234567 & 0xffffff, key: true);
    final moved = FlvTag.withTimestamp(tag, 0x7f000010);
    expect(FlvTag.timestamp(moved), 0x7f000010);
    expect(FlvTag.dataSize(moved), FlvTag.dataSize(tag));
    expect(moved.sublist(8), tag.sublist(8));
    expect(FlvTag.timestamp(FlvTag.withTimestamp(tag, 0x100000000 + 5)), 5);
  });

  test('classifies configurations, keyframes and frames', () {
    expect(FlvTag.isVideoConfig(flv.videoConfig(0)), isTrue);
    expect(FlvTag.isKeyframe(flv.videoConfig(0)), isFalse);
    expect(FlvTag.isKeyframe(SyntheticFlv.video(0, key: true)), isTrue);
    expect(FlvTag.isKeyframe(SyntheticFlv.video(40, key: false)), isFalse);
    expect(FlvTag.isAudioConfig(SyntheticFlv.audioConfig(0)), isTrue);
    expect(FlvTag.isAudioConfig(SyntheticFlv.audio(23)), isFalse);
    // Enhanced FLV (hvc1): IsExHeader | keyframe | SequenceStart / CodedFrames.
    final enhancedConfig = FlvTag.build(type: FlvTag.video, timestamp: 0, data: [0x90, 0x68, 0x76, 0x63, 0x31, 1]);
    final enhancedKey = FlvTag.build(type: FlvTag.video, timestamp: 0, data: [0x91, 0x68, 0x76, 0x63, 0x31, 1]);
    expect(FlvTag.isVideoConfig(enhancedConfig), isTrue);
    expect(FlvTag.isKeyframe(enhancedKey), isTrue);
    expect(FlvTag.samePayload(flv.videoConfig(0), flv.videoConfig(500)), isTrue);
    expect(FlvTag.samePayload(flv.videoConfig(0), const SyntheticFlv(videoConfigPayload: [9]).videoConfig(0)), isFalse);
  });

  test('builds tags with a matching PreviousTagSize', () {
    final tag = FlvTag.build(type: FlvTag.audio, timestamp: 7, data: [1, 2, 3]);
    expect(tag.length, 11 + 3 + 4);
    expect(ByteData.sublistView(tag).getUint32(14), 14);
  });
}
