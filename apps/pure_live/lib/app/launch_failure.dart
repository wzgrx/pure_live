import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Runs [start] (the services and everything else before the first frame).
/// When it throws (storage that cannot be opened: a full disk, a damaged or
/// locked database), the error goes to the app log and [show] (`runApp`)
/// puts up [LaunchFailureApp] instead of leaving the splash screen up for
/// good; its "重试" calls [retry] and "导出日志" [exportLog]. Returns what
/// [start] made, or null after a failure.
Future<T?> launchOrExplain<T extends Object>(
  Future<T> Function() start, {
  required void Function(Widget app) show,
  required Future<void> Function() retry,
  required Future<String?> Function() exportLog,
}) async {
  try {
    return await start();
  } on Object catch (error, stack) {
    AppLog.instance.add(LogLevel.error, 'startup', 'The app could not start', error, stack);
    if (!i18nExists('retry')) {
      // The settings never opened: the system's language.
      try {
        final language = AppLanguage.resolve(stored: null, preferred: PlatformDispatcher.instance.locales);
        currentStrings = await AppStrings.load(language, rootBundle);
      } on Object {
        // The keys show instead.
      }
    }
    show(LaunchFailureApp(error: error, onRetry: retry, onExportLog: exportLog));
    return null;
  }
}

/// Why the app could not start, in the user's words: the folder and the
/// system's reason for a file error, else the error itself (shortened).
String launchFailureReason(Object error) {
  String shorten(String text) {
    final line = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return line.length <= 240 ? line : '${line.substring(0, 240)}…';
  }

  if (error case FileSystemException(:final message, :final path, :final osError)) {
    final system = osError?.message ?? '';
    final detail = system.isNotEmpty ? system : message;
    return i18n('launch_failed_files', args: {'path': path ?? '', 'detail': shorten(detail)});
  }
  return i18n('launch_failed_data', args: {'detail': shorten('$error')});
}

/// The app in place of the usual one when the start failed (release fixes,
/// item 7): the reason, "重试" and "导出日志".
class LaunchFailureApp extends StatelessWidget {
  /// Creates the app for [error].
  const new({required this.error, required this.onRetry, required this.onExportLog, super.key});

  /// What went wrong.
  final Object error;

  /// Starts again.
  final Future<void> Function() onRetry;

  /// Exports the log; the message to show, if any.
  final Future<String?> Function() onExportLog;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: const LiveTheme().light,
    darkTheme: const LiveTheme().dark,
    home: LaunchFailurePage(error: error, onRetry: onRetry, onExportLog: onExportLog),
  );
}

/// The page of [LaunchFailureApp].
class LaunchFailurePage extends StatefulWidget {
  /// Creates the page for [error].
  const new({required this.error, required this.onRetry, required this.onExportLog, super.key});

  /// What went wrong.
  final Object error;

  /// Starts again.
  final Future<void> Function() onRetry;

  /// Exports the log; the message to show, if any.
  final Future<String?> Function() onExportLog;

  @override
  State<LaunchFailurePage> createState() => _LaunchFailurePageState();
}

class _LaunchFailurePageState extends State<LaunchFailurePage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    String? message;
    try {
      message = await widget.onExportLog();
    } on Object {
      message = i18n('settings_log_export_failed');
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AppStatusView(
          type: AppStatusType.error,
          icon: AppIcons.warning,
          title: i18n('launch_failed_title'),
          subtitle: '${launchFailureReason(widget.error)}\n${i18n('launch_failed_hint')}',
          buttonText: i18n('retry'),
          onButtonPressed: _busy ? null : () => _run(widget.onRetry),
          secondaryButtonText: i18n('launch_failed_export'),
          onSecondaryButtonPressed: _busy ? null : () => _run(_export),
        ),
      ),
    ),
  );
}
