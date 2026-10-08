import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart' as material;

void main() {
  group('resolveAppFontFamily', () {
    test('a downloaded font wins, then YaHei on Windows, else the system font', () {
      expect(resolveAppFontFamily(selectedName: 'my', customFonts: ['my'], isWindows: true), 'my');
      expect(resolveAppFontFamily(selectedName: 'gone', customFonts: ['my'], isWindows: true), 'Microsoft YaHei');
      expect(resolveAppFontFamily(selectedName: 'gone', customFonts: const [], isWindows: false), isNull);
    });
  });

  group('LiveTheme', () {
    test('text sizes follow the font settings as in 3.x', () {
      const sizes = LiveFontSizes(bodySmall: 11, bodyMedium: 14, bodyLarge: 16, titleMedium: 17, titleLarge: 22);
      final text = const LiveTheme(primaryColor: Colors.blue, fontSizes: sizes).light.textTheme;
      expect(text.bodySmall!.fontSize, 11);
      // A01.4 c5: no smaller than the small size.
      expect(text.labelSmall!.fontSize, 11);
      expect(text.bodyMedium!.fontSize, 14);
      expect(text.labelLarge!.fontSize, 14);
      expect(text.bodyLarge!.fontSize, 16);
      expect(text.titleSmall!.fontSize, 16);
      expect(text.titleMedium!.fontSize, 17);
      // A01.2, UI.md §8.2: weights are 400 and 600 (3.x's 500 became 600).
      expect(text.titleMedium!.fontWeight, FontWeight.w600);
      expect(text.titleSmall!.fontWeight, FontWeight.w600);
      expect(text.labelLarge!.fontWeight, FontWeight.w600);
      expect(text.titleLarge!.fontSize, 22);
      expect(text.titleLarge!.fontWeight, FontWeight.w600);
      expect(text.headlineSmall!.fontSize, closeTo(26.4, 1e-9));
      expect(text.headlineLarge!.fontSize, closeTo(35.2, 1e-9));
      expect(text.displayLarge!.fontSize, closeTo(52.25, 1e-9));
      expect(LiveFontSizes.of(text), sizes);
    });

    test('the font family reaches every text style', () {
      final theme = const LiveTheme(primaryColor: Colors.red, fontFamily: 'Microsoft YaHei').dark;
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Microsoft YaHei');
      expect(theme.textTheme.titleLarge!.fontFamily, 'Microsoft YaHei');
    });

    test("keeps the app bar 3.x showed (main.dart's override) and its page transitions", () {
      final theme = const LiveTheme(primaryColor: Colors.teal).light;
      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
      // The platform's alignment; the pages 3.x centred use centredPageTitle.
      expect(theme.appBarTheme.centerTitle, isNull);
      expect(theme.pageTransitionsTheme, appPageTransitionsTheme);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.cardTheme.margin, EdgeInsets.zero);
      expect(theme.tabBarTheme.labelColor, theme.colorScheme.primary);
    });

    test('a dynamic palette is used as given; its dark error colour is replaced', () {
      final light = ColorScheme.fromSeed(seedColor: Colors.green);
      final dark = ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark);
      expect(LiveTheme(colorScheme: light).light.colorScheme.primary, light.primary);
      expect(LiveTheme(colorScheme: dark).dark.colorScheme.error, LiveTheme.darkDynamicError);
      expect(const LiveTheme(primaryColor: Colors.green).dark.colorScheme.error, isNot(LiveTheme.darkDynamicError));
    });

    test('toFlutterColorScheme keeps the system roles', () {
      final source = material.ColorScheme.fromSeed(seedColor: const Color(0xFF3366FF));
      final converted = toFlutterColorScheme(source);
      expect(converted.primary, source.primary);
      expect(converted.surfaceContainerHigh, source.surfaceContainerHigh);
      expect(converted.brightness, Brightness.light);
    });
  });

  group('AppTextStyles', () {
    testWidgets('come from the theme in scope, a local override included', (tester) async {
      final outer = const LiveTheme(primaryColor: Colors.blue).light;
      final inner = const LiveTheme(primaryColor: Colors.blue, fontSizes: LiveFontSizes(bodyMedium: 19)).light;
      late AppTextStyles outerStyles;
      late AppTextStyles innerStyles;
      await tester.pumpWidget(
        MaterialApp(
          theme: outer,
          home: Builder(
            builder: (context) {
              outerStyles = context.textStyles;
              return Theme(
                data: inner,
                child: Builder(
                  builder: (context) {
                    innerStyles = context.textStyles;
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(outerStyles.t13.fontSize, 13);
      expect(innerStyles.t13.fontSize, 19);
      expect(outerStyles.t11.fontSize, outerStyles.t12.fontSize);
      expect(outerStyles.t15SemiBold.fontWeight, FontWeight.w600);
      expect(outerStyles.t13Primary.color, outer.colorScheme.primary);
    });
  });
}
