import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

final class _Input implements MediaInput {
  new(this.name);

  final String name;
  int closes = 0;

  @override
  PlaybackSource get source => LineSource(LivePlayLine('https://cdn.test/$name.flv'));

  @override
  MediaRoute get route => MediaRoute.direct;

  @override
  Uri get uri => Uri.parse('https://cdn.test/$name.flv');

  @override
  Map<String, String> get headers => const {};

  @override
  bool get private => false;

  @override
  String get proxyUrl => '';

  @override
  bool get onDemand => false;

  @override
  Duration? get start => null;

  @override
  LivePlayLine? get line => null;

  @override
  bool get isUsable => closes == 0;

  @override
  Future<void> close() async => closes = 1; // Idempotent, as the contract says.
}

// The main cases of 3.x's playback_source_transport_test.dart.
void main() {
  test('a successful open becomes active and releases the previous input', () async {
    final transport = PlaybackTransport();
    final first = _Input('a');
    final second = _Input('b');
    final opened = <String>[];
    await transport.open((_) async => first, (input) async => opened.add((input as _Input).name));
    await transport.open((_) async => second, (input) async => opened.add((input as _Input).name));
    expect(opened, ['a', 'b']);
    expect(transport.active, same(second));
    expect(first.closes, 1);
    expect(second.closes, 0);
    expect(transport.activeInputIsUsable, isTrue);
  });

  test('an engine open that finishes after a newer open never becomes active', () async {
    final transport = PlaybackTransport();
    final slow = _Input('slow');
    final fast = _Input('fast');
    final gate = Completer<void>();
    final late = transport.open((_) async => slow, (_) => gate.future);
    await Future<void>.delayed(Duration.zero);
    final newer = transport.open((_) async => fast, (_) async {});
    gate.complete();
    await expectLater(late, throwsStateError);
    await newer;
    expect(transport.active, same(fast));
    expect(slow.closes, 1);
  });

  test('a failed engine open releases its input; close releases the active one', () async {
    final transport = PlaybackTransport();
    final broken = _Input('broken');
    await expectLater(
      transport.open(
        (_) async => broken,
        (_) async => throw const PlayerException(message: 'x', type: PlayerErrorType.source),
      ),
      throwsA(isA<PlayerException>()),
    );
    expect(broken.closes, 1);
    final ok = _Input('ok');
    await transport.open((_) async => ok, (_) async {});
    await transport.close();
    expect(ok.closes, 1);
    expect(transport.activeInputIsUsable, isFalse);
    await expectLater(transport.open((_) async => _Input('c'), (_) async {}), throwsStateError);
  });
}
