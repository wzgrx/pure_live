import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';

import 'support/fake_engine.dart';

void main() {
  testWidgets('the view is black until the session has an mpv engine', (tester) async {
    final session = PlaybackSession(engine: () async => FakeEngine(), opener: MediaOpener());
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LiveVideoView(session: session),
      ),
    );
    final box = tester.widget<ColoredBox>(find.byType(ColoredBox));
    expect(box.color, const Color(0xFF000000));
  });
}
