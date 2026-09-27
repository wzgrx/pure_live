import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';

/// Writes [text] to the clipboard; true only once the write went through
/// (REG-ROOM-016: copying reports success only after the clipboard took it).
typedef ClipboardWriter = Future<bool> Function(String text);

Future<bool> _systemClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } on Object {
    return false;
  }
}

/// 获取直链 from a card (spec/product.md F-SRC-04): loads the room and its
/// stream lines, lets the user pick a quality and a line, and copies that
/// URL. Returns the copied URL, or null when nothing was copied.
Future<Uri?> showStreamLinkPicker(
  BuildContext context,
  WidgetRef ref,
  RoomRef room, {
  String? title,
  ClipboardWriter? clipboard,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = await showDialog<Uri>(
    context: context,
    builder: (context) => StreamLinkDialog(room: room, title: title, clipboard: clipboard ?? _systemClipboard),
  );
  if (copied != null) messenger?.showSnackBar(const SnackBar(content: Text('直链已复制，有时效，过期后需要重新复制')));
  return copied;
}

/// The picker of [showStreamLinkPicker]: quality chips, then one row per
/// line; tapping a line copies it and closes with its URL.
class StreamLinkDialog extends ConsumerStatefulWidget {
  const new({required this.room, required this.clipboard, this.title, super.key});

  /// The room.
  final RoomRef room;

  /// Streamer's name for the title.
  final String? title;

  /// Clipboard access.
  final ClipboardWriter clipboard;

  @override
  ConsumerState<StreamLinkDialog> createState() => _StreamLinkDialogState();
}

class _StreamLinkDialogState extends ConsumerState<StreamLinkDialog> {
  RoomDetail? _detail;
  StreamSet? _streams;
  Quality? _loading;
  Object? _error;
  bool _offline = false;
  bool _copyFailed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch(++_request, null));
  }

  /// Loads the lines of [quality] again (a chip or retry).
  void _load(Quality? quality) {
    setState(() {
      _error = null;
      _copyFailed = false;
      _loading = quality ?? _streams?.selected;
    });
    unawaited(_fetch(++_request, quality));
  }

  /// Loads the detail once, then the lines of [quality] (the platform's
  /// default first). Only the latest request applies.
  Future<void> _fetch(int request, Quality? quality) async {
    try {
      final site = ref.read(sitesProvider).of(widget.room.platform);
      final detail = _detail ?? await site.rooms.detail(widget.room);
      if (!mounted || request != _request) return;
      _detail = detail;
      if (detail.state == LiveState.offline) {
        setState(() {
          _offline = true;
          _loading = null;
        });
        return;
      }
      final streams = await site.streams.streams(detail, quality: quality);
      if (!mounted || request != _request) return;
      setState(() {
        _streams = streams;
        _loading = null;
      });
    } on Object catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = null;
      });
    }
  }

  Future<void> _copy(StreamLine line) async {
    final ok = await widget.clipboard(line.url.toString());
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, line.url);
    } else {
      setState(() => _copyFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streams = _streams;
    final error = _error;
    final Widget body;
    if (_offline) {
      body = const Text('主播现在没有开播，拿不到直链。');
    } else if (error != null) {
      final text = describeError(error);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.s1),
          Text(text.message),
          if (text.retryable)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => _load(_streams?.selected), child: const Text('重试')),
            ),
        ],
      );
    } else if (streams == null) {
      body = const SizedBox(height: 96, child: LoadingView(label: '正在获取线路'));
    } else {
      final loading = _loading != null;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('画质', style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.s2),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              for (final quality in streams.qualities)
                ChoiceChip(
                  label: Text(quality.label),
                  selected: (_loading ?? streams.selected) == quality,
                  onSelected: loading || quality == streams.selected ? null : (_) => _load(quality),
                ),
            ],
          ),
          const SizedBox(height: Space.s4),
          Text('线路（点一下复制）', style: theme.textTheme.titleSmall),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(Space.s4),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (streams.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.s2),
              child: Text('这个画质没有可用的线路'),
            )
          else
            for (final (index, line) in streams.lines.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.content_copy),
                title: Text('线路 ${index + 1} · ${line.format == StreamFormat.flv ? 'FLV' : 'HLS'}'),
                subtitle: Text(line.url.host, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _copy(line),
              ),
          if (_copyFailed)
            Text('没能写入剪贴板，再试一次', style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
        ],
      );
    }
    return AlertDialog(
      title: Text(widget.title == null ? '获取直链' : '获取直链 · ${widget.title}'),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: body)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    );
  }
}
