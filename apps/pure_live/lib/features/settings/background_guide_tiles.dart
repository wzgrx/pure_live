import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/background_guide.dart';
import 'package:pure_live/platform/system_permissions.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/permission_prompts.dart';

// "后台播放设置" (docs/O-Android系统集成/O01-通知和前台服务/O01.3-后台播放增强): the row on the
// video page, the phone's checks on its page, and the one-time hint after
// background play turns on. The look is the settings page's own rows
// (D-003: no new component).

/// The native side of the guide (tests replace it).
final Provider<BackgroundGuideChannel> backgroundGuideChannelProvider = Provider(
  (ref) => const BackgroundGuideChannel(),
);

/// The system permissions the guide's notification and battery steps ask
/// for (tests replace it).
final Provider<SystemPermissions> backgroundGuidePermissionsProvider = Provider((ref) => const SystemPermissions());

/// What the phone says now; read again when the app comes back from the
/// system settings ([BackgroundGuideRefresh]).
final FutureProvider<BackgroundStatus?> backgroundStatusProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(backgroundGuideChannelProvider).status(),
);

/// Where the one-time hint is remembered (`LiveStore.meta`).
const String backgroundGuideOfferedKey = 'backgroundGuide.offered';

/// Reads the phone again whenever the app comes back to the front (after a
/// system page).
mixin BackgroundGuideRefresh<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(backgroundStatusProvider));
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }
}

/// "后台播放设置" on the video page: opens its page; "N 项待处理" when
/// something Android lets the app read is in the way.
class BackgroundGuideLinkTile extends ConsumerStatefulWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  ConsumerState<BackgroundGuideLinkTile> createState() => _BackgroundGuideLinkTileState();
}

class _BackgroundGuideLinkTileState extends ConsumerState<BackgroundGuideLinkTile> with BackgroundGuideRefresh {
  @override
  Widget build(BuildContext context) {
    final status = ref.watch(backgroundStatusProvider).value;
    final pending = status == null ? 0 : pendingSteps(guideSteps(status));
    return SettingLinkTile(
      entry: widget.entry,
      icon: AppIcons.settingsBackgroundGuide,
      subpage: SettingsSubpage.backgroundPlay,
      value: pending == 0 ? null : i18n('background_guide_pending', args: {'count': '$pending'}),
    );
  }
}

/// The icon of [step] (one meaning per icon, A01.4).
IconData backgroundStepIcon(GuideStep step) => switch (step.id) {
  'notifications' => AppIcons.backgroundGuideNotifications,
  'battery' => AppIcons.backgroundGuideBattery,
  'restricted' => AppIcons.backgroundGuideRestricted,
  'data_saver' => AppIcons.backgroundGuideDataSaver,
  'lock_recents' => AppIcons.backgroundGuideLockRecents,
  'xiaomi_autostart' ||
  'oppo_autostart' ||
  'vivo_autostart' ||
  'huawei_launch' ||
  'honor_launch' => AppIcons.backgroundGuideAutostart,
  _ => AppIcons.backgroundGuidePowerSaving,
};

/// The phone's checks: the phone, then a row per step with where it
/// stands; a tap opens the system page (the app's details where the
/// vendor's page is missing) or asks for the permission.
class BackgroundGuideTile extends ConsumerStatefulWidget {
  /// Creates the rows.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  ConsumerState<BackgroundGuideTile> createState() => _BackgroundGuideTileState();
}

class _BackgroundGuideTileState extends ConsumerState<BackgroundGuideTile> with BackgroundGuideRefresh {
  String? _opening;

  Future<void> _run(GuideStep step) async {
    if (_opening != null) return;
    setState(() => _opening = step.id);
    try {
      await _act(step);
    } finally {
      if (mounted) {
        setState(() => _opening = null);
        ref.invalidate(backgroundStatusProvider);
      }
    }
  }

  Future<void> _act(GuideStep step) async {
    final permissions = ref.read(backgroundGuidePermissionsProvider);
    switch (step.action) {
      case GuideAction.notifications:
        // The system dialog while it can still ask, else the settings page.
        if (await permissions.notifications() == NotificationPermission.askable) {
          await permissions.requestNotifications();
          return;
        }
        if (await permissions.openNotificationSettings()) return;
        await _open(step);
      case GuideAction.battery:
        // The system's "允许后台运行" dialog; vendors that removed it get the
        // list of apps, then the app's details.
        // Already exempt: the list, to look or to change it back.
        if (step.check == GuideCheck.todo) {
          if (await permissions.requestBatteryUnrestricted()) return;
          if (await permissions.batteryUnrestricted()) return;
        }
        await _open(step);
      case GuideAction.pages:
        await _open(step);
      case GuideAction.none:
        break;
    }
  }

