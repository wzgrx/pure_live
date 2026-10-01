import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/version/app_version.dart';

/// The repository the update files are read from (3.x `AppConfig`).
const GitHubMirror updateRepository = GitHubMirror(owner: 'wzgrx', repo: 'pure_live');

/// The project page (3.x `VersionUtil.projectUrl`).
final Uri projectUrl = Uri.parse('https://github.com/${updateRepository.owner}/${updateRepository.repo}');

/// The newer version the start-up check or the version page last found;
/// null when there is none or nothing was checked. The about page shows it
/// as "新版本 v…" (docs/ui/compare/U.12b c3).
final ValueNotifier<UpdateInfo?> foundUpdate = ValueNotifier<UpdateInfo?>(null);

/// Keeps [info] in [foundUpdate] when it is newer, clears it otherwise.
void noteCheckedUpdate(UpdateInfo info) => foundUpdate.value = info.isNewer ? info : null;

/// The Android ABIs 3.x builds (3.x `AppConsts.supportAndroidAbis`).
const Set<String> supportedAndroidAbis = {'arm64-v8a', 'armeabi-v7a', 'x86_64'};

/// The newest version for this platform, from the repository's
/// `assets/version.json` (3.x `VersionUtil._applyVersionData`; the file's
/// format is shared with the installed 3.x apps and must not change).
final class UpdateInfo {
  /// Creates the information.
  const new({
    required this.version,
    required this.buildNumber,
    this.log = '',
    this.prerelease = false,
    this.releaseUrl = '',
    this.androidAbis = const {'arm64-v8a'},
    this.windowsMsixAvailable = false,
  });

  /// Reads `version.json`: the top level, overridden by `platforms.<platform>`.
  /// Throws [FormatException] without a version or a positive build number.
  factory fromJson(Map<String, Object?> json, {required String platform}) {
    final platforms = json['platforms'];
    final own = platforms is Map ? platforms[platform] : null;
    final data = {...json, if (own is Map) ...own.cast<String, Object?>()};
    final version = data['version']?.toString().trim() ?? '';
    final build = _int(data['build_number']);
    if (version.isEmpty || build == null || build <= 0) throw const FormatException('Incomplete release identity');
    final abis = data['android_abis'];
    return UpdateInfo(
      version: version,
      buildNumber: build,
      log: data['version_desc']?.toString() ?? '',
      prerelease: data['prerelease'] == true,
      releaseUrl: data['download_url']?.toString() ?? '',
      androidAbis: abis is List
          ? {for (final abi in abis) abi.toString()}.intersection(supportedAndroidAbis)
          : const {'arm64-v8a'},
      windowsMsixAvailable: data['windows_msix_available'] == true,
    );
  }

  /// Version name.
  final String version;

  /// Build number.
  final int buildNumber;

  /// What changed (Markdown).
  final String log;

  /// Whether it is a pre-release.
  final bool prerelease;

  /// The release page.
  final String releaseUrl;

  /// The Android ABIs this release has packages for.
  final Set<String> androidAbis;

  /// Whether this release has a Windows MSIX package.
  final bool windowsMsixAvailable;

  /// Whether it is newer than the installed version.
  bool get isNewer => isNewerVersion(version, appVersion);
}

/// One downloadable file of a release.
final class ReleaseFile {
  /// Creates the file.
  const new({required this.name, required this.size, required this.downloads, required this.url});

  /// Reads one entry of `files` (or GitHub's `assets`).
  factory fromJson(Map<String, Object?> json) => ReleaseFile(
    name: _string(json['name']),
    size: _size(json['size']),
    downloads: _int(json['downloads'] ?? json['downloadCount']) ?? 0,
    url: _string(json['url'] ?? json['browser_download_url']),
  );

  /// File name.
  final String name;

  /// Size as shown (`137.77mb`).
  final String size;

  /// Download count.
  final int downloads;

  /// Download address.
  final String url;
}

/// One release of `assets/releases.json` (3.x `ReleaseModel`).
final class ReleaseInfo {
  /// Creates the release.
  const new({
    required this.version,
    required this.date,
    this.title = '',
    this.github = '',
    this.authorName = '',
    this.authorAvatar = '',
    this.changelog = '',
    this.files = const [],
  });

