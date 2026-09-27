import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/features/system/pip.dart';
import 'package:pure_live_app/features/system/pip_view.dart';

import 'fake_window.dart';
import 'session_harness.dart';

final class _FakePip implements PipPlatform {
  bool supported = true;
  bool accept = true;
  bool reportOnEnter = false;
  final entered = <PipRequest>[];
  final updates = <PipRequest>[];
  final controller = StreamController<PipEvent>.broadcast(sync: true);

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> enter(PipRequest request) async {
    entered.add(request);
    if (reportOnEnter) controller.add(const PipModeChanged(active: true));
    return accept;
  }

  @override
  Future<void> update(PipRequest request) async => updates.add(request);

  @override
  Future<bool> exit() async {
    controller.add(const PipModeChanged(active: false));
    return true;
  }

  @override
  Stream<PipEvent> get events => controller.stream;
}

void main() {
  group('PipController (PIP-1, PIP-2)', () {
    late _FakePip platform;
    late Completer<void> frame;
    late ProviderContainer container;

    void setUpContainer() {
      platform = _FakePip();
      frame = Completer<void>();
      container = ProviderContainer(
        overrides: [
          pipPlatformProvider.overrideWithValue(platform),
          pipFrameWaiterProvider.overrideWithValue(() => frame.future),
        ],
      )..read(pipProvider);
    }

    PipController pip() => container.read(pipProvider.notifier);
    PipState state() => container.read(pipProvider);

    test('shows the video-only layout first, then asks the platform; the report makes it active', () {
      fakeAsync((async) {
        setUpContainer();
        final h = SessionHarness(async)..openAndPlay(width: 1280, height: 720);
        async.flushMicrotasks();
        expect(state().supported, isTrue);
        final result = pip().enter(h.session);
        expect(state().mode, PipMode.entering);
        expect(state().videoOnly, isTrue);
        async.flushMicrotasks();
        expect(platform.entered, isEmpty, reason: 'PIP-2: the video-only frame comes first');
        frame.complete();
        async.flushMicrotasks();
        expect(platform.entered.single.aspect, closeTo(16 / 9, 0.001));
        expect(platform.entered.single.playing, isTrue);
        platform.controller.add(const PipModeChanged(active: true));
        expect(state().mode, PipMode.active);
        bool? entered;
        unawaited(result.then((value) => entered = value));
        async.flushMicrotasks();
        expect(entered, isTrue);
        platform.controller.add(const PipModeChanged(active: false));
        expect(state().mode, PipMode.off);
        container.dispose();
      });
    });

    test('PIP-1: no entry before the engine exists, after a user pause or without support', () {
      fakeAsync((async) {
        setUpContainer();
        final idle = SessionHarness(async);
        async.flushMicrotasks();
        bool? result;
        unawaited(pip().enter(idle.session).then((value) => result = value));
        async.flushMicrotasks();
        expect(result, isFalse);
        expect(state().mode, PipMode.off);

        final h = SessionHarness(async)..openAndPlay();
        unawaited(h.session.pause());
        h.settle();
        unawaited(pip().enter(h.session).then((value) => result = value));
        async.flushMicrotasks();
        expect(result, isFalse);

        expect(
          pipEntryAllowed(state: const PlaybackState(), engineReady: true, mode: PipMode.off),
          isFalse,
          reason: 'idle',
        );
        container.dispose();
      });
    });

    test('a refused request returns to the normal layout; a report during the request wins', () {
      fakeAsync((async) {
        setUpContainer();
        final h = SessionHarness(async)..openAndPlay();
        async.flushMicrotasks();
        platform.accept = false;
        frame.complete();
        bool? result;
        unawaited(pip().enter(h.session).then((value) => result = value));
        async.flushMicrotasks();
        expect(result, isFalse);
        expect(state().mode, PipMode.off);

        platform
          ..reportOnEnter = true
          ..accept = false;
        unawaited(pip().enter(h.session).then((value) => result = value));
        async.flushMicrotasks();
        expect(state().mode, PipMode.active, reason: "the system's report beats the return value");
        expect(result, isTrue);
        container.dispose();
      });
    });

    test('cancel drops an entry in progress; an accepted entry without a report falls back', () {
      fakeAsync((async) {
        setUpContainer();
        final h = SessionHarness(async)..openAndPlay();
        async.flushMicrotasks();
        unawaited(pip().enter(h.session));
        pip().cancel();
        expect(state().mode, PipMode.off);
        frame.complete();
        async.flushMicrotasks();
        expect(platform.entered, isEmpty);

        unawaited(pip().enter(h.session));
        async.flushMicrotasks();
        expect(platform.entered, hasLength(1));
        expect(state().mode, PipMode.entering);
        async.elapse(PipController.reportTimeout);
        expect(state().mode, PipMode.off);
        container.dispose();
      });
    });

    test('updates skip aspect changes below 0.004 (PIP-2) and carry play state and auto entry', () {
      fakeAsync((async) {
        setUpContainer();
        async.flushMicrotasks();
        unawaited(pip().update(aspect: 1.7777, playing: true, autoEnter: false));
        unawaited(pip().update(aspect: 1.7800, playing: true, autoEnter: false));
        unawaited(pip().update(aspect: 1.7840, playing: true, autoEnter: false));
        unawaited(pip().update(aspect: 1.7840, playing: false, autoEnter: false));
        unawaited(pip().update(aspect: 1.7840, playing: false, autoEnter: true));
        async.flushMicrotasks();
        expect(platform.updates.map((r) => (r.aspect, r.playing, r.autoEnter)), [
          (1.7777, true, false),
          (1.7840, true, false),
          (1.7840, false, false),
          (1.7840, false, true),
        ]);
        container.dispose();
      });
    });

    test('parameters set before support is known go out once it is', () {
      fakeAsync((async) {
        setUpContainer();
        unawaited(pip().update(aspect: 0.5625, playing: true, autoEnter: true));
        expect(platform.updates, isEmpty);
        async.flushMicrotasks();
        expect(platform.updates.single.autoEnter, isTrue);
        container.dispose();
      });
    });

    test('the play/pause action of the PiP window is forwarded', () {
      fakeAsync((async) {
        setUpContainer();
        final toggles = <bool>[];
        pip().playToggles.listen(toggles.add);
        platform.controller
          ..add(const PipPlayToggled(play: false))
          ..add(const PipPlayToggled(play: true));
        async.flushMicrotasks();
        expect(toggles, [false, true]);
        container.dispose();
      });
    });
  });

  group('aspect and window geometry', () {
    test('pipAspect uses the committed geometry, then the decoded size, clamped', () {
      expect(pipAspect(const PlaybackState()), closeTo(16 / 9, 1e-9));
      expect(pipAspect(const PlaybackState(videoWidth: 720, videoHeight: 1280)), closeTo(0.5625, 1e-9));
      expect(
        pipAspect(
          const PlaybackState(
            videoWidth: 1920,
            videoHeight: 1080,
            geometry: VideoGeometry(orientation: VideoOrientation.portrait, width: 1080, height: 1920),
          ),
        ),
        closeTo(0.5625, 1e-9),
      );
      expect(pipAspect(const PlaybackState(videoWidth: 4000, videoHeight: 1000)), maxPipAspect);
      expect(pipAspect(const PlaybackState(videoWidth: 500, videoHeight: 4000)), minPipAspect);
    });

    test('the Windows PiP window sits in the bottom-right corner of the work area', () {
      const area = Rect.fromLTWH(0, 0, 1920, 1040);
      expect(pipWindowRect(aspect: 16 / 9, workArea: area), const Rect.fromLTWH(1424, 754, 480, 270));
      expect(pipWindowRect(aspect: 9 / 16, workArea: area), const Rect.fromLTWH(1634, 544, 270, 480));
      final small = pipWindowRect(aspect: 16 / 9, workArea: const Rect.fromLTWH(0, 0, 300, 400));
      expect(small.width, closeTo(268, 0.01));
      expect(small.right, 284);
    });
  });

  group('WindowsPipPlatform (F-PIP-02, PIP-3)', () {
    test('shrinks to a frameless window with the video ratio and restores everything', () async {
      final window = FakeWindow()
        ..maximized = true
        ..fullScreen = true;
      final original = window.bounds;
      var onTop = true;
      final platform = WindowsPipPlatform(window, alwaysOnTop: () => onTop);
      final events = <PipEvent>[];
      platform.events.listen(events.add);

      expect(await platform.enter(const PipRequest(aspect: 16 / 9)), isTrue);
      expect(window.calls.take(3), ['fullScreen false', 'unmaximize', 'frameless true']);
      expect(window.bounds, const Rect.fromLTWH(1424, 754, 480, 270));
      expect(window.aspectRatio, closeTo(16 / 9, 1e-9));
      expect(window.alwaysOnTop, isTrue);
      expect(window.minimumSize, pipMinimumWindowSize);

      await platform.update(const PipRequest(aspect: 9 / 16));
      expect(window.bounds, const Rect.fromLTWH(1634, 544, 270, 480), reason: 'long edge and corner stay');

      onTop = false;
      expect(await platform.exit(), isTrue);
      expect(window.bounds, original);
      expect(window.maximized, isTrue);
      expect(window.fullScreen, isTrue);
      expect(window.frameless, isFalse);
      expect(window.alwaysOnTop, isFalse);
      expect(window.aspectRatio, 0);
      expect(window.minimumSize, minimumWindowSize);
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<PipModeChanged>().map((e) => e.active), [true, false]);
    });
  });

  group('AndroidPipPlatform (channel purelive/pip)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('purelive/pip');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('sends an integer ratio, the source rect and flags; reports mode and actions', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'enter' || call.method == 'isSupported';
      });
      final platform = AndroidPipPlatform();
      final events = <PipEvent>[];
      platform.events.listen(events.add);
      expect(await platform.isSupported(), isTrue);
      expect(
        await platform.enter(
          const PipRequest(aspect: 16 / 9, sourceRect: Rect.fromLTRB(0, 100.4, 1080, 707.6), autoEnter: true),
        ),
        isTrue,
      );
      expect(calls.last.arguments, {
        'width': 17778,
        'height': 10000,
        'sourceRect': [0, 100, 1080, 708],
        'playing': true,
        'autoEnter': true,
      });

      Future<void> fromActivity(String method, Object? arguments) => messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
      await fromActivity('modeChanged', true);
      await fromActivity('action', 'pause');
      await Future<void>.delayed(Duration.zero);
      expect(events[0], isA<PipModeChanged>().having((e) => e.active, 'active', isTrue));
      expect(events[1], isA<PipPlayToggled>().having((e) => e.play, 'play', isFalse));
    });

    test('a missing activity channel means no PiP', () async {
      final platform = AndroidPipPlatform();
      expect(await platform.isSupported(), isFalse);
      expect(await platform.enter(const PipRequest(aspect: 1)), isFalse);
    });
  });

  testWidgets('PipAwareLayout shows only the video while PiP enters or is active (PIP-2)', (tester) async {
    final platform = _FakePip();
    final container = ProviderContainer(
      overrides: [
        pipPlatformProvider.overrideWithValue(platform),
        pipFrameWaiterProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    final session = await playingSession(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PipAwareLayout(
            session: session,
            video: const Text('画面'),
            builder: (context, video) => Column(children: [video, const Text('聊天')]),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('聊天'), findsOneWidget);
    unawaited(container.read(pipProvider.notifier).enter(session));
    await tester.pump();
    expect(find.text('画面'), findsOneWidget);
    expect(find.text('聊天'), findsNothing);
    platform.controller.add(const PipModeChanged(active: true));
    await tester.pump();
    expect(find.text('聊天'), findsNothing);
    platform.controller.add(const PipModeChanged(active: false));
    await tester.pump();
    expect(find.text('聊天'), findsOneWidget);
    unawaited(session.dispose());
    await tester.pump(const Duration(seconds: 1));
  });
}
