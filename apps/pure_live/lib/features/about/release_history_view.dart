import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/markdown_text.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Every release with its notes and files (3.x `VersionHistoryPage`): a
/// list on phones (a release opens in a dialog), list and details side by
/// side on wide windows.
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
    final media = MediaQuery.of(context);
    final textScale = media.textScaler.scale(1);
    final wide = media.size.width > 760 && textScale <= 1.5;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: textScale <= 1.5 ? kToolbarHeight : math.min(152, 44 + 36 * textScale),
        title: Text(i18n('version_history_desc'), maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('release-history-refresh'),
            tooltip: i18n('refresh'),
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _body(wide),
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

  Widget _wide(ReleaseInfo selected) {
    final theme = Theme.of(context);
    return Row(
      key: const ValueKey('release-history-desktop-layout'),
      children: [
        Container(
          width: 320,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4))),
          ),
          child: ListView.builder(
            physics: const PureLiveScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: _releases.length,
            itemBuilder: (context, index) {
              final release = _releases[index];
              final current = identical(release, selected);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  key: ValueKey('release-history-desktop-${release.version}'),
                  onTap: () => setState(() => _selected = release.version),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: current ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: current ? theme.colorScheme.primary : Colors.transparent, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _VersionLine(release: release, highlighted: current),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: current ? theme.colorScheme.primary : theme.colorScheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: Padding(
            key: ValueKey('release-history-detail-${selected.version}'),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReleaseHeader(release: selected),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      physics: const PureLiveScrollPhysics(),
                      child: _ReleaseBody(release: selected),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _narrow() {
    final theme = Theme.of(context);
    return ListView.separated(
      key: const ValueKey('release-history-mobile-list'),
      physics: const PureLiveScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _releases.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final release = _releases[index];
        return InkWell(
          key: ValueKey('release-history-mobile-${release.version}'),
          onTap: () => unawaited(_showDetails(release)),
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(child: _VersionLine(release: release, highlighted: false)),
                Icon(Icons.chevron_right_rounded, size: 18, color: theme.colorScheme.outline),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDetails(ReleaseInfo release) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final media = MediaQuery.of(dialogContext);
      final theme = Theme.of(dialogContext);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        child: SizedBox(
          width: math.min(680, media.size.width - 32),
          height: math.max(240, math.min(640, media.size.height - media.padding.vertical - 48)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('release-history-detail-scroll'),
                  physics: const PureLiveScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReleaseHeader(release: release),
                      const SizedBox(height: 8),
                      _ReleaseBody(release: release),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('release-history-close-details'),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(i18n('close'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The version, date and size of a release, marked when it is installed.
class _VersionLine extends StatelessWidget {
  const new({required this.release, required this.highlighted});

  final ReleaseInfo release;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = compareVersions(release.version, appVersion) == 0;
    final size = release.files.where((file) => file.name.toLowerCase().endsWith('.apk')).firstOrNull?.size;
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
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: highlighted ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
            ),
            if (installed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  i18n('about_installed_version'),
                  style: context.textStyles.t11.copyWith(color: theme.colorScheme.primary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          [
            release.date,
            if (size != null) i18n('version_file_size', args: {'size': size}),
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Publisher, version, date and the release page button.
class _ReleaseHeader extends StatelessWidget {
  const new({required this.release});

  final ReleaseInfo release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = updateDownloadUri(release.github);
    final avatar = updateDownloadUri(release.authorAvatar);
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: avatar == null
              ? Icon(Icons.person_outline_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant)
              : ClipOval(
                  child: Image.network(
                    avatar.toString(),
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.person_outline_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
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
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                i18n('version_published_at', args: {'date': release.date}),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('release-history-open-release'),
          tooltip: i18n('version_history_open_release'),
          onPressed: page == null ? null : () => unawaited(_open(page)),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarkdownText(release.changelog),
        if (release.files.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(i18n('download_files'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final (index, file) in release.files.indexed)
            _FileCard(key: ValueKey('release-history-file-$index'), file: file),
        ],
      ],
    );
  }
}

class _FileCard extends StatelessWidget {
  const new({required this.file, super.key});

  final ReleaseFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uri = updateDownloadUri(file.url);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: theme.colorScheme.surfaceContainer),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name.isEmpty ? i18n('version_history_unnamed_file') : file.name,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  i18n('version_downloads_count', args: {'size': file.size, 'count': '${file.downloads}'}),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: i18n('copy_link'),
            onPressed: uri == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: uri.toString()));
                    AppNavigator.toast(i18n('copied_to_clipboard'));
                  },
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
          IconButton(
            tooltip: i18n('download'),
            onPressed: uri == null ? null : () => unawaited(_open(uri)),
            icon: const Icon(Icons.download_rounded, size: 18),
          ),
        ],
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
