import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Follows [room] and waits for the write (spec/product.md F-FAV-02). The
/// store writes in one transaction, so a failed write leaves the follows as
/// they were and pages that watch them never change; the failure is said.
/// Returns whether the room is followed now.
Future<bool> followWithNotice(BuildContext context, WidgetRef ref, RoomSnapshot room) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(storeProvider).follows.follow(room);
    return true;
  } on Object catch (error, stack) {
    ref.read(appLogProvider).error('follows', 'follow ${room.ref.key} failed', error, stack);
    messenger?.showSnackBar(SnackBar(content: Text(t.follows.followFailed)));
    return false;
  }
}

/// Unfollows [room] and waits for the write (F-FAV-02); returns the removed
/// entry for undo, or null when nothing was removed. A failed write keeps the
/// follow and is said.
Future<FollowedRoom?> unfollowWithNotice(BuildContext context, WidgetRef ref, RoomRef room) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    return await ref.read(storeProvider).follows.unfollow(room);
  } on Object catch (error, stack) {
    ref.read(appLogProvider).error('follows', 'unfollow ${room.key} failed', error, stack);
    messenger?.showSnackBar(SnackBar(content: Text(t.follows.unfollowFailed)));
    return null;
  }
}

/// Unfollows with "已取消关注" and an undo action; the undo reports its own
/// failure (F-FAV-02).
Future<void> unfollowWithUndo(BuildContext context, WidgetRef ref, RoomRef room, String name) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final store = ref.read(storeProvider);
  final log = ref.read(appLogProvider);
  final removed = await unfollowWithNotice(context, ref, room);
  if (removed == null) return;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(t.follows.unfollowed(name: name)),
      action: SnackBarAction(
        label: t.common.undo,
        onPressed: () async {
          try {
            await store.follows.restore([removed]);
          } on Object catch (error, stack) {
            log.error('follows', 'undo unfollow ${room.key} failed', error, stack);
            messenger.showSnackBar(SnackBar(content: Text(t.follows.undoFailed)));
          }
        },
      ),
    ),
  );
}
