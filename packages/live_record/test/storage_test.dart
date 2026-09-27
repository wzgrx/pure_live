import 'dart:io';

import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const int _mb = 1024 * 1024;

void main() {
  group('enforceStorageLimit (§15)', () {
    late MemoryRecordFiles files;
    final day = DateTime.utc(2026, 9);

    setUp(() {
      files = MemoryRecordFiles()
        ..put('/rec/${RecordRoot.markerName}', List.filled(10, 0), modified: day)
        ..put('/rec/douyu/a/2026-09-01/old_001.mp4', List.filled(3 * _mb, 1), modified: day)
        ..put('/rec/douyu/a/2026-09-01/old.gaps.json', List.filled(100, 1), modified: day.add(const Duration(hours: 1)))
        ..put('/rec/huya/b/2026-09-02/mid_001.mp4', List.filled(2 * _mb, 1), modified: day.add(const Duration(days: 1)))
        ..put(
          '/rec/huya/b/2026-09-03/new_001.flv.part',
          List.filled(4 * _mb, 1),
          modified: day.add(const Duration(days: 2)),
        );
    });

    test('under the limit nothing is deleted; the marker does not count', () async {
      final sweep = await enforceStorageLimit(files: files, root: '/rec', limitBytes: 9 * _mb + 100);
      expect(sweep.totalBytes, 9 * _mb + 100);
      expect(sweep.deleted, isEmpty);
      expect(files.paths, hasLength(5));
    });

    test('over the limit the oldest files go first until it fits; empty folders are removed', () async {
      final sweep = await enforceStorageLimit(files: files, root: '/rec', limitBytes: 6 * _mb);
      expect(sweep.deleted, ['/rec/douyu/a/2026-09-01/old_001.mp4', '/rec/douyu/a/2026-09-01/old.gaps.json']);
      expect(sweep.remainingBytes, 6 * _mb);
      expect(files.paths, contains('/rec/${RecordRoot.markerName}'), reason: 'the marker stays');
      expect(files.directories, isNot(contains('/rec/douyu/a/2026-09-01')));
      expect(files.directories, isNot(contains('/rec/douyu')), reason: 'deepest first, up to the root');
      expect(files.directories, contains('/rec'));
      expect(sweep.directoriesRemoved, 3);
    });

    test('protected session folders count but are never deleted (REG-RECORD-015)', () async {
      final sweep = await enforceStorageLimit(
        files: files,
        root: '/rec',
        limitBytes: 1 * _mb,
        isProtected: (dir) => dir == '/rec/huya/b/2026-09-03',
      );
      expect(sweep.deleted, hasLength(3));
      expect(files.paths, contains('/rec/huya/b/2026-09-03/new_001.flv.part'));
      expect(sweep.remainingBytes, 4 * _mb, reason: 'still over the limit: only protected files are left');
      expect(files.directories, contains('/rec/huya/b/2026-09-03'));
      expect(files.directories, contains('/rec/huya/b'), reason: 'a parent of a protected folder is not empty');
    });

    test('a locked file is skipped and the next one taken (bounded work)', () async {
      files.locked.add(p.normalize('/rec/douyu/a/2026-09-01/old_001.mp4'));
      final sweep = await enforceStorageLimit(files: files, root: '/rec', limitBytes: 7 * _mb);
      expect(sweep.deleted, ['/rec/douyu/a/2026-09-01/old.gaps.json', '/rec/huya/b/2026-09-02/mid_001.mp4']);
      expect(files.paths, contains('/rec/douyu/a/2026-09-01/old_001.mp4'));
    });

    test('a missing root is an empty sweep', () async {
      final sweep = await enforceStorageLimit(files: MemoryRecordFiles(), root: '/none', limitBytes: 0);
      expect(sweep.totalBytes, 0);
      expect(sweep.deleted, isEmpty);
    });
  });

  test('IoRecordFiles.scan and deleteDirectoryIfEmpty work on disk', () async {
    final temp = await Directory.systemTemp.createTemp('live_record_storage');
    addTearDown(() => temp.delete(recursive: true));
    final root = p.join(temp.path, 'rec');
    await File(p.join(root, 'douyu', 'a', 'x.flv')).create(recursive: true);
    await File(p.join(root, 'douyu', 'a', 'x.flv')).writeAsBytes([1, 2, 3]);
    await Directory(p.join(root, 'empty', 'deeper')).create(recursive: true);
    const io = IoRecordFiles();
    final tree = await io.scan(root);
    expect(tree.files.single.path, p.join(root, 'douyu', 'a', 'x.flv'));
    expect(tree.files.single.size, 3);
    expect(tree.directories, containsAll([p.join(root, 'douyu'), p.join(root, 'douyu', 'a'), p.join(root, 'empty')]));
    expect(await io.deleteDirectoryIfEmpty(p.join(root, 'douyu', 'a')), isFalse);
    expect(await io.deleteDirectoryIfEmpty(p.join(root, 'empty', 'deeper')), isTrue);
    expect(await io.deleteDirectoryIfEmpty(p.join(root, 'empty')), isTrue);
    expect((await io.scan(p.join(temp.path, 'missing'))).files, isEmpty);

    final sweep = await enforceStorageLimit(files: io, root: root, limitBytes: 0);
    expect(sweep.deleted, [p.join(root, 'douyu', 'a', 'x.flv')]);
    expect(Directory(p.join(root, 'douyu')).existsSync(), isFalse);
    expect(Directory(root).existsSync(), isTrue);
  });
}
