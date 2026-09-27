import 'dart:typed_data';

import 'package:live_record/live_record.dart';
import 'package:live_record/src/remux/codec_config.dart';
import 'package:live_record/src/remux/mp4_writer.dart';
import 'package:live_record/src/remux/sample_table.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/flv_build.dart';
import '../support/mp4_reader.dart';

List<(int, int)> _runs(RunList list) => [for (var i = 0; i < list.length; i++) (list.counts[i], list.values[i])];

List<int> _list(U32Blocks blocks) => [for (var i = 0; i < blocks.length; i++) blocks[i]];

Future<Uint8List> _header(Mp4Header header) async {
  final files = MemoryRecordFiles();
  final sink = await files.create('/h.mp4');
  final out = Mp4Output(sink, bufferSize: 4096);
  await header.write(out);
  await out.flush();
  await sink.close();
  return files.bytesOf('/h.mp4')!;
}

void main() {
  group('U32Blocks and RunList', () {
    test('values survive block boundaries', () {
      final blocks = U32Blocks();
      for (var i = 0; i < 40000; i++) {
        blocks.add(i * 3);
      }
      expect(blocks.length, 40000);
      expect(blocks[16383], 16383 * 3);
      expect(blocks[16384], 16384 * 3);
      expect(blocks.last, 39999 * 3);
      blocks.last = 7;
      expect(blocks[39999], 7);
      expect(blocks.capacityBytes, 3 * 16384 * 4);
    });

    test('equal neighbours share a run; signed values keep their bits', () {
      final runs = RunList();
      [3, 3, 3, 5, 3, -2, -2].forEach(runs.add);
      expect(_runs(runs), [(3, 3), (1, 5), (1, 3), (2, 0xfffffffe)]);
    });
  });

  group('TrackTable', () {
    test('builds stts and ctts runs, sync samples and the last duration', () {
      final table = TrackTable(90000);
      // I P B B P B B: decode every 3000 ticks, presentation reordered.
      const offsets = [6000, 15000, 3000, 3000, 15000, 3000, 3000];
      for (var i = 0; i < offsets.length; i++) {
        table.add(dts: i * 3000, offset: offsets[i], size: 100 + i, sync: i == 0);
      }
      table
        ..add(dts: 21000, offset: 6000, size: 50, sync: true)
        ..finish(table.medianDuration(3000));
      expect(_runs(table.stts), [(8, 3000)]);
      expect(_runs(table.ctts), [(1, 6000), (1, 15000), (2, 3000), (1, 15000), (2, 3000), (1, 6000)]);
      expect(_list(table.syncSamples), [1, 8]);
      expect(table.hasCompositionOffsets, isTrue);
      expect(table.hasNegativeOffsets, isFalse);
      expect(table.duration, 24000);
      expect(table.firstOffset, 6000);
      expect(table.presentationEnd, 21000 + 6000 + 3000);
      expect(table.totalBytes, 100 + 101 + 102 + 103 + 104 + 105 + 106 + 50);
      expect(table.maxSampleSize, 106);
    });

    test('rejects decode times that do not increase and offsets out of range', () {
      final table = TrackTable(1000)..add(dts: 10, offset: 0, size: 1, sync: true);
      expect(() => table.add(dts: 10, offset: 0, size: 1, sync: true), throwsA(isA<RemuxException>()));
      expect(() => table.add(dts: 20, offset: 1 << 31, size: 1, sync: true), throwsA(isA<RemuxException>()));
    });

    test('chunks: stsc runs change only when the samples per chunk change', () {
      final table = TrackTable(1000);
      for (final (offset, samples) in [(0, 3), (500, 3), (900, 2), (1200, 2), (1500, 3)]) {
        table.addChunk(offset, samples);
      }
      expect(_list(table.chunkRunFirst), [1, 3, 5]);
      expect(_list(table.chunkRunSamples), [3, 2, 3]);
      expect(table.chunkedSamples, 13);
    });

    test('the last duration is the median of the recent ones', () {
      final table = TrackTable(90000);
      var dts = 0;
      for (final delta in [1440, 1530, 1530, 1440, 1530, 99999, 1530]) {
        table.add(dts: dts, offset: 0, size: 1, sync: true);
        dts += delta;
      }
      expect(table.medianDuration(3000), 1530);
      expect(TrackTable(1000).medianDuration(33), 33);
    });
  });

  group('VideoTimeline', () {
    test('converts to 90 kHz from the first timestamp and keeps presentation times', () {
      final timeline = VideoTimeline();
      expect(timeline.next(5000, 66), (dts: 0, offset: 66 * 90));
      expect(timeline.next(5033, 100), (dts: 33 * 90, offset: 100 * 90));
      // Duplicate timestamp: decode time moves by one tick, presentation stays.
      expect(timeline.next(5033, 0), (dts: 33 * 90 + 1, offset: -1));
      expect(timeline.next(5066, 0), (dts: 66 * 90, offset: 0));
      expect(timeline.firstMs, 5000);
    });

    test('small steps back are absorbed, large ones are errors', () {
      final timeline = VideoTimeline()
        ..next(0, 0)
        ..next(1000, 0);
      expect(timeline.next(990, 0).dts, 1000 * 90 + 1);
      expect(() => timeline.next(-500, 0), throwsA(isA<RemuxException>()));
    });
  });

  group('AudioTimeline', () {
    test('millisecond jitter keeps whole AAC frames', () {
      final timeline = AudioTimeline(sampleRate: 44100, frameSamples: 1024);
      final times = [for (var i = 0; i < 100; i++) timeline.next(1000 + (i * 1024 * 1000 / 44100).round())];
      expect(times, [for (var i = 0; i < 100; i++) i * 1024]);
    });

    test('a gap of a frame or more is kept; a step back past one second is an error', () {
      final timeline = AudioTimeline(sampleRate: 48000, frameSamples: 1024)
        ..next(0)
        ..next(21);
      expect(timeline.next(43), 2048);
      expect(timeline.next(200), 9600, reason: '157 ms gap');
      expect(timeline.next(221), 9600 + 1024);
      expect(() => timeline.next(-2000), throwsA(isA<RemuxException>()));
    });

    test('timestamps that squeeze frames shorten them but never repeat a time', () {
      final timeline = AudioTimeline(sampleRate: 48000, frameSamples: 1024)
        ..next(0)
        ..next(21);
      expect(timeline.next(10), 1025);
    });
  });

  group('ChunkPlanner', () {
    test('closes a track chunk after the window and interleaves tracks', () {
      final chunks = <(int, int, int)>[];
      final planner = ChunkPlanner(tracks: 2, windowMs: 100, onChunk: (t, s, b) => chunks.add((t, s, b)));
      for (var ms = 0; ms <= 300; ms += 20) {
        planner
          ..add(0, ms, 10)
          ..add(1, ms + 5, 1);
      }
      planner.finish();
      expect(chunks, [(0, 5, 50), (1, 5, 5), (0, 5, 50), (1, 5, 5), (0, 5, 50), (1, 5, 5), (0, 1, 10), (1, 1, 1)]);
    });

    test('a chunk never exceeds the byte limit; a large sample is alone', () {
      final chunks = <(int, int, int)>[];
      final planner = ChunkPlanner(tracks: 1, maxChunkBytes: 100, onChunk: (t, s, b) => chunks.add((t, s, b)))
        ..add(0, 0, 60)
        ..add(0, 1, 30)
        ..add(0, 2, 30)
        ..add(0, 3, 500)
        ..add(0, 4, 1)
        ..finish();
      expect(chunks, [(0, 2, 90), (0, 1, 30), (0, 1, 500), (0, 1, 1)]);
      expect(planner.pendingBytes, 0);
    });

    test('a stalled track is flushed once the other runs two windows ahead', () {
      final chunks = <(int, int, int)>[];
      final planner = ChunkPlanner(tracks: 2, windowMs: 100, onChunk: (t, s, b) => chunks.add((t, s, b)))
        ..add(1, 0, 1)
        ..add(0, 0, 10)
        ..add(0, 150, 10);
      expect(chunks, [(0, 1, 10)]);
      planner.add(0, 200, 10);
      expect(chunks, [(0, 1, 10), (1, 1, 1)]);
    });
  });

  test('sample tables of a six-hour 60 fps recording stay small', () {
    // 6 h of 60 fps video with FLV millisecond jitter (16/17/17 ms) and
    // B-frame offsets, and 48 kHz AAC: 1.3 M + 1.0 M samples.
    final video = TrackTable(VideoTimeline.timescale);
    final audio = TrackTable(48000);
    final videoTime = VideoTimeline();
    final audioTime = AudioTimeline(sampleRate: 48000, frameSamples: 1024);
    var payload = 0;
    final planner = ChunkPlanner(
      tracks: 2,
      onChunk: (track, samples, bytes) {
        (track == 0 ? video : audio).addChunk(payload, samples);
        payload += bytes;
      },
    );
    const frames = 6 * 3600 * 60;
    const audioFrames = 6 * 3600 * 48000 ~/ 1024;
    var a = 0;
    for (var i = 0; i < frames; i++) {
      final ms = i * 1000 ~/ 60;
      final time = videoTime.next(ms, const [34, 84, 50, 17, 67][i % 5]);
      video.add(dts: time.dts, offset: time.offset, size: 3500 + (i % 7), sync: i % 120 == 0);
      planner.add(0, ms, 3500 + (i % 7));
      while (a < audioFrames && a * 1024 * 1000 ~/ 48000 <= ms) {
        final audioMs = a * 1024 * 1000 ~/ 48000;
        audio.add(dts: audioTime.next(audioMs), offset: 0, size: 300, sync: true);
        planner.add(1, audioMs, 300);
        a++;
      }
    }
    planner.finish();
    video.finish(video.medianDuration(1500));
    audio.finish(1024);
    expect(video.sampleCount, frames);
    expect(audio.sampleCount, audioFrames);
    expect(audio.stts.length, lessThanOrEqualTo(2), reason: 'AAC frames are regular');
    expect(video.stts.length, lessThan(frames), reason: 'runs of equal deltas');
    expect(video.chunkOffsets.length, lessThan(frames ~/ 20), reason: 'half-second chunks');
    final memory = video.memoryBytes + audio.memoryBytes;
    expect(memory, lessThan(40 << 20), reason: 'about 4 bytes per sample plus runs: $memory');
    final header = Mp4Header(
      tracks: [
        Mp4Track(
          table: video,
          codec: Mp4VideoCodec(VideoConfig.parse(VideoCodec.avc, avcRecordOf(remuxFixture('avc_aac.flv')))),
          startMs: 0,
        ),
        Mp4Track(table: audio, codec: Mp4AacCodec(AacConfig.parse(hex('1190'))), startMs: 0),
      ],
      payloadBytes: payload,
    );
    expect(header.co64, isTrue, reason: '${payload >> 30} GiB of payload');
    expect(header.durationMs, closeTo(6 * 3600 * 1000, 1000));
  });

  test('co64 and a 64-bit mdat size are used only past 4 GiB', () async {
    Mp4Header build(int payload, {required int lastOffset}) {
      final table = TrackTable(48000)
        ..add(dts: 0, offset: 0, size: 10, sync: true)
        ..add(dts: 1024, offset: 0, size: 10, sync: true)
        ..addChunk(0, 1)
        ..addChunk(lastOffset, 1)
        ..finish(1024);
      return Mp4Header(
        tracks: [Mp4Track(table: table, codec: Mp4AacCodec(AacConfig.parse(hex('1190'))), startMs: 0)],
        payloadBytes: payload,
      );
    }

    final small = build(1000, lastOffset: 990);
    expect(small.co64, isFalse);
    final smallBytes = await _header(small);
    expect(smallBytes.length, small.payloadStart);
    final smallBoxes = parseBoxes(Uint8List.fromList([...smallBytes, ...Uint8List(1000)]));
    expect(smallBoxes.map((box) => box.type), ['ftyp', 'moov', 'mdat']);
    final smallTrack = readTrack(Uint8List.fromList([...smallBytes, ...Uint8List(1000)]), smallBoxes[1].find('trak')!);
    expect(smallTrack.offsets, [small.payloadStart, small.payloadStart + 990]);

    const big = 5 << 30;
    final large = build(big, lastOffset: big - 10);
    expect(large.co64, isTrue);
    final bytes = await _header(large);
    expect(bytes.length, large.payloadStart);
    // ftyp, moov, then a 16-byte mdat header with a 64-bit size.
    final moov = parseBoxes(bytes, 0, large.payloadStart - 16);
    expect(moov.map((box) => box.type), ['ftyp', 'moov']);
    final data = ByteData.sublistView(bytes);
    final mdat = large.payloadStart - 16;
    expect(data.getUint32(mdat), 1);
    expect(String.fromCharCodes(bytes, mdat + 4, mdat + 8), 'mdat');
    expect(data.getUint32(mdat + 8) * 0x100000000 + data.getUint32(mdat + 12), big + 16);
    final co64 = moov[1].find('trak/mdia/minf/stbl/co64')!;
    expect(data.getUint32(co64.offset + 12), 2);
    expect(
      data.getUint32(co64.offset + 24) * 0x100000000 + data.getUint32(co64.offset + 28),
      large.payloadStart + big - 10,
    );
    expect(moov[1].find('trak/mdia/minf/stbl/stco'), isNull);
  });
}
