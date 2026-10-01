import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// A system folder picker for the recording directory (3.x used
/// file_picker's `getDirectoryPath`); null until the app adds one (M12.3),
/// then the page lets the user type the path.
final Provider<Future<String?> Function()?> recordDirectoryPickerProvider = Provider((ref) => null);

/// One choice of a radio dialog.
final class RecordOption<T> {
  /// Creates the choice.
  const new({required this.value, required this.label, this.description});

  /// The value.
  final T value;

  /// Its name.
  final String label;

  /// A line under the name.
  final String? description;
}

/// A list of choices that applies the tapped one and closes (3.x
/// `_showRadioDialog`); a failed save keeps the dialog open.
Future<void> showRecordRadioDialog<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<RecordOption<T>> options,
  required Future<void> Function(T value) onSelected,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) {
    final theme = Theme.of(dialogContext);
    var pending = false;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      content: RadioGroup<T>(
        groupValue: selected,
        onChanged: (value) async {
          if (value == null || pending) return;
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
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              RadioListTile<T>(
                key: ValueKey('record-option-${option.value}'),
                value: option.value,
                selected: option.value == selected,
                selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text(option.label, style: dialogContext.textStyles.t16.copyWith(fontWeight: FontWeight.w600)),
                subtitle: option.description == null
                    ? null
                    : Text(option.description!, style: dialogContext.textStyles.t12),
              ),
          ],
        ),
      ),
    );
  },
);

/// A whole number typed or picked from [quickValues] (3.x
/// `_RecordIntegerDialog`).
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
    this.quickValues = const [],
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

  /// Saves the value.
  final Future<void> Function(int value) onSubmitted;

  /// Chips for common values.
  final List<int> quickValues;

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
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
          if (widget.quickValues.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(i18n('quick_select'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in widget.quickValues)
                  ChoiceChip(
                    key: ValueKey('${widget.fieldKey}-quick-$value'),
                    label: Text('$value'),
                    selected: int.tryParse(_controller.text) == value,
                    selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                    onSelected: _submitting
                        ? null
                        : (_) => setState(() {
                            _controller.text = '$value';
                            _invalid = false;
                          }),
                  ),
              ],
            ),
          ],
        ],
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

/// The recording folder typed by the user (until a system picker exists):
/// the field shows the current choice; "default" clears it. [onSubmitted]
/// proves the folder writable and returns an error text, or null when
/// saved.
class RecordDirectoryDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({required this.initialPath, required this.defaultPath, required this.onSubmitted, super.key});

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
    title: Text(i18n('storage_directory'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
