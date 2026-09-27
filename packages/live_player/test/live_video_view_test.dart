import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_media/testing.dart';
import 'package:live_player/live_player.dart';

const _quality = Quality(id: '0', label: '原画', rank: 1);

PlaybackRequest _request() => PlaybackRequest(
  site: 'douyu',
  roomKey: 'douyu:1',
  resolve: (quality) async => StreamSet(
    qualities: const [_quality],
    selected: _quality,
    lines: [
      StreamLine(
        url: Uri.parse('https://cdn.test/hw/1.flv'),
        format: StreamFormat.flv,
        lineId: 'hw',
        requested: _quality,
      ),
    ],
  ),
);

void main() {
  testWidgets('paints the background when the engine is not mpv, and follows the session', (tester) async {
    final session = PlaybackSession(engine: FakeEngine.new);
    await tester.pumpWidget(LiveVideoView(session: session, background: const Color(0xFF101010)));
    final box = tester.widget<ColoredBox>(find.byType(ColoredBox));
    expect(box.color, const Color(0xFF101010));

    await tester.runAsync(() => session.open(_request()));
    await tester.pump();
    expect(session.engine, isA<FakeEngine>());
    expect(find.byType(LiveVideoView), findsOneWidget);
    await tester.runAsync(session.dispose);
  });

  testWidgets('a second view of the same session fails (SURF-5)', (tester) async {
    final session = PlaybackSession(engine: FakeEngine.new);
    await tester.pumpWidget(
      Column(
        textDirection: TextDirection.ltr,
        children: [
          Expanded(child: LiveVideoView(session: session)),
          Expanded(child: LiveVideoView(session: session)),
        ],
      ),
    );
    expect(tester.takeException(), isA<FlutterError>());
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(session.dispose);
  });

  testWidgets('moving the view with a GlobalKey keeps one surface (SURF-5)', (tester) async {
    final session = PlaybackSession(engine: FakeEngine.new);
    final key = GlobalKey();
    Widget layout({required bool fullscreen}) => Directionality(
      textDirection: TextDirection.ltr,
      child: fullscreen
          ? LiveVideoView(key: key, session: session, fit: VideoFit.cover)
          : Column(
              children: [
                SizedBox(
                  height: 200,
                  child: LiveVideoView(key: key, session: session),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
    );
    await tester.pumpWidget(layout(fullscreen: false));
    final state = tester.state(find.byType(LiveVideoView));
    await tester.pumpWidget(layout(fullscreen: true));
    expect(tester.takeException(), isNull);
    expect(tester.state(find.byType(LiveVideoView)), same(state));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(session.dispose);
  });

  testWidgets('PlaybackStateNotifier follows the session state', (tester) async {
    final session = PlaybackSession(engine: FakeEngine.new);
    final notifier = PlaybackStateNotifier(session);
    expect(notifier.value.phase, PlaybackPhase.idle);
    await tester.runAsync(() async {
      await session.open(_request());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(notifier.value.phase, PlaybackPhase.connecting);
    expect(notifier.value.line?.lineId, 'hw');
    notifier.dispose();
    await tester.runAsync(session.dispose);
  });
}
