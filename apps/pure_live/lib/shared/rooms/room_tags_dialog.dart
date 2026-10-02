import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Longest tag name (3.x `maxLength: 15`).
const int roomTagNameMaxLength = 15;

/// Longest tag note (3.x `maxLength: 40`).
const int roomTagNoteMaxLength = 40;

/// The width from which the tags sit in two columns (U.4a c14: the
/// dialog's own content width, not the screen's).
const double roomTagTwoColumnWidth = 400;

/// "设置房间标签 / 分类" of a followed room (3.x
/// `_showTagSelectionGridModal`, docs/ui/compare/U.4a c13, c14).
///
/// Says which room under the title; every tag as a tile (tap to select or
/// clear, several at once); "＋ 新建标签" opens the form in place (name up
/// to 15 characters, an optional note up to 40, "添加"), the list stays;
/// "确认" always works and first makes a tag of a name still typed; the
/// dialog is as tall as its content and scrolls inside when it is long;
/// the tags take two columns once the content is [roomTagTwoColumnWidth]
/// wide. Without tags the form is open from the start.
class RoomTagPicker extends StatefulWidget {
  /// Creates the picker.
  const new({required this.store, required this.room, required this.tags, required this.selected, super.key});

  /// Storage.
  final LiveStore store;

  /// The room.
  final LiveRoom room;

  /// Every tag, in the user's order.
  final List<StoreTag> tags;

  /// The room's tag ids.
  final Set<String> selected;

  @override
  State<RoomTagPicker> createState() => _RoomTagPickerState();
}

