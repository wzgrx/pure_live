import 'dart:async';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';

/// A platform with scripted rooms and lines.
final class FakeSite extends LiveSite {
  new({
    this.status = LiveStatus.live,
    this.restriction,
    this.qualities = const [LivePlayQuality(quality: '原画', id: 'origin', sort: 2)],
    Map<String, List<LivePlayLine>>? lines,
    this.detailError,
  }) : lines =
           lines ??
           {
             'origin': const [LivePlayLine('rtmp://cdn-a.example/live/1?sign=a')],
           };

  LiveStatus status;
  LiveRestriction? restriction;
  List<LivePlayQuality> qualities;
  Map<String, List<LivePlayLine>> lines;
  Exception? detailError;
  final requests = <String>[];

  @override
  String get id => 'fake';

  @override
  String get name => 'Fake';

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    requests.add('detail');
    final error = detailError;
    if (error != null) throw error;
    return LiveRoom(
      roomId: roomId,
      platform: id,
      nick: '主播',
      title: 'title',
      liveStatus: status,
      restriction: restriction,
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => qualities;

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    requests.add('urls:${quality.selectionId}');
    return [for (final line in lines['${quality.selectionId}'] ?? const <LivePlayLine>[]) line.url];
  }
}

/// FFmpeg that writes clock-v1 segments for a capture and an MP4 for a
/// join, ending when cancelled (a capture) or at once (a join).
final class FakeFfmpeg implements FfmpegRunner {
  final runs = <List<String>>[];
  final executions = <FakeExecution>[];

  /// The concat manifest of every join, read when it starts.
  final joinManifests = <String>[];

  /// Code a capture ends with by itself after [captureSeconds]; null runs
  /// until cancelled.
  int? captureExit;
  Duration captureSeconds = Duration.zero;

  /// Bytes of the segment a capture writes; 0 writes an empty segment and
  /// an empty journal (FFmpeg cut off before any data).
  int captureBytes = 1000;

  /// Statistics a join reports, one per turn of the event loop, before it
  /// ends; none: it ends at once.
  List<FfmpegStatistics> joinStatistics = const [];

  @override
  Future<FfmpegExecution> start(List<String> arguments) async {
    runs.add(arguments);
    final execution = FakeExecution();
    executions.add(execution);
    if (arguments.contains('concat')) {
      final output = arguments.last;
      joinManifests.add(File(arguments[arguments.indexOf('-i') + 1]).readAsStringSync());
      File(output).writeAsStringSync('mp4');
      final samples = List.of(joinStatistics);
      void next() {
        if (samples.isEmpty) {
          execution.finish(0);
        } else {
          execution.stats.add(samples.removeAt(0));
          Timer.run(next);
        }
      }

      if (samples.isEmpty) {
        scheduleMicrotask(next);
      } else {
        Timer.run(next);
      }
      return execution;
    }
    final pattern = arguments.last;
    final journal = arguments[arguments.indexOf('-segment_list') + 1];
    final segment = pattern.replaceFirst('%06d', '000000');
    File(segment).writeAsBytesSync(List.filled(captureBytes, 1));
    File(journal)
        .writeAsStringSync(captureBytes > 0 ? '${segment.split(Platform.pathSeparator).last},0.000000,4.000000\n' : '');
    Timer.run(() => execution.stats.add(const FfmpegStatistics(time: 4000, videoFrame: 100)));
    final exit = captureExit;
    if (exit != null) Timer(captureSeconds, () => execution.finish(exit));
    return execution;
  }
}

final class FakeExecution implements FfmpegExecution {
  final _logs = StreamController<String>.broadcast();
  final stats = StreamController<FfmpegStatistics>.broadcast();
  final _exit = Completer<int>();
  bool cancelled = false;

  void finish(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  void log(String line) => _logs.add(line);

  @override
  Stream<String> get logs => _logs.stream;

  @override
  Stream<FfmpegStatistics> get statistics => stats.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void cancel() {
    cancelled = true;
    finish(255);
  }
}
