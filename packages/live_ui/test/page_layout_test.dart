import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

/// principles §2.4: the header and the content of a page share one margin.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required ThemeData theme,
    required Widget Function(BuildContext context) page,
    bool tv = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TvScope(
        config: TvConfig(enabled: tv),
        child: MaterialApp(
          theme: theme,
          home: Builder(builder: page),
        ),
      ),
    );
  }

  Widget content() => const PageBody(child: ListTile(title: Text('row')));

  final phone = PureTheme.of(Appearance.light, platform: TargetPlatform.android);
  final desktop = PureTheme.of(Appearance.light, platform: TargetPlatform.windows);
  final tvTheme = PureTheme.tv(Appearance.dark, platform: TargetPlatform.android);

  for (final (name, size, theme, margin) in [
    ('compact', const Size(393, 852), phone, 16.0),
    ('medium', const Size(768, 1024), phone, 24.0),
    ('expanded', const Size(1024, 768), phone, 24.0),
    ('large desktop', const Size(1440, 900), desktop, 32.0),
    ('extra-large desktop', const Size(1920, 1080), desktop, 32.0),
  ]) {
    testWidgets('$name: title, rows and the last action glyph on the $margin dp margin', (tester) async {
      await pump(
        tester,
        size: size,
        theme: theme,
        page: (context) => Scaffold(
          appBar: PageAppBar(
            title: const Text('Title'),
            actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.refresh))],
          ),
          body: content(),
        ),
      );
      expect(tester.getTopLeft(find.text('Title')).dx, margin);
      expect(tester.getTopLeft(find.text('row')).dx, margin);
      expect(size.width - tester.getTopRight(find.byIcon(Icons.refresh)).dx, margin);
    });
  }

  testWidgets('a back button sits on the margin, the title 32 dp after its glyph', (tester) async {
    await pump(
      tester,
      size: const Size(1440, 900),
      theme: desktop,
      page: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  appBar: const PageAppBar(title: Text('Sub')),
                  body: content(),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final back = tester.getRect(find.byIcon(Icons.arrow_back));
    expect(back.left, 32);
    expect(tester.getTopLeft(find.text('Sub')).dx, back.right + 32);
    expect(tester.getTopLeft(find.text('row')).dx, 32);
  });

  testWidgets('a centered column: the title and the rows start together', (tester) async {
    await pump(
      tester,
      size: const Size(1440, 900),
      theme: desktop,
      page: (context) => const Scaffold(
        appBar: PageAppBar(title: Text('Me'), maxContentWidth: Sizes.readingWidth),
        body: PageBody(maxContentWidth: Sizes.readingWidth, child: ListTile(title: Text('row'))),
      ),
    );
    final row = tester.getTopLeft(find.text('row')).dx;
    expect(row, (1440 - Sizes.readingWidth) / 2 + 32);
    expect(tester.getTopLeft(find.text('Me')).dx, row);
  });

  testWidgets('tabs: the first label starts on the margin', (tester) async {
    await pump(
      tester,
      size: const Size(1440, 900),
      theme: desktop,
      page: (context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: const PageAppBar(
            title: Text('Discover'),
            bottom: PageTabBar(tabs: [Tab(text: 'One'), Tab(text: 'Two')]),
          ),
          body: content(),
        ),
      ),
    );
    expect(tester.getTopLeft(find.text('One')).dx, 32);
    expect(tester.getTopLeft(find.text('Discover')).dx, 32);
  });

  testWidgets('TV: the title starts where the cards start (8 dp in from the rail)', (tester) async {
    await pump(
      tester,
      size: const Size(792, 540),
      theme: tvTheme,
      tv: true,
      page: (context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: PageAppBar(
            title: const Text('Follows'),
            actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.refresh))],
            bottom: const PageTabBar(tabs: [Tab(text: 'One'), Tab(text: 'Two')]),
          ),
          body: content(),
        ),
      ),
    );
    expect(tester.getTopLeft(find.text('Follows')).dx, Space.s2);
    expect(tester.getTopLeft(find.text('One')).dx, Space.s2);
    // A 48 dp touch button centres its 24 dp glyph 12 dp from its edge: 4 dp
    // inside the line, since the button cannot reach into the overscan margin.
    expect(792 - tester.getTopRight(find.byIcon(Icons.refresh)).dx, 12);
  });
}
