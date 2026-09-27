// Fixtures (ffmpeg 9.0.2, testsrc 160×96 30 fps, 2 s):
//   remux/avc_aac.ts   -c:v libx264 -profile:v high -bf 2 -g 30 -c:a aac -ac 1 (44.1 kHz) -f mpegts
//   remux/hevc_aac.ts  -c:v libx265 (bframes=2, keyint=30) -c:a aac -ac 1 (48 kHz) -f mpegts
//   hls/ts/seg*.ts     ffmpeg -i avc_aac.ts -c copy -f hls -hls_time 1
//   hls/fmp4/*         ffmpeg -i avc_aac.ts -c copy -bsf:a aac_adtstoasc -f hls -hls_time 1 -hls_segment_type fmp4
//   *.ffmpeg.mp4       ffmpeg -i <input> -map 0 -c copy -f mp4 (the reference each remux is compared with;
//                      avc_aac.m4s is hls/fmp4/init.mp4 + seg0.m4s + seg1.m4s)
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/src/remux/ts_demux.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/mp4_reader.dart';
import '../support/ts_build.dart';

final _fixed = Clock.fixed(DateTime.utc(2026, 9, 28, 12));

Uint8List _fixture(String name) => File('test/fixtures/remux/$name').readAsBytesSync();

Future<(Uint8List, RemuxResult)> _remux(Uint8List input, {int blockSize = 4096, bool fmp4 = false}) async {
  final name = fmp4 ? '/in.m4s' : '/in.ts';
  final files = MemoryRecordFiles()..put(name, input);
  final result = await withClock(
    _fixed,
    () => fmp4
        ? remuxFmp4ToMp4(files: files, input: name, output: '/out.mp4')
        : remuxTsToMp4(files: files, input: name, output: '/out.mp4', blockSize: blockSize),
  );
  return (files.bytesOf('/out.mp4')!, result);
}

Future<RemuxException> _fails(Uint8List input) async {
  final files = MemoryRecordFiles()..put('/in.ts', input);
  try {
    await remuxTsToMp4(files: files, input: '/in.ts', output: '/out.mp4');
  } on RemuxException catch (error) {
    expect(await files.exists('/out.mp4'), isFalse, reason: 'no partial output is left behind');
    return error;
  }
  fail('expected a RemuxException');
}

/// Tracks of [mp4] by handler, after checking the faststart layout.
Map<String, TrackSamples> tracksOf(Uint8List mp4) {
  final boxes = parseBoxes(mp4);
  expect(boxes.map((box) => box.type), ['ftyp', 'moov', 'mdat'], reason: 'faststart: moov before mdat');
  return {for (final trak in boxes[1].all('trak')) readTrack(mp4, trak).handler: readTrack(mp4, trak)};
}

