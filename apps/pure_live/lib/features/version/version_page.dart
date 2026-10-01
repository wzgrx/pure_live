import 'dart:async';
import 'dart:ffi' show Abi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/markdown_text.dart';
import 'package:pure_live/features/version/release_history_view.dart';
import 'package:pure_live/features/version/update_download.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

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

/// The title of this device's package among [platformPackages] (the "本机"
/// mark, docs/ui/compare/U.12b c7): the running app's architecture on
/// Android, the EXE installer on Windows, the universal package on macOS;
/// null elsewhere.
String? nativePackageTitle([Abi? abi]) => switch (abi ?? Abi.current()) {
  Abi.androidArm64 => 'arch_arm64',
  Abi.androidArm => 'arch_arm32',
  Abi.androidX64 => 'arch_x86_64',
  Abi.windowsX64 || Abi.windowsArm64 => 'exe_installer',
  Abi.macosArm64 || Abi.macosX64 => 'macos_package',
  _ => null,
};

/// [nativePackageTitle] for the version page (tests replace it).
final Provider<String?> nativePackageTitleProvider = Provider<String?>((ref) => nativePackageTitle());

/// The name of an update platform on the page ("下载文件 · Android").
String _platformName(String platform) => switch (platform) {
  'android' => 'Android',
  'windows' => 'Windows',
  'macos' => 'macOS',
  'ios' => 'iOS',
  'linux' => 'Linux',
  _ => platform,
};

/// Update check and version history (3.x `lib/modules/version` and
/// `modules/about/version_history.dart`, docs/ui/compare/U.12b).
///
/// Routes: `RoutePath.kVersionPage` ([UpdateView]) and
/// `RoutePath.kVersionHistory` ([ReleaseHistoryView]; the about page hands
/// that route here).
class VersionPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) => switch (route.path) {
    RoutePath.kVersionHistory => const ReleaseHistoryView(),
    _ => const UpdateView(),
  };
}

/// Reads `assets/version.json` and `assets/releases.json` from the
/// repository (the files the installed 3.x apps read too) and shows a
/// status card (a newer version or the newest), this platform's packages
/// with "下载并安装" (this device's marked "本机", the mirrors folded under
/// "选择下载源"), and the update notes; at most 720 wide.
class UpdateView extends ConsumerStatefulWidget {
  /// Creates the view.
  const new({super.key});

  @override
  ConsumerState<UpdateView> createState() => _UpdateViewState();
}

class _UpdateViewState extends ConsumerState<UpdateView> {
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
        noteCheckedUpdate(info);
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
    final short = MediaQuery.sizeOf(context).height < 480;
    final platform = ref.read(updateFeedProvider).platform;
    return Scaffold(
      appBar: AppBar(
        // 3.x's app bars centre the title (common/style/theme.dart:119).
        centerTitle: true,
        toolbarHeight: short ? 48 : null,
        title: Text(i18n('version_update'), maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('version-refresh'),
            tooltip: i18n('refresh'),
            onPressed: _loading ? null : _check,
            icon: _loading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(AppIcons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: switch ((_loading, _info)) {
          (true, null) => AppStatusView(
            key: const ValueKey('version-checking'),
            type: AppStatusType.loading,
            title: i18n('version_checking'),
          ),
          // 3.x's failure: an offline cloud, what failed, "重试".
          (_, null) => AppStatusView(
            key: const ValueKey('version-update-error'),
            type: AppStatusType.error,
            icon: AppIcons.cloudOff,
            title: i18n('version_update_failed_title'),
            subtitle: i18n('version_update_failed_subtitle'),
            buttonText: i18n('retry'),
            buttonIcon: AppIcons.retry,
            onButtonPressed: _check,
          ),
          (_, final UpdateInfo info) => _Details(
            key: const ValueKey('version-update-scroll'),
            info: info,
            platform: _platformName(platform),
            packages: platformPackages(platform, info, _files),
            native: ref.watch(nativePackageTitleProvider),
          ),
        },
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const new({required this.info, required this.platform, required this.packages, required this.native, super.key});

  final UpdateInfo info;
  final String platform;
  final List<(String, ReleaseFile)> packages;
  final String? native;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final githubOrigin = watchSetting(ref, Settings.useGitHubOriginForUpdates);
    final release = updateDownloadUri(info.releaseUrl);
    final colors = Theme.of(context).colorScheme;
    return ListView(
      physics: const PureLiveScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        for (final child in [
          _StatusCard(info: info),
          if (packages.isNotEmpty)
            SettingsGroup(
              key: const ValueKey('version-packages'),
              title: '${i18n('download_files')} · $platform',
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, (title, file)) in packages.indexed) ...[
                      if (index > 0)
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: colors.outlineVariant.withValues(alpha: 0.7),
                        ),
                      _Package(
                        title: i18n(title),
                        file: file,
                        native: title == native,
                        sources: downloadSources(file.url, githubOrigin: githubOrigin),
                        githubOrigin: githubOrigin,
                        version: info.version,
                      ),
                    ],
                  ],
                ),
              ],
            )
          else if (release != null)
            // iOS, Linux: no package of this platform (v4).
            SettingsGroup(
              title: i18n('download_files'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i18n('version_no_packages'),
                        style: context.textStyles.t14.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('version-open-release'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                        onPressed: () => unawaited(_openExternal(release)),
                        icon: const Icon(AppIcons.openExternal, size: 18),
                        label: Text(i18n('version_history_open_release')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          if (info.log.trim().isNotEmpty)
            SettingsGroup(
              title: i18n('update_log'),
              children: [Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: MarkdownText(info.log))],
            ),
        ])
          ReadableContent(
            child: SizedBox(width: double.infinity, child: child),
          ),
      ],
    );
  }
}

