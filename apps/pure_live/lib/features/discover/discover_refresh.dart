import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live_app/core/clock.dart';

/// Counts requests to reload the discover list on screen; the lists of the
/// discover branch listen to it (spec/product.md F-APP-03).
class DiscoverRefresh extends Notifier<int> {
  @override
  int build() => 0;

  /// Asks the visible discover list to load again.
  void request() => state++;
}

/// See [DiscoverRefresh].
final discoverRefreshProvider = NotifierProvider<DiscoverRefresh, int>(DiscoverRefresh.new);

/// Home tab index of discover in the shell.
const discoverTab = 1;

/// F-APP-03: after the app was away at least [awayAtLeast], [delay] after it
/// comes back the current home tab refreshes (3.x home_page.dart:141-160).
/// Discover reloads the list on screen here; the follows refresh has its own
/// resume rule (FollowRefreshNotifier.resumed) because it also feeds live
/// alerts whatever the tab.
class HomeResumeRefresh extends ConsumerStatefulWidget {
  const new({required this.tab, required this.child, super.key});

  /// The current home tab.
  final int tab;

  /// The shell's body.
  final Widget child;

  /// How long the app must be away.
  static const awayAtLeast = Duration(seconds: 15);

  /// Delay after coming back, so the retained list paints first.
  static const delay = Duration(milliseconds: 450);

  @override
  ConsumerState<HomeResumeRefresh> createState() => _HomeResumeRefreshState();
}

class _HomeResumeRefreshState extends ConsumerState<HomeResumeRefresh> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _awayAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _hidden, onResume: _resumed);
  }

  void _hidden() {
    _timer?.cancel();
    _awayAt ??= ref.read(clockProvider)();
  }

  void _resumed() {
    final away = _awayAt;
    _awayAt = null;
    if (away == null || ref.read(clockProvider)().difference(away) < HomeResumeRefresh.awayAtLeast) return;
    _timer?.cancel();
    _timer = Timer(HomeResumeRefresh.delay, () {
      if (mounted && widget.tab == discoverTab) ref.read(discoverRefreshProvider.notifier).request();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
