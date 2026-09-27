import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/network.dart';
import 'package:pure_live_app/features/discover/discover_refresh.dart';
import 'package:pure_live_app/features/search/search_page.dart';
import 'package:pure_live_app/l10n/strings.dart';

const _destinations = [
  NavDestination(icon: Icons.favorite_border, selectedIcon: Icons.favorite, label: S.follows),
  NavDestination(icon: Icons.explore_outlined, selectedIcon: Icons.explore, label: S.discover),
  NavDestination(icon: Icons.search, selectedIcon: Icons.saved_search, label: S.search),
  NavDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: S.me),
];

/// The four top-level destinations (principles §4.1) in the adaptive shell;
/// in TV mode the collapsed rail that expands on focus (§5.3).
class AppShell extends ConsumerStatefulWidget {
  const new({required this.shell, super.key});

  /// go_router's branch navigator.
  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // Choosing the current destination again returns to its first page.
  void _select(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  /// Ctrl+F (principles §6.2): the search tab with its box focused, from any
  /// page of the shell, focused or not. A page pushed above the shell (a
  /// room) keeps the key.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyF) return false;
    if (!HardwareKeyboard.instance.isControlPressed || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _select(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(searchFocusRequestProvider.notifier).request();
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(networkKindProvider).value == NetworkKind.offline;
    // F-APP-03: coming back after 15 s refreshes the current tab.
    final body = HomeResumeRefresh(
      tab: shell.currentIndex,
      child: offline
          ? Column(
              children: [
                const OfflineBar(),
                Expanded(child: shell),
              ],
            )
          : shell,
    );
    return TvScope.of(context).enabled
        ? TvNavScaffold(destinations: _destinations, selectedIndex: shell.currentIndex, onSelected: _select, body: body)
        : AdaptiveNavScaffold(
            destinations: _destinations,
            selectedIndex: shell.currentIndex,
            onSelected: _select,
            body: body,
          );
  }
}

/// F-NEW-10: says the device is offline, above the pages of the shell.
class OfflineBar extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s2),
          child: Row(
            children: [
              Icon(Icons.wifi_off, size: Sizes.iconDense, color: colors.onErrorContainer),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Text('网络已断开，恢复后列表和播放会重新加载', style: TextStyle(color: colors.onErrorContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
