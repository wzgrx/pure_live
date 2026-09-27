import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart' show BlockKind;
import 'package:pure_live_app/features/danmaku/danmaku_text.dart';

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
    final DanmakuGift gift => (gift.userName, giftText(gift)),
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
            subtitle: user.isEmpty ? null : Text(user),
          ),
          const Divider(height: 1),
          if (line is DanmakuChat) ...[
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制'),
              onTap: () => Navigator.pop(context, _LineAction.copy),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('屏蔽关键词'),
              onTap: () => Navigator.pop(context, _LineAction.blockKeyword),
            ),
          ],
          if (user.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('屏蔽用户'),
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
      messenger?.showSnackBar(const SnackBar(content: Text('已复制')));
    case _LineAction.blockKeyword:
      final keyword = await showBlockKeywordDialog(context, initial: text);
      if (keyword == null) return;
      onBlock(BlockKind.keyword, keyword);
      _confirm(messenger, '已屏蔽关键词“$keyword”', onUnblock == null ? null : () => onUnblock(BlockKind.keyword, keyword));
    case _LineAction.blockUser:
      onBlock(BlockKind.user, user);
      _confirm(messenger, '已屏蔽用户“$user”', onUnblock == null ? null : () => onUnblock(BlockKind.user, user));
  }
}

void _confirm(ScaffoldMessengerState? messenger, String text, VoidCallback? undo) {
  messenger?.showSnackBar(
    SnackBar(
      content: Text(text),
      action: undo == null ? null : SnackBarAction(label: '撤销', onPressed: undo),
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
    title: const Text('屏蔽关键词'),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLength: 64,
      decoration: const InputDecoration(hintText: '包含这个词的弹幕都会被隐藏', helperText: '不区分大小写'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _submit, child: const Text('屏蔽')),
    ],
  );
}

/// Shows [text] briefly; used after blocking from outside a chat menu.
void showDanmakuToast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
}

/// Runs [action] and ignores its result (store writes the UI does not wait for).
void fireAndForget(Future<Object?> action) => unawaited(action.then((_) {}, onError: (Object _) {}));
