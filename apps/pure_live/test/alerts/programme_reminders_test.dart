import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/appearance.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/alert_notifier.dart';
import 'package:pure_live_app/features/alerts/alert_tiles.dart';
import 'package:pure_live_app/features/alerts/programme_reminders.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/iptv/iptv_room.dart';

import 'fake_notifier.dart';

/// Reminder storage in memory, so timers can run on a fake clock.
final class _MemoryStorage {
  String? text;
  int writes = 0;

  ReminderStorage get storage => ReminderStorage(
    read: () async => text,
    write: (value) async {
      writes++;
      text = value;
    },
  );

  List<String> get titles => [
    for (final item in (text == null ? const <Object?>[] : jsonDecode(text!) as List)) (item as Map)['title'] as String,
  ];
}

/// The site only needs its clock for the sheet.
final class _NoRepository implements IptvRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final channel = IptvSite.refOf('CCTV-1 综合');
  final t0 = DateTime.utc(2026, 9, 28, 12);

  ProgrammeReminder reminder(Duration fromT0, String title) => ProgrammeReminder(
    room: channel,
    title: title,
    start: t0.add(fromT0),
    stop: t0.add(fromT0 + const Duration(minutes: 30)),
  );

  group('timers', () {
    late _MemoryStorage memory;
    late FakeAlertNotifier notifier;

    ProviderContainer container(FakeAsync async) {
      final container = ProviderContainer(
        overrides: [
          programmeReminderStorageProvider.overrideWithValue(memory.storage),
          alertNotifierProvider.overrideWithValue(notifier),
          alertClockProvider.overrideWithValue(() => t0.add(async.elapsed)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() {
      memory = _MemoryStorage();
      notifier = FakeAlertNotifier();
    });

    test('a reminder fires 1 minute before the start, then leaves the list', () {
      fakeAsync((async) {
        final reminders = container(async);
        final news = reminder(const Duration(minutes: 10), '新闻联播');
        var on = false;
        unawaited(reminders.read(programmeRemindersProvider.notifier).toggle(news).then((value) => on = value));
        async.flushMicrotasks();
        expect(on, isTrue);
        expect(reminders.read(programmeRemindersProvider), [news]);
        expect(memory.titles, ['新闻联播'], reason: 'stored at once');

        async.elapse(const Duration(minutes: 8, seconds: 59));
        expect(notifier.shown, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(notifier.shown.single.title, '新闻联播 即将开始');
        expect(notifier.shown.single.channel, AlertChannel.programme);
        expect(notifier.shown.single.payload, roomLocation(channel), reason: 'a tap opens the channel');
        expect(notifier.shown.single.body, contains('CCTV-1 综合'));
        expect(reminders.read(programmeRemindersProvider), isEmpty);
        expect(memory.text, isNull);
      });
    });

    test('toggling again removes the reminder and its timer', () {
      fakeAsync((async) {
        final reminders = container(async);
        final news = reminder(const Duration(minutes: 10), '新闻联播');
        final notifier$ = reminders.read(programmeRemindersProvider.notifier);
        notifier$.toggle(news).ignore();
        async.flushMicrotasks();
        var on = true;
        unawaited(notifier$.toggle(news).then((value) => on = value));
        async.flushMicrotasks();
        expect(on, isFalse);
        expect(notifier$.contains(news), isFalse);
        async.elapse(const Duration(hours: 1));
        expect(notifier.shown, isEmpty);
        expect(memory.text, isNull);
      });
    });

    test('a programme that already started cannot be set', () {
      fakeAsync((async) {
        final reminders = container(async);
        var on = true;
        unawaited(
          reminders
              .read(programmeRemindersProvider.notifier)
              .toggle(reminder(const Duration(minutes: -1), '已开始'))
              .then((value) => on = value),
        );
        async.flushMicrotasks();
        expect(on, isFalse);
        expect(reminders.read(programmeRemindersProvider), isEmpty);
      });
    });

    test('a restart restores pending reminders: due ones fire at once, started ones are dropped', () {
      memory.text = jsonEncode([
        reminder(const Duration(minutes: -5), '已经开始').toJson(),
        reminder(const Duration(seconds: 30), '马上开始').toJson(),
        reminder(const Duration(hours: 1), '一小时后').toJson(),
        {'title': 'broken'},
      ]);
      fakeAsync((async) {
        final reminders = container(async);
        int? pending;
        unawaited(reminders.read(programmeRemindersProvider.notifier).restore().then((value) => pending = value));
        async.flushMicrotasks();
        expect(pending, 2);
        expect(memory.titles, ['马上开始', '一小时后'], reason: 'the started one is dropped from storage');

        async.elapse(Duration.zero);
        expect(notifier.shown.map((notice) => notice.title), ['马上开始 即将开始']);
        async.elapse(const Duration(minutes: 59));
        expect(notifier.shown, hasLength(2));
        expect(memory.text, isNull);
      });
    });
  });

  test('reminders are kept in the meta table', () async {
    final store = await LiveStore.inMemory();
    addTearDown(store.close);
    final container = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        alertNotifierProvider.overrideWithValue(FakeAlertNotifier()),
        alertClockProvider.overrideWithValue(() => t0),
      ],
    );
    addTearDown(container.dispose);
    final news = reminder(const Duration(hours: 2), '新闻联播');
    expect(await container.read(programmeRemindersProvider.notifier).toggle(news), isTrue);
    final stored = await store.meta.get(ReminderStorage.key);
    expect(ProgrammeReminder.fromJson((jsonDecode(stored!) as List).single), news);

    final restarted = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        alertNotifierProvider.overrideWithValue(FakeAlertNotifier()),
        alertClockProvider.overrideWithValue(() => t0),
      ],
    );
    addTearDown(restarted.dispose);
    expect(await restarted.read(programmeRemindersProvider.notifier).restore(), 1);
    expect(restarted.read(programmeRemindersProvider), [news]);
  });

  group('guide sheet', () {
    Future<(FakeAlertNotifier, _MemoryStorage)> show(WidgetTester tester, {bool grant = true}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now().toUtc();
      final start = DateTime.utc(now.year, now.month, now.day, now.hour);
      IptvProgramme programme(int hours, String title) => IptvProgramme(
        channelId: 'CCTV1',
        start: start.add(Duration(hours: hours)),
        stop: start.add(Duration(hours: hours + 1)),
        title: title,
      );
      final notifier = FakeAlertNotifier(grant: grant, allowed: false);
      final memory = _MemoryStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iptvSiteProvider.overrideWithValue(IptvSite(_NoRepository(), now: () => now)),
            iptvChannelProvider.overrideWith(
              (ref, room) async => IptvChannel(
                ref: channel,
                sources: const [
                  IptvSource(
                    entry: IptvEntry(name: 'CCTV-1 综合', url: 'http://a.fixture/1.m3u8'),
                    playlistId: '1',
                  ),
                ],
                guideId: '1',
                guideChannelId: 'CCTV1',
              ),
            ),
            iptvGuideProvider.overrideWith((ref, room) async => [programme(0, '正在播出的节目'), programme(1, '下一个节目')]),
            alertNotifierProvider.overrideWithValue(notifier),
            programmeReminderStorageProvider.overrideWithValue(memory.storage),
          ],
          child: MaterialApp(
            theme: themesFor(AppThemeMode.light, pureBlack: false).$1,
            home: Scaffold(
              body: IptvGuideSheet(room: channel, now: now),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return (notifier, memory);
    }

    testWidgets('upcoming programmes offer 提醒我, which sets and clears a reminder', (tester) async {
      final (notifier, memory) = await show(tester);
      expect(find.text('提醒我'), findsOneWidget, reason: 'only the upcoming programme');
      await tester.tap(find.text('提醒我'));
      await tester.pump();
      await tester.pump();
      expect(notifier.requests, 1, reason: 'permission first (Android 13+)');
      expect(find.text('已提醒'), findsOneWidget);
      expect(memory.titles, ['下一个节目']);

      await tester.tap(find.text('已提醒'));
      await tester.pump();
      await tester.pump();
      expect(find.text('提醒我'), findsOneWidget);
      expect(memory.text, isNull);
    });

    testWidgets('a refused permission sets nothing and says why', (tester) async {
      final (notifier, memory) = await show(tester, grant: false);
      await tester.tap(find.text('提醒我'));
      await tester.pump();
      await tester.pump();
      expect(find.text('无法提醒'), findsOneWidget);
      expect(find.text('提醒我'), findsOneWidget);
      expect(memory.writes, 0);
      await tester.tap(find.text('知道了'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('无法提醒'), findsNothing);
    });

    testWidgets('platforms without notifications show no button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProgrammeReminderButton(
                room: channel,
                programme: IptvProgramme(
                  channelId: 'CCTV1',
                  start: DateTime.now().add(const Duration(hours: 1)),
                  stop: DateTime.now().add(const Duration(hours: 2)),
                  title: '下一个节目',
                ),
              ),
            ),
          ),
        ),
      );
      // The default notifier on a Linux host is the silent one.
      expect(
        ProviderScope.containerOf(tester.element(find.byType(Scaffold))).read(alertNotifierProvider),
        isA<NoAlertNotifier>(),
      );
      expect(find.text('提醒我'), findsNothing);
    });
  });
}
