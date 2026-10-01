import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/search/search_capability.dart';
import 'package:pure_live/features/search/search_model.dart';
import 'package:pure_live/features/search/search_ranking.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Height of the platform row (3.x's 56).
const double searchPlatformStripHeight = 56;

/// The page width from which the search field and the platform row share
/// one line and the filters and the scope line another (docs/ui/compare/
/// U.5a c12: phones held sideways and wide windows).
const double searchOneRowWidth = 600;

/// The widest search field (U.5a c13).
const double searchFieldMaxWidth = 480;

/// The platform row (3.x `SearchPlatformStrip`): "all" and the user's
/// platforms as chips with their logos, the chosen one scrolled to the
/// middle. A mouse wheel scrolls it sideways (U.5a c16).
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

  /// A vertical wheel turn scrolls the row sideways (3.x needed Shift).
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dy == 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final position = _scroll.position;
      _scroll.jumpTo((position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: searchPlatformStripHeight,
      child: Listener(
        onPointerSignal: _wheel,
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
                      ? Icon(AppIcons.allPlatforms, size: 18, color: selected ? scheme.onSecondaryContainer : null)
                      : PlatformLogo(site.id, size: 18),
                  label: Text(site == null ? i18n('site_all') : platformName(site.id, fallback: site.name)),
                  selected: selected,
                  showCheckmark: false,
                  side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
                  onSelected: (_) => widget.onSelected(index),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The filters under the platform row (3.x's options area, U.5a c3–c7):
/// rooms or streamers, offline results, the order, the web search of a
/// single platform, and one line on what is searched, which opens the
/// scope panel.
///
/// Narrow pages wrap the filters onto as many lines as they need (3.x hid
/// them off the right edge) with the scope line under them; with [oneLine]
/// (sideways phones, wide windows) the scope line takes the rest of the
/// filters' line, or goes under them when too little is left.
class SearchOptionsBar extends StatelessWidget {
  /// Creates the bar.
  const new({
    required this.model,
    required this.onModeChanged,
    required this.onOpenWebSearch,
    required this.onOpenScope,
    this.oneLine = false,
    super.key,
  });

  /// The search.
  final SearchModel model;

  /// Switches rooms and streamers.
  final ValueChanged<SearchMode> onModeChanged;

  /// Opens the chosen platform's web search.
  final VoidCallback onOpenWebSearch;

  /// Opens the scope panel.
  final VoidCallback onOpenScope;

  /// The scope line beside the filters.
  final bool oneLine;

  /// The words of [mode] in the order menu (3.x's whole sentences).
  static String sortLabel(SearchSortMode mode) => switch (mode) {
    SearchSortMode.smart => i18n('search_sort_smart'),
    SearchSortMode.platform => i18n('search_sort_platform'),
    SearchSortMode.audience => i18n('search_sort_audience'),
    SearchSortMode.followers => i18n('search_sort_followers'),
  };

  /// The words of [mode] on the order button (U.5a c4, X2 A: "综合 ⌄").
  static String sortShortLabel(SearchSortMode mode) => switch (mode) {
    SearchSortMode.smart => i18n('search_sort_smart_short'),
    SearchSortMode.platform => i18n('search_sort_platform_short'),
    SearchSortMode.audience => i18n('search_sort_audience_short'),
    SearchSortMode.followers => i18n('search_sort_followers_short'),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = Wrap(
      key: const ValueKey('search-filters'),
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<SearchMode>(
          key: const ValueKey('search-mode'),
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(value: SearchMode.rooms, label: Text(i18n('search_mode_rooms'))),
            ButtonSegment(value: SearchMode.anchors, label: Text(i18n('search_mode_anchors'))),
          ],
          selected: {model.mode},
          onSelectionChanged: (value) => onModeChanged(value.single),
        ),
        FilterChip(
          key: const ValueKey('search-include-offline'),
          label: Text(i18n('search_include_offline')),
          selected: model.includeOffline,
          onSelected: (value) => model.setIncludeOffline(value: value),
        ),
        if (model.mode == SearchMode.rooms) _SortButton(model: model),
        if (model.canOpenWebSearch)
          ActionChip(
            key: const ValueKey('search-web'),
            avatar: const Icon(AppIcons.webSearch, size: 18),
            label: Text(i18n('continue_web_search')),
            onPressed: onOpenWebSearch,
          ),
      ],
    );
    return Material(
      key: const ValueKey('search-options'),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: oneLine ? const EdgeInsets.symmetric(horizontal: 12) : const EdgeInsets.fromLTRB(12, 2, 12, 6),
        child: _LeadThenRest(
          inline: oneLine,
          leading: filters,
          trailing: SearchCoverageLine(model: model, oneLine: oneLine, onTap: onOpenScope),
        ),
      ),
    );
  }
}

/// The order button "≡ 综合 ⌄" and its small menu with 3.x's four
/// sentences, the current one in the primary colour with a tick (U.5a c4).
class _SortButton extends StatelessWidget {
  const new({required this.model});

  final SearchModel model;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => ActionChip(
      key: const ValueKey('search-sort-selector'),
      tooltip: i18n('search_sort'),
      avatar: const Icon(AppIcons.sort, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(SearchOptionsBar.sortShortLabel(model.sort)),
          const SizedBox(width: 2),
          const Icon(AppIcons.dropDown, size: 18),
        ],
      ),
      onPressed: () async {
        final chosen = await showAppMenu<SearchSortMode>(
          anchor,
          selected: model.sort,
          entries: [
            for (final mode in SearchSortMode.values)
              AppMenuEntry(
                key: ValueKey('search-sort-${mode.name}'),
                value: mode,
                label: SearchOptionsBar.sortLabel(mode),
              ),
          ],
        );
        if (chosen != null) model.setSort(chosen);
      },
    ),
  );
}

