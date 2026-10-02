import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/danmaku/block_manager.dart';

/// Danmaku blocking in the settings (3.x `lib/modules/shield`,
/// docs/A-界面设计/A08-弹幕界面/A08.3-弹幕屏蔽页).
///
/// Routes: `RoutePath.kSettingsDanmuShield`; `BlockKind.user` as the
/// argument scrolls to the blocked users.
///
/// The live room's "屏蔽管理" component ([DanmakuBlockManager], U.2e E4) as
/// a page of its own: blocked keywords, blocked viewers, the platform's
/// filter and the similarity filter (3.x had only the keywords here, c2).
/// One store for both, so a change holds in every room at once. At most
/// 720 wide (c6).
class ShieldPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height < 480;
    return Scaffold(
      appBar: AppBar(toolbarHeight: short ? 48 : null, title: Text(i18n('shield_title'))),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // The component's cards keep 12 from its edges: the column is
          // 720 + 24 wide, centred, and scrolls with the whole window.
          final side = math.max(0, (constraints.maxWidth - readableContentMaxWidth - 24) / 2).toDouble();
          return DanmakuBlockManager(
            key: const ValueKey('shield-block-manager'),
            showUsers: route.arguments == BlockKind.user,
            padding: EdgeInsets.fromLTRB(side, 0, side, 32),
          );
        },
      ),
    );
  }
}
