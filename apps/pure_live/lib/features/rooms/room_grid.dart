import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/features/rooms/room_card_menu.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// Geometry of a card grid in a content area of a given width: the window
/// class's margins, gap and column count (principles §5.2), or on TV four
/// columns with the 20 dp gutter (§5.3). Card height follows the text
/// scale, never a constant.
@immutable
final class CardGridGeometry {
  const new({
    required this.columns,
    required this.gap,
    required this.padding,
    required this.cellWidth,
    required this.cellHeight,
  });

  /// The geometry for [context] at [width] with [density].
  factory of(BuildContext context, double width, {CardDensity density = CardDensity.standard}) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    if (TvScope.of(context).enabled) {
      // A little side room so a focused card can grow without being clipped;
      // the rail and the safe area already hold the margins.
      const padding = EdgeInsets.fromLTRB(Space.s2, Space.s3, Space.s2, TvMetrics.safeY);
      const gap = TvMetrics.gutter;
      final text = Theme.of(context).textTheme;
      double line(TextStyle style) => style.fontSize! * (style.height ?? 1.4);
      final lines = density == CardDensity.standard
          ? line(text.titleSmall!) + line(text.bodySmall!)
          : line(text.titleSmall!);
      final cellWidth = (width - padding.horizontal - (TvMetrics.columns - 1) * gap) / TvMetrics.columns;
      return CardGridGeometry(
        columns: TvMetrics.columns,
        gap: gap,
        padding: padding,
        cellWidth: cellWidth,
        cellHeight: cellWidth * 9 / 16 + lines * textScale + 16,
      );
    }
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    final inner = width - 2 * layout.margin;
    final columns = layout.columnsFor(inner);
    final cellWidth = (inner - (columns - 1) * layout.gap) / columns;
    return CardGridGeometry(
      columns: columns,
      gap: layout.gap,
      padding: EdgeInsets.fromLTRB(layout.margin, layout.gap, layout.margin, layout.gap),
      cellWidth: cellWidth,
      cellHeight: cellWidth * 9 / 16 + (density == CardDensity.standard ? 44 : 24) * textScale + 12,
    );
  }

  /// Cards per row.
  final int columns;

  /// Gap between cards.
  final double gap;

  /// Padding around the grid.
  final EdgeInsets padding;

  /// Width of a card (the cover's decode width).
  final double cellWidth;

  /// Height of a card.
  final double cellHeight;

  /// A row with its gap: how far one D-pad step down scrolls.
  double get rowExtent => cellHeight + gap;

  /// The delegate for these cards.
  SliverGridDelegate get delegate => SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: gap,
    crossAxisSpacing: gap,
    mainAxisExtent: cellHeight,
  );
}

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

class _Grid extends StatefulWidget {
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
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> {
  final TvGridFocus _focus = TvGridFocus(debugLabel: 'room-grid');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    // The column count follows the content width, which excludes the
    // navigation rail (principles §5.2).
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = CardGridGeometry.of(context, constraints.maxWidth, density: widget.density);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final now = DateTime.now();
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 800) widget.onLoadMore();
            return false;
          },
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: grid.padding,
                  sliver: SliverGrid.builder(
                    gridDelegate: grid.delegate,
                    itemCount: items.length,
                    itemBuilder: (context, index) => RoomCardTile(
                      card: items[index],
                      density: widget.density,
                      coverWidth: grid.cellWidth,
                      devicePixelRatio: dpr,
                      now: now,
                      origin: () => RoomOrigin.fromCards(items),
                      focusNode: _focus.node(index),
                      onFocusChange: (focused) {
                        if (focused) _focus.focused(index);
                      },
                      onKeyEvent: (node, event) => _focus.handleKey(
                        index,
                        event,
                        count: items.length,
                        columns: grid.columns,
                        rowExtent: grid.rowExtent,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _Footer(state: widget.state, onRetry: widget.onLoadMore),
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
class RoomCardTile extends ConsumerWidget {
  const new({
    required this.card,
    required this.coverWidth,
    required this.devicePixelRatio,
    required this.now,
    this.density = CardDensity.standard,
    this.origin,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChange,
    super.key,
  });

  final RoomCard card;
  final double coverWidth;
  final double devicePixelRatio;
  final DateTime now;
  final CardDensity density;

  /// The list the card belongs to, for switching rooms (F-NEW-04); built on
  /// open only.
  final RoomOrigin Function()? origin;

  /// Remote focus of the card in its grid.
  final FocusNode? focusNode;

  /// Grid moves.
  final FocusOnKeyEventCallback? onKeyEvent;

  /// Focus changes.
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      onFocusChange: onFocusChange,
      onTap: () => context.push(roomLocation(card.ref), extra: origin?.call()),
      // principles §4.2: the same menu on every card.
      onMenu: () => unawaited(
        showRoomCardMenu(
          context,
          ref,
          room: card.ref,
          anchorName: card.anchorName,
          snapshot: RoomSnapshot.fromCard(card),
        ),
      ),
    );
  }
}
