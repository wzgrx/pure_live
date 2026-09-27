import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live_app/features/about/semver.dart';

/// What a release file is for.
enum AssetKind {
  /// Android APK (see [ReleaseAsset.abi]).
  androidApk,

  /// Windows installer.
  windowsSetup,

  /// Windows portable archive.
  windowsPortable,

  /// macOS package.
  macos,

  /// Linux package.
  linux,

  /// A checksum list such as `SHA256SUMS`.
  checksums,

  /// Anything else (for example the native libraries' source archive).
  other,
}

/// One downloadable file of a release.
@immutable
final class ReleaseAsset {
  /// Creates an asset.
  const new({required this.name, required this.url, this.size = 0, this.sha256});

  /// File name.
  final String name;

  /// Download URL.
  final Uri url;

  /// Size in bytes.
  final int size;

  /// SHA-256 as 64 lower-case hex digits, when the release lists it.
  final String? sha256;

  /// What the file is for, from its name.
  AssetKind get kind => classify(name).$1;

  /// Android ABI of an APK (`arm64-v8a`, `armeabi-v7a`, `x86_64`,
  /// `universal`); null for other files.
  String? get abi => classify(name).$2;

  /// A copy with [sha256] set.
  ReleaseAsset withSha256(String value) => ReleaseAsset(name: name, url: url, size: size, sha256: value);

  /// Kind and ABI of a file called [name].
  static (AssetKind, String?) classify(String name) {
    final lower = name.toLowerCase();
    if (lower == 'sha256sums' ||
        lower.endsWith('.sha256') ||
        lower.contains('sha256sums') ||
        lower.contains('checksums')) {
      return (AssetKind.checksums, null);
    }
    if (lower.endsWith('.apk')) {
      final abi = switch (lower) {
        _ when lower.contains('arm64') => 'arm64-v8a',
        _ when lower.contains('armeabi') || lower.contains('armv7') || lower.contains('arm32') => 'armeabi-v7a',
        _ when lower.contains('x86_64') || lower.contains('x86-64') || lower.contains('x64') => 'x86_64',
        _ => 'universal',
      };
      return (AssetKind.androidApk, abi);
    }
    if (lower.endsWith('.exe')) return (AssetKind.windowsSetup, null);
    // MSIX is not published any more (F-UPD-02).
    if (lower.endsWith('.msix')) return (AssetKind.other, null);
    final windows = lower.contains('windows') || lower.contains('win64') || lower.contains('-win');
    if (lower.endsWith('.zip') && (windows || lower.contains('portable'))) return (AssetKind.windowsPortable, null);
    if (lower.endsWith('.dmg') || (lower.contains('macos') && lower.endsWith('.zip'))) return (AssetKind.macos, null);
    if (lower.endsWith('.appimage') ||
        lower.endsWith('.deb') ||
        lower.endsWith('.rpm') ||
        (lower.contains('linux') && (lower.endsWith('.tar.gz') || lower.endsWith('.tar.xz')))) {
      return (AssetKind.linux, null);
    }
    return (AssetKind.other, null);
  }
}

/// A published release.
@immutable
final class Release {
  /// Creates a release.
  const new({
    required this.tag,
    required this.version,
    required this.pageUrl,
    this.name = '',
    this.notes = '',
    this.preRelease = false,
    this.publishedAt,
    this.assets = const [],
  });

