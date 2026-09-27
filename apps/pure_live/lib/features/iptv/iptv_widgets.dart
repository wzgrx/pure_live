import 'package:flutter/material.dart';

/// A playlist or guide to import, handed over by a share or a deep link
/// (spec/modules/iptv.md §6): a URL, the text of a playlist, or file bytes.
@immutable
final class IptvImportRequest {
  const new({this.url, this.bytes, this.fileName});

  /// An http(s) URL to import.
  final String? url;

  /// File or text content to import.
  final List<int>? bytes;

  /// Name of the shared file, if any.
  final String? fileName;
}

/// "刚刚同步", "3 小时前同步", "9月27日 08:00 同步", or "未同步".
String syncedText(DateTime? at, {DateTime? now}) {
  if (at == null) return '未同步';
  final local = at.toLocal();
  final elapsed = (now ?? DateTime.now()).difference(at);
  if (elapsed < const Duration(minutes: 1)) return '刚刚同步';
  if (elapsed < const Duration(hours: 1)) return '${elapsed.inMinutes} 分钟前同步';
  if (elapsed < const Duration(days: 1)) return '${elapsed.inHours} 小时前同步';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.month}月${local.day}日 ${two(local.hour)}:${two(local.minute)} 同步';
}

/// `HH:mm` in local time.
String clockText(DateTime at) {
  final local = at.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Asks for a name and optionally a URL; returns null when cancelled.
Future<({String name, String url})?> askSource(
  BuildContext context, {
  required String title,
  String url = '',
  String name = '',
  bool askUrl = true,
  String action = '导入',
}) => showDialog<({String name, String url})>(
  context: context,
  builder: (context) => _SourceDialog(title: title, url: url, name: name, askUrl: askUrl, action: action),
);

class _SourceDialog extends StatefulWidget {
  const new({required this.title, required this.url, required this.name, required this.askUrl, required this.action});

  final String title;
  final String url;
  final String name;
  final bool askUrl;
  final String action;

  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  late final _url = TextEditingController(text: widget.url);
  late final _name = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, (name: _name.text.trim(), url: _url.text.trim()));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.askUrl)
          TextField(
            controller: _url,
            autofocus: widget.url.isEmpty,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: '网址', hintText: 'https://…'),
            onSubmitted: (_) => _submit(),
          ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: '名称（可不填）'),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

/// Asks for one line of text; null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String? helper,
}) => showDialog<String>(
  context: context,
  builder: (context) => _TextDialog(title: title, initial: initial, hint: hint, helper: helper),
);

class _TextDialog extends StatefulWidget {
  const new({required this.title, required this.initial, this.hint, this.helper});

  final String title;
  final String initial;
  final String? hint;
  final String? helper;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      decoration: InputDecoration(hintText: widget.hint, helperText: widget.helper, helperMaxLines: 3),
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(context, _text.text.trim()), child: const Text('保存')),
    ],
  );
}

/// Asks to confirm a destructive action.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = '删除',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    ) ??
    false;
