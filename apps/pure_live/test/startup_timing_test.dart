import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/features/favorite/favorite_page.dart';
import 'package:pure_live/features/splash/splash_page.dart';

import 'support.dart';

/// A timing over a clock the test moves, with Android's answer `process`.
final class _Run {
  new({StartupProcess process = (cold: true, processToMain: 180)}) {
    timing = StartupTiming(
      clock: () => now,
      process: (_) async {
        asked++;
        return process;
      },
      write: lines.add,
      reportFullyDrawn: () async => drawn++,
    );
  }

  late final StartupTiming timing;
  Duration now = Duration.zero;
  final List<String> lines = [];
  int drawn = 0;
  int asked = 0;

  void advance(int ms) => now += Duration(milliseconds: ms);

  /// A whole start: every step and mark, [ms] apart.
  Future<void> start({int ms = 10}) async {
    timing.splash = true;
    for (final name in startupSteps) {
      advance(ms);
      timing.step(name);
      if (name == 'binding') timing.askProcess();
    }
    for (final name in startupMarks.take(3)) {
      advance(ms);
      timing.mark(name);
    }
    advance(ms);
  }
}

Map<String, String> _fields(String line) => {
  for (final field in line.split(' ').skip(1)) field.split('=').first: field.split('=').last,
};

