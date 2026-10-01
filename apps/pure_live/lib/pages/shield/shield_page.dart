import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/shield/block_list_tab.dart';
import 'package:pure_live/routes/route_args.dart';

/// Danmaku block lists (3.x `lib/modules/shield`).
///
/// Routes: `RoutePath.kSettingsDanmuShield`; `BlockKind.user` as the
/// argument opens the users tab.
///
/// Two tabs over `LiveStore.blockLists`: blocked keywords (3.x had only
/// this list here) and blocked senders (3.x showed them only in the live
/// room's panel). The live room's filter follows every change.
class ShieldPage extends ConsumerWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String count(BlockKind kind) => '${ref.watch(blockListProvider(kind)).value?.length ?? 0}';
    return DefaultTabController(
      length: BlockKind.values.length,
      initialIndex: route.arguments == BlockKind.user ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(i18n('shield_title')),
          bottom: TabBar(
            tabs: [
              Tab(
                key: const ValueKey('shield-tab-keyword'),
                text: i18n('shield_tab_keywords', args: {'count': count(BlockKind.keyword)}),
              ),
              Tab(
                key: const ValueKey('shield-tab-user'),
                text: i18n('shield_tab_users', args: {'count': count(BlockKind.user)}),
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            BlockListTab(kind: BlockKind.keyword),
            BlockListTab(kind: BlockKind.user),
          ],
        ),
      ),
    );
  }
}
