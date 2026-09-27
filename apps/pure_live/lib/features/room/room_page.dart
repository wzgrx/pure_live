import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/room/room_layout.dart';
import 'package:pure_live_app/l10n/strings.dart';
import 'package:url_launcher/url_launcher.dart';

/// A room's details.
final FutureProviderFamily<RoomDetail, RoomRef> roomDetailProvider = FutureProvider.autoDispose
    .family<RoomDetail, RoomRef>((ref, room) async {
      final detail = await ref.watch(sitesProvider)[room.platform]!.rooms.detail(room);
      // Opening a room records it in the history and refreshes a followed card.
      final store = ref.read(storeProvider);
      final snapshot = RoomSnapshot.fromDetail(detail);
      await store.history.record(snapshot);
      await store.rooms.update([snapshot]);
      return detail;
    });

/// Whether a room is followed.
final StreamProviderFamily<bool, RoomRef> isFollowedProvider = StreamProvider.autoDispose.family<bool, RoomRef>(
  (ref, room) => ref.watch(storeProvider).follows.watchContains(room),
);

/// The room page: video on top at compact width, video plus chat panel from
/// expanded width (principles §5.2). No navigation bar inside a room.
class RoomPage extends ConsumerWidget {
  const new({required this.room, super.key});

  /// The room.
  final RoomRef room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(roomDetailProvider(room));
    return Scaffold(
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (error, _) {
            final text = describeError(error);
            return Column(
              children: [
                const _TopBar(),
                Expanded(
                  child: MessageView.error(
                    title: text.title,
                    message: text.message,
                    onAction: text.retryable ? () => ref.invalidate(roomDetailProvider(room)) : null,
                    secondaryLabel: '返回',
                    onSecondary: () => context.pop(),
                  ),
                ),
              ],
            );
          },
          data: (detail) => RoomLayout(
            presentation: RoomPresentation.inline,
            video: _PlayerArea(detail: detail),
            info: _RoomInfo(detail: detail),
            chat: const _ChatPlaceholder(),
          ),
        ),
      ),
    );
  }
}

class _ChatPlaceholder extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const MessageView(icon: Icons.subtitles_outlined, title: '弹幕即将接入');
}

class _TopBar extends StatelessWidget {
  const new({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: IconButton(tooltip: '返回', color: color, icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
  );
}

/// The video surface; shows the cover until playback is wired in.
class _PlayerArea extends StatelessWidget {
  const new({required this.detail});

  final RoomDetail detail;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cover = networkImage(
      detail.card.cover,
      logicalWidth: width,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final live = detail.state == LiveState.live;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              Opacity(
                opacity: 0.35,
                child: Image(image: cover, fit: BoxFit.cover),
              ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(live ? Icons.play_circle_outline : Icons.tv_off_outlined, color: Colors.white, size: 48),
                  const SizedBox(height: Space.s2),
                  Text(
                    live ? '播放器即将接入' : (detail.state == LiveState.replay ? S.replay : S.offline),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            const Positioned(left: 0, top: 0, child: _TopBar(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _RoomInfo extends ConsumerWidget {
  const new({required this.detail});

  final RoomDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final card = detail.card;
    final followed = ref.watch(isFollowedProvider(card.ref)).value ?? false;
    final audience = card.audience.online ?? card.audience.popularity ?? card.audience.cumulative;
    final avatar = networkImage(
      detail.avatar ?? card.avatar,
      logicalWidth: 48,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                foregroundImage: avatar,
                child: Text(card.anchorName.characters.firstOrNull ?? '?'),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.anchorName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        PlatformLogo(platformId: card.ref.platform),
                        const SizedBox(width: Space.s1),
                        Text(platformNames[card.ref.platform] ?? card.ref.platform, style: theme.textTheme.bodySmall),
                        if (audience != null) ...[
                          const SizedBox(width: Space.s2),
                          Text(formatCount(audience), style: LiveTheme.of(context).numeric),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (card.state == LiveState.live) const LiveBadge(),
            ],
          ),
          const SizedBox(height: Space.s3),
          Text(card.title, style: theme.textTheme.bodyLarge),
          if (card.area != null) ...[
            const SizedBox(height: Space.s1),
            Text(card.area!, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: Space.s4),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              if (followed)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.favorite, size: 18),
                  label: const Text(S.unfollow),
                  onPressed: () => ref.read(storeProvider).follows.unfollow(card.ref),
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.favorite_border, size: 18),
                  label: const Text(S.follow),
                  onPressed: () => ref.read(storeProvider).follows.follow(RoomSnapshot.fromDetail(detail)),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text(S.openSite),
                onPressed: () => launchUrl(detail.link, mode: LaunchMode.externalApplication),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 18),
                label: const Text(S.copyLink),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: detail.link.toString()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.linkCopied)));
                  }
                },
              ),
            ],
          ),
          if (detail.introduction case final intro? when intro.trim().isNotEmpty) ...[
            const SizedBox(height: Space.s4),
            Text(intro, style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
