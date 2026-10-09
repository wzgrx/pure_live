import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/chat_text.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/block_manager.dart';
import 'package:pure_live/shared/danmaku/masked_blocks.dart';

/// The room's actions on [message] (UI_PLAN §7: a long-pressed danmaku is a
/// panel; docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一 c1): the chat list's long press and a tap or
/// long press on a flying danmaku (F.2b) open the same panel, under the
/// picture in portrait and on the right in landscape; where there is no
/// room page around [context], in a sheet (with the room's local
/// interaction, if [context] has one, for "+1（本地）"). Completes when the
/// panel closes (the flying danmaku stand until then, 3.x).
Future<void> showRoomMessageActions(BuildContext context, LiveRoomController controller, LiveMessage message) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels == null) {
    final session = LocalRoomScope.maybeOf(context);
    return showRoomPanelSheet(
      context,
      heightFactor: 0.5,
      builder: (sheetContext, close) =>
          RoomMessagePanel(controller: controller, message: message, onClose: close, session: session),
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
/// have no "屏蔽此用户". A local danmaku or gift has no "屏蔽关键词…"
/// either (A08.13): local messages do not pass the filters
/// (`LiveRoomController.addLocal`), so the word would only take the lines
/// off the list and never stop the next one; only "复制" stays.
///
/// A08.14: under "复制", a chat line's words go out once more as a local
/// danmaku with the user's local profile and style ([localSendAgainText]):
/// "+1（本地）" on a platform's, "再发一次" on one's own. Only while the
/// local interaction is on and the room has one ([session]; not in
/// multi-view or on the TV); a gift, a super chat or a notice has none.
class RoomMessagePanel extends StatefulWidget {
  /// Creates the panel.
  const new({
    required this.controller,
    required this.message,
    required this.onClose,
    this.dragToClose = false,
    this.session,
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

  /// The room's local interaction; found around the panel when null (none:
  /// no "+1（本地）").
  final LocalRoomSession? session;

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
            // A08.11: a gift's name, the word that blocks it (D07.1).
            initial: switch (_message.gift?.displayName.trim()) {
              final name? when name.isNotEmpty => name,
              _ => _message.message,
            },
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
    final shownName = chatSenderName(message);
    final hint = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final level = message.userLevel.trim();
    final text = Text.rich(
      TextSpan(
        children: [
          // A08.10: the chat list's two roles; the name shows here even
          // with "显示用户名" off (this is where the sender is blocked).
          if (shownName.isNotEmpty)
            TextSpan(
              text: '$shownName${ChatText.nameEnd}',
              style: ChatText.name(theme, chatNameInk(message, scheme.surfaceContainerLowest, scheme)),
            ),
          // A08.11 c7: a platform's gift as its line says it, with the value.
          TextSpan(text: _words(message), style: ChatText.content(theme)),
        ],
      ),
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
    );
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
              child: level.isEmpty
                  ? text
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        text,
                        // A08.8: 3.x's "Lv.N" as the platform gives it; read as
                        // "等级 N".
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Semantics(
                            label: i18n('danmaku_user_level', args: {'level': level}),
                            excludeSemantics: true,
                            child: Text(
                              'Lv.$level',
                              key: const ValueKey('live-play-message-level'),
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
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
        if (widget.session ?? LocalRoomScope.maybeOf(context) case final session?)
          if (localSendAgainText(message) case final words?) ...[
            _SendAgainRow(session: session, message: message, words: words, onClose: widget.onClose, hint: hint),
            // D08.2 c3: one's own words kept for the composer's chips.
            if (message.isLocal) _SavePhraseRow(session: session, words: words, onClose: widget.onClose, hint: hint),
          ],
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
        // A08.13: the filters never see a local message, so blocking its
        // words would do nothing for the next one.
        if (!message.isLocal)
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

/// What "+1（本地）" sends for [message] (A08.14 c4): a chat line's words as
/// they came (an emote's code too), cut to [LocalCatalog.danmakuLimit]
/// characters as the composer cuts a paste; null for a gift, a super chat,
/// a notice or a line without words.
String? localSendAgainText(LiveMessage message) {
  if (message.type != LiveMessageType.chat || message.gift != null) return null;
  final words = LocalCatalog.clipDanmaku(message.message);
  return words.isEmpty ? null : words;
}

/// "+1（本地）" (a platform's danmaku) or "再发一次" (a local one), while the
/// local interaction is on: closes the panel, sends [words] the way the
/// composer does ([LocalRoomSession.sendChat]: the chat list at once, over
/// the picture as set, into the history) and says so.
class _SendAgainRow extends StatelessWidget {
  const new({
    required this.session,
    required this.message,
    required this.words,
    required this.onClose,
    required this.hint,
  });

  final LocalRoomSession session;
  final LiveMessage message;
  final String words;
  final VoidCallback onClose;
  final TextStyle? hint;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.interaction,
    builder: (context, _) {
      if (!session.interaction.enabled) return const SizedBox.shrink();
      return ListTile(
        key: const ValueKey('live-play-send-local-again'),
        leading: const Icon(AppIcons.localSendAgain),
        title: Text(i18n(message.isLocal ? 'local_history_again' : 'local_plus_one')),
        subtitle: Text(withoutOrphan(i18n('local_plus_one_desc')), style: hint),
        onTap: () {
          onClose();
          if (session.sendChat(words)) session.toast(i18n('local_message_sent'));
        },
      );
    },
  );
}

/// D08.2 c3: "存为常用语" on one's own local danmaku, while the local
/// interaction is on: closes the panel, keeps [words] as the last phrase
/// and says so. A phrase already is "已在常用语里" and cannot be tapped; with
/// the phrases full it says how many there may be.
class _SavePhraseRow extends StatelessWidget {
  const new({required this.session, required this.words, required this.onClose, required this.hint});

  final LocalRoomSession session;
  final String words;
  final VoidCallback onClose;
  final TextStyle? hint;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.interaction,
    builder: (context, _) {
      final local = session.interaction;
      if (!local.enabled) return const SizedBox.shrink();
      final saved = local.hasPhrase(words);
      final full = !saved && local.phrasesFull;
      return ListTile(
        key: const ValueKey('live-play-save-phrase'),
        enabled: !saved && !full,
        leading: Icon(saved ? AppIcons.localPhraseSaved : AppIcons.localPhraseSave),
        title: Text(i18n(saved ? 'local_phrase_saved' : 'local_phrase_save')),
        subtitle: Text(
          withoutOrphan(
            full
                ? i18n(LocalPhraseProblem.full.messageKey, args: {'count': '${Settings.localPhraseLimit}'})
                : i18n('local_phrase_save_desc'),
          ),
          style: hint,
        ),
        onTap: () {
          onClose();
          if (local.addPhrase(words)) session.toast(i18n('local_phrase_added'));
        },
      );
    },
  );
}

/// What the card says after the name: [chatMessageWords], and a gift's
/// value ("送出 小心心 ×3 · 3 元").
String _words(LiveMessage message) {
  final gift = message.gift;
  final value = gift == null || message.isLocal ? null : giftValueText(gift);
  final words = chatMessageWords(message);
  return value == null ? words : '$words · $value';
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

  /// What is wrong with the word, under the field (D02.2: a bad `/…/`).
  String? _error;

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

  void _edited() => setState(() => _error = null);

  String get _text => _input.text.trim();

  Future<void> _submit() async {
    if (_busy || _text.isEmpty) return;
    if (blockKeywordProblem(_text) case final problem?) {
      setState(() => _error = problem);
      return;
    }
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
        // A `/…/` pattern may be longer (D02.2).
        maxLength: blockKeywordMaxLengthOf(_input.text),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => unawaited(_submit()),
        decoration: dialogFieldDecoration(
          context,
          hint: i18n('please_enter_keyword'),
          helper: i18n('live_play_block_word_desc'),
          error: _error,
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
