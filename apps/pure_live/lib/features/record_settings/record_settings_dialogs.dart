import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// A system folder picker for the recording directory (3.x used
/// file_picker's `getDirectoryPath`; the app sets it, M12.3). With it the
/// folder row opens the picker straight away (3.x); null falls back to the
/// folder dialog ([RecordDirectoryDialog]).
final Provider<Future<String?> Function()?> recordDirectoryPickerProvider = Provider((ref) => null);

/// One choice of a [showRecordRadioDialog].
final class RecordOption<T> {
  /// Creates the choice.
  const new({required this.value, required this.label, this.description});

  /// The value.
  final T value;

  /// Its name.
  final String label;

  /// A line under the name (what the value means).
  final String? description;
}

/// A list of choices that applies the tapped one and closes (3.x
/// `_showRadioDialog`); a failed save keeps the dialog open and says so.
/// The current choice is in the primary colour with a tick instead of a
/// radio circle, its explanation 14 px (U.7b c13, UI_PLAN §7).
Future<void> showRecordRadioDialog<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<RecordOption<T>> options,
  required Future<void> Function(T value) onSelected,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) {
    var pending = false;
    Future<void> choose(T value) async {
      if (pending) return;
      pending = true;
      try {
        await onSelected(value);
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      } on Object {
        pending = false;
        if (dialogContext.mounted) {
          ScaffoldMessenger.maybeOf(dialogContext)
              ?.showSnackBar(SnackBar(content: Text(i18n('record_settings_apply_failed'))));
        }
      }
    }

    final theme = Theme.of(dialogContext);
    final colors = theme.colorScheme;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in options)
              _RecordChoice(
                key: ValueKey('record-option-${option.value}'),
                label: option.label,
                description: option.description,
                current: option.value == selected,
                colors: colors,
                onTap: () => unawaited(choose(option.value)),
              ),
          ],
        ),
      ),
    );
  },
);

class _RecordChoice extends StatelessWidget {
  const new({
    required this.label,
    required this.description,
    required this.current,
    required this.colors,
    required this.onTap,
    super.key,
  });

  final String label;
  final String? description;
  final bool current;
  final ColorScheme colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final styles = context.textStyles;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: colors.primary.withValues(alpha: current ? 0.08 : 0),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      selected: current,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: styles.t15.copyWith(
                              fontWeight: FontWeight.w600,
                              color: current ? colors.primary : colors.onSurface,
                            ),
                          ),
                          if (description case final description?)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(description, style: styles.t14.copyWith(color: colors.onSurfaceVariant)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (current) ...[const SizedBox(width: 12), Icon(AppIcons.selected, size: 22, color: colors.primary)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A whole number typed in a field (3.x `_RecordIntegerDialog`, now only
/// the size cap: "最大同时录制任务数" moved onto its row, U.7b c9).
class RecordIntegerDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({
    required this.title,
    required this.fieldKey,
    required this.initialValue,
    required this.minimum,
    required this.hintText,
    required this.errorText,
    required this.onSubmitted,
    this.maximum,
    this.suffix,
    this.note,
    super.key,
  });

  /// Title.
  final String title;

  /// Key prefix of the field (tests).
  final String fieldKey;

  /// The current value.
  final int initialValue;

  /// Smallest accepted value.
  final int minimum;

  /// Largest accepted value.
  final int? maximum;

  /// Hint of the field.
  final String hintText;

  /// Shown for a value out of range.
  final String errorText;

  /// Unit after the number.
  final String? suffix;

  /// What the value does, under the field.
  final String? note;

  /// Saves the value.
  final Future<void> Function(int value) onSubmitted;

  @override
  State<RecordIntegerDialog> createState() => _RecordIntegerDialogState();
}

class _RecordIntegerDialogState extends State<RecordIntegerDialog> {
  late final TextEditingController _controller = TextEditingController(text: '${widget.initialValue}');
  var _invalid = false;
  var _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? _parse(String text) {
    final value = int.tryParse(text.trim());
    if (value == null || value < widget.minimum) return null;
    final maximum = widget.maximum;
    return maximum != null && value > maximum ? null : value;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final value = _parse(_controller.text);
    if (value == null) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmitted(value);
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: ValueKey('${widget.fieldKey}-input'),
              controller: _controller,
              enabled: !_submitting,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: context.textStyles.t18,
              decoration: InputDecoration(
                labelText: i18n('manual_input'),
                hintText: widget.hintText,
                suffixText: widget.suffix,
                errorText: _invalid ? widget.errorText : null,
                errorMaxLines: 3,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (text) {
                final invalid = _parse(text) == null;
                if (invalid != _invalid) setState(() => _invalid = invalid);
              },
              onSubmitted: (_) => unawaited(_submit()),
            ),
            if (widget.note case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(note, style: context.textStyles.t14.copyWith(color: colors.onSurfaceVariant)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
        FilledButton(
          key: ValueKey('${widget.fieldKey}-confirm'),
          onPressed: _submitting ? null : () => unawaited(_submit()),
          child: Text(i18n('confirm')),
        ),
      ],
    );
  }
}

/// Asks before emptying the recording folder: how much goes and that it
/// cannot come back (U.7b c8); true to empty it.
Future<bool> confirmRecordClear(BuildContext context, {required String size}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(i18n('record_clear_title'), style: const TextStyle(fontWeight: FontWeight.w600)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              i18n('record_clear_body', args: {'size': size}),
              style: dialogContext.textStyles.t14.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
            FilledButton(
              key: const ValueKey('record-clear-confirm'),
              style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(i18n('record_clear_action')),
            ),
          ],
        );
      },
    ) ??
    false;

