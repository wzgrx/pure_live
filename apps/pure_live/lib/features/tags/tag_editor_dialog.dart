import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Longest tag name (3.x `maxLength: 15`).
const int tagNameMaxLength = 15;

/// Longest tag description (3.x `maxLength: 40`).
const int tagDescriptionMaxLength = 40;

/// Shows the dialog that adds a tag, or edits [tag] when given (3.x
/// `_TagEditorDialog`). Completes with the saved tag, or null when the
/// dialog was closed without saving.
Future<StoreTag?> showTagEditor(BuildContext context, {required TagStore tags, StoreTag? tag}) => showDialog<StoreTag>(
  context: context,
  builder: (_) => TagEditorDialog(tags: tags, tag: tag),
);

/// The add or edit dialog: name and description, checked against the other
/// tags when saving; a tag changed elsewhere while it is open is not
/// overwritten (3.x `tag_editor_stale_error`).
class TagEditorDialog extends StatefulWidget {
  /// Creates the dialog over [tags]; edits [tag] when given.
  const new({required this.tags, this.tag, super.key});

  /// Where the tag is saved.
  final TagStore tags;

  /// The tag being edited; null adds a new one.
  final StoreTag? tag;

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.tag?.name ?? '');
  late final TextEditingController _description = TextEditingController(text: widget.tag?.description ?? '');
  final FocusNode _nameFocus = FocusNode();
  String? _nameError;
  String? _saveError;
  String? _staleError;
  bool _saving = false;

  bool get _isEdit => widget.tag != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_staleError != null || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final original = widget.tag;
      if (original != null) {
        // The tag may have been renamed or deleted elsewhere meanwhile.
        final current = (await widget.tags.all()).where((tag) => tag.id == original.id).firstOrNull;
        if (current != original) {
          _markStale();
          return;
        }
      }
      final validation = await widget.tags.validateName(_name.text, excludingId: original?.id);
      if (!mounted) return;
      if (validation != TagNameValidation.valid) {
        _refuse(
          validation == TagNameValidation.empty ? i18n('tag_name_empty_error') : i18n('tag_name_duplicate_error'),
        );
        return;
      }
      final StoreTag? saved;
      if (original == null) {
        saved = await widget.tags.add(_name.text, description: _description.text);
      } else {
        final updated = await widget.tags.update(original.id, name: _name.text, description: _description.text);
        saved = updated
            ? StoreTag(id: original.id, name: _name.text.trim(), description: _description.text.trim())
            : null;
      }
      if (!mounted) return;
      if (saved == null) {
        _refuse(i18n('tag_invalid_or_duplicate'));
        return;
      }
      Navigator.pop(context, saved);
    } on Object catch (error, stack) {
      log('Saving a tag failed', name: 'TagsPage', error: error, stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = i18n('tag_changes_save_failed');
      });
      _nameFocus.requestFocus();
    }
  }

  void _refuse(String error) {
    setState(() {
      _saving = false;
      _nameError = error;
    });
    _nameFocus.requestFocus();
  }

  void _markStale() {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _nameError = null;
      _saveError = null;
      _staleError = i18n('tag_editor_stale_error');
    });
    _nameFocus.unfocus();
  }

  void _clearErrors() {
    if (_nameError == null && _saveError == null) return;
    setState(() {
      _nameError = null;
      _saveError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = _staleError ?? _saveError;
    return PopScope<Object?>(
      canPop: !_saving,
      child: DialogButtonsTheme(
        child: AlertDialog(
          key: const ValueKey('tag-editor'),
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text(
            i18n(_isEdit ? 'edit_tag' : 'add_tag'),
            style: context.textStyles.t18.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // c7: the label sits on the field's border, the count of
                // characters and the error under it (3.x: a title above
                // each field, no count).
                _field(
                  key: const ValueKey('tag-editor-name'),
                  controller: _name,
                  focusNode: _nameFocus,
                  autofocus: !_isEdit,
                  maxLength: tagNameMaxLength,
                  label: i18n('tag_name_label'),
                  hint: i18n('tag_input_hint'),
                  error: _nameError,
                  clearLabel: i18n('clear_tag_name'),
                  action: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                _field(
                  key: const ValueKey('tag-editor-description'),
                  controller: _description,
                  maxLength: tagDescriptionMaxLength,
                  label: i18n('tag_desc_label'),
                  hint: i18n('tag_desc_hint'),
                  clearLabel: i18n('clear_tag_description'),
                  action: TextInputAction.done,
                  onSubmitted: () => unawaited(_submit()),
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      key: const ValueKey('tag-editor-error'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(message, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              key: const ValueKey('tag-editor-cancel'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(i18n('cancel')),
            ),
            FilledButton(
              key: const ValueKey('tag-editor-confirm'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _staleError == null && !_saving ? () => unawaited(_submit()) : null,
              child: _saving
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: i18n('refresh_loading')),
                    )
                  : Text(i18n('confirm')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required int maxLength,
    required String label,
    required String hint,
    required String clearLabel,
    required TextInputAction action,
    FocusNode? focusNode,
    bool autofocus = false,
    String? error,
    VoidCallback? onSubmitted,
  }) => TextField(
    key: key,
    controller: controller,
    focusNode: focusNode,
    autofocus: autofocus,
    maxLength: maxLength,
    textInputAction: action,
    enabled: !_saving && _staleError == null,
    onChanged: (_) => _clearErrors(),
    onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      suffixIcon: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => value.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: clearLabel,
                icon: const Icon(AppIcons.clearField, size: 18),
                onPressed: () {
                  controller.clear();
                  _clearErrors();
                  focusNode?.requestFocus();
                },
              ),
      ),
    ),
  );
}
