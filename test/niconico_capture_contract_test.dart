import 'package:flutter_test/flutter_test.dart';

import '../tool/probes/niconico_capture_contract.dart';

Map<String, Object?> capture(int video, int audio, double audioStart, double duration) => {
  'format': {'duration': '$duration'},
  'streams': [
    {'index': 0, 'codec_type': 'video'},
    {'index': 1, 'codec_type': 'audio'},
  ],
  'packets': [
    for (var i = 0; i < video; i++) packet(0, i / 30, 1 / 30),
    for (var i = 0; i < audio; i++) packet(1, audioStart + i * 1024 / 48000, 1024 / 48000),
  ],
};

Map<String, Object?> packet(int stream, double time, double duration) => {
  'stream_index': stream,
  'pts_time': '$time',
  'dts_time': '$time',
  'duration_time': '$duration',
};

void main() {
  test('six-second continuous audio/video satisfy the short probe contract', () {
    expect(inspectNiconicoCapture(capture(180, 282, 0.009, 6.025))['passed'], true);
  });
  test('first observed 90V/140A clock remains a short capture failure', () {
    final result = inspectNiconicoCapture(capture(90, 140, 0.020, 3.006667));
    expect(result['passed'], false);
    expect(
      result['failures'],
      containsAll(['container-duration', 'video-duration', 'audio-duration', 'common-duration']),
    );
  });
  test('six-second container with observed 180V/141A still fails the audio tail', () {
    final result = inspectNiconicoCapture(capture(180, 141, 0.009, 6.0));
    expect(result['passed'], false);
    expect(result['failures'], containsAll(['audio-duration', 'common-duration', 'av-tail']));
    expect(result['failures'], isNot(contains('container-duration')));
  });
  test('internal holes are not hidden by adequate duration', () {
    final input = capture(180, 282, 0.009, 6.025);
    (input['packets'] as List).removeAt(60);
    expect(inspectNiconicoCapture(input)['failures'], contains('video-gap'));
  });
  test('unknown packet duration remains unverified', () {
    final input = capture(180, 282, 0.009, 6.025);
    ((input['packets'] as List).first as Map).remove('duration_time');
    final result = inspectNiconicoCapture(input);
    expect(result['passed'], false);
    expect(result['failures'], contains('video-clock'));
  });
}
