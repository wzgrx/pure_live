import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

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

/// Technical label of a line's format; a single HTTP stream (IPTV `.ts`,
/// udpxy) is labelled by its transport, its container is only known once read.
String _formatLabel(StreamFormat format) => switch (format) {
  StreamFormat.flv => 'FLV',
  StreamFormat.hls => 'HLS',
  StreamFormat.other => 'HTTP',
};

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
  if (copied != null) messenger?.showSnackBar(SnackBar(content: Text(t.room.streamUrlCopied)));
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
      body = Text(t.rooms.notLive);
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
              child: TextButton(onPressed: () => _load(_streams?.selected), child: Text(t.common.retry)),
            ),
        ],
      );
    } else if (streams == null) {
      body = SizedBox(height: 96, child: LoadingView(label: t.rooms.loadingLines));
    } else {
      final loading = _loading != null;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.multiview.quality, style: theme.textTheme.titleSmall),
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
          Text(t.rooms.linesTapToCopy, style: theme.textTheme.titleSmall),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(Space.s4),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (streams.lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s2),
              child: Text(t.rooms.noLinesForQuality),
            )
          else
            for (final (index, line) in streams.lines.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const LiveIcon(LiveIcons.copy),
                title: Text('${t.multiview.lineN(n: index + 1)} · ${_formatLabel(line.format)}'),
                subtitle: Text(line.url.host, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _copy(line),
              ),
          if (_copyFailed)
            Text(t.rooms.clipboardFailed, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
        ],
      );
    }
    return AlertDialog(
      title: Text(widget.title == null ? t.rooms.streamLink : t.rooms.streamLinkFor(title: widget.title!)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: body)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.close))],
    );
  }
}
