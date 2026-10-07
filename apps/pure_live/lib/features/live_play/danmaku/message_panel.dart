import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/masked_blocks.dart';

/// The room's actions on [message] (UI_PLAN §7: a long-pressed danmaku is a
/// panel; docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一 c1): the chat list's long press and a tap or
/// long press on a flying danmaku (F.2b) open the same panel, under the
/// picture in portrait and on the right in landscape; where there is no
/// room page around [context], in a sheet. Completes when the panel closes
/// (the flying danmaku stand until then, 3.x).
Future<void> showRoomMessageActions(BuildContext context, LiveRoomController controller, LiveMessage message) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels == null) {
    return showRoomPanelSheet(
      context,
      heightFactor: 0.5,
      builder: (sheetContext, close) => RoomMessagePanel(controller: controller, message: message, onClose: close),
    );
  }
  panels.openMessage(message);
  final closed = Completer<void>();
  void watch() {
    if (panels.value == RoomPanelKind.message && identical(panels.message, message)) return;
    panels.removeListener(watch);
    closed.complete();
  }

  panels.addListener(watch);
  return closed.future;
}

/// The panel of a long-pressed danmaku (3.x `DanmakuMessageActions`,
/// docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗 长按弹幕): "弹幕" and ✕, the message in a card (the
/// name in its colour), then copy, block the viewer and block a keyword,
/// each saying what it does. "屏蔽关键词…" turns to the panel's second page
/// (B09 c8: no centred dialog over the picture, which is often in
/// fullscreen): ← back, the field filled with the message to cut down to the
/// word (one line, at most 40, U.1d c8) and "屏蔽". A local danmaku and a
/// masked name (a Bilibili guest's `观***`, [isMaskedViewerName], B01 c1)
/// have no "屏蔽此用户".
class RoomMessagePanel extends StatefulWidget {
  /// Creates the panel.
  const new({
    required this.controller,
    required this.message,
    required this.onClose,
    this.dragToClose = false,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// The danmaku.
  final LiveMessage message;

  /// Closes the panel.
  final VoidCallback onClose;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  /// The longest keyword (3.x's field counted to 40).
  static const int keywordMaxLength = 40;

  @override
  State<RoomMessagePanel> createState() => _RoomMessagePanelState();
}

class _RoomMessagePanelState extends State<RoomMessagePanel> {
  /// The keyword page is open.
  bool _keyword = false;

  LiveMessage get _message => widget.message;

  @override
  Widget build(BuildContext context) => RoomSidePanel(
    key: const ValueKey('live-play-message-panel'),
    title: i18n(_keyword ? 'block_danmaku_keyword' : 'danmaku'),
    onClose: widget.onClose,
    dragToClose: widget.dragToClose,
    leading: _keyword
        ? IconButton(
            key: const ValueKey('message-panel-back'),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => setState(() => _keyword = false),
            icon: const Icon(AppIcons.back),
          )
        : null,
    child: _keyword
        ? _KeywordPage(
            key: const ValueKey('live-play-keyword-page'),
            initial: _message.message,
            onBlock: (keyword) async {
              widget.onClose();
              await widget.controller.blockKeyword(keyword);
              AppNavigator.toast(i18n('danmaku_keyword_blocked'));
            },
          )
        : _actions(context),
  );

  Widget _actions(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = _message;
    final name = message.userName.trim();
    final body = theme.textTheme.bodyLarge?.regular;
    final hint = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    return ListView(
      key: const ValueKey('live-play-message-sheet'),
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: DecoratedBox(
            key: const ValueKey('live-play-message-card'),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (name.isNotEmpty)
                      TextSpan(
                        text: '$name：',
                        style: body?.copyWith(
                          color: chatNameColor(message.color, scheme.surfaceContainerLowest) ?? scheme.onSurfaceVariant,
                        ),
                      ),
                    TextSpan(
                      text: message.message,
                      style: body?.copyWith(color: scheme.onSurface),
                    ),
                  ],
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        ListTile(
          key: const ValueKey('live-play-copy-message'),
          leading: const Icon(AppIcons.copy),
          title: Text(i18n('copy')),
          onTap: () async {
            widget.onClose();
            // 3.x copied "用户名: 内容".
            await Clipboard.setData(ClipboardData(text: chatCopyText(message)));
            AppNavigator.toast(i18n('copied_to_clipboard'));
          },
        ),
        // 3.x: a local danmaku cannot block its sender. B-1: nor can a
        // masked name, which stands for many viewers.
        if (name.isNotEmpty && !message.isLocal && !isMaskedViewerName(name))
          ListTile(
            key: const ValueKey('live-play-block-user'),
            leading: const Icon(AppIcons.blockUser),
            title: Text(i18n('live_play_block_viewer')),
            subtitle: Text(withoutOrphan(i18n('live_play_block_viewer_desc', args: {'name': name})), style: hint),
            onTap: () async {
              widget.onClose();
              await widget.controller.blockUser(name);
              AppNavigator.toast(i18n('live_play_user_blocked', args: {'name': name}));
            },
          ),
        ListTile(
          key: const ValueKey('live-play-block-keyword'),
          leading: const Icon(AppIcons.blockKeyword),
          title: Text(i18n('live_play_block_word')),
          subtitle: Text(withoutOrphan(i18n('live_play_block_word_desc')), style: hint),
          onTap: () => setState(() => _keyword = true),
        ),
      ],
    );
  }
}

/// The keyword page: the field, filled with the message and selected, and
/// "屏蔽" (the input dialog's parts, U.1d c8).
class _KeywordPage extends StatefulWidget {
  const new({required this.initial, required this.onBlock, super.key});

  final String initial;
  final Future<void> Function(String keyword) onBlock;

  @override
  State<_KeywordPage> createState() => _KeywordPageState();
}

class _KeywordPageState extends State<_KeywordPage> {
  late final TextEditingController _input = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_edited);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _edited() => setState(() {});

  String get _text => _input.text.trim();

  Future<void> _submit() async {
    if (_busy || _text.isEmpty) return;
    setState(() => _busy = true);
    await widget.onBlock(_text);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    children: [
      TextField(
        key: const ValueKey('live-play-keyword-input'),
        controller: _input,
        autofocus: true,
        enabled: !_busy,
        maxLength: RoomMessagePanel.keywordMaxLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => unawaited(_submit()),
        decoration: dialogFieldDecoration(
          context,
          hint: i18n('please_enter_keyword'),
          helper: i18n('live_play_block_word_desc'),
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton(
          key: const ValueKey('live-play-keyword-confirm'),
          onPressed: _busy || _text.isEmpty ? null : () => unawaited(_submit()),
          child: Text(i18n('live_play_block_action')),
        ),
      ),
    ],
  );
}
