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
    dialogTitle: '保存诊断包',
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
      if (await exportDiagnostics(ref)) _toast('诊断包已保存');
    } on Object catch (error, stack) {
      ref.read(appLogProvider).error('diagnostics', 'export failed', error, stack);
      _toast('导出失败：$error');
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
      appBar: AppBar(title: const Text('诊断与日志')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              if (_busy) const LinearProgressIndicator(),
              ListTile(
                leading: const Icon(Icons.medical_information_outlined),
                title: const Text('导出诊断包'),
                subtitle: const Text('版本、设备信息、设置和最近的日志，保存为一个 JSON 文件；不含 Cookie、密码等账号信息'),
                enabled: !_busy,
                onTap: _export,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.bug_report_outlined),
                title: const Text('崩溃报告'),
                subtitle: const Text('出错后，下次启动时提示导出诊断包。不会自动上传任何数据'),
                value: prefs.crashReports,
                onChanged: (value) => ref.read(appPrefsProvider.notifier).setCrashReports(enabled: value),
              ),
              const Divider(),
              ListTile(
                title: const Text('最近的日志'),
                subtitle: const Text('只保存在本机，最多约 768 KB，Cookie 和令牌写入前已去除'),
                trailing: TextButton(onPressed: lines.isEmpty ? null : _clear, child: const Text('清空')),
              ),
              if (lines.isEmpty)
                const Padding(padding: EdgeInsets.all(Space.s4), child: Text('本次运行还没有日志'))
              else
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: 2),
                    child: SelectableText(line, style: mono),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
