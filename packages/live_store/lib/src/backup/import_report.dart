import 'package:meta/meta.dart';

/// Counts of one data category in an import (store.md §6.3 step 6).
@immutable
final class ImportCount {
  /// Creates counts.
  const new({this.read = 0, this.written = 0, this.dropped = 0});

  /// Items found in the source.
  final int read;

  /// Items stored.
  final int written;

  /// Items discarded (invalid, duplicate, unknown); see the report's issues.
  final int dropped;

  @override
  String toString() => 'read $read, written $written, dropped $dropped';
}

/// One discarded item or ignored key. Details are identities and key names,
/// never secret values.
@immutable
final class ImportIssue {
  /// Creates an issue.
  const new(this.section, this.reason, [this.detail]);

  /// Data category, for example `follows` or `settings`.
  final String section;

  /// Machine-readable reason: `invalidRoom`, `duplicate`, `unknownKey`,
  /// `invalidValue`, `unknownTag`, `otherPlatform`, `unsupported`,
  /// `unmatchedRoom`, `invalidItem`, `overLimit`.
  final String reason;

  /// What was affected, for example a room key or setting id.
  final String? detail;

  @override
  String toString() => '$section: $reason${detail == null ? '' : ' ($detail)'}';
}

/// What an import read, wrote and discarded.
final class ImportReport {
  /// Format of the source: `v4`, `v3`, `v2`, `legacy`, `legacyFollows`, ...
  String format = '';

  /// Whether the source carried an encrypted secrets section.
  bool secretsPresent = false;

  /// Whether the secrets section was skipped (no or wrong passphrase).
  bool secretsSkipped = false;

  final Map<String, ImportCount> _counts = {};
  final List<ImportIssue> _issues = [];

  /// Counts per category.
  Map<String, ImportCount> get counts => Map.unmodifiable(_counts);

  /// Discarded items and ignored keys.
  List<ImportIssue> get issues => List.unmodifiable(_issues);

  /// Records that [section] read [count] items.
  @internal
  void read(String section, int count) => _update(section, read: count);

  /// Records that [section] wrote [count] items.
  @internal
  void written(String section, int count) => _update(section, written: count);

  /// Records a discarded item of [section].
  @internal
  void drop(String section, String reason, [String? detail]) {
    _issues.add(ImportIssue(section, reason, detail));
    final current = _counts[section] ?? const ImportCount();
    _counts[section] = ImportCount(read: current.read, written: current.written, dropped: current.dropped + 1);
  }

  /// Records a note that is not a discarded item (for example an ignored
  /// section).
  @internal
  void note(String section, String reason, [String? detail]) => _issues.add(ImportIssue(section, reason, detail));

  void _update(String section, {int? read, int? written}) {
    final current = _counts[section] ?? const ImportCount();
    _counts[section] = ImportCount(
      read: read ?? current.read,
      written: written ?? current.written,
      dropped: current.dropped,
    );
  }

  @override
  String toString() => 'ImportReport($format, $_counts, ${_issues.length} issues)';
}
