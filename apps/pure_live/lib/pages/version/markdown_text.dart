import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The Markdown of the update notes (3.x used markdown_widget): headings,
/// lists, quotes, rules, tables, paragraphs, and inline bold, code and
/// links. Everything else shows as plain text.
class MarkdownText extends StatelessWidget {
  /// Shows [data].
  const new(this.data, {super.key});

  /// The Markdown.
  final String data;

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks(data.replaceAll('\r\n', '\n').split('\n'));
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final block in blocks) block.build(context)],
      ),
    );
  }

  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
  static final RegExp _numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
  static final RegExp _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');

  List<_Block> _blocks(List<String> lines) {
    final blocks = <_Block>[];
    final paragraph = <String>[];
    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(_Paragraph(paragraph.join(' ')));
      paragraph.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flush();
        continue;
      }
      if (trimmed.startsWith('```')) {
        flush();
        final code = <String>[];
        for (i++; i < lines.length && !lines[i].trim().startsWith('```'); i++) {
          code.add(lines[i]);
        }
        blocks.add(_Code(code.join('\n')));
        continue;
      }
      if (_heading.firstMatch(trimmed) case final match?) {
        flush();
        blocks.add(_Heading(match.group(1)!.length, match.group(2)!));
        continue;
      }
      if (_rule.hasMatch(trimmed)) {
        flush();
        blocks.add(const _Rule());
        continue;
      }
      if (trimmed.startsWith('|')) {
        flush();
        final rows = <List<String>>[];
        for (; i < lines.length && lines[i].trim().startsWith('|'); i++) {
          final cells = lines[i].trim().replaceFirst(RegExp(r'^\|'), '').replaceFirst(RegExp(r'\|$'), '').split('|');
          final row = [for (final cell in cells) cell.trim()];
          // The separator row (|---|:---:|).
          if (row.every((cell) => RegExp(r'^:?-{2,}:?$').hasMatch(cell))) continue;
          rows.add(row);
        }
        i--;
        if (rows.isNotEmpty) blocks.add(_Table(rows));
        continue;
      }
      if (trimmed.startsWith('>')) {
        flush();
        blocks.add(_Quote(trimmed.replaceFirst(RegExp(r'^>\s?'), '')));
        continue;
      }
      if (_bullet.firstMatch(line) case final match?) {
        flush();
        blocks.add(_Item(match.group(1)!.length ~/ 2, '•', match.group(2)!));
        continue;
      }
      if (_numbered.firstMatch(line) case final match?) {
        flush();
        blocks.add(_Item(match.group(1)!.length ~/ 2, '${match.group(2)}.', match.group(3)!));
        continue;
      }
      paragraph.add(trimmed);
    }
    flush();
    return blocks;
  }
}

sealed class _Block {
  const new();

  Widget build(BuildContext context);
}

final class _Heading extends _Block {
  const new(this.level, this.text);

  final int level;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final style = switch (level) {
      1 => theme.titleLarge,
      2 => theme.titleMedium,
      _ => theme.titleSmall,
    };
    return Padding(
      padding: EdgeInsets.only(top: level == 1 ? 12 : 10, bottom: 6),
      child: _Inline(text, style: style?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

final class _Paragraph extends _Block {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: _Inline(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
  );
}

final class _Item extends _Block {
  const new(this.depth, this.marker, this.text);

  final int depth;
  final String marker;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);
    return Padding(
      padding: EdgeInsets.only(left: 4 + depth * 16.0, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, child: Text(marker, style: style)),
          Expanded(child: _Inline(text, style: style)),
        ],
      ),
    );
  }
}

final class _Quote extends _Block {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3)),
      ),
      child: _Inline(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

final class _Rule extends _Block {
  const new();

  @override
  Widget build(BuildContext context) => const Divider(height: 20);
}

final class _Code extends _Block {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
    );
  }
}

final class _Table extends _Block {
  const new(this.rows);

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = rows.fold<int>(0, (most, row) => row.length > most ? row.length : most);
    final style = theme.textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: theme.colorScheme.outlineVariant),
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: r == 0 ? BoxDecoration(color: theme.colorScheme.surfaceContainerHighest) : null,
                children: [
                  for (var c = 0; c < columns; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: _Inline(
                          c < rows[r].length ? rows[r][c] : '',
                          style: r == 0 ? style?.copyWith(fontWeight: FontWeight.bold) : style,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Bold (`**`), code (`` ` ``) and links (`[text](url)`) inside a line.
class _Inline extends StatefulWidget {
  const new(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_Inline> createState() => _InlineState();
}

class _InlineState extends State<_Inline> {
  static final RegExp _token = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)');
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    _disposeTaps();
    super.dispose();
  }

  void _disposeTaps() {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeTaps();
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final match in _token.allMatches(widget.text)) {
      if (match.start > at) spans.add(TextSpan(text: widget.text.substring(at, match.start)));
      if (match.group(1) case final bold?) {
        spans.add(
          TextSpan(
            text: bold,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      } else if (match.group(2) case final code?) {
        spans.add(
          TextSpan(
            text: code,
            style: TextStyle(fontFamily: 'monospace', backgroundColor: theme.colorScheme.surfaceContainerHighest),
          ),
        );
      } else {
        final uri = Uri.tryParse(match.group(4)!);
        final tap = TapGestureRecognizer()
          ..onTap = uri == null || !uri.hasScheme ? null : () => unawaited(AppNavigator.openExternal(uri));
        _taps.add(tap);
        spans.add(
          TextSpan(
            text: match.group(3),
            style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
            recognizer: tap,
          ),
        );
      }
      at = match.end;
    }
    if (at < widget.text.length) spans.add(TextSpan(text: widget.text.substring(at)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
