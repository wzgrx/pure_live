import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Platforms whose links are understood (a pasted room link, short link or
/// app share text), in display order. The toolbox and the TV's link player
/// show the same list (docs/ui/TASKS.md §7, U.15e → U.12a).
List<LiveSite> linkPlatforms(SiteRegistry registry) => [
  for (final site in registry.sites)
    if (site is LiveSiteLinks && site.id != SiteIds.iptv) site,
];

/// "支持解析列表 · 共 N 个平台" (docs/ui/compare/U.12a c4): a card of its
/// own, folded by default; unfolded, a line on what can be pasted and a
/// labelled logo for each platform of [linkPlatforms] (3.x showed a fixed
/// text of seventy lines that no longer matched the platforms).
class SupportedPlatformsCard extends ConsumerWidget {
  /// Creates the card.
  const new({this.initiallyExpanded = false, super.key});

  /// Whether it starts unfolded.
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final sites = linkPlatforms(ref.watch(sitesProvider));
    const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)));
    return Material(
      color: colors.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('toolbox-supported'),
        initiallyExpanded: initiallyExpanded,
        shape: shape,
        collapsedShape: shape,
        minTileHeight: 64,
        leading: Icon(AppIcons.infoLine, color: colors.primary),
        title: Text(i18n('toolbox_support_list'), style: context.textStyles.t15),
        subtitle: Text(
          i18n('toolbox_support_count', args: {'count': '${sites.length}'}),
          style: context.textStyles.t13.copyWith(color: colors.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n('toolbox_support_hint'), style: context.textStyles.t13.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final site in sites)
                Chip(
                  key: ValueKey('toolbox-platform-${site.id}'),
                  avatar: PlatformLogo(site.id, size: 18),
                  label: Text(i18nOr('site_${site.id}', site.name)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
