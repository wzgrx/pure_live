import 'package:flutter_test/flutter_test.dart';

import '../tool/probes/recording_clock_probe_support.dart';

void main() {
  String value(List<String> args, String key) => args[args.indexOf(key) + 1];
  test('legacy observations retain exact selected stream and authored cadence', () {
    final video = buildClockDecodeArguments('input path.flv', 'video');
    expect(value(video, '-i'), 'input path.flv');
    expect(value(video, '-map'), '0:v:0');
    expect(value(video, '-pix_fmt'), 'yuv420p');
    expect(value(video, '-fps_mode'), 'passthrough');
    expect(value(video, '-enc_time_base'), 'demux');
    expect(value(buildClockDecodeArguments('input', 'audio'), '-map'), '0:a:0');
  });
  test('multi-audio evidence selects each distinct ordinal rather than repeating track zero', () {
    final first = buildClockDecodeArguments('input.ts', 'audio_0');
    final second = buildClockDecodeArguments('input.ts', 'audio_1');
    expect(value(first, '-map'), '0:a:0');
    expect(value(second, '-map'), '0:a:1');
    expect(second.where((value) => value == '-map'), hasLength(1));
    expect(second, isNot(contains('-pix_fmt')));
  });
  test('ten-bit video is observed without silently reducing decoded precision', () {
    final args = buildClockDecodeArguments('input.ts', 'video_0', pixelFormat: 'yuv420p10le');
    expect(value(args, '-pix_fmt'), 'yuv420p10le');
    expect(value(args, '-c:v'), 'rawvideo');
  });
  test('invalid or excessive observation selectors are rejected before process launch', () {
    for (final label in ['audio_64', 'video_100', 'audio_1/../x', 'subtitle_0', 'video_-1']) {
      expect(() => buildClockDecodeArguments('input', label), throwsArgumentError);
    }
    expect(() => buildClockDecodeArguments('input', 'video', pixelFormat: 'yuv420p\n-map'), throwsArgumentError);
  });
}
