import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/downloads.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/version/update_feed.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// What the update download uses (replaced in tests): the downloader over
/// the app's HTTP client, the folder, and how a finished file is opened.
final class UpdateDownloadTools {
  /// Creates the tools.
  const new({required this.downloader, required this.folder, this.pickFastest = true});

  /// Downloads through the app's HTTP client (app proxy, logging).
  final FileDownloader downloader;

  /// The download folder (cache page setting, else the default).
  final Future<Directory> Function() folder;

  /// Whether the fastest mirror is raced for first (off in tests).
  final bool pickFastest;
}

/// The update download's tools.
final Provider<UpdateDownloadTools> updateDownloadToolsProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return UpdateDownloadTools(
    downloader: FileDownloader(services.http, site: 'update'),
    folder: () => resolveDownloadDirectory(services.store.settings, dataRoot: services.dataRoot),
  );
});

/// Downloads [file] in the app (3.x `downloadAndInstallApk`): progress,
/// cancel, resume, then install (Android hands the APK to the system
/// installer, Windows runs the installer) or open its folder (desktop).
/// [sources] are the mirrors in order ([downloadSources]); the fastest is
/// tried first. Only one download runs at a time.
Future<void> showUpdateDownload(BuildContext context, {required ReleaseFile file, required List<String> sources}) {
  final active = _active;
  if (active != null) return active;
  final uris = [for (final source in sources) ?updateDownloadUri(source)];
  if (uris.isEmpty) {
    AppNavigator.toast(i18n('download_failed'));
    return Future.value();
  }
  final shown = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDownloadDialog(file: file, sources: uris),
  ).whenComplete(() => _active = null);
  return _active = shown;
}

Future<void>? _active;

/// The download dialog of [showUpdateDownload].
class UpdateDownloadDialog extends ConsumerStatefulWidget {
  /// Creates the dialog.
  const new({required this.file, required this.sources, super.key});

  /// The package.
  final ReleaseFile file;

  /// Where it can be downloaded, in order.
  final List<Uri> sources;

  @override
  ConsumerState<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

enum _Phase { downloading, failed, done }

class _UpdateDownloadDialogState extends ConsumerState<UpdateDownloadDialog> {
  _Phase _phase = _Phase.downloading;
  CancelToken _cancel = CancelToken();
  int _received = 0;
  int? _total;
  File? _file;
  String _message = '';
  bool _opening = false;

