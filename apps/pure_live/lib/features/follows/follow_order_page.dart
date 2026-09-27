import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The custom order of the follows page (spec/product.md F-FAV-01, 自定义):
/// drag a streamer to its place; the order is stored at once.
class FollowOrderPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FollowOrderPage> createState() => _FollowOrderPageState();
}

class _FollowOrderPageState extends ConsumerState<FollowOrderPage> {
  /// The order shown while a write is on its way, so a drop never jumps back.
  List<RoomRef>? _pending;

  Future<void> _move(List<FollowedRoom> follows, int from, int to) async {
    final order = [for (final follow in follows) follow.ref];
    order.insert(to, order.removeAt(from));
    setState(() => _pending = order);
    try {
      await ref.read(storeProvider).follows.reorder(order);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.follows.orderNotSaved)));
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final follows = ref.watch(followsProvider).value ?? const <FollowedRoom>[];
    final pending = _pending;
    final shown = pending == null
        ? follows
        : [for (final ref in pending) ...follows.where((follow) => follow.ref == ref)];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.follows.reorder)),
      body: shown.isEmpty
          ? MessageView(icon: Icons.favorite_border, title: t.follows.emptyTitle)
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
                child: ReorderableListView.builder(
                  itemCount: shown.length,
                  onReorderItem: (from, to) => unawaited(_move(shown, from, to)),
                  itemBuilder: (context, index) {
                    final room = shown[index].room;
                    return ListTile(
                      key: ValueKey(room.ref.key),
                      leading: CircleAvatar(
                        foregroundImage: networkImage(room.avatar, logicalWidth: 40, devicePixelRatio: dpr),
                        child: Text(room.anchorName.characters.firstOrNull ?? '?'),
                      ),
                      title: Text(room.anchorName.isEmpty ? room.ref.roomId : room.anchorName),
                      subtitle: Text(platformName(room.ref.platform)),
                      trailing: const Icon(Icons.drag_handle),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
