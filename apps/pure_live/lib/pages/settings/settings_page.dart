import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/settings/settings_catalog.dart';
import 'package:pure_live/pages/settings/settings_dialogs.dart';
import 'package:pure_live/pages/settings/settings_editors.dart';
import 'package:pure_live/pages/settings/settings_model.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// Wider than this shows the sections beside their content.
const double settingsTwoPaneBreakpoint = 840;

/// Settings (3.x `lib/modules/settings`): ten sections with search.
///
/// Routes: `RoutePath.kSettings`; the arguments may name a section
/// (`SettingsSection.name`, e.g. `'danmaku'`) to open it directly.
class SettingsPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _search = TextEditingController();
  late SettingsSection _selected = _initialSection ?? SettingsSection.appearance;

  SettingsSection? get _initialSection => switch (widget.route.arguments) {
    final String name => SettingsSection.values.asNameMap()[name],
    final SettingsSection section => section,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    // The exit countdown follows the settings (the app attaches it at start
    // too once wired, see AutoExitTimer).
    AutoExitTimer.instance.attach(ref.read(storeProvider).settings);
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final env = SettingsEnv(platform: defaultTargetPlatform, wide: width > 680);
    final twoPane = width >= settingsTwoPaneBreakpoint;
    final query = _search.text.trim();
    final searchField = _SearchField(controller: _search);
    final initial = _initialSection;

    if (!twoPane && initial != null && query.isEmpty) {
      return SettingsSectionPage(section: initial);
    }

    final Widget body;
    if (query.isNotEmpty) {
      body = _SearchResults(query: query, env: env);
    } else if (twoPane) {
      body = SettingsSectionView(key: ValueKey(_selected), section: _selected, env: env, showHeader: true);
    } else {
      body = _SectionList(env: env, onOpen: (section) => _open(context, section));
    }

    return Scaffold(
      appBar: AppBar(title: Text(i18n('settings_title'))),
      body: twoPane
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: Column(
                    children: [
                      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: searchField),
                      Expanded(
                        child: _SectionList(
                          env: env,
                          selected: query.isEmpty ? _selected : null,
                          onOpen: (section) => setState(() {
                            _selected = section;
                            _search.clear();
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : Column(
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: searchField),
                Expanded(child: body),
              ],
            ),
    );
  }

  void _open(BuildContext context, SettingsSection section) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsSectionPage(section: section)));
  }
}

class _SearchField extends StatelessWidget {
  const new({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
    child: SearchBar(
      key: const ValueKey('settings-search'),
      controller: controller,
      hintText: i18n('settings_search_hint'),
      elevation: const WidgetStatePropertyAll(0),
      constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
      leading: const Icon(Icons.search_rounded),
      trailing: [
        if (controller.text.isNotEmpty)
          IconButton(
            key: const ValueKey('settings-search-clear'),
            tooltip: i18n('clear'),
            icon: const Icon(Icons.close_rounded),
            onPressed: controller.clear,
          ),
      ],
    ),
  );
}

/// Rebuilds when any setting changes (section badges, reset actions).
class _SettingsChanges extends ConsumerStatefulWidget {
  const new({required this.builder});

  final WidgetBuilder builder;

  @override
  ConsumerState<_SettingsChanges> createState() => _SettingsChangesState();
}

class _SettingsChangesState extends ConsumerState<_SettingsChanges> {
  StreamSubscription<Setting<Object>>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = ref.read(storeProvider).settings.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class _SectionList extends ConsumerWidget {
  const new({required this.env, required this.onOpen, this.selected});

  final SettingsEnv env;
  final ValueChanged<SettingsSection> onOpen;
  final SettingsSection? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(storeProvider).settings;
    final colors = Theme.of(context).colorScheme;
    return _SettingsChanges(
      builder: (context) => ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          context.buildModernCard([
            for (final section in SettingsSection.values)
              if (groupsOf(settingsCatalog, section, env).isNotEmpty)
                CardTile(
                  key: ValueKey('settings-section-${section.name}'),
                  child: Builder(
                    builder: (context) {
                      final changed = changedSettings(
                        store,
                        settingsCatalog.where((entry) => entry.section == section && entry.when(env)),
                      ).length;
                      final isSelected = section == selected;
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: colors.primaryContainer.withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(section.icon, color: colors.primary, size: 22),
                        ),
                        title: Text(
                          i18n(section.titleKey),
                          style: context.textStyles.t15.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          i18n(section.descriptionKey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.t12.copyWith(color: Theme.of(context).hintColor),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (changed > 0)
                              Tooltip(
                                message: i18n('settings_changed_count', args: {'count': '$changed'}),
                                child: Badge(
                                  label: Text('$changed'),
                                  backgroundColor: colors.secondaryContainer,
                                  textColor: colors.onSecondaryContainer,
                                ),
                              ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Theme.of(context).hintColor.withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                        onTap: () => onOpen(section),
                      );
                    },
                  ),
                ),
          ]),
        ],
      ),
    );
  }
}