  late final String _name = safeDownloadFileName(widget.file.url, suggested: widget.file.name);

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final tools = ref.read(updateDownloadToolsProvider);
    setState(() {
      _phase = _Phase.downloading;
      _cancel = CancelToken();
      _message = i18n('download_preparing');
    });
    final cancel = _cancel;
    try {
      final folder = await tools.folder();
      if (!await canWriteDirectory(folder)) {
        _fail(i18n('download_directory_permission_hint'));
        return;
      }
      var sources = widget.sources;
      if (tools.pickFastest && sources.length > 1) {
        final http = tools.downloader.http;
        final fastest = await fastestUrl(http, 'update', sources, timeout: const Duration(seconds: 10));
        if (fastest != null) sources = [fastest, ...sources.where((uri) => uri != fastest)];
      }
      if (cancel.isCancelled) return;
      final target = File(p.join(folder.path, _name));
      final done = await tools.downloader.download(
        sources.take(6).toList(),
        target,
        cancel: cancel,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _file = done;
        _message = i18n('download_complete');
      });
    } on DownloadException catch (error) {
      if (error.reason == DownloadFailure.cancelled) return;
      _fail(
        error.reason == DownloadFailure.disk
            ? i18n('download_directory_permission_hint')
            : i18n('update_download_failed_resume'),
      );
    } on Object {
      _fail(i18n('update_download_failed_resume'));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _message = message;
    });
  }

  /// Android: the system installer (asks for "install unknown apps" first);
  /// Windows: runs the installer; a ZIP opens its folder.
  Future<void> _install() async {
    final file = _file;
    if (file == null || _opening) return;
    setState(() => _opening = true);
    try {
      if (Platform.isAndroid && file.path.toLowerCase().endsWith('.apk') && !await SystemAccess.canInstallPackages()) {
        AppNavigator.toast(i18n('grant_install_permission'));
        await SystemAccess.openInstallSettings();
        return;
      }
      if (file.path.toLowerCase().endsWith('.zip')) {
        await _openFolder();
        return;
      }
      setState(() => _message = i18n('download_complete_opening'));
      final opened = await AppNavigator.openFile(file.path);
      if (!mounted) return;
      if (opened) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _message = i18n('download_open_failed'));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openFolder() async {
    final file = _file;
    if (file == null) return;
    var opened = false;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', ['/select,', file.path]);
        opened = true;
      } else {
        opened = await AppNavigator.openExternal(Uri.directory(file.parent.path));
      }
    } on Object {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() => _message = i18n('download_open_folder_failed', args: {'path': file.parent.path}));
    }
  }

  Future<void> _openInBrowser() async {
    final opened = await AppNavigator.openExternal(widget.sources.last);
    if (!opened) AppNavigator.toast(i18n('external_browser_not_opened'));
  }

  String get _progressText {
    String mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);
    final total = _total;
    if (total != null && total > 0) return '${mb(_received)} MB / ${mb(total)} MB';
    if (_received > 0) return i18n('downloaded_mb', args: {'mb': mb(_received)});
    return _message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;
    final progress = total != null && total > 0 ? (_received / total).clamp(0.0, 1.0) : null;
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return PopScope(
      canPop: _phase != _Phase.downloading,
      child: AlertDialog(
        key: const ValueKey('update-download-dialog'),
        title: Text(i18n('downloading_app', args: {'app': _name}), maxLines: 2, overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_phase == _Phase.downloading) ...[
                LinearProgressIndicator(value: progress, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 10),
                Text(_progressText, key: const ValueKey('update-download-progress'), style: context.textStyles.t13),
              ] else ...[
                Row(
                  children: [
                    Icon(
                      _phase == _Phase.done ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      color: _phase == _Phase.done ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _message,
                        key: const ValueKey('update-download-message'),
                        style: context.textStyles.t13,
                      ),
                    ),
                  ],
                ),
                if (_file case final file?) ...[
                  const SizedBox(height: 10),
                  SelectableText(file.path, style: context.textStyles.t11.copyWith(color: theme.hintColor)),
                ],
              ],
            ],
          ),
        ),
        actions: switch (_phase) {
          _Phase.downloading => [
            TextButton(
              key: const ValueKey('update-download-cancel'),
              onPressed: () {
                _cancel.cancel();
                Navigator.of(context).pop();
                AppNavigator.toast(i18n('update_download_paused'));
              },
              child: Text(i18n('cancel')),
            ),
          ],
          _Phase.failed => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('close'))),
            TextButton(
              key: const ValueKey('update-download-browser'),
              onPressed: () => unawaited(_openInBrowser()),
              child: Text(i18n('update_open_in_browser')),
            ),
            FilledButton(
              key: const ValueKey('update-download-retry'),
              onPressed: () => unawaited(_start()),
              child: Text(i18n('retry')),
            ),
          ],
          _Phase.done => [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('close'))),
            if (desktop)
              TextButton(
                key: const ValueKey('update-download-folder'),
                onPressed: () => unawaited(_openFolder()),
                child: Text(i18n('open_folder')),
              ),
            FilledButton.icon(
              key: const ValueKey('update-download-install'),
              onPressed: _opening ? null : () => unawaited(_install()),
              icon: const Icon(Icons.install_mobile_rounded),
              label: Text(i18n('install')),
            ),
          ],
        },
      ),
    );
  }
}
