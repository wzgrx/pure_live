import 'dart:ffi' show Abi;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('live properties keep 3.x values and the bounded buffer', () {
    const config = MpvEngineConfig();
    final properties = config.liveProperties;
    expect(properties['demuxer-lavf-probesize'], '2097152');
    expect(properties['demuxer-lavf-analyzeduration'], '2');
    expect(properties['network-timeout'], '15');
    expect(properties['hwdec-software-fallback'], '1');
    expect(properties['demuxer-max-bytes'], '33554432');
    expect(properties['demuxer-max-back-bytes'], '4194304');
    expect(properties['demuxer-donate-buffer'], 'no');
    expect(properties['cache-on-disk'], 'no');
    expect(properties['ao'], 'audiotrack,aaudio,opensles,');
    expect(properties.containsKey('hwdec'), isFalse);
    expect(const MpvEngineConfig(platform: MpvPlatform.macos).liveProperties['hwdec'], 'no');
    expect(
      const MpvEngineConfig(platform: MpvPlatform.windows, rtxVideoSuperResolution: true).liveProperties['vf'],
      'd3d11vpp=scale=2:scaling-mode=nvidia',
    );
  });

  test('G03.1: the probe keeps 3.x values unless the build overrides them', () {
    // No --dart-define in the test run: 3.x's 2 MiB / 2 s.
    expect(mpvProbeValues(), (probeSize: '2097152', analyzeDuration: '2'));
    expect(mpvProbeValues(probeSize: '1048576', analyzeDuration: '1'), (probeSize: '1048576', analyzeDuration: '1'));
    expect(mpvProbeValues(probeSize: ' 524288 ', analyzeDuration: '0.5'), (
      probeSize: '524288',
      analyzeDuration: '0.5',
    ));
    // Each value falls back on its own; mpv refuses a probe under 32 bytes.
    expect(mpvProbeValues(probeSize: '31', analyzeDuration: '1'), (probeSize: '2097152', analyzeDuration: '1'));
    for (final bad in ['', 'abc', '-1', '0', '1e400', 'NaN', '99999999999']) {
      expect(mpvProbeValues(probeSize: bad, analyzeDuration: bad), (
        probeSize: '2097152',
        analyzeDuration: '2',
      ), reason: bad);
    }
    expect(mpvProbeValues(analyzeDuration: '3601'), (probeSize: '2097152', analyzeDuration: '2'));
    final overridden = const MpvEngineConfig().liveProperties;
    expect(overridden['demuxer-lavf-probesize'], mpvProbeValues().probeSize);
    expect(overridden['demuxer-lavf-analyzeduration'], mpvProbeValues().analyzeDuration);
  });

  test('decoder and output choices follow 3.x settings', () {
    expect(const MpvEngineConfig().hwdecFor(software: false), 'auto-safe');
    expect(const MpvEngineConfig().hwdecFor(software: true), 'no');
    expect(const MpvEngineConfig(hardwareDecoding: false).preferredHardwareDecoder, 'no');
    expect(const MpvEngineConfig(androidCompatibility: true).preferredHardwareDecoder, 'mediacodec');
    expect(const MpvEngineConfig(androidCompatibility: true).videoOutput, 'mediacodec_embed');
    expect(const MpvEngineConfig(customOutput: true, hardwareDecoder: 'bogus').preferredHardwareDecoder, 'auto');
    expect(const MpvEngineConfig(customOutput: true).audioOutput, 'audiotrack,aaudio,opensles,');
    expect(
      const MpvEngineConfig(platform: MpvPlatform.windows, customOutput: true, audioOutputDriver: 'wasapi').audioOutput,
      'wasapi',
    );
    expect(const MpvEngineConfig(customOutput: true, audioOutputDriver: 'null').audioDisabled, isTrue);
    expect(const MpvEngineConfig(platform: MpvPlatform.linux).audioOutput, 'alsa');
  });

  test('HEVC FLV is rewritten only where the bundled FFmpeg is older or unknown', () {
    expect(nativeBundleTarget(Abi.androidArm64), 'android_arm64');
    expect(mpvEngineProfile(Abi.androidArm64).rewriteLegacyHevcFlv, isFalse);
    expect(mpvEngineProfile(Abi.windowsX64).rewriteLegacyHevcFlv, isFalse);
    expect(mpvEngineProfile(Abi.linuxX64).rewriteLegacyHevcFlv, isFalse);
    expect(mpvEngineProfile(Abi.androidIA32).rewriteLegacyHevcFlv, isTrue);
    expect(mpvEngineProfile(Abi.macosArm64).rewriteLegacyHevcFlv, isTrue);
  });

  test('display size applies rotation and needs both sides', () {
    expect(displaySizeOf(const VideoParams(w: 1920, h: 1080)), (width: 1920, height: 1080));
    expect(displaySizeOf(const VideoParams(dw: 1080, dh: 1920, rotate: 90)), (width: 1920, height: 1080));
    expect(displaySizeOf(const VideoParams(w: 1920)), isNull);
  });

  test('background playback and room volume keep 3.x rules', () {
    expect(shouldContinueInBackground(backgroundPlaybackEnabled: false, sleepSessionActive: false), isFalse);
    expect(shouldContinueInBackground(backgroundPlaybackEnabled: true, sleepSessionActive: false), isTrue);
    expect(shouldContinueInBackground(backgroundPlaybackEnabled: false, sleepSessionActive: true), isTrue);
    expect(roomVolumeKey('Douyu ', ' 9999 '), 'room_vol_douyu_9999');
    final saved = {'room_vol_douyu_9999': 1.4};
    double volume({bool mute = false, bool mobile = false, String room = '9999'}) =>
        roomVolume(platform: 'douyu', roomId: room, saved: saved, globalMute: mute, mobile: mobile);
    expect(volume(), 1);
    expect(volume(mute: true), 0);
    expect(volume(room: '1', mobile: true), 0.5);
    expect(volume(room: '1'), 1);
  });
}