  /// Reads one entry; GitHub API names are accepted too (3.x).
  factory fromJson(Map<String, Object?> json) {
    final files = json['files'] ?? json['assets'];
    final author = json['author'] is Map ? (json['author']! as Map).cast<String, Object?>() : const <String, Object?>{};
    return ReleaseInfo(
      version: _string(json['version'] ?? json['tagName']),
      title: _string(json['title'] ?? json['name']),
      date: _string(json['date'] ?? json['publishedAt']),
      github: _string(json['github'] ?? json['url']),
      authorName: _string(author['name'] ?? author['login']),
      authorAvatar: _string(author['avatar'] ?? author['avatar_url']),
      changelog: _string(json['changelog'] ?? json['body']),
      files: [
        if (files is List)
          for (final file in files.whereType<Map<Object?, Object?>>()) ReleaseFile.fromJson(file.cast()),
      ],
    );
  }

  /// Version name.
  final String version;

  /// Title.
  final String title;

  /// Publication date (`2026-09-27`).
  final String date;

  /// The release page.
  final String github;

  /// Who published it.
  final String authorName;

  /// The publisher's avatar.
  final String authorAvatar;

  /// What changed (Markdown).
  final String changelog;

  /// Downloadable files.
  final List<ReleaseFile> files;
}

/// The releases of `releases.json` (a list, or `{releases: [...]}`), newest
/// first: by date, then by version (3.x `ReleaseHistoryRepository.parse`).
List<ReleaseInfo> parseReleases(Object? json) {
  final raw = switch (json) {
    final List<Object?> values => values,
    {'releases': final List<Object?> values} => values,
    _ => throw const FormatException('Invalid release history payload'),
  };
  final releases =
      [
        for (final entry in raw.whereType<Map<Object?, Object?>>())
          if (ReleaseInfo.fromJson(entry.cast()) case final release when release.version.isNotEmpty) release,
      ]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : compareVersions(b.version, a.version);
      });
  return List.unmodifiable(releases);
}

/// A web address the update pages may open or copy: http(s), with a host
/// and no user info (3.x `updateDownloadUri`).
Uri? updateDownloadUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

/// Kinds of installation packages a release offers (3.x
/// `ReleaseAssetUrls`; the keys are 3.x's).
enum PackageKind {
  /// Android arm64-v8a APK.
  androidArm64('android-arm64-v8a', ['android', 'arm64-v8a'], ['.apk']),

  /// Android armeabi-v7a APK.
  androidArm32('android-armeabi-v7a', ['android', 'armeabi-v7a'], ['.apk']),

  /// Android x86_64 APK.
  androidX64('android-x86_64', ['android', 'x86_64'], ['.apk']),

  /// Windows x64 installer.
  windowsSetup('windows-x64-setup.exe', ['windows', 'setup'], ['.exe'], preferred: ['x64']),

  /// Windows x64 MSIX.
  windowsMsix('windows-x64.msix', ['windows', 'x64'], ['.msix']),

  /// Windows x64 portable ZIP.
  windowsPortable('windows-x64-portable.zip', ['windows', 'portable'], ['.zip'], preferred: ['x64']),

  /// macOS universal disk image.
  macosDmg('macos-universal.dmg', ['macos', 'universal'], ['.dmg']),

  /// macOS universal ZIP.
  macosZip('macos-universal.zip', ['macos', 'universal'], ['.zip']);

  new(this.key, this.required, this.extensions, {this.preferred = const []});

  /// 3.x's key.
  final String key;

  /// Words the file name must contain.
  final List<String> required;

  /// Allowed endings of the name or the address.
  final List<String> extensions;

  /// Words that make a file the better match.
  final List<String> preferred;

  /// The best file of [files] for this kind (https only; release builds and
  /// shorter names win), or null.
  ReleaseFile? pick(Iterable<ReleaseFile> files) {
    ReleaseFile? best;
    var bestScore = -1;
    for (final file in files) {
      final name = file.name.trim().toLowerCase();
      final url = file.url.trim().toLowerCase();
      final uri = Uri.tryParse(file.url.trim());
      if (name.isEmpty || uri == null || uri.scheme != 'https' || !uri.hasAuthority) continue;
      if (!extensions.any((ending) => name.endsWith(ending) || url.endsWith(ending))) continue;
      if (!required.every(name.contains)) continue;
      final score = preferred.where(name.contains).length + (name.contains('release') ? 1 : 0);
      final better =
          best == null ||
          score > bestScore ||
          (score == bestScore &&
              (name.length < best.name.length ||
                  (name.length == best.name.length && name.compareTo(best.name.toLowerCase()) < 0)));
      if (better) {
        best = file;
        bestScore = score;
      }
    }
    return best;
  }
}

