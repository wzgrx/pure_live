import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The limit that keeps every entry (3.x `unlimitedHistoryLimit`).
const int unlimitedHistoryLimit = 0;

/// The limit as shown: a number, or "unlimited" for 0.
String historyLimitLabel(int limit) => limit == unlimitedHistoryLimit ? i18n('history_unlimited') : '$limit';

/// Asks for the number of history entries to keep (3.x
/// `_HistoryLimitDialog`); [save] stores the chosen one. [count] is the
/// number of entries now, for the warning about entries a smaller limit
/// removes.
Future<void> showHistoryLimitDialog(
  BuildContext context, {
  required int limit,
  required int count,
  required Future<void> Function(int limit) save,
}) => showAppDialog<void>(
  context: context,
  builder: (_) => HistoryLimitDialog(limit: limit, count: count, save: save),
);

/// The history limit dialog: preset chips, "unlimited", a custom number,
/// and a warning when the new limit would remove entries.
class HistoryLimitDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({required this.limit, required this.count, required this.save, super.key});

  /// The limit now.
  final int limit;

  /// Entries now.
  final int count;

  /// Stores a limit.
  final Future<void> Function(int limit) save;

  /// The preset limits (3.x).
  static const presets = <int>[20, 50, 100, 200, 500];

  @override
  State<HistoryLimitDialog> createState() => _HistoryLimitDialogState();
}

class _HistoryLimitDialogState extends State<HistoryLimitDialog> {
  late int _draft = widget.limit;
  final _custom = TextEditingController();
  bool _invalid = false;
  bool _saving = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _select(int value) => setState(() {
    _draft = value;
    _invalid = false;
  });

  void _applyCustom() {
    if (_saving) return;
    final value = int.tryParse(_custom.text.trim());
    if (value == null || value < 0) {
      setState(() => _invalid = true);
      return;
    }
    _custom.clear();
    _select(value);
  }

  Future<void> _save() async {
    if (_saving) return;
    // A number typed but not applied is what the user means.
    if (_custom.text.trim().isNotEmpty) {
      _applyCustom();
      if (_invalid) return;
    }
    setState(() => _saving = true);
    try {
      await widget.save(_draft);
      if (mounted) Navigator.pop(context);
    } on Object catch (error, stack) {
      log('Saving the history limit failed', name: 'HistoryPage', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('history_changes_save_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final styles = context.textStyles;
    final theme = Theme.of(context);
    final removes = _draft == unlimitedHistoryLimit ? 0 : widget.count - _draft;
    return AppDialog(
      title: i18n('history_limit'),
      busy: _saving,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n('history_limit_presets'), style: styles.t12Muted),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in HistoryLimitDialog.presets)
                ChoiceChip(
                  label: Text('$value', style: styles.t12),
                  selected: _draft == value,
                  onSelected: _saving ? null : (_) => _select(value),
                ),
              ChoiceChip(
                label: Text(i18n('history_unlimited'), style: styles.t12),
                selected: _draft == unlimitedHistoryLimit,
                onSelected: _saving ? null : (_) => _select(unlimitedHistoryLimit),
              ),
              if (!HistoryLimitDialog.presets.contains(_draft) && _draft != unlimitedHistoryLimit)
                ChoiceChip(
                  label: Text('$_draft', style: styles.t12),
                  selected: true,
                  onSelected: _saving ? null : (_) {},
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(i18n('history_limit_custom'), style: styles.t13Medium),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('history-limit-custom'),
            controller: _custom,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9-]'))],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _applyCustom(),
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
            style: styles.t14,
            decoration: dialogFieldDecoration(
              context,
              hint: '50',
              suffix: i18n('items'),
              error: _invalid ? i18n('history_limit_invalid') : null,
            ),
          ),
          const SizedBox(height: 8),
          // 3.x's whole-width "应用" (U.5c c1); "确认" takes a typed
          // number too (c6).
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              key: const ValueKey('history-limit-apply'),
              onPressed: _saving ? null : _applyCustom,
              child: Text(i18n('apply'), style: styles.t13Medium.copyWith(color: theme.colorScheme.primary)),
            ),
          ),
          const SizedBox(height: 16),
          Text('${i18n('current_value')}: ${historyLimitLabel(_draft)}', style: styles.t12Muted),
          if (removes > 0) ...[
            const SizedBox(height: 8),
            Row(
              key: const ValueKey('history-limit-warning'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.warning, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(i18n('history_limit_trim_warning', args: {'count': '$removes'}), style: styles.t12Error),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(i18n('history_limit_desc'), style: styles.t12Muted),
        ],
      ),
      actions: [
        DialogCancelButton(key: const ValueKey('history-limit-cancel'), enabled: !_saving),
        DialogActionButton(
          key: const ValueKey('history-limit-save'),
          label: i18n('save'),
          busy: _saving,
          onPressed: () => unawaited(_save()),
        ),
      ],
    );
  }
}
