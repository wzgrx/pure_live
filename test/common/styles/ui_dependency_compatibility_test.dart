import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart' as flutter;
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_indicator/loading_indicator.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:pure_live/common/styles/dynamic_color_adapter.dart';

void main() {
  testWidgets('color picker renders inside the application Material tree', (tester) async {
    await tester.pumpWidget(
      flutter.MaterialApp(
        home: flutter.Scaffold(
          body: ColorPicker(color: const flutter.Color(0xff6750a4), onColorChanged: (_) {}, width: 32, height: 32),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ColorPicker), findsOneWidget);
  });

  testWidgets('loading indicator renders with the upgraded controller implementation', (tester) async {
    await tester.pumpWidget(
      const flutter.MaterialApp(
        home: flutter.Center(
          child: flutter.SizedBox.square(
            dimension: 32,
            child: LoadingIndicator(indicatorType: Indicator.ballPulse, colors: <flutter.Color>[flutter.Colors.blue]),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(LoadingIndicator), findsOneWidget);
  });

  testWidgets('material UI bridge keeps color picker dialogs on the active dark theme', (tester) async {
    material.ThemeData? observedTheme;
    final flutterTheme = flutter.ThemeData(
      brightness: flutter.Brightness.dark,
      colorScheme: flutter.ColorScheme.fromSeed(
        seedColor: const flutter.Color(0xff006c4c),
        brightness: flutter.Brightness.dark,
      ),
    );

    await tester.pumpWidget(
      flutter.MaterialApp(
        theme: flutterTheme,
        supportedLocales: const [flutter.Locale('en')],
        localizationsDelegates: const [material.GlobalMaterialLocalizations.delegate],
        builder: (context, child) => MaterialUiThemeBridge(child: child!),
        home: flutter.Builder(
          builder: (context) => flutter.TextButton(
            onPressed: () async {
              await ColorPicker(
                color: const flutter.Color(0xff006c4c),
                onColorChanged: (_) {},
              ).showPickerDialog(context);
            },
            child: const flutter.Text('open picker'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();

    final picker = tester.element(find.byType(ColorPicker));
    observedTheme = material.Theme.of(picker);
    expect(tester.takeException(), isNull);
    expect(observedTheme.brightness, flutter.Brightness.dark);
    expect(observedTheme.colorScheme.primary, flutterTheme.colorScheme.primary);
  });
}
