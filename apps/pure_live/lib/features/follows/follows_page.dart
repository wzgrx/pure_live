import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// Followed streamers: live ones as cover cards, offline ones as compact rows
/// (principles §4.1). Backed by live_store once it lands.
class FollowsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(S.follows)),
    body: MessageView(
      icon: Icons.favorite_border,
      title: S.followsEmptyTitle,
      message: S.followsEmptyMessage,
      actionLabel: S.goDiscover,
      onAction: () => context.go('/discover'),
    ),
  );
}