/// "发现新版本: v…" or "已在使用最新版本", the installed and the newest
/// version and "预发布" (c6; 3.x computed it but did not say it).
class _StatusCard extends StatelessWidget {
  const new({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final newer = info.isNewer;
    final color = newer ? colors.primary : colors.tertiary;
    final muted = styles.t13.copyWith(color: colors.onSurfaceVariant);
    return Container(
      key: ValueKey(newer ? 'version-newer' : 'version-latest'),
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(newer ? AppIcons.updateAvailable : AppIcons.upToDate, color: color, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  newer ? i18n('new_version_info', args: {'version': info.version}) : i18n('no_new_version_info'),
                  style: styles.t16Bold,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(i18n('version_installed', args: {'version': appVersion}), style: muted),
                    Text(i18n('version_newest', args: {'version': info.version}), style: muted),
                    if (info.prerelease)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: const BorderRadius.all(Radius.circular(6)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          child: Text(
                            i18n('version_prerelease'),
                            style: styles.t12.copyWith(color: colors.onErrorContainer),
                          ),
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

/// One package (c7, N2 A): "ARM64 (64位) · 38.6 MB", "本机" on this
/// device's, "下载并安装" (U.3d: the fastest mirror first, the next one on
/// failure); the mirrors fold under "选择下载源（N 个）" and each opens its
/// dialog as in 3.x.
class _Package extends StatefulWidget {
  const new({
    required this.title,
    required this.file,
    required this.native,
    required this.sources,
    required this.githubOrigin,
    required this.version,
  });

  final String title;
  final ReleaseFile file;
  final bool native;
  final List<String> sources;
  final bool githubOrigin;
  final String version;

  @override
  State<_Package> createState() => _PackageState();
}

class _PackageState extends State<_Package> {
  bool _open = false;

  String _sourceName(int index) => widget.githubOrigin || index == widget.sources.length - 1
      ? i18n('github_origin_source')
      : i18n('download_source', args: {'num': '${index + 1}'});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final file = widget.file;
    final heading = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(widget.title, style: styles.t15.copyWith(fontWeight: FontWeight.w600)),
        Text('· ${file.size}', style: styles.t13.copyWith(color: colors.onSurfaceVariant)),
        if (widget.native)
          DecoratedBox(
            key: ValueKey('version-native-${file.name}'),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Text(
                i18n('update_native_package'),
                style: styles.t12.copyWith(color: colors.onPrimaryContainer, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
    final install = FilledButton.tonalIcon(
      key: ValueKey('version-download-${file.name}'),
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: widget.sources.isEmpty
          ? null
          : () => unawaited(showUpdateDownload(context, file: file, sources: widget.sources, version: widget.version)),
      icon: const Icon(AppIcons.downloadPackage, size: 18),
      label: Text(i18n('update_download_install')),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 280
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [heading, const SizedBox(height: 8), install],
                  )
                : Row(
                    children: [
                      Expanded(child: heading),
                      const SizedBox(width: 8),
                      install,
                    ],
                  ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: ValueKey('version-sources-${file.name}'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(_open ? AppIcons.foldUp : AppIcons.dropDown, size: 20),
              label: Text(i18n('update_choose_source', args: {'count': '${widget.sources.length}'})),
            ),
          ),
          if (_open)
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width > 800 ? 4 : (width > 500 ? 3 : 2);
                const spacing = 8.0;
                final buttonWidth = (width - spacing * (columns - 1)) / columns;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final (index, source) in widget.sources.indexed)
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
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(12)),
                                ),
                              ),
                              onPressed: () => unawaited(_showSource(context, index, source)),
                              icon: const Icon(AppIcons.downloadSource, size: 16),
                              label: Text(
                                _sourceName(index),
                                style: styles.t13.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  /// One mirror (c8): "ARM64 (64位) · 下载源 3", the file and the address,
  /// then download in the app, in the browser, or copy (3.x needed another
  /// "点击下载" inside).
  Future<void> _showSource(BuildContext pageContext, int index, String url) => showDialog<void>(
    context: pageContext,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      final styles = dialogContext.textStyles;
      final file = widget.file;
      const wide = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)));
      return DialogButtonsTheme(
        child: AlertDialog(
          key: const ValueKey('version-source-dialog'),
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text(
            '${widget.title} · ${_sourceName(index)}',
            style: styles.t18.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(file.name, style: styles.t14.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(url, style: styles.t12.copyWith(color: colors.onSurfaceVariant)),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('version-source-download'),
                  style: wide,
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    unawaited(showUpdateDownload(pageContext, file: file, sources: [url], version: widget.version));
                  },
                  icon: const Icon(AppIcons.downloadPackage, size: 20),
                  label: Text(i18n('update_download_in_app')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('version-source-browser'),
                  style: wide,
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    final uri = updateDownloadUri(url);
                    if (uri != null) unawaited(_openExternal(uri));
                  },
                  icon: const Icon(AppIcons.openInBrowser, size: 20),
                  label: Text(i18n('update_open_in_browser')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('version-source-copy'),
                  style: wide,
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await Clipboard.setData(ClipboardData(text: url));
                    AppNavigator.toast(i18n('copied_to_clipboard'));
                  },
                  icon: const Icon(AppIcons.copy, size: 20),
                  label: Text(i18n('copy_link')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('version-source-cancel'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(i18n('cancel')),
            ),
          ],
        ),
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
