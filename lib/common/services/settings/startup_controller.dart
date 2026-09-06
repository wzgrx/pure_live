import 'dart:developer' as dev;

import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/site/huya/huya_site.dart';
import 'package:pure_live/common/global/win_auto_start.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';

class StartupController extends GetxController {
  final RxBool enableStartUp = hiveBool('enableStartUp', true);

  @override
  void onInit() {
    super.onInit();
    ever<bool>(enableStartUp, (_) => setupLaunchAtStartup());
    loadHuyaUa();
  }

  Future<void> loadHuyaUa() async {
    HuyaSite().getHuYaUA();
  }

  Future<void> setupLaunchAtStartup() async {
    try {
      final isEnabled = WindowsAutoStart.isEnabled();

      if (enableStartUp.v && !isEnabled) {
        final result = WindowsAutoStart.enable();
        dev.log("Enable startup result: $result");
      } else if (!enableStartUp.v && isEnabled) {
        final result = WindowsAutoStart.disable();
        dev.log("Disable startup result: $result");
      }
    } catch (e) {
      dev.log("Auto-start error: $e");
    }
  }

  void enableStartup() {
    enableStartUp.v = true;
  }

  void disableStartup() {
    enableStartUp.v = false;
  }

  void toggleStartup() {
    enableStartUp.v = !enableStartUp.v;
  }

  Map<String, dynamic> toJson() {
    return {'enableStartUp': enableStartUp.v};
  }

  /// Parse the complete section without notifying observers or persisting values.
  static Map<String, dynamic> parseConfig(Map<String, dynamic> json) {
    return {'enableStartUp': (json['enableStartUp'] ?? true) as bool};
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    enableStartUp.v = parsed['enableStartUp'];
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final startup = rootConfig?['startup'] as Map<String, dynamic>? ?? {};
    return {'enableStartUp': startup['enableStartUp'] ?? true};
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final startup = Map<String, dynamic>.from(rootConfig['startup'] ?? {});
    updateFields.forEach((k, v) => startup[k] = v);
    rootConfig['startup'] = startup;
    return rootConfig;
  }
}
