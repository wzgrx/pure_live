import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_media/testing.dart';

const _original = Quality(id: '0', label: '原画', rank: 10);

/// A session playing a room on the widget tester's fake clock.
Future<PlaybackSession> playingSession(WidgetTester tester, {int width = 1920, int height = 1080}) async {
  final session = PlaybackSession(engine: FakeEngine.new);
  unawaited(session.open(const PlaybackRequest(site: 'douyu', roomKey: 'douyu:1', resolve: _resolve)));
  await tester.pump(const Duration(milliseconds: 50));
  (session.engine! as FakeEngine).startStreaming(width: width, height: height);
  await tester.pump(const Duration(milliseconds: 50));
  return session;
}

Future<StreamSet> _resolve(Quality? quality) async => StreamSet(
  qualities: const [_original],
  selected: _original,
  lines: [
    StreamLine(
      url: Uri.parse('https://cdn.test/hw/1.flv'),
      format: StreamFormat.flv,
      lineId: 'hw',
      requested: quality ?? _original,
    ),
  ],
);

/// A [PlaybackSession] over live_media's [FakeEngine] (recorded media_kit
/// event order) with a scripted room, for the system integration tests.
final class SessionHarness {
  new(this.async) {
    session = PlaybackSession(engine: _create);
  }

  final FakeAsync async;
  late final PlaybackSession session;
  final engines = <FakeEngine>[];

  FakeEngine get engine => engines.last;

  PlaybackState get state => session.state;

  FakeEngine _create() {
    final engine = FakeEngine();
    engines.add(engine);
    return engine;
  }

  /// Opens a room and lets the engine stream at [width]×[height].
  void openAndPlay({String room = 'douyu:1', int width = 1920, int height = 1080}) {
    unawaited(session.open(PlaybackRequest(site: 'douyu', roomKey: room, resolve: _resolve)));
    settle();
    engine.startStreaming(width: width, height: height);
    settle();
  }

  /// Engine commands since the engine was created.
  List<String> get commands => engine.commands;

  void settle([Duration duration = const Duration(milliseconds: 50)]) => async.elapse(duration);
}
