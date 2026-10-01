import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/search/search_capability.dart';
import 'package:pure_live/pages/search/search_model.dart';
import 'package:pure_live/pages/search/search_ranking.dart';

/// Height of the platform row under the search field.
const double searchPlatformStripHeight = 56;

/// The platform row (3.x `SearchPlatformStrip`): "all" and the user's
/// platforms as chips with their logos, the chosen one scrolled into view.
class SearchPlatformStrip extends StatefulWidget {
  /// Creates the row.
  const new({required this.sites, required this.selected, required this.onSelected, super.key});

  /// The platforms after "all".
  final List<LiveSite> sites;

  /// The chosen index (0 is all).
  final int selected;

  /// Chooses an index.
  final ValueChanged<int> onSelected;

  @override
  State<SearchPlatformStrip> createState() => _SearchPlatformStripState();
}

class _SearchPlatformStripState extends State<SearchPlatformStrip> {
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);
  List<GlobalKey> _keys = const [];

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.sites.length + 1, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(covariant SearchPlatformStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sites.length != widget.sites.length) {
      _keys = List.generate(widget.sites.length + 1, (_) => GlobalKey());
    }
    if (oldWidget.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final item = widget.selected < _keys.length ? _keys[widget.selected].currentContext : null;
        if (!mounted || item == null) return;
        Scrollable.ensureVisible(
          item,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: searchPlatformStripHeight,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false, scrollbars: false),
        child: ListView.separated(
          key: const ValueKey('search-platform-strip'),
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const PureLiveBoundedScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          itemCount: widget.sites.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final selected = index == widget.selected;
            final site = index == 0 ? null : widget.sites[index - 1];
            return Center(
              key: _keys[index],
              child: ChoiceChip(
                key: ValueKey('search-platform-$index'),
                avatar: site == null
                    ? Icon(Icons.apps_rounded, size: 18, color: selected ? scheme.onSecondaryContainer : null)
                    : PlatformLogo(site.id, size: 18),
                label: Text(site == null ? i18n('site_all') : searchPlatformName(site.id, site.name)),
                selected: selected,
                showCheckmark: false,
                side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
                onSelected: (_) => widget.onSelected(index),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The filters under the platform row: rooms or streamers, offline results,
/// order, the web search, and what the chosen platforms can find.
class SearchOptionsBar extends StatelessWidget {
  /// Creates the bar.
  const new({required this.model, required this.onModeChanged, required this.onOpenWebSearch, super.key});

  /// The search.
  final SearchModel model;

  /// Switches rooms and streamers.
  final ValueChanged<SearchMode> onModeChanged;

  /// Opens the chosen platform's web search.
  final VoidCallback onOpenWebSearch;

  /// The words of [mode].
  static String sortLabel(SearchSortMode mode) => switch (mode) {
    SearchSortMode.smart => i18n('search_sort_smart'),
    SearchSortMode.platform => i18n('search_sort_platform'),
    SearchSortMode.audience => i18n('search_sort_audience'),
    SearchSortMode.followers => i18n('search_sort_followers'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const PureLiveBoundedScrollPhysics(),
              child: Row(
                children: [
                  SegmentedButton<SearchMode>(
                    key: const ValueKey('search-mode'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      ButtonSegment(
                        value: SearchMode.rooms,
                        icon: const Icon(Icons.live_tv_rounded, size: 17),
                        label: Text(i18n('search_mode_rooms')),
                      ),
                      ButtonSegment(
                        value: SearchMode.anchors,
                        icon: const Icon(Icons.person_search_rounded, size: 17),
                        label: Text(i18n('search_mode_anchors')),
                      ),
                    ],
                    selected: {model.mode},
                    onSelectionChanged: (value) => onModeChanged(value.single),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    key: const ValueKey('search-include-offline'),
                    avatar: const Icon(Icons.offline_bolt_rounded, size: 17),
                    label: Text(i18n('search_include_offline')),
                    selected: model.includeOffline,
                    onSelected: (value) => model.setIncludeOffline(value: value),
                  ),
                  if (model.mode == SearchMode.rooms) ...[
                    const SizedBox(width: 8),
                    PopupMenuButton<SearchSortMode>(
                      key: const ValueKey('search-sort-selector'),
                      tooltip: sortLabel(model.sort),
                      initialValue: model.sort,
                      onSelected: model.setSort,
                      itemBuilder: (context) => [
                        for (final mode in SearchSortMode.values)
                          PopupMenuItem(value: mode, child: Text(sortLabel(mode))),
                      ],
                      child: Chip(avatar: const Icon(Icons.sort_rounded, size: 17), label: Text(sortLabel(model.sort))),
                    ),
                  ],
                  if (model.canOpenWebSearch) ...[
                    const SizedBox(width: 8),
                    ActionChip(
                      key: const ValueKey('search-web'),
                      avatar: const Icon(Icons.open_in_browser_rounded, size: 17),
                      label: Text(i18n('continue_web_search')),
                      onPressed: onOpenWebSearch,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            _CoverageLine(model: model),
          ],
        ),
      ),
    );
  }
}

/// One line on what the chosen platforms find; tapping shows every
/// platform's scope (3.x showed the whole text with "expand").
class _CoverageLine extends StatelessWidget {
  const new({required this.model});

  final SearchModel model;

  String get _text {
    final site = model.selectedSite;
    if (site != null) {
      final name = searchPlatformName(site.id, site.name);
      if (model.mode == SearchMode.anchors && !SearchCapabilities.of(site.id).anchors) {
        return i18n('search_anchor_unsupported', args: {'site': name});
      }
      return searchCoverageText(SearchCapabilities.of(site.id), name);
    }
    if (model.mode == SearchMode.anchors) {
      final names = [
        for (final site in model.sites)
          if (SearchCapabilities.of(site.id).anchors) searchPlatformName(site.id, site.name),
      ];
      return i18n('search_anchor_platforms', args: {'sites': names.join('、')});
    }
    final count = model.sites.where((site) => SearchCapabilities.of(site.id).native).length;
    return i18n('search_scope_summary', args: {'count': '$count'});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.3);
    return InkWell(
      key: const ValueKey('search-coverage'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => showSearchScopeSheet(context, model.sites),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Shows what every platform in [sites] can find, grouped by scope.
Future<void> showSearchScopeSheet(BuildContext context, List<LiveSite> sites) {
  const groups = [
    (SearchCoverage.liveAndOffline, 'search_scope_group_live_and_offline'),
    (SearchCoverage.liveOnly, 'search_scope_group_live_only'),
    (SearchCoverage.showcaseSnapshot, 'search_scope_group_showcase'),
    (SearchCoverage.channelLookup, 'search_scope_group_lookup'),
    (SearchCoverage.roomLookup, 'search_scope_group_lookup'),
    (SearchCoverage.localChannels, 'search_scope_group_local'),
    (SearchCoverage.unavailable, 'search_scope_group_unavailable'),
    (SearchCoverage.webOnly, 'search_scope_group_unavailable'),
  ];
  final byTitle = <String, List<LiveSite>>{};
  for (final (coverage, title) in groups) {
    for (final site in sites) {
      if (SearchCapabilities.of(site.id).coverage == coverage) (byTitle[title] ??= []).add(site);
    }
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => ListView(
          key: const ValueKey('search-scope-sheet'),
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(i18n('search_scope_title'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              i18n('search_scope_sheet_desc'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            for (final MapEntry(key: title, value: members) in byTitle.entries) ...[
              const SizedBox(height: 16),
              Text(i18n(title), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 6),
              for (final site in members)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: PlatformLogo(site.id, size: 24),
                  title: Text(searchPlatformName(site.id, site.name)),
                  subtitle: Text(_siteDetail(site)),
                ),
            ],
          ],
        ),
      );
    },
  );
}

String _siteDetail(LiveSite site) {
  final capability = SearchCapabilities.of(site.id);
  return [
    searchCoverageText(capability, searchPlatformName(site.id, site.name)),
    if (capability.anchors) i18n('search_scope_has_anchors'),
    if (capability.webSearch) i18n('search_scope_has_web'),
  ].join(' ');
}

/// Recent searches as chips; tapping one searches it again.
class SearchHistoryPanel extends StatelessWidget {
  /// Creates the panel.
  const new({required this.words, required this.onSelected, required this.onRemove, required this.onClear, super.key});

  /// The words, newest first.
  final List<String> words;

  /// Searches a word.
  final ValueChanged<String> onSelected;

  /// Removes a word.
  final ValueChanged<String> onRemove;

  /// Removes every word.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('search-history'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text(i18n('search_history'), style: theme.textTheme.titleSmall)),
              TextButton.icon(
                key: const ValueKey('search-history-clear'),
                onPressed: onClear,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(i18n('search_history_clear')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final word in words)
                InputChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(word, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  onPressed: () => onSelected(word),
                  onDeleted: () => onRemove(word),
                  deleteButtonTooltipMessage: i18n('search_history_remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A placeholder grid while the first results load (instead of 3.x's
/// single spinner).
class SearchSkeletonGrid extends StatelessWidget {
  /// Creates the grid with [columns] columns.
  const new({required this.columns, super.key});

  /// Cards per row.
  final int columns;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
    Widget card() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: DecoratedBox(
            decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        FractionallySizedBox(
          widthFactor: 0.8,
          child: Container(
            height: 12,
            decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(6)),
          ),
        ),
        const SizedBox(height: 6),
        FractionallySizedBox(
          widthFactor: 0.5,
          child: Container(
            height: 10,
            decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(5)),
          ),
        ),
      ],
    );
    return Padding(
      key: const ValueKey('search-skeleton'),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var row = 0; row < 3; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: 8),
                    Expanded(child: card()),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A streamer in the results.
class AnchorResultTile extends StatelessWidget {
  /// Creates the tile.
  const new({required this.result, required this.platformName, required this.onTap, super.key});

  /// The streamer.
  final AnchorResult result;

  /// The platform's name.
  final String platformName;

  /// Opens the streamer's room.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = result.item.userName.trim().isEmpty ? platformName : result.item.userName.trim();
    return ListTile(
      onTap: onTap,
      leading: CommonAvatar(avatarUrl: result.item.avatar, fallbackName: name),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          PlatformLogo(result.platform, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$platformName · ${i18n('room_id_label', args: {'id': result.item.roomId})}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: result.isLive
          ? Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.primaryContainer,
              side: BorderSide.none,
              label: Text(i18n('live'), style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
            )
          : Text(i18n('offline'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
    );
  }
}
