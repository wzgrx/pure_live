import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/toolbox_test_site.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> translations;
  late Map<String, dynamic> english;
  late List<String> notices;
  late List<String> copied;
  late List<String> casted;
  bool currentRoom = true;
  Future<void>? castReply;
  late ToolBoxTestSite site;
  late List<Completer<Object?>> writes;
  late BuildContext origin;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    translations = jsonDecode(await File('assets/translations/zh.json').readAsString()) as Map<String, dynamic>;
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });
  setUp(() {
    Get.testMode = true;
    site = ToolBoxTestSite();
    writes = [];
    notices = [];
    copied = [];
    casted = [];
    currentRoom = true;
    castReply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
          final pending = Completer<Object?>();
          writes.add(pending);
          return pending.future;
        }
        return null;
      },
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    Get.reset();
  });
  Future<void> frame(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> open(WidgetTester tester, {String locale = 'zh', bool narrow = false}) async {
    tester.view.physicalSize = narrow ? const Size(320, 480) : const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      for (final pending in writes) {
        if (!pending.isCompleted) pending.complete(null);
      }
      if (origin.mounted) Navigator.of(origin).popUntil((route) => route.isFirst);
      unawaited(SmartDialog.dismiss());
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: [Locale(locale)],
        startLocale: Locale(locale),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Loader(locale == 'zh' ? translations : english),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            navigatorObservers: [FlutterSmartDialog.observer],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
              child: FlutterSmartDialog.init()(context, child),
            ),
            home: Builder(
              builder: (context) {
                origin = context;
                return const Scaffold(body: Text('Player fixture'));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> run({bool cast = false}) => cast
      ? LiveUrlTool.castPlayUrlByRoomId(
          context: origin,
          roomId: '123',
          platform: 'bilibili',
          siteFor: (_) => site,
          isCurrentRoom: () => currentRoom,
          notify: notices.add,
          openCast: (url) {
            casted.add(url);
            return castReply ?? Future.value();
          },
        )
      : LiveUrlTool.getPlayUrlByRoomId(
          context: origin,
          roomId: '123',
          platform: 'bilibili',
          siteFor: (_) => site,
          isCurrentRoom: () => currentRoom,
          notify: notices.add,
        );
  for (final cast in [false, true]) {
    testWidgets('known-room ${cast ? 'cross-action' : 'copy'} requests are single-flight', (tester) async {
      final pending = Completer<LiveRoom>();
      site.detailReply = pending.future;
      await open(tester);
      final first = run();
      final second = run(cast: cast);
      await frame(tester);
      final count = site.calls.where((call) => call == 'detail').length;
      pending.completeError(StateError('fixture end'));
      await Future.wait([first, second]);
      await frame(tester);
      expect(count, 1);
    });
    testWidgets('known-room ${cast ? 'cast' : 'copy'} ignores late result after leaving origin', (tester) async {
      final pending = Completer<LiveRoom>();
      site.detailReply = pending.future;
      await open(tester);
      unawaited(run(cast: cast));
      await frame(tester);
      unawaited(
        Navigator.of(origin).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Other page')))),
      );
      await frame(tester);
      pending.complete(site.room);
      await frame(tester);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.text('Other page'), findsOneWidget);
    });
  }
  testWidgets('known-room copy waits for clipboard acknowledgement', (tester) async {
    await open(tester);
    var done = false;
    unawaited(run().then((_) => done = true));
    await frame(tester);
    await tester.tap(find.widgetWithText(ListTile, 'HD'));
    await frame(tester);
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.byType(ListTile)).first);
    await frame(tester);
    expect(writes, hasLength(1));
    expect(done, isFalse);
  });
  testWidgets('empty known-room lines do not open an empty selector', (tester) async {
    site.urls = [];
    await open(tester);
    unawaited(run());
    await frame(tester);
    await tester.tap(find.widgetWithText(ListTile, 'HD'));
    await frame(tester);
    expect(find.byType(SimpleDialog), findsNothing);
  });
  testWidgets('known-room copy success is emitted only after actual clipboard completion', (tester) async {
    await open(tester);
    var done = false;
    unawaited(run().then((_) => done = true));
    await frame(tester);
    await tester.tap(find.widgetWithText(ListTile, 'SD'));
    await frame(tester);
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.byType(ListTile)).last);
    await frame(tester);
    expect(site.requestedQuality, same(site.qualities.last));
    expect(copied, [site.urls.last]);
    expect(notices, isEmpty);
    expect(done, isFalse);
    writes.single.complete(null);
    await frame(tester);
    expect(done, isTrue);
    expect(notices, ['toolbox_copy_success']);
    expect(find.byType(SimpleDialog), findsNothing);
  });
  testWidgets('clipboard error closes the action without reporting success', (tester) async {
    await open(tester);
    unawaited(run());
    await frame(tester);
    await tester.tap(find.widgetWithText(ListTile, 'HD'));
    await frame(tester);
    await tester.tap(find.byType(ListTile).first);
    await frame(tester);
    writes.single.completeError(PlatformException(code: 'fixture_denied'));
    await frame(tester);
    expect(notices, ['toolbox_copy_failed']);
    expect(find.byType(SimpleDialog), findsNothing);
  });
  testWidgets('cast hands the selected URL to the receiver UI without copying', (tester) async {
    final pending = Completer<void>();
    castReply = pending.future;
    await open(tester);
    var done = false;
    unawaited(run(cast: true).then((_) => done = true));
    await frame(tester);
    await tester.tap(find.widgetWithText(ListTile, 'HD'));
    await frame(tester);
    await tester.tap(find.byType(ListTile).last);
    await frame(tester);
    expect(casted, [site.urls.last]);
    expect(writes, isEmpty);
    expect(done, isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(done, isFalse, reason: 'Receiver controls are user interaction, not a network timeout.');
    pending.complete();
    await frame(tester);
    expect(done, isTrue);
    expect(notices, isEmpty);
  });
  testWidgets('cancel releases the guard and ignores a late network result', (tester) async {
    final pending = Completer<LiveRoom>();
    site.detailReply = pending.future;
    await open(tester);
    final action = run();
    await frame(tester);
    await tester.tap(find.widgetWithText(TextButton, translations['cancel'] as String));
    await frame(tester);
    await action;
    pending.complete(site.room);
    await frame(tester);
    expect(site.calls, ['detail']);
    expect(notices, isEmpty);
    site.detailReply = null;
    unawaited(run());
    await frame(tester);
    expect(find.widgetWithText(ListTile, 'HD'), findsOneWidget);
  });
  testWidgets('changed room invalidates a pending result', (tester) async {
    final pending = Completer<LiveRoom>();
    site.detailReply = pending.future;
    await open(tester);
    unawaited(run());
    await frame(tester);
    currentRoom = false;
    pending.complete(site.room);
    await frame(tester);
    expect(site.calls, ['detail']);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(notices, isEmpty);
  });
  testWidgets('changed room prevents a visible stale choice from casting', (tester) async {
    await open(tester);
    unawaited(run(cast: true));
    await frame(tester);
    currentRoom = false;
    await tester.tap(find.widgetWithText(ListTile, 'HD'));
    await frame(tester);
    expect(site.calls, ['detail', 'qualities']);
    expect(casted, isEmpty);
    expect(find.byType(SimpleDialog), findsNothing);
  });
  testWidgets('duplicate retiring choice callbacks execute once', (tester) async {
    await open(tester);
    unawaited(run());
    await frame(tester);
    final quality = tester.widget<ListTile>(find.widgetWithText(ListTile, 'HD'));
    quality.onTap!();
    quality.onTap!();
    await frame(tester);
    final line = tester.widget<ListTile>(find.byType(ListTile).first);
    line.onTap!();
    line.onTap!();
    await frame(tester);
    expect(site.calls, ['detail', 'qualities', 'urls']);
    expect(writes, hasLength(1));
    // A non-opaque dialog retains the source page; duplicate callbacks must not pop it.
    expect(find.text('Player fixture', skipOffstage: false), findsOneWidget);
  });
  testWidgets('request timeout closes owned UI and does not advance after a late reply', (tester) async {
    final pending = Completer<LiveRoom>();
    site.detailReply = pending.future;
    await open(tester);
    unawaited(run());
    await frame(tester);
    await tester.pump(const Duration(seconds: 13));
    await frame(tester);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(notices, ['toolbox_get_url_failed']);
    pending.complete(site.room);
    await frame(tester);
    expect(site.calls, ['detail']);
  });
  for (final locale in ['zh', 'en']) {
    testWidgets('$locale narrow large-text selector remains cancellable', (tester) async {
      await open(tester, locale: locale, narrow: true);
      unawaited(run());
      await frame(tester);
      final cancel = find.widgetWithText(TextButton, (locale == 'zh' ? translations : english)['cancel'] as String);
      await tester.ensureVisible(cancel);
      await frame(tester);
      await tester.tap(cancel);
      await frame(tester);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Loader extends AssetLoader {
  _Loader(this.data);
  final Map<String, dynamic> data;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}
