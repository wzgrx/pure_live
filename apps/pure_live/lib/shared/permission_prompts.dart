import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/system_permissions.dart';
import 'package:pure_live/routes/app_navigator.dart';

// The explanations before a system permission (docs/A-界面设计/A14-系统界面/A14.1-系统界面 c12–c14;
// 3.x `LiveAudioService._showExplainDialog`, M12.5 → F.0a).

/// What asking for a permission came to.
enum PermissionAnswer {
  /// Allowed (or nothing to ask).
  granted,

  /// The system said no, or it is still off after the settings page.
  denied,

  /// The user cancelled the explanation (3.x: the switch stays off).
  cancelled,
}

/// The explanation before a system permission, as the app's other dialogs
/// (U.14 c12, U.1d: title on the left, "取消" and the main button at the
/// bottom right; 3.x drew its own centred card). True for the main button.
Future<bool> showPermissionDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  String? cancel,
}) => showAppConfirmDialog(
  context: context,
  key: const ValueKey('permission-dialog'),
  title: title,
  message: message,
  confirmLabel: confirm,
  cancelLabel: cancel ?? i18n('permission_cancel'),
  cancelKey: const ValueKey('permission-cancel'),
  confirmKey: const ValueKey('permission-confirm'),
);

/// Completes the next time the app comes back to the front (after the
/// system settings page).
Future<void> nextResume() {
  final done = Completer<void>();
  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    onResume: () {
      listener.dispose();
      if (!done.isCompleted) done.complete();
    },
  );
  return done.future;
}

/// What "后台播放" and "新直播间自动助眠" ask for before they turn on (3.x
/// `LiveAudioService.requestPlatformPermissions`, U.14 c12, c13):
///
/// 1. Notifications (the playback controls in the notification bar):
///    3.x's explanation, then the system dialog; cancelling or refusing
///    keeps the switch off (3.x). Refused for good (or switched off in the
///    system settings), the explanation becomes "通知权限已关闭" with
///    "去设置"; back in the app it looks again and lets the switch on when
///    notifications are allowed now.
/// 2. Battery optimisation: 3.x's explanation, then the system dialog;
///    never keeps the switch off (3.x).
final class BackgroundPermissions {
  /// Creates the questions over [permissions].
  new({required this.permissions, BuildContext? Function()? navigator, Future<void> Function()? resumed})
    : _navigator = navigator ?? (() => AppNavigator.navigatorContext),
      _resumed = resumed ?? nextResume;

  /// The system permissions.
  final SystemPermissions permissions;

  final BuildContext? Function() _navigator;
  final Future<void> Function() _resumed;

  /// Asks what is missing; whether the switch may turn on.
  Future<PermissionAnswer> confirm() async {
    if (!permissions.applies) return PermissionAnswer.granted;
    final notifications = await _notifications();
    if (notifications != PermissionAnswer.granted) return notifications;
    if (!await permissions.batteryUnrestricted()) {
      final context = _navigator();
      if (context != null &&
          context.mounted &&
          await showPermissionDialog(
            context,
            title: i18n('permission_battery_title'),
            message: i18n('permission_battery_content'),
            confirm: i18n('permission_go_enable'),
          )) {
        await permissions.requestBatteryUnrestricted();
      }
    }
    return PermissionAnswer.granted;
  }

  /// Only the notification step of [confirm], explained with [content]
  /// (askable) or [blockedContent] (refused for good): "开播提醒" needs
  /// nothing else (O01.1; the battery exemption does not keep a frozen
  /// app checking, V01.1 L8).
  Future<PermissionAnswer> confirmNotifications({required String content, required String blockedContent}) async {
    if (!permissions.applies) return PermissionAnswer.granted;
    return await _notifications(content: content, blockedContent: blockedContent);
  }

