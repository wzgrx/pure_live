import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/history/history_limit_dialog.dart';
import 'package:pure_live/features/history/history_refresh.dart';
import 'package:pure_live/features/history/history_sections.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The history, newest first, again after every change.
final StreamProvider<List<LiveRoom>> historyRoomsProvider = StreamProvider.autoDispose<List<LiveRoom>>(
  (ref) => ref.watch(storeProvider).history.watchAll(),
);

/// How the page loads a room's current detail on refresh (tests replace it).
final Provider<HistoryRoomLoader> historyLoaderProvider = Provider<HistoryRoomLoader>(
  (ref) => siteHistoryLoader(ref.watch(sitesProvider)),
);

/// The page's clock, for the day sections (tests replace it).
final Provider<DateTime Function()> historyClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Watch history (3.x `lib/modules/history`, docs/ui/compare/U.5c).
///
/// Routes: `RoutePath.kHistory`.
///
/// The rooms come from `LiveStore.history` (the live room records them).
/// The app bar: "观看记录" with "18 / 50 条" under it (c2), filter, refresh,
/// the limit and clear (Z2 A); the rooms by day (c3) in a grid whose columns
/// follow the width (c8), each card with 3.x's delete button. The page
/// refreshes their state (button or pull, c4), removes one or all of them,
/// filters them (c5) and sets how many are kept (c6).
class HistoryPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _refreshView = GlobalKey<AppRefreshViewState>();
  final _query = TextEditingController();
  final _queryFocus = FocusNode();

  /// Refresh progress (0..1), null when no refresh runs.
  final _progress = ValueNotifier<double?>(null);
  Future<void>? _refreshTask;
  bool _mutating = false;
  bool _filtering = false;

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    _progress.dispose();
    super.dispose();
  }

  LiveStore get _store => ref.read(storeProvider);

  List<LiveRoom> get _rooms => ref.read(historyRoomsProvider).value ?? const [];

  List<LiveRoom> get _shown => filterHistory(_rooms, _filtering ? _query.text : '');

  /// One refresh at a time; a second pull joins the running one (3.x).
  Future<void> _refresh() => _refreshTask ??= _runRefresh().whenComplete(() => _refreshTask = null);

  Future<void> _runRefresh() async {
    final rooms = _shown;
    if (rooms.isEmpty) return;
    final store = _store;
    final load = ref.read(historyLoaderProvider);
    _progress.value = 0;
    final result = await refreshHistoryRooms(
      rooms,
      load: load,
      maxConcurrent: store.settings.get(Settings.maxConcurrentRefresh),
      onProgress: (done) {
        if (mounted) _progress.value = done / rooms.length;
      },
      isCancelled: () => !mounted,
    );
    if (mounted) _progress.value = null;
    try {
      // What was fetched is kept even when the page has closed meanwhile.
      await store.history.update(result.rooms);
    } on Object catch (error, stack) {
      log('Saving the refreshed history failed', name: 'HistoryPage', error: error, stackTrace: stack);
      if (mounted) AppNavigator.toast(i18n('history_changes_save_failed'));
      return;
    }
    if (!mounted || result.cancelled) return;
    AppNavigator.toast(
      result.failed == 0
          ? i18n('history_refresh_done', args: {'count': '${result.succeeded}'})
          : i18n('history_refresh_partial', args: {'failed': '${result.failed}', 'count': '${rooms.length}'}),
    );
  }

  Future<bool> _confirm({required String title, required String message, required String action}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Text(title, style: dialogContext.textStyles.t16Bold),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(message, style: dialogContext.textStyles.t14),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(i18n('cancel'), style: dialogContext.textStyles.t14Muted),
            ),
            FilledButton(
              key: const ValueKey('history-confirm'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Runs [change] unless another change is running, telling the user when
  /// it failed (3.x `_historyMutationBusy`).
  Future<void> _mutate(Future<bool> Function() change) async {
    if (_mutating || !mounted) return;
    setState(() => _mutating = true);
    try {
      await change();
    } on Object catch (error, stack) {
      log('Changing the history failed', name: 'HistoryPage', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('history_changes_save_failed'));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  /// Removes [room] after asking; one watched again since stays (3.x
  /// `_deleteHistoryRoom`).
  Future<void> _remove(LiveRoom room) => _mutate(() async {
    final confirmed = await _confirm(
      title: i18n('delete'),
      message: i18n('remove_history_confirm_named', args: {'title': roomLabel(room)}),
      action: i18n('delete'),
    );
    if (!confirmed) return false;
    await _store.history.clear([room]);
    AppNavigator.toast(i18n('history_removed'));
    return true;
  });

  /// Removes the entries shown (all, or those the filter matches) after
  /// asking; entries watched again since stay (3.x `_clearHistory`).
  Future<void> _clear() => _mutate(() async {
    final shown = _shown;
    if (shown.isEmpty) return false;
    final filtered = shown.length != _rooms.length;
    final count = {'count': '${shown.length}'};
    final confirmed = await _confirm(
      title: i18n('clear_history'),
      message: filtered
          ? i18n('history_clear_filtered_confirm', args: count)
          : i18n('clear_history_confirm_named', args: count),
      action: i18n('clear'),
    );
    if (!confirmed) return false;
    await _store.history.clear(shown);
    AppNavigator.toast(i18n('history_cleared', args: count));
    return true;
  });

  Future<void> _editLimit() => showHistoryLimitDialog(
    context,
    limit: _store.settings.get(Settings.historyLimit),
    count: _rooms.length,
    save: _store.history.setLimit,
  );

  void _toggleFilter() {
    setState(() {
      _filtering = !_filtering;
      if (!_filtering) _query.clear();
    });
    if (_filtering) _queryFocus.requestFocus();
  }

  /// Back and Esc close the filter first (button 1).
  void _back() {
    if (_filtering) {
      _toggleFilter();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _openMenu(LiveRoom room) => unawaited(
    showRoomMenu(
      context,
      store: _store,
      room: room,
      detail: historyWatchedLabel(room.lastWatchedAt, ref.read(historyClockProvider)()),
      actions: [
        RoomMenuAction(
          key: const ValueKey('history-menu-remove'),
          icon: AppIcons.delete,
          label: i18n('remove_history_entry_named', args: {'title': roomLabel(room)}),
          danger: true,
          onSelected: () => unawaited(_remove(room)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(historyRoomsProvider);
    final limit = watchSetting(ref, Settings.historyLimit);
    final all = rooms.value ?? const <LiveRoom>[];
    final shown = filterHistory(all, _filtering ? _query.text : '');
    return PopScope(
      canPop: !_filtering,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _filtering) _toggleFilter();
      },
      child: CallbackShortcuts(
        // Esc is Back: the filter closes first.
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
        child: FocusScope(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              centerTitle: false,
              titleSpacing: 4,
              // "观看记录" with "18 / 50 条" under it (c2, Z1 A).
              title: PageTitle(
                title: i18n('watch_history'),
                subtitle: limit == unlimitedHistoryLimit
                    ? i18n('history_count_unlimited', args: {'count': '${all.length}'})
                    : i18n('history_count_of_limit', args: {'count': '${all.length}', 'limit': '$limit'}),
              ),
              // Filter and refresh, then 3.x's limit and clear (Z2 A).
              actions: [
                IconButton(
                  key: const ValueKey('history-filter'),
                  tooltip: i18n(_filtering ? 'history_filter_close' : 'history_filter'),
                  icon: Icon(_filtering ? AppIcons.filterOff : AppIcons.filter),
                  onPressed: all.isEmpty && !_filtering ? null : _toggleFilter,
                ),
                ValueListenableBuilder(
                  valueListenable: _progress,
                  builder: (context, progress, _) => IconButton(
                    key: const ValueKey('history-refresh'),
                    tooltip: i18n('history_refresh_status'),
                    icon: const Icon(AppIcons.refresh),
                    onPressed: shown.isEmpty || progress != null
                        ? null
                        : () => unawaited(_refreshView.currentState?.show()),
                  ),
                ),
                IconButton(
                  key: const ValueKey('history-limit'),
                  tooltip: i18n('history_limit'),
                  icon: const Icon(AppIcons.historyLimit),
                  onPressed: () => unawaited(_editLimit()),
                ),
                if (shown.isNotEmpty)
                  IconButton(
                    key: const ValueKey('history-clear'),
                    tooltip: i18n('clear_history'),
                    icon: const Icon(AppIcons.clearHistory),
                    onPressed: _mutating ? null : () => unawaited(_clear()),
                  ),
                const SizedBox(width: 4),
              ],
              bottom: _filtering ? _filterBar(context, shown.length) : null,
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: switch (rooms) {
                    AsyncValue(value: final _?) when all.isEmpty => AppStatusView(
                      key: const ValueKey('history-empty'),
                      type: AppStatusType.empty,
                      icon: AppIcons.historyEmpty,
                      title: i18n('empty_history'),
                      subtitle: i18n('history_empty_hint'),
                    ),
                    AsyncValue(value: final _?) when shown.isEmpty => AppStatusView(
                      key: const ValueKey('history-filter-empty'),
                      type: AppStatusType.empty,
                      icon: AppIcons.noResults,
                      title: i18n('history_filter_empty'),
                      subtitle: '',
                    ),
                    AsyncValue(value: final _?) => _grid(context, shown, mixed: mixesPlatforms(all)),
                    AsyncValue(error: final _?) => AppStatusView(
                      type: AppStatusType.error,
                      buttonText: i18n('status_retry_button'),
                      onButtonPressed: () => ref.invalidate(historyRoomsProvider),
                    ),
                    _ => const AppStatusView(type: AppStatusType.loading),
                  },
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder(
                    valueListenable: _progress,
                    builder: (context, progress, _) => progress == null
                        ? const SizedBox.shrink()
                        : LinearProgressIndicator(
                            key: const ValueKey('history-progress'),
                            value: progress,
                            minHeight: 2,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The filter under the app bar (c5): outlined in the primary colour
  /// while open, the number of matches at its end.
  PreferredSizeWidget _filterBar(BuildContext context, int matches) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: scheme.primary, width: 2),
    );
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: TextField(
          key: const ValueKey('history-filter-field'),
          controller: _query,
          focusNode: _queryFocus,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          style: styles.t14,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            hintText: i18n('history_filter_hint'),
            hintStyle: styles.t14.copyWith(color: scheme.onSurfaceVariant),
            prefixIcon: Icon(AppIcons.filter, size: 20, color: scheme.onSurfaceVariant),
            suffixText: _query.text.isEmpty ? null : i18n('history_filter_matches', args: {'count': '$matches'}),
            suffixStyle: styles.t12.copyWith(color: scheme.onSurfaceVariant),
            border: border,
            enabledBorder: border,
            focusedBorder: border,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
    );
  }

  /// The rooms by day (c3): each day's heading with its count, then a grid
  /// whose columns follow the width (c8, docs/ui/UI_PLAN.md §5.3).
  Widget _grid(BuildContext context, List<LiveRoom> rooms, {required bool mixed}) {
    final appearance = watchCardAppearance(ref);
    final fontSizes = watchFontSizes(ref);
    final policy = watchAudiencePolicy(ref);
    final spacing = watchSetting(ref, Settings.crossAxisSpacing);
    final mainSpacing = watchSetting(ref, Settings.mainAxisSpacing);
    final sections = historySections(rooms, ref.read(historyClockProvider)());
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = RoomGridGeometry.of(
          context,
          width: constraints.maxWidth,
          spacing: spacing,
          appearance: appearance,
          fontSizes: fontSizes,
        );
        return AppRefreshView(
          key: _refreshView,
          onRefresh: _refresh,
          builder: (context, physics) => CustomScrollView(
            key: const ValueKey('history-grid'),
            physics: physics,
            slivers: [
              for (final (section, sectionRooms) in sections) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Text(
                      '${historySectionTitle(section)} · ${sectionRooms.length}',
                      key: ValueKey('history-section-${section.name}'),
                      style: context.textStyles.t13SemiBold.copyWith(color: scheme.primary).tabular,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: roomGridPadding),
                  sliver: SliverGrid.builder(
                    gridDelegate: geometry.delegate(spacing: spacing, mainSpacing: mainSpacing),
                    itemCount: sectionRooms.length,
                    itemBuilder: (context, index) {
                      final room = sectionRooms[index];
                      return LiveRoomCard(
                        key: ValueKey('history-card-${room.identityKey}'),
                        data: policy.cardOf(room),
                        appearance: appearance,
                        // The history mixes platforms: an automatic badge shows (U.4a c2).
                        mixedPlatforms: mixed,
                        showDelete: true,
                        deleteTooltip: i18n('remove_history_entry_named', args: {'title': roomLabel(room)}),
                        onDelete: _mutating ? null : () => unawaited(_remove(room)),
                        onTap: () => unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room)),
                        onLongPress: () => _openMenu(room),
                      );
                    },
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: roomGridPadding + 12)),
            ],
          ),
        );
      },
    );
  }
}
