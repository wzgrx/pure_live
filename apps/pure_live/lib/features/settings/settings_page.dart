import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_section_view.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// From this width (of the page, not the screen) the overview and the open
/// page sit side by side (U.6a c9, c10).
const double settingsTwoPaneBreakpoint = 840;

/// The width of the overview in the two-pane layout.
const double settingsOverviewWidth = 360;

/// Settings (3.x `lib/modules/settings/settings_page.dart`; U.6a): the
/// overview of five groups, search, and the pages it opens. Below 840 the
/// overview is a page of its own and a row opens its page; from 840 the
/// page opens beside it, and pages it opens stay in that pane.
///
/// Routes: `RoutePath.kSettings`; the arguments may name a page
/// (`SettingsSection.name`, e.g. `'network'`) to open it directly.
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
  final _searchFocus = FocusNode();
  final _content = GlobalKey<NavigatorState>();
  late final _contentObserver = _ContentObserver(_contentChanged);
  late SettingsSection? _open = switch (SettingsSection.byName(widget.route.arguments)) {
    final SettingsSection section when section.route == null => section,
    _ => null,
  };
  String _query = '';
  String? _highlight;
  int _shown = 0;
  bool _contentCanPop = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // The exit countdown follows the settings (the app attaches it at start
    // too once wired, see AutoExitTimer).
    AutoExitTimer.instance.attach(ref.read(storeProvider).settings);
    _search.addListener(_searchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _searchChanged() {
    final text = _search.text.trim();
    if (text == _query) return;
    _debounce?.cancel();
    // Filtering waits for a pause in typing (U.6a, performance); clearing
    // shows the overview at once.
    if (text.isEmpty) {
      setState(() => _query = '');
    } else {
      _debounce = Timer(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _query = _search.text.trim());
      });
    }
  }

  void _contentChanged() {
    final canPop = _content.currentState?.canPop() ?? false;
    if (canPop != _contentCanPop && mounted) setState(() => _contentCanPop = canPop);
  }

  void _openSection(SettingsSection section) {
    if (section.route case final route?) {
      unawaited(AppNavigator.toNamed<void>(route));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _open = section;
      _highlight = null;
      _shown++;
      _contentCanPop = false;
    });
  }

  /// A search result that opens a page: its page, the row highlighted.
  void _reveal(SettingsEntry entry) {
    FocusScope.of(context).unfocus();
    setState(() {
      _open = entry.section;
      _highlight = entry.subpage == null ? entry.id : null;
      _shown++;
      _contentCanPop = false;
    });
    if (entry.subpage case final subpage?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = _content.currentState;
        if (navigator == null || !navigator.mounted) return;
        unawaited(openSettingsSubpage(navigator.context, subpage, highlight: entry.id));
      });
    }
  }

  void _closeSection() => setState(() {
    _open = null;
    _highlight = null;
    _contentCanPop = false;
  });

  Widget _contentNavigator(SettingsSection section, {required bool twoPane}) => HeroControllerScope.none(
    child: Navigator(
      key: _content,
      observers: [_contentObserver],
      pages: [
        MaterialPage<void>(
          key: ValueKey('settings-content-${section.name}-$_shown'),
          child: SettingsSectionPage(section: section, highlight: _highlight, onBack: twoPane ? null : _closeSection),
        ),
      ],
      onDidRemovePage: (_) {},
    ),
  );

  Widget _overviewBody({required bool twoPane, required SettingsSection? selected}) {
    final env = SettingsEnv(platform: defaultTargetPlatform);
    return _query.isEmpty
        ? _Overview(selected: selected, onOpen: _openSection, twoPane: twoPane)
        : SettingsReveal(
            reveal: _reveal,
            child: _SearchResults(query: _query, env: env, twoPane: twoPane),
          );
  }

  Widget _searchField() => SettingsSearchField(
    controller: _search,
    focusNode: _searchFocus,
    hint: i18n('settings_search_hint'),
    clearTooltip: i18n('clear'),
    fieldKey: const ValueKey('settings-search'),
    clearKey: const ValueKey('settings-search-clear'),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoPane = constraints.maxWidth >= settingsTwoPaneBreakpoint;
      final Widget page;
      if (twoPane) {
        final section = _open ?? SettingsSection.appearance;
        final short = MediaQuery.sizeOf(context).height < 480;
        page = Scaffold(
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: settingsOverviewWidth,
                  child: Column(
                    children: [
                      SizedBox(
                        height: short ? 48 : kToolbarHeight,
                        child: Row(
                          children: [
                            if (Navigator.of(context).canPop()) const BackButton() else const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                i18n('settings_title'),
                                textAlign: TextAlign.center,
                                style: context.textStyles.t20.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 4), child: _searchField()),
                      Expanded(child: _overviewBody(twoPane: true, selected: section)),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: SettingsPane(child: _contentNavigator(section, twoPane: true))),
              ],
            ),
          ),
        );
      } else if (_open case final section?) {
        page = _contentNavigator(section, twoPane: false);
      } else {
        page = Scaffold(
          appBar: settingsAppBar(context, title: i18n('settings_title')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _searchField()),
              ),
              Expanded(child: _overviewBody(twoPane: false, selected: null)),
            ],
          ),
        );
      }
      return PopScope(
        canPop: !_contentCanPop && (twoPane || _open == null),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_contentCanPop) {
            _content.currentState?.maybePop();
          } else if (!twoPane && _open != null) {
            _closeSection();
          }
        },
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyF, control: true): _FindIntent(),
            SingleActivator(LogicalKeyboardKey.keyF, meta: true): _FindIntent(),
            SingleActivator(LogicalKeyboardKey.escape): _ClearSearchIntent(),
          },
          child: Actions(
            actions: {
              _FindIntent: CallbackAction<_FindIntent>(
                onInvoke: (_) {
                  if (!twoPane && _open != null) _closeSection();
                  _searchFocus.requestFocus();
                  return null;
                },
              ),
              _ClearSearchIntent: _ClearSearchAction(_search),
            },
            child: page,
          ),
        ),
      );
    },
  );
}

