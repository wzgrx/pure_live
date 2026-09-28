import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart' show BlockKind;
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/danmaku/danmaku_text.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Blocks a word or a user; the room applies it at once and stores it.
typedef BlockCallback = void Function(BlockKind kind, String value);

/// The actions of a chat line or an on-video danmaku (F-DM-04, REN-8): copy,
/// block a keyword (edited from the text), block the user. Resolves when the
/// menu and any follow-up dialog are closed.
Future<void> showChatLineActions(
  BuildContext context, {
  required DanmakuEvent line,
  required BlockCallback onBlock,
  BlockCallback? onUnblock,
}) async {
  final (user, text) = switch (line) {
    DanmakuChat(:final userName, :final text) => (userName, text),
    // A whole sentence: "今天也要早睡 送出 火箭", "Alice sent Rocket".
    final DanmakuGift gift => (gift.userName, '${gift.userName} ${giftText(gift)}'),
    _ => ('', ''),
  };
  final messenger = ScaffoldMessenger.maybeOf(context);
  final action = await showModalBottomSheet<_LineAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
            subtitle: user.isEmpty || line is DanmakuGift ? null : Text(user),
          ),
          const Divider(height: 1),
          if (line is DanmakuChat) ...[
            ListTile(
              leading: const LiveIcon(LiveIcons.copy),
              title: Text(t.common.copy),
              onTap: () => Navigator.pop(context, _LineAction.copy),
            ),
            ListTile(
              leading: const LiveIcon(LiveIcons.block),
              title: Text(t.danmaku.blockKeyword),
              onTap: () => Navigator.pop(context, _LineAction.blockKeyword),
            ),
          ],
          if (user.isNotEmpty)
            ListTile(
              leading: const LiveIcon(LiveIcons.blockUser),
              title: Text(t.danmaku.blockUser),
              subtitle: Text(user),
              onTap: () => Navigator.pop(context, _LineAction.blockUser),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _LineAction.copy:
      await Clipboard.setData(ClipboardData(text: text));
      messenger?.showSnackBar(SnackBar(content: Text(t.common.copied)));
    case _LineAction.blockKeyword:
      final keyword = await showBlockKeywordDialog(context, initial: text);
      if (keyword == null) return;
      onBlock(BlockKind.keyword, keyword);
      _confirm(
        messenger,
        t.danmaku.keywordBlocked(keyword: keyword),
        onUnblock == null ? null : () => onUnblock(BlockKind.keyword, keyword),
      );
    case _LineAction.blockUser:
      onBlock(BlockKind.user, user);
      _confirm(
        messenger,
        t.danmaku.userBlocked(user: user),
        onUnblock == null ? null : () => onUnblock(BlockKind.user, user),
      );
  }
}

void _confirm(ScaffoldMessengerState? messenger, String text, VoidCallback? undo) {
  messenger?.showSnackBar(
    SnackBar(
      content: Text(text),
      action: undo == null ? null : SnackBarAction(label: t.common.undo, onPressed: undo),
    ),
  );
}

enum _LineAction { copy, blockKeyword, blockUser }

/// Asks for a keyword, starting from [initial] (the message text, all
/// selected so typing replaces it); null when cancelled or blank.
Future<String?> showBlockKeywordDialog(BuildContext context, {String initial = ''}) => showDialog<String>(
  context: context,
  builder: (context) => _KeywordDialog(initial: initial),
);

class _KeywordDialog extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_KeywordDialog> createState() => _KeywordDialogState();
}

class _KeywordDialogState extends State<_KeywordDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    Navigator.pop(context, value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t.danmaku.blockKeyword),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLength: 64,
      decoration: InputDecoration(hintText: t.danmaku.blockKeywordHint, helperText: t.danmaku.caseInsensitive),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
      FilledButton(onPressed: _submit, child: Text(t.danmaku.block)),
    ],
  );
}

/// Shows [text] briefly; used after blocking from outside a chat menu.
void showDanmakuToast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
}

/// Runs [action] and ignores its result (store writes the UI does not wait for).
void fireAndForget(Future<Object?> action) => unawaited(action.then((_) {}, onError: (Object _) {}));
