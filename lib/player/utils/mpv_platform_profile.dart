import 'package:flutter/foundation.dart';
import 'package:pure_live/player/utils/player_consts.dart';

const Map<String, String> _iosVideoOutputDrivers = <String, String>{'libmpv': 'libmpv'};
const Map<String, String> _iosAudioOutputDrivers = <String, String>{
  'auto': 'auto',
  'audiounit': 'audiounit (iOS only)',
  'null': 'null (No audio output)',
};
const Map<String, String> _iosHardwareDecoders = <String, String>{
  'auto': 'auto',
  'auto-safe': 'auto-safe',
  'auto-copy': 'auto-copy',
  'no': 'no',
  'videotoolbox': 'videotoolbox',
  'videotoolbox-copy': 'videotoolbox-copy',
};

/// Returns only native MPV outputs that the current settings UI may persist.
///
/// media_kit owns the iOS Flutter texture through `vo=libmpv`. Android and
/// desktop keep their existing expert list; filtering those platforms needs
/// separate native evidence because their output backends differ.
Map<String, String> mpvVideoOutputDriversForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? _iosVideoOutputDrivers : PlayerConsts.videoOutputDrivers;

Map<String, String> mpvAudioOutputDriversForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? _iosAudioOutputDrivers : PlayerConsts.audioOutputDrivers;

Map<String, String> mpvHardwareDecodersForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? _iosHardwareDecoders : PlayerConsts.hardwareDecoder;

String defaultMpvVideoOutputDriverForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? 'libmpv' : 'gpu';

String normalizeMpvVideoOutputDriverForPlatform(String value, TargetPlatform platform) => _normalizeMpvOption(
  value,
  mpvVideoOutputDriversForPlatform(platform),
  defaultMpvVideoOutputDriverForPlatform(platform),
);

String normalizeMpvAudioOutputDriverForPlatform(String value, TargetPlatform platform) =>
    _normalizeMpvOption(value, mpvAudioOutputDriversForPlatform(platform), 'auto');

String normalizeMpvHardwareDecoderForPlatform(String value, TargetPlatform platform) =>
    _normalizeMpvOption(value, mpvHardwareDecodersForPlatform(platform), 'auto');

String _normalizeMpvOption(String value, Map<String, String> available, String fallback) =>
    available.containsKey(value) ? value : fallback;
