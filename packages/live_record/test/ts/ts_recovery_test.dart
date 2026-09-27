import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/ts_check.dart';
import '../support/ts_live.dart';

void main() {
  final layout = SessionLayout.at('/rec', RoomRef('iptv', 'CCTV-1'), 'CCTV-1', DateTime(2026, 9, 28, 10));
  final live = TsLive(durationMs: 20000);
  final source = TsCheck.of(live.bytes(0, live.packets.length));

  /// A continuous recording from the keyframe at 11 s (PAT and PMT first)
  /// that a crash cut at stream time [endUs].
  Uint8List crashed(int endUs) => live.bytes(live.indexAt(11000000), live.indexAt(endUs));

  test('a crashed continuous .ts is cut before its last video PES when PATs sit inside frames (§14.1)', () async {
    final files = MemoryRecordFiles();
    final path = layout.segment(1, extension: 'ts');
    // The PAT at 14.1 s is inside the frame of 14.08 s; the frame of 14.12 s is cut.
    final bytes = crashed(14150000);
    files.put('$path.part', [...bytes, ...List.filled(50, 0x47)]);
    final segments = await recoverSession(files, layout, room: 'iptv:CCTV-1');
    expect(segments, [path]);
    final repaired = files.bytesOf(path)!;
    final check = TsCheck.of(repaired);
    expect([for (final pts in check.videoPts) (pts - live.base) ~/ 90].last, 14080);
    for (final MapEntry(key: pts, value: packets) in check.videoPesPackets.entries) {
      expect(packets, source.videoPesPackets[pts], reason: 'every video PES kept is whole');
    }
    expect(check.problems.where((p) => !p.startsWith('last PES of PID ${TsLivePids.audio}')), isEmpty);
    final result = await remuxRecording(files: files, input: path, output: '$path.mp4');
    expect(result.videoSamples, check.videoStarts.length);
  });

  test('a PAT on a frame boundary is cut there, as for HLS segments', () async {
    final files = MemoryRecordFiles();
    final path = layout.segment(1, extension: 'ts');
    // PAT and PMT at 14.2 s come right before the frame of 14.2 s.
    final at = live.indexAt(14200000);
    files.put('$path.part', crashed(14230000));
    await recoverSession(files, layout, room: 'iptv:CCTV-1');
    expect(files.bytesOf(path)!.length, (at - live.indexAt(11000000)) * 188);
    final result = await remuxRecording(files: files, input: path, output: '$path.mp4');
    expect(result.videoSamples, TsCheck.of(files.bytesOf(path)!).videoStarts.length);
  });
}
