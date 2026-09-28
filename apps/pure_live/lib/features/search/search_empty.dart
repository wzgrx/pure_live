import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// 粘贴链接 (principles §3.3): search with the clipboard's text, which opens
/// a recognised room link or share code (principles §4.1); with nothing to
/// paste, the search page opens and says so.
Future<void> pasteRoomLink(BuildContext context) async {
  String? text;
  try {
    text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
  } on Object {
    text = null;
  }
  if (!context.mounted) return;
  if (text == null || text.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.search.clipboardEmpty)));
    context.go('/search');
    return;
  }
  context.go(searchLocation(text));
}

/// A search without results (principles §3.3): the magnifier, what to try
/// next (the spelling, another platform) and 粘贴链接.
class SearchEmptyView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => MessageView(
    illustration: Illustration.noResults,
    title: t.search.empty,
    message: t.search.emptyHint,
    actionLabel: t.follows.pasteLink,
    onAction: () => pasteRoomLink(context),
  );
}
