import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/sites.dart';

const _methods = MethodChannel('purelive/share');
const _events = EventChannel('purelive/share/events');

/// Opens text shared into the app (Android "分享到纯粹直播"): a recognised room
/// link opens the room, anything else goes to search. Waits for the first
/// frame so a cold start does not push before the router exists (3.2.2 lesson).
final shareIntakeProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;

  Future<void> open(String text) async {
    await WidgetsBinding.instance.endOfFrame;
    final router = ref.read(routerProvider);
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