  Future<PermissionAnswer> _notifications({String? content, String? blockedContent}) async {
    final state = await permissions.notifications();
    if (state == NotificationPermission.granted) return PermissionAnswer.granted;
    final context = _navigator();
    if (context == null || !context.mounted) return PermissionAnswer.denied;
    if (state == NotificationPermission.askable) {
      final go = await showPermissionDialog(
        context,
        title: i18n('permission_notification_title'),
        message: content ?? i18n('permission_notification_content'),
        confirm: i18n('permission_go_enable'),
      );
      if (!go) return PermissionAnswer.cancelled;
      return await permissions.requestNotifications() ? PermissionAnswer.granted : PermissionAnswer.denied;
    }
    final go = await showPermissionDialog(
      context,
      title: i18n('permission_notification_blocked_title'),
      message: blockedContent ?? i18n('permission_notification_blocked_content'),
      confirm: i18n('permission_open_settings'),
    );
    if (!go) return PermissionAnswer.cancelled;
    if (!await permissions.openNotificationSettings()) return PermissionAnswer.denied;
    await _resumed();
    return await permissions.notifications() == NotificationPermission.granted
        ? PermissionAnswer.granted
        : PermissionAnswer.denied;
  }
}

/// The questions of [BackgroundPermissions] where the platform asks (Android),
/// else null (the switches turn on at once).
final Provider<BackgroundPermissions?> backgroundPermissionsProvider = Provider((ref) {
  const permissions = SystemPermissions();
  return permissions.applies ? BackgroundPermissions(permissions: permissions) : null;
});

/// The explanations around recording (U.14 c14; 3.x asked for neither):
/// notifications once, the first time a recording starts while they are
/// off (recording runs without them, only its notification is missing);
/// all-files access before the system page opens.
final class RecordingPermissionPrompts {
  /// Creates the prompts over [permissions]; [meta] remembers that the
  /// notification question was asked.
  new({required this.permissions, required this.meta, BuildContext? Function()? navigator, bool Function()? inFront})
    : _navigator = navigator ?? (() => AppNavigator.navigatorContext),
      _inFront = inFront ?? (() => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  /// Where [askedKey] is kept.
  static const String askedKey = 'permission.recordingNotifications';

  /// The system permissions.
  final SystemPermissions permissions;

  /// The meta store.
  final MetaStore meta;

  final BuildContext? Function() _navigator;
  final bool Function() _inFront;
  bool _asking = false;

  /// The first recording started: explains the notification permission
  /// once while the app is in front; never holds the recording up.
  Future<void> notificationsOnce() async {
    if (!permissions.applies || _asking || !_inFront()) return;
    _asking = true;
    try {
      if (await meta.get(askedKey) != null) return;
      final state = await permissions.notifications();
      if (state == NotificationPermission.granted) return;
      final context = _navigator();
      if (context == null || !context.mounted) return;
      await meta.set(askedKey, '1');
      if (!context.mounted) return;
      final askable = state == NotificationPermission.askable;
      final go = await showPermissionDialog(
        context,
        title: i18n(askable ? 'permission_notification_title' : 'permission_notification_blocked_title'),
        message: i18n('permission_record_notification_content'),
        confirm: i18n(askable ? 'permission_go_enable' : 'permission_open_settings'),
        cancel: i18n('permission_later'),
      );
      if (!go) return;
      if (askable) {
        await permissions.requestNotifications();
      } else {
        await permissions.openNotificationSettings();
      }
    } on Object catch (error, stack) {
      log(
        'Recording notification question failed',
        name: 'RecordingPermissionPrompts',
        error: error,
        stackTrace: stack,
      );
    } finally {
      _asking = false;
    }
  }

  /// Says why the system page for all-files access opens next; false when
  /// the user cancelled (no page opens).
  Future<bool> explainStorage() async {
    final context = _navigator();
    if (context == null || !context.mounted) return true;
    return await showPermissionDialog(
      context,
      title: i18n('permission_storage_title'),
      message: i18n('permission_storage_content'),
      confirm: i18n('permission_go_enable'),
    );
  }
}
