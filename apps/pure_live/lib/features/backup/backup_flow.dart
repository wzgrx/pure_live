import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/store.dart';

/// Backups of this app: v4 format with the app version, and the secret store
/// so accounts can travel in a passphrase-protected section (store.md §7.3).
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(storeProvider), secrets: ref.watch(secretStoreProvider), appVersion: appVersion),
);

/// What to put into a backup.
@immutable
final class ExportOptions {
  /// Creates options.
  const new({this.scope = BackupScope.full, this.passphrase});

  /// Full backup or follows only.
  final BackupScope scope;

  /// Passphrase for the accounts section; null leaves accounts out.
  final String? passphrase;
}

/// Minimum passphrase length for an accounts section.
const minPassphraseLength = 6;

/// Asks what to back up: full or follows only, and whether to add the
/// platform accounts behind a passphrase (off by default, store.md §7.3).
Future<ExportOptions?> showExportOptions(BuildContext context, {String title = '导出备份', String action = '导出'}) =>
    showDialog<ExportOptions>(
      context: context,
      builder: (context) => _ExportOptionsDialog(title: title, action: action),
    );

class _ExportOptionsDialog extends StatefulWidget {
  const new({required this.title, required this.action});

  final String title;
  final String action;

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  BackupScope _scope = BackupScope.full;
  bool _accounts = false;
  final _passphrase = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    final withAccounts = _accounts && _scope == BackupScope.full;
    if (withAccounts) {
      if (_passphrase.text.length < minPassphraseLength) {
        setState(() => _error = '口令至少 $minPassphraseLength 个字符');
        return;
      }
      if (_passphrase.text != _repeat.text) {
        setState(() => _error = '两次输入的口令不一样');
        return;
      }
    }
    Navigator.pop(context, ExportOptions(scope: _scope, passphrase: withAccounts ? _passphrase.text : null));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<BackupScope>(
              segments: const [
                ButtonSegment(value: BackupScope.full, label: Text('完整备份')),
                ButtonSegment(value: BackupScope.follows, label: Text('仅关注')),
              ],
              selected: {_scope},
              onSelectionChanged: (value) => setState(() => _scope = value.single),
            ),
            const SizedBox(height: Space.s2),
            Text(
              _scope == BackupScope.full ? '关注、分组、历史、屏蔽词、直播间偏好和设置' : '只有关注的直播间和关注的分区',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_scope == BackupScope.full) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _accounts,
                onChanged: (value) => setState(() => _accounts = value ?? false),
                title: const Text('包含平台登录信息'),
                subtitle: const Text('Cookie 和 WebDAV 密码会用口令加密；导入时要输入同一个口令'),
              ),
              if (_accounts) ...[
                TextField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '口令'),
                ),
                TextField(
                  controller: _repeat,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '再输入一次'),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: Space.s2),
                Text('请记住这个口令，忘记后账号信息无法恢复。', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
            if (_error case final error?) ...[
              const SizedBox(height: Space.s2),
              Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

/// The backup document as pretty JSON bytes.
Uint8List encodeBackup(Map<String, Object?> document) =>
    Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(document)));

/// Decodes backup bytes; throws [FormatException] for anything but JSON.
Object? decodeBackup(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } on FormatException {
    throw const FormatException('Backup is not valid JSON');
  }
}

/// Lets the user pick a backup file; null when cancelled.
Future<Object?> pickBackupFile() async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: '选择备份文件',
    type: FileType.custom,
    allowedExtensions: const ['json', 'txt'],
  );
  if (picked.isEmpty) return null;
  return decodeBackup(await picked.single.readAsBytes());
}

/// Exports a backup with [options] through the system save dialog; returns
/// whether it was saved.
Future<bool> exportBackupToFile(BackupService service, ExportOptions options) async {
  final now = DateTime.now();
  final document = await service.export(scope: options.scope, passphrase: options.passphrase, now: now);
  final saved = await FilePicker.saveFile(
    dialogTitle: '保存备份',
    fileName: BackupService.fileName(options.scope, now),
    mimeType: 'application/json',
    type: FileType.custom,
    allowedExtensions: const ['json'],
    bytes: encodeBackup(document),
  );
  return saved != null;
}

/// Chinese text for a failed backup or restore.
String backupErrorText(Object error) => switch (error) {
  BackupTooNewException() => '这个备份来自更新的版本，请先升级应用',
  FormatException(:final message) when isFollowsOnlyError(message) => '这是只含关注的备份，请用“仅恢复关注”',
  FormatException() => '不是可以识别的备份文件',
  StateError() => '另一个恢复正在进行，请稍后再试',
  _ => '操作失败：$error',
};

/// Whether a plan failed because a follows-only file was restored in full.
bool isFollowsOnlyError(String message) => message.startsWith('Follows-only');

/// What the user chose in the restore confirmation.
@immutable
final class RestoreChoice {
  /// Creates a choice.
  const new(this.mode, {this.passphrase});

  /// Full or follows only.
  final RestoreMode mode;

  /// Passphrase for an encrypted accounts section, if given.
  final String? passphrase;
}