void main() {
  test('startup timing writes one line with every mark', () async {
    final run = _Run();
    await run.start();
    await run.timing.firstContent(tab: 'popular', content: 'rooms');

    expect(run.lines, hasLength(1));
    final line = run.lines.single;
    expect(line, startsWith('startup-timing '));
    final fields = _fields(line);
    expect(fields.keys, ['cold', 'splash', 'tab', 'content', 'process', ...startupSteps, ...startupMarks, 'total']);
    expect(fields['cold'], 'true');
    expect(fields['splash'], 'on');
    expect(fields['tab'], 'popular');
    expect(fields['content'], 'rooms');
    // Steps are their own durations, never negative.
    for (final name in startupSteps) {
      expect(int.parse(fields[name]!), 10, reason: name);
    }
    // Marks are cumulative from main and rise.
    final marks = [for (final name in startupMarks) int.parse(fields[name]!)];
    expect(marks, [120, 130, 140, 150]);
    expect(fields['process'], '180');
    expect(fields['total'], '330');
    expect(run.drawn, 1);
    expect(run.asked, 1, reason: 'asked once, at the binding');
  });

  test('home first content counts once: one line, fully drawn reported once', () async {
    final run = _Run();
    await run.start();
    await run.timing.firstContent(tab: 'popular', content: 'rooms');
    run.advance(500);
    // A refresh, another tab, a second page: none of them count.
    await run.timing.firstContent(tab: 'popular', content: 'rooms');
    await run.timing.firstContent(tab: 'favorites', content: 'empty');
    expect(run.lines, hasLength(1));
    expect(_fields(run.lines.single)['firstPage'], '150');
    expect(run.drawn, 1);
    expect(run.timing.reported, isTrue);
  });

  test("a warm start (not the process's first main) reports fully drawn but writes no line", () async {
    final run = _Run(process: (cold: false, processToMain: 90000));
    await run.start();
    await run.timing.firstContent(tab: 'popular', content: 'rooms');
    expect(run.lines, isEmpty);
    expect(run.drawn, 1);
  });

  test('a failed launch (the failure page and a retry) writes no line', () async {
    final run = _Run();
    await run.start();
    run.timing.abandon();
    await run.timing.firstContent(tab: 'popular', content: 'rooms');
    expect(run.lines, isEmpty);
    expect(run.drawn, 1);
  });

  test('a step or mark recorded again keeps its first time; Android is asked when nobody asked', () async {
    final run = _Run()..advance(5);
    run.timing.step('binding');
    run.advance(7);
    run.timing
      ..step('binding')
      ..step('imageCache')
      ..mark('runApp');
    run.advance(100);
    run.timing.mark('runApp');
    await run.timing.firstContent(tab: 'tv', content: 'home');
    final fields = _fields(run.lines.single);
    expect(fields['binding'], '5');
    expect(fields['imageCache'], '7');
    expect(fields['runApp'], '12');
    expect(fields['firstPage'], '112');
    expect(fields['store'], '-');
    expect(fields['splash'], '-');
    expect(run.asked, 1);
  });

  test('a failing fully-drawn call still writes the line', () async {
    final lines = <String>[];
    final timing = StartupTiming(
      clock: () => Duration.zero,
      process: (_) async => (cold: true, processToMain: null),
      write: lines.add,
      reportFullyDrawn: () async => throw StateError('no activity'),
    );
    await timing.firstContent(tab: 'areas', content: 'home');
    expect(lines, hasLength(1));
    expect(_fields(lines.single)['process'], '-');
    expect(_fields(lines.single)['total'], '-');
  });

  test('formatStartupTiming: order, missing values as -, total from the process start', () {
    final line = formatStartupTiming(
      cold: true,
      splash: false,
      tab: 'favorites',
      content: 'empty',
      processToMain: 200,
      steps: const {'binding': 12, 'store': 45},
      marks: const {'runApp': 131, 'firstPage': 980},
    );
    expect(
      line,
      'startup-timing cold=true splash=off tab=favorites content=empty process=200 binding=12 imageCache=- '
      'tvDetect=- dataRoot=- store=45 legacy=- wire=- log=- strings=- fonts=- desktop=- runApp=131 '
      'firstFrame=- home=- firstPage=980 total=1180',
    );
    expect(
      formatStartupTiming(
        cold: true,
        splash: null,
        tab: null,
        content: null,
        processToMain: 200,
        steps: const {},
        marks: const {},
      ),
      endsWith('firstPage=- total=-'),
    );
  });

  test('processToMainMs: the process age less the middle of the call, never below zero', () {
    expect(
      processToMainMs(
        sinceProcessStart: 400,
        sent: const Duration(milliseconds: 20),
        received: const Duration(milliseconds: 30),
      ),
      375,
    );
    expect(
      processToMainMs(
        sinceProcessStart: 10,
        sent: const Duration(milliseconds: 20),
        received: const Duration(seconds: 1),
      ),
      0,
    );
  });

  group('home', () {
    tearDown(() => StartupTiming.current = null);

    /// The app with follows as home and [splash], timed by a fresh run.
    Future<(_Run, AppServices)> pump(WidgetTester tester, {required bool splash}) async {
      final run = _Run();
      StartupTiming.current = run.timing..splash = splash;
      final services = (await tester.runAsync(() async {
        final services = await testServices();
        await services.store.settings.set(Settings.showSplashPage, splash);
        await services.store.settings.set(Settings.savedMenuIds, ['favorites', 'popular']);
        return services;
      }))!;
      final strings = (await tester.runAsync(loadStrings))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
        ),
      );
      return (run, services);
    }

    testWidgets('follows as home: drawn once the stored follows show', (tester) async {
      final (run, services) = await pump(tester, splash: false);
      await tester.pumpAndSettle();
      expect(find.byType(FavoritePage), findsOneWidget);
      expect(run.drawn, 1);
      expect(_fields(run.lines.single), containsPair('tab', 'favorites'));
      expect(_fields(run.lines.single), containsPair('content', 'empty'));
      expect(_fields(run.lines.single)['home'], isNot('-'));
      // Back to follows, or a pass over the page: not again.
      await tester.pumpAndSettle();
      expect(run.drawn, 1);
      await tester.runAsync(services.close);
    });

    testWidgets('with the splash page on, home reports only after the splash page leaves', (tester) async {
      final (run, services) = await pump(tester, splash: true);
      await tester.pump();
      expect(find.byType(SplashPage), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900));
      expect(run.drawn, 0);
      expect(run.timing.reported, isFalse);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SplashPage), findsNothing);
      expect(find.byType(FavoritePage), findsOneWidget);
      expect(run.drawn, 1);
      expect(_fields(run.lines.single), containsPair('splash', 'on'));
      await tester.runAsync(services.close);
    });
  });
}
