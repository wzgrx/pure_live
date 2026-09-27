import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/about/update_state.dart';
import 'package:pure_live_app/features/diagnostics/crash_handler.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/features/onboarding/first_run.dart';
import 'package:pure_live_app/features/onboarding/onboarding_page.dart';
import 'package:pure_live_app/features/share/clipboard_watch.dart';

/// Location of the diagnostics page.
const diagnosticsLocation = '/me/diagnostics';

/// Whether to offer the first-run wizard, backed by the app preferences and
/// the follow count.
final firstRunGateProvider = Provider<FirstRunGate>(
  (ref) => FirstRunGate(
    isDone: () => ref.read(appPrefsProvider).firstRunDone,
    markDone: ref.read(appPrefsProvider.notifier).markFirstRunDone,
    followCount: ref.watch(storeProvider).follows.count,
  ),
);

/// Work that starts after the first frame (the router's navigator exists
/// then): the first-run wizard, the crash prompt, the automatic update
/// check 2 s later and the clipboard check 1 s after each return to the
/// foreground. Timers and listeners end with the provider.
final startupTasksProvider = Provider<void>((ref) {
  final router = ref.read(routerProvider);
  unawaited(_offerFirstRun(ref, router));
  _offerCrashReport(ref, router);

  final update = scheduleAutoUpdateCheck(ref, router);
  Timer? clipboard;
  final lifecycle = AppLifecycleListener(
    onResume: () {
      clipboard?.cancel();
      clipboard = Timer(const Duration(seconds: 1), () => unawaited(ref.read(clipboardWatcherProvider).check()));
    },
  );
  ref.onDispose(() {
    update.cancel();
    clipboard?.cancel();
    lifecycle.dispose();
  });
});

Future<void> _offerFirstRun(Ref ref, GoRouter router) async {
  try {
    if (await ref.read(firstRunGateProvider).take()) unawaited(router.push(welcomeLocation));
  } on Object catch (error, stack) {
    ref.read(appLogProvider).error('startup', 'first-run check failed', error, stack);
  }
}

void _offerCrashReport(Ref ref, GoRouter router) {
  // The marker is cleared either way; the prompt only when the user asked.
  if (!CrashMarker(ref.read(appLogProvider)).take() || !ref.read(appPrefsProvider).crashReports) return;
  final context = router.routerDelegate.navigatorKey.currentContext;
  if (context == null) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: const Text('上次运行时出现了错误。导出诊断包附在问题反馈里，可以帮助定位原因'),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(label: '导出', onPressed: () => router.go(diagnosticsLocation)),
    ),
  );
}

/// Starts [startupTasksProvider] after the first frame; wraps the app in
/// main().
class StartupTasks extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  ConsumerState<StartupTasks> createState() => _StartupTasksState();
}

class _StartupTasksState extends ConsumerState<StartupTasks> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(startupTasksProvider);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
