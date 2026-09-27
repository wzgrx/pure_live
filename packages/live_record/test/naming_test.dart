import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('sanitizePathComponent (§9)', () {
    test('replaces unsafe characters and whitespace, collapses underscores, trims trailing dots', () {
      expect(sanitizePathComponent(r'a<b>c:d"e/f\g|h?i*j'), 'a_b_c_d_e_f_g_h_i_j');
      expect(sanitizePathComponent('主播  名\t字'), '主播_名_字');
      expect(sanitizePathComponent('name...'), 'name');
      expect(sanitizePathComponent('name. .'), 'name._', reason: 'whitespace became _ first');
      expect(sanitizePathComponent('a\u0001b'), 'a_b');
    });

    test('caps at 80 characters without splitting surrogate pairs', () {
      final long = '😀' * 100;
      final result = sanitizePathComponent(long);
      expect(result.runes.length, 80);
      expect(result, '😀' * 80);
    });

    test('guards Windows reserved names and empty results', () {
      expect(sanitizePathComponent('CON'), '_CON');
      expect(sanitizePathComponent('nul.txt'), '_nul.txt');
      expect(sanitizePathComponent('com1'), '_com1');
      expect(sanitizePathComponent('console'), 'console');
      expect(sanitizePathComponent('   '), 'unknown');
      expect(sanitizePathComponent('...'), 'unknown');
    });

    test('runs a transliteration first (pinyin folders)', () {
      expect(sanitizePathComponent('主播', transliterate: (_) => 'zhu bo'), 'zhu_bo');
    });
  });

  test('session prefix is the local start time to the millisecond (REG-RECORD-014)', () {
    expect(sessionPrefix(DateTime(2026, 9, 27, 10, 15, 30, 123)), '20260927_101530_123');
    expect(sessionPrefix(DateTime(2026, 1, 2, 3, 4, 5, 6)), '20260102_030405_006');
  });

  test('layout: <root>/<platform>/<anchor>/<yyyy-MM-dd>/<prefix>_NNN.flv (§9)', () {
    final layout = SessionLayout.at('/rec', RoomRef('douyu', '9999'), '主播/A', DateTime(2026, 9, 27, 10, 15, 30, 123));
    expect(layout.directory, p.join('/rec', 'douyu', '主播_A', '2026-09-27'));
    expect(layout.segment(1), p.join(layout.directory, '20260927_101530_123_001.flv'));
    expect(layout.segment(12, extension: 'xml'), endsWith('_012.xml'));
    expect(layout.gaps, endsWith('20260927_101530_123.gaps.json'));
    final restored = SessionLayout.fromJson(layout.toJson());
    expect(restored.directory, layout.directory);
    expect(restored.prefix, layout.prefix);
    final unnamed = SessionLayout.at('/rec', RoomRef('douyu', '9999'), ' ', DateTime(2026));
    expect(unnamed.directory, contains('9999'), reason: 'no streamer name: the room id');
  });

  test('uniquePath adds -1, -2 and treats .part and .partial names as taken (§6.9)', () async {
    final files = MemoryRecordFiles()
      ..put('/d/a.flv', [1])
      ..put('/d/a-1.flv.part', [1])
      ..put('/d/b.mp4.partial', [1]);
    expect(await uniquePath(files, '/d/a.flv'), '/d/a-2.flv');
    expect(await uniquePath(files, '/d/b.mp4'), '/d/b-1.mp4');
    expect(await uniquePath(files, '/d/c.flv'), '/d/c.flv');
  });

  group('RecordRoot (§15)', () {
    test('default, chosen parent and a marked PureLiveRecords folder', () {
      expect(RecordRoot.resolve(defaultRoot: '/app/RECORDS'), '/app/RECORDS');
      expect(RecordRoot.resolve(defaultRoot: '/app/RECORDS', chosen: ' '), '/app/RECORDS');
      expect(RecordRoot.resolve(defaultRoot: '/app/RECORDS', chosen: '/data/user/0/x'), '/app/RECORDS');
      expect(
        RecordRoot.resolve(defaultRoot: '/app/RECORDS', chosen: '/sdcard/Movies'),
        '/sdcard/Movies/PureLiveRecords',
      );
      expect(
        RecordRoot.resolve(defaultRoot: '/app/RECORDS', chosen: '/sdcard/PureLiveRecords', isMarked: true),
        '/sdcard/PureLiveRecords',
      );
      expect(
        RecordRoot.resolve(defaultRoot: '/app/RECORDS', chosen: '/sdcard/PureLiveRecords'),
        '/sdcard/PureLiveRecords/PureLiveRecords',
        reason: 'an unmarked folder of that name is only a parent',
      );
    });

    test('prepare writes the marker and proves the folder writable', () async {
      final files = MemoryRecordFiles();
      expect(await RecordRoot.prepare('/rec', files: files), isNull);
      expect(await files.exists('/rec/${RecordRoot.markerName}'), isTrue);
      expect(files.paths.where((path) => path.contains('.probe')), isEmpty);
      files.writeError = const FileSystemException('denied', '/ro', OSError('Read-only file system', 30));
      final problem = await RecordRoot.prepare('/ro', files: files);
      expect(classifyFileError(problem!).kind, RecordErrorKind.readOnly);
    });
  });

  group('errors (§21)', () {
    test('site errors map to typed kinds', () {
      expect(classifySiteError(const NotFound('douyu'), RecordStage.room).kind, RecordErrorKind.roomNotFound);
      expect(classifySiteError(const NeedsLogin('douyu'), RecordStage.room).kind, RecordErrorKind.loginRequired);
      expect(classifySiteError(const StreamUnavailable('douyu'), RecordStage.room).kind, RecordErrorKind.roomOffline);
      expect(classifySiteError(const StreamUnavailable('douyu'), RecordStage.stream).kind, RecordErrorKind.noQuality);
      expect(classifySiteError(const NetworkFailure('douyu'), RecordStage.room).kind, RecordErrorKind.network);
      expect(classifySiteError(const ApiChanged('douyu'), RecordStage.room).kind, RecordErrorKind.roomStateUnknown);
    });

    test('file errors map by OS code', () {
      FileSystemException error(int code) => FileSystemException('x', '/p', OSError('e', code));
      expect(classifyFileError(error(28)).kind, RecordErrorKind.diskFull);
      expect(classifyFileError(error(112)).kind, RecordErrorKind.diskFull);
      expect(classifyFileError(error(13)).kind, RecordErrorKind.permissionDenied);
      expect(classifyFileError(error(30)).kind, RecordErrorKind.readOnly);
      expect(classifyFileError(error(2)).kind, RecordErrorKind.pathInvalid);
    });

    test('error text loses query strings, cookies and tokens (REG-RECORD-013)', () {
      final text = sanitizeErrorText(
        'GET https://cdn.test/live/1.flv?wsSecret=abc&token=def failed; cookie=acf_uid=1; token: xyz',
      );
      expect(text, isNot(contains('abc')));
      expect(text, isNot(contains('def')));
      expect(text, isNot(contains('xyz')));
      expect(text, isNot(contains('acf_uid=1')));
      expect(text, contains('https://cdn.test/live/1.flv?…'));
    });
  });
}
