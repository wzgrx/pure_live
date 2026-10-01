import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/downloads.dart';
import 'package:pure_live/app/services.dart';

/// One font family of the cloud list (3.x `FontModel`,
/// `assets/fonts/fonts-manifest.json`): files in the `liuchuancong/fonts`
/// repository, a description, the official page and the license.
@immutable
final class FontFamily {
  /// Creates the family.
  const new({
    required this.id,
    required this.name,
    required this.files,
    this.description = '',
    this.official = '',
    this.license = '',
    this.licenseUrl = '',
  });

  /// Reads one manifest entry.
  factory fromJson(Map<String, Object?> json) {
    final license = json['license'];
    return FontFamily(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      files: [for (final file in json['files'] as List<Object?>? ?? const []) '$file'],
      description: '${json['desc'] ?? ''}',
      official: '${json['official'] ?? ''}',
      license: license is Map ? '${license['name'] ?? ''}' : '',
      licenseUrl: license is Map ? '${license['url'] ?? ''}' : '',
    );
  }

  /// The id: the folder name and the registered family name (3.x).
  final String id;

  /// The shown name.
  final String name;

  /// Paths in the font repository, `<folder>/<file>.ttf`.
  final List<String> files;

  /// One sentence about the font.
  final String description;

  /// The font's home page.
  final String official;

  /// License name.
  final String license;

  /// License page.
  final String licenseUrl;

  /// The file names (last path segment) of [files].
  List<String> get fileNames => [for (final file in files) file.split('/').last];
}

/// The bundled cloud font list (3.x read the same file).
const String fontManifestAsset = 'assets/fonts/fonts-manifest.json';

/// The font repository (3.x `GitHubMirror(owner: 'liuchuancong', repo: 'fonts')`).
const GitHubMirror fontRepository = GitHubMirror(owner: 'liuchuancong', repo: 'fonts');

/// Reads the font list; entries with unsafe ids or file paths are dropped.
List<FontFamily> parseFontManifest(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return List.unmodifiable([
    for (final item in decoded)
      if (item is Map<String, Object?>)
        if (FontFamily.fromJson(item) case final family when isSafeFontId(family.id) && validFontFiles(family.files))
          family,
  ]);
}

/// Whether [id] can be a folder name (3.x `_isSafeFontId`).
bool isSafeFontId(String id) => id.isNotEmpty && id != '.' && id != '..' && RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(id);

