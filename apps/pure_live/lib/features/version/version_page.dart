import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/markdown_text.dart';
import 'package:pure_live/features/version/update_download.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// The installation packages of [platform] in a release, by section title
/// key, in 3.x's order; Android only lists the ABIs the release declares.
List<(String, ReleaseFile)> platformPackages(String platform, UpdateInfo info, List<ReleaseFile> files) {
  final packages = <(String, ReleaseFile)>[];
  void add(String title, PackageKind kind, {bool offered = true, PackageKind? otherwise}) {
    if (!offered) return;
    final file = kind.pick(files) ?? otherwise?.pick(files);
    if (file != null) packages.add((title, file));
  }

  switch (platform) {
    case 'android':
      add('arch_arm64', PackageKind.androidArm64, offered: info.androidAbis.contains('arm64-v8a'));
      add('arch_arm32', PackageKind.androidArm32, offered: info.androidAbis.contains('armeabi-v7a'));
      add('arch_x86_64', PackageKind.androidX64, offered: info.androidAbis.contains('x86_64'));
    case 'windows':
      add('exe_installer', PackageKind.windowsSetup);
      add('msix_installer', PackageKind.windowsMsix, offered: info.windowsMsixAvailable);
      add('portable_package', PackageKind.windowsPortable);
    case 'macos':
      add('macos_package', PackageKind.macosDmg, otherwise: PackageKind.macosZip);
  }
  return packages;
}

/// Update check (3.x `lib/modules/version`).
///
/// Routes: `RoutePath.kVersionPage`.
///
/// Reads `assets/version.json` and `assets/releases.json` from the
/// repository (the files the installed 3.x apps read too), shows the
/// installed and the newest version, this platform's packages on every
/// download mirror, and the update notes.
class VersionPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<VersionPage> createState() => _VersionPageState();
}

class _VersionPageState extends ConsumerState<VersionPage> {
  bool _loading = true;
  UpdateInfo? _info;
  List<ReleaseFile> _files = const [];
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  /// Always asks the repository again (3.x answered from a copy kept since
  /// the start-up check, so "retry" never saw a new release).
  Future<void> _check() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
    });
    final feed = ref.read(updateFeedProvider);
    UpdateInfo? info;
    var files = const <ReleaseFile>[];
    try {
      info = await feed.latest();
      if (info != null) {
        try {
          final releases = await feed.releases() ?? const [];
          final wanted = info.version.replaceFirst(RegExp('^[vV]'), '');
          files =
              releases
                  .where((release) => release.version.replaceFirst(RegExp('^[vV]'), '') == wanted)
                  .firstOrNull
                  ?.files ??
              const [];
        } on Object {
          // The packages are optional: the release page still links them.
        }
      }
    } on Object {
      info = null;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      _info = info;
      _files = files;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: textScale <= 1.5 ? kToolbarHeight : math.min(152, 44 + 36 * textScale),
        title: Text(i18n('version_update'), maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('version-refresh'),
            tooltip: i18n('refresh'),
            onPressed: _loading ? null : _check,
            icon: _loading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: switch ((_loading, _info)) {
          (true, null) => const _Checking(key: ValueKey('version-checking')),
          (_, null) => _Failed(key: const ValueKey('version-update-error'), onRetry: _check),
          (_, final UpdateInfo info) => _Details(
            key: const ValueKey('version-update-scroll'),
            info: info,
            packages: platformPackages(ref.read(updateFeedProvider).platform, info, _files),
          ),
        },
      ),
    );
  }
}

class _Checking extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(i18n('version_checking'), style: context.textStyles.t13),
      ],
    ),
  );
}