  /// Reads a release from the GitHub REST API; null for drafts and tags that
  /// are not versions.
  static Release? fromGitHub(Object? json) {
    if (json is! Map<String, Object?> || json['draft'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String) return null;
    final version = SemVer.tryParse(tag);
    if (version == null) return null;
    final assets = <ReleaseAsset>[];
    if (json['assets'] case final List<Object?> list) {
      for (final item in list) {
        if (item is! Map<String, Object?>) continue;
        final name = item['name'];
        final url = Uri.tryParse('${item['browser_download_url'] ?? ''}');
        if (name is! String || url == null || !url.hasScheme) continue;
        final digest = item['digest'];
        final sha = digest is String && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null;
        assets.add(
          ReleaseAsset(
            name: name,
            url: url,
            size: item['size'] is int ? item['size']! as int : 0,
            sha256: sha != null && _hex64.hasMatch(sha) ? sha : null,
          ),
        );
      }
    }
    final release = Release(
      tag: tag,
      version: version,
      pageUrl: Uri.tryParse('${json['html_url'] ?? ''}') ?? Uri(),
      name: json['name'] is String ? json['name']! as String : '',
      notes: json['body'] is String ? json['body']! as String : '',
      preRelease: json['prerelease'] == true || version.isPreRelease,
      publishedAt: json['published_at'] is String ? DateTime.tryParse(json['published_at']! as String) : null,
      assets: assets,
    );
    // Checksums written into the release notes.
    return release.withChecksums(release.notes);
  }

  /// Tag, for example `v4.0.0-preview.2`.
  final String tag;

  /// Version from the tag.
  final SemVer version;

  /// The release page.
  final Uri pageUrl;

  /// Title.
  final String name;

  /// Release notes (Markdown), the changelog.
  final String notes;

  /// Whether this is a pre-release (flag or version).
  final bool preRelease;

  /// Publication time.
  final DateTime? publishedAt;

  /// Files.
  final List<ReleaseAsset> assets;

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _hexInText = RegExp(r'\b[0-9a-fA-F]{64}\b');

  /// A copy where assets without a checksum take the one [text] lists next
  /// to their name (`sha256sum` output, or a table in the notes).
  Release withChecksums(String text) {
    if (text.isEmpty || assets.every((asset) => asset.sha256 != null)) return this;
    final found = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final hex = _hexInText.firstMatch(line)?[0];
      if (hex == null) continue;
      for (final asset in assets) {
        if (asset.sha256 == null && line.contains(asset.name)) found[asset.name] = hex.toLowerCase();
      }
    }
    if (found.isEmpty) return this;
    return Release(
      tag: tag,
      version: version,
      pageUrl: pageUrl,
      name: name,
      notes: notes,
      preRelease: preRelease,
      publishedAt: publishedAt,
      assets: [
        for (final asset in assets)
          if (found[asset.name] case final sha?) asset.withSha256(sha) else asset,
      ],
    );
  }

  /// The checksum list among the assets, if any.
  ReleaseAsset? get checksumAsset => assets.where((asset) => asset.kind == AssetKind.checksums).firstOrNull;

  /// Whether some installable file has no checksum yet.
  bool get missingChecksums => assets.any((asset) => asset.kind != AssetKind.checksums && asset.sha256 == null);
}

/// Why checking for updates failed.
enum UpdateCheckError {
  /// GitHub's rate limit for anonymous requests (60 per hour) is used up.
  rateLimited,

  /// No response.
  network,

  /// An unexpected answer.
  server,
}

/// Thrown by [UpdateChecker].
final class UpdateCheckException implements Exception {
  /// Creates the exception.
  const new(this.error, [this.detail]);

  /// What went wrong.
  final UpdateCheckError error;

  /// Diagnostic detail.
  final String? detail;

  @override
  String toString() => 'UpdateCheckException(${error.name}${detail == null ? '' : ': $detail'})';
}

/// Reads v4 releases from GitHub (F-UPD-01). The installed 3.x apps keep
/// their own feed (`assets/version.json` at the repository root), which this
/// never reads or writes. Requests go through the app's HTTP transport, so
/// they follow its proxy policy (site id `github`).
final class UpdateChecker {
  /// Reads releases of [repository] over [_http].
  new(this._http, {this.repository = 'wzgrx/pure_live', this.userAgent = 'PureLive'});

  /// Site id of the requests.
  static const site = 'github';

  final LiveHttp _http;

  /// `owner/name` on GitHub.
  final String repository;

  /// User-Agent (GitHub rejects requests without one).
  final String userAgent;

