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

/// Discover: platform tabs, each with recommended rooms and areas
/// (principles §4.1; "热门" and "分区" are one entry).
class DiscoverPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platforms = ref.watch(browsablePlatformsProvider);
    // F-DSC-03: opens on the preferred platform.
    final preferred = platforms.indexOf(ref.watch(catalogPreferredSetting));
    return DefaultTabController(
      length: platforms.length,
      initialIndex: preferred < 0 ? 0 : preferred,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.app.tabs.discover),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final id in platforms)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PlatformLogo(platformId: id, size: 18),
                      const SizedBox(width: Space.s2),
                      Text(platformNames[id]!),
                    ],
                  ),
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final id in platforms)
              if (id == 'iptv') const IptvDiscover() else _PlatformDiscover(platform: id),
          ],
        ),
      ),
    );
  }
}

class _PlatformDiscover extends StatelessWidget {
  const new({required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerHeight: 0,
          tabs: [
            Tab(text: t.discover.recommended, height: 40),
            Tab(text: t.discover.areas, height: 40),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              // F-APP-03: reloads when the app comes back after a while.
              RoomGrid(query: RecommendedQuery(platform), refreshOn: discoverRefreshProvider),
              _Categories(platform: platform),
            ],
          ),
        ),
      ],
    ),
  );
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
