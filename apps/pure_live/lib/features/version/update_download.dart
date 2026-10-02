import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/downloads.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/version/download_directory_dialog.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/plugins.dart' show pickDownloadDirectory;
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// What the update download uses (replaced in tests): the downloader over
/// the app's HTTP client, the folder, and how a finished file is opened.
final class UpdateDownloadTools {
  /// Creates the tools; without [settings] the download folder is not asked
  /// for.
  const new({
    required this.downloader,
    required this.folder,
    this.pickFastest = true,
    this.settings,
    this.defaultFolder,
    this.pickFolder,
  });

  /// Downloads through the app's HTTP client (app proxy, logging).
  final FileDownloader downloader;

  /// The download folder (cache page setting, else the default).
  final Future<Directory> Function() folder;

  /// Whether the fastest mirror is raced for first (off in tests).
  final bool pickFastest;

  /// Where the folder choice is kept ([Settings.downloadDirectoryPath],
  /// [Settings.downloadDirectoryDecisionMade]).
  final SettingsStore? settings;

  /// The platform's default folder.
  final Future<Directory> Function()? defaultFolder;

  /// The system folder picker; null where there is none.
  final Future<String?> Function()? pickFolder;
}

/// The update download's tools.
final Provider<UpdateDownloadTools> updateDownloadToolsProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return UpdateDownloadTools(
    downloader: FileDownloader(services.http, site: 'update'),
    folder: () => resolveDownloadDirectory(services.store.settings, dataRoot: services.dataRoot),
    settings: services.store.settings,
    defaultFolder: () => defaultDownloadDirectory(dataRoot: services.dataRoot),
    pickFolder: pickDownloadDirectory,
  );
});

/// Downloads [file] in the app (3.x `downloadAndInstallApk`): on Android an
/// APK needs "install unknown apps" first (3.x asked before downloading);
/// without a usable download folder the user picks one
/// ([showDownloadDirectoryDialog]); then the download dialog: progress,
/// cancel, resume, then install (Android hands the APK to the system
/// installer, Windows runs the installer) or open its folder. [sources]
/// are the mirrors in order ([downloadSources]); the fastest is tried
/// first. [version] names the download in the dialog. Only one download
/// runs at a time.
Future<void> showUpdateDownload(
  BuildContext context, {
  required ReleaseFile file,
  required List<String> sources,
  String? version,
}) {
  final active = _active;
  if (active != null) return active;
  final uris = [for (final source in sources) ?updateDownloadUri(source)];
  if (uris.isEmpty) {
    AppNavigator.toast(i18n('download_failed'));
    return Future.value();
  }
  return _active = _download(context, file: file, sources: uris, version: version).whenComplete(() => _active = null);
}

Future<void>? _active;

Future<void> _download(
  BuildContext context, {
  required ReleaseFile file,
  required List<Uri> sources,
  String? version,
}) async {
  final tools = ProviderScope.containerOf(context, listen: false).read(updateDownloadToolsProvider);
  final name = safeDownloadFileName(file.url, suggested: file.name);
  if (Platform.isAndroid && name.toLowerCase().endsWith('.apk')) {
    try {
      if (!await SystemAccess.canInstallPackages()) {
        AppNavigator.toast(i18n('grant_install_permission'));
        await SystemAccess.openInstallSettings();
        return;
      }
    } on Object catch (error) {
      AppNavigator.toast('${i18n('request_install_permission_failed')}$error');
      return;
    }
  }
  if (!context.mounted || !await ensureDownloadDirectory(context, tools) || !context.mounted) return;
  await showAppDialog<void>(
    context: context,
    dismissible: false,
    builder: (_) => UpdateDownloadDialog(file: file, sources: sources, version: version),
  );
}