class _RoomTagPickerState extends State<RoomTagPicker> {
  late final List<StoreTag> _tags = List.of(widget.tags);
  late final Set<String> _selected = Set.of(widget.selected);
  late bool _formOpen = widget.tags.isEmpty;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String? _nameError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The refusal stays until the name changes (focus moves the selection,
    // which notifies too).
    var last = _name.text;
    _name.addListener(() {
      if (_name.text == last) return;
      last = _name.text;
      if (_nameError != null) setState(() => _nameError = null);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _openForm() {
    setState(() => _formOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  void _closeForm() => setState(() {
    _formOpen = false;
    _nameError = null;
    _name.clear();
    _note.clear();
  });

  /// Makes a tag of the form and selects it; false when the name is
  /// refused or saving failed.
  Future<bool> _addTag() async {
    final tags = widget.store.tags;
    try {
      final validation = await tags.validateName(_name.text);
      if (!mounted) return false;
      if (validation != TagNameValidation.valid) {
        setState(() {
          _nameError = i18n(
            validation == TagNameValidation.empty ? 'tag_name_empty_error' : 'tag_name_duplicate_error',
          );
        });
        _nameFocus.requestFocus();
        return false;
      }
      final tag = await tags.add(_name.text, description: _note.text);
      if (!mounted) return false;
      if (tag == null) {
        setState(() => _nameError = i18n('tag_invalid_or_duplicate'));
        return false;
      }
      setState(() {
        _tags.add(tag);
        _selected.add(tag.id);
        _name.clear();
        _note.clear();
        _nameError = null;
      });
      return true;
    } on Object catch (error, stack) {
      log('Adding a tag failed', name: 'RoomTags', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('tag_changes_save_failed'));
      return false;
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _addTag();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_formOpen && _name.text.trim().isNotEmpty && !await _addTag()) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      await widget.store.tags.setTagsOf(widget.room, [
        for (final tag in _tags)
          if (_selected.contains(tag.id)) tag.id,
      ]);
      if (mounted) Navigator.pop(context);
    } on Object catch (error, stack) {
      log('Saving room tags failed', name: 'RoomTags', error: error, stackTrace: stack);
      if (mounted) setState(() => _busy = false);
      AppNavigator.toast(i18n('tag_assignment_save_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = context.textStyles;
    final room = widget.room;
    final name = room.displayNick(platformName(room.platform));
    // The one dialog (docs/ui/compare/U.1d): the long-content width, the
    // title and the buttons stay while the tags scroll.
    return AppDialog(
      key: const ValueKey('room-tags'),
      title: i18n('set_room_tags'),
      wide: true,
      busy: _busy,
      autofocus: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            i18n('room_tags_subtitle', args: {'name': name, 'platform': platformName(room.platform)}),
            key: const ValueKey('room-tags-subtitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.t14.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= roomTagTwoColumnWidth ? 2 : 1;
              final tileWidth = (constraints.maxWidth - 8 * (columns - 1)) / columns;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_tags.isEmpty) _empty(context),
                  Wrap(
                    key: ValueKey('room-tags-columns-$columns'),
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in _tags)
                        SizedBox(
                          width: tileWidth,
                          child: _TagTile(
                            tag: tag,
                            selected: _selected.contains(tag.id),
                            onTap: _busy
                                ? null
                                : () => setState(() {
                                    if (!_selected.remove(tag.id)) _selected.add(tag.id);
                                  }),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_formOpen) _form(context) else _newTagRow(context),
                ],
              );
            },
          ),
        ],
      ),
      actions: [
        DialogCancelButton(key: const ValueKey('room-tags-cancel'), enabled: !_busy),
        DialogActionButton(
          key: const ValueKey('room-tags-save'),
          label: i18n('confirm'),
          busy: _busy,
          onPressed: () => unawaited(_save()),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    return Padding(
      key: const ValueKey('room-tags-empty'),
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Column(
        children: [
          Icon(AppIcons.tag, size: 32, color: scheme.primary),
          const SizedBox(height: 8),
          Text(i18n('room_tags_empty_title'), style: styles.t15.copyWith(fontWeight: FontWeight.w600)),
          Text(
            i18n('room_tags_empty_hint'),
            textAlign: TextAlign.center,
            style: styles.t13.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _newTagRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _DashedOutline(color: scheme.outline, radius: 12),
      child: InkWell(
        key: const ValueKey('room-tags-new'),
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : _openForm,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              Icon(AppIcons.add, size: 20, color: scheme.primary),
              Text(
                i18n('room_tags_new'),
                style: context.textStyles.t14.copyWith(color: scheme.primary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: const UnderlineInputBorder(),
    );
    return Container(
      key: const ValueKey('room-tags-form'),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  i18n('room_tags_new'),
                  style: styles.t13.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const ValueKey('room-tags-collapse'),
                tooltip: i18n('room_tags_collapse'),
                onPressed: _busy ? null : _closeForm,
                icon: Icon(AppIcons.close, size: 20, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ListenableBuilder(
              listenable: _name,
              builder: (context, _) => TextField(
                key: const ValueKey('room-tags-name'),
                controller: _name,
                focusNode: _nameFocus,
                autofocus: _tags.isNotEmpty,
                maxLength: roomTagNameMaxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_add()),
                decoration: field(i18n('room_tags_name_hint')).copyWith(
                  counterText: '',
                  errorText: _nameError,
                  suffixIcon: _name.text.isEmpty
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_name.text.characters.length}/$roomTagNameMaxLength',
                              style: styles.t12.copyWith(color: scheme.onSurfaceVariant).tabular,
                            ),
                            IconButton(
                              tooltip: i18n('clear'),
                              onPressed: _name.clear,
                              icon: const Icon(AppIcons.clearField, size: 18),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              key: const ValueKey('room-tags-note'),
              controller: _note,
              maxLength: roomTagNoteMaxLength,
              decoration: field(i18n('room_tags_note_hint')).copyWith(counterText: ''),
              onSubmitted: (_) => unawaited(_add()),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('room-tags-add'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 36), shape: const StadiumBorder()),
                onPressed: _busy ? null : () => unawaited(_add()),
                icon: const Icon(AppIcons.add, size: 18),
                label: Text(i18n('room_tags_add')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagTile extends StatelessWidget {
  const new({required this.tag, required this.selected, required this.onTap});

  final StoreTag tag;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final description = tag.description.trim();
    final radius = BorderRadius.circular(12);
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: selected ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        key: ValueKey('tag-choice-${tag.id}'),
        borderRadius: radius,
        onTap: onTap,
        child: Semantics(
          selected: selected,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tag.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: styles.t14.copyWith(
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
                          ),
                        ),
                        if (description.isNotEmpty)
                          Text(
                            description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: styles.t12.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? scheme.primary : null,
                      border: selected ? null : Border.all(color: scheme.outline, width: 2),
                    ),
                    child: selected ? Icon(AppIcons.selected, size: 16, color: scheme.onPrimary) : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded outline ("＋ 新建标签").
class _DashedOutline extends CustomPainter {
  const new({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.75));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
}
