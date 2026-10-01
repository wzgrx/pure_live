import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/in_app_web.dart';
import 'package:url_launcher/url_launcher.dart';

/// How a short message is shown (3.x `ToastUtil.show`); the app sets it to
/// a snack bar on the root messenger.
typedef ToastPresenter = void Function(String message);

/// Navigation without a [BuildContext] (3.x `AppNavigator` plus the
/// `Get.toNamed` / `Get.offAllNamed` / `Get.back` calls of the pages), so
/// pages port call by call:
///
/// | 3.x | here |
/// |---|---|
/// | `Get.toNamed(path, arguments: x)` | `AppNavigator.toNamed(path, arguments: x)` |
/// | `Get.offAllNamed(path)` | `AppNavigator.offAllNamed(path)` |
/// | `Get.back()` | `AppNavigator.back()` |
/// | `Get.arguments` | `GoRouterState.of(context).extra` (the page builder passes it) |
abstract final class AppNavigator {
  static GoRouter? _router;
  static bool _openingLiveRoom = false;
  static bool _openingOfficialCategory = false;

  /// Shows a short message; set by the app.
  static ToastPresenter toast = (message) => log(message, name: 'Toast');

  /// Opens a web address outside the app; replaceable in tests.
  static Future<bool> Function(Uri uri) openExternal = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Opens a local file with the app the system picks; the app sets it
  /// (open_filex on Android, M12.3); replaceable in tests.
  static Future<bool> Function(String path) openFile = (path) => openExternal(Uri.file(path));

  /// The context of the root navigator (dialogs from outside a page, such
  /// as the window's close question); null before the app is up.
  static BuildContext? get navigatorContext => _router?.routerDelegate.navigatorKey.currentContext;

  /// The router in use.
  static GoRouter get router => _router ?? (throw StateError('No router attached'));

  /// Attaches [router] (the app does this once it builds it).
  static set router(GoRouter? router) => _router = router;

  /// Opens [path] on top (3.x `Get.toNamed`).
  static Future<T?> toNamed<T extends Object?>(String path, {Object? arguments}) =>
      router.push<T>(path, extra: arguments);

  /// Replaces every page with [path] (3.x `Get.offAllNamed`).
  static void offAllNamed(String path, {Object? arguments}) => router.go(path, extra: arguments);

  /// Replaces the top page with [path] (3.x `Get.offAndToNamed`).
  static Future<T?> offAndToNamed<T extends Object?>(String path, {Object? arguments}) =>
      router.pushReplacement<T>(path, extra: arguments);

  /// Closes the top page (3.x `Get.back`).
  static void back<T extends Object?>([T? result]) {
    if (router.canPop()) router.pop<T>(result);
  }

  /// Opens the rooms of [category] on [site] (3.x `toCategoryDetail`). CC's
  /// official entries are web pages and open in the browser.
  static Future<void> toCategoryDetail({required LiveSite site, required LiveArea category}) async {
    if (CcApi.isOfficialEntry(category)) {
      if (_openingOfficialCategory) return;
      final uri = site.id == SiteIds.cc ? CcApi.officialEntryUri(category) : null;
      if (uri == null) {
        toast(i18n('external_browser_not_opened'));
        return;
      }
      _openingOfficialCategory = true;
      try {
        if (!await openExternal(uri)) toast(i18n('external_browser_not_opened'));
      } on Object {
        toast(i18n('external_browser_not_opened'));
      } finally {
        _openingOfficialCategory = false;
      }
      return;
    }
    unawaited(toNamed<void>(RoutePath.kAreaRooms, arguments: [site, category]));
  }

  /// The room with a usable platform and id, or null after telling the user
  /// why not (retired platform, missing id).
  static LiveRoom? _openable(LiveRoom room) {
    final platform = room.platform.trim().toLowerCase();
    if (platform.isEmpty || room.roomId.isEmpty || !SiteIds.isSupported(platform)) {
      toast(i18n(SiteIds.isRetired(platform) ? 'platform_retired' : 'get_room_info_failed_retry'));
      return null;
    }
    return room;
  }

  /// Opens the live room (3.x `toLiveRoomDetail`); a second call while one
  /// is opening is ignored. The player's floating window hand-off belongs
  /// to the player (M7.2/M13).
  static Future<void> toLiveRoomDetail({required LiveRoom liveRoom}) async {
    if (_openingLiveRoom) return;
    final room = _openable(liveRoom);
    if (room == null) return;
    _openingLiveRoom = true;
    try {
      // 3.x awaited `Get.toNamed`, which completes when the room closes, so
      // it ignored every other room while one was open. Here a second tap
      // is ignored only while the room's page is coming in.
      unawaited(toNamed<void>(RoutePath.kLivePlay, arguments: room));
    } on Object catch (error, stack) {
      log('Open live room failed', name: 'AppNavigator', error: error, stackTrace: stack);
      toast(i18n('get_room_info_failed_retry'));
    } finally {
      unawaited(Future<void>.delayed(openGuard, () => _openingLiveRoom = false));
    }
  }

  /// How long a second request to open a room is ignored.
  static const Duration openGuard = Duration(milliseconds: 500);

  /// Replaces the current live room with [liveRoom] (3.x
  /// `offAndToRoomDetail`).
  static Future<void> offAndToRoomDetail({required LiveRoom liveRoom}) async {
    final room = _openable(liveRoom);
    if (room == null) return;
    unawaited(offAndToNamed<void>(RoutePath.kLivePlay, arguments: room));
  }

  /// Opens multi-view (3.x `toMultiview`).
  static Future<void> toMultiview() async => unawaited(toNamed<void>(RoutePath.kMultiview));

  /// Opens the Bilibili login (3.x `toBiliBiliLogin`): phones with the
  /// in-app browser choose between the web page (SMS or password) and the
  /// QR code; desktops, and phones without it, go to the QR code.
  static Future<void> toBiliBiliLogin(BuildContext context, {required bool mobile}) async {
    if (!mobile || !InAppWeb.available) {
      await toNamed<void>(RoutePath.kBiliBiliQRLogin);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(i18n('select_login_method')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RoutePath.kBiliBiliWebLogin),
            child: Text(i18n('sms_login')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RoutePath.kBiliBiliQRLogin),
            child: Text(i18n('qrcode_login')),
          ),
        ],
      ),
    );
    if (choice != null) await toNamed<void>(choice);
  }
}