/// Whether every path is `segments/name.ttf|otf` without `..`, backslashes
/// or repeated names (3.x's manifest checks).
bool validFontFiles(List<String> files) {
  if (files.isEmpty) return false;
  final names = <String>{};
  for (final path in files) {
    final parts = path.split('/');
    final name = parts.last;
    final lower = name.toLowerCase();
    if (path.contains(r'\') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(name) ||
        !(lower.endsWith('.ttf') || lower.endsWith('.otf')) ||
        !names.add(name)) {
      return false;
    }
  }
  return true;
}

/// Whether [file] starts like a TrueType/OpenType font (3.x `_isValidFontFile`).
bool isFontFile(File file) {
  try {
    if (!file.existsSync() || file.lengthSync() < 12) return false;
    final handle = file.openSync();
    try {
      final head = handle.readSync(4);
      if (head.length != 4) return false;
      final tag = String.fromCharCodes(head);
      return (head[0] == 0 && head[1] == 1 && head[2] == 0 && head[3] == 0) ||
          tag == 'OTTO' ||
          tag == 'true' ||
          tag == 'typ1' ||
          tag == 'ttcf';
    } finally {
      handle.closeSync();
    }
  } on FileSystemException {
    return false;
  }
}

/// Registers font bytes under a family name (Flutter's `FontLoader`;
/// replaced in tests).
typedef FontRegistrar = Future<void> Function(String family, List<Future<ByteData>> fonts);

Future<void> _registerWithFontLoader(String family, List<Future<ByteData>> fonts) async {
  final loader = FontLoader(family);
  fonts.forEach(loader.addFont);
  await loader.load();
}

/// The downloaded fonts (3.x `FontDownloadManager` and the font part of
/// `FontSettingsController`): `<data folder>/fonts/<id>/` holds a family's
/// files; a download goes to `.<id>.pending` and replaces the folder only
/// when every file arrived and looks like a font.
///
/// A family is registered with Flutter under its id ([registered]); the app
/// theme uses the registered app font (`resolveAppFontFamily`), the danmaku
/// layer the danmaku font. A file name ([Settings.fontFamilyFileName])
/// registers one weight only (3.x's "lock weight").
///
/// 3.x's choice is kept: when the chosen family is not here but in 3.x's
/// font folder ([legacyRoots]), it is copied over (3.x's files are only
/// read); otherwise the settings row says it needs downloading.
final class FontLibrary extends ChangeNotifier {
  /// Creates the library in [root] (`<data folder>/fonts`).
  new({
    required this.root,
    required this.http,
    this.legacyRoots = const [],
    FontRegistrar? register,
    Future<String> Function()? manifest,
  }) : _register = register ?? _registerWithFontLoader,
       _manifest = manifest ?? (() => rootBundle.loadString(fontManifestAsset));

  /// The fonts folder.
  final Directory root;

  /// Transport of the downloads (the app proxy applies).
  final LiveHttp http;

  /// 3.x's font folders (`<3.x data>/DOWNLOADS/fonts`).
  final List<Directory> legacyRoots;

  final FontRegistrar _register;
  final Future<String> Function() _manifest;
  final Set<String> _registered = {};
  final Map<String, String> _registeredFile = {};
  List<FontFamily>? _families;

  /// Family ids registered with Flutter (for `resolveAppFontFamily`).
  Set<String> get registered => Set.unmodifiable(_registered);

  /// The cloud list; empty when the bundled file cannot be read.
  Future<List<FontFamily>> families() async {
    final cached = _families;
    if (cached != null) return cached;
    try {
      return _families = parseFontManifest(await _manifest());
    } on Object catch (error) {
      log('Font list unreadable', name: 'Fonts', error: error);
      return _families = const [];
    }
  }

  /// The family [id] of the list, or null.
  Future<FontFamily?> family(String id) async => (await families()).where((family) => family.id == id).firstOrNull;

  /// The folder of [id].
  Directory folderOf(String id) => Directory(p.join(root.path, id));

  /// The font files of [id] on this device, sorted; empty when not here.
  List<File> filesOf(String id) {
    if (!isSafeFontId(id)) return const [];
    _finishInterrupted(id);
    final folder = folderOf(id);
    if (!folder.existsSync()) return const [];
    final files = [
      for (final entity in folder.listSync())
        if (entity is File && _isFontName(entity.path) && isFontFile(entity)) entity,
    ]..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Whether [id] is downloaded.
  bool isDownloaded(String id) => filesOf(id).isNotEmpty;

  /// Bytes of [id]'s folder, or null when not downloaded.
  int? sizeOf(String id) {
    final files = filesOf(id);
    if (files.isEmpty) return null;
    return files.fold<int>(0, (total, file) => total + file.lengthSync());
  }

  static bool _isFontName(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf');
  }

  /// A download stopped between moving the old folder away and the new one
  /// in: the old one comes back (3.x `_resolveFontDirectory`).
  void _finishInterrupted(String id) {
    final folder = folderOf(id);
    final previous = Directory(p.join(root.path, '.$id.previous'));
    if (!previous.existsSync()) return;
    try {
      if (folder.existsSync()) {
        previous.deleteSync(recursive: true);
      } else {
        previous.renameSync(folder.path);
      }
    } on FileSystemException {
      // Tried again next time.
    }
  }

  /// Registers [id] (all its files, or only [fileName]) with Flutter; false
  /// when it is not downloaded or the file is missing.
  Future<bool> load(String id, {String fileName = ''}) async {
    final files = [
      for (final file in filesOf(id))
        if (fileName.isEmpty || p.basename(file.path) == fileName) file,
    ];
    if (files.isEmpty) return false;
    if (_registered.contains(id) && _registeredFile[id] == fileName) return true;
    try {
      await _register(id, [for (final file in files) file.readAsBytes().then(ByteData.sublistView)]);
    } on Object catch (error) {
      log('Font $id did not load', name: 'Fonts', error: error);
      return false;
    }
    _registered.add(id);
    _registeredFile[id] = fileName;
    notifyListeners();
    return true;
  }

  /// Copies [id] from 3.x's font folders when it is there and not here;
  /// whether it is here afterwards.
  Future<bool> adoptLegacy(String id) async {
    if (!isSafeFontId(id)) return false;
    if (isDownloaded(id)) return true;
    for (final legacy in legacyRoots) {
      final source = Directory(p.join(legacy.path, id));
      if (!source.existsSync()) continue;
      final fonts = [
        for (final entity in source.listSync())
          if (entity is File && _isFontName(entity.path) && isFontFile(entity)) entity,
      ];
      if (fonts.isEmpty) continue;
      try {
        final staged = Directory(p.join(root.path, '.$id.pending'));
        if (staged.existsSync()) staged.deleteSync(recursive: true);
        staged.createSync(recursive: true);
        for (final font in fonts) {
          await font.copy(p.join(staged.path, p.basename(font.path)));
        }
        await staged.rename(folderOf(id).path);
        return true;
      } on FileSystemException catch (error) {
        log('3.x font $id not copied', name: 'Fonts', error: error);
      }
    }
    return false;
  }

  /// At start (before the first frame, 3.x `initUserFontLifecycle`):
  /// registers the chosen app and danmaku fonts, taking 3.x's files when
  /// needed. A chosen weight that is gone falls back to the whole family.
  Future<void> restore(SettingsStore settings) async {
    for (final (name, file) in [
      (Settings.fontFamilyName, Settings.fontFamilyFileName),
      (Settings.danmakuFontFamilyName, Settings.danmakuFontFamilyFileName),
    ]) {
      final id = settings.get(name);
      if (id.isEmpty || id == name.defaultValue) continue;
      if (!isDownloaded(id)) await adoptLegacy(id);
      final weight = settings.get(file);
      if (await load(id, fileName: weight)) continue;
      if (weight.isNotEmpty && await load(id)) await settings.reset(file);
    }
  }

  /// Downloads [family] (every file, from the fastest mirror; files already
  /// here are kept) and replaces its folder when complete. [onProgress]
  /// gets the files done and the total. Throws [DownloadException].
  Future<void> download(
    FontFamily family, {
    void Function(int done, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    if (!isSafeFontId(family.id) || !validFontFiles(family.files)) {
      throw const DownloadException(DownloadFailure.network, 'invalid manifest entry');
    }
    _finishInterrupted(family.id);
    final folder = folderOf(family.id);
    final staged = Directory(p.join(root.path, '.${family.id}.pending'));
    final previous = Directory(p.join(root.path, '.${family.id}.previous'));
    final downloader = FileDownloader(http, site: 'fonts');
    try {
      if (staged.existsSync()) staged.deleteSync(recursive: true);
      staged.createSync(recursive: true);
      for (final (index, path) in family.files.indexed) {
        onProgress?.call(index, family.files.length);
        final name = path.split('/').last;
        final existing = File(p.join(folder.path, name));
        final target = File(p.join(staged.path, name));
        if (isFontFile(existing)) {
          await existing.copy(target.path);
          continue;
        }
        final mirrors = fontRepository.mirrors(path);
        final fastest = await fastestUrl(http, 'fonts', mirrors, timeout: const Duration(seconds: 15));
        final sources = [?fastest, ...mirrors.where((url) => url != fastest)];
        await downloader.download(
          sources.take(4).toList(),
          target,
          cancel: cancel,
          headers: const {'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/151.0.0.0 Safari/537.36'},
        );
        if (!isFontFile(target)) throw const DownloadException(DownloadFailure.network, 'not a font');
      }
      onProgress?.call(family.files.length, family.files.length);
      final hadOld = folder.existsSync();
      if (hadOld) folder.renameSync(previous.path);
      try {
        staged.renameSync(folder.path);
      } on FileSystemException {
        if (hadOld && previous.existsSync() && !folder.existsSync()) previous.renameSync(folder.path);
        rethrow;
      }
      if (previous.existsSync()) previous.deleteSync(recursive: true);
    } on FileSystemException catch (error) {
      throw DownloadException(DownloadFailure.disk, error.message);
    } finally {
      if (staged.existsSync()) {
        try {
          staged.deleteSync(recursive: true);
        } on FileSystemException {
          // Removed by the next download.
        }
      }
      notifyListeners();
    }
  }

  /// Deletes [id]'s files; the settings choosing it go back to the system
  /// font (3.x `uninstallFontFamily`). A registered family stays usable
  /// until the app restarts (Flutter cannot unload fonts).
  Future<bool> delete(String id, SettingsStore settings) async {
    if (!isSafeFontId(id)) return false;
    try {
      for (final folder in [
        folderOf(id),
        Directory(p.join(root.path, '.$id.pending')),
        Directory(p.join(root.path, '.$id.previous')),
      ]) {
        if (folder.existsSync()) folder.deleteSync(recursive: true);
      }
    } on FileSystemException catch (error) {
      log('Font $id not deleted', name: 'Fonts', error: error);
      return false;
    }
    if (settings.get(Settings.fontFamilyName) == id) {
      await settings.reset(Settings.fontFamilyName);
      await settings.reset(Settings.fontFamilyFileName);
    }
    if (settings.get(Settings.danmakuFontFamilyName) == id) {
      await settings.reset(Settings.danmakuFontFamilyName);
      await settings.reset(Settings.danmakuFontFamilyFileName);
    }
    _registered.remove(id);
    notifyListeners();
    return true;
  }
}

/// 3.x's font folders next to its settings boxes: `<3.x data>/DOWNLOADS/fonts`
/// for each box in `HIVE_DB` (or the data folder itself).
List<Directory> legacyFontRoots(Iterable<String> hiveFiles) {
  final roots = <String>{};
  for (final box in hiveFiles) {
    final folder = p.dirname(box);
    final data = p.basename(folder).toUpperCase() == 'HIVE_DB' ? p.dirname(folder) : folder;
    roots.add(p.join(data, 'DOWNLOADS', 'fonts'));
  }
  return [for (final root in roots) Directory(root)];
}

/// The font library; `main` overrides it with the restored one.
final Provider<FontLibrary> fontLibraryProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return FontLibrary(root: Directory(p.join(services.dataRoot.path, 'fonts')), http: services.http);
});
