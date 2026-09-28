import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/discover/discover_refresh.dart';
import 'package:pure_live_app/features/discover/followed_areas.dart';
import 'package:pure_live_app/features/iptv/iptv_discover.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The platform tabs of discover and search: each platform's logo and name
/// (principles §4.1: 横向的 logo 标签).
Tab platformTab(String id) => Tab(
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PlatformLogo(platformId: id, size: 18),
      const SizedBox(width: Space.s2),
      Text(platformNames[id] ?? id),
    ],
  ),
);

/// The two views of a platform in discover.
enum DiscoverSection { recommended, areas }

/// Discover: platform tabs, each with recommended rooms and areas
/// (principles §4.1; "热门" and "分区" are one entry).
///
/// On a landscape phone (compact height, principles §5.2) there is no page
/// title, 推荐 / 分区 join the platform row, and that one row scrolls away
/// with the content, so the cards get the height.
class DiscoverPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  /// The view every platform shows on a landscape phone.
  DiscoverSection _section = DiscoverSection.recommended;

  @override
  Widget build(BuildContext context) {
    final platforms = ref.watch(browsablePlatformsProvider);
    // F-DSC-03: opens on the preferred platform.
    final preferred = platforms.indexOf(ref.watch(catalogPreferredSetting));
    final short = WindowLayout(MediaQuery.sizeOf(context)).isShortLandscape && !TvScope.of(context).enabled;
    final tabs = PageTabBar(dividerHeight: short ? 0 : null, tabs: [for (final id in platforms) platformTab(id)]);
    final pages = TabBarView(
      children: [
        for (final id in platforms)
          if (id == 'iptv') const IptvDiscover() else _PlatformDiscover(platform: id, section: short ? _section : null),
      ],
    );
    return DefaultTabController(
      length: platforms.length,
      initialIndex: preferred < 0 ? 0 : preferred,
      child: short
          ? Scaffold(
              body: ScrollAwayHeader(
                header: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      Expanded(child: tabs),
                      Padding(
                        padding: EdgeInsetsDirectional.only(start: Space.s2, end: PageMargin.of(context)),
                        child: _SectionSwitch(
                          section: _section,
                          onChanged: (section) => setState(() => _section = section),
                        ),
                      ),
                    ],
                  ),
                ),
                body: pages,
              ),
            )
          : Scaffold(
              appBar: PageAppBar(title: Text(t.app.tabs.discover), bottom: tabs),
              body: pages,
            ),
    );
  }
}

/// 推荐 / 分区 in the platform row of a landscape phone.
class _SectionSwitch extends StatelessWidget {
  const new({required this.section, required this.onChanged});

  final DiscoverSection section;
  final ValueChanged<DiscoverSection> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<DiscoverSection>(
    showSelectedIcon: false,
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    segments: [
      ButtonSegment(value: DiscoverSection.recommended, label: Text(t.discover.recommended)),
      ButtonSegment(value: DiscoverSection.areas, label: Text(t.discover.areas)),
    ],
    selected: {section},
    onSelectionChanged: (value) => onChanged(value.single),
  );
}

class _PlatformDiscover extends StatelessWidget {
  const new({required this.platform, this.section});

  final String platform;

  /// The one view to show (landscape phones pick it in the platform row);
  /// null shows 推荐 and 分区 as tabs.
  final DiscoverSection? section;

  // F-APP-03: reloads when the app comes back after a while.
  Widget get _recommended => RoomGrid(query: RecommendedQuery(platform), refreshOn: discoverRefreshProvider);

  @override
  Widget build(BuildContext context) => switch (section) {
    DiscoverSection.recommended => _recommended,
    DiscoverSection.areas => _Categories(platform: platform),
    null => DefaultTabController(
      length: 2,
      child: Column(
        // Full width, so the scrollable tab bar starts at the edge instead of
        // shrinking to its tabs and sitting in the middle.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTabBar(
            dividerHeight: 0,
            tabs: [
              Tab(text: t.discover.recommended, height: 40),
              Tab(text: t.discover.areas, height: 40),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _recommended,
                _Categories(platform: platform),
              ],
            ),
          ),
        ],
      ),
    ),
  };
}

class _Categories extends ConsumerWidget {
  const new({required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider(platform));
    final layout = WindowLayout(MediaQuery.sizeOf(context));
    return async.when(
      loading: () => const LoadingView(),
      error: (error, _) {
        final text = describeError(error);
        return MessageView.error(
          title: text.title,
          message: text.message,
          onAction: () => ref.invalidate(categoriesProvider(platform)),
        );
      },
      data: (categories) {
        final followed = followedAreasIn(ref.watch(followedAreasProvider).value ?? const [], platform, categories);
        return ListView(
          padding: EdgeInsets.symmetric(horizontal: layout.margin, vertical: Space.s2),
          children: [
            if (followed.isNotEmpty)
              _CategorySection(
                platform: platform,
                category: Category(
                  id: '_followed',
                  name: t.discover.savedAreas,
                  areas: [for (final (area, _) in followed) area],
                ),
              ),
            for (final category in categories) _CategorySection(platform: platform, category: category),
          ],
        );
      },
    );
  }
}

class _CategorySection extends StatelessWidget {
  const new({required this.platform, required this.category});

  final String platform;
  final Category category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s2),
            child: Text(category.name, style: theme.textTheme.titleSmall),
          ),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              for (final area in category.areas)
                ActionChip(
                  label: Text(areaName(area)),
                  onPressed: () => context.push(areaLocation(platform), extra: area),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
