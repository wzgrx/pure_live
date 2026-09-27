import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/deep_link.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/features/share/clipboard_watch.dart';
import 'package:pure_live_app/features/share/share_text.dart';

const _methods = MethodChannel('purelive/share');
const _events = EventChannel('purelive/share/events');

/// Opens text shared into the app (Android "分享到纯粹直播", F-SHR-02) and
/// `purelive://` links opened with it (F-APP-05): a `purelive://room/…` link
/// opens the room and a LAN sync QR link the send page; a playlist goes to the
/// IPTV import, a share code (3.x-compatible, store.md §8) or a recognised
/// room link opens the room, anything else goes to search.
/// Waits for the first frame so a cold start does not push before the router
/// exists (3.2.2 lesson).
final shareIntakeProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;

  Future<void> open(String text) async {
    await WidgetsBinding.instance.endOfFrame;
    final router = ref.read(routerProvider);
    switch (DeepLink.parse(text)) {
      case RoomDeepLink(:final room):
        if (ref.read(sitesProvider).containsKey(room.platform)) {
          unawaited(router.push(roomLocation(room)));
        } else {
          router.go(searchLocation(room.roomId));
        }
        return;
      case SyncDeepLink(:final address):
        unawaited(router.push(syncLocation(address)));
        return;
      case null:
    }
    // The same text is often still in the clipboard; do not offer it again.
    ref.read(clipboardWatcherProvider).remember(text);
    // A playlist URL or playlist text goes to the IPTV import (iptv.md §6).
    if (iptvShareRequest(text) case final request?) {
      unawaited(router.push(iptvLocation, extra: request));
      return;
    }
    final code = ShareTextRecognizer.findShareCode(text);
    if (code != null) {
      if (ref.read(sitesProvider).containsKey(code.ref.platform)) {
        unawaited(router.push(roomLocation(code.ref)));
      } else {
        // A platform this build has no adapter for: look the streamer up.
        router.go(searchLocation(code.anchorName.isNotEmpty ? code.anchorName : code.title));
      }
      return;
    }
    final room = await ref.read(linkResolverProvider)(text).catchError((Object _) => null);
    if (room != null) {
      unawaited(router.push(roomLocation(room)));
    } else {
      router.go(searchLocation(text));
    }
  }

  unawaited(
    _methods.invokeMethod<String>('takePendingText').then((text) {
      if (text != null) unawaited(open(text));
    }, onError: (Object _) {}),
  );
  final subscription = _events.receiveBroadcastStream().cast<String>().listen(open, onError: (Object _) {});
  ref.onDispose(subscription.cancel);
});
