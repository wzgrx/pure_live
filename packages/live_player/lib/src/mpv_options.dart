import 'package:meta/meta.dart';

/// The platforms mpv runs on, for option defaults.
enum MpvPlatform {
  /// Android.
  android,

  /// iOS.
  ios,

  /// Windows.
  windows,

  /// Linux.
  linux,

  /// macOS.
  macos,
}

/// How `MpvEngine` configures libmpv (3.x's `applyNativeLiveProperties`,
/// `LiveBufferPolicy` and `mpv_platform_profile.dart`, with the settings
/// they read passed in). One property set for the room player and every
/// multiview cell.
@immutable
final class MpvEngineConfig {
  /// Creates a configuration; the defaults are 3.x's default settings.
  const new({
    this.platform = MpvPlatform.android,
    this.hardwareDecoding = true,
    this.customOutput = false,
    this.videoOutputDriver = 'gpu',
    this.hardwareDecoder = 'auto',
    this.audioOutputDriver = 'auto',
    this.androidCompatibility = false,
    this.rtxVideoSuperResolution = false,
  });

  /// The platform the defaults are for.
  final MpvPlatform platform;

  /// 3.x's "硬件解码" (`enableCodec`): `auto-safe` when on, `no` when off.
  final bool hardwareDecoding;

  /// 3.x's expert output overrides (`customPlayerOutput`): use
  /// [videoOutputDriver], [hardwareDecoder] and [audioOutputDriver].
  final bool customOutput;

  /// mpv `vo` with [customOutput].
  final String videoOutputDriver;

  /// mpv `hwdec` with [customOutput].
  final String hardwareDecoder;

  /// mpv `ao` with [customOutput].
  final String audioOutputDriver;

  /// Android compatibility mode (`playerCompatMode`): `mediacodec_embed`
  /// output with `mediacodec` decoding.
  final bool androidCompatibility;

  /// Windows RTX Video Super Resolution (`enableRtxVsr`).
  final bool rtxVideoSuperResolution;

  /// Hardware decoders the settings may store per platform (iOS has its own
  /// list; the others share 3.x's `PlayerConsts.hardwareDecoder`).
  static const hardwareDecoders = {
    'no', 'auto', 'auto-safe', 'yes', 'auto-copy', 'd3d11va', 'd3d11va-copy', 'videotoolbox', //
    'videotoolbox-copy', 'vaapi', 'vaapi-copy', 'nvdec', 'nvdec-copy', 'drm', 'drm-copy', 'vulkan', 'vulkan-copy',
    'dxva2', 'dxva2-copy', 'vdpau', 'vdpau-copy', 'mediacodec', 'mediacodec-copy', 'cuda', 'cuda-copy', 'crystalhd',
    'rkmpp',
  };

  /// Hardware decoders the settings may store on iOS.
  static const iosHardwareDecoders = {'auto', 'auto-safe', 'auto-copy', 'no', 'videotoolbox', 'videotoolbox-copy'};

  /// Video outputs the settings may store (3.x's `PlayerConsts.videoOutputDrivers`;
  /// iOS only has `libmpv`).
  static const videoOutputDrivers = {
    'gpu', 'gpu-next', 'xv', 'x11', 'vdpau', 'direct3d', 'sdl', 'dmabuf-wayland', 'vaapi', 'null', 'libmpv', //
    'mediacodec_embed',
  };

  /// Audio drivers 3.x offered on Android.
  static const androidAudioOutputDrivers = {'auto', 'audiotrack', 'aaudio', 'opensles', 'null'};

  /// The `hwdec` of a hardware open (3.x's `_preferredHardwareDecoder`).
  String get preferredHardwareDecoder {
    if (platform == MpvPlatform.macos) return 'no';
    if (androidCompatibility && platform == MpvPlatform.android) return 'mediacodec';
    if (customOutput) {
      final known = platform == MpvPlatform.ios ? iosHardwareDecoders : hardwareDecoders;
      return known.contains(hardwareDecoder) ? hardwareDecoder : 'auto';
    }
    return hardwareDecoding ? 'auto-safe' : 'no';
  }

  /// The `hwdec` of an open; software decoding is `no`.
  String hwdecFor({required bool software}) => software ? 'no' : preferredHardwareDecoder;

  /// The `vo` of the video controller, or null for media_kit's default.
  String? get videoOutput {
    if (androidCompatibility && platform == MpvPlatform.android) return 'mediacodec_embed';
    if (customOutput) {
      if (platform == MpvPlatform.ios) return 'libmpv';
      return videoOutputDrivers.contains(videoOutputDriver) ? videoOutputDriver : 'gpu';
    }
    return null;
  }