class _FindIntent extends Intent {
  const new();
}

class _ClearSearchIntent extends Intent {
  const new();
}

/// Esc clears the search; with nothing typed it is not handled, so Esc
/// keeps going back.
class _ClearSearchAction extends Action<_ClearSearchIntent> {
  new(this.search);

  final TextEditingController search;

  @override
  bool isEnabled(_ClearSearchIntent intent) => search.text.isNotEmpty;

  @override
  Object? invoke(_ClearSearchIntent intent) {
    search.clear();
    return null;
  }
}

class _ContentObserver extends NavigatorObserver {
  new(this.changed);

  final VoidCallback changed;

  void _later() => WidgetsBinding.instance.addPostFrameCallback((_) => changed());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _later();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _later();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _later();
}

/// The overview: five groups of pages (U.6a c2).
class _Overview extends StatelessWidget {
  const new({required this.selected, required this.onOpen, required this.twoPane});

  final SettingsSection? selected;
  final ValueChanged<SettingsSection> onOpen;
  final bool twoPane;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('settings-overview'),
      physics: const PureLiveScrollPhysics(),
      padding: EdgeInsets.fromLTRB(twoPane ? 12 : 16, 0, twoPane ? 12 : 16, 32),
      children: [
        for (final (index, area) in SettingsArea.values.indexed)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SettingsGroup(
                first: index == 0,
                title: i18n(area.titleKey),
                children: [
                  for (final section in SettingsSection.values)
                    if (section.area == area)
                      SettingsLinkRow(
                        key: ValueKey('settings-section-${section.name}'),
                        icon: section.icon,
                        leading: section.icon == null
                            ? DanmakuIcon(DanmakuIconKind.settings, size: 24, color: colors.primary)
                            : null,
                        title: i18n(section.titleKey),
                        subtitle: i18n(section.descriptionKey),
                        selected: twoPane && section == selected,
                        onTap: () => onOpen(section),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Search results: the rows themselves, under "页面 › 分组" (U.6a c8).
class _SearchResults extends StatelessWidget {
  const new({required this.query, required this.env, required this.twoPane});

  final String query;
  final SettingsEnv env;
  final bool twoPane;

  @override
  Widget build(BuildContext context) {
    final found = searchSettings(settingsCatalog.where((entry) => entry.when(env)), query);
    if (found.isEmpty) {
      return AppStatusView(
        key: const ValueKey('settings-search-empty'),
        type: AppStatusType.empty,
        icon: AppIcons.search,
        title: i18n('settings_search_empty'),
        subtitle: i18n('settings_search_empty_hint'),
      );
    }
    final byCrumb = <String, List<SettingsEntry>>{};
    for (final entry in found) {
      byCrumb.putIfAbsent(entry.crumb, () => []).add(entry);
    }
    return SettingsHighlight(
      words: searchWords(query),
      child: ListView(
        key: const ValueKey('settings-search-results'),
        physics: const PureLiveScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(twoPane ? 12 : 16, 0, twoPane ? 12 : 16, 32),
        children: [
          for (final (index, MapEntry(key: crumb, value: entries)) in byCrumb.entries.indexed)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SettingsGroup(
                  first: index == 0,
                  title: crumb,
                  children: [for (final entry in entries) entry.build(context, entry)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
