import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The platforms of this build in the user's order: the stored ones first,
/// then the rest; with whether each one shows.
List<(String, bool)> platformRows(List<String> stored) => [
  for (final id in stored)
    if (platformOrder.contains(id)) (id, true),
  for (final id in platformOrder)
    if (!stored.contains(id)) (id, false),
];

/// The list to store for [rows]: the shown ones in order, then the ids this
/// build no longer has (retired platforms keep their slot, F-DSC-03).
List<String> storedPlatforms(List<(String, bool)> rows, List<String> previous) => [
  for (final (id, shown) in rows)
    if (shown) id,
  for (final id in previous)
    if (!platformOrder.contains(id)) id,
];

/// Appends platforms this build added since the last run to the user's list
/// (F-DSC-03: new platforms join at the end; a platform the user hid stays
/// hidden). The first run only records what is known.
Future<void> appendNewPlatforms(LiveStore store) async {
  const key = 'catalog.knownPlatforms';
  final known = (await store.meta.get(key))?.split(',').where((id) => id.isNotEmpty).toSet();
  if (known != null) {
    final added = [
      for (final id in platformOrder)
        if (!known.contains(id)) id,
    ];
    final current = store.settings.get(Settings.catalogPlatforms);
    final missing = added.where((id) => !current.contains(id)).toList();
    if (missing.isNotEmpty) await store.settings.set(Settings.catalogPlatforms, [...current, ...missing]);
  }
  await store.meta.set(key, platformOrder.join(','));
}

/// 首页平台 (F-DSC-03): which platforms discover, search and accounts show,
/// their order and the one discover opens on.
class PlatformsPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PlatformsPage> createState() => _PlatformsPageState();
}

class _PlatformsPageState extends ConsumerState<PlatformsPage> {
  late final List<(String, bool)> _rows = platformRows(ref.read(catalogPlatformsSetting));

  void _save() {
    final previous = ref.read(catalogPlatformsSetting);
    unawaited(ref.read(catalogPlatformsSetting.notifier).set(storedPlatforms(_rows, previous)));
  }

  @override
  Widget build(BuildContext context) {
    final preferred = ref.watch(catalogPreferredSetting);
    final shown = _rows.where((row) => row.$2).length;
    return Scaffold(
      appBar: PageAppBar(title: Text(t.settings.accounts.platforms)),
      body: PageBody(
        child: ReorderableListView.builder(
          header: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, Space.s2),
            child: Text(t.settings.platformsHint),
          ),
          itemCount: _rows.length,
          onReorderItem: (from, to) {
            setState(() => _rows.insert(to, _rows.removeAt(from)));
            _save();
          },
          itemBuilder: (context, index) {
            final (id, on) = _rows[index];
            return ListTile(
              key: ValueKey(id),
              leading: Checkbox(
                value: on,
                // At least one platform stays.
                onChanged: on && shown == 1
                    ? null
                    : (value) {
                        setState(() => _rows[index] = (id, value ?? false));
                        _save();
                      },
              ),
              title: Row(
                children: [
                  PlatformLogo(platformId: id, size: Sizes.logoMedium),
                  const SizedBox(width: Space.s2),
                  Text(platformNames[id] ?? id),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: preferred == id ? t.settings.discoverDefault : t.settings.setDiscoverDefault,
                    isSelected: preferred == id,
                    icon: const Icon(Icons.star_border),
                    selectedIcon: const Icon(Icons.star),
                    onPressed: on ? () => unawaited(ref.read(catalogPreferredSetting.notifier).set(id)) : null,
                  ),
                  ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
