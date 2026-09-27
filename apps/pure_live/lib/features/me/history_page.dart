import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/rooms/room_card_menu.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// Watch history, newest first.
final historyProvider = StreamProvider<List<HistoryEntry>>((ref) => ref.watch(storeProvider).history.watchAll());

/// Watch history with clear-and-undo (constitution: destructive actions can be undone).
class HistoryPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyProvider);
    final entries = async.value ?? const <HistoryEntry>[];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.history),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final store = ref.read(storeProvider);
                final removed = await store.history.clear(entries);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('已清空观看历史'),
                    action: SnackBarAction(label: '撤销', onPressed: () => store.history.restore(removed)),
                  ),
                );
              },
            ),
        ],
      ),
      body: async.isLoading && entries.isEmpty
          ? const LoadingView()
          : entries.isEmpty
          ? const MessageView(icon: Icons.history, title: '还没有观看记录')
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final room = entry.room;
                final watched = entry.lastWatchedAt;
                return OfflineRoomRow(
                  platformId: room.ref.platform,
                  anchorName: room.anchorName,
                  avatar: networkImage(room.avatar, logicalWidth: 40, devicePixelRatio: dpr),
                  subtitle: [room.title, if (watched != null) formatAgo(watched, now)].join(' · '),
                  onTap: () => context.push(roomLocation(room.ref)),
                  onMenu: () => unawaited(
                    showRoomCardMenu(
                      context,
                      ref,
                      room: room.ref,
                      anchorName: room.anchorName,
                      snapshot: RoomSnapshot(
                        ref: room.ref,
                        anchorName: room.anchorName,
                        title: room.title,
                        avatar: room.avatar,
                        cover: room.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
