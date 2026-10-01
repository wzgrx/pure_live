import 'package:flutter/services.dart' as flutter show appBuildName, appBuildNumber;

/// `pubspec.yaml`'s version, for builds without Flutter's build name (a
/// test keeps it in step with `pubspec.yaml`).
const String pubspecVersion = '3.2.11';

/// `pubspec.yaml`'s build number.
const int pubspecBuild = 4134;

/// The installed version: the build name Flutter compiled in (3.x read it
/// with package_info_plus).
const String appVersion = flutter.appBuildName ?? pubspecVersion;

/// The installed build number.
final int appBuild = int.tryParse(flutter.appBuildNumber ?? '') ?? pubspecBuild;

/// The numeric parts of a dotted version: a leading `v` and anything after
/// `-` or `+` are ignored; null when a part is not a number.
List<int>? versionParts(String version) {
  final clean = version.trim().split(RegExp('[-+]')).first.replaceFirst(RegExp('^[vV]'), '').trim();
  if (clean.isEmpty) return null;
  final parts = <int>[];
  for (final part in clean.split('.')) {
    final value = int.tryParse(part);
    if (value == null) return null;
    parts.add(value);
  }
  return parts;
}

/// Whether [latest] is newer than [current] (3.x `VersionUtil.isNewerVersion`):
/// numeric part by part, missing parts are 0, unreadable versions are never
/// newer.
bool isNewerVersion(String latest, String current) {
  final a = versionParts(latest);
  final b = versionParts(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Orders dotted versions numerically, so 3.2.10 sorts after 3.2.9 (3.x
/// `compareReleaseVersions`); parts that are not numbers compare as text.
int compareVersions(String left, String right) {
  List<String> parts(String value) => value.trim().replaceFirst(RegExp('^[vV]'), '').split(RegExp('[.+-]'));
  final a = parts(left);
  final b = parts(right);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : '0';
    final y = i < b.length ? b[i] : '0';
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final byPart = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (byPart != 0) return byPart;
  }
  return 0;
}
