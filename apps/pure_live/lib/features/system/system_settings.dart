import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/features/system/close_behaviour.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// System tiles of 设置 › 通用 (principles §4.4): launch at login and the
/// close behaviour on Windows.
List<Widget> systemGeneralTiles({bool? windows}) => [
  if (windows ?? Platform.isWindows) ...[
    SwitchSettingTile(
      setting: Settings.launchAtStartup,
      title: t.system.launchAtStartup,
      subtitle: t.system.launchAtStartupSubtitle,
    ),
    const CloseBehaviourTile(),
  ],
];

/// System tiles of 设置 › 播放: the mini window everywhere, automatic
/// picture-in-picture on Android and the PiP window on top on Windows.
List<Widget> systemPlaybackTiles({bool? android, bool? windows}) => [
  SwitchSettingTile(
    setting: Settings.miniPlayerOnLeave,
    title: t.system.miniOnLeave,
    subtitle: t.system.miniOnLeaveSubtitle,
  ),
  if (android ?? Platform.isAndroid)
    SwitchSettingTile(setting: Settings.autoPip, title: t.system.autoPip, subtitle: t.system.autoPipSubtitle),
  if (windows ?? Platform.isWindows) SwitchSettingTile(setting: Settings.pipAlwaysOnTop, title: t.system.pipOnTop),
];

/// Which system tiles a [SystemSettingTiles] shows.
enum SystemSettingsSection {
  /// 设置 › 通用.
  general,

  /// 设置 › 播放.
  playback,
}

/// The system tiles of one section as a single widget, so a settings page can
/// list it among its const tiles.
class SystemSettingTiles extends StatelessWidget {
  /// Shows the tiles of [section].
  const new(this.section, {this.android, this.windows, super.key});

  /// The section.
  final SystemSettingsSection section;

  /// Describes Android (true) or not (false) instead of this device; tests.
  final bool? android;

  /// Describes Windows (true) or not (false) instead of this device; tests.
  final bool? windows;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: switch (section) {
      SystemSettingsSection.general => systemGeneralTiles(windows: windows),
      SystemSettingsSection.playback => systemPlaybackTiles(android: android, windows: windows),
    },
  );
}