/// The NAL units of a sample with 4-byte lengths, without parameter sets
/// (they are in the sample entry: ffmpeg keeps repeats in the samples, the
/// recorder leaves identical ones out).
List<String> _nals(Uint8List sample, {required bool hevc}) {
  final out = <String>[];
  var at = 0;
  while (at + 4 <= sample.length) {
    final length = ByteData.sublistView(sample, at).getUint32(0);
    final nal = sample.sublist(at + 4, at + 4 + length);
    at += 4 + length;
    final type = hevc ? (nal[0] >> 1) & 0x3F : nal[0] & 0x1F;
    final parameterSet = hevc ? type >= 32 && type <= 34 : type == 7 || type == 8;
    if (!parameterSet) out.add(nal.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
  }
  expect(at, sample.length, reason: 'whole NAL units');
  return out;
}

/// Checks that [ours] holds the samples of ffmpeg's `-c copy` MP4 [reference]:
/// same payloads, same sync samples, same presentation times (relative to
/// the first sample of the track, in ms).
void sameAsReference(Uint8List ours, Uint8List reference, {required bool hevc}) {
  final a = tracksOf(ours);
  final moov = parseBoxes(reference).firstWhere((box) => box.type == 'moov');
  final ref = {for (final trak in moov.all('trak')) readTrack(reference, trak).handler: readTrack(reference, trak)};
  expect(a.keys.toSet(), ref.keys.toSet());
  for (final handler in a.keys) {
    final x = a[handler]!;
    final y = ref[handler]!;
    expect(x.sizes.length, y.sizes.length, reason: '$handler sample count');
    for (var i = 0; i < x.sizes.length; i++) {
      if (handler == 'vide') {
        expect(
          _nals(x.sample(ours, i), hevc: hevc),
          _nals(y.sample(reference, i), hevc: hevc),
          reason: 'video $i',
        );
      } else {
        expect(x.sample(ours, i), y.sample(reference, i), reason: 'audio $i');
      }
    }
    expect(x.syncSamples ?? const <int>[], y.syncSamples ?? const <int>[], reason: '$handler sync samples');
    double pts(TrackSamples t, int i) => (t.decodeTimes[i] + t.compositionOffsets[i]) * 1000 / t.timescale;
    for (var i = 0; i < x.sizes.length; i++) {
      expect(pts(x, i) - pts(x, 0), closeTo(pts(y, i) - pts(y, 0), 0.5), reason: '$handler presentation time $i');
    }
    for (var i = 1; i < x.decodeTimes.length; i++) {
      expect(x.decodeTimes[i], greaterThan(x.decodeTimes[i - 1]), reason: 'decode times increase');
    }
  }
}

void main() {
  group('fixtures (x264/x265 + AAC in MPEG-TS from ffmpeg testsrc)', () {
    test('H.264: the samples of ffmpeg -c copy, one timeline, avc1 + avcC', () async {
      final (mp4, result) = await _remux(_fixture('avc_aac.ts'));
      sameAsReference(mp4, _fixture('avc_aac.ts.ffmpeg.mp4'), hevc: false);
      expect((result.videoSamples, result.audioSamples, result.keyframes), (60, 88, 2));
      expect(result.videoCodec, VideoCodec.avc);
      expect(result.audioSampleRate, 44100);
      final moov = parseBoxes(mp4)[1];
      expect(moov.find('trak/mdia/minf/stbl/stsd/avc1/avcC'), isNotNull);
      expect(tracksOf(mp4)['vide']!.timescale, 90000);
    });

    test('H.265: hvc1 + hvcC with VPS, SPS and PPS; parameter sets leave the samples', () async {
      final (mp4, result) = await _remux(_fixture('hevc_aac.ts'));
      sameAsReference(mp4, _fixture('hevc_aac.ts.ffmpeg.mp4'), hevc: true);
      expect(result.videoCodec, VideoCodec.hevc);
      expect(result.audioSampleRate, 48000);
      final moov = parseBoxes(mp4)[1];
      final hvcc = moov.find('trak/mdia/minf/stbl/stsd/hvc1/hvcC')!;
      expect(mp4[hvcc.offset + 8 + 22], 3, reason: 'VPS, SPS and PPS arrays');
    });

    test('the output does not depend on the read block size', () async {
      final (a, _) = await _remux(_fixture('avc_aac.ts'), blockSize: 188);
      final (b, _) = await _remux(_fixture('avc_aac.ts'), blockSize: 1 << 20);
      expect(a, b);
    });

    test('HLS segments written one after the other remux like the whole stream', () async {
      final seg0 = File('test/fixtures/hls/ts/seg0.ts').readAsBytesSync();
      final seg1 = File('test/fixtures/hls/ts/seg1.ts').readAsBytesSync();
      final (mp4, result) = await _remux(Uint8List.fromList([...seg0, ...seg1]));
      expect((result.videoSamples, result.audioSamples), (60, 88));
      final (whole, _) = await _remux(_fixture('avc_aac.ts'));
      final a = tracksOf(mp4);
      final b = tracksOf(whole);
      for (final handler in ['vide', 'soun']) {
        expect(a[handler]!.sizes, b[handler]!.sizes);
        expect(a[handler]!.decodeTimes, b[handler]!.decodeTimes);
      }
    });
  });

  test('ffprobe reads the MP4s and ffmpeg decodes them without an error (skipped without ffmpeg)', () async {
    final dir = Directory.systemTemp.createTempSync('ts_remux');
    try {
      for (final (name, fmp4) in [('avc_aac.ts', false), ('hevc_aac.ts', false)]) {
        final (mp4, _) = await _remux(_fixture(name), fmp4: fmp4);
        final path = '${dir.path}/$name.mp4';
        File(path).writeAsBytesSync(mp4);
        final ProcessResult probe;
        try {
          probe = await Process.run('ffprobe', [
            '-v',
            'error',
            '-show_entries',
            'stream=codec_name',
            '-of',
            'csv=p=0',
            path,
          ]);
        } on ProcessException {
          markTestSkipped('ffprobe is not installed');
          return;
        }
        expect(probe.stderr, isEmpty);
        expect((probe.stdout as String).trim().split('\n').toSet(), hasLength(2), reason: 'video and audio');
        final decode = await Process.run('ffmpeg', ['-v', 'error', '-i', path, '-f', 'null', '-']);
        expect(decode.stderr, isEmpty, reason: name);
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  group('timeline', () {
    test('a discontinuity (timestamps restart) continues the file time after what was written', () async {
      final seg0 = File('test/fixtures/hls/ts/seg0.ts').readAsBytesSync();
      // The same second twice, as after an HLS discontinuity (an ad, a restarted encoder).
      final (mp4, result) = await _remux(Uint8List.fromList([...seg0, ...seg0]));
      final tracks = tracksOf(mp4);
      final video = tracks['vide']!;
      expect(result.videoSamples, 60);
      final steps = [for (var i = 1; i < video.sizes.length; i++) video.decodeTimes[i] - video.decodeTimes[i - 1]];
      expect(steps.every((step) => step > 0 && step <= 3000), isTrue, reason: 'one frame at most across the join');
      final audio = tracks['soun']!;
      final end = audio.decodeTimes.last / audio.timescale;
      expect(end, closeTo(video.decodeTimes.last / 90000, 0.1), reason: 'audio joins the same timeline');
    });

    test('a hole of a few seconds stays in the file time (like FLV, §6.3)', () async {
      final ts = buildTs([
        for (var i = 0; i < 30; i++) TsUnit.video(pts: 900000 + i * 3000, key: i == 0),
        for (var i = 0; i < 30; i++) TsUnit.video(pts: 900000 + (i + 130) * 3000, key: i == 0),
      ]);
      final (mp4, _) = await _remux(ts);
      final video = tracksOf(mp4)['vide']!;
      final steps = [for (var i = 1; i < video.sizes.length; i++) video.decodeTimes[i] - video.decodeTimes[i - 1]];
      expect(steps.where((step) => step > 3000), [3000 * 101], reason: 'the 100 missing frames');
    });

    test('33-bit timestamp wrap is followed', () async {
      const wrap = 1 << 33;
      final ts = buildTs([
        for (var i = 0; i < 60; i++) TsUnit.video(pts: (wrap - 30 * 3000 + i * 3000) % wrap, key: i % 30 == 0),
      ]);
      final (mp4, _) = await _remux(ts);
      final video = tracksOf(mp4)['vide']!;
      expect(video.sizes, hasLength(60));
      expect(video.decodeTimes[59] - video.decodeTimes[0], 59 * 3000);
    });

    test('units before the first keyframe are dropped and counted', () async {
      final ts = buildTs([for (var i = 0; i < 20; i++) TsUnit.video(pts: 9000 + i * 3000, key: i == 5 || i == 15)]);
      final (mp4, result) = await _remux(ts);
      expect(result.videoSamples, 15);
      expect(result.droppedTags, 5);
      expect(tracksOf(mp4)['vide']!.syncSamples, [1, 11]);
    });
  });

  group('damage and unsupported input', () {
    test('a lost packet inside a unit fails the remux (REG-RECORD-008)', () async {
      final ts = buildTs([for (var i = 0; i < 10; i++) TsUnit.video(pts: 9000 + i * 3000, key: i == 0, size: 600)]);
      // Drop the second packet of the first video PES (continuity breaks mid-unit).
      final videoPackets = [
        for (var at = 0; at < ts.length; at += 188)
          if (((ts[at + 1] & 0x1F) << 8 | ts[at + 2]) == TsBuild.videoPid) at,
      ];
      final cut = Uint8List.fromList([...ts.sublist(0, videoPackets[1]), ...ts.sublist(videoPackets[1] + 188)]);
      expect((await _fails(cut)).message, contains('packets lost'));
    });

    test('a PES longer than declared fails', () async {
      final ts = buildTs([TsUnit.audio(pts: 9000, declaredExtra: -3), TsUnit.audio(pts: 9000 + 1920)]);
      expect((await _fails(ts)).message, contains('declared'));
    });

    test('lost sync fails', () async {
      final ts = buildTs([for (var i = 0; i < 5; i++) TsUnit.video(pts: 9000 + i * 3000, key: i == 0)]);
      ts[188 * 3] = 0x00;
      expect((await _fails(ts)).message, contains('sync'));
    });

    test('a truncated last packet fails', () async {
      final ts = buildTs([for (var i = 0; i < 5; i++) TsUnit.video(pts: 9000 + i * 3000, key: i == 0)]);
      expect((await _fails(Uint8List.sublistView(ts, 0, ts.length - 7))).message, contains('truncated'));
    });

    test('a video configuration change inside a file fails', () async {
      final ts = buildTs([
        for (var i = 0; i < 5; i++) TsUnit.video(pts: 9000 + i * 3000, key: i == 0),
        TsUnit.video(pts: 9000 + 5 * 3000, key: true, sps: TsBuild.otherSps),
      ]);
      expect((await _fails(ts)).message, contains('configuration changes'));
    });

    test('MP3 audio without AAC is not supported', () async {
      final ts = buildTs([TsUnit.video(pts: 9000, key: true)], audioType: 0x03);
      expect((await _fails(ts)).message, contains('stream type 0x3'));
    });

    test('not MPEG-TS at all', () async {
      expect((await _fails(Uint8List.fromList(List.filled(400, 1)))).message, contains('sync'));
    });
  });

  test('an incomplete audio PES at the very end (a file cut by a crash) is dropped, not an error', () async {
    final ts = buildTs([
      TsUnit.video(pts: 9000, key: true),
      TsUnit.audio(pts: 9000),
      TsUnit.audio(pts: 9000 + 1920, size: 700),
    ]);
    final cut = Uint8List.sublistView(ts, 0, ts.length - 188);
    final (_, result) = await _remux(Uint8List.fromList(cut));
    expect(result.audioSamples, 1);
  });

  test('HLS segments that restart their continuity counters are not duplicate packets (SOOP)', () async {
    // Each segment starts every PID at counter 0; the audio PID of the first
    // one ended at 0 too. Only a packet repeated byte for byte is a duplicate.
    final first = buildTs([TsUnit.video(pts: 9000, key: true), TsUnit.audio(pts: 9000)]);
    final second = buildTs([TsUnit.video(pts: 9000 + 3000), TsUnit.audio(pts: 9000 + 1920)]);
    final (_, result) = await _remux(Uint8List.fromList([...first, ...second]));
    expect((result.videoSamples, result.audioSamples), (2, 2));
    final duplicated = Uint8List.fromList([
      ...first.sublist(0, first.length - 188),
      ...first.sublist(first.length - 188),
      ...first.sublist(first.length - 188),
    ]);
    final (_, again) = await _remux(duplicated);
    expect(again.audioSamples, 1, reason: 'a repeated packet is dropped');
  });

  test('an access unit whose tail starts the next PES is joined again (Twitch / Amazon IVS)', () async {
    List<TsUnit> units({required bool split}) => [
      for (var i = 0; i < 6; i++)
        TsUnit.video(pts: 9000 + i * 3000, key: i == 0, size: 400, tail: split && i < 5 ? 90 : 0),
    ];
    final (whole, _) = await _remux(buildTs(units(split: false)));
    final (split, result) = await _remux(buildTs(units(split: true)));
    expect(result.videoSamples, 6);
    final a = tracksOf(whole)['vide']!;
    final b = tracksOf(split)['vide']!;
    expect(b.sizes, a.sizes);
    for (var i = 0; i < a.sizes.length; i++) {
      expect(b.sample(split, i), a.sample(whole, i), reason: 'sample $i');
    }
  });

  test('the demuxer splits ADTS frames and carries one across PES packets', () {
    final ts = buildTs([TsUnit.audio(pts: 9000, frames: 3, splitLast: true), TsUnit.audio(pts: 9000 + 3 * 1920)]);
    final demuxer = TsDemuxer();
    final units = <TsSample>[];
    for (var at = 0; at < ts.length; at += 188) {
      demuxer.add(Uint8List.sublistView(ts, at, at + 188), at, units.add);
    }
    demuxer.finish(units.add);
    expect([for (final unit in units) unit.pts], [9000, 9000 + 1920, 9000 + 3840, 9000 + 5760]);
  });

  test('a frame split across PES and cut by a gap or the file start is dropped, not joined (§8.2)', () {
    List<int> run(Uint8List ts, TsDemuxer demuxer) {
      final units = <TsSample>[];
      for (var at = 0; at < ts.length; at += 188) {
        demuxer.add(Uint8List.sublistView(ts, at, at + 188), at, units.add);
      }
      demuxer.finish(units.add);
      return [for (final unit in units) unit.pts];
    }

    /// [ts] without the packets of its audio PES number [from] up to [to].
    Uint8List without(Uint8List ts, int from, int to) {
      final starts = [
        for (var at = 0; at < ts.length; at += 188)
          if (((ts[at + 1] & 0x1F) << 8 | ts[at + 2]) == TsBuild.audioPid && (ts[at + 1] & 0x40) != 0) at,
      ];
      return Uint8List.fromList([...ts.sublist(0, starts[from]), ...ts.sublist(starts[to])]);
    }

    // A reconnection lost the PES that held the end of A's last frame; C
    // starts with the rest of B's last frame.
    final gap = buildTs([
      TsUnit.audio(pts: 9000, frames: 3, splitLast: true),
      TsUnit.audio(pts: 9000 + 3 * 1920, frames: 2, splitLast: true),
      TsUnit.audio(pts: 909000, frames: 2),
    ]);
    final strict = TsDemuxer();
    expect(run(without(gap, 1, 2), strict), [9000, 9000 + 1920, 909000, 909000 + 1920]);
    expect(strict.damaged, 2, reason: 'the carried half frame and the rest in front of C');
    // A file that starts inside a split frame (a continuous recording split at a keyframe).
    final start = TsDemuxer();
    expect(run(without(gap, 0, 1), start), [9000 + 3 * 1920, 909000, 909000 + 1920]);
    expect(start.damaged, 3, reason: 'the rest of A in front of B, then the gap before C as above');
  });

  test('Mp4Remuxer picks the format by content (FLV, MPEG-TS, fragmented MP4)', () async {
    final files = MemoryRecordFiles()
      ..put('/a.flv', _fixture('avc_aac.flv'))
      ..put('/b.ts', _fixture('avc_aac.ts'))
      ..put('/c.m4s', [
        ...File('test/fixtures/hls/fmp4/init.mp4').readAsBytesSync(),
        ...File('test/fixtures/hls/fmp4/seg0.m4s').readAsBytesSync(),
      ]);
    for (final name in ['/a.flv', '/b.ts', '/c.m4s']) {
      final result = await remuxRecording(files: files, input: name, output: '$name.mp4');
      expect(result.videoSamples, greaterThan(0), reason: name);
    }
    files.put('/d.bin', List.filled(100, 7));
    await expectLater(remuxRecording(files: files, input: '/d.bin', output: '/d.mp4'), throwsA(isA<RemuxException>()));
  });
}
