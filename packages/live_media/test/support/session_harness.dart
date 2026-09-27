import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_media/testing.dart';

const original = Quality(id: '0', label: '原画', rank: 10);
const high = Quality(id: '4', label: '蓝光', rank: 8);

/// A session over [FakeEngine] with a scripted platform: each resolve
/// returns fresh URLs (`/<line>/<serial>.flv`) for [lineIds].
final class Harness {
  new(
    this.async, {
    this.lineIds = const ['hw', 'hs'],
    this.lease = LeaseKind.none,
    this.continuousLive = true,
    this.capabilities = const EngineCapabilities(),
    this.openLatency = Duration.zero,
    PlaybackTimings timings = const PlaybackTimings(),
  }) {
    session = PlaybackSession(engine: _create, timings: timings);
    session.states.listen(states.add);
  }

  final FakeAsync async;
  final List<String> lineIds;
  final LeaseKind lease;
  final bool continuousLive;
  final EngineCapabilities capabilities;
  final Duration openLatency;
  late final PlaybackSession session;
  final engines = <FakeEngine>[];
  final states = <PlaybackState>[];
  int resolves = 0;

  /// Makes the next resolves throw these, in order.
  final failures = <Exception>[];

  /// When set, every resolve returns these exact URLs (a signing service
  /// that answers with the same URL).
  bool sameUrls = false;

  FakeEngine get engine => engines.last;

  PlaybackState get state => session.state;

  /// URLs the engine opened, as `line/serial`.
  List<String> get opened => [for (final media in engine.opened) media.uri.path.substring(1).replaceAll('.flv', '')];

  FakeEngine _create() {
    final engine = FakeEngine(capabilities: capabilities, openLatency: openLatency);
    engines.add(engine);
    return engine;
  }

  StreamSet _set(Quality? quality) {
    final serial = sameUrls ? 0 : resolves;
    final selected = quality ?? original;
    final now = clock.now();
    return StreamSet(
      qualities: const [original, high],
      selected: selected,
      lines: [
        for (final id in lineIds)
          StreamLine(
            url: Uri.parse('https://cdn.test/$id/$serial.flv'),
            format: StreamFormat.flv,
            lineId: id,
            requested: selected,
            lease: switch (lease) {
              LeaseKind.none => null,
              LeaseKind.prefetch => Lease(
                refreshAt: now.add(const Duration(seconds: 270)),
                expiresAt: now.add(const Duration(seconds: 300)),
                cutsConnection: false,
              ),
            },
          ),
      ],
    );
  }

  Future<StreamSet> resolve(Quality? quality) async {
    resolves++;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return _set(quality);
  }

  PlaybackRequest request({String room = 'douyu:1', String? lineId, StreamSet? initial}) => PlaybackRequest(
    site: 'douyu',
    roomKey: room,
    resolve: resolve,
    lineId: lineId,
    initial: initial,
    continuousLive: continuousLive,
  );

  /// Opens a room and lets the engine start streaming.
  void openAndPlay({String room = 'douyu:1', int width = 1920, int height = 1080}) {
    unawaited(session.open(request(room: room)));
    settle();
    engine.startStreaming(width: width, height: height);
    settle();
  }

  void settle([Duration duration = const Duration(milliseconds: 50)]) => async.elapse(duration);

  /// The engine received an open for a new source since [count] opens.
  bool reopenedSince(int count) => engine.opened.length > count;
}

enum LeaseKind { none, prefetch }
