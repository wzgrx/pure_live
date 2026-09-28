import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

/// Principles §2.6: every icon is a Material Symbols Rounded glyph (or one
/// live_ui draws), named by meaning in `LiveIcons` and shown with `LiveIcon`,
/// which sets the variable axes. This keeps the old ways out of the code:
/// Material Icons (`Icons.*`), Cupertino icons, raw `Symbols.*` glyphs,
/// hand-made `IconData` and plain `Icon` widgets (no optical size, no fill
/// rule) are allowed only inside live_ui's icon code.
void main() {
  // The i18n files are generated and never name icons.
  bool generated(File file) => file.path.endsWith('.g.dart');

  /// The code of every Dart file under [roots], comments removed.
  Map<String, String> sources(List<String> roots) => {
    for (final root in roots)
      for (final file in Directory(root).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') && !generated(file))
          file.path.replaceAll(r'\', '/'): file
              .readAsLinesSync()
              .map((line) => line.replaceFirst(RegExp(r'^\s*//.*'), ''))
              .join('\n'),
  };

  const app = 'lib';
  const liveUi = '../../packages/live_ui/lib';
  // Where the font glyphs and the Icon widget may appear.
  const iconCode = '../../packages/live_ui/lib/src/icons/';

  final rules = <String, RegExp>{
    'Material Icons (Icons.*)': RegExp(r'(?<![\w.])Icons\.\w'),
    'Cupertino icons': RegExp(r'\bCupertinoIcons\.'),
    'a raw Symbols glyph': RegExp(r'(?<![\w.])Symbols\.\w|package:material_symbols_icons/'),
    'a hand-made IconData': RegExp(r'\bIconData\b'),
    'a plain Icon widget (use LiveIcon)': RegExp(r'(?<![\w.])Icon\('),
    'CheckedPopupMenuItem (a Material Icons check; use CheckedMenuItem)': RegExp(r'\bCheckedPopupMenuItem\b'),
  };

  test('lib names icons only through LiveIcons and shows them only with LiveIcon', () {
    final found = <String>[];
    for (final MapEntry(key: path, value: code) in sources([app, liveUi]).entries) {
      if (path.startsWith(iconCode)) continue;
      for (final MapEntry(key: what, value: pattern) in rules.entries) {
        for (final match in pattern.allMatches(code)) {
          final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
          found.add('$path:$line: $what');
        }
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('every LiveIcons glyph is used', () {
    final code = [
      for (final MapEntry(key: path, value: text) in sources([app, liveUi]).entries)
        if (!path.endsWith('/live_icons.dart')) text,
    ].join('\n');
    final unused = [
      for (final icon in LiveIcons.values)
        if (!RegExp('LiveIcons\\.${icon.name}\\b').hasMatch(code)) icon.name,
    ];
    expect(unused, isEmpty, reason: 'drop them from LiveIcons and the README table');
  });
}
