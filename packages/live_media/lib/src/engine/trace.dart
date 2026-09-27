import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:live_media/src/engine/engine.dart';
import 'package:meta/meta.dart';

/// One line of a recorded engine trace (`fixtures/player/*/trace.jsonl`).
@immutable
final class TraceStep {
  /// A command the recorder issued (`open`, `pause`, `play`, `stop`, `dispose`).
  const new command(this.ms, String this.command) : event = null;

  /// An event the engine emitted.
  const new event(this.ms, EngineEvent this.event) : command = null;

  /// Milliseconds from the scenario start.
  final int ms;

  /// The command, for a command step.
  final String? command;

  /// The event, for an event step.
  final EngineEvent? event;

  @override
  String toString() => '$ms ${command ?? event}';
}

/// A media_kit event trace recorded from real libmpv (spec §4). Test doubles
/// replay these instead of inventing an order.
@immutable
final class EngineTrace {
  /// Creates a trace from steps.
  const new(this.steps);

  /// Parses the JSON-lines format of `fixtures/player`: `width` and `height`
  /// lines merge into one [EngineVideoSize]; track counts drop media_kit's
  /// `auto` and `no` pseudo tracks; `server` lines are skipped; recorded
  /// `error` lines came from the player core, so they carry the `cplayer` prefix.
  factory parse(String jsonLines) {
    final steps = <TraceStep>[];
    int? pendingWidth;
    var hasPendingWidth = false;
    for (final line in const LineSplitter().convert(jsonLines)) {
      if (line.trim().isEmpty) continue;
      final entry = jsonDecode(line) as Map<String, dynamic>;
      final ms = entry['ms'] as int;
      if (entry['command'] case final String command) {
        steps.add(TraceStep.command(ms, command));
        continue;
      }
      EngineEvent? event;
      if (entry.containsKey('width')) {
        pendingWidth = entry['width'] as int?;
        hasPendingWidth = true;
        continue;
      }
      if (entry.containsKey('height')) {
        event = EngineVideoSize(hasPendingWidth ? pendingWidth : null, entry['height'] as int?);
        hasPendingWidth = false;
      } else if (entry['playing'] case final bool playing) {
        event = EnginePlaying(playing);
      } else if (entry['completed'] case final bool completed) {
        event = EngineCompleted(completed);
      } else if (entry['buffering'] case final bool buffering) {
        event = EngineBuffering(buffering);
      } else if (entry['position'] case final int position) {
        event = EnginePosition(Duration(milliseconds: position));
      } else if (entry['duration'] case final int duration) {
        event = EngineDuration(Duration(milliseconds: duration));
      } else if (entry['tracks'] case final Map<String, dynamic> tracks) {
        event = EngineTracks(
          video: math.max(0, (tracks['video'] as int) - 2),
          audio: math.max(0, (tracks['audio'] as int) - 2),
        );
      } else if (entry['error'] case final String message) {
        event = EngineError(message, prefix: 'cplayer');
      }
      if (event != null) steps.add(TraceStep.event(ms, event));
    }
    return EngineTrace(List.unmodifiable(steps));
  }

  /// Loads `trace.jsonl` of a recorded scenario directory.
  factory load(String directory) => EngineTrace.parse(File('$directory/trace.jsonl').readAsStringSync());

  /// Steps in recorded order.
  final List<TraceStep> steps;

  /// The events only, in order.
  List<EngineEvent> get events => [for (final step in steps) ?step.event];

  /// Commands in order.
  List<String> get commands => [for (final step in steps) ?step.command];
}
