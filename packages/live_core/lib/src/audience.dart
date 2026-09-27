import 'package:meta/meta.dart';

/// Audience figures in the three measures platforms report (ADR 0010, rule 3).
///
/// Each measure is optional and never stands in for another: a popularity
/// score is not an online count, and a cumulative view count is neither.
@immutable
final class Audience {
  /// Creates figures; every value must be zero or more.
  const new({this.online, this.popularity, this.cumulative})
    : assert(online == null || online >= 0, 'online must not be negative'),
      assert(popularity == null || popularity >= 0, 'popularity must not be negative'),
      assert(cumulative == null || cumulative >= 0, 'cumulative must not be negative');

  /// No figures reported.
  static const none = Audience();

  /// Concurrent viewers.
  final int? online;

  /// Platform "heat" score (Douyu hot, Huya 8006, Bilibili online field).
  final int? popularity;

  /// Viewers so far in this broadcast.
  final int? cumulative;

  /// Whether no measure is reported.
  bool get isEmpty => online == null && popularity == null && cumulative == null;

  @override
  bool operator ==(Object other) =>
      other is Audience && other.online == online && other.popularity == popularity && other.cumulative == cumulative;

  @override
  int get hashCode => Object.hash(online, popularity, cumulative);

  @override
  String toString() => 'Audience(online: $online, popularity: $popularity, cumulative: $cumulative)';
}
