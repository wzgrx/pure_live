import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/error_view.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// One platform's check result.
@immutable
final class PlatformHealth {
  const new({required this.platform, required this.ok, required this.elapsed, this.problem});

  final String platform;
  final bool ok;
  final Duration elapsed;

  /// What went wrong, in words.
  final String? problem;
}

/// Checks every enabled platform by loading its category list, in parallel,
/// each within 15 s (spec/product.md F-NEW-09 "平台健康状态").
final FutureProvider<List<PlatformHealth>> platformHealthProvider = FutureProvider.autoDispose<List<PlatformHealth>>((
  ref,
) async {
  final sites = ref.watch(sitesProvider);
  final platforms = ref.watch(browsablePlatformsProvider);
  return await Future.wait([
    for (final id in platforms)
      () async {
        final watch = Stopwatch()..start();
        try {
          await sites[id]!.catalog.categories().timeout(const Duration(seconds: 15));
          return PlatformHealth(platform: id, ok: true, elapsed: watch.elapsed);
        } on TimeoutException {
          return PlatformHealth(platform: id, ok: false, elapsed: watch.elapsed, problem: t.health.timeout);
        } on Object catch (error) {
          return PlatformHealth(platform: id, ok: false, elapsed: watch.elapsed, problem: describeError(error).title);
        }
      }(),
  ]);
});

/// 关于 › 平台状态: which platforms answer right now, so "看不了" can be told
/// apart from a platform outage.
class PlatformStatusPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(platformHealthProvider);
    final live = LiveTheme.of(context);
    return Scaffold(
      appBar: PageAppBar(
        title: Text(t.about.platformStatus),
        actions: [
          IconButton(
            tooltip: t.health.checkAgain,
            icon: const LiveIcon(LiveIcons.refresh),
            onPressed: () => ref.invalidate(platformHealthProvider),
          ),
        ],
      ),
      body: PageBody(
        child: async.when(
          loading: () => LoadingView(label: t.health.checkingAll),
          error: (error, _) =>
              ErrorView(error, title: t.health.checkFailed, onRetry: () => ref.invalidate(platformHealthProvider)),
          data: (results) => ListView(
            children: [
              for (final result in results)
                ListTile(
                  leading: PlatformLogo(platformId: result.platform, size: Sizes.logoLarge),
                  title: Text(platformNames[result.platform] ?? result.platform),
                  subtitle: Text(
                    result.ok ? t.health.ok(ms: result.elapsed.inMilliseconds) : result.problem ?? t.health.failed,
                  ),
                  trailing: LiveIcon(
                    result.ok ? LiveIcons.success : LiveIcons.error,
                    filled: true,
                    color: result.ok ? live.success : Theme.of(context).colorScheme.error,
                  ),
                ),
              Padding(padding: const EdgeInsets.all(Space.s4), child: Text(t.health.method)),
            ],
          ),
        ),
      ),
    );
  }
}
