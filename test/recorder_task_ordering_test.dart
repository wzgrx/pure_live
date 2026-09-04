import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';
import 'package:pure_live/recorder/models/recorder_task_ordering.dart';

void main() {
  test('aggregate recording view groups actionable states then uses newest first', () {
    final stoppedNew = _task('stopped-new', RecordStatus.stopped, '2026-09-04T21:00:00');
    final runningOld = _task('running-old', RecordStatus.running, '2026-09-04T19:00:00');
    final stoppedOld = _task('stopped-old', RecordStatus.stopped, '2026-09-04T18:00:00');

    final result = RecorderTaskOrdering.forDisplay(<LiveRecordTask>[
      stoppedOld,
      stoppedNew,
      runningOld,
    ], groupByStatus: true);

    expect(result.map((task) => task.taskId), <String>['running-old', 'stopped-new', 'stopped-old']);
  });

  test('status-filtered recording view is newest first', () {
    final result = RecorderTaskOrdering.forDisplay(<LiveRecordTask>[
      _task('old', RecordStatus.stopped, '2026-09-04T18:00:00'),
      _task('new', RecordStatus.stopped, '2026-09-04T21:00:00'),
    ], groupByStatus: false);

    expect(result.map((task) => task.taskId), <String>['new', 'old']);
  });
}

LiveRecordTask _task(String taskId, RecordStatus status, String createTime) =>
    LiveRecordTask.fromJson(<String, dynamic>{
      'taskId': taskId,
      'roomId': taskId,
      'platform': 'bilibili',
      'statusName': status.name,
      'createTime': createTime,
    });
