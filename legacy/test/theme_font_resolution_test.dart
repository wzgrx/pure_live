import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/style/theme.dart';

void main() {
  group('resolveAppFontFamily', () {
    test('uses a downloaded font on every platform', () {
      expect(
        resolveAppFontFamily(selectedName: 'local-font-id', customFonts: const {'local-font-id'}, isWindows: false),
        'local-font-id',
      );
    });

    test('uses the native system font on Android and other platforms', () {
      expect(resolveAppFontFamily(selectedName: 'Default', customFonts: const <String>{}, isWindows: false), isNull);
    });

    test('does not retain a removed custom font id', () {
      expect(
        resolveAppFontFamily(selectedName: 'removed-font-id', customFonts: const <String>{}, isWindows: false),
        isNull,
      );
    });

    test('keeps the optimized Windows CJK fallback', () {
      expect(
        resolveAppFontFamily(selectedName: 'Default', customFonts: const <String>{}, isWindows: true),
        'Microsoft YaHei',
      );
    });
  });
}
