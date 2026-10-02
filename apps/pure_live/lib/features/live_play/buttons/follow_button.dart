import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Where a [FollowButton] sits, which decides its look.
enum FollowButtonPlace {
  /// The room's app bar: "＋ 关注" filled with the theme colour, "✓ 已关注"
  /// grey (docs/T05/T05b/T05b.1, change 12).
  bar,

  /// The room details: 3.x's heart on a tonal button.
  details,

  /// The fullscreen bars: the bar's pill on the picture (3.x
  /// `FavoriteButton`, U.2c change 6).
  video,
}

/// Follow and unfollow (3.x `FavoriteFloatingButton`, `FavoriteButton`):
/// unfollowing asks first in a small menu next to the button and then
/// offers "撤销" (docs/T05/T05g/T05g.2 c8); the state follows the store, so every button of
/// the room (bar, details, fullscreen) shows the same and a change made
/// elsewhere shows here; a spinner replaces the mark while saving.
class FollowButton extends ConsumerStatefulWidget {
  /// Creates the button for [room].
  const new({required this.room, this.latest, this.place = FollowButtonPlace.bar, this.compact = false, super.key});

  /// The room.
  final LiveRoom room;

  /// The room as known at the tap (its newest title and audience go into
  /// the follow list); [room] when null.
  final LiveRoom Function()? latest;

  /// Where the button sits.
  final FollowButtonPlace place;

  /// The bar's narrow form: the mark alone in a round button.
  final bool compact;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _pending = false;
  bool _asking = false;
  late Stream<bool> _followed;

  @override
  void initState() {
    super.initState();
    _followed = ref.read(storeProvider).follows.watchContains(widget.room);
  }

  @override
  void didUpdateWidget(FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.room.hasSameIdentity(widget.room)) {
      _followed = ref.read(storeProvider).follows.watchContains(widget.room);
    }
  }

  Future<void> _toggle(bool followed) async {
    if (_pending || _asking) return;
    final room = widget.latest?.call() ?? widget.room;
    final store = ref.read(storeProvider);
    if (followed) {
      // U.2a choice D: unfollowing asks first (no spinner while asking), in
      // a small menu next to the button, which never covers the picture's
      // middle (docs/T05/T05g/T05g.2 c8, N3): who it is, then "取消关注" in
      // red (B-15: the button says what it does).
      _asking = true;
      final bool? chosen;
      try {
        chosen = await showAppMenu<bool>(
          context,
          title: '${room.displayNick(platformName(room.platform))} · ${platformName(room.platform)}',
          preferAbove: widget.place == FollowButtonPlace.video,
          entries: [
            AppMenuEntry(
              key: const ValueKey('unfollow-confirm'),
              value: true,
              icon: AppIcons.unfollow,
              label: i18n('unfollow'),
              danger: true,
            ),
          ],
        );
      } finally {
        _asking = false;
      }
      if (!(chosen ?? false) || !mounted) return;
    }
    setState(() => _pending = true);
    try {
      if (followed) {
        // "已取消关注 X · 撤销" puts it back in its place (B-15).
        await unfollowRoom(context, store: store, room: room, confirmed: true);
      } else if (await store.follows.add(room)) {
        AppNavigator.toast(i18n('live_play_followed_toast'));
      }
    } on Object {
      AppNavigator.toast(i18n('favorite_changes_save_failed'));
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _followed,
    builder: (context, snapshot) {
      final followed = snapshot.data ?? false;
      final onPressed = _pending || !snapshot.hasData ? null : () => unawaited(_toggle(followed));
      return switch (widget.place) {
        FollowButtonPlace.bar => _bar(context, followed: followed, known: snapshot.hasData, onPressed: onPressed),
        FollowButtonPlace.details => _details(followed: followed, onPressed: onPressed),
        FollowButtonPlace.video => _video(context, followed: followed, onPressed: onPressed),
      };
    },
  );

  Widget _mark(IconData icon, Color color, {double size = 18}) => _pending
      ? SizedBox.square(
          dimension: size - 2,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        )
      : Icon(icon, size: size, color: color);

  Widget _bar(BuildContext context, {required bool followed, required bool known, required VoidCallback? onPressed}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = i18n(followed ? 'followed' : 'follow');
    if (!known) {
      // The store has not answered yet: a quiet placeholder of the button's
      // size instead of a button that may flip (E2).
      return Padding(
        key: const ValueKey('live-play-follow-placeholder'),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: widget.compact ? 40 : 76,
          height: widget.compact ? 40 : 36,
          child: DecoratedBox(
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
          ),
        ),
      );
    }
    final background = followed ? scheme.surfaceContainerHighest : scheme.primary;
    final foreground = followed ? scheme.onSurfaceVariant : scheme.onPrimary;
    final icon = followed ? AppIcons.followed : AppIcons.follow;
    if (widget.compact) {
      return IconButton.filled(
        key: const ValueKey('live-play-follow'),
        tooltip: label,
        style: IconButton.styleFrom(backgroundColor: background, foregroundColor: foreground),
        onPressed: onPressed,
        icon: _mark(icon, foreground),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilledButton.icon(
        key: const ValueKey('live-play-follow'),
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background,
          disabledForegroundColor: foreground,
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: const StadiumBorder(),
          textStyle: theme.textTheme.labelLarge?.emphasis,
        ),
        onPressed: onPressed,
        icon: _mark(icon, foreground),
        label: Text(label, maxLines: 1),
      ),
    );
  }

  Widget _details({required bool followed, required VoidCallback? onPressed}) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      key: const ValueKey('live-play-details-follow'),
      style: FilledButton.styleFrom(shape: const StadiumBorder()),
      onPressed: onPressed,
      icon: _mark(followed ? AppIcons.followedHeart : AppIcons.followHeart, scheme.onSecondaryContainer),
      label: Text(i18n(followed ? 'followed' : 'follow')),
    );
  }

  /// The fullscreen bars' pill (docs/T05/T05d/T05d.1 change 6, U.2b change
  /// 6): the bar's look on the picture, "✓ 已关注" on a light chip, "＋ 关注"
  /// filled with the theme colour; 32 high, 48 to touch.
  Widget _video(BuildContext context, {required bool followed, required VoidCallback? onPressed}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = followed ? OnVideoColors.followChip : scheme.primary;
    final foreground = followed ? OnVideoColors.foreground : scheme.onPrimary;
    return Tooltip(
      message: i18n(followed ? 'unfollow' : 'follow'),
      child: InkWell(
        key: const ValueKey('live-play-video-follow'),
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              widthFactor: 1,
              child: DecoratedBox(
                decoration: ShapeDecoration(color: background, shape: const StadiumBorder()),
                child: SizedBox(
                  height: 32,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 9, right: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _mark(followed ? AppIcons.followed : AppIcons.follow, foreground, size: 16),
                        const SizedBox(width: 3),
                        Text(
                          i18n(followed ? 'followed' : 'follow'),
                          maxLines: 1,
                          style: theme.textTheme.labelLarge?.emphasis.copyWith(fontSize: 13, color: foreground),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
