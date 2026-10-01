import 'package:live_record/live_record.dart';
import 'package:pure_live/shared/record/record_state.dart';

/// The recording centre's filters (docs/ui/compare/U.7a, c6, choice U1 A):
/// one row of five with counts instead of 3.x's nine. "没在录制" shows only
/// under [all]; the card itself names every state.
enum RecorderFilter {
  /// Every task.
  all,

  /// Recording, reconnecting, joining, preparing, queued.
  active,

  /// Waiting for the room to go live.
  waiting,

  /// Finished with a file.
  saved,

  /// Failed and not retrying.
  failed;

  /// Whether a card in [state] shows under this filter.
  bool accepts(RecordCardState state) => switch (this) {
    all => true,
    active => const {
      RecordCardState.recording,
      RecordCardState.reconnecting,
      RecordCardState.processing,
      RecordCardState.preparing,
      RecordCardState.queued,
    }.contains(state),
    waiting => state == RecordCardState.waiting,
    saved => state == RecordCardState.saved,
    failed => state == RecordCardState.failed,
  };
}

/// The card state of each of [tasks] when [capacity] recordings may run at
/// once (a queued task with a free slot shows as preparing).
Map<String, RecordCardState> recorderStates(List<RecordTask> tasks, {required int capacity}) {
  final running = recordSlotsInUse(tasks);
  return {for (final task in tasks) task.taskId: recordCardState(task, running: running, capacity: capacity)};
}

/// The tasks under [filter] in the centre's order (U.7a c1, 3.x's): by
/// [recordCardOrder], then the newest session first, then by id.
List<RecordTask> recorderVisible(List<RecordTask> tasks, Map<String, RecordCardState> states, RecorderFilter filter) {
  int rank(RecordTask task) => recordCardOrder.indexOf(states[task.taskId] ?? RecordCardState.idle);
  return tasks.where((task) => filter.accepts(states[task.taskId] ?? RecordCardState.idle)).toList()
    ..sort((left, right) {
      final state = rank(left).compareTo(rank(right));
      if (state != 0) return state;
      final time = right.displayStartTime.compareTo(left.displayStartTime);
      return time != 0 ? time : right.taskId.compareTo(left.taskId);
    });
}

/// The number of tasks under each filter.
typedef RecorderCounts = ({int all, int active, int waiting, int saved, int failed});

/// The counts of [states].
RecorderCounts recorderCounts(Map<String, RecordCardState> states) {
  int count(RecorderFilter filter) => states.values.where(filter.accepts).length;
  return (
    all: states.length,
    active: count(RecorderFilter.active),
    waiting: count(RecorderFilter.waiting),
    saved: count(RecorderFilter.saved),
    failed: count(RecorderFilter.failed),
  );
}

/// The count of [filter] in [counts].
int recorderCountOf(RecorderCounts counts, RecorderFilter filter) => switch (filter) {
  RecorderFilter.all => counts.all,
  RecorderFilter.active => counts.active,
  RecorderFilter.waiting => counts.waiting,
  RecorderFilter.saved => counts.saved,
  RecorderFilter.failed => counts.failed,
};

/// The smallest card of the grid (U.7a c10).
const double recorderMinCardWidth = 400;

/// The gap between cards.
const double recorderCardGap = 12;

/// Columns of the task grid in [width] (the list's width inside its
/// padding): as many cards of at least [recorderMinCardWidth] as fit, one to
/// four (a phone in portrait one, in landscape two, 1280 wide three, 1920
/// four).
int recorderColumns(double width) =>
    ((width + recorderCardGap) / (recorderMinCardWidth + recorderCardGap)).floor().clamp(1, 4);
