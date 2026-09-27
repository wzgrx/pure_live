import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/features/iptv/iptv_widgets.dart';

const _methods = MethodChannel('purelive/share');
const _files = EventChannel('purelive/share/files');

/// Playlist files shared into the app or opened with it on Android
/// (spec/modules/iptv.md §6): MainActivity reads the file (at most 32 MB)
/// and hands over `{name, bytes}`; the IPTV page asks before importing.
/// Waits for the first frame so a cold start does not push before the router
/// exists.
final iptvShareIntakeProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;

  Future<void> open(Object? value) async {
    if (value is! Map) return;
    final bytes = value['bytes'];
    final name = value['name'];
    if (bytes is! Uint8List || bytes.isEmpty) return;
    await WidgetsBinding.instance.endOfFrame;
    unawaited(
      ref
          .read(routerProvider)
          .push(
            iptvLocation,
            extra: IptvImportRequest(bytes: bytes, fileName: name is String ? name : null),
          ),
    );
  }

  unawaited(_methods.invokeMethod<Object?>('takePendingFile').then(open, onError: (Object _) {}));
  final subscription = _files.receiveBroadcastStream().listen(open, onError: (Object _) {});
  ref.onDispose(subscription.cancel);
});
