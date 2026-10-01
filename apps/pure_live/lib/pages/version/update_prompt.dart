import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/version/markdown_text.dart';
import 'package:pure_live/pages/version/update_download.dart';
import 'package:pure_live/pages/version/update_feed.dart';
import 'package:pure_live/pages/version/version_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// How long after home appears the start-up check runs (3.x
/// `HomePage.updateCheckDelay`).
const Duration startupUpdateCheckDelay = Duration(seconds: 2);

/// The start-up update check (3.x `HomePage._checkForStartupUpdate`): when
/// the setting `enableAutoCheckUpdate` is on and the repository has a newer
/// version, shows [NewVersionDialog] over [context]. Failures are quiet.
///
/// Home calls it once after its first frame (after
/// [startupUpdateCheckDelay]); 3.x fetched the files even with the setting
/// off, here nothing is fetched then.
Future<void> checkForUpdateOnStartup(
  BuildContext context, {
  required SettingsStore settings,
  required UpdateFeed feed,
}) async {
  if (!settings.get(Settings.enableAutoCheckUpdate)) return;
  try {
    final info = await feed.latest();
    if (info == null || !info.isNewer || !context.mounted || !settings.get(Settings.enableAutoCheckUpdate)) return;
    // This platform's first package (arm64 APK, Windows installer) for the
    // in-app download; without one "update" opens the version page.
    ReleaseFile? package;
    try {
      final wanted = info.version.replaceFirst(RegExp('^[vV]'), '');
      final files =
          (await feed.releases())
              ?.where((release) => release.version.replaceFirst(RegExp('^[vV]'), '') == wanted)
              .firstOrNull
              ?.files ??
          const <ReleaseFile>[];
      package = platformPackages(feed.platform, info, files).firstOrNull?.$2;
    } on Object {
      package = null;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => NewVersionDialog(
        info: info,
        package: package,
        sources: package == null
            ? const []
            : downloadSources(package.url, githubOrigin: settings.get(Settings.useGitHubOriginForUpdates)),
      ),
    );
  } on Object catch (error, stack) {
    log('Start-up update check skipped', name: 'Update', error: error, stackTrace: stack);
  }
}

/// "A new version is out" (3.x `NewVersionDialog`): the project link, the
/// update notes, "details" to the version page and, when this platform has a
/// package, "download and install" in the app ([showUpdateDownload]).
class NewVersionDialog extends StatelessWidget {
  /// Shows [info]; [package] and its [sources] enable the in-app download.
  const new({required this.info, this.package, this.sources = const [], super.key});

  /// The newer version.
  final UpdateInfo info;

  /// This platform's package, or null.
  final ReleaseFile? package;

  /// Its download mirrors ([downloadSources]).
  final List<String> sources;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('new-version-dialog'),
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    title: Text(i18n('new_version_info', args: {'version': info.version})),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            key: const ValueKey('new-version-open-project'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            onPressed: () {
              Navigator.pop(context);
              unawaited(AppNavigator.openExternal(projectUrl));
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(i18n('open_source_free')),
          ),
          if (info.log.trim().isNotEmpty) MarkdownText(info.log),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('new-version-cancel'),
        onPressed: () => Navigator.pop(context),
        child: Text(i18n('cancel')),
      ),
      if (package case final file? when sources.isNotEmpty) ...[
        TextButton(
          key: const ValueKey('new-version-details'),
          onPressed: () {
            Navigator.pop(context);
            unawaited(AppNavigator.toNamed<void>(RoutePath.kVersionPage));
          },
          child: Text(i18n('update_details')),
        ),
        FilledButton(
          key: const ValueKey('new-version-update'),
          onPressed: () {
            final navigator = Navigator.of(context);
            final host = navigator.context;
            navigator.pop();
            unawaited(showUpdateDownload(host, file: file, sources: sources));
          },
          child: Text(i18n('update_download_install')),
        ),
      ] else
        FilledButton(
          key: const ValueKey('new-version-update'),
          onPressed: () {
            Navigator.pop(context);
            unawaited(AppNavigator.toNamed<void>(RoutePath.kVersionPage));
          },
          child: Text(i18n('update')),
        ),
    ],
  );
}
