import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/about/releases.dart';
import 'package:pure_live_app/features/about/semver.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Location of the version and update page.
const updateLocation = '/me/about/update';

/// This build's version.
final SemVer currentVersion = SemVer.tryParse(appVersion) ?? const SemVer(0, 0, 0);

/// Reads GitHub releases over the app's HTTP transport.
final updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => UpdateChecker(ref.watch(liveHttpProvider), userAgent: 'PureLive/$appVersion'),
);

/// The result of an update check.
@immutable
final class UpdateStatus {
  /// Creates a status.
  const new({this.releases = const [], this.latest, this.error, this.checking = false});

  /// v4 releases of this build's channel, newest first.
  final List<Release> releases;

  /// The newest release above this build, or null when up to date.
  final Release? latest;

  /// Why the last check failed.
  final UpdateCheckException? error;

  /// Whether a check is running.
  final bool checking;
}

/// Update checks (F-UPD-01); null until the first check.
class UpdateNotifier extends Notifier<UpdateStatus?> {
  @override
  UpdateStatus? build() => null;

  Future<UpdateStatus>? _running;

  /// Checks now; concurrent calls share one request.
  Future<UpdateStatus> check() => _running ??= _check().whenComplete(() => _running = null);

  Future<UpdateStatus> _check() async {
    final previous = state;
    state = UpdateStatus(releases: previous?.releases ?? const [], latest: previous?.latest, checking: true);
    final checker = ref.read(updateCheckerProvider);
    UpdateStatus result;
    try {
      final all = await checker.releases();
      var latest = UpdateChecker.newest(all, currentVersion);
      if (latest != null) latest = await checker.withChecksumFile(latest);
      result = UpdateStatus(
        releases: UpdateChecker.v4Releases(all, includePreRelease: currentVersion.isPreRelease),
        latest: latest,
      );
      ref.read(appLogProvider).info('update', latest == null ? 'up to date' : 'found ${latest.tag}');
    } on UpdateCheckException catch (error) {
      ref.read(appLogProvider).warning('update', 'check failed', error);
      result = UpdateStatus(releases: previous?.releases ?? const [], latest: previous?.latest, error: error);
    }
    state = result;
    return result;
  }
}

/// The update check state shared by the about and update pages.
final updateProvider = NotifierProvider<UpdateNotifier, UpdateStatus?>(UpdateNotifier.new);

/// Chinese text for a failed check.
String updateErrorText(UpdateCheckException error) => switch (error.error) {
  UpdateCheckError.rateLimited => t.about.errorRateLimited,
  UpdateCheckError.network => t.about.errorNetwork,
  UpdateCheckError.server => t.about.errorServer(detail: error.detail ?? t.about.unknownError),
};

/// The automatic check (F-UPD-01): once per launch, 2 s after the first
/// frame, when `app.autoCheckUpdate` is on; a newer release shows a snack
/// bar that opens the update page. Returns the timer so tests can cancel it.
Timer scheduleAutoUpdateCheck(Ref ref, GoRouter router, {Duration delay = const Duration(seconds: 2)}) =>
    Timer(delay, () async {
      if (!ref.read(storeProvider).settings.get(Settings.autoCheckUpdate)) return;
      final status = await ref.read(updateProvider.notifier).check();
      final latest = status.latest;
      final context = router.routerDelegate.navigatorKey.currentContext;
      if (latest == null || context == null || !context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            latest.preRelease
                ? t.about.newPreviewVersion(version: latest.version)
                : t.about.newVersion(version: latest.version),
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: t.about.view, onPressed: () => router.go(updateLocation)),
        ),
      );
    });