/// What the chosen platforms find, in one plain sentence (U.5a c5; 3.x
/// showed a developer's paragraph with "expand"): at most two lines (one
/// beside the filters); a tap opens the scope panel.
class SearchCoverageLine extends StatelessWidget {
  /// Creates the line.
  const new({required this.model, required this.onTap, this.oneLine = false, super.key});

  /// The search.
  final SearchModel model;

  /// Opens the scope panel.
  final VoidCallback onTap;

  /// One line only.
  final bool oneLine;

  /// The sentence.
  static String textOf(SearchModel model) {
    final site = model.selectedSite;
    if (site != null) {
      final name = platformName(site.id, fallback: site.name);
      if (model.mode == SearchMode.anchors && !SearchCapabilities.of(site.id).anchors) {
        return i18n('search_anchor_unsupported', args: {'site': name});
      }
      return searchCoverageText(SearchCapabilities.of(site.id), name);
    }
    if (model.mode == SearchMode.anchors) {
      final names = [
        for (final site in model.allScope)
          if (SearchCapabilities.of(site.id).anchors) platformName(site.id, fallback: site.name),
      ];
      return i18n('search_anchor_platforms', args: {'sites': names.join('、')});
    }
    final count = model.allScope.where((site) => SearchCapabilities.of(site.id).native).length;
    final left = model.sites.length - model.allScope.length;
    if (left > 0) {
      return i18n(
        'search_scope_summary_excluded',
        args: {'count': '$count', 'total': '${model.sites.length}', 'excluded': '$left'},
      );
    }
    return i18n('search_scope_summary', args: {'count': '$count'});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant, height: 1.3);
    return InkWell(
      key: const ValueKey('search-coverage'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(AppIcons.info, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  textOf(model),
                  key: const ValueKey('search-coverage-text'),
                  style: style,
                  maxLines: oneLine ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(AppIcons.openDetails, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays its two children out on one line, the second taking the rest of
/// the width, when [inline] and at least 240 is left;
/// otherwise the second goes under the first at the full width.
class _LeadThenRest extends MultiChildRenderObjectWidget {
  new({required Widget leading, required Widget trailing, required this.inline}) : super(children: [leading, trailing]);

  /// Try the one-line form.
  final bool inline;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLeadThenRest(inline: inline);

  @override
  void updateRenderObject(BuildContext context, _RenderLeadThenRest renderObject) => renderObject.inline = inline;
}

class _LeadThenRestData extends ContainerBoxParentData<RenderBox>;

class _RenderLeadThenRest extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LeadThenRestData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LeadThenRestData> {
  new({required this._inline});

  /// The narrowest second child beside the first.
  static const double minTrailingWidth = 240;

  /// The space between the two on one line.
  static const double gap = 8;

  bool _inline;
  bool get inline => _inline;
  set inline(bool value) {
    if (value == _inline) return;
    _inline = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LeadThenRestData) child.parentData = _LeadThenRestData();
  }

  /// Lays the children out with [layoutChild] and returns the size and the
  /// two offsets.
  (Size, Offset, Offset) _arrange(BoxConstraints constraints, Size Function(RenderBox, BoxConstraints) layoutChild) {
    final leading = firstChild!;
    final trailing = childAfter(leading)!;
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
    final lead = layoutChild(leading, BoxConstraints(maxWidth: width));
    final rest = width - lead.width - gap;
    if (_inline && rest >= minTrailingWidth) {
      final tail = layoutChild(trailing, BoxConstraints.tightFor(width: rest));
      final height = math.max(lead.height, tail.height);
      return (
        constraints.constrain(Size(width, height)),
        Offset(0, (height - lead.height) / 2),
        Offset(lead.width + gap, (height - tail.height) / 2),
      );
    }
    final tail = layoutChild(trailing, BoxConstraints.tightFor(width: width));
    return (constraints.constrain(Size(width, lead.height + tail.height)), Offset.zero, Offset(0, lead.height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _arrange(constraints, (child, constraints) => child.getDryLayout(constraints)).$1;

  @override
  void performLayout() {
    final (size, lead, tail) = _arrange(constraints, (child, constraints) {
      child.layout(constraints, parentUsesSize: true);
      return child.size;
    });
    this.size = size;
    (firstChild!.parentData! as _LeadThenRestData).offset = lead;
    (lastChild!.parentData! as _LeadThenRestData).offset = tail;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild!.getMaxIntrinsicWidth(height) + gap + lastChild!.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// "识别到直播链接 · 进入" over the results when the field holds a room
/// link (M13.4; U.5a c11).
class SearchLinkBanner extends StatelessWidget {
  /// Creates the banner.
  const new({required this.resolving, required this.onOpen, super.key});

  /// The link is being read.
  final bool resolving;

  /// Opens the room.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final ink = scheme.onSecondaryContainer;
    return Container(
      key: const ValueKey('search-link-banner'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n('search_link_detected'), style: styles.t14SemiBold.copyWith(color: ink)),
                const SizedBox(height: 2),
                Text(
                  i18n(resolving ? 'search_link_resolving' : 'search_link_desc'),
                  style: styles.t12.copyWith(color: ink),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (resolving)
            const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
          else
            FilledButton(
              key: const ValueKey('search-link-open'),
              onPressed: onOpen,
              child: Text(i18n('search_room_enter')),
            ),
        ],
      ),
    );
  }
}

/// "还有 N 个平台在搜索…" under a progress line while platforms answer
/// (M13.16; U.5a c8).
class SearchPendingRow extends StatelessWidget {
  /// Creates the row.
  const new({required this.count, super.key});

  /// Platforms still answering.
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('search-pending'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 4),
          Text(
            i18n('search_pending', args: {'count': '$count'}),
            style: context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Recent searches as chips; tapping one searches it again (M13.4; U.5a
/// c11).
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('search-history'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.searchHistory, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text(i18n('search_history'), style: context.textStyles.t14Medium)),
              TextButton.icon(
                key: const ValueKey('search-history-clear'),
                onPressed: onClear,
                icon: const Icon(AppIcons.clearAll, size: 18),
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
              i18n('room_menu_subtitle', args: {'platform': platformName, 'id': result.item.roomId}),
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
