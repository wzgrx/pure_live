import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';

/// Backup and restore (spec/modules/store.md §7): export a v4 backup, import a
/// v4 or 3.x backup. 3.x users bring their follows into the preview this way,
/// since a separately installed preview cannot read the 3.x app's files.
class BackupPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;

  BackupService get _service => BackupService(ref.read(storeProvider), appVersion: '4.0.0-preview.1');

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on FormatException catch (error) {
      _toast('这个文件不是可以识别的备份：${error.message}');
    } on BackupTooNewException {
      _toast('这个备份来自更新的版本，请先升级应用');
    } on Object catch (error) {
      _toast('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export() => _run(() async {
    final document = await _service.export();
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final name =
        'PureLive-v4-backup-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}.json';
    final saved = await FilePicker.saveFile(
      dialogTitle: '保存备份',
      fileName: name,
      mimeType: 'application/json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(document))),
    );
    if (saved != null) _toast('备份已保存');
  });

  Future<void> _import(RestoreMode mode) => _run(() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
    );
    if (picked.isEmpty) return;
    final bytes = await picked.single.readAsBytes();
    final Object? document;
    try {
      document = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException('不是 JSON 文件');
    }
    final plan = await _service.plan(document, mode: mode);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认导入'),
        content: _ReportSummary(report: plan.report, planned: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('导入')),
        ],
      ),
    );
    if (confirmed != true) return;
    final report = await _service.apply(plan);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入完成'),
        content: _ReportSummary(report: report, planned: false),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('好'))],
      ),
    );
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('备份与恢复')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            children: [
              if (_busy) const LinearProgressIndicator(),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('导出备份'),
                subtitle: const Text('关注、分组、历史、屏蔽词和设置；不含平台登录信息'),
                onTap: _export,
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('导入关注'),
                subtitle: const Text('支持 v4 和 3.x 的备份文件，只导入关注和关注的分区'),
                onTap: () => _import(RestoreMode.follows),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('完整恢复'),
                subtitle: const Text('导入备份里的全部内容，文件里没有的部分保持不变'),
                onTap: () => _import(RestoreMode.full),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

const _sectionNames = {
  'follows': '关注',
  'followAreas': '关注的分区',
  'tags': '分组',
  'roomTags': '分组成员',
  'history': '观看历史',
  'blockRules': '屏蔽词',
  'settings': '设置',
  'roomPrefs': '直播间偏好',
};

class _ReportSummary extends StatelessWidget {
  const new({required this.report, required this.planned});

  final ImportReport report;
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final entry in report.counts.entries)
        if (entry.value.read > 0 || entry.value.written > 0) _line(_sectionNames[entry.key] ?? entry.key, entry.value),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('备份格式：${report.format}'),
        const SizedBox(height: Space.s2),
        if (lines.isEmpty) const Text('文件里没有可以导入的内容') else ...lines.map(Text.new),
        if (report.secretsPresent) ...[const SizedBox(height: Space.s2), const Text('备份里的平台登录信息这次不导入。')],
      ],
    );
  }

  String _line(String section, ImportCount count) {
    final main = planned ? '读到 ${count.read} 项' : '写入 ${count.written} 项';
    final dropped = count.dropped > 0 ? '，跳过 ${count.dropped} 项' : '';
    return '$section：$main$dropped';
  }
}
