import 'dart:io';

import 'package:flutter/services.dart';

/// The asset key of the Material Symbols Rounded font in the test bundle.
const symbolsFontAsset = 'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf';

/// The family `Symbols.*_rounded` glyphs name, as a package font.
const symbolsFamily = 'packages/material_symbols_icons/MaterialSymbolsRounded';

var _loaded = false;

/// Registers Material Symbols Rounded once per test isolate; the test engine
/// otherwise draws every glyph as a box.
Future<void> loadSymbolsFont() async {
  if (_loaded) return;
  _loaded = true;
  await (FontLoader(symbolsFamily)..addFont(rootBundle.load(symbolsFontAsset))).load();
}

/// The Flutter SDK running the tests.
String? get flutterRoot {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return root;
  // flutter_tester lives in <root>/bin/cache/artifacts/engine/<platform>/.
  final tester = File(Platform.resolvedExecutable).absolute.path.split(Platform.pathSeparator);
  final bin = tester.lastIndexOf('bin');
  return bin > 0 ? tester.sublist(0, bin).join(Platform.pathSeparator) : null;
}
