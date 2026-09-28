import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/audience.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';
import 'package:pure_live_app/features/rooms/room_card_menu.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

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
  const new({
    required this.query,
    this.where,
    this.arrange,
    this.density,
    this.emptyText,
    this.refreshOn,
    this.originLabel,
    this.offlineAsRows = false,
    super.key,
  });

  /// The list to show.
  final RoomListQuery query;

  /// Rooms that are not live show as compact rows under the cards
  /// ([RoomCardGrid.offlineAsRows]).
  final bool offlineAsRows;

  /// Optional client-side filter ("只看开播").
  final bool Function(RoomCard card)? where;

  /// Optional client-side order of the loaded rooms (search sort, F-SRC-01).
  final List<RoomCard> Function(List<RoomCard> cards)? arrange;

  /// Card density; by default this device's preset (F-SET-03).
  final CardDensity? density;

  /// Empty-state title.
  final String? emptyText;

  /// Reloads the list when this changes (discover on resume, F-APP-03).
  final ProviderListenable<Object?>? refreshOn;

  /// Name of the list for switching rooms (F-NEW-04).
  final String? originLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = roomListProvider(query);
    if (refreshOn case final signal?) ref.listen(signal, (_, _) => ref.invalidate(provider));
    final async = ref.watch(provider);
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const LoadingView(),
      error: (error, _) {
        final text = describeError(error);
        return MessageView.error(title: text.title, message: text.message, onAction: () => ref.invalidate(provider));
      },
      data: (state) {
        final filtered = where == null ? state.items : state.items.where(where!).toList();
        final items = arrange == null ? filtered : arrange!(filtered);
        return RoomCardGrid(
          items: items,
          hasMore: state.hasMore,
          moreError: state.moreError,
          density: density ?? ref.watch(cardDensityProvider),
          emptyText: emptyText,
          originLabel: originLabel,
          offlineAsRows: offlineAsRows,
          onLoadMore: () => ref.read(provider.notifier).loadMore(),
          onRefresh: () => ref.refresh(provider.future),
        );
      },
    );
  }
}

/// Room cards in a grid with infinite scrolling: [onLoadMore] runs near the
/// end, the footer shows loading, a retry or the end (F-DSC-04, PLAN §10).
class RoomCardGrid extends StatefulWidget {
  const new({
    required this.items,
    required this.hasMore,
    required this.onLoadMore,
    required this.onRefresh,
    this.moreError,
    this.density = CardDensity.standard,
    this.emptyText,
    this.originLabel,
    this.header,
    this.offlineAsRows = false,
    super.key,
  });

  /// Cards in their shown order.
  final List<RoomCard> items;

  /// Rooms that are not live show as compact rows (avatar, name, title)
  /// under a "未开播" heading after the cards, as on the follows page
  /// (principles §4.1), instead of blank cover cards; search results mix
  /// both.
  final bool offlineAsRows;

  /// Whether another page can load.
  final bool hasMore;

  /// The last next-page request failed.
  final Object? moreError;

  /// Card density.
  final CardDensity density;

  /// Empty-state title.
  final String? emptyText;

  /// Name of the list for switching rooms (F-NEW-04).
  final String? originLabel;

  /// A note above the cards (partial failures).
  final Widget? header;

  /// Loads the next page; ignored while one loads.
  final VoidCallback onLoadMore;

  /// Pull to refresh.
  final Future<void> Function() onRefresh;

  @override
  State<RoomCardGrid> createState() => _RoomCardGridState();
}

