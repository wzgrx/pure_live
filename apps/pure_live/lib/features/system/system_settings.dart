import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/features/system/close_behaviour.dart';

/// System tiles of 设置 › 通用 (principles §4.4): launch at login and the
/// close behaviour on Windows.
List<Widget> systemGeneralTiles({bool? windows}) => [
  if (windows ?? Platform.isWindows) ...const [
    SwitchSettingTile(setting: Settings.launchAtStartup, title: '开机自启', subtitle: '登录 Windows 后自动打开纯粹直播'),
    CloseBehaviourTile(),
  ],
];

/// System tiles of 设置 › 播放: the mini window everywhere, automatic
/// picture-in-picture on Android and the PiP window on top on Windows.
List<Widget> systemPlaybackTiles({bool? android, bool? windows}) => [
  const SwitchSettingTile(setting: Settings.miniPlayerOnLeave, title: '离开直播间时小窗播放', subtitle: '小窗会继续占用内存和流量'),
  if (android ?? Platform.isAndroid)
    const SwitchSettingTile(setting: Settings.autoPip, title: '离开应用时自动画中画', subtitle: '在直播间按主屏幕键时进入画中画'),
  if (windows ?? Platform.isWindows) const SwitchSettingTile(setting: Settings.pipAlwaysOnTop, title: '画中画窗口置顶'),
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
  const new(this.section, {super.key});

  /// The section.
  final SystemSettingsSection section;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: switch (section) {
      SystemSettingsSection.general => systemGeneralTiles(),
      SystemSettingsSection.playback => systemPlaybackTiles(),
    },
  );
}
