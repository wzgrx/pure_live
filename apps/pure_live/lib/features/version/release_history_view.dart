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

/// From this width of the page the history shows the list and the details
/// side by side (docs/ui/compare/U.12b c10, N3 A: the plan's "expanded"
/// width of the parent; 3.x used the whole screen's 760).
const double releaseHistorySplitWidth = 840;

/// Every release with its notes and files (3.x `VersionHistoryPage`,
/// docs/ui/compare/U.12b "版本历史"): a list (a release opens in a dialog
/// whose close button is at the top right), or the list and the details
/// side by side from [releaseHistorySplitWidth]. The newest release is
/// marked "最新", the installed one "当前" (c11).
class ReleaseHistoryView extends ConsumerStatefulWidget {
  /// Creates the view.
  const new({super.key});

  @override
  ConsumerState<ReleaseHistoryView> createState() => _ReleaseHistoryViewState();
}

class _ReleaseHistoryViewState extends ConsumerState<ReleaseHistoryView> {
  List<ReleaseInfo> _releases = const [];
  bool _loading = false;
  bool _failed = false;
  String? _selected;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    List<ReleaseInfo>? releases;
    try {
      releases = await ref.read(updateFeedProvider).releases();
    } on Object {
      releases = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (releases == null) {
        _failed = true;
        // A failed refresh keeps the list it had (3.x).
        if (_releases.isNotEmpty) AppNavigator.toast(i18n('version_history_load_failed'));
      } else {
        _releases = releases;
        if (!releases.any((release) => release.version == _selected)) _selected = releases.firstOrNull?.version;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height < 480;
    return Scaffold(
      appBar: AppBar(
        // 3.x's app bars centre the title (common/style/theme.dart:119).
        centerTitle: true,
        toolbarHeight: short ? 48 : null,
        title: Text(i18n('version_history'), maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('release-history-refresh'),
            tooltip: i18n('refresh'),
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(AppIcons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          return _body(constraints.maxWidth >= releaseHistorySplitWidth && textScale <= 1.5);
        },
      ),
    );
  }

  Widget _body(bool wide) {
    if (_releases.isEmpty) {
      if (_loading) return const AppStatusView(type: AppStatusType.loading);
      if (_failed) return AppStatusView(type: AppStatusType.error, onButtonPressed: _load);
      return const AppStatusView(type: AppStatusType.empty);
    }
    final selected = _releases.firstWhere((release) => release.version == _selected, orElse: () => _releases.first);
    return Stack(
      children: [
        Positioned.fill(child: wide ? _wide(selected) : _narrow()),
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(key: ValueKey('release-history-refresh-progress'), minHeight: 2),
          ),
      ],
    );
  }

  /// The newest release is the first (by date, then version).
  bool _latest(ReleaseInfo release) => identical(release, _releases.first);

  Widget _wide(ReleaseInfo selected) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('release-history-desktop-layout'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: ListView.builder(
            physics: const PureLiveScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: _releases.length,
            itemBuilder: (context, index) {
              final release = _releases[index];
              final current = identical(release, selected);
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: current ? colors.primaryContainer.withValues(alpha: 0.35) : colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    side: current ? BorderSide(color: colors.primary, width: 1.5) : BorderSide.none,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('release-history-desktop-${release.version}'),
                    onTap: () => setState(() => _selected = release.version),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: _VersionLine(release: release, latest: _latest(release), highlighted: current),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant.withValues(alpha: 0.6)),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                key: ValueKey('release-history-detail-${selected.version}'),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReleaseHeader(release: selected),
                    const SizedBox(height: 16),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: const BorderRadius.all(Radius.circular(16)),
                        ),
                        child: SingleChildScrollView(
                          physics: const PureLiveScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          child: _ReleaseBody(release: selected),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _narrow() => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final side = math.max(16, (constraints.maxWidth - readableContentMaxWidth) / 2).toDouble();
      final last = _releases.length - 1;
      return ListView.builder(
        key: const ValueKey('release-history-mobile-list'),
        physics: const PureLiveScrollPhysics(),
        padding: EdgeInsets.fromLTRB(side, 8, side, 24),
        itemCount: _releases.length,
        // One card, the releases on it divided by lines.
        itemBuilder: (context, index) {
          final release = _releases[index];
          return Material(
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: index == 0 ? const Radius.circular(16) : Radius.zero,
                bottom: index == last ? const Radius.circular(16) : Radius.zero,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('release-history-mobile-${release.version}'),
              onTap: () => unawaited(_showDetails(release)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: index == last
                      ? null
                      : Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7))),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _VersionLine(release: release, latest: _latest(release), highlighted: false),
                      ),
                      Icon(AppIcons.forward, size: 22, color: colors.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  /// One release on a phone (c12): the close button at the top right next
  /// to the release page, the rest scrolls on its own; Back, Esc and a tap
  /// outside close it too (3.x put "关闭" after everything).
  Future<void> _showDetails(ReleaseInfo release) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final media = MediaQuery.of(dialogContext);
      return Dialog(
        key: const ValueKey('release-history-detail-dialog'),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: math.min(680, media.size.width - 32),
          height: math.max(240, math.min(640, media.size.height - media.padding.vertical - 48)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: _ReleaseHeader(release: release, onClose: () => Navigator.of(dialogContext).pop()),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('release-history-detail-scroll'),
                  physics: const PureLiveScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _ReleaseBody(release: release),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A small filled mark after a version ("最新", "当前").
class _Badge extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          text,
          style: context.textStyles.t12.copyWith(color: colors.onPrimaryContainer, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// The version with "最新" or "当前", and "发布于 date" (c11; 3.x wrote the
/// size of the release's first file, which may be another platform's).
class _VersionLine extends StatelessWidget {
  const new({required this.release, required this.latest, required this.highlighted});

  final ReleaseInfo release;
  final bool latest;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final installed = compareVersions(release.version, appVersion) == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'v${release.version}',
              style: styles.t16.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: highlighted ? colors.primary : colors.onSurface,
              ),
            ),
            if (latest) _Badge(key: ValueKey('release-latest-${release.version}'), i18n('version_latest_badge')),
            if (installed) _Badge(key: ValueKey('release-current-${release.version}'), i18n('version_current_badge')),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          i18n('version_published_at', args: {'date': release.date}),
          style: styles.t13.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Publisher, version, date and the release page button; [onClose] adds
/// the close button at the end (the phone's dialog).
class _ReleaseHeader extends StatelessWidget {
  const new({required this.release, this.onClose});

  final ReleaseInfo release;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final page = updateDownloadUri(release.github);
    final avatar = updateDownloadUri(release.authorAvatar);
    final placeholder = Icon(AppIcons.releaseAuthor, size: 18, color: colors.onSurfaceVariant);
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: colors.surfaceContainerHighest,
          child: avatar == null
              ? placeholder
              : ClipOval(
                  child: Image.network(
                    avatar.toString(),
                    width: 36,
                    height: 36,
                    cacheWidth: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'v${release.version}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: styles.t16.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              Text(
                i18n('version_published_at', args: {'date': release.date}),
                style: styles.t13.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('release-history-open-release'),
          tooltip: i18n('version_history_open_release'),
          style: onClose == null ? IconButton.styleFrom(backgroundColor: colors.surfaceContainerHigh) : null,
          onPressed: page == null ? null : () => unawaited(_open(page)),
          icon: const Icon(AppIcons.releasePage, size: 20),
        ),
        if (onClose case final close?)
          IconButton(
            key: const ValueKey('release-history-close-details'),
            tooltip: i18n('close'),
            onPressed: close,
            icon: const Icon(AppIcons.close),
          ),
      ],
    );
  }
}

/// The notes and the files of a release.
class _ReleaseBody extends StatelessWidget {
  const new({required this.release});

  final ReleaseInfo release;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MarkdownText(release.changelog),
      if (release.files.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(i18n('download_files'), style: context.textStyles.t15.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        for (final (index, file) in release.files.indexed)
          _FileCard(key: ValueKey('release-history-file-$index'), file: file, version: release.version),
      ],
    ],
  );
}

class _FileCard extends ConsumerWidget {
  const new({required this.file, required this.version, super.key});

  final ReleaseFile file;
  final String version;

  String get _name => file.name.isEmpty ? i18n('version_history_unnamed_file') : file.name;

  /// c13: says what is downloaded and what happens after (3.x asked
  /// "点击下载" twice), then downloads in the app like 3.x
  /// (`downloadAndInstallApk`, U.3d's dialog).
  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => DialogButtonsTheme(
        child: AlertDialog(
          key: const ValueKey('release-download-confirm'),
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text(
            i18n('update_download_package_title'),
            style: dialogContext.textStyles.t18.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              i18n('update_download_confirm_named', args: {'name': _name, 'size': file.size}),
              style: dialogContext.textStyles.t14,
            ),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              key: const ValueKey('release-download-cancel'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(i18n('cancel')),
            ),
            FilledButton(
              key: const ValueKey('release-download-start'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(i18n('update_download_action')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final githubOrigin = ref.read(appServicesProvider).store.settings.get(Settings.useGitHubOriginForUpdates);
    await showUpdateDownload(
      context,
      file: file,
      sources: downloadSources(file.url, githubOrigin: githubOrigin),
      version: version,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final uri = updateDownloadUri(file.url);
    final round = IconButton.styleFrom(backgroundColor: colors.surfaceContainerHighest);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(AppIcons.releaseFile, color: colors.primary, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name, style: styles.t14.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      i18n('version_downloads_count', args: {'size': file.size, 'count': '${file.downloads}'}),
                      style: styles.t12.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('release-file-copy'),
                tooltip: i18n('copy_link'),
                style: round,
                onPressed: uri == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: uri.toString()));
                        AppNavigator.toast(i18n('copied_to_clipboard'));
                      },
                icon: Icon(AppIcons.copy, size: 20, color: colors.primary),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('release-file-download'),
                tooltip: i18n('update_download_action'),
                style: round,
                onPressed: uri == null ? null : () => unawaited(_download(context, ref)),
                icon: Icon(AppIcons.downloadPackage, size: 20, color: colors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _open(Uri uri) async {
  var opened = false;
  try {
    opened = await AppNavigator.openExternal(uri);
  } on Object {
    opened = false;
  }
  if (!opened) AppNavigator.toast(i18n('external_browser_not_opened'));
}