  Future<void> _open(GuideStep step) async {
    final opened = await ref.read(backgroundGuideChannelProvider).open(step.pages);
    if (opened < 0) {
      AppNavigator.toast(i18n('background_guide_open_failed'));
    } else if (step.pages[opened].isAppDetails && step.pages.length > 1) {
      // The vendor's own page is missing on this build.
      AppNavigator.toast(i18n('background_guide_opened_details', args: {'name': i18n(step.titleKey)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(backgroundStatusProvider);
    // A read again after a system page keeps showing the last one.
    final value = status.value;
    return Column(
      key: widget.entry.rowKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: value != null
          ? _rows(context, value)
          : [
              SettingsRow(
                icon: AppIcons.backgroundGuideDevice,
                title: widget.entry.titleText,
                subtitle: status.isLoading ? null : i18n('background_guide_unavailable'),
                busy: status.isLoading,
              ),
            ],
    );
  }

  List<Widget> _rows(BuildContext context, BackgroundStatus status) {
    final rom = status.rom;
    final steps = guideSteps(status);
    final colors = Theme.of(context).colorScheme;
    final device = [rom.manufacturer, rom.model].where((part) => part.isNotEmpty).join(' ');
    final system = [
      if (rom.romName.isNotEmpty) rom.romLabel,
      if (rom.androidVersion.isNotEmpty) 'Android ${rom.androidVersion}',
    ].join(' · ');
    Widget state(GuideCheck check) {
      final (key, color) = switch (check) {
        GuideCheck.ok => ('background_guide_state_ok', colors.primary),
        GuideCheck.todo => ('background_guide_state_todo', colors.error),
        GuideCheck.manual => ('background_guide_state_manual', colors.onSurfaceVariant),
      };
      return Text(i18n(key), style: context.textStyles.t13.copyWith(color: color));
    }

    final firstManual = steps.indexWhere((step) => step.check == GuideCheck.manual);
    return [
      SettingsRow(
        key: const ValueKey('background-guide-device'),
        icon: AppIcons.backgroundGuideDevice,
        title: device.isEmpty ? widget.entry.titleText : device,
        subtitle: system.isEmpty ? null : system,
      ),
      if (status.powerSave) SettingsNote(i18n('background_guide_power_save')),
      for (final (index, step) in steps.indexed) ...[
        if (index == firstManual) SettingsNote(i18n('background_guide_manual_note', args: {'rom': rom.romLabel})),
        SettingsRow(
          key: ValueKey('background-guide-${step.id}'),
          icon: backgroundStepIcon(step),
          title: i18n(step.titleKey),
          subtitle: i18n(step.check == GuideCheck.todo ? step.problemKey ?? step.howKey : step.howKey),
          subtitleMaxLines: null,
          subtitleColor: step.check == GuideCheck.todo ? colors.error : null,
          trailing: step.action == GuideAction.none ? null : state(step.check),
          busy: _opening == step.id,
          onTap: step.action == GuideAction.none ? null : () => unawaited(_run(step)),
        ),
      ],
    ];
  }
}

/// After background play turned on (O01.3): on a vendor build that clears
/// apps away, once, says that the system needs a few more switches and
/// offers the page that has them.
Future<void> offerBackgroundGuide(BuildContext context, WidgetRef ref) async {
  final channel = ref.read(backgroundGuideChannelProvider);
  if (!channel.applies) return;
  final meta = ref.read(storeProvider).meta;
  if (await meta.get(backgroundGuideOfferedKey) != null) return;
  final status = await channel.status();
  if (status == null || !hasVendorSteps(status.rom.family) || !context.mounted) return;
  await meta.set(backgroundGuideOfferedKey, '1');
  if (!context.mounted) return;
  final go = await showPermissionDialog(
    context,
    title: i18n('background_guide_offer_title'),
    message: i18n('background_guide_offer_content', args: {'rom': status.rom.romLabel}),
    confirm: i18n('permission_open_settings'),
    cancel: i18n('permission_later'),
  );
  if (go && context.mounted) await openSettingsSubpage(context, SettingsSubpage.backgroundPlay);
}