class _RoomCardGridState extends State<RoomCardGrid> {
  final TvGridFocus _focus = TvGridFocus(debugLabel: 'room-grid');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty && !widget.hasMore) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            MessageView(title: widget.emptyText ?? t.common.noRooms),
          ],
        ),
      );
    }
    final cards = widget.offlineAsRows
        ? [
            for (final card in items)
              if (card.state == LiveState.live) card,
          ]
        : items;
    final rows = widget.offlineAsRows
        ? [
            for (final card in items)
              if (card.state != LiveState.live) card,
          ]
        : const <RoomCard>[];
    // The column count follows the content width, which excludes the
    // navigation rail (principles §5.2).
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = CardGridGeometry.of(context, constraints.maxWidth, density: widget.density);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final now = DateTime.now();
        final margin = grid.padding.left;
        final theme = Theme.of(context);
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 800 && widget.hasMore) widget.onLoadMore();
            return false;
          },
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (widget.header case final header?) SliverToBoxAdapter(child: header),
                SliverPadding(
                  padding: grid.padding,
                  sliver: SliverGrid.builder(
                    gridDelegate: grid.delegate,
                    itemCount: cards.length,
                    itemBuilder: (context, index) => RoomCardTile(
                      card: cards[index],
                      density: widget.density,
                      coverWidth: grid.cellWidth,
                      devicePixelRatio: dpr,
                      now: now,
                      origin: () => RoomOrigin.fromCards(items, label: widget.originLabel),
                      focusNode: _focus.node(index),
                      onFocusChange: (focused) {
                        if (focused) _focus.focused(index);
                      },
                      onKeyEvent: (node, event) => _focus.handleKey(
                        index,
                        event,
                        count: cards.length,
                        columns: grid.columns,
                        rowExtent: grid.rowExtent,
                      ),
                    ),
                  ),
                ),
                if (rows.isNotEmpty) ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(margin, Space.s4, margin, Space.s1),
                    sliver: SliverToBoxAdapter(
                      child: Text(t.follows.offlineCount(n: rows.length), style: theme.textTheme.titleSmall),
                    ),
                  ),
                  // As wide as a reading column on the grid's left line, like
                  // the follows page (principles §4.3).
                  SliverConstrainedCrossAxis(
                    maxExtent: Sizes.readingWidth + 2 * margin,
                    sliver: ListTileTheme.merge(
                      contentPadding: PageMargin.tilePadding(margin),
                      child: SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) => OfflineRoomTile(
                          card: rows[index],
                          devicePixelRatio: dpr,
                          origin: () => RoomOrigin.fromCards(items, label: widget.originLabel),
                        ),
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: _Footer(hasMore: widget.hasMore, moreError: widget.moreError, onRetry: widget.onLoadMore),
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
  const new({required this.hasMore, required this.moreError, required this.onRetry});

  final bool hasMore;
  final Object? moreError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final Widget child;
    if (moreError != null) {
      child = TextButton(onPressed: onRetry, child: Text(t.common.loadMoreFailed));
    } else if (hasMore) {
      child = const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      child = Text(t.common.noMore, style: style);
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
    final audience = shownAudience(card.audience, preferOnline: ref.watch(preferRealOnlineSetting));
    final since = card.liveSince;
    final live = card.state == LiveState.live;
    // F-FAV-01: the recording mark on every card (principles §4.2); F-FAV-04:
    // live covers follow the cover refresh period.
    final recording = ref.watch(recordingRoomsProvider.select((rooms) => rooms.value?.contains(card.ref.key) ?? false));
    final period = live ? ref.watch(coverPeriodProvider) : null;
    return RoomCardView(
      platformId: card.ref.platform,
      anchorName: card.anchorName,
      title: card.title,
      isLive: live,
      cover: networkImage(card.cover, logicalWidth: coverWidth, devicePixelRatio: devicePixelRatio, period: period),
      audience: audience == null ? null : formatCount(audience),
      liveFor: since == null || !live ? null : formatLiveDuration(now.difference(since)),
      recording: recording,
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

/// A room that is not live, as a compact row: avatar, name, title, platform
/// logo (principles §4.1); the same taps and menu as a card (§4.2).
class OfflineRoomTile extends ConsumerWidget {
  const new({required this.card, required this.devicePixelRatio, this.origin, super.key});

  final RoomCard card;
  final double devicePixelRatio;

  /// The list the room belongs to, for switching rooms (F-NEW-04).
  final RoomOrigin Function()? origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(recordingRoomsProvider.select((rooms) => rooms.value?.contains(card.ref.key) ?? false));
    return OfflineRoomRow(
      platformId: card.ref.platform,
      anchorName: card.anchorName.isEmpty ? card.ref.roomId : card.anchorName,
      avatar: networkImage(card.avatar, logicalWidth: 40, devicePixelRatio: devicePixelRatio),
      subtitle: card.title.isEmpty ? t.common.offline : card.title,
      tag: card.state == LiveState.replay ? t.follows.tag.replay : null,
      recording: recording,
      onTap: () => context.push(roomLocation(card.ref), extra: origin?.call()),
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

/// The density of discover and search cards (F-SET-03, principles §4.3):
/// v4 keeps only the density of 3.x's presets, per device family; 紧凑 is
/// one line, the others two.
final Provider<CardDensity> cardDensityProvider = Provider<CardDensity>((ref) {
  final touch = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  final preset = ref.watch(touch ? cardPresetMobileSetting : cardPresetDesktopSetting);
  return preset == CardPreset.compact ? CardDensity.compact : CardDensity.standard;
});