/// The dry run and confirmation every restore goes through (store.md §7.2):
/// parse and validate [document] without writing, show what would be
/// imported, then write it in one transaction and show the result.
///
/// [mode] null lets the user choose between a full and a follows-only
/// restore (follows-only files offer only the latter). An encrypted accounts
/// section asks for its passphrase; a wrong one imports everything else.
/// [showResult] false skips the closing report dialog (the LAN receiver
/// answers the sender first and shows a short message instead).
/// Returns null when the user cancelled. Throws [FormatException] or
/// [BackupTooNewException] when the document cannot be restored at all;
/// [backupErrorText] turns those into a message.
Future<ImportReport?> confirmAndRestore(
  BuildContext context, {
  required BackupService service,
  required Object? document,
  RestoreMode? mode,
  String? source,
  String title = '确认导入',
  bool showResult = true,
}) async {
  final plans = <RestoreMode, ImportPlan>{};
  for (final candidate in mode == null ? RestoreMode.values : [mode]) {
    try {
      plans[candidate] = await service.plan(document, mode: candidate);
    } on FormatException catch (error) {
      if (mode == null && candidate == RestoreMode.full && isFollowsOnlyError(error.message)) continue;
      rethrow;
    }
  }
  if (!context.mounted) return null;
  final choice = await showDialog<RestoreChoice>(
    context: context,
    builder: (context) => RestoreConfirmDialog(plans: plans, title: title, source: source),
  );
  if (choice == null) return null;
  var plan = plans[choice.mode]!;
  final passphrase = choice.passphrase;
  if (passphrase != null && passphrase.isNotEmpty && choice.mode == RestoreMode.full && hasLockedSecrets(plan)) {
    plan = await service.plan(document, mode: choice.mode, passphrase: passphrase);
    if (plan.report.secretsSkipped) {
      if (!context.mounted) return null;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('口令不正确'),
          content: const Text('平台登录信息不会导入。要继续导入其余内容吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续导入')),
          ],
        ),
      );
      if (proceed != true) return null;
    }
  }
  final report = await service.apply(plan);
  if (showResult && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入完成'),
        content: ReportSummary(report: report, planned: false),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('好'))],
      ),
    );
  }
  return report;
}

/// Whether [plan] carries an encrypted accounts section it could not open
/// yet (no passphrase given).
bool hasLockedSecrets(ImportPlan plan) => plan.report.secretsPresent && plan.report.secretsSkipped;

/// Shows a planned restore and returns the user's [RestoreChoice].
class RestoreConfirmDialog extends StatefulWidget {
  const new({required this.plans, this.title = '确认导入', this.source, super.key});

  /// Plans by mode; with two, the user picks the mode.
  final Map<RestoreMode, ImportPlan> plans;

  /// Dialog title.
  final String title;

  /// Where the backup comes from, for example the sending device.
  final String? source;

  @override
  State<RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<RestoreConfirmDialog> {
  late RestoreMode _mode = widget.plans.keys.first;
  final _passphrase = TextEditingController();

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plans[_mode]!;
    final report = plan.report;
    final full = _mode == RestoreMode.full;
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.source case final source?) ...[Text(source), const SizedBox(height: Space.s2)],
              if (widget.plans.length > 1) ...[
                SegmentedButton<RestoreMode>(
                  segments: const [
                    ButtonSegment(value: RestoreMode.full, label: Text('完整恢复')),
                    ButtonSegment(value: RestoreMode.follows, label: Text('仅恢复关注')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) => setState(() => _mode = value.single),
                ),
                const SizedBox(height: Space.s2),
              ],
              Text(full ? '备份里有的部分会替换本机的对应数据，备份里没有的部分保持不变。' : '只替换关注的直播间和关注的分区，其它数据不变。', style: small),
              const SizedBox(height: Space.s2),
              ReportSummary(report: report, planned: true),
              if (full && hasLockedSecrets(plan)) ...[
                const SizedBox(height: Space.s3),
                const Text('备份里有加密的平台登录信息。输入导出时设置的口令可以一并导入，不填则跳过。'),
                TextField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '口令（可选）'),
                ),
              ] else if (full && report.secretsPresent) ...[
                const SizedBox(height: Space.s2),
                const Text('备份里有平台登录信息，会一并导入，并在本机加密保存。'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, RestoreChoice(_mode, passphrase: _passphrase.text)),
          child: const Text('导入'),
        ),
      ],
    );
  }
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
  'secrets': '平台登录信息',
};

/// What a planned or finished import contains, section by section.
class ReportSummary extends StatelessWidget {
  const new({required this.report, required this.planned, super.key});

  /// The report.
  final ImportReport report;

  /// Whether the import has not run yet (shows read counts).
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
        if (!planned && report.secretsPresent && report.secretsSkipped) ...[
          const SizedBox(height: Space.s2),
          const Text('平台登录信息这次没有导入。'),
        ],
      ],
    );
  }

  String _line(String section, ImportCount count) {
    final main = planned ? '读到 ${count.read} 项' : '写入 ${count.written} 项';
    final dropped = count.dropped > 0 ? '，跳过 ${count.dropped} 项' : '';
    return '$section：$main$dropped';
  }
}
