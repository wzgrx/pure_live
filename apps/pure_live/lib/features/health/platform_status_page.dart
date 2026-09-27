import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';

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
  final platforms = ref.watch(enabledPlatformsProvider);
  return await Future.wait([
    for (final id in platforms)
      () async {
        final watch = Stopwatch()..start();
        try {
          await sites[id]!.catalog.categories().timeout(const Duration(seconds: 15));
          return PlatformHealth(platform: id, ok: true, elapsed: watch.elapsed);
        } on TimeoutException {
          return PlatformHealth(platform: id, ok: false, elapsed: watch.elapsed, problem: '15 秒内没有响应');
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
      appBar: AppBar(
        title: const Text('平台状态'),
        actions: [
          IconButton(
            tooltip: '重新检查',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(platformHealthProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(label: '正在检查各平台'),
        error: (error, _) => MessageView.error(title: '检查失败', message: '$error'),
        data: (results) => ListView(
          children: [
            for (final result in results)
              ListTile(
                leading: PlatformLogo(platformId: result.platform, size: Sizes.iconLg),
                title: Text(platformNames[result.platform] ?? result.platform),
                subtitle: Text(result.ok ? '正常 · ${result.elapsed.inMilliseconds} ms' : result.problem ?? '异常'),
                trailing: Icon(
                  result.ok ? Icons.check_circle : Icons.error,
                  color: result.ok ? live.success : Theme.of(context).colorScheme.error,
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(Space.s4),
              child: Text('检查方式：请求各平台的分区列表。某个平台异常时，关注页和发现页会显示上次的内容，直播间可能打不开。'),
            ),
          ],
        ),
      ),
    );
  }
}