/// Makes sure the download has a folder (3.x `_ensureDownloadDirectorySelected`):
/// asks when the chosen folder is gone or not writable, or when the user
/// never answered and the default folder does not exist yet. "使用默认目录"
/// remembers the default; "选择目录" opens the system picker; cancelling
/// either cancels the download with "未选择下载目录，已取消下载". Whether to go on.
Future<bool> ensureDownloadDirectory(BuildContext context, UpdateDownloadTools tools) async {
  final settings = tools.settings;
  final defaultFolder = tools.defaultFolder;
  if (settings == null || defaultFolder == null) return true;
  final custom = settings.get(Settings.downloadDirectoryPath).trim();
  final bool ask;
  if (custom.isNotEmpty) {
    ask = !Directory(custom).existsSync() || !await canWriteDirectory(Directory(custom));
  } else {
    ask = !settings.get(Settings.downloadDirectoryDecisionMade) && !(await defaultFolder()).existsSync();
  }
  if (!ask) return true;
  final defaultPath = (await defaultFolder()).path;
  if (!context.mounted) return false;
  final pick = tools.pickFolder;
  final choice = await showDownloadDirectoryDialog(context, defaultPath: defaultPath, canPick: pick != null);
  switch (choice) {
    case null:
      AppNavigator.toast(i18n('download_directory_not_selected'));
      return false;
    case DownloadDirectoryChoice.useDefault:
      await settings.setAll({Settings.downloadDirectoryPath: '', Settings.downloadDirectoryDecisionMade: true});
      return true;
    case DownloadDirectoryChoice.pick:
      String? picked;
      try {
        picked = await pick?.call();
      } on Object {
        picked = null;
      }
      if (picked == null || picked.trim().isEmpty) {
        AppNavigator.toast(i18n('download_directory_not_selected'));
        return false;
      }
      await settings.setAll({
        Settings.downloadDirectoryPath: picked.trim(),
        Settings.downloadDirectoryDecisionMade: true,
      });
      if (await canWriteDirectory(Directory(picked.trim()))) return true;
      AppNavigator.toast(i18n('download_directory_permission_hint'));
      return false;
  }
}

/// Where the download dialog is.
enum UpdateDownloadPhase {
  /// Downloading (or preparing).
  downloading,

  /// Stopped by an error; what arrived is kept.
  failed,

  /// The file is complete.
  done,
}

/// From this text scale the dialog stacks its icon over the title and its
/// buttons in a column (3.x did that below 420 wide too, U.3d c10).
const double updateDownloadStackedScale = 1.5;

/// The download dialog of [showUpdateDownload] (3.x `DownloadApkDialog`,
/// docs/A-界面设计/A06-首页和全局/A06.3-全局弹窗): a round icon, a title that follows the state
/// ("正在下载 v…", "v… 已下载", "下载没有完成"), a status line, the progress
/// box with the percentage, and the buttons of the state; the same layout
/// at every width (c10). Back and Esc are the dialog's own cancel or close
/// (c7).
class UpdateDownloadDialog extends ConsumerStatefulWidget {
  /// Creates the dialog.
  const new({required this.file, required this.sources, this.version, super.key});

  /// The package.
  final ReleaseFile file;

  /// Where it can be downloaded, in order.
  final List<Uri> sources;

  /// The version, for the title; the file name without it.
  final String? version;

  @override
  ConsumerState<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

typedef _Progress = ({int received, int? total});

class _UpdateDownloadDialogState extends ConsumerState<UpdateDownloadDialog> {
  UpdateDownloadPhase _phase = UpdateDownloadPhase.downloading;
  CancelToken _cancel = CancelToken();
  final ValueNotifier<_Progress> _progress = ValueNotifier((received: 0, total: null));
  File? _file;
  String? _message;
  bool _messageIsError = false;
  bool _opening = false;
  bool _openFailed = false;

  late final String _name = safeDownloadFileName(widget.file.url, suggested: widget.file.name);

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _cancel.cancel();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final tools = ref.read(updateDownloadToolsProvider);
    setState(() {
      _phase = UpdateDownloadPhase.downloading;
      _cancel = CancelToken();
      _message = null;
      _messageIsError = false;
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
          if (mounted) _progress.value = (received: received, total: total);
        },
      );
      if (!mounted) return;
      setState(() {
        _phase = UpdateDownloadPhase.done;
        _file = done;
        _message = null;
        _openFailed = false;
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
      _phase = UpdateDownloadPhase.failed;
      _message = message;
      _messageIsError = true;
    });
  }

