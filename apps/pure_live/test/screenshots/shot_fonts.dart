import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pure_live_app/features/fonts/fonts.dart';

/// Real fonts for the screenshots; the test engine otherwise draws every
/// glyph as a box (README.md).
///
/// - Latin on Android is Roboto. The theme leaves the family empty there
///   (the system's font); the test engine would draw that as boxes, so the
///   Android and TV screenshots choose the interface font [appFontId]
///   (F-SET-01), registered as Roboto, and every style carries it. Windows
///   screenshots keep their explicit family.
/// - On-video danmaku has no fallback list; its font [danmakuFontId] is
///   registered as Noto Sans CJK SC.
/// - Chinese is Noto Sans CJK from the system (Debian and Ubuntu:
///   `fonts-noto-cjk`). The Simplified face stands in for the theme's first
///   Simplified fallback (`Microsoft YaHei UI`, also the explicit Windows
///   family) and the Traditional face for `Microsoft JhengHei UI`, so every
///   glyph Roboto lacks resolves to it instead of the test font.
/// - Icons are Material Icons from the Flutter SDK.
abstract final class ShotFonts {
  /// Noto Sans CJK, regular.
  static const cjkRegular = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';

  /// Noto Sans CJK, bold.
  static const cjkBold = '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc';

  /// The interface font id the Android and TV screenshots choose.
  static const appFontId = 'screenshot-roboto';

  /// The danmaku font id every screenshot chooses.
  static const danmakuFontId = 'screenshot-noto';

  /// Faces of the CJK collections (`fc-scan --format "%{index} %{family[0]}\n"`).
  static const _simplified = 2;
  static const _traditional = 3;

  /// The Flutter SDK running the tests.
  static String? get flutterRoot {
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null && root.isNotEmpty) return root;
    // flutter_tester lives in <root>/bin/cache/artifacts/engine/<platform>/.
    final tester = File(Platform.resolvedExecutable).absolute.path.split(Platform.pathSeparator);
    final bin = tester.lastIndexOf('bin');
    return bin > 0 ? tester.sublist(0, bin).join(Platform.pathSeparator) : null;
  }

  static String _material(String file) =>
      [flutterRoot ?? '', 'bin', 'cache', 'artifacts', 'material_fonts', file].join(Platform.pathSeparator);

  static List<String> get _files => [
    cjkRegular,
    cjkBold,
    _material('MaterialIcons-Regular.otf'),
    _material('Roboto-Regular.ttf'),
    _material('Roboto-Medium.ttf'),
    _material('Roboto-Bold.ttf'),
  ];

  /// Why the screenshots cannot run here (a missing font file), or null.
  static String? get missing {
    for (final path in _files) {
      if (!File(path).existsSync()) return 'screenshot font not found: $path (see test/screenshots/README.md)';
    }
    return null;
  }

  static var _loaded = false;

  /// Registers the fonts once per test isolate.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final regular = File(cjkRegular).readAsBytesSync();
    final bold = File(cjkBold).readAsBytesSync();
    ByteData file(String path) => ByteData.sublistView(File(path).readAsBytesSync());
    Future<void> family(String name, List<ByteData> fonts) async {
      final loader = FontLoader(name);
      for (final font in fonts) {
        loader.addFont(Future.value(font));
      }
      await loader.load();
    }

    final simplified = [collectionFace(regular, _simplified), collectionFace(bold, _simplified)];
    final traditional = [collectionFace(regular, _traditional), collectionFace(bold, _traditional)];
    final roboto = [
      file(_material('Roboto-Regular.ttf')),
      file(_material('Roboto-Medium.ttf')),
      file(_material('Roboto-Bold.ttf')),
    ];
    await family('Roboto', roboto);
    await family(fontFamilyOf(appFontId), roboto);
    await family(fontFamilyOf(danmakuFontId), simplified);
    await family('MaterialIcons', [file(_material('MaterialIcons-Regular.otf'))]);
    // Windows' default family for text outside the theme.
    await family('Segoe UI', simplified);
    await family('Microsoft YaHei UI', simplified);
    await family('Microsoft JhengHei UI', traditional);
  }

  /// Face [index] of an OpenType collection as a standalone font: the table
  /// directory of that face with its tables copied after it.
  static ByteData collectionFace(Uint8List collection, int index) {
    final data = ByteData.sublistView(collection);
    if (data.getUint32(0) != 0x74746366) throw ArgumentError('not a font collection'); // 'ttcf'
    final offset = data.getUint32(12 + 4 * index);
    final count = data.getUint16(offset + 4);
    final header = 12 + 16 * count;
    int padded(int length) => (length + 3) & ~3;
    var size = header;
    for (var i = 0; i < count; i++) {
      size += padded(data.getUint32(offset + 12 + 16 * i + 12));
    }
    final out = ByteData(size);
    final bytes = out.buffer.asUint8List()..setRange(0, 12, collection, offset);
    var at = header;
    for (var i = 0; i < count; i++) {
      final record = offset + 12 + 16 * i;
      final source = data.getUint32(record + 8);
      final length = data.getUint32(record + 12);
      // Tag and checksum stay; the offset points into the new file.
      bytes
        ..setRange(12 + 16 * i, 12 + 16 * i + 8, collection, record)
        ..setRange(at, at + length, collection, source);
      out
        ..setUint32(12 + 16 * i + 8, at)
        ..setUint32(12 + 16 * i + 12, length);
      at += padded(length);
    }
    return out;
  }
}