  /// The `ao` sent to mpv (3.x's `effectiveMpvAudioOutputDriverForPlatform`):
  /// Android prefers AudioTrack with AAudio and OpenSL ES as fallbacks,
  /// Linux uses ALSA, the others keep mpv's default.
  String? get audioOutput {
    final platformDefault = switch (platform) {
      MpvPlatform.android => 'audiotrack,aaudio,opensles,',
      MpvPlatform.linux => 'alsa',
      _ => null,
    };
    if (!customOutput) return platformDefault;
    final driver = audioOutputDriver.trim();
    if (platform == MpvPlatform.android && (driver == 'auto' || !androidAudioOutputDrivers.contains(driver))) {
      return platformDefault;
    }
    return driver.isEmpty ? 'auto' : driver;
  }

  /// Whether audio is switched off (`ao=null`): an automatic recovery must
  /// not turn it on.
  bool get audioDisabled => customOutput && audioOutputDriver.trim() == 'null';

  /// Properties applied once after the player is created, in 3.x's order.
  Map<String, String> get liveProperties {
    final probe = mpvProbeValues();
    return {
      'force-seekable': 'yes',
      'protocol_whitelist': 'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto,rtmp,rtmps,rtsp,srt',
      // Live FLV/HLS need a short probe, not a long-file analysis pass
      // ([mpvProbeValues]).
      'demuxer-lavf-probesize': probe.probeSize,
      'demuxer-lavf-analyzeduration': probe.analyzeDuration,
      // Bounded live buffer (3.x's LiveBufferPolicy): memory only, small
      // forward and back windows, and the back cache may not borrow the
      // unused forward reserve.
      'cache': 'yes',
      'cache-on-disk': 'no',
      'cache-secs': '6',
      'demuxer-max-bytes': '${32 * 1024 * 1024}',
      'demuxer-max-back-bytes': '${4 * 1024 * 1024}',
      'demuxer-donate-buffer': 'no',
      'demuxer-readahead-secs': '2',
      'network-timeout': '15',
      // Leave a failing hardware decoder after the first failing frame.
      'hwdec-software-fallback': '1',
      'ao': ?audioOutput,
      if (platform == MpvPlatform.macos) 'hwdec': 'no',
      if (platform == MpvPlatform.windows && rtxVideoSuperResolution) ...{
        'hwdec': 'd3d11va',
        'vf': 'd3d11vpp=scale=2:scaling-mode=nvidia',
      },
    };
  }
}

/// `--dart-define=MPV_PROBESIZE=<bytes>` of the build, '' without one.
const String _probeSizeDefine = String.fromEnvironment('MPV_PROBESIZE');

/// `--dart-define=MPV_ANALYZEDURATION=<seconds>` of the build, '' without
/// one.
const String _analyzeDurationDefine = String.fromEnvironment('MPV_ANALYZEDURATION');

/// The probe without a build override (see [mpvProbeValues]).
const ({String probeSize, String analyzeDuration}) mpvProbeDefaults = (probeSize: '1048576', analyzeDuration: '1');

/// mpv's probe of a new input (`demuxer-lavf-probesize` in bytes,
/// `demuxer-lavf-analyzeduration` in seconds): 1 MiB / 1 s (G03.1: on the
/// K90 Bilibili's first frame came after 1802 ms with 3.x's 2 MiB / 2 s and
/// 708 ms with these, cold, median of 5, sound every time; its CDN sends
/// one or two seconds at once and then real time, so a 2 s analysis waits
/// for the stream; other platforms did not change), unless the build names
/// other values for an A/B on a phone: `flutter build apk --profile
/// --dart-define=MPV_PROBESIZE=2097152 --dart-define=MPV_ANALYZEDURATION=2`.
/// A value mpv would refuse (not a number, a probe under 32 bytes or over 2^31 - 1, a duration that is not
/// above 0 and at most 3600) keeps its default. The parameters exist for
/// tests; the app passes none.
({String probeSize, String analyzeDuration}) mpvProbeValues({
  String probeSize = _probeSizeDefine,
  String analyzeDuration = _analyzeDurationDefine,
}) {
  final size = int.tryParse(probeSize.trim());
  final seconds = double.tryParse(analyzeDuration.trim());
  return (
    probeSize: size != null && size >= 32 && size <= 0x7fffffff ? '$size' : mpvProbeDefaults.probeSize,
    analyzeDuration: seconds != null && seconds > 0 && seconds <= 3600
        ? analyzeDuration.trim()
        : mpvProbeDefaults.analyzeDuration,
  );
}
