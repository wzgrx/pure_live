import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/intake/clipboard_rooms.dart';
import 'package:pure_live/app/intake/share_intake.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/platform/share_channel.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_prompt.dart';

/// What comes into the app from the system, in the main window (M12.5 →
/// F.0a, docs/ui/compare/U.14): shares, "open with", launcher shortcuts and
/// notification taps (Android, [ShareIntake]); share codes on the
/// clipboard (every platform as 3.x, [ClipboardRoomWatcher]); the recent
/// rooms behind the launcher icon (U.14 c15) and the system splash
/// screen's light or dark (U.14 c9), both Android. Extra desktop windows
/// do none of it, so one clipboard text is not offered by every window.
abstract final class SystemIntake {
  static ClipboardRoomWatcher? _clipboard;
  static final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Starts it all over [services] (`main`, after the app runs).
  static void start(AppServices services, {ShareChannel? channel}) {
    if (!services.launch.isPrimary || _clipboard != null) return;
    final native = channel ?? ShareChannel();
    final store = services.store;
    _clipboard = ClipboardRoomWatcher(
      settings: store.settings,
      prompt: (room) async {
        final context = await appNavigatorReady();
        if (context == null || !context.mounted) return RoomPromptChoice.dismiss;
        return await showRoomPrompt(context, room: room);
      },
      open: (room) => AppNavigator.toLiveRoomDetail(liveRoom: room),
      stamp: native.clipboardStamp,
    )..start();
    if (!native.available) return;
    final shares = ShareIntake(
      links: LinkParser(services.sites, services.http),
      importer: services.iptvImporter,
      navigator: appNavigatorReady,
      openRoom: (room) => AppNavigator.toLiveRoomDetail(liveRoom: room),
      openRoute: (route) => AppNavigator.toNamed<void>(route),
      notify: (message) => AppNavigator.toast(message),
    );
    unawaited(native.listen((payload) => unawaited(shares.ingest(payload))));
    _subscriptions
      ..add(recentRoomShortcuts(store.history.watchAll()).listen((rooms) => unawaited(native.setRecentRooms(rooms))))
      ..add(store.settings.watch(Settings.themeMode).listen((mode) => unawaited(setSplashTheme(mode))));
  }

  /// Stops it (tests).
  @visibleForTesting
  static void stop() {
    _clipboard?.dispose();
    _clipboard = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}

/// The two newest rooms of [history] for the launcher's shortcuts (U.14
/// c15), sent again only when they change.
Stream<List<RecentRoomShortcut>> recentRoomShortcuts(Stream<List<LiveRoom>> history) => history
    .map(
      (rooms) => [
        for (final room in rooms.take(2))
          (platform: room.platform, roomId: room.roomId, title: room.title, nick: room.nick),
      ],
    )
    .distinct(listEquals);

const MethodChannel _appChannel = MethodChannel('pure_live/app');

/// Tells Android 13+ which splash screen the next cold start shows (U.14
/// c9): the app's own light or dark, or the system's for "跟随系统".
Future<void> setSplashTheme(String mode) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await _appChannel.invokeMethod<void>('setSplashTheme', {'mode': mode});
  } on PlatformException catch (error) {
    log('Splash theme failed: ${error.message}', name: 'SystemIntake');
  } on MissingPluginException {
    // A build without the native side.
  }
}

/// The navigator's context once a page other than the splash page shows,
/// or null after [timeout] (3.x `_waitForShareCommandNavigator`). A share
/// can start the app before its routes exist, and the splash page replaces
/// the whole stack when it leaves, taking anything opened above it along.
Future<BuildContext?> appNavigatorReady({Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final context = AppNavigator.navigatorContext;
    if (context != null && context.mounted && _pastSplash(context)) return context;
    if (DateTime.now().isAfter(deadline)) return null;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

bool _pastSplash(BuildContext context) {
  final location = GoRouter.maybeOf(context)?.routerDelegate.currentConfiguration;
  return location != null && location.isNotEmpty && location.uri.path != RoutePath.kSplash;
}
