import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The platform list after showing ([show]) or hiding platform [id] in
/// [visible]; null when hiding the last one (3.x kept at least one).
List<String>? toggleHotArea(List<String> visible, String id, {required bool show}) {
  if (show) return visible.contains(id) ? visible : [...visible, id];
  if (!visible.contains(id)) return visible;
  if (visible.length <= 1) return null;
  return [
    for (final value in visible)
      if (value != id) value,
  ];
}

/// [visible] with the platform at [oldIndex] moved to [newIndex] (its
/// index once moved, as [ReorderableListView.onReorderItem] gives it).
List<String> reorderHotAreas(List<String> visible, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= visible.length || newIndex < 0) return visible;
  final result = [...visible];
  final moved = result.removeAt(oldIndex);
  result.insert(newIndex.clamp(0, result.length), moved);
  return result;
}

/// The preferred platform once the list is [visible]: kept when still
/// shown, else the first shown (3.x).
String preferredAfter(List<String> visible, String preferred) =>
    visible.isEmpty || visible.contains(preferred) ? preferred : visible.first;

/// Platforms shown on the areas and popular pages, and their order (3.x
/// `lib/modules/hot_areas`, "platform display").
///
/// Route: `RoutePath.kSettingsHotAreas`.
///
/// The shown platforms come first and are dragged into order; the hidden
/// ones are listed below them (new: 3.x mixed both in one list). A count
/// and "restore default" sit above the list (new).
class HotAreasPage extends ConsumerWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  Future<void> _save(WidgetRef ref, List<String> visible) async {
    final settings = ref.read(storeProvider).settings;
    await settings.set(Settings.hotAreasList, visible);
    final preferred = settings.get(Settings.preferPlatform);
    final next = preferredAfter(visible, preferred);
    if (next != preferred) await settings.set(Settings.preferPlatform, next);
  }

  Future<void> _toggle(WidgetRef ref, List<String> visible, String id, bool show) async {
    final next = toggleHotArea(visible, id, show: show);
    if (next == null) {
      AppNavigator.toast(i18n('at_least_one_platform_required'));
      return;
    }
    await _save(ref, next);
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('hot_areas_reset')),
        content: Text(i18n('hot_areas_reset_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(i18n('confirm'))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _save(ref, ref.read(sitesProvider).availableIds(Settings.hotAreasList.defaultValue));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sites = ref.read(sitesProvider);
    final visible = sites.availableIds(watchSetting(ref, Settings.hotAreasList));
    final hidden = [
      for (final id in sites.ids)
        if (!visible.contains(id)) id,
    ];
    String name(String id) => platformName(id, fallback: sites.maybeOf(id)?.name);

    Widget row(String id, {required bool shown, int? index}) {
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            key: ValueKey('platform-switch-$id'),
            value: shown,
            onChanged: (value) => _toggle(ref, visible, id, value).ignore(),
          ),
          if (shown && index != null && visible.length > 1) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: i18n('drag_to_sort_tip'),
              child: ReorderableDragStartListener(
                key: ValueKey('platform-drag-$id'),
                index: index,
                child: const SizedBox.square(
                  dimension: kMinInteractiveDimension,
                  child: Center(child: Icon(Icons.drag_handle_rounded, size: 20)),
                ),
              ),
            ),
          ],
        ],
      );
      return Material(
        key: ValueKey(id),
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final title = Text(
              name(id),
              key: ValueKey('platform-title-$id'),
              style: context.textStyles.t15.copyWith(fontWeight: FontWeight.w600),
            );
            // Narrow screens and large text put the controls under the name (3.x).
            final stack = constraints.maxWidth < 360 || MediaQuery.textScalerOf(context).scale(1) > 1.5;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: PlatformLogo(id, size: 24),
              title: stack
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 6), controls],
                    )
                  : title,
              trailing: stack ? null : controls,
            );
          },
        ),
      );
    }

    BoxDecoration group() => BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05), width: 0.5),
    );

    return Scaffold(
      appBar: AppBar(title: Text(i18n('platform_display'))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Remix.information_line, size: 18, color: theme.colorScheme.primary.withValues(alpha: 0.8)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${i18n('drag_to_sort_tip')}\n${i18n('at_least_one_platform_required')}',
                    style: context.textStyles.t13.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: context.buildGroupTitle(
                  i18n('hot_areas_visible_count', args: {'count': '${visible.length}', 'total': '${sites.ids.length}'}),
                ),
              ),
              TextButton(
                key: const ValueKey('hot-areas-reset'),
                onPressed: () => _reset(context, ref).ignore(),
                child: Text(i18n('hot_areas_reset')),
              ),
            ],
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: group(),
            child: ReorderableListView.builder(
              key: const ValueKey('hot-areas-visible'),
              buildDefaultDragHandles: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visible.length,
              onReorderItem: (oldIndex, newIndex) => _save(ref, reorderHotAreas(visible, oldIndex, newIndex)).ignore(),
              itemBuilder: (context, index) => row(visible[index], shown: true, index: index),
            ),
          ),
          if (hidden.isNotEmpty) ...[
            const SizedBox(height: 16),
            context.buildGroupTitle(i18n('hot_areas_hidden_title')),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: group(),
              child: Column(children: [for (final id in hidden) row(id, shown: false)]),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
