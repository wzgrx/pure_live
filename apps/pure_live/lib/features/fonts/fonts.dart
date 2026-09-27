import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/data_root.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';

/// A font the app can download (F-DM-06, F-SET-01): only fonts with a clear
/// licence that allows redistribution (SIL OFL 1.1, IPA Font License 1.0),
/// from 3.x's catalogue.
@immutable
final class FontEntry {
  const new({
    required this.id,
    required this.name,
    required this.files,
    required this.licenseName,
    this.description = '',
    this.official = '',
    this.licenseUrl = '',
  });

  factory fromJson(Map<String, Object?> json) {
    final license = json['license'];
    return FontEntry(
      id: json['id']! as String,
      name: json['name']! as String,
      files: [for (final file in json['files']! as List<Object?>) file! as String],
      description: json['desc'] as String? ?? '',
      official: json['official'] as String? ?? '',
      licenseName: license is Map ? '${license['name'] ?? ''}' : '',
      licenseUrl: license is Map ? '${license['url'] ?? ''}' : '',
    );
  }

  final String id;
  final String name;

  /// Paths in the font repository.
  final List<String> files;
  final String description;
  final String official;
  final String licenseName;
  final String licenseUrl;

  /// The family name the app registers the files under.
  String get family => fontFamilyOf(id);
}

/// The registered family of font [id].
String fontFamilyOf(String id) => 'PureLive-$id';

/// The family for a stored font setting, null for the system font.
String? familyForSetting(String id) => id.isEmpty ? null : fontFamilyOf(id);

/// The catalogue shipped with the app.
final FutureProvider<List<FontEntry>> fontCatalogProvider = FutureProvider<List<FontEntry>>((ref) async {
  final list = jsonDecode(await rootBundle.loadString('assets/fonts/fonts.json')) as List<Object?>;
  return [for (final item in list) FontEntry.fromJson(item! as Map<String, Object?>)];
});

/// Where each font file is downloaded from, first first: jsDelivr's two
/// CDNs, then GitHub itself (3.x's font repository).
List<Uri> fontSources(String file) {
  final path = file.split('/').map(Uri.encodeComponent).join('/');
  return [
    Uri.parse('https://cdn.jsdelivr.net/gh/liuchuancong/fonts@master/$path'),
    Uri.parse('https://fastly.jsdelivr.net/gh/liuchuancong/fonts@master/$path'),
    Uri.parse('https://raw.githubusercontent.com/liuchuancong/fonts/master/$path'),
  ];
}

/// Whether [bytes] start like a TrueType, OpenType or collection file.
bool looksLikeFont(Uint8List bytes) {
  if (bytes.length < 12) return false;
  final tag = String.fromCharCodes(bytes.sublist(0, 4));
  return tag == 'OTTO' ||
      tag == 'true' ||
      tag == 'ttcf' ||
      (bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0);
}

/// The downloaded fonts in `<data root>/FONTS/<id>/`.
final class FontFiles {
  new(this.root, this._http);

  final Directory root;
  final LiveHttp _http;
  final Set<String> _loaded = {};

  Directory _dir(FontEntry font) => Directory('${root.path}${Platform.pathSeparator}${font.id}');

  File _file(FontEntry font, String path) => File('${_dir(font).path}${Platform.pathSeparator}${path.split('/').last}');

  /// Whether every file of [font] is here.
  Future<bool> installed(FontEntry font) async {
    for (final path in font.files) {
      if (!_file(font, path).existsSync()) return false;
    }
    return true;
  }

  /// Downloads [font] file by file, each from the first source that answers
  /// with a font; [progress] gets 0–1. A failed download leaves nothing.
  Future<void> download(FontEntry font, {void Function(double progress)? progress}) async {
    final dir = _dir(font);
    await dir.create(recursive: true);
    try {
      for (final (index, path) in font.files.indexed) {
        final target = _file(font, path);
        if (!target.existsSync()) {
          Uint8List? bytes;
          Object? lastError;
          for (final url in fontSources(path)) {
            try {
              final response = await _http.send(
                LiveRequest(site: 'fonts', url: url, timeout: const Duration(minutes: 3)),
              );
              final body = Uint8List.fromList(response.bytes);
              if (response.status == 200 && looksLikeFont(body)) {
                bytes = body;
                break;
              }
              lastError = StateError('HTTP ${response.status}');
            } on Object catch (error) {
              lastError = error;
            }
          }
          if (bytes == null) throw FontDownloadError(font.name, lastError);
          final part = File('${target.path}.part');
          await part.writeAsBytes(bytes, flush: true);
          await part.rename(target.path);
        }
        progress?.call((index + 1) / font.files.length);
      }
    } on Object {
      await delete(font);
      rethrow;
    }
  }

  /// Removes [font]'s files. A font already registered stays usable until
  /// the app restarts.
  Future<void> delete(FontEntry font) async {
    final dir = _dir(font);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Registers [font]'s files under [FontEntry.family]; false when they are
  /// not all here. Text using the family re-lays out once it is loaded.
  Future<bool> load(FontEntry font) async {
    if (_loaded.contains(font.id)) return true;
    if (!await installed(font)) return false;
    final loader = FontLoader(font.family);
    for (final path in font.files) {
      final bytes = await _file(font, path).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
    _loaded.add(font.id);
    return true;
  }
}

/// A font that could not be downloaded from any source.
final class FontDownloadError implements Exception {
  const new(this.font, this.cause);

  final String font;
  final Object? cause;

  @override
  String toString() => '“$font”下载失败，检查网络或代理后重试';
}

/// The app's font files.
final Provider<FontFiles> fontFilesProvider = Provider<FontFiles>(
  (ref) => FontFiles(
    Directory('${ref.watch(dataRootProvider).path}${Platform.pathSeparator}FONTS'),
    ref.watch(liveHttpProvider),
  ),
);

/// Loads the chosen interface and danmaku fonts when the app starts and when
/// the choice changes; the themes name their families from the settings, so
/// text switches to a font as soon as it is registered.
final Provider<void> chosenFontsProvider = Provider<void>((ref) {
  final settings = ref.watch(storeProvider).settings;
  Future<void> load() async {
    final ids = {settings.get(Settings.appFontFamily), settings.get(Settings.danmakuFontFamily)}..remove('');
    if (ids.isEmpty) return;
    try {
      final catalogue = await ref.read(fontCatalogProvider.future);
      final files = ref.read(fontFilesProvider);
      for (final font in catalogue.where((font) => ids.contains(font.id))) {
        await files.load(font);
      }
    } on Object {
      // A missing or broken font leaves the system font in place.
    }
  }

  unawaited(load());
  final subscription = settings.changes
      .where((id) => id == Settings.appFontFamily.id || id == Settings.danmakuFontFamily.id)
      .listen((_) => unawaited(load()));
  ref.onDispose(subscription.cancel);
});

/// The interface font's family, null for the platform font.
final appFontFamilySetting = NotifierProvider<SettingNotifier<String>, String>(
  () => SettingNotifier(Settings.appFontFamily),
);
