import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/features/system/media_controls.dart';
import 'package:pure_live_app/features/system/now_playing.dart';
import 'package:pure_live_app/features/system/windows_native.dart';

import 'session_harness.dart';

final class _FakeControls implements MediaControls {
  final shown = <String>[];
  final commandsController = StreamController<MediaCommand>.broadcast(sync: true);
  Completer<void>? gate;

  @override
  Stream<MediaCommand> get commands => commandsController.stream;

  @override
  Future<void> show(MediaInfo info, {required bool playing}) async {
    shown.add('${info.title}/${info.artist}/${playing ? 'playing' : 'paused'}');
    await gate?.future;
  }

  @override
  Future<void> hide() async => shown.add('hidden');
}

NowPlaying _playing(PlaybackSession session, {String title = '标题'}) => NowPlaying(
  session: session,
  room: RoomRef('douyu', '1'),
  title: title,
  anchor: '主播',
  platformName: '斗鱼',
  cover: Uri.parse('https://img.test/c.jpg'),
);

void main() {
  group('MediaControlsBridge (F-BG-01, F-NEW-12)', () {
    test('shows the room while it plays, paused when suspended or paused', () {
      fakeAsync((async) {
        final controls = _FakeControls();
        final bridge = MediaControlsBridge(controls: controls, enabled: () => true);
        final h = SessionHarness(async)..openAndPlay();
        bridge.attach(_playing(h.session));
        h.settle();
        expect(controls.shown, ['标题/主播/playing']);

        final token = h.session.suspend(SuspendReason.background);
        h.settle();
        expect(controls.shown.last, '标题/主播/paused');
        h.session.resume(token);
        h.settle();
        expect(controls.shown.last, '标题/主播/playing');

        unawaited(h.session.pause());
        h.settle();
        expect(controls.shown.last, '标题/主播/paused');

        bridge.attach(null);
        h.settle();
        expect(controls.shown.last, 'hidden');
      });
    });

    test('commands reach the session; stop pauses and hides until the next play', () {
      fakeAsync((async) {
        final controls = _FakeControls();
        final bridge = MediaControlsBridge(controls: controls, enabled: () => true);
        final h = SessionHarness(async)..openAndPlay();
        bridge.attach(_playing(h.session));
        h.settle();

        controls.commandsController.add(MediaCommand.pause);
        h.settle();
        expect(h.state.phase, PlaybackPhase.paused);
        controls.commandsController.add(MediaCommand.play);
        h.settle();
        expect(h.state.wantsPlay, isTrue);

        controls.commandsController.add(MediaCommand.stop);
        h.settle();
        expect(h.state.phase, PlaybackPhase.paused);
        expect(controls.shown.last, 'hidden');

        unawaited(h.session.play());
        h.settle();
        expect(controls.shown.last, '标题/主播/playing', reason: 'playing again brings the controls back');
      });
    });

    test('hidden while disabled (Android without background play)', () {
      fakeAsync((async) {
        var enabled = false;
        final controls = _FakeControls();
        final bridge = MediaControlsBridge(controls: controls, enabled: () => enabled);
        final h = SessionHarness(async)..openAndPlay();
        bridge.attach(_playing(h.session));
        h.settle();
        expect(controls.shown, isEmpty);
        enabled = true;
        bridge.refresh();
        h.settle();
        expect(controls.shown, ['标题/主播/playing']);
      });
    });

    test('a slow platform gets only the latest update (AUD-5)', () {
      fakeAsync((async) {
        final controls = _FakeControls()..gate = Completer<void>();
        final bridge = MediaControlsBridge(controls: controls, enabled: () => true);
        final h = SessionHarness(async)..openAndPlay();
        bridge.attach(_playing(h.session));
        h.settle();
        expect(controls.shown, ['标题/主播/playing']);
        // Several changes while the first update is still running.
        bridge.attach(_playing(h.session, title: '新标题'));
        unawaited(h.session.pause());
        h.settle();
        unawaited(h.session.play());
        h.settle();
        controls.gate!.complete();
        controls.gate = null;
        h.settle();
        expect(controls.shown, ['标题/主播/playing', '新标题/主播/playing']);
      });
    });
  });

  group('WindowsNative (runner channel purelive/windows)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('purelive/windows');

    Future<void> fromRunner(String method, Object? arguments) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
    }

    test('delivers forwarded launches, tray events and media buttons', () async {
      final native = WindowsNative();
      final forwarded = <List<String>>[];
      final tray = <TrayEvent>[];
      final media = <MediaCommand>[];
      native.forwardedArguments.listen(forwarded.add);
      native.trayEvents.listen(tray.add);
      native.mediaCommands.listen(media.add);
      await fromRunner('forwardedArguments', ['--open-room=douyu:1', 7]);
      await fromRunner('trayEvent', 'click');
      await fromRunner('trayEvent', 'bogus');
      await fromRunner('mediaButton', 'pause');
      await Future<void>.delayed(Duration.zero);
      expect(forwarded, [
        ['--open-room=douyu:1'],
      ]);
      expect(tray, [TrayEvent.click]);
      expect(media, [MediaCommand.pause]);
    });

    test('sends SMTC updates and survives a missing runner', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'setLaunchAtStartup' ? true : null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
      final native = WindowsNative();
      await WindowsMediaControls(native).show(
        MediaInfo(id: 'douyu:1', title: 't', artist: 'a', artwork: Uri.parse('https://img.test/c.jpg')),
        playing: true,
      );
      expect(await native.setLaunchAtStartup(name: 'PureLiveNext', enabled: true), isTrue);
      expect(calls.first.method, 'updateMediaControls');
      expect(calls.first.arguments, {
        'title': 't',
        'artist': 'a',
        'album': '',
        'thumbnail': 'https://img.test/c.jpg',
        'playing': true,
      });
      expect(calls.last.arguments, {'name': 'PureLiveNext', 'enabled': true});

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      expect(await native.setLaunchAtStartup(name: 'PureLiveNext', enabled: true), isFalse);
    });
  });
}
