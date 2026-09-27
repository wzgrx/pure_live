import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/dialogs/live_dlna_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> english;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });

  test('DLNA source accepts normalized web URLs and rejects unsafe inputs', () {
    expect(
      normalizeDlnaSource('  https://media.example/live.m3u8?token=fixture  '),
      'https://media.example/live.m3u8?token=fixture',
    );
    for (final value in [
      '',
      'file:///tmp/live.m3u8',
      'rtmp://media.example/live',
      'https:///missing-host',
      'https://user:secret@media.example/live',
      'javascript:alert(1)',
    ]) {
      expect(normalizeDlnaSource(value), isNull, reason: value);
    }
  });

  testWidgets('invalid source is terminal and never starts discovery', (tester) async {
    var starts = 0;
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(
        datasource: 'file:///tmp/live.m3u8',
        startDiscovery: () async {
          starts++;
          return _FixtureSession();
        },
      ),
    );

    expect(starts, 0);
    expect(find.byKey(const ValueKey('dlna-invalid-source')), findsOneWidget);
    expect(find.text(english['dlna_invalid_source'] as String), findsOneWidget);
    expect(find.byKey(const ValueKey('dlna-refresh')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup is single-flight and timeout stops one session', (tester) async {
    final startGate = Completer<DlnaDiscoverySession>();
    final session = _FixtureSession();
    var starts = 0;
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(
        datasource: _source,
        searchDuration: const Duration(seconds: 1),
        startDiscovery: () {
          starts++;
          return startGate.future;
        },
      ),
      settle: false,
    );

    final dynamic state = tester.state(find.byType(LiveDlnaPage));
    final Future<void> first = state.startSearch() as Future<void>;
    final Future<void> second = state.startSearch() as Future<void>;
    expect(first, same(second));
    expect(starts, 1);

    startGate.complete(session);
    await tester.pump();
    await first;
    await tester.pump();
    expect(find.byKey(const ValueKey('dlna-searching')), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await _pumpUi(tester);
    expect(find.byKey(const ValueKey('dlna-empty')), findsOneWidget);
    expect(session.stopCalls, 1);
    expect(find.byKey(const ValueKey('dlna-retry')).hitTestable(), findsOneWidget);
  });

  testWidgets('failed discovery shows retry and a later attempt can recover', (tester) async {
    final recovered = _FixtureSession();
    var starts = 0;
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(
        datasource: _source,
        startDiscovery: () async {
          starts++;
          if (starts == 1) throw StateError('fixture discovery failure');
          return recovered;
        },
      ),
    );

    expect(find.byKey(const ValueKey('dlna-search-failed')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dlna-retry')));
    await _pumpUi(tester);
    await _waitForListener(tester, recovered);
    recovered.emit([_FixtureDevice(id: 'receiver-1', name: 'Living room')]);
    await _pumpUi(tester);

    expect(starts, 2);
    expect(find.byKey(const ValueKey('dlna-device-receiver-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('dlna-search-failed')), findsNothing);
  });

  testWidgets('device snapshots replace missing receivers instead of retaining stale rows', (tester) async {
    final session = _FixtureSession();
    await _pumpDialog(tester, english, LiveDlnaPage(datasource: _source, startDiscovery: () async => session));
    final first = _FixtureDevice(id: 'first', name: 'First receiver');
    final second = _FixtureDevice(id: 'second', name: 'Second receiver');

    await _waitForListener(tester, session);
    session.emit([first, second]);
    await _pumpUi(tester);
    expect(find.byKey(const ValueKey('dlna-device-first')), findsOneWidget);
    expect(find.byKey(const ValueKey('dlna-device-second')), findsOneWidget);

    session.emit([second]);
    await _pumpUi(tester);
    expect(find.byKey(const ValueKey('dlna-device-first')), findsNothing);
    expect(find.byKey(const ValueKey('dlna-device-second')), findsOneWidget);
  });

  testWidgets('refresh releases the prior search and ignores its later snapshots', (tester) async {
    final first = _FixtureSession();
    final second = _FixtureSession();
    var starts = 0;
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(datasource: _source, startDiscovery: () async => starts++ == 0 ? first : second),
    );

    await _waitForListener(tester, first);
    await tester.pump(const Duration(milliseconds: 1));
    final dynamic state = tester.state(find.byType(LiveDlnaPage));
    unawaited(state.startSearch() as Future<void>);
    await tester.pump(const Duration(milliseconds: 1));
    expect(starts, 2);
    await _waitForListener(tester, second);
    expect(first.stopCalls, 1);

    first.emit([_FixtureDevice(id: 'stale', name: 'Stale')]);
    second.emit([_FixtureDevice(id: 'current', name: 'Current')]);
    await _pumpUi(tester);
    expect(find.byKey(const ValueKey('dlna-device-stale')), findsNothing);
    expect(find.byKey(const ValueKey('dlna-device-current')), findsOneWidget);
  });

  testWidgets('cast requests are single-flight and await set-source before play', (tester) async {
    final notices = <String>[];
    final session = _FixtureSession();
    final setGate = Completer<void>();
    final playGate = Completer<void>();
    final device = _FixtureDevice(id: 'receiver', name: 'Receiver', setGate: setGate, playGate: playGate);
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(datasource: _source, startDiscovery: () async => session, notice: notices.add),
    );
    await _waitForListener(tester, session);
    session.emit([device]);
    await _pumpUi(tester);

    final dynamic state = tester.state(find.byType(LiveDlnaPage));
    final Future<void> first = state.castToDevice('receiver') as Future<void>;
    final Future<void> second = state.castToDevice('receiver') as Future<void>;
    expect(first, same(second));
    expect(device.events, ['set:$_source']);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    setGate.complete();
    await tester.pump();
    expect(device.events, ['set:$_source', 'play']);
    expect(notices, isEmpty);

    playGate.complete();
    await tester.pump();
    await first;
    await _pumpUi(tester);
    expect(notices, ['dlna_cast_started']);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('switching receivers waits for the previous pause and tolerates its failure', (tester) async {
    final session = _FixtureSession();
    final first = _FixtureDevice(id: 'first', name: 'First');
    final second = _FixtureDevice(id: 'second', name: 'Second');
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(datasource: _source, startDiscovery: () async => session, notice: (_) {}),
    );
    await _waitForListener(tester, session);
    session.emit([first, second]);
    await _pumpUi(tester);

    final dynamic state = tester.state(find.byType(LiveDlnaPage));
    await state.castToDevice('first');
    await tester.pump();
    first.pauseError = StateError('fixture receiver left');
    await state.castToDevice('second');
    await _pumpUi(tester);

    expect(first.events, ['set:$_source', 'play', 'pause']);
    expect(second.events, ['set:$_source', 'play']);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('cast failure stays visible and permits an explicit retry', (tester) async {
    final notices = <String>[];
    final session = _FixtureSession();
    final device = _FixtureDevice(id: 'receiver', name: 'Receiver')..setError = StateError('fixture set failure');
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(datasource: _source, startDiscovery: () async => session, notice: notices.add),
    );
    await _waitForListener(tester, session);
    session.emit([device]);
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('dlna-device-receiver')));
    await _pumpUi(tester);
    expect(find.byKey(const ValueKey('dlna-inline-error')), findsOneWidget);
    expect(notices, ['dlna_cast_failed']);

    device.setError = null;
    await tester.tap(find.byKey(const ValueKey('dlna-device-receiver')));
    await _pumpUi(tester);
    expect(notices, ['dlna_cast_failed', 'dlna_cast_started']);
    expect(find.byKey(const ValueKey('dlna-inline-error')), findsNothing);
  });

  testWidgets('closing during discovery stops the late session without publishing it', (tester) async {
    final gate = Completer<DlnaDiscoverySession>();
    final session = _FixtureSession();
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(datasource: _source, startDiscovery: () => gate.future),
      settle: false,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(session);
    await tester.pump();
    await tester.pump();
    expect(session.stopCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing after source assignment suppresses the late play command', (tester) async {
    final session = _FixtureSession();
    final setGate = Completer<void>();
    final device = _FixtureDevice(id: 'receiver', name: 'Receiver', setGate: setGate);
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(datasource: _source, startDiscovery: () async => session, notice: (_) {}),
    );
    await _waitForListener(tester, session);
    session.emit([device]);
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('dlna-device-receiver')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    setGate.complete();
    await tester.pump();
    await tester.pump();
    expect(device.events, ['set:$_source']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow 3x English empty and device states keep controls reachable', (tester) async {
    final session = _FixtureSession();
    await _pumpDialog(
      tester,
      english,
      LiveDlnaPage(
        datasource: _source,
        startDiscovery: () async => session,
        searchDuration: const Duration(milliseconds: 300),
        notice: (_) {},
      ),
      textScale: 3,
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await _pumpUi(tester);
    final retry = find.byKey(const ValueKey('dlna-retry'));
    await tester.ensureVisible(retry);
    await _pumpUi(tester);
    expect(retry.hitTestable(), findsOneWidget);
    expect(tester.getRect(retry).right, lessThanOrEqualTo(320));

    await tester.tap(retry);
    await _pumpUi(tester);
    await _waitForListener(tester, session);
    session.emit([
      _FixtureDevice(
        id: 'receiver-with-a-very-long-network-identity',
        name: 'A very long living-room receiver name that must remain inside the dialog',
      ),
    ]);
    await _pumpUi(tester);
    final tile = find.byKey(const ValueKey('dlna-device-receiver-with-a-very-long-network-identity'));
    await tester.ensureVisible(tile);
    await _pumpUi(tester);
    expect(tile.hitTestable(), findsOneWidget);
    expect(tester.getRect(tile).right, lessThanOrEqualTo(320));
    expect(find.text(english['close'] as String).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _source = 'https://media.example/live.m3u8';

class _FixtureSession implements DlnaDiscoverySession {
  final _controller = StreamController<List<DlnaCastDevice>>.broadcast(sync: true);
  int stopCalls = 0;

  @override
  Stream<List<DlnaCastDevice>> get devices => _controller.stream;

  bool get hasListener => _controller.hasListener;

  void emit(List<DlnaCastDevice> devices) => _controller.add(devices);

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

class _FixtureDevice implements DlnaCastDevice {
  _FixtureDevice({required this.id, required this.name, this.setGate, this.playGate});

  @override
  final String id;
  @override
  final String name;
  final Completer<void>? setGate;
  final Completer<void>? playGate;
  Object? setError;
  Object? playError;
  Object? pauseError;
  final events = <String>[];

  @override
  Future<void> pause() async {
    events.add('pause');
    final error = pauseError;
    if (error != null) throw error;
  }

  @override
  Future<void> setSource(String source) async {
    events.add('set:$source');
    final error = setError;
    if (error != null) throw error;
    await setGate?.future;
  }

  @override
  Future<void> play() async {
    events.add('play');
    final error = playError;
    if (error != null) throw error;
    await playGate?.future;
  }
}

Future<void> _pumpDialog(
  WidgetTester tester,
  Map<String, dynamic> labels,
  Widget home, {
  bool settle = true,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: _Labels(labels),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: Center(child: home)),
        ),
      ),
    ),
  );
  if (settle) {
    await _pumpUi(tester);
  } else {
    await tester.pump();
  }
}

class _Labels extends AssetLoader {
  const _Labels(this.labels);

  final Map<String, dynamic> labels;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => labels;
}

Future<void> _waitForListener(WidgetTester tester, _FixtureSession session) async {
  for (var index = 0; index < 20 && !session.hasListener; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(session.hasListener, isTrue);
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}