  /// Android: the system installer (asks for "install unknown apps" first);
  /// Windows: runs the installer; a ZIP opens its folder.
  Future<void> _install() async {
    final file = _file;
    if (file == null || _opening) return;
    if (Platform.isAndroid && file.path.toLowerCase().endsWith('.apk') && !await SystemAccess.canInstallPackages()) {
      AppNavigator.toast(i18n('grant_install_permission'));
      await SystemAccess.openInstallSettings();
      return;
    }
    if (file.path.toLowerCase().endsWith('.zip')) {
      await _openFolder();
      return;
    }
    setState(() {
      _opening = true;
      _message = i18n('download_complete_opening');
      _messageIsError = false;
    });
    var opened = false;
    try {
      opened = await AppNavigator.openFile(file.path);
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _opening = false;
      _openFailed = true;
      _message = i18n('download_open_failed');
      _messageIsError = true;
    });
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
      setState(() {
        _message = i18n('download_open_folder_failed', args: {'path': file.parent.path});
        _messageIsError = false;
      });
    }
  }

  Future<void> _openInBrowser() async {
    final opened = await AppNavigator.openExternal(widget.sources.last);
    if (!opened) AppNavigator.toast(i18n('external_browser_not_opened'));
  }

  /// Stops the download (what arrived stays for a later resume) and closes.
  void _cancelDownload() {
    _cancel.cancel();
    Navigator.of(context).pop();
    AppNavigator.toast(i18n('update_download_paused'));
  }

  void _close() => Navigator.of(context).pop();

  /// Enter: the state's main button (install, reopen, retry); nothing while
  /// downloading or opening.
  void _mainAction() {
    if (_opening) return;
    switch (_phase) {
      case UpdateDownloadPhase.done:
        unawaited(_install());
      case UpdateDownloadPhase.failed:
        unawaited(_start());
      case UpdateDownloadPhase.downloading:
        break;
    }
  }

  /// Back and Esc: the dialog's own cancel or close.
  void _onBack() {
    if (_opening) return;
    if (_phase == UpdateDownloadPhase.downloading) {
      _cancelDownload();
    } else {
      _close();
    }
  }

  String _title() {
    final version = widget.version;
    return switch (_phase) {
      UpdateDownloadPhase.failed => i18n('update_download_incomplete'),
      UpdateDownloadPhase.done => version == null ? _name : i18n('update_downloaded_title', args: {'version': version}),
      UpdateDownloadPhase.downloading =>
        version == null
            ? i18n('downloading_app', args: {'app': _name})
            : i18n('update_downloading_title', args: {'version': version}),
    };
  }

  static String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

  String _status(_Progress progress) {
    if (_message case final message?) return message;
    if (_phase == UpdateDownloadPhase.done) return i18n('download_complete');
    final total = progress.total;
    if (total != null && total > 0) return '${_mb(progress.received)} MB / ${_mb(total)} MB';
    if (progress.received > 0) return i18n('downloaded_mb', args: {'mb': _mb(progress.received)});
    return i18n('download_preparing');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = context.textStyles;
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 10 * updateDownloadStackedScale;
    final error = _phase == UpdateDownloadPhase.failed || _openFailed;
    final busy = _phase == UpdateDownloadPhase.downloading || _opening;

    final icon = Container(
      key: const ValueKey('update-download-icon'),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (error ? scheme.error : scheme.primary).withValues(alpha: 0.1),
      ),
      alignment: Alignment.center,
      child: busy
          ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary))
          : Icon(error ? AppIcons.downloadFailed : AppIcons.downloadDone, color: error ? scheme.error : scheme.primary),
    );
    final heading = ValueListenableBuilder<_Progress>(
      valueListenable: _progress,
      builder: (context, progress, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title(),
            key: const ValueKey('update-download-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: styles.t15.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            _status(progress),
            key: const ValueKey('update-download-message'),
            style: styles.t14.copyWith(color: _messageIsError ? scheme.error : scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
    final progressBox = ValueListenableBuilder<_Progress>(
      valueListenable: _progress,
      builder: (context, progress, _) {
        final total = progress.total;
        final value = _phase == UpdateDownloadPhase.done
            ? 1.0
            : (total != null && total > 0)
            ? (progress.received / total).clamp(0.0, 1.0)
            : (_phase == UpdateDownloadPhase.failed ? 0.0 : null);
        final failed = _phase == UpdateDownloadPhase.failed;
        final bar = LinearProgressIndicator(
          key: const ValueKey('update-download-bar'),
          value: value,
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
          backgroundColor: scheme.surfaceContainerHighest,
          color: failed ? scheme.outline : scheme.primary,
        );
        final percent = Text(
          value == null ? '…' : '${(value * 100).round()}%',
          key: const ValueKey('update-download-progress'),
          textAlign: stacked ? TextAlign.start : TextAlign.end,
          style: styles.t14.tabular.copyWith(
            fontWeight: FontWeight.w700,
            color: failed ? scheme.onSurfaceVariant : scheme.primary,
          ),
        );
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [bar, const SizedBox(height: 8), percent],
                )
              : Row(
                  children: [
                    Expanded(child: bar),
                    const SizedBox(width: 16),
                    SizedBox(width: 48, child: percent),
                  ],
                ),
        );
      },
    );

    final close = TextButton(
      key: const ValueKey('update-download-close'),
      style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
      onPressed: _close,
      child: Text(i18n('close')),
    );
    final List<Widget> leading;
    final List<Widget> trailing;
    switch (_phase) {
      case UpdateDownloadPhase.downloading:
        leading = const [];
        trailing = [
          TextButton(
            key: const ValueKey('update-download-cancel'),
            onPressed: _cancelDownload,
            child: Text(i18n('cancel')),
          ),
        ];
      case UpdateDownloadPhase.failed:
        leading = [close];
        trailing = [
          TextButton(
            key: const ValueKey('update-download-browser'),
            onPressed: () => unawaited(_openInBrowser()),
            child: Text(i18n('update_open_in_browser')),
          ),
          FilledButton.icon(
            key: const ValueKey('update-download-retry'),
            onPressed: () => unawaited(_start()),
            icon: const Icon(AppIcons.retry, size: 18),
            label: Text(i18n('retry')),
          ),
        ];
      case UpdateDownloadPhase.done when _opening:
        leading = const [];
        trailing = [
          FilledButton.icon(
            key: const ValueKey('update-download-opening'),
            onPressed: null,
            icon: const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            label: Text(i18n('update_opening')),
          ),
        ];
      case UpdateDownloadPhase.done when _openFailed:
        leading = [close];
        trailing = [
          FilledButton.icon(
            key: const ValueKey('update-download-install'),
            onPressed: () => unawaited(_install()),
            icon: const Icon(AppIcons.install, size: 18),
            label: Text(i18n('download_open_again')),
          ),
        ];
      case UpdateDownloadPhase.done:
        leading = [close];
        trailing = [
          TextButton(
            key: const ValueKey('update-download-folder'),
            onPressed: () => unawaited(_openFolder()),
            child: Text(i18n('open_folder')),
          ),
          FilledButton.icon(
            key: const ValueKey('update-download-install'),
            onPressed: () => unawaited(_install()),
            icon: const Icon(AppIcons.install, size: 18),
            label: Text(i18n('install')),
          ),
        ];
    }
    final actions = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final button in [...trailing.reversed, ...leading]) ...[const SizedBox(height: 8), button],
            ],
          )
        : Row(
            children: [
              ...leading,
              // At the right, wrapping to a second line with a large font.
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: trailing,
                ),
              ),
            ],
          );

    return DialogButtonsTheme(
      child: DialogKeys(
        onEnter: _mainAction,
        // Not closed by a tap outside, so the route gives it no Esc.
        onEscape: _onBack,
        child: PopScope<Object?>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _onBack();
          },
          child: Dialog(
            key: const ValueKey('update-download-dialog'),
            insetPadding: const EdgeInsets.all(appDialogMargin),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (stacked) ...[
                      Align(alignment: Alignment.centerLeft, child: icon),
                      const SizedBox(height: 12),
                      heading,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: 16),
                          Expanded(child: heading),
                        ],
                      ),
                    const SizedBox(height: 20),
                    progressBox,
                    const SizedBox(height: 8),
                    actions,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