/// The recording folder, typed or picked with the system picker
/// ([browse]): the field shows the current choice; "default" clears it.
/// Used where no system picker opens straight from the row. [onSubmitted]
/// proves the folder writable and returns an error text, or null when saved.
class RecordDirectoryDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({required this.initialPath, required this.defaultPath, required this.onSubmitted, this.browse, super.key});

  /// The system folder picker; null hides the browse button.
  final Future<String?> Function()? browse;

  /// The configured parent ('' for the default).
  final String initialPath;

  /// The default folder, shown as the hint.
  final String defaultPath;

  /// Saves a path ('' for the default); returns an error text or null.
  final Future<String?> Function(String path) onSubmitted;

  @override
  State<RecordDirectoryDialog> createState() => _RecordDirectoryDialogState();
}

class _RecordDirectoryDialogState extends State<RecordDirectoryDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialPath);
  String? _error;
  var _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Picks the folder and saves it at once (the picker is the user's
  /// confirmation); a folder that cannot be used stays in the field with
  /// the error.
  Future<void> _browse() async {
    final picked = (await widget.browse?.call())?.trim() ?? '';
    if (picked.isEmpty || !mounted) return;
    _controller.text = picked;
    await _submit(picked);
  }

  Future<void> _submit(String path) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final error = await widget.onSubmitted(path.trim());
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _checking = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: Text(i18n('storage_directory'), style: const TextStyle(fontWeight: FontWeight.w600)),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n('record_settings_directory_help'), style: context.textStyles.t13),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('record-directory-input'),
            controller: _controller,
            enabled: !_checking,
            decoration: InputDecoration(
              labelText: i18n('record_settings_directory_parent'),
              hintText: widget.defaultPath,
              errorText: _error,
              errorMaxLines: 4,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: widget.browse == null
                  ? null
                  : IconButton(
                      key: const ValueKey('record-directory-browse'),
                      tooltip: i18n('select_folder'),
                      icon: const Icon(AppIcons.openFolder),
                      onPressed: _checking ? null : () => unawaited(_browse()),
                    ),
            ),
            onSubmitted: (text) => unawaited(_submit(text)),
          ),
          if (_checking) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Expanded(child: Text(i18n('record_storage_checking'), style: context.textStyles.t12)),
              ],
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('record-directory-default'),
        onPressed: _checking ? null : () => unawaited(_submit('')),
        child: Text(i18n('record_settings_directory_default')),
      ),
      TextButton(onPressed: _checking ? null : () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
      FilledButton(
        key: const ValueKey('record-directory-confirm'),
        onPressed: _checking ? null : () => unawaited(_submit(_controller.text)),
        child: Text(i18n('confirm')),
      ),
    ],
  );
}
