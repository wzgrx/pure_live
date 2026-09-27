import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/share/share_text.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Offers rooms found in the clipboard (F-SHR-02, store.md §8): when the app
/// returns to the foreground the caller runs [check]; a share code or room
/// link there opens a confirmation dialog.
///
/// Each clipboard content is looked at once (declined or not), and texts
/// the app produced itself (its own share codes) are never offered back.
/// Only hashes of seen texts are kept.
final class ClipboardShareWatcher {
  /// Creates a watcher.
  new({required this.read, required this.recognizer, required this.present, required this.enabled});

  /// Reads the clipboard's text.
  final Future<String?> Function() read;

  /// Finds rooms in text.
  final ShareTextRecognizer recognizer;

  /// Asks the user and opens the room.
  final Future<void> Function(SharedRoom room) present;

  /// Whether the user allows reading the clipboard.
  final bool Function() enabled;

  final LinkedHashSet<String> _seen = LinkedHashSet();
  Future<bool>? _running;

  static const _remembered = 64;

  static String _hash(String text) => sha256.convert(utf8.encode(text.trim())).toString();

  /// Marks [text] as seen, for example a share code this app just copied.
  void remember(String text) {
    final hash = _hash(text);
    _seen
      ..remove(hash)
      ..add(hash);
    while (_seen.length > _remembered) {
      _seen.remove(_seen.first);
    }
  }

  /// Looks at the clipboard once; true when a room was offered. Concurrent
  /// calls share the running check.
  Future<bool> check() => _running ??= _check().whenComplete(() => _running = null);

  Future<bool> _check() async {
    if (!enabled()) return false;
    String? text;
    try {
      text = await read();
    } on Object {
      return false;
    }
    if (text == null || text.trim().isEmpty) return false;
    final hash = _hash(text);
    if (_seen.contains(hash)) return false;
    remember(text);
    final room = await recognizer.recognize(text);
    if (room == null) return false;
    await present(room);
    return true;
  }
}

/// The app's clipboard watcher: reads the system clipboard, recognises codes
/// and links with the adapters, asks with [openSharedRoom].
final clipboardWatcherProvider = Provider<ClipboardShareWatcher>((ref) {
  final sites = ref.watch(sitesProvider);
  return ClipboardShareWatcher(
    read: () async => (await Clipboard.getData(Clipboard.kTextPlain))?.text,
    recognizer: ShareTextRecognizer(resolveLink: ref.watch(linkResolverProvider), supports: sites.containsKey),
    enabled: () => ref.read(appPrefsProvider).clipboardRecognition,
    present: (room) => openSharedRoom(ref.read(routerProvider), room),
  );
});

/// Asks whether to open [room] and opens it; the dialog runs on the router's
/// navigator, so it works from anywhere in the app.
Future<void> openSharedRoom(GoRouter router, SharedRoom room) async {
  final context = router.routerDelegate.navigatorKey.currentContext;
  if (context == null) return;
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => SharedRoomDialog(room: room),
  );
  if (open ?? false) unawaited(router.push(roomLocation(room.ref)));
}

/// "打开直播间？" for a room found in the clipboard.
class SharedRoomDialog extends StatelessWidget {
  const new({required this.room, super.key});

  /// The room.
  final SharedRoom room;

  @override
  Widget build(BuildContext context) {
    final platform = platformNames[room.ref.platform] ?? room.ref.platform;
    final who = room.anchorName.isNotEmpty ? room.anchorName : t.share.roomN(id: room.ref.roomId);
    return AlertDialog(
      title: Text(room.fromShareCode ? t.share.shareCodeReceived : t.share.roomLinkFound),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$platform · $who', style: Theme.of(context).textTheme.titleMedium),
          if (room.title.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(room.title)),
          const SizedBox(height: 12),
          Text(t.share.fromClipboard, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.share.enterRoom)),
      ],
    );
  }
}
