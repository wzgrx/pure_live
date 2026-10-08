import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/area_artwork.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// What an area card says under its name (docs/A-界面设计/A09-浏览界面/A09.4-分区 c3, U.4f c3).
enum AreaCaption {
  /// The name only: the category tab above says the rest.
  nameOnly,

  /// The category under the name (Douyin's single grid, a single platform of
  /// the followed areas).
  category,

  /// "platform · category" (the followed areas' "all").
  platformAndCategory,
}

/// An area tile (3.x `AreaCard`): the square picture and the name; the line
/// under it as [caption] says; CC's official entries say they open in the
/// browser. A followed area carries a heart on its picture (display only);
/// a long press or right click opens the area dialog (U.4d c6, X3).
class AreaCard extends ConsumerStatefulWidget {
  /// Shows [area].
  const new({required this.area, this.caption = AreaCaption.nameOnly, super.key});

  /// The area.
  final LiveArea area;

  /// The line under the name.
  final AreaCaption caption;

  @override
  ConsumerState<AreaCard> createState() => _AreaCardState();
}

class _AreaCardState extends ConsumerState<AreaCard> {
  void _menu() => showAreaDialog(context, ref, widget.area).ignore();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final area = widget.area;
    final pictures = ref.watch(areaPicturesProvider);
    final followed = ref.watch(followedAreaKeysProvider).value?.contains(area.identityKey) ?? false;
    final official = CcApi.isOfficialEntry(area);
    final typeName = area.typeName.trim();
    final category = typeName.isEmpty ? i18n('no_data') : typeName;
    final subtitle = official
        ? i18n('open_in_system_browser')
        : switch (widget.caption) {
            AreaCaption.nameOnly => null,
            AreaCaption.category => category,
            AreaCaption.platformAndCategory => '${platformName(area.platform)} · $category',
          };
    final name = areaDisplayName(area);
    final styles = context.textStyles;
    return Semantics(
      button: true,
      label: followed ? '$name, ${i18n('followed')}' : name,
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => openArea(ref, area),
          onLongPress: official ? null : _menu,
          onSecondaryTap: official ? null : _menu,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: ColoredBox(
                        color: scheme.surfaceContainerLowest,
                        child: AreaArtwork(url: pictures.pictureFor(area)),
                      ),
                    ),
                    if (followed)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              AppIcons.areaFollowedMark,
                              key: const ValueKey('area-card-followed'),
                              size: 14,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: styles.t12.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                key: const ValueKey('area-card-caption'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: styles.t12.copyWith(fontWeight: FontWeight.w400, height: 1.3),
                              ),
                          ],
                        ),
                      ),
                      if (official) const Icon(AppIcons.openExternal, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Static placeholder cards of an area grid while it loads (U.4d c8).
class AreaGridSkeleton extends ConsumerWidget {
  /// Creates the placeholder.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = watchSetting(ref, Settings.crossAxisSpacing);
    final mainSpacing = watchSetting(ref, Settings.mainAxisSpacing);
    final block = Theme.of(context).colorScheme.surfaceContainerHigh;
    final card = Theme.of(context).colorScheme.surfaceContainerLow;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = GridColumns.areas(
          width: constraints.maxWidth,
          windowWidth: MediaQuery.sizeOf(context).width,
          spacing: spacing,
        );
        final itemWidth = GridColumns.itemWidth(width: constraints.maxWidth, columns: columns, spacing: spacing);
        final extent = areaCardExtent(context, itemWidth, twoLines: false);
        final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 800.0;
        final rows = (height / (extent + mainSpacing)).ceil().clamp(1, 12);
        return Semantics(
          key: const ValueKey('area-grid-skeleton'),
          label: i18n('refresh_loading'),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(6),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: mainSpacing,
              mainAxisExtent: extent,
            ),
            itemCount: rows * columns,
            itemBuilder: (context, _) => DecoratedBox(
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(15)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Center(
                        child: FractionallySizedBox(
                          widthFactor: 0.6,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A grid of area tiles (3.x `buildFlattenAreasView`): the columns of UI_PLAN
/// §5.3 with the area card's smallest widths (110 / 130 / 150, 3–10
/// columns, U.4d c5), fixed row heights, spacing from the settings.
class AreaGrid extends ConsumerWidget {
  /// Shows [areas].
  const new({
    required this.areas,
    this.controller,
    this.caption = AreaCaption.nameOnly,
    this.bottomPadding = 80,
    this.physics = const AlwaysScrollableScrollPhysics(parent: PureLiveScrollPhysics()),
    super.key,
  });

  /// The areas.
  final List<LiveArea> areas;

  /// The scroll position.
  final ScrollController? controller;

  /// The line under the names.
  final AreaCaption caption;

  /// Room under the last row (the floating "关注分区" button).
  final double bottomPadding;

  /// The grid's physics (the pull-to-refresh view's on phones).
  final ScrollPhysics physics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = gridSpacing(ref);
    final twoLines = caption != AreaCaption.nameOnly || areas.any(CcApi.isOfficialEntry);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = GridColumns.areas(
          width: width,
          windowWidth: MediaQuery.sizeOf(context).width,
          spacing: spacing.cross,
        );
        final itemWidth = GridColumns.itemWidth(width: width, columns: columns, spacing: spacing.cross);
        return GridView.builder(
          key: const ValueKey('area-grid'),
          controller: controller,
          physics: physics,
          padding: EdgeInsets.fromLTRB(6, 6, 6, bottomPadding),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing.cross,
            mainAxisSpacing: spacing.main,
            mainAxisExtent: areaCardExtent(context, itemWidth, twoLines: twoLines),
          ),
          itemCount: areas.length,
          itemBuilder: (context, index) {
            final area = areas[index];
            return AreaCard(
              key: ValueKey(area.identityKey ?? '${area.platform}:${area.areaType}:${area.areaId}:$index'),
              area: area,
              caption: caption,
            );
          },
        );
      },
    );
  }
}
