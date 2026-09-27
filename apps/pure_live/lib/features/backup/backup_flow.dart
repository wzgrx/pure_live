import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Backups of this app: v4 format with the app version, the secret store
/// so accounts can travel in a passphrase-protected section (store.md §7.3),
/// and the recorder's tasks (F-BAK-01), read only when a backup runs.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(storeProvider),
    secrets: ref.watch(secretStoreProvider),
    recordTasks: RecordTaskBackupAdapter(() => ref.read(recordManagerProvider)),
    appVersion: appVersion,
  ),
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
Future<ExportOptions?> showExportOptions(BuildContext context, {String? title, String? action}) =>
    showDialog<ExportOptions>(
      context: context,
      builder: (context) =>
          _ExportOptionsDialog(title: title ?? t.backup.exportTitle, action: action ?? t.common.export),
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
        setState(() => _error = t.backup.passphraseTooShort(n: minPassphraseLength));
        return;
      }
      if (_passphrase.text != _repeat.text) {
        setState(() => _error = t.backup.passphraseMismatch);
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
              segments: [
                ButtonSegment(value: BackupScope.full, label: Text(t.backup.scopeFull)),
                ButtonSegment(value: BackupScope.follows, label: Text(t.backup.scopeFollows)),
              ],
              selected: {_scope},
              onSelectionChanged: (value) => setState(() => _scope = value.single),
            ),
            const SizedBox(height: Space.s2),
            Text(
              _scope == BackupScope.full ? t.backup.scopeFullDetail : t.backup.scopeFollowsDetail,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_scope == BackupScope.full) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _accounts,
                onChanged: (value) => setState(() => _accounts = value ?? false),
                title: Text(t.backup.includeAccounts),
                subtitle: Text(t.backup.includeAccountsDetail),
              ),
              if (_accounts) ...[
                TextField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.backup.passphrase),
                ),
                TextField(
                  controller: _repeat,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.backup.passphraseRepeat),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: Space.s2),
                Text(t.backup.passphraseRemember, style: Theme.of(context).textTheme.bodySmall),
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
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
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
    dialogTitle: t.backup.pickBackupFile,
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
    dialogTitle: t.backup.saveBackup,
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
  BackupTooNewException() => t.backup.errorTooNew,
  FormatException(:final message) when isFollowsOnlyError(message) => t.backup.errorFollowsOnly,
  FormatException() => t.backup.errorUnknownFile,
  StateError() => t.backup.errorBusy,
  _ => t.common.error(error: error),
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
  String? title,
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
          title: Text(t.backup.wrongPassphrase),
          content: Text(t.backup.skipAccountsQuestion),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.backup.continueImport)),
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
        title: Text(t.backup.importDone),
        content: ReportSummary(report: report, planned: false),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.backup.okay))],
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
  const new({required this.plans, this.title, this.source, super.key});

  /// Plans by mode; with two, the user picks the mode.
  final Map<RestoreMode, ImportPlan> plans;

  /// Dialog title; null for the default one.
  final String? title;

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
      title: Text(widget.title ?? t.backup.confirmImport),
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
                  segments: [
                    ButtonSegment(value: RestoreMode.full, label: Text(t.backup.restoreFull)),
                    ButtonSegment(value: RestoreMode.follows, label: Text(t.backup.restoreFollows)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) => setState(() => _mode = value.single),
                ),
                const SizedBox(height: Space.s2),
              ],
              Text(full ? t.backup.restoreFullDetail : t.backup.restoreFollowsDetail, style: small),
              const SizedBox(height: Space.s2),
              ReportSummary(report: report, planned: true),
              if (full && hasLockedSecrets(plan)) ...[
                const SizedBox(height: Space.s3),
                Text(t.backup.encryptedAccountsHint),
                TextField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.backup.passphraseOptional),
                ),
              ] else if (full && report.secretsPresent) ...[
                const SizedBox(height: Space.s2),
                Text(t.backup.plainAccountsHint),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, RestoreChoice(_mode, passphrase: _passphrase.text)),
          child: Text(t.common.import),
        ),
      ],
    );
  }
}

Map<String, String> get _sectionNames => {
  'follows': t.backup.section.follows,
  'followAreas': t.backup.section.followAreas,
  'tags': t.backup.section.tags,
  'roomTags': t.backup.section.roomTags,
  'history': t.backup.section.history,
  'blockRules': t.backup.section.blockRules,
  'settings': t.backup.section.settings,
  'roomPrefs': t.backup.section.roomPrefs,
  'recordTasks': t.backup.section.recordTasks,
  'secrets': t.backup.section.secrets,
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
        Text(t.backup.format(format: report.format)),
        const SizedBox(height: Space.s2),
        if (lines.isEmpty) Text(t.backup.nothingToImport) else ...lines.map(Text.new),
        if (!planned && report.secretsPresent && report.secretsSkipped) ...[
          const SizedBox(height: Space.s2),
          Text(t.backup.accountsSkipped),
        ],
      ],
    );
  }

  String _line(String section, ImportCount count) {
    final main = planned ? t.backup.readCount(n: count.read) : t.backup.writtenCount(n: count.written);
    final dropped = count.dropped > 0 ? t.backup.skippedCount(n: count.dropped) : '';
    return t.backup.sectionLine(section: section, counts: '$main$dropped');
  }
}
