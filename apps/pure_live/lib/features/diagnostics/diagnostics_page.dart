import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/diagnostics/app_log.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_bundle.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The app-wide log (main() opens the file log before the first frame).
final appLogProvider = Provider<AppLog>((ref) => AppLog.current);

/// Exports the diagnostics bundle through the system save dialog; returns
/// whether it was saved.
Future<bool> exportDiagnostics(WidgetRef ref) async {
  final now = DateTime.now();
  final document = await DiagnosticsBundle.build(
    store: ref.read(storeProvider),
    log: ref.read(appLogProvider),
    now: now,
  );
  final saved = await FilePicker.saveFile(
    dialogTitle: t.diagnostics.saveBundle,
    fileName: DiagnosticsBundle.fileName(now),
    mimeType: 'application/json',
    type: FileType.custom,
    allowedExtensions: const ['json'],
    bytes: Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(document))),
  );
  return saved != null;
}

/// 诊断与日志 (F-BAK-02, F-NEW-11): export a diagnostics bundle, the crash
/// prompt switch (off by default, nothing is uploaded) and the recent log.
class DiagnosticsPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  bool _busy = false;

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      if (await exportDiagnostics(ref)) _toast(t.diagnostics.bundleSaved);
    } on Object catch (error, stack) {
      ref.read(appLogProvider).error('diagnostics', 'export failed', error, stack);
      _toast(t.diagnostics.exportFailed(error: error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    await ref.read(appLogProvider).clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPrefsProvider);
    final lines = ref.watch(appLogProvider).recent.reversed.take(200).toList();
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return Scaffold(
      appBar: PageAppBar(maxContentWidth: Sizes.readingWidth, title: Text(t.backup.diagnostics)),
      body: PageBody(
        maxContentWidth: Sizes.readingWidth,
        child: ListView(
          children: [
            if (_busy) const LinearProgressIndicator(),
            ListTile(
              leading: const Icon(Icons.medical_information_outlined),
              title: Text(t.diagnostics.exportBundle),
              subtitle: Text(t.diagnostics.exportBundleSubtitle),
              enabled: !_busy,
              onTap: _export,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: Text(t.backup.crashReports),
              subtitle: Text(t.diagnostics.crashReportsSubtitle),
              value: prefs.crashReports,
              onChanged: (value) => ref.read(appPrefsProvider.notifier).setCrashReports(enabled: value),
            ),
            const Divider(),
            ListTile(
              title: Text(t.diagnostics.recentLogs),
              subtitle: Text(t.diagnostics.recentLogsSubtitle),
              trailing: TextButton(onPressed: lines.isEmpty ? null : _clear, child: Text(t.common.clear)),
            ),
            if (lines.isEmpty)
              Padding(padding: const EdgeInsets.all(Space.s4), child: Text(t.diagnostics.noLogs))
            else
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: 2),
                  child: SelectableText(line, style: mono),
                ),
          ],
        ),
      ),
    );
  }
}
