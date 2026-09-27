import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';

/// Stable ordering for the recording centre.
///
/// The aggregate view keeps actionable states first; tasks with the same
/// state, and every status-filtered view, show the newest session first. This
/// prevents a newly stopped recording from being appended below an arbitrarily
/// long history where neither the user nor runtime verification can see it.
class RecorderTaskOrdering {
  const RecorderTaskOrdering._();

  static List<LiveRecordTask> forDisplay(Iterable<LiveRecordTask> tasks, {required bool groupByStatus}) {
    final result = tasks.toList(growable: false);
    result.sort((left, right) {
      if (groupByStatus) {
        final status = left.status.order.compareTo(right.status.order);
        if (status != 0) return status;
      }
      final time = right.displayStartTime.compareTo(left.displayStartTime);
      return time != 0 ? time : right.taskId.compareTo(left.taskId);
    });
    return result;
  }
}
