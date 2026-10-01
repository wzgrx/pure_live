import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
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

/// Asks which of [sites] "all" searches, starting from [excluded] (the ones
/// left out); the new excluded ids, or null when cancelled. Domestic and
/// overseas platforms are grouped, with "domestic only" and "select all"
/// shortcuts; at least one platform stays chosen.
Future<Set<String>?> showSearchScopeDialog(BuildContext context, List<LiveSite> sites, Set<String> excluded) {
  return showDialog<Set<String>>(
    context: context,
    builder: (context) => _ScopeDialog(sites: sites, excluded: excluded),
  );
}

class _ScopeDialog extends StatefulWidget {
  const new({required this.sites, required this.excluded});

  final List<LiveSite> sites;
  final Set<String> excluded;

  @override
  State<_ScopeDialog> createState() => _ScopeDialogState();
}

class _ScopeDialogState extends State<_ScopeDialog> {
  late final Set<String> _excluded = {
    for (final site in widget.sites)
      if (widget.excluded.contains(site.id)) site.id,
  };

  bool get _noneChosen => widget.sites.every((site) => _excluded.contains(site.id));

  Widget _group(BuildContext context, String title, List<LiveSite> sites) {
    if (sites.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final site in sites)
              FilterChip(
                key: ValueKey('search-scope-${site.id}'),
                avatar: PlatformLogo(site.id, size: 16),
                label: Text(platformName(site.id, fallback: site.name)),
                selected: !_excluded.contains(site.id),
                showCheckmark: false,
                onSelected: (chosen) => setState(() => chosen ? _excluded.remove(site.id) : _excluded.add(site.id)),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final domestic = [
      for (final site in widget.sites)
        if (!overseasPlatforms.contains(site.id)) site,
    ];
    final overseas = [
      for (final site in widget.sites)
        if (overseasPlatforms.contains(site.id)) site,
    ];
    return AlertDialog(
      key: const ValueKey('search-scope-dialog'),
      title: Text(i18n('search_scope_title')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                i18n('search_scope_hint'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    key: const ValueKey('search-scope-domestic'),
                    avatar: const Icon(Icons.flag_outlined, size: 16),
                    label: Text(i18n('search_scope_domestic_only')),
                    onPressed: domestic.isEmpty
                        ? null
                        : () => setState(() {
                            _excluded
                              ..clear()
                              ..addAll(overseas.map((site) => site.id));
                          }),
                  ),
                  ActionChip(
                    key: const ValueKey('search-scope-all'),
                    avatar: const Icon(Icons.select_all_rounded, size: 16),
                    label: Text(i18n('search_scope_select_all')),
                    onPressed: () => setState(_excluded.clear),
                  ),
                ],
              ),
              _group(context, i18n('account_group_domestic'), domestic),
              _group(context, i18n('account_group_overseas'), overseas),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
        FilledButton(
          key: const ValueKey('search-scope-save'),
          onPressed: _noneChosen ? null : () => Navigator.of(context).pop(Set<String>.of(_excluded)),
          child: Text(i18n('confirm')),
        ),
      ],
    );
  }
}
