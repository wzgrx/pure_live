import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/markdown_text.dart';
import 'package:pure_live/features/version/update_download.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/version_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/app_prompts.dart';

/// How long after home appears the start-up check runs (3.x
/// `HomePage.updateCheckDelay`).
const Duration startupUpdateCheckDelay = Duration(seconds: 2);

/// The start-up update check (3.x `HomePage._checkForStartupUpdate`): when
/// the setting `enableAutoCheckUpdate` is on and the repository has a newer
/// version the user did not skip ([Settings.skippedUpdateVersion]), shows
/// [NewVersionDialog] over [context]. Failures are quiet.
///
/// The dialog waits its turn among the app's prompts ([AppPrompts]: after a
/// share prompt) and opens only while the page of [context] is on top, so
/// it never covers a live room; it waits for home to come back (U.3c c7,
/// K2; 3.x opened it over whatever was there).
///
/// Home calls it once after its first frame (after
/// [startupUpdateCheckDelay]); 3.x fetched the files even with the setting
/// off, here nothing is fetched then.
Future<void> checkForUpdateOnStartup(
  BuildContext context, {
  required SettingsStore settings,
  required UpdateFeed feed,
  AppPrompts? prompts,
}) async {
  if (!settings.get(Settings.enableAutoCheckUpdate)) return;
  try {
    final info = await feed.latest();
    // The about page shows "新版本 v…" from this (U.12b c3), also when the
    // version was skipped.
    if (info != null) noteCheckedUpdate(info);
    if (info == null || !info.isNewer || !context.mounted || !_wanted(settings, info)) return;
    // This device's package (U.12b "本机"; else the platform's first: arm64
    // APK, Windows installer) for the in-app download; without one "update"
    // opens the version page.
    ReleaseFile? package;
    try {
      final wanted = info.version.replaceFirst(RegExp('^[vV]'), '');
      final files =
          (await feed.releases())
              ?.where((release) => release.version.replaceFirst(RegExp('^[vV]'), '') == wanted)
              .firstOrNull
              ?.files ??
          const <ReleaseFile>[];
      final packages = platformPackages(feed.platform, info, files);
      final native = nativePackageTitle();
      package = (packages.where((entry) => entry.$1 == native).firstOrNull ?? packages.firstOrNull)?.$2;
    } on Object {
      package = null;
    }
    if (!context.mounted) return;
    final route = ModalRoute.of(context);
    await (prompts ?? AppPrompts.instance).show<void>(
      AppPromptKind.update,
      ready: () => context.mounted && (route?.isCurrent ?? true),
      () async {
        // The setting or the skip may have changed while it waited.
        if (!context.mounted || !_wanted(settings, info)) return;
        await showDialog<void>(
          context: context,
          builder: (_) => NewVersionDialog(
            info: info,
            package: package,
            settings: settings,
            sources: package == null
                ? const []
                : downloadSources(package.url, githubOrigin: settings.get(Settings.useGitHubOriginForUpdates)),
          ),
        );
      },
    );
  } on Object catch (error, stack) {
    log('Start-up update check skipped', name: 'Update', error: error, stackTrace: stack);
  }
}

bool _wanted(SettingsStore settings, UpdateInfo info) =>
    settings.get(Settings.enableAutoCheckUpdate) &&
    compareVersions(settings.get(Settings.skippedUpdateVersion), info.version) != 0;

/// From this width the "skip" box sits at the left of the button row (U.3d
/// c5), so a landscape phone shows the whole log.
const double newVersionWideFrom = 480;

/// "A new version is out" (3.x `NewVersionDialog`, docs/ui/compare/U.3d):
/// "发现新版本 v…", the installed version and the project link (which keeps
/// the dialog open), the update notes under "更新内容" (scrolling on their
/// own when long), "不再提醒这个版本" when [settings] are given, and the
/// buttons "其他下载方式" (the version page), "取消" and "下载并安装" (the
/// in-app download of [package], [showUpdateDownload]). Without a package
/// the main button is "更新" and opens the version page.
///
/// Enter presses the main button, Esc and Back cancel.
class NewVersionDialog extends StatefulWidget {
  /// Shows [info]; [package] and its [sources] enable the in-app download.
  const new({required this.info, this.package, this.sources = const [], this.settings, super.key});

