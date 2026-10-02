import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/popular/popular_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

/// The note of a platform whose directory is not the whole site (the
/// adapter's `LiveDirectoryNotice`), rewritten for the popular page (U.4b
/// c6).
String? popularNoticeOf(LiveSite site) {
  if (site is! LiveDirectoryNotice) return null;
  final key = 'popular_scope_${site.id}';
  return i18nExists(key) ? i18n(key) : i18n((site as LiveDirectoryNotice).directoryNoticeKey);
}

/// One platform's recommendations (3.x `PopularGridView` over
/// `BasePageView`, docs/A-界面设计/A09-浏览界面/A09.2-热门): the shared [RoomFeedView] over the
/// platform's feed, with the popular page's empty state (c4) and its notes.
class PopularPlatformView extends ConsumerWidget {
  /// Creates the view of [platform].
  const new({required this.platform, super.key});

  /// Platform id.
  final String platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.read(popularCatalogProvider);
    final site = ref.read(sitesProvider).of(platform);
    return RoomFeedView(
      feed: catalog.feedOf(platform),
      keyPrefix: 'popular',
      notice: popularNoticeOf(site),
      pageSize: catalog.pageSize,
      onPageSize: (size) => catalog.pageSize = size,
      empty: (
        icon: AppIcons.emptyPopular,
        title: i18n('empty_live_title'),
        subtitle: ({required desktop}) => i18n(desktop ? 'popular_empty_desktop' : 'popular_empty_phone'),
      ),
      hiddenNote: (count) => i18n('popular_hidden_count', args: {'count': '$count'}),
      onShowHidden: () => ref.read(storeProvider).settings.set(Settings.showUnplayableInDiscover, true).ignore(),
    );
  }
}