/// Download mirrors put in front of a GitHub download address (3.x
/// `plugins/update.dart`; resumable ones first).
const List<String> downloadMirrorPrefixes = [
  'https://cdn.gh-proxy.org/',
  'https://edgeone.gh-proxy.org/',
  'https://hk.gh-proxy.org/',
  'https://gh.noki.eu.org/',
  'https://gh-proxy.com/',
  'https://slink.ltd/',
  'https://gh.catmak.name/',
  'https://proxy.gitwarp.top/',
  'https://github.ednovas.xyz/',
  'https://ghproxy.monkeyray.net/',
  'https://fastgit.cc/',
  'https://ghfile.geekertao.top/',
  'https://gh-proxy.org/',
  'https://ghproxy.net/',
  'https://wget.la/',
  'https://git.yylx.win/',
  'https://g.blfrp.cn/',
];

/// The download sources of [url]: only the address itself with
/// [githubOrigin], else every mirror and then the address (3.x
/// `getMirrorUrls`).
List<String> downloadSources(String url, {required bool githubOrigin}) {
  final uri = updateDownloadUri(url);
  if (uri == null) return const [];
  final plain = uri.toString();
  if (githubOrigin) return [plain];
  return List.unmodifiable({for (final prefix in downloadMirrorPrefixes) '$prefix$plain', plain});
}

/// The update platform key of this device (3.x `_currentPlatformKey`).
String currentUpdatePlatform() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isIOS) return 'ios';
  if (Platform.isLinux) return 'linux';
  return 'default';
}

/// Reads the update files from the repository through the mirrors (3.x
/// `VersionUtil.checkUpdate` and `ReleaseHistoryRepository`).
class UpdateFeed {
  /// A feed over [http]; [githubOrigin] reads GitHub only (setting
  /// `useGitHubOriginForUpdates`), [now] stamps the addresses past caches.
  new(this.http, {required this.githubOrigin, String? platform, DateTime Function()? now})
    : platform = platform ?? currentUpdatePlatform(),
      _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  /// Whether only GitHub itself is asked.
  final bool githubOrigin;

  /// The `platforms` key of `version.json`.
  final String platform;

  final DateTime Function() _now;

  static const Map<String, String> _headers = {
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/151.0.0.0 Safari/537.36',
    'accept': 'application/json,text/plain,*/*',
  };

  List<Uri> _sources(String path) {
    final stamp = '${_now().millisecondsSinceEpoch}';
    final urls = githubOrigin ? [updateRepository.raw(path)] : updateRepository.mirrors(path);
    return [
      for (final url in urls) url.replace(queryParameters: {...url.queryParameters, 'ts': stamp}),
    ];
  }

  /// The newest version for this platform; null when no source answered
  /// (3.x gave up after 10 seconds). Throws [FormatException] for an
  /// incomplete file.
  Future<UpdateInfo?> latest({Duration timeout = const Duration(seconds: 10)}) async {
    final json = await raceJson(http, 'update', _sources('assets/version.json'), headers: _headers, timeout: timeout);
    return json == null ? null : UpdateInfo.fromJson(json, platform: platform);
  }

  /// Every release, newest first; null when no source answered.
  Future<List<ReleaseInfo>?> releases({Duration timeout = const Duration(seconds: 15)}) =>
      raceFirst<List<ReleaseInfo>>(_sources('assets/releases.json'), (url, cancel) async {
        final response = await http.send(
          LiveRequest(site: 'update', url: url, headers: _headers, timeout: timeout, cancel: cancel),
        );
        if (response.status != 200) return null;
        return parseReleases(response.json);
      }, timeout: timeout);
}

/// The update feed of the pages (tests replace it).
final Provider<UpdateFeed> updateFeedProvider = Provider<UpdateFeed>((ref) {
  final services = ref.watch(appServicesProvider);
  return UpdateFeed(services.http, githubOrigin: services.store.settings.get(Settings.useGitHubOriginForUpdates));
});

String _string(Object? value) => value?.toString().trim() ?? '';

int? _int(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text.trim()),
  _ => null,
};

String _size(Object? value) => switch (value) {
  null => '0.0mb',
  final String text when text.trim().isEmpty => '0.0mb',
  final String text => text.trim(),
  final num bytes => '${(bytes / (1024 * 1024)).toStringAsFixed(2)}mb',
  _ => value.toString(),
};
