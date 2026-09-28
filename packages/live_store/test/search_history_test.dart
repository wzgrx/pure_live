import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

/// spec/product.md F-SRC-06: recent searches, newest first, at most 20, one
/// entry per keyword; backed up with the full backup.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LiveStore store;

  setUp(() async => store = await LiveStore.inMemory());
  tearDown(() => store.close());

  List<String> keywords(List<SearchHistoryEntry> entries) => [for (final entry in entries) entry.keyword];
  Future<List<String>> shown() async => keywords(await store.searchHistory.all());

  group('recording', () {
    test('newest first; a keyword searched again moves to the top with its latest spelling', () async {
      final history = store.searchHistory;
      await history.record('英雄联盟', at: DateTime.utc(2026, 9));
      await history.record('  LOL  ', at: DateTime.utc(2026, 9, 2));
      await history.record('原神', at: DateTime.utc(2026, 9, 3));
      expect(await shown(), ['原神', 'LOL', '英雄联盟'], reason: 'trimmed');
      await history.record('lol', at: DateTime.utc(2026, 9, 4));
      expect(await shown(), ['lol', '原神', '英雄联盟'], reason: 'one entry per keyword, case folded');
      await history.record('英雄   联盟', at: DateTime.utc(2026, 9, 5));
      expect(await shown(), ['英雄 联盟', 'lol', '原神', '英雄联盟'], reason: 'inner spaces collapse to one');
    });

    test('blank keywords are not recorded', () async {
      expect(await store.searchHistory.record('   '), isFalse);
      expect(await shown(), isEmpty);
    });

    test('keeps the newest 20', () async {
      for (var i = 0; i < 25; i++) {
        await store.searchHistory.record('词$i', at: DateTime.utc(2026, 9, 1, 0, i));
      }
      final entries = await shown();
      expect(entries, hasLength(SearchHistoryStore.limit));
      expect(entries.first, '词24');
      expect(entries.last, '词5');
    });

    test('nothing is recorded while search history is off', () async {
      await store.settings.set(Settings.recordSearchHistory, false);
      expect(await store.searchHistory.record('原神'), isFalse);
      expect(await shown(), isEmpty);
    });

    test('watchAll emits after each change', () async {
      final seen = <List<String>>[];
      final subscription = store.searchHistory.watchAll().listen((entries) => seen.add(keywords(entries)));
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      await store.searchHistory.record('原神');
      await pumpEventQueue();
      await store.searchHistory.remove('原神');
      await pumpEventQueue();
      expect(seen, [
        <String>[],
        ['原神'],
        <String>[],
      ]);
    });
  });

  group('removing and undo', () {
    setUp(() async {
      await store.searchHistory.record('a', at: DateTime.utc(2026, 9));
      await store.searchHistory.record('b', at: DateTime.utc(2026, 9, 2));
      await store.searchHistory.record('c', at: DateTime.utc(2026, 9, 3));
    });

    test('one entry, then undo puts it back in its place', () async {
      final removed = await store.searchHistory.remove('B');
      expect(removed?.keyword, 'b');
      expect(await shown(), ['c', 'a']);
      expect(await store.searchHistory.remove('b'), isNull);
      await store.searchHistory.restore([removed!]);
      expect(await shown(), ['c', 'b', 'a']);
    });

    test('clear removes what was shown; a keyword searched since stays', () async {
      final seen = await store.searchHistory.all();
      await store.searchHistory.record('a', at: DateTime.utc(2026, 9, 4));
      await store.searchHistory.record('d', at: DateTime.utc(2026, 9, 5));
      final removed = await store.searchHistory.clear(seen);
      expect(keywords(removed), ['c', 'b']);
      expect(await shown(), ['d', 'a']);
      await store.searchHistory.restore(removed);
      expect(await shown(), ['d', 'a', 'c', 'b'], reason: 'a keeps its newer search');
    });

    test('clear without a list removes everything', () async {
      expect(keywords(await store.searchHistory.clear()), ['c', 'b', 'a']);
      expect(await shown(), isEmpty);
    });

    test('undo works while recording is off (turning it off clears, undo turns it back)', () async {
      await store.settings.set(Settings.recordSearchHistory, false);
      final removed = await store.searchHistory.clear();
      await store.searchHistory.restore(removed);
      expect(await shown(), ['c', 'b', 'a']);
    });
  });

  group('backup', () {
    late LiveStore target;

    setUp(() async => target = await LiveStore.inMemory());
    tearDown(() => target.close());

    Future<void> seed() async {
      await store.searchHistory.record('英雄联盟', at: DateTime.utc(2026, 9));
      await store.searchHistory.record('原神', at: DateTime.utc(2026, 9, 2));
    }

    test('the full backup carries the search history; restoring replaces the local one', () async {
      await seed();
      final document = await BackupService(store, platform: 'android').export();
      final sections = document['sections']! as Map<String, Object?>;
      expect(sections['searchHistory'], [
        {'keyword': '原神', 'searchedAt': DateTime.utc(2026, 9, 2).millisecondsSinceEpoch},
        {'keyword': '英雄联盟', 'searchedAt': DateTime.utc(2026, 9).millisecondsSinceEpoch},
      ]);
      await target.searchHistory.record('本机');
      final report = await BackupService(target, platform: 'android').restore(document);
      expect(report.counts['searchHistory']?.written, 2);
      expect(keywords(await target.searchHistory.all()), ['原神', '英雄联盟']);
    });

    test('the follows-only backup has none, and restoring follows keeps the local history', () async {
      await seed();
      final document = await BackupService(store, platform: 'android').export(scope: BackupScope.follows);
      expect((document['sections']! as Map<String, Object?>).containsKey('searchHistory'), isFalse);
      final full = await BackupService(store, platform: 'android').export();
      await target.searchHistory.record('本机');
      await BackupService(target, platform: 'android').restore(full, mode: RestoreMode.follows);
      expect(keywords(await target.searchHistory.all()), ['本机']);
    });

    test('an older v4 backup without the section leaves the local history as it is', () async {
      await seed();
      final document = await BackupService(store, platform: 'android').export();
      (document['sections']! as Map<String, Object?>).remove('searchHistory');
      await target.searchHistory.record('本机');
      final report = await BackupService(target, platform: 'android').restore(document);
      expect(report.issues, isEmpty);
      expect(keywords(await target.searchHistory.all()), ['本机']);
    });

    test('a 3.x backup has no search history and leaves the local one', () async {
      await target.searchHistory.record('本机');
      await BackupService(target, platform: 'android').restore({
        'backupVersion': 3,
        'favorite': {
          'favoriteRooms': [
            {'roomId': '1', 'platform': 'douyu'},
          ],
        },
      });
      expect(keywords(await target.searchHistory.all()), ['本机']);
    });

    test('the section is checked: duplicates, blanks and entries beyond 20 are dropped', () async {
      final document = await BackupService(store, platform: 'android').export();
      final millis = DateTime.utc(2026, 9).millisecondsSinceEpoch;
      (document['sections']! as Map<String, Object?>)['searchHistory'] = [
        {'keyword': 'LOL', 'searchedAt': millis + 100},
        {'keyword': 'lol', 'searchedAt': millis},
        {'keyword': '  '},
        'not an object',
        for (var i = 0; i < 20; i++) {'keyword': '词$i', 'searchedAt': millis - i},
      ];
      final report = await BackupService(target, platform: 'android').restore(document);
      final entries = keywords(await target.searchHistory.all());
      expect(entries, hasLength(20));
      expect(entries.take(3), ['LOL', '词0', '词1']);
      final reasons = [
        for (final issue in report.issues)
          if (issue.section == 'searchHistory') issue.reason,
      ];
      expect(reasons, containsAll(['duplicate', 'invalidItem', 'overLimit']));
    });

    test('a section that is not a list is a format error and nothing is written', () async {
      final document = await BackupService(store, platform: 'android').export();
      (document['sections']! as Map<String, Object?>)['searchHistory'] = {'keyword': 'x'};
      await target.searchHistory.record('本机');
      await expectLater(BackupService(target, platform: 'android').restore(document), throwsFormatException);
      expect(keywords(await target.searchHistory.all()), ['本机']);
    });

    test('when the restored settings turn recording off, no history is written and the local one goes', () async {
      await seed();
      final document = await BackupService(store, platform: 'android').export();
      ((document['sections']! as Map<String, Object?>)['settings']! as Map<String, Object?>)['search.recordHistory'] =
          false;
      await target.searchHistory.record('本机');
      final report = await BackupService(target, platform: 'android').restore(document);
      expect(target.settings.get(Settings.recordSearchHistory), isFalse);
      expect(await target.searchHistory.all(), isEmpty);
      expect(report.counts['searchHistory']?.written, 0);
      expect(report.issues.map((issue) => issue.reason), contains('recordingOff'));
    });
  });
}
