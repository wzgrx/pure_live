import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/search/search_history.dart';
import 'package:pure_live/features/search/search_model.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// Search as a page of its own (the phone's `RoutePath.kSearch` on the TV).
class TvSearchPage extends StatelessWidget {
  /// Creates the page for [route]; a `String` argument is searched at once.
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TvTheme.of(context).background,
    body: TvBackground(child: TvSearchPane(initial: route.arguments is String ? route.arguments! as String : null)),
  );
}

/// Search with the remote (pure_live_TV `TvSearchPage` over v4's search
/// model, M13.4):
///
/// - the field opens the system keyboard through a native input dialog on
///   Android ([TvTextInput]: the TV's IME and its voice input, where the box
///   has one), a text field elsewhere;
/// - before a search, the recent words (v4's search history): OK searches
///   one again, a held OK removes it;
/// - the platform tabs (all, then the platform list) search the same words
///   there; results are rooms in a grid that loads more at its end;
/// - Back from the results goes back to the field and the history.
class TvSearchPane extends ConsumerStatefulWidget {
  /// Creates the pane; [initial] is searched at once.
  const new({this.initial, super.key});

  /// Words to search when the pane opens.
  final String? initial;

  @override
  ConsumerState<TvSearchPane> createState() => _TvSearchPaneState();
}

class _TvSearchPaneState extends ConsumerState<TvSearchPane> {
  late final SearchModel _model;
  late final SearchHistory _history;
  final FocusNode _field = FocusNode(debugLabel: 'tv search field');
  final GlobalKey<TvTabBarState> _tabs = GlobalKey();
  final GlobalKey<TvRoomGridState> _grid = GlobalKey();
  bool _showResults = false;
  TvHomeHost? _host;

  @override
  void initState() {
    super.initState();
    final store = ref.read(storeProvider);
    final registry = ref.read(sitesProvider);
    final settings = store.settings;
    final realOnline = settings.get(Settings.realOnlinePlatforms).toSet();
    _model = SearchModel(
      sites: [for (final id in registry.availableIds(settings.get(Settings.hotAreasList))) registry.of(id)],
      audienceCompare: (left, right) => LiveRoom.compareAudienceRanking(
        left,
        right,
        preferRealOnline: settings.get(Settings.preferRealOnlineCounts),
        platformEnabled: realOnline.contains,
      ),
    )..addListener(_changed);
    _history = SearchHistory(store.meta)..addListener(_changed);
    unawaited(_history.load());
    if (widget.initial case final word? when word.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(word));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = TvHomeScope.maybeOf(context);
    final host = scope?.host;
    if (host != null && host != _host) {
      _host = host;
      host.setBackHandler(TvPane.search, _back);
    }
  }

  @override
  void dispose() {
    _host?.setBackHandler(TvPane.search, null);
    _model
      ..removeListener(_changed)
      ..dispose();
    _history
      ..removeListener(_changed)
      ..dispose();
    _field.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Back inside the pane: from the results to the field.
  bool _back() {
    if (!_showResults) return false;
    setState(() => _showResults = false);
    _field.requestFocus();
    return true;
  }

  /// Clears the recent words after asking (pure_live_TV asked; the focus
  /// starts on cancel, U.15a c12).
  Future<void> _clearRecent(int count) async {
    final confirmed = await showTvConfirm(
      context,
      title: i18n('tv_search_clear_title'),
      message: i18n('tv_search_clear_message', args: {'count': '$count'}),
      confirmLabel: i18n('tv_search_clear'),
      danger: true,
    );
    if (confirmed) await _history.clear();
  }

  void _search(String word) {
    final text = word.trim();
    if (text.isEmpty) return;
    setState(() => _showResults = true);
    unawaited(_history.add(text));
    unawaited(_model.search(text));
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final standalone = TvHomeScope.maybeOf(context) == null;
    return PopScope<Object?>(
      canPop: !standalone || !_showResults,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(scale.px(12), scale.px(16), scale.px(12), scale.px(4)),
            child: TvInputField(
              focusNode: _field,
              autofocus: standalone,
              text: _model.keyword,
              hint: i18n('tv_search_hint'),
              onSubmitted: _search,
            ),
          ),
          TvTabBar(
            key: _tabs,
            small: true,
            tabs: [
              TvTab(id: SiteIds.all, label: i18n('tv_all_platforms'), icon: TvIcons.allPlatforms),
              for (final site in _model.sites)
                TvTab(
                  id: site.id,
                  label: platformName(site.id, fallback: site.name),
                  logo: site.id,
                ),
            ],
            selected: _model.selected,
            busy: _model.loading || _model.loadingMore,
            onSelect: (index) => _model.select(index, draft: _model.keyword),
            onRefresh: () => _search(_model.keyword),
            onDown: _showResults ? () => _grid.currentState?.enter() ?? false : null,
          ),
          Expanded(child: _showResults ? _results() : _recent()),
        ],
      ),
    );
  }

  Widget _results() {
    final rooms = _model.results;
    if (rooms.isEmpty) {
      if (_model.loading) return const TvSkeletonGrid();
      final unsupported = _model.unsupported;
      return TvStatusView(
        icon: TvIcons.noResults,
        title: unsupported != null
            ? i18n('tv_search_unsupported', args: {'platform': platformName(unsupported.id)})
            : i18n('tv_search_empty'),
        subtitle: _model.failed.isEmpty
            ? i18n('tv_search_empty_hint')
            : i18n('tv_search_failed', args: {'platforms': _model.failed.map(platformName).join('、')}),
      );
    }
    return TvRoomGrid(
      key: _grid,
      rooms: rooms,
      showPlatform: _model.selected == 0,
      onLeaveUp: () => _tabs.currentState?.focusSelected(),
      onEndReached: () {
        if (_model.hasMore && !_model.loadingMore && !_model.loading) unawaited(_model.loadMore());
      },
    );
  }

  Widget _recent() {
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    final words = _history.words;
    if (words.isEmpty) {
      return TvStatusView(icon: TvIcons.searchIntro, title: i18n('tv_menu_search'), subtitle: i18n('tv_search_intro'));
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(scale.px(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                i18n('tv_search_recent'),
                style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: palette.text),
              ),
              SizedBox(width: scale.px(12)),
              Text(i18n('tv_search_recent_hint'), style: scale.font(TvTextSize.small, color: palette.textSecondary)),
              const Spacer(),
              TvButton(
                key: const ValueKey('tv-search-clear'),
                icon: TvIcons.clearAll,
                label: i18n('tv_search_clear'),
                kind: TvButtonKind.danger,
                onTap: () => unawaited(_clearRecent(words.length)),
              ),
            ],
          ),
          SizedBox(height: scale.px(12)),
          Wrap(
            spacing: scale.px(12),
            runSpacing: scale.px(12),
            children: [
              for (final word in words)
                TvButton(
                  key: ValueKey('tv-search-word-$word'),
                  icon: TvIcons.recentWord,
                  label: word,
                  small: true,
                  onTap: () => _search(word),
                  onLongPress: () => unawaited(_history.remove(word)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
