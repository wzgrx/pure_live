import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// A paged, pull-to-refresh grid of room cards for one [RoomListQuery].
class RoomGrid extends ConsumerWidget {
  const new({required this.query, this.where, this.density = CardDensity.standard, this.emptyText, super.key});

  /// The list to show.
  final RoomListQuery query;

  /// Optional client-side filter ("只看开播").
  final bool Function(RoomCard card)? where;

  /// Card density.
  final CardDensity density;

  /// Empty-state title.
  final String? emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = roomListProvider(query);
    final async = ref.watch(provider);
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const LoadingView(),
      error: (error, _) {
        final text = describeError(error);
        return MessageView.error(title: text.title, message: text.message, onAction: () => ref.invalidate(provider));
      },
      data: (state) {
        final items = where == null ? state.items : state.items.where(where!).toList();
        if (items.isEmpty && !state.hasMore) {
          return RefreshIndicator(
            onRefresh: () => ref.refresh(provider.future),
            child: ListView(
              children: [
                const SizedBox(height: 120),
                MessageView(title: emptyText ?? S.empty),
              ],
            ),
          );
        }
        return _Grid(
          items: items,
          state: state,
          density: density,
          onLoadMore: () => ref.read(provider.notifier).loadMore(),
          onRefresh: () => ref.refresh(provider.future),
        );
      },
    );
  }
}

class _Grid extends StatelessWidget {
  const new({
    required this.items,
    required this.state,
    required this.density,
    required this.onLoadMore,
    required this.onRefresh,
  });

  final List<RoomCard> items;
  final RoomListState state;
  final CardDensity density;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    // Margins and card sizes follow the window class; the column count follows
    // the content width, which excludes the navigation rail (principles §5.2).
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        final inner = constraints.maxWidth - 2 * layout.margin;
        final columns = layout.columnsFor(inner);
        final cellWidth = (inner - (columns - 1) * layout.gap) / columns;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final textHeight = (density == CardDensity.standard ? 44 : 24) * textScale + 12;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final now = DateTime.now();
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 800) onLoadMore();
            return false;
          },
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(layout.margin, layout.gap, layout.margin, layout.gap),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: layout.gap,
                      crossAxisSpacing: layout.gap,
                      mainAxisExtent: cellWidth * 9 / 16 + textHeight,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) => RoomCardTile(
                      card: items[index],
                      density: density,
                      coverWidth: cellWidth,
                      devicePixelRatio: dpr,
                      now: now,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _Footer(state: state, onRetry: onLoadMore),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const new({required this.state, required this.onRetry});

  final RoomListState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final Widget child;
    if (state.moreError != null) {
      child = TextButton(onPressed: onRetry, child: const Text(S.loadMoreFailed));
    } else if (state.hasMore) {
      child = const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      child = Text(S.noMore, style: style);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s6),
      child: Center(child: child),
    );
  }
}

/// One card: maps a live_core [RoomCard] onto the design system's view.
class RoomCardTile extends StatelessWidget {
  const new({
    required this.card,
    required this.coverWidth,
    required this.devicePixelRatio,
    required this.now,
    this.density = CardDensity.standard,
    super.key,
  });

  final RoomCard card;
  final double coverWidth;
  final double devicePixelRatio;
  final DateTime now;
  final CardDensity density;

  @override
  Widget build(BuildContext context) {
    final audience = card.audience.online ?? card.audience.popularity ?? card.audience.cumulative;
    final since = card.liveSince;
    return RoomCardView(
      platformId: card.ref.platform,
      anchorName: card.anchorName,
      title: card.title,
      isLive: card.state == LiveState.live,
      cover: networkImage(card.cover, logicalWidth: coverWidth, devicePixelRatio: devicePixelRatio),
      audience: audience == null ? null : formatCount(audience),
      liveFor: since == null || card.state != LiveState.live ? null : formatLiveDuration(now.difference(since)),
      density: density,
      onTap: () => context.push(roomLocation(card.ref)),
    );
  }
}
