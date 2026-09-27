import 'package:flutter/foundation.dart';

/// A semantic version such as `4.0.0-preview.2+40002`, compared by SemVer 2
/// precedence (the build part is ignored): `4.0.0-preview.9` <
/// `4.0.0-preview.10` < `4.0.0`.
@immutable
final class SemVer implements Comparable<SemVer> {
  /// Creates a version.
  const new(this.major, this.minor, this.patch, {this.preRelease = const [], this.build = ''});

  /// Parses `[v]MAJOR.MINOR.PATCH[-PRE][+BUILD]`; null for anything else.
  static SemVer? tryParse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    final pre = match[4];
    return SemVer(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      preRelease: pre == null || pre.isEmpty ? const [] : pre.split('.'),
      build: match[5] ?? '',
    );
  }

  static final RegExp _pattern = RegExp(
    r'^[vV]?(\d{1,9})\.(\d{1,9})\.(\d{1,9})(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z.-]+))?$',
  );

  /// Major version.
  final int major;

  /// Minor version.
  final int minor;

  /// Patch version.
  final int patch;

  /// Pre-release identifiers (`['preview', '2']`); empty for a release.
  final List<String> preRelease;

  /// Build metadata, not part of the comparison.
  final String build;

  /// Whether this is a pre-release such as a preview.
  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(SemVer other) {
    for (final (a, b) in [(major, other.major), (minor, other.minor), (patch, other.patch)]) {
      if (a != b) return a.compareTo(b);
    }
    // A release ranks above its pre-releases.
    if (preRelease.isEmpty || other.preRelease.isEmpty) {
      return (preRelease.isEmpty ? 1 : 0) - (other.preRelease.isEmpty ? 1 : 0);
    }
    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final order = _compareIdentifier(preRelease[i], other.preRelease[i]);
      if (order != 0) return order;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  static int _compareIdentifier(String a, String b) {
    final x = int.tryParse(a);
    final y = int.tryParse(b);
    if (x != null && y != null) return x.compareTo(y);
    // Numeric identifiers rank below alphanumeric ones.
    if (x != null) return -1;
    if (y != null) return 1;
    return a.compareTo(b);
  }

  /// Whether this version is newer than [other].
  bool operator >(SemVer other) => compareTo(other) > 0;

  /// Whether this version is older than [other].
  bool operator <(SemVer other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, Object.hashAll(preRelease));

  @override
  String toString() => '$major.$minor.$patch${isPreRelease ? '-${preRelease.join('.')}' : ''}';
}