class _Failed extends StatelessWidget {
  const new({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      physics: const PureLiveScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    i18n('version_update_failed_title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    i18n('version_update_failed_subtitle'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('version-update-retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(i18n('retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Details extends ConsumerWidget {
  const new({required this.info, required this.packages, super.key});

  final UpdateInfo info;
  final List<(String, ReleaseFile)> packages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final githubOrigin = watchSetting(ref, Settings.useGitHubOriginForUpdates);
    final release = updateDownloadUri(info.releaseUrl);
    return ListView(
      physics: const PureLiveScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusCard(info: info),
                const SizedBox(height: 20),
                if (packages.isNotEmpty) ...[
                  context.buildGroupTitle(i18n('download_files')),
                  const SizedBox(height: 8),
                  context.buildModernCard([
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (index, (title, file)) in packages.indexed) ...[
                            if (index > 0) const SizedBox(height: 16),
                            _PackageSources(
                              title: i18n(title),
                              file: file,
                              sources: downloadSources(file.url, githubOrigin: githubOrigin),
                              githubOrigin: githubOrigin,
                              version: info.version,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                ] else if (release != null) ...[
                  Text(
                    i18n('version_no_packages'),
                    style: context.textStyles.t13.copyWith(color: Theme.of(context).hintColor),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('version-open-release'),
                    onPressed: () => unawaited(_openExternal(release)),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(i18n('version_history_open_release')),
                  ),
                  const SizedBox(height: 20),
                ],
                if (info.log.trim().isNotEmpty) ...[
                  context.buildGroupTitle(i18n('update_log')),
                  const SizedBox(height: 8),
                  context.buildModernCard([
                    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: MarkdownText(info.log)),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const new({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newer = info.isNewer;
    final color = newer ? theme.colorScheme.primary : theme.colorScheme.tertiary;
    return Container(
      key: ValueKey(newer ? 'version-newer' : 'version-latest'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(newer ? Icons.system_update_rounded : Icons.verified_rounded, color: color, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  newer ? i18n('new_version_info', args: {'version': info.version}) : i18n('no_new_version_info'),
                  style: context.textStyles.t16Bold,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      i18n('version_installed', args: {'version': appVersion}),
                      style: context.textStyles.t12.copyWith(color: theme.hintColor),
                    ),
                    Text(
                      i18n('version_newest', args: {'version': info.version}),
                      style: context.textStyles.t12.copyWith(color: theme.hintColor),
                    ),
                    if (info.prerelease)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          i18n('version_prerelease'),
                          style: context.textStyles.t11.copyWith(color: theme.colorScheme.onErrorContainer),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageSources extends StatelessWidget {
  const new({
    required this.title,
    required this.file,
    required this.sources,
    required this.githubOrigin,
    required this.version,
  });

  final String title;
  final ReleaseFile file;
  final List<String> sources;
  final bool githubOrigin;
  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$title · ${file.size}',
                style: context.textStyles.t13.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              key: ValueKey('version-download-${file.name}'),
              onPressed: () => unawaited(showUpdateDownload(context, file: file, sources: sources, version: version)),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(i18n('update_download_install')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width > 800 ? 4 : (width > 500 ? 3 : 2);
            const spacing = 8.0;
            final buttonWidth = (width - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final (index, source) in sources.indexed)
                  SizedBox(
                    width: buttonWidth,
                    child: Tooltip(
                      message: source,
                      waitDuration: const Duration(milliseconds: 300),
                      child: OutlinedButton.icon(
                        key: ValueKey('version-source-${file.name}-$index'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, kMinInteractiveDimension),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => unawaited(_showSource(context, index, source)),
                        icon: const Icon(Icons.link_rounded, size: 14),
                        label: Text(
                          githubOrigin || index == sources.length - 1
                              ? i18n('github_origin_source')
                              : i18n('download_source', args: {'num': '${index + 1}'}),
                          style: context.textStyles.t12.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _showSource(BuildContext pageContext, int index, String url) => showDialog<void>(
    context: pageContext,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(title, style: dialogContext.textStyles.t15.copyWith(fontWeight: FontWeight.bold)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(file.name, style: dialogContext.textStyles.t13.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(url, style: dialogContext.textStyles.t11),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('version-source-download'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(showUpdateDownload(pageContext, file: file, sources: [url], version: version));
                },
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(i18n('update_download_in_app')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('version-source-browser'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  final uri = updateDownloadUri(url);
                  if (uri != null) unawaited(_openExternal(uri));
                },
                icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                label: Text(i18n('update_open_in_browser')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('version-source-copy'),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await Clipboard.setData(ClipboardData(text: url));
                  AppNavigator.toast(i18n('copied_to_clipboard'));
                },
                icon: const Icon(Icons.copy_rounded, size: 20),
                label: Text(i18n('copy_link')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('version-source-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(i18n('cancel')),
          ),
        ],
      );
    },
  );
}

/// Opens [uri] in the browser; tells the user when nothing opened.
Future<void> _openExternal(Uri uri) async {
  var opened = false;
  try {
    opened = await AppNavigator.openExternal(uri);
  } on Object {
    opened = false;
  }
  if (!opened) AppNavigator.toast(i18n('external_browser_not_opened'));
}
