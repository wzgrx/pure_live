import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:loading_indicator/loading_indicator.dart';

Widget _app(Widget child, {LiveUiConfig config = const LiveUiConfig()}) => MaterialApp(
  theme: const LiveTheme(primaryColor: Colors.indigo).light,
  home: LiveUiScope(
    config: config,
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('the empty state shows the default words', (tester) async {
    await tester.pumpWidget(_app(const EmptyView()));
    await tester.pumpAndSettle();
    expect(find.text('暂无数据'), findsOneWidget);
    expect(find.text('这里空空如也，什么都没有发现'), findsOneWidget);
    expect(find.byIcon(Icons.live_tv_rounded), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('the error state retries with the words of the scope', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _app(
        AppStatusView(type: AppStatusType.error, onButtonPressed: () => retries++),
        config: const LiveUiConfig(strings: LiveUiStrings.en),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Network Request Error'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('a button that is not a retry shows its own icon', (tester) async {
    await tester.pumpWidget(
      _app(EmptyView(buttonText: 'Search', buttonIcon: Icons.search_rounded, onButtonPressed: () {})),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithIcon(TextButton, Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
  });

  testWidgets('the mini form shows only the icon when the texts are empty', (tester) async {
    await tester.pumpWidget(
      _app(AppStatusView(type: AppStatusType.error, title: '', subtitle: '', isMini: true, onButtonPressed: () {})),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.getSize(find.byType(Icon)).width, 16);
  });

  testWidgets('loading shows the style and colour the user picked', (tester) async {
    await tester.pumpWidget(
      _app(
        const AppStatusView(type: AppStatusType.loading),
        config: const LiveUiConfig(loadingStyle: 'wave', loadingColor: Colors.orange),
      ),
    );
    expect(tester.widget<SpinKitWave>(find.byType(SpinKitWave)).color, Colors.orange);

    await tester.pumpWidget(_app(const AppStatusView(type: AppStatusType.loading, iconColor: Colors.pink)));
    expect(find.byType(SpinKitWave), findsNothing);
    final spinner = tester.widget<DefaultLoadingIndicator>(find.byType(DefaultLoadingIndicator));
    expect(spinner.color, Colors.pink);
    expect(spinner.size, 32); // wider than 680 (the test view is 800)

    await tester.pumpWidget(
      _app(
        const AppStatusView(type: AppStatusType.loading),
        config: const LiveUiConfig(loadingStyle: 'pacman'),
      ),
    );
    expect(find.byType(LoadingIndicator), findsOneWidget);
  });

  test('the 85 loading styles of 3.x; unknown keys fall back', () {
    expect(LoadingStyles.keys, hasLength(85));
    expect(LoadingStyles.keys.toSet(), hasLength(85));
    expect(LoadingStyles.keys.first, LoadingStyles.defaultKey);
    expect(LoadingStyles.normalize(' ripple '), 'ripple');
    expect(LoadingStyles.normalize('gone'), LoadingStyles.defaultKey);
  });

  testWidgets('every loading style builds', (tester) async {
    for (final key in LoadingStyles.keys) {
      await tester.pumpWidget(
        _app(
          const AppStatusView(type: AppStatusType.loading),
          config: LiveUiConfig(loadingStyle: key),
        ),
      );
      expect(tester.takeException(), isNull, reason: key);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
