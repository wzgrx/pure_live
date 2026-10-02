import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Follows or unfollows the area from the app bar (3.x
/// `FavoriteAreaFloatingButton`; docs/T07/T07c/T07c.3 c3, choice Y1): the
/// live room's pill, "＋ 关注" filled while not followed, "✓ 已关注" grey
/// once followed (3.x shrank to the area's picture). Unfollowing asks first
/// (3.x's dialog); while saving the pill is grey and cannot be pressed; a
/// failure says the change was not saved.
class FollowAreaButton extends ConsumerStatefulWidget {
  /// The button of [area].
  const new({required this.area, super.key});

  /// The area.
  final LiveArea area;

  @override
  ConsumerState<FollowAreaButton> createState() => _FollowAreaButtonState();
}

class _FollowAreaButtonState extends ConsumerState<FollowAreaButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await toggleAreaFollow(context, ref, widget.area);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(followedAreaKeysProvider);
    final followed = keys.value?.contains(widget.area.identityKey) ?? false;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FollowPill(
        key: const ValueKey('follow-area-button'),
        followed: followed,
        followLabel: i18n('follow'),
        followedLabel: i18n('followed'),
        tooltip: i18n(followed ? 'unfollow' : 'follow'),
        // Grey and not pressable while saving (U.4e c3).
        onPressed: keys.hasValue && !_busy ? _toggle : null,
      ),
    );
  }
}
