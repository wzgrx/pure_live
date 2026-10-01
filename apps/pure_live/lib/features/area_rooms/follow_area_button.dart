import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Follows or unfollows the area (3.x `FavoriteAreaFloatingButton`): the
/// area's picture (or first letter) with "follow · name" while not
/// followed; once followed it shrinks to the picture with a heart (new: 3.x
/// showed the bare picture, which did not say it was followed). Unfollowing
/// asks first; both say what happened (new).
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

  Widget _avatar(BuildContext context, {required bool followed}) {
    final theme = Theme.of(context);
    final name = areaDisplayName(widget.area);
    final first = String.fromCharCode(name.runes.first);
    final picture = normalizeImageUrl(ref.watch(areaPicturesProvider).pictureFor(widget.area));
    Widget letter(BuildContext context) => Center(
      child: Text(first, style: context.textStyles.t12Bold.copyWith(color: theme.colorScheme.onPrimaryContainer)),
    );
    return SizedBox.square(
      dimension: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primaryContainer),
            child: ClipOval(
              child: SizedBox.square(
                dimension: 32,
                child: picture.isEmpty
                    ? letter(context)
                    : LiveNetworkImage(url: picture, placeholder: letter, error: letter, memCacheWidth: 64),
              ),
            ),
          ),
          if (followed)
            Positioned(
              right: -4,
              bottom: -4,
              child: DecoratedBox(
                decoration: BoxDecoration(color: theme.colorScheme.surface, shape: BoxShape.circle),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.favorite_rounded, size: 12, color: theme.colorScheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final followed = ref.watch(followedAreaKeysProvider).value?.contains(widget.area.identityKey) ?? false;
    final radius = BorderRadius.circular(followed ? 24 : 16);
    final wide = MediaQuery.sizeOf(context).width > 680;
    return Tooltip(
      message: followed ? i18n('unfollow') : i18n('follow'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.95),
          borderRadius: radius,
          border: Border.all(
            color: followed
                ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
                : theme.colorScheme.primary.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('follow-area-button'),
            borderRadius: radius,
            onTap: _busy ? null : _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _avatar(context, followed: followed),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOutCubic,
                    child: followed
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  i18n('follow'),
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.1),
                                ),
                                const SizedBox(height: 1),
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: wide ? 120 : 80),
                                  child: Text(
                                    areaDisplayName(widget.area),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.textStyles.t12Bold.copyWith(
                                      color: theme.colorScheme.primary,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
