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
}) => showAppDialog<void>(
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
        if (dialogContext.mounted) showAppToast(dialogContext, AppToast(i18n('record_settings_apply_failed')));
      }
    }

    return AppDialog(
      title: title,
      contentPadding: EdgeInsets.zero,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            DialogOptionRow(
              key: ValueKey('record-option-${option.value}'),
              label: option.label,
              description: option.description,
              selected: option.value == selected,
              onTap: () => unawaited(choose(option.value)),
            ),
        ],
      ),
    );
  },
);

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
    return AppDialog(
      title: widget.title,
      busy: _submitting,
      autofocus: false,
      content: Column(
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
            decoration: dialogFieldDecoration(
              context,
              label: i18n('manual_input'),
              hint: widget.hintText,
              suffix: widget.suffix,
              error: _invalid ? widget.errorText : null,
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
      actions: [
        DialogCancelButton(enabled: !_submitting),
        DialogActionButton(
          key: ValueKey('${widget.fieldKey}-confirm'),
          label: i18n('save'),
          busy: _submitting,
          onPressed: () => unawaited(_submit()),
        ),
      ],
    );
  }
}

/// Asks before emptying the recording folder: how much goes and that it
/// cannot come back (U.7b c8); true to empty it.
Future<bool> confirmRecordClear(BuildContext context, {required String size}) => showAppConfirmDialog(
  context: context,
  title: i18n('record_clear_title'),
  message: i18n('record_clear_body', args: {'size': size}),
  confirmLabel: i18n('record_clear_action'),
  danger: true,
  confirmKey: const ValueKey('record-clear-confirm'),
);

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
  Widget build(BuildContext context) => AppDialog(
    title: i18n('storage_directory'),
    message: i18n('record_settings_directory_help'),
    wide: true,
    busy: _checking,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('record-directory-input'),
          controller: _controller,
          enabled: !_checking,
          decoration: dialogFieldDecoration(
            context,
            label: i18n('record_settings_directory_parent'),
            hint: widget.defaultPath,
            error: _error,
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
    leading: TextButton(
      key: const ValueKey('record-directory-default'),
      onPressed: _checking ? null : () => unawaited(_submit('')),
      child: Text(i18n('record_settings_directory_default')),
    ),
    actions: [
      DialogCancelButton(enabled: !_checking),
      DialogActionButton(
        key: const ValueKey('record-directory-confirm'),
        label: i18n('confirm'),
        onPressed: _checking ? null : () => unawaited(_submit(_controller.text)),
      ),
    ],
  );
}
