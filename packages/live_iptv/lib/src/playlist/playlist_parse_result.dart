import 'package:live_iptv/src/model.dart';
import 'package:meta/meta.dart';

/// A problem in one line of a playlist.
@immutable
final class PlaylistIssue {
  /// Creates an issue at 1-based [line] (0 for the whole file).
  const new(this.line, this.message);

  /// 1-based line number, 0 for the whole file.
  final int line;

  /// What is wrong (English, for logs).
  final String message;

  @override
  String toString() => line == 0 ? message : 'Line $line: $message';
}

/// What a playlist parser read.
@immutable
final class PlaylistParseResult {
  /// Creates a result.
  new({required List<IptvEntry> entries, List<PlaylistIssue> issues = const [], this.truncated = false})
    : entries = List.unmodifiable(entries),
      issues = List.unmodifiable(issues);

  /// Entries in file order.
  final List<IptvEntry> entries;

  /// Skipped lines and other problems.
  final List<PlaylistIssue> issues;

  /// The file ends inside a stanza (`#EXTINF` without its URL): the download
  /// was probably cut, so it must not replace a saved playlist.
  final bool truncated;

  /// Whether any problem was found.
  bool get hasIssues => issues.isNotEmpty;
}