  /// The newer version.
  final UpdateInfo info;

  /// This platform's package, or null.
  final ReleaseFile? package;

  /// Its download mirrors ([downloadSources]).
  final List<String> sources;

  /// Where "不再提醒这个版本" is kept; without it the box is not shown.
  final SettingsStore? settings;

  @override
  State<NewVersionDialog> createState() => _NewVersionDialogState();
}

class _NewVersionDialogState extends State<NewVersionDialog> {
  late bool _skip = widget.settings?.get(Settings.skippedUpdateVersion) == widget.info.version;

  bool get _inApp => widget.package != null && widget.sources.isNotEmpty;

  void _toggleSkip(bool? value) {
    final skip = value ?? false;
    setState(() => _skip = skip);
    unawaited(widget.settings?.set(Settings.skippedUpdateVersion, skip ? widget.info.version : ''));
  }

  void _otherWays() {
    Navigator.pop(context);
    unawaited(AppNavigator.toNamed<void>(RoutePath.kVersionPage));
  }

  void _primary() {
    final navigator = Navigator.of(context);
    if (widget.package case final file? when _inApp) {
      final host = navigator.context;
      navigator.pop();
      unawaited(showUpdateDownload(host, file: file, sources: widget.sources, version: widget.info.version));
      return;
    }
    navigator.pop();
    unawaited(AppNavigator.toNamed<void>(RoutePath.kVersionPage));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = context.textStyles;
    final body = styles.t14.copyWith(color: scheme.onSurface);
    final subtle = styles.t14.copyWith(color: scheme.onSurfaceVariant);
    final log = widget.info.log.trim();
    final skip = widget.settings == null
        ? null
        : InkWell(
            key: const ValueKey('new-version-skip'),
            onTap: () => _toggleSkip(!_skip),
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(value: _skip, onChanged: _toggleSkip),
                  Text(i18n('update_skip_version'), style: body),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          );
    final other = _inApp
        ? TextButton(
            key: const ValueKey('new-version-details'),
            onPressed: _otherWays,
            child: Text(i18n('update_other_ways')),
          )
        : null;
    final cancel = TextButton(
      key: const ValueKey('new-version-cancel'),
      onPressed: () => Navigator.pop(context),
      child: Text(i18n('cancel')),
    );
    final primary = FilledButton(
      key: const ValueKey('new-version-update'),
      onPressed: _primary,
      child: Text(i18n(_inApp ? 'update_download_install' : 'update')),
    );
    return DialogButtonsTheme(
      child: DialogKeys(
        onEnter: _primary,
        child: Dialog(
          key: const ValueKey('new-version-dialog'),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= newVersionWideFrom;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i18n('update_new_version_title', args: {'version': widget.info.version}),
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(i18n('version_installed', args: {'version': appVersion}), style: subtle),
                              InkWell(
                                key: const ValueKey('new-version-open-project'),
                                borderRadius: BorderRadius.circular(4),
                                // The dialog stays (U.3d c2; 3.x closed it first).
                                onTap: () => unawaited(AppNavigator.openExternal(projectUrl)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(i18n('open_source_free'), style: subtle.copyWith(color: scheme.primary)),
                                    const SizedBox(width: 2),
                                    Icon(AppIcons.openExternal, size: 16, color: scheme.primary),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (log.isNotEmpty)
                      Flexible(
                        child: SingleChildScrollView(
                          key: const ValueKey('new-version-log'),
                          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                i18n('update_log_title'),
                                style: styles.t13.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              // The notes at the dialog's body size (3.x: 16).
                              Theme(
                                data: theme.copyWith(
                                  textTheme: theme.textTheme.copyWith(bodyMedium: body.copyWith(height: 1.5)),
                                ),
                                child: MarkdownText(log),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (skip != null && !wide)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 24, 0),
                        child: Align(alignment: Alignment.centerLeft, child: skip),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(wide && skip != null ? 14 : 24, 20, 24, 24),
                      // Left: the skip box (wide) or "其他下载方式"; the rest at
                      // the right, wrapping to a second line with a large font.
                      child: Row(
                        children: [
                          if (wide) ?skip else ?other,
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [if (wide) ?other, cancel, primary],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
