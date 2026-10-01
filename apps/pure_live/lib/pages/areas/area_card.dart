import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/areas/area_artwork.dart';
import 'package:pure_live/pages/areas/areas_common.dart';

/// An area tile (3.x `AreaCard`): the square picture, the name and the
/// parent category; CC's official entries say they open in the browser.
/// Followed areas carry a heart; a long press (or right click) follows or
/// unfollows (new).
class AreaCard extends ConsumerWidget {
  /// Shows [area].
  const new({required this.area, this.showPlatform = false, super.key});

  /// The area.
  final LiveArea area;

  /// Shows the platform's logo in the corner (the "all" tab of followed
  /// areas mixes platforms).
  final bool showPlatform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pictures = ref.watch(areaPicturesProvider);
    final followed = ref.watch(followedAreaKeysProvider).value?.contains(area.identityKey) ?? false;
    final official = CcApi.isOfficialEntry(area);
    final typeName = area.typeName.trim();
    final subtitle = official ? i18n('open_in_system_browser') : (typeName.isEmpty ? i18n('no_data') : typeName);
    final name = areaDisplayName(area);
    return Semantics(
      button: true,
      label: followed ? '$name, ${i18n('followed')}' : name,
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openArea(ref, area),
          onLongPress: official ? null : () => toggleAreaFollow(context, ref, area).ignore(),
          onSecondaryTap: official ? null : () => toggleAreaFollow(context, ref, area).ignore(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: ColoredBox(
                        color: Colors.white,
                        child: AreaArtwork(url: pictures.pictureFor(area)),
                      ),
                    ),
                    if (showPlatform) Positioned(left: 6, top: 6, child: PlatformLogo(area.platform, size: 18)),
                    if (followed)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(
                              Icons.favorite_rounded,
                              key: const ValueKey('area-card-followed'),
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                title: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.t12.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.t11.copyWith(fontWeight: FontWeight.w500),
                ),
                trailing: official ? const Icon(Icons.open_in_new_rounded, size: 16) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grid of area tiles (3.x `buildFlattenAreasView`), 3 to 9 columns by
/// width, spacing from the theme settings.
class AreaGrid extends ConsumerWidget {
  /// Shows [areas].
  const new({required this.areas, this.controller, this.showPlatform = false, super.key});

  /// The areas.
  final List<LiveArea> areas;

  /// The scroll position.
  final ScrollController? controller;

  /// Passed to [AreaCard.showPlatform].
  final bool showPlatform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = gridSpacing(ref);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = areaGridColumns(width);
        final itemWidth = (width - 12 - spacing.cross * (columns - 1)) / columns;
        return GridView.builder(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(parent: PureLiveScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 80),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing.cross,
            mainAxisSpacing: spacing.main,
            mainAxisExtent: areaCardExtent(context, itemWidth),
          ),
          itemCount: areas.length,
          itemBuilder: (context, index) {
            final area = areas[index];
            return AreaCard(
              key: ValueKey(area.identityKey ?? '${area.platform}:${area.areaType}:${area.areaId}:$index'),
              area: area,
              showPlatform: showPlatform,
            );
          },
        );
      },
    );
  }
}
