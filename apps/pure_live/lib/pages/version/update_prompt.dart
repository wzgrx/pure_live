import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/version/markdown_text.dart';
import 'package:pure_live/pages/version/update_feed.dart';
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
    await showDialog<void>(
      context: context,
      builder: (_) => NewVersionDialog(info: info),
    );
  } on Object catch (error, stack) {
    log('Start-up update check skipped', name: 'Update', error: error, stackTrace: stack);
  }
}

/// "A new version is out" (3.x `NewVersionDialog`): the project link, the
/// update notes, and "update" to the version page.
class NewVersionDialog extends StatelessWidget {
  /// Shows [info].
  const new({required this.info, super.key});

  /// The newer version.
  final UpdateInfo info;

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