/// One section on its own page (phones).
class SettingsSectionPage extends StatelessWidget {
  /// Creates the page.
  const new({required this.section, super.key});

  /// The section shown.
  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final env = SettingsEnv(platform: defaultTargetPlatform, wide: width > 680);
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n(section.titleKey)),
        actions: [_ResetSectionButton(section: section, env: env)],
      ),
      body: SettingsSectionView(section: section, env: env),
    );
  }
}

/// "Restore this section's defaults", shown when something in it changed.
class _ResetSectionButton extends ConsumerWidget {
  const new({required this.section, required this.env});

  final SettingsSection section;
  final SettingsEnv env;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    return _SettingsChanges(
      builder: (context) {
        final changed = changedSettings(
          settings,
          settingsCatalog.where((entry) => entry.section == section && entry.when(env)),
        );
        if (changed.isEmpty) return const SizedBox.shrink();
        return IconButton(
          key: const ValueKey('settings-section-reset'),
          tooltip: i18n('settings_reset_section'),
          icon: const Icon(Icons.restart_alt_rounded),
          onPressed: () async {
            final confirmed = await showConfirmDialog(
              context: context,
              title: i18n('settings_reset_section'),
              message: i18n(
                'settings_reset_section_confirm',
                args: {'section': i18n(section.titleKey), 'count': '${changed.length}'},
              ),
              confirmLabel: i18n('reset'),
            );
            if (!confirmed) return;
            for (final setting in changed) {
              await settings.reset(setting);
            }
            AppNavigator.toast(i18n('settings_reset_done'));
          },
        );
      },
    );
  }
}

/// The groups of a section: a title and a card of rows each.
class SettingsSectionView extends StatelessWidget {
  /// Creates the view.
  const new({required this.section, required this.env, this.showHeader = false, super.key});

  /// The section shown.
  final SettingsSection section;

  /// Where the page runs.
  final SettingsEnv env;

  /// Shows the section's title, summary and reset action (two-pane layout,
  /// which has no section app bar).
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final groups = groupsOf(settingsCatalog, section, env);
    final theme = Theme.of(context);
    return ListView(
      key: ValueKey('settings-section-view-${section.name}'),
      physics: const PureLiveScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (showHeader)
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 0, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i18n(section.titleKey), style: theme.textTheme.headlineSmall),
                          const SizedBox(height: 4),
                          Text(i18n(section.descriptionKey), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    _ResetSectionButton(section: section, env: env),
                  ],
                ),
              ),
            ),
          ),
        for (final (index, (group, entries)) in groups.indexed) ...[
          if (index > 0) const SizedBox(height: 20),
          context.buildGroupTitle(i18n(group)),
          context.buildModernCard([for (final entry in entries) CardTile(child: entry.build(context, entry))]),
        ],
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const new({required this.query, required this.env});

  final String query;
  final SettingsEnv env;

  @override
  Widget build(BuildContext context) {
    final found = searchSettings(settingsCatalog.where((entry) => entry.when(env)), query);
    if (found.isEmpty) {
      return AppStatusView(
        key: const ValueKey('settings-search-empty'),
        type: AppStatusType.empty,
        title: i18n('settings_search_empty'),
        subtitle: i18n('settings_search_empty_hint'),
      );
    }
    final bySection = <SettingsSection, List<SettingsEntry>>{};
    for (final entry in found) {
      bySection.putIfAbsent(entry.section, () => []).add(entry);
    }
    return ListView(
      key: const ValueKey('settings-search-results'),
      physics: const PureLiveScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final (index, MapEntry(key: section, value: entries)) in bySection.entries.indexed) ...[
          if (index > 0) const SizedBox(height: 20),
          context.buildGroupTitle(i18n(section.titleKey)),
          context.buildModernCard([for (final entry in entries) CardTile(child: entry.build(context, entry))]),
        ],
      ],
    );
  }
}
