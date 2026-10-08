import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/search/search_capability.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Platforms outside mainland China: without a proxy their requests usually
/// fail there (M13.16: "all" listed nine of them as failed on every search).
const Set<String> overseasPlatforms = {
  SiteIds.twitch,
  SiteIds.soop,
  SiteIds.picarto,
  SiteIds.twitcasting,
  SiteIds.niconico,
  SiteIds.showroom,
  SiteIds.chzzk,
  SiteIds.liveMe,
  SiteIds.tiktok,
  SiteIds.youtube,
  SiteIds.bigo,
  SiteIds.pandaLive,
  SiteIds.fc2Live,
  SiteIds.steamBroadcast,
  SiteIds.seventeenLive,
};

/// The platforms the user leaves out of the search's "all" (M13.16), kept
/// in the meta store as a JSON list of ids, like the search history.
final class SearchScopeStore {
  /// A store over [_meta].
  new(this._meta);

  final MetaStore _meta;

  /// The record key.
  static const String key = 'search.allExcluded';

  /// The stored ids; none when nothing (or nothing readable) is stored.
  Future<Set<String>> load() async {
    try {
      final decoded = jsonDecode(await _meta.get(key) ?? '[]');
      return {
        if (decoded is List)
          for (final id in decoded)
            if (id is String && id.trim().isNotEmpty) id.trim().toLowerCase(),
      };
    } on Object {
      return {};
    }
  }

  /// Stores [excluded]; none removes the record.
  Future<void> save(Set<String> excluded) =>
      _meta.set(key, excluded.isEmpty ? null : jsonEncode(excluded.toList()..sort()));
}

/// Opens the search scope panel (docs/A-界面设计/A09-浏览界面/A09.7-搜索 c6, choice X3 A: one
/// panel instead of v4's explanation sheet and choice dialog): what every
/// platform finds, and which of [sites] "all" searches, domestic and
/// overseas apart, with "domestic only" and "select all". It rises from the
/// bottom on narrow pages and stands on the right on wide ones; ✕, Back,
/// Esc, a tap outside and a downward drag close it.
///
/// Completes with the platforms left out of "all" once it closes, starting
/// from [excluded]; at least one platform stays chosen.
Future<Set<String>> showSearchScopePanel(
  BuildContext context, {
  required List<LiveSite> sites,
  required Set<String> excluded,
}) async {
  final choice = ValueNotifier<Set<String>>({
    for (final site in sites)
      if (excluded.contains(site.id)) site.id,
  });
  await showAdaptivePanel<void>(
    context,
    side: MediaQuery.sizeOf(context).width >= 600,
    builder: (_) => SearchScopePanel(sites: sites, choice: choice),
  );
  final result = choice.value;
  choice.dispose();
  return result;
}

/// The content of [showSearchScopePanel]; [choice] holds the platforms left
/// out and changes with every tick.
class SearchScopePanel extends StatelessWidget {
  /// Creates the panel.
  const new({required this.sites, required this.choice, super.key});

  /// The user's platforms, in their order.
  final List<LiveSite> sites;

  /// The platforms left out of "all".
  final ValueNotifier<Set<String>> choice;

  void _set(Set<String> excluded) {
    // Leaving every platform out would search none: keep the last one.
    if (sites.every((site) => excluded.contains(site.id))) return;
    choice.value = excluded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = context.textStyles;
    final domestic = [
      for (final site in sites)
        if (!overseasPlatforms.contains(site.id)) site,
    ];
    final overseas = [
      for (final site in sites)
        if (overseasPlatforms.contains(site.id)) site,
    ];
    return ValueListenableBuilder(
      valueListenable: choice,
      builder: (context, excluded, _) {
        final chosen = sites.where((site) => !excluded.contains(site.id)).length;
        List<Widget> group(String title, List<LiveSite> members) => [
          if (members.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: styles.t13SemiBold.copyWith(color: scheme.primary)),
                  ),
                  Text(
                    i18n(
                      'search_scope_selected',
                      args: {
                        'count': '${members.where((site) => !excluded.contains(site.id)).length}',
                        'total': '${members.length}',
                      },
                    ),
                    style: styles.t12.copyWith(color: scheme.onSurfaceVariant).tabular,
                  ),
                ],
              ),
            ),
          for (final site in members)
            _ScopeRow(
              site: site,
              chosen: !excluded.contains(site.id),
              // The last chosen platform cannot be left out.
              locked: chosen == 1 && !excluded.contains(site.id),
              onChanged: (value) => _set(value ? ({...excluded}..remove(site.id)) : {...excluded, site.id}),
            ),
        ];
        // The panel's frame (U.1d): a line under the header once scrolled.
        return PanelFrame(
          key: const ValueKey('search-scope-panel'),
          expand: false,
          header: PanelHeader(title: i18n('search_scope_title'), closeTooltip: i18n('close')),
          child: ListView(
            shrinkWrap: true,
            physics: const PureLiveScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Text(
                  '${i18n('search_scope_hint')}\n${i18n('search_scope_tags_hint')}',
                  style: styles.t13.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('search-scope-domestic'),
                      onPressed: domestic.isEmpty ? null : () => _set({for (final site in overseas) site.id}),
                      child: Text(i18n('search_scope_domestic_only')),
                    ),
                    OutlinedButton(
                      key: const ValueKey('search-scope-all'),
                      onPressed: () => _set(const {}),
                      child: Text(i18n('search_scope_select_all')),
                    ),
                  ],
                ),
              ),
              ...group(i18n('account_group_domestic'), domestic),
              ...group(i18n('account_group_overseas'), overseas),
            ],
          ),
        );
      },
    );
  }
}

/// One platform of the scope panel: the box, the logo, the name with its
/// "主播" and "网页" tags, and what it finds; a tap anywhere ticks it.
class _ScopeRow extends StatelessWidget {
  const new({required this.site, required this.chosen, required this.locked, required this.onChanged});

  final LiveSite site;
  final bool chosen;
  final bool locked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final capability = SearchCapabilities.of(site.id);
    Widget tag(String text) => Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: styles.t12.copyWith(color: scheme.onSurfaceVariant)),
    );
    final name = platformName(site.id, fallback: site.name);
    return InkWell(
      key: ValueKey('search-scope-${site.id}'),
      onTap: locked ? null : () => onChanged(!chosen),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 20, 4),
          child: Row(
            children: [
              Checkbox(value: chosen, onChanged: locked ? null : (value) => onChanged(value ?? false)),
              const SizedBox(width: 4),
              PlatformLogo(site.id, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(name, style: styles.t14.copyWith(color: scheme.onSurface)),
                        if (capability.anchors) tag(i18n('search_mode_anchors')),
                        if (capability.webSearch) tag(i18n('search_scope_tag_web')),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      searchCoverageShortText(capability),
                      style: styles.t12.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
