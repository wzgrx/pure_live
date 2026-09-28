import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

/// An image whose loading the test finishes or fails by hand.
class _Controlled extends ImageProvider<_Controlled> {
  new(this.name);

  final String name;
  final Completer<ImageInfo> _info = Completer();

  void load(ui.Image image) => _info.complete(ImageInfo(image: image));

  void fail() => _info.completeError(StateError('404'));

  @override
  Future<_Controlled> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Controlled key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_info.future);
}

double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  Widget host(Widget child, {bool tv = false, Appearance appearance = Appearance.light}) => MaterialApp(
    theme: PureTheme.of(appearance, platform: TargetPlatform.android),
    home: TvScope(
      config: tv ? const TvConfig(enabled: true) : TvConfig.off,
      child: Scaffold(
        body: Center(child: SizedBox(width: 240, child: child)),
      ),
    ),
  );

  List<double> logoSizes(WidgetTester tester) => [
    for (final logo in tester.widgetList<PlatformLogo>(find.byType(PlatformLogo))) logo.size,
  ];

  BoxDecoration coverDecoration(WidgetTester tester) =>
      tester
              .widget<DecoratedBox>(
                find.descendant(of: find.byType(RoomCover), matching: find.byType(DecoratedBox)).first,
              )
              .decoration
          as BoxDecoration;

  group('principles §3.4: the cover placeholder', () {
    testWidgets('without a cover the block carries the 24 dp logo; no clip layer', (tester) async {
      await tester.pumpWidget(host(const RoomCardView(platformId: 'douyu', anchorName: 'a', title: 'b', isLive: true)));
      expect(logoSizes(tester), unorderedEquals([Sizes.logoSmall, Sizes.logoLarge]));
      expect(find.byType(ClipRRect), findsNothing, reason: 'principles §7.11');
      final decoration = coverDecoration(tester);
      expect(decoration.image, isNull);
      expect(decoration.borderRadius, BorderRadius.circular(Radii.r2));
    });

    testWidgets('while loading only the plain block; the image then fills the decoration', (tester) async {
      final cover = _Controlled('a');
      await tester.pumpWidget(
        host(RoomCardView(platformId: 'douyu', anchorName: 'a', title: 'b', isLive: true, cover: cover)),
      );
      expect(logoSizes(tester), [Sizes.logoSmall], reason: 'no logo, no spinner while loading');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(coverDecoration(tester).image, isNull);

      final image = (await tester.runAsync(() => createTestImage(width: 16, height: 9)))!;
      addTearDown(image.dispose);
      cover.load(image.clone());
      await tester.pump();
      await tester.pump();
      expect(coverDecoration(tester).image?.image, cover);
      expect(logoSizes(tester), [Sizes.logoSmall]);
    });

    testWidgets('a failing cover shows the logo', (tester) async {
      final cover = _Controlled('b');
      await tester.pumpWidget(
        host(RoomCardView(platformId: 'douyu', anchorName: 'a', title: 'b', isLive: true, cover: cover)),
      );
      cover.fail();
      await tester.pump();
      await tester.pump();
      expect(logoSizes(tester), unorderedEquals([Sizes.logoSmall, Sizes.logoLarge]));
      expect(coverDecoration(tester).image, isNull);
    });

    testWidgets('a refreshed cover replaces the old one only once it has loaded', (tester) async {
      final image = (await tester.runAsync(() => createTestImage(width: 16, height: 9)))!;
      addTearDown(image.dispose);
      final first = _Controlled('first');
      final second = _Controlled('second');
      Widget card(ImageProvider cover) =>
          host(RoomCardView(platformId: 'douyu', anchorName: 'a', title: 'b', isLive: true, cover: cover));
      await tester.pumpWidget(card(first));
      first.load(image.clone());
      await tester.pump();
      await tester.pump();
      expect(coverDecoration(tester).image?.image, first);

      await tester.pumpWidget(card(second));
      expect(coverDecoration(tester).image?.image, first, reason: 'no flash back to the placeholder');
      second.load(image.clone());
      await tester.pump();
      await tester.pump();
      expect(coverDecoration(tester).image?.image, second);
    });

    testWidgets('on TV the corner logo is 24 dp', (tester) async {
      await tester.pumpWidget(
        host(const RoomCardView(platformId: 'douyu', anchorName: 'a', title: 'b', isLive: true), tv: true),
      );
      expect(logoSizes(tester), [Sizes.logoLarge, Sizes.logoLarge]);
    });
  });

  group('PlatformLogo', () {
    testWidgets('sits on the white r1 tile as a decoration image, without a clip', (tester) async {
      await tester.pumpWidget(
        host(
          const Align(
            child: PlatformLogo(platformId: 'bilibili', size: Sizes.logoMedium),
          ),
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(PlatformLogo), matching: find.byType(DecoratedBox)),
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, FixedColors.logoTile);
      expect(decoration.borderRadius, BorderRadius.circular(Radii.r1));
      expect(decoration.image, isNotNull);
      expect(find.byType(ClipRRect), findsNothing);
      expect(tester.getSize(find.byType(PlatformLogo)), const Size.square(20));
    });

    test('comes in 16, 20 and 24 dp only', () {
      for (final size in [Sizes.logoSmall, Sizes.logoMedium, Sizes.logoLarge]) {
        expect(() => PlatformLogo(platformId: 'douyu', size: size), returnsNormally);
      }
      for (final size in [18.0, 32.0]) {
        expect(() => PlatformLogo(platformId: 'douyu', size: size), throwsAssertionError);
      }
    });
  });

  testWidgets('principles §2.2: every recording dot is the live red', (tester) async {
    await tester.pumpWidget(host(const Column(children: [RecordingBadge(), StatusTag.recording()])));
    final dots = tester.widgetList<DecoratedBox>(
      find.descendant(of: find.byType(RecordingDot), matching: find.byType(DecoratedBox)),
    );
    expect(dots, hasLength(2));
    for (final dot in dots) {
      expect((dot.decoration as BoxDecoration).color, FixedColors.live);
    }
  });

  group('principles §3.4: InitialAvatar', () {
    test('the tone depends only on the seed and spreads over the eight tones', () {
      expect(InitialAvatar.toneOf('douyu:6979222'), InitialAvatar.toneOf('douyu:6979222'));
      final tones = {for (var i = 0; i < 200; i++) InitialAvatar.toneOf('huya:$i')};
      expect(tones, hasLength(8));
      expect(InitialAvatar.initialOf(' kiri'), 'K');
      expect(InitialAvatar.initialOf(''), '?');
      expect(InitialAvatar.initialOf('北岛看海'), '北');
    });

    test('every initial reads on its tone at 4.5:1 or more, in light and in dark', () {
      for (final (background, ink) in [...InitialAvatar.lightTones, ...InitialAvatar.darkTones]) {
        expect(_contrast(background, ink), greaterThanOrEqualTo(4.5), reason: '$background / $ink');
      }
    });

    testWidgets('light and dark themes use their own tones; the picture is a circular decoration', (tester) async {
      const seed = 'douyu:1';
      final tone = InitialAvatar.toneOf(seed);
      for (final (appearance, tones) in [
        (Appearance.light, InitialAvatar.lightTones),
        (Appearance.dark, InitialAvatar.darkTones),
        (Appearance.black, InitialAvatar.darkTones),
      ]) {
        await tester.pumpWidget(
          host(
            const InitialAvatar(name: '夜航星', seed: seed, image: _Blank()),
            appearance: appearance,
          ),
        );
        // MaterialApp animates between themes.
        await tester.pumpAndSettle();
        final boxes = tester
            .widgetList<DecoratedBox>(
              find.descendant(of: find.byType(InitialAvatar), matching: find.byType(DecoratedBox)),
            )
            .map((box) => box.decoration as BoxDecoration)
            .toList();
        expect(boxes.first.color, tones[tone].$1, reason: '$appearance');
        expect(boxes.first.shape, BoxShape.circle);
        expect(boxes.last.image, isNotNull, reason: 'the picture fills a decoration');
        expect(boxes.last.shape, BoxShape.circle);
        final text = tester.widget<Text>(find.text('夜'));
        expect(text.style!.color, tones[tone].$2);
        expect(find.byType(ClipOval), findsNothing);
      }
    });
  });
}

/// A picture that never loads, so the initial stays visible.
class _Blank extends ImageProvider<_Blank> {
  const new();

  @override
  Future<_Blank> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Blank key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}
