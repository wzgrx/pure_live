import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  test('live property set follows PERF-3 and PERF-4', () {
    expect(const MpvEngineConfig().liveProperties, {
      'demuxer-lavf-probesize': '2097152',
      'demuxer-lavf-analyzeduration': '2',
      'network-timeout': '15',
      'hwdec-software-fallback': '1',
      'force-seekable': 'yes',
      'cache': 'yes',
      'cache-on-disk': 'no',
      'cache-secs': '6',
      'demuxer-max-bytes': '33554432',
      'demuxer-max-back-bytes': '4194304',
      'demuxer-readahead-secs': '2',
      'protocol_whitelist': 'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto',
    });
    final lowLatency = const MpvEngineConfig(lowLatency: true, audioOutput: 'opensles').liveProperties;
    expect(lowLatency['cache-secs'], '2');
    expect(lowLatency['ao'], 'opensles');
  });

  test('hardware decoding by default, software for a retry or when switched off (REC-1, SURF-6)', () {
    const config = MpvEngineConfig();
    expect(config.hwdecFor(softwareDecoding: false), 'auto-safe');
    expect(config.hwdecFor(softwareDecoding: true), 'no');
    expect(const MpvEngineConfig(hardwareDecoding: false).hwdecFor(softwareDecoding: false), 'no');
    expect(const MpvEngineConfig(androidCompatibility: true).hwdecFor(softwareDecoding: false), 'mediacodec');
  });

  group('output size (PERF-1)', () {
    test('covers the physical viewport with even sides and the source aspect', () {
      expect(
        videoOutputSize(
          viewport: const Size(640, 360),
          pixelRatio: 1.5,
          fit: VideoFit.contain,
          sourceWidth: 1920,
          sourceHeight: 1080,
        ),
        const Size(960, 540),
      );
      expect(
        videoOutputSize(
          viewport: const Size(400, 400),
          pixelRatio: 1,
          fit: VideoFit.cover,
          sourceWidth: 1920,
          sourceHeight: 1080,
        ),
        const Size(712, 400),
      );
      expect(
        videoOutputSize(
          viewport: const Size(400, 400),
          pixelRatio: 1,
          fit: VideoFit.contain,
          sourceWidth: 1920,
          sourceHeight: 1080,
        ),
        const Size(400, 226),
      );
    });

    test('never exceeds the source and assumes 1080p when unknown', () {
      expect(
        videoOutputSize(
          viewport: const Size(3840, 2160),
          pixelRatio: 2,
          fit: VideoFit.contain,
          sourceWidth: 1280,
          sourceHeight: 720,
        ),
        const Size(1280, 720),
      );
      expect(
        videoOutputSize(viewport: const Size(960, 540), pixelRatio: 1, fit: VideoFit.contain),
        const Size(960, 540),
      );
      expect(videoOutputSize(viewport: Size.zero, pixelRatio: 1, fit: VideoFit.fill), Size.zero);
    });
  });
}
