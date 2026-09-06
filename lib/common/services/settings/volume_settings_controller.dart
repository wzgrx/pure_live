import 'dart:io';
import 'dart:convert';

import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';

class VolumeSettingsController extends GetxController {
  final RxDouble defaultMobileVolume = hiveDouble('defaultMobileVolume', 0.5);
  final RxDouble defaultDesktopVolume = hiveDouble('defaultDesktopVolume', 1.0);
  final RxBool globalVolumeMute = hiveBool('globalVolumeMute', false);
  final RxString _roomVolumesRaw = hiveString('roomVolumes', '{}');
  final RxMap<String, double> rxRoomVolumes = <String, double>{}.obs;
  Map<String, double> get roomVolumes => rxRoomVolumes;

  set roomVolumes(Map<String, double> value) {
    rxRoomVolumes.assignAll(value);
    _roomVolumesRaw.v = jsonEncode(rxRoomVolumes);
  }

  @override
  void onInit() {
    super.onInit();
    try {
      final map = jsonDecode(_roomVolumesRaw.v) as Map<String, dynamic>;
      rxRoomVolumes.assignAll(map.map((k, v) => MapEntry(k, (v as num).toDouble())));
    } catch (_) {
      rxRoomVolumes.clear();
    }
  }

  void setRoomVolume(String roomId, double volume) {
    rxRoomVolumes[roomId] = volume.clamp(0.0, 1.0);
    _roomVolumesRaw.v = jsonEncode(rxRoomVolumes);
  }

  double get currentPlatformDefaultVolume {
    return Platform.isAndroid || Platform.isIOS ? defaultMobileVolume.v : defaultDesktopVolume.v;
  }

  void setCurrentPlatformDefaultVolume(double volume) {
    final v = volume.clamp(0.0, 1.0);
    if (Platform.isAndroid || Platform.isIOS) {
      defaultMobileVolume.v = v;
    } else {
      defaultDesktopVolume.v = v;
    }
  }

  void resetVolumeToDefault() {
    defaultMobileVolume.v = 0.5;
    defaultDesktopVolume.v = 1.0;
    globalVolumeMute.v = false;
    rxRoomVolumes.clear();
    _roomVolumesRaw.v = '{}';
  }

  Map<String, dynamic> toJson() {
    return {
      'defaultMobileVolume': defaultMobileVolume.v,
      'defaultDesktopVolume': defaultDesktopVolume.v,
      'globalVolumeMute': globalVolumeMute.v,
      'roomVolumes': rxRoomVolumes,
    };
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    defaultMobileVolume.v = parsed.mobile;
    defaultDesktopVolume.v = parsed.desktop;
    globalVolumeMute.v = parsed.mute;
    rxRoomVolumes.assignAll(parsed.volumes);
    _roomVolumesRaw.v = jsonEncode(parsed.volumes);
  }

  static ({double mobile, double desktop, bool mute, Map<String, double> volumes}) parseConfig(
    Map<String, dynamic> json,
  ) {
    final mobile = (json['defaultMobileVolume'] as num?)?.toDouble() ?? 0.5;
    final desktop = (json['defaultDesktopVolume'] as num?)?.toDouble() ?? 1.0;
    final mute = json['globalVolumeMute'] as bool? ?? false;
    final volumes = parseRoomVolumes(json['roomVolumes']);
    if (!mobile.isFinite || !desktop.isFinite) throw const FormatException('Invalid default volume');
    return (mobile: mobile, desktop: desktop, mute: mute, volumes: volumes);
  }

  /// Parse before changing Rx values: malformed imports must not erase volumes.
  static Map<String, double> parseRoomVolumes(dynamic data) {
    if (data == null) return {};
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! Map) throw const FormatException('Invalid roomVolumes');
    final result = <String, double>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (entry.key is! String || value is! num || !value.isFinite) {
        throw const FormatException('Invalid roomVolumes entry');
      }
      result[entry.key as String] = value.toDouble();
    }
    return result;
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final volume = rootConfig?['volume'] as Map<String, dynamic>? ?? {};
    return {
      'defaultMobileVolume': (volume['defaultMobileVolume'] ?? 0.5).toDouble(),
      'defaultDesktopVolume': (volume['defaultDesktopVolume'] ?? 1.0).toDouble(),
      'globalVolumeMute': volume['globalVolumeMute'] ?? false,
      'roomVolumes': volume['roomVolumes'] ?? {},
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final volume = Map<String, dynamic>.from(rootConfig['volume'] ?? {});
    updateFields.forEach((k, v) => volume[k] = v);
    rootConfig['volume'] = volume;
    return rootConfig;
  }
}