  /// The repository's page.
  Uri get projectUrl => Uri.parse('https://github.com/$repository');

  /// The releases page.
  Uri get releasesUrl => Uri.parse('https://github.com/$repository/releases');

  /// The latest published releases, newest first as GitHub lists them.
  Future<List<Release>> releases() async {
    final LiveResponse response;
    try {
      response = await _http.send(
        LiveRequest(
          site: site,
          url: Uri.parse('https://api.github.com/repos/$repository/releases?per_page=30'),
          headers: {
            'accept': 'application/vnd.github+json',
            'x-github-api-version': '2022-11-28',
            'user-agent': userAgent,
          },
        ),
      );
    } on TransportFailure catch (failure) {
      throw UpdateCheckException(UpdateCheckError.network, failure.reason.name);
    }
    if (response.status == 403 || response.status == 429) {
      throw UpdateCheckException(UpdateCheckError.rateLimited, '${response.status}');
    }
    if (response.status != 200) throw UpdateCheckException(UpdateCheckError.server, 'HTTP ${response.status}');
    final Object? decoded;
    try {
      decoded = jsonDecode(response.text);
    } on FormatException {
      throw const UpdateCheckException(UpdateCheckError.server, 'not JSON');
    }
    if (decoded is! List<Object?>) throw const UpdateCheckException(UpdateCheckError.server, 'not a list');
    return [...decoded.map(Release.fromGitHub).nonNulls];
  }

  /// Fills missing checksums of [release] from its checksum list asset.
  Future<Release> withChecksumFile(Release release) async {
    final asset = release.checksumAsset;
    if (asset == null || !release.missingChecksums) return release;
    try {
      final response = await _http.send(
        LiveRequest(
          site: site,
          url: asset.url,
          headers: {'user-agent': userAgent},
          timeout: const Duration(seconds: 20),
        ),
      );
      return response.isSuccess && response.bytes.length < 1024 * 1024 ? release.withChecksums(response.text) : release;
    } on TransportFailure {
      return release;
    }
  }

  /// v4 releases (major 4 and later; 3.x tags are the old app's) newest
  /// first; pre-releases only when [includePreRelease].
  static List<Release> v4Releases(Iterable<Release> releases, {required bool includePreRelease}) =>
      [...releases.where((release) => release.version.major >= 4 && (includePreRelease || !release.preRelease))]
        ..sort((a, b) => b.version.compareTo(a.version));

  /// The newest release above [current], or null when up to date. Preview
  /// builds also see preview releases; release builds only releases.
  static Release? newest(Iterable<Release> releases, SemVer current) {
    final candidates = v4Releases(releases, includePreRelease: current.isPreRelease);
    final top = candidates.firstOrNull;
    return top != null && top.version > current ? top : null;
  }
}

/// The Android ABI this app runs as (from the Dart runtime, no plugin).
String? runningAndroidAbi() {
  if (!Platform.isAndroid) return null;
  final version = Platform.version;
  if (version.contains('android_arm64')) return 'arm64-v8a';
  if (version.contains('android_arm')) return 'armeabi-v7a';
  if (version.contains('android_x64')) return 'x86_64';
  return null;
}

/// The files of [release] that fit this device first: the APK for this ABI
/// (then universal) on Android, installer then portable on Windows.
List<ReleaseAsset> recommendedAssets(Release release, {required String platform, String? abi}) {
  int rank(ReleaseAsset asset) => switch ((platform, asset.kind)) {
    ('android', AssetKind.androidApk) when asset.abi == abi => 0,
    ('android', AssetKind.androidApk) when asset.abi == 'universal' => 1,
    ('windows', AssetKind.windowsSetup) => 0,
    ('windows', AssetKind.windowsPortable) => 1,
    ('macos', AssetKind.macos) => 0,
    ('linux', AssetKind.linux) => 0,
    _ => 9,
  };
  return [...release.assets.where((asset) => rank(asset) < 9)]..sort((a, b) => rank(a).compareTo(rank(b)));
}
