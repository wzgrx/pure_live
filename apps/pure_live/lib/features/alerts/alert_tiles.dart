import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/alert_notifier.dart';
import 'package:pure_live_app/features/alerts/live_alerts.dart';
import 'package:pure_live_app/features/alerts/programme_reminders.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

/// Text shown when the system refuses notifications.
const notificationsDeniedText = '没有通知权限，开播提醒保持关闭。可以在系统设置里允许本应用的通知后再打开';

/// The global live alert switch (F-NEW-01). Turning it on asks for the
/// notification permission first (Android 13+); when refused the switch stays
/// off and says why.
class LiveAlertsTile extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<LiveAlertsTile> createState() => _LiveAlertsTileState();
}

class _LiveAlertsTileState extends ConsumerState<LiveAlertsTile> {
  bool _asking = false;

  Future<void> _turnOn(ValueChanged<bool> set) async {
    final notifier = ref.read(alertNotifierProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _asking = true);
    var granted = false;
    try {
      granted = await notifier.requestPermission();
    } on Object {
      granted = false;
    }
    if (mounted) setState(() => _asking = false);
    set(granted);
    if (!granted) messenger?.showSnackBar(const SnackBar(content: Text(notificationsDeniedText)));
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(alertNotifierProvider).supported;
    return SettingBuilder<bool>(
      setting: Settings.liveAlerts,
      builder: (context, value, set) => SwitchListTile(
        title: const Text('开播提醒'),
        subtitle: Text(supported ? '关注的主播开播时发通知，应用在后台运行时按刷新间隔检查；可在关注页对单个主播关闭' : '这个系统上不支持通知'),
        value: supported && value,
        onChanged: !supported || _asking
            ? null
            : (on) {
                if (on) {
                  unawaited(_turnOn(set));
                } else {
                  set(false);
                }
              },
      ),
    );
  }
}

/// A followed room's own live alert switch in its menu (principles §4.1:
/// 逐个设置开播提醒). It only turns a room off; with the global switch off it
/// is disabled and says where to turn alerts on.
class RoomAlertSwitch extends ConsumerWidget {
  const new({required this.room, super.key});

  /// The followed room.
  final RoomRef room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Channels are always on air; their programmes have reminders instead.
    if (room.platform == IptvSite.platformId) return const SizedBox.shrink();
    final global = ref.watch(liveAlertsSetting);
    final off = ref.watch(liveAlertsOffProvider).value?.contains(room) ?? false;
    return SwitchListTile(
      secondary: Icon(global && !off ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
      title: const Text('开播提醒'),
      subtitle: Text(
        !global
            ? '先在 设置 › 通用 打开开播提醒'
            : off
            ? '这个主播开播时不提醒'
            : '开播时发通知',
      ),
      value: global && !off,
      onChanged: global ? (on) => unawaited(ref.read(storeProvider).roomPrefs.setLiveAlert(room, enabled: on)) : null,
    );
  }
}

/// "提醒我" on an upcoming programme in the guide (F-IPTV-09). Hidden where
/// the system has no notifications.
class ProgrammeReminderButton extends ConsumerWidget {
  const new({required this.room, required this.programme, super.key});

  /// The channel.
  final RoomRef room;

  /// The upcoming programme.
  final IptvProgramme programme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(alertNotifierProvider).supported) return const SizedBox.shrink();
    final reminder = ProgrammeReminder.of(room, programme);
    final on = ref.watch(programmeRemindersProvider).any((item) => item.key == reminder.key);
    return TextButton.icon(
      icon: Icon(on ? Icons.notifications_active : Icons.notifications_none, size: 18),
      label: Text(on ? '已提醒' : '提醒我'),
      onPressed: () => unawaited(toggleProgrammeReminder(context, ref, reminder)),
    );
  }
}

/// Sets or removes [reminder]; setting one asks for the notification
/// permission first and explains a refusal in a dialog (the guide is a sheet,
/// where a snack bar would sit underneath).
Future<void> toggleProgrammeReminder(BuildContext context, WidgetRef ref, ProgrammeReminder reminder) async {
  final reminders = ref.read(programmeRemindersProvider.notifier);
  if (!reminders.contains(reminder)) {
    var granted = false;
    try {
      granted = await ref.read(alertNotifierProvider).requestPermission();
    } on Object {
      granted = false;
    }
    if (!granted) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('无法提醒'),
            content: const Text('没有通知权限。可以在系统设置里允许本应用的通知后再设置节目提醒。'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
          ),
        );
      }
      return;
    }
  }
  await reminders.toggle(reminder);
}
