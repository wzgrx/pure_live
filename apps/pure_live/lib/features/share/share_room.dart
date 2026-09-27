import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/share/clipboard_watch.dart';

/// The 3.x-compatible share code of a room (F-SHR-01, store.md §8).
String shareCodeOf(RoomDetail detail) {
  final card = detail.card;
  return ShareCode(
    card.ref,
    title: card.title,
    anchorName: card.anchorName,
    link: detail.link.toString(),
    cover: card.cover?.toString() ?? '',
    avatar: (detail.avatar ?? card.avatar)?.toString() ?? '',
  ).encode();
}

/// Shares a room (F-SHR-01) for the room page's menu:
///
/// ```dart
/// onPressed: () => shareRoom(context, ref, detail),
/// ```
///
/// Copies the share code to the clipboard and says so; the app has no system
/// share-sheet plugin yet, so phones copy too. The code is remembered, so the
/// clipboard check does not offer the user's own share back.
Future<void> shareRoom(BuildContext context, WidgetRef ref, RoomDetail detail) async {
  final text = shareCodeOf(detail);
  ref.read(clipboardWatcherProvider).remember(text);
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('分享口令已复制。对方复制后打开纯粹直播（3.x 或 v4），即可进入这个直播间')));
  }
}
