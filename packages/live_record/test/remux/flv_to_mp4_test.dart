import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/flv_build.dart';
import '../support/mp4_reader.dart';

/// A media sample as the FLV tag holds it.
typedef _Sample = ({bool video, int ts, int cts, bool key, Uint8List data});

/// The media samples of an FLV with length-prefixed video, read straight from the tags.
List<_Sample> _flvSamples(Uint8List flv) {
  final samples = <_Sample>[];
  for (final tag in flvPackets(flv).skip(1)) {
    final data = tagData(tag);
    final ts = FlvTag.timestamp(tag);
    if (FlvTag.type(tag) == FlvTag.audio) {
      if (data[1] == 1) samples.add((video: false, ts: ts, cts: 0, key: true, data: data.sublist(2)));
    } else if (FlvTag.type(tag) == FlvTag.video) {
      final first = data[0];
      final key = (first >> 4) & 0x07 == 1;
      int cts(int at) {
        final value = (data[at] << 16) | (data[at + 1] << 8) | data[at + 2];
        return value >= 0x800000 ? value - 0x1000000 : value;
      }

      if (first & 0x80 != 0) {
        if (first & 0x0f == 1) samples.add((video: true, ts: ts, cts: cts(5), key: key, data: data.sublist(8)));
        if (first & 0x0f == 3) samples.add((video: true, ts: ts, cts: 0, key: key, data: data.sublist(5)));
      } else if (data[1] == 1) {
        samples.add((video: true, ts: ts, cts: cts(2), key: key, data: data.sublist(5)));
      }
    }
  }
  return samples;
}

final _fixed = Clock.fixed(DateTime.utc(2026, 9, 28, 12));

Future<(Uint8List, FlvRemuxResult)> _remux(
  Uint8List flv, {
  int blockSize = 4096,
  bool Function()? isCancelled,
  void Function(int)? onProgress,
}) async {
  final files = MemoryRecordFiles()..put('/in.flv', flv);
  final result = await withClock(
    _fixed,
    () => remuxFlvToMp4(
      files: files,
      input: '/in.flv',
      output: '/out.mp4',
      blockSize: blockSize,
      isCancelled: isCancelled,
      onProgress: onProgress,
    ),
  );
  return (files.bytesOf('/out.mp4')!, result);
}

Future<RemuxException> _fails(Uint8List flv) async {
  final files = MemoryRecordFiles()..put('/in.flv', flv);
  try {
    await remuxFlvToMp4(files: files, input: '/in.flv', output: '/out.mp4');
  } on RemuxException catch (error) {
    expect(await files.exists('/out.mp4'), isFalse, reason: 'no partial output is left behind');
    return error;
  }
  fail('expected a RemuxException');
}

/// Parses [mp4], checks the layout and returns its tracks by handler.
Map<String, TrackSamples> _tracks(Uint8List mp4) {
  final boxes = parseBoxes(mp4);
  expect(boxes.map((box) => box.type), ['ftyp', 'moov', 'mdat'], reason: 'faststart: moov before mdat');
  final mdat = boxes[2];
  final tracks = <String, TrackSamples>{};
  for (final trak in boxes[1].all('trak')) {
    final track = readTrack(mp4, trak);
    expect(track.sampleOffsets, hasLength(track.sizes.length));
    for (var i = 0; i < track.sizes.length; i++) {
      expect(track.sampleOffsets[i], greaterThanOrEqualTo(mdat.offset + mdat.headerSize));
      expect(track.sampleOffsets[i] + track.sizes[i], lessThanOrEqualTo(mdat.offset + mdat.size));
    }
    for (var i = 1; i < track.decodeTimes.length; i++) {
      expect(track.decodeTimes[i], greaterThan(track.decodeTimes[i - 1]), reason: 'decode times increase');
    }
    tracks[track.handler] = track;
  }
  return tracks;
}

/// Checks that [mp4] holds exactly the samples of [flv], in order, with their
/// timing: video presentation times exact, audio within a millisecond.
void _sameSamples(Uint8List flv, Uint8List mp4, {List<_Sample>? expected}) {
  final samples = expected ?? _flvSamples(flv);
  final tracks = _tracks(mp4);
  for (final video in [true, false]) {
    final wanted = samples.where((sample) => sample.video == video).toList();
    final track = tracks[video ? 'vide' : 'soun'];
    if (wanted.isEmpty) {
      expect(track, isNull);
      continue;
    }
    expect(track!.sizes, hasLength(wanted.length));
    final first = wanted.first.ts;
    for (var i = 0; i < wanted.length; i++) {
      expect(track.sample(mp4, i), wanted[i].data, reason: '${video ? 'video' : 'audio'} sample $i');
      if (video) {
        final pts = track.decodeTimes[i] + track.compositionOffsets[i];
        expect(pts, (wanted[i].ts - first + wanted[i].cts) * 90, reason: 'video presentation time $i');
      } else {
        final ms = track.decodeTimes[i] * 1000 / track.timescale;
        expect(ms, closeTo(wanted[i].ts - first, 1), reason: 'audio time $i');
      }
    }
    if (video) {
      final keys = [
        for (var i = 0; i < wanted.length; i++)
          if (wanted[i].key) i + 1,
      ];
      expect(track.syncSamples ?? [for (var i = 1; i <= wanted.length; i++) i], keys);
    }
  }
}

List<String> _brands(Uint8List mp4) {
  final ftyp = parseBoxes(mp4).first;
  return [for (var at = ftyp.offset + 16; at < ftyp.offset + ftyp.size; at += 4) String.fromCharCodes(mp4, at, at + 4)];
}

Uint8List _body(Uint8List mp4, Box box) =>
    Uint8List.sublistView(mp4, box.offset + box.headerSize, box.offset + box.size);

/// [record] (an avcC with one SPS) with the last byte of its first PPS changed.
Uint8List _otherPps(Uint8List record) {
  final spsLength = (record[6] << 8) | record[7];
  final ppsAt = 8 + spsLength + 1;
  final ppsLength = (record[ppsAt] << 8) | record[ppsAt + 1];
  return Uint8List.fromList(record)..[ppsAt + 2 + ppsLength - 1] ^= 1;
}

/// [flv] without the tags [drop] matches.
Uint8List _filtered(Uint8List flv, bool Function(Uint8List tag) drop) => flvFile([
  for (final packet in flvPackets(flv))
    if (packet.length == 13 || !drop(packet)) packet,
]);

/// The HEVC fixture as a Chinese-CDN legacy FLV: codec id 12 and, with [annexB], start codes.
Uint8List _legacyHevc(Uint8List flv, {required bool annexB}) {
  final out = <Uint8List>[];
  for (final packet in flvPackets(flv)) {
    if (packet.length == 13 || FlvTag.type(packet) != FlvTag.video) {
      out.add(packet);
      continue;
    }
    final data = tagData(packet);
    final frameType = (data[0] >> 4) & 0x07;
    final packetType = data[0] & 0x0f;
    final ts = FlvTag.timestamp(packet);
    final List<int> payload;
    switch (packetType) {
      case 0:
        final record = data.sublist(5);
        if (annexB) {
          // hvcC arrays → start codes.
          final units = <int>[];
          var at = 23;
          for (var a = 0; a < record[22]; a++) {
            final count = (record[at + 1] << 8) | record[at + 2];
            at += 3;
            for (var i = 0; i < count; i++) {
              final length = (record[at] << 8) | record[at + 1];
              units.addAll([0, 0, 0, 1, ...record.sublist(at + 2, at + 2 + length)]);
              at += 2 + length;
            }
          }
          payload = units;
        } else {
          payload = record;
        }
        out.add(videoTag(ts, payload, packetType: 0, key: true, codec: 12));
      case 1 || 3:
        final cts = packetType == 1 ? (data[5] << 16) | (data[6] << 8) | data[7] : 0;
        final nal = data.sublist(packetType == 1 ? 8 : 5);
        out.add(videoTag(ts, annexB ? annexBOf(nal) : nal, key: frameType == 1, cts: cts, codec: 12));
      default:
        break;
    }
  }
  return flvFile(out);
}

void main() {
  final avc = remuxFixture('avc_aac.flv');
  final hevc = remuxFixture('hevc_aac.flv');

  group('fixtures (x264/x265 + AAC from ffmpeg testsrc)', () {
    for (final (name, flv, golden) in [('AVC', avc, 'avc_aac.mp4'), ('HEVC', hevc, 'hevc_aac.mp4')]) {
      test('$name: golden bytes', () async {
        final (mp4, _) = await _remux(flv);
        final file = File('test/fixtures/remux/$golden');
        if (Platform.environment['UPDATE_GOLDEN'] == '1') file.writeAsBytesSync(mp4);
        expect(mp4, file.readAsBytesSync());
      });
    }

    test('AVC: samples, timing, sync samples and boxes', () async {
      final (mp4, result) = await _remux(avc);
      _sameSamples(avc, mp4);
      expect(_brands(mp4), ['isom', 'iso2', 'avc1', 'mp41']);
      expect((result.videoSamples, result.audioSamples, result.keyframes), (60, 88, 2));
      expect(result.videoCodec, VideoCodec.avc);
      expect(result.audioSampleRate, 44100);
      final moov = parseBoxes(mp4)[1];
      final traks = moov.all('trak');
      expect(traks, hasLength(2));
      final video = traks.first;
      expect(video.find('mdia/minf/stbl/stsd/avc1/avcC'), isNotNull);
      expect(_body(mp4, video.find('mdia/minf/stbl/stsd/avc1/avcC')!), avcRecordOf(avc));
      expect(video.find('mdia/minf/vmhd'), isNotNull);
      final videoTrack = readTrack(mp4, video);
      expect(videoTrack.timescale, 90000);
      expect(videoTrack.cttsVersion, 0);
      // Audio starts at 44 ms, video is presented from 67 ms: the movie starts
      // with the audio and the video waits 23 ms (an empty edit).
      expect(videoTrack.edits, hasLength(2));
      expect(videoTrack.edits.first, (23, -1));
      expect(videoTrack.edits.last.$2, 67 * 90);
      final audio = readTrack(mp4, traks.last);
      expect(audio.entry, 'mp4a');
      expect(audio.timescale, 44100);
      expect(audio.edits, isEmpty);
      expect(audio.decodeTimes.toSet().length, audio.decodeTimes.length);
      final esds = traks.last.find('mdia/minf/stbl/stsd/mp4a/esds')!;
      final body = _body(mp4, esds);
      expect(body.sublist(body.length - 11, body.length - 6), hex('121056e500'), reason: 'AudioSpecificConfig');
      expect(traks.last.find('mdia/minf/smhd'), isNotNull);
    });

    test('HEVC: Enhanced FLV hvc1 with CodedFramesX and command frames', () async {
      final (mp4, result) = await _remux(hevc);
      _sameSamples(hevc, mp4);
      expect(_brands(mp4), ['isom', 'iso2', 'hvc1', 'mp41']);
      expect(result.videoCodec, VideoCodec.hevc);
      final video = parseBoxes(mp4)[1].all('trak').first;
      expect(video.find('mdia/minf/stbl/stsd/hvc1/hvcC'), isNotNull);
    });

    test('the output does not depend on the read block size', () async {
      final (a, _) = await _remux(avc, blockSize: 7);
      final (b, _) = await _remux(avc, blockSize: 1 << 20);
      expect(a, b);
    });

    test('progress counts both passes and ends at the input size', () async {
      final values = <int>[];
      await _remux(hevc, onProgress: values.add);
      expect(values.last, hevc.length);
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i - 1]));
      }
      expect(values.where((value) => value <= hevc.length ~/ 2), isNotEmpty, reason: 'first pass reports half');
    });
  });

  group('stream variants', () {
    test('audio only', () async {
      final flv = _filtered(avc, (tag) => FlvTag.type(tag) == FlvTag.video);
      final (mp4, result) = await _remux(flv);
      _sameSamples(flv, mp4);
      expect(result.videoSamples, 0);
      expect(result.videoCodec, isNull);
      expect(_brands(mp4), ['isom', 'iso2', 'mp41']);
      final tracks = _tracks(mp4);
      expect(tracks.keys, ['soun']);
      expect(tracks['soun']!.edits, isEmpty);
    });

    test('video only', () async {
      final flv = _filtered(hevc, (tag) => FlvTag.type(tag) == FlvTag.audio);
      final (mp4, result) = await _remux(flv);
      _sameSamples(flv, mp4);
      expect(result.audioSamples, 0);
      expect(_tracks(mp4).keys, ['vide']);
    });

    test('legacy codec 12 HEVC with an hvcC gives the same file as Enhanced FLV', () async {
      final (enhanced, _) = await _remux(hevc);
      final (legacy, _) = await _remux(_legacyHevc(hevc, annexB: false));
      final a = _tracks(enhanced)['vide']!;
      final b = _tracks(legacy)['vide']!;
      expect(b.sizes, a.sizes);
      for (var i = 0; i < a.sizes.length; i++) {
        expect(b.sample(legacy, i), a.sample(enhanced, i));
      }
      expect(b.compositionOffsets, a.compositionOffsets);
    });

    test('legacy codec 12 HEVC in Annex B (Huya) becomes hvcC and length-prefixed samples', () async {
      final (enhanced, _) = await _remux(hevc);
      final (legacy, result) = await _remux(_legacyHevc(hevc, annexB: true));
      expect(result.videoCodec, VideoCodec.hevc);
      final a = _tracks(enhanced)['vide']!;
      final b = _tracks(legacy)['vide']!;
      expect(b.sizes, a.sizes, reason: 'start codes became 4-byte lengths');
      for (var i = 0; i < a.sizes.length; i++) {
        expect(b.sample(legacy, i), a.sample(enhanced, i));
      }
      final moov = parseBoxes(legacy)[1];
      final hvcc = _body(legacy, moov.find('trak/mdia/minf/stbl/stsd/hvc1/hvcC')!);
      expect(hvcc[21] & 3, 3);
      expect(hvcc[22], 3, reason: 'VPS, SPS and PPS arrays');
    });

    test('Annex B AVC becomes avcC and length-prefixed samples', () async {
      final packets = flvPackets(avc);
      final record = avcRecordOf(avc);
      final sps = record.sublist(8, 8 + ((record[6] << 8) | record[7]));
      final ppsAt = 8 + sps.length + 1;
      final pps = record.sublist(ppsAt + 2, ppsAt + 2 + ((record[ppsAt] << 8) | record[ppsAt + 1]));
      final converted = flvFile([
        for (final packet in packets)
          if (packet.length == 13 || FlvTag.type(packet) != FlvTag.video)
            packet
          else if (FlvTag.isVideoConfig(packet))
            videoTag(0, [0, 0, 0, 1, ...sps, 0, 0, 1, ...pps], packetType: 0, key: true)
          else if (tagData(packet)[1] == 1)
            FlvTag.build(
              type: FlvTag.video,
              timestamp: FlvTag.timestamp(packet),
              data: [...tagData(packet).sublist(0, 5), ...annexBOf(tagData(packet).sublist(5))],
            ),
      ]);
      final (mp4, _) = await _remux(converted);
      _sameSamples(avc, mp4);
      final avcc = _body(mp4, parseBoxes(mp4)[1].find('trak/mdia/minf/stbl/stsd/avc1/avcC')!);
      expect(avcc.sublist(0, 8 + sps.length), record.sublist(0, 8 + sps.length));
    });

    test('ADTS-wrapped AAC is unwrapped, with or without an AudioSpecificConfig tag', () async {
      for (final keepConfig in [true, false]) {
        final packets = <Uint8List>[];
        for (final packet in flvPackets(avc)) {
          if (packet.length == 13 || FlvTag.type(packet) != FlvTag.audio) {
            packets.add(packet);
          } else if (tagData(packet)[1] == 0) {
            if (keepConfig) packets.add(packet);
          } else {
            final frame = tagData(packet).sublist(2);
            packets.add(aacTag(FlvTag.timestamp(packet), [...adtsHeader(frame.length), ...frame]));
          }
        }
        final flv = flvFile(packets);
        final (mp4, result) = await _remux(flv);
        _sameSamples(avc, mp4);
        expect(result.audioSampleRate, 44100);
      }
    });

    test('a repeated identical sequence header is accepted', () async {
      final packets = flvPackets(avc);
      final config = packets.firstWhere(FlvTag.isVideoConfig);
      final audioConfig = packets.firstWhere(FlvTag.isAudioConfig);
      final flv = flvFile([
        ...packets.take(packets.length - 5),
        config,
        audioConfig,
        ...packets.skip(packets.length - 5),
      ]);
      final (mp4, _) = await _remux(flv);
      _sameSamples(avc, mp4);
    });
  });

  group('timestamps', () {
    final record = avcRecordOf(avc);
    final key = nals([
      [0x65, 0x88, 0x84, 0x21],
    ]);
    final frame = nals([
      [0x41, 0x9a, 0x21],
    ]);

    test('duplicate and negative composition times keep presentation times (ctts version 1)', () async {
      final flv = flvFile([
        FlvTag.fileHeader(audio: false),
        videoTag(1000, record, packetType: 0, key: true),
        videoTag(1000, key, key: true, cts: 40),
        videoTag(1040, frame, cts: 120),
        videoTag(1040, frame, cts: -40),
        videoTag(1080, frame),
        videoTag(1120, frame, cts: 40),
      ]);
      final (mp4, _) = await _remux(flv);
      final track = _tracks(mp4)['vide']!;
      expect(track.cttsVersion, 1);
      expect(track.decodeTimes.take(5), [0, 3600, 3601, 7200, 10800]);
      expect(
        [for (var i = 0; i < 5; i++) track.decodeTimes[i] + track.compositionOffsets[i]],
        [3600, 14400, 0, 7200, 14400],
      );
      expect(track.decodeTimes.last - track.decodeTimes[4], 3600, reason: 'last duration: the median');
      expect(track.syncSamples, [1]);
    });

    test('a timestamp going back more than a second is an error', () async {
      final error = await _fails(
        flvFile([
          FlvTag.fileHeader(audio: false),
          videoTag(0, record, packetType: 0, key: true),
          videoTag(5000, key, key: true),
          videoTag(3000, frame),
        ]),
      );
      expect(error.message, contains('go back'));
    });

    test('a stream not starting at 0 is moved to 0 (movie time of the earliest sample)', () async {
      final flv = flvFile([
        FlvTag.fileHeader(),
        videoTag(900000, record, packetType: 0, key: true),
        aacTag(900000, hex('1210'), packetType: 0),
        aacTag(900010, [1, 2, 3]),
        videoTag(900020, key, key: true),
        aacTag(900033, [4, 5, 6]),
        videoTag(900053, frame),
      ]);
      final (mp4, result) = await _remux(flv);
      final tracks = _tracks(mp4);
      expect(tracks['soun']!.edits, isEmpty);
      expect(tracks['vide']!.edits, [(10, -1), (66, 0)]);
      expect(result.duration.inMilliseconds, lessThan(100));
    });
  });

  group('malformed or unsupported input throws RemuxException', () {
    final record = avcRecordOf(avc);
    final key = nals([
      [0x65, 0x88],
    ]);

    Uint8List stream(List<Uint8List> tags) => flvFile([FlvTag.fileHeader(), ...tags]);

    final cases = <String, (Uint8List, String)>{
      'not an FLV': (Uint8List.fromList(List.generate(64, (i) => i)), 'Not an FLV'),
      'an empty file': (Uint8List(0), 'not an FLV'),
      'a header without tags': (FlvTag.fileHeader(), 'no audio or video'),
      'only metadata': (
        stream([
          FlvTag.build(type: FlvTag.script, timestamp: 0, data: [2, 0, 1, 0x61]),
        ]),
        'no audio',
      ),
      'a truncated last tag': (Uint8List.sublistView(avc, 0, avc.length - 10), 'truncated'),
      'a bad tag type': (
        stream([
          FlvTag.build(type: 7, timestamp: 0, data: [1, 2]),
        ]),
        'tag type',
      ),
      'an encrypted tag': (
        stream([
          FlvTag.build(type: 0x20 | FlvTag.audio, timestamp: 0, data: [0xaf, 1]),
        ]),
        'encrypted',
      ),
      'MP3 audio': (
        stream([
          FlvTag.build(type: FlvTag.audio, timestamp: 0, data: [0x2f, 0xff, 0xfb]),
        ]),
        'audio format 2',
      ),
      'VP6 video': (
        stream([
          FlvTag.build(type: FlvTag.video, timestamp: 0, data: [0x14, 0, 0]),
        ]),
        'codec id 4',
      ),
      'AV1 video': (
        stream([
          FlvTag.build(type: FlvTag.video, timestamp: 0, data: [0x90, ...'av01'.codeUnits, 1]),
        ]),
        'codec av01',
      ),
      'multitrack Enhanced FLV': (
        stream([
          FlvTag.build(type: FlvTag.video, timestamp: 0, data: [0x96, 0, ...'hvc1'.codeUnits]),
        ]),
        'packet type 6',
      ),
      'video before any sequence header': (stream([videoTag(0, key, key: true)]), 'sequence header'),
      'AAC before any AudioSpecificConfig': (
        stream([
          aacTag(0, [1, 2, 3]),
        ]),
        'AudioSpecificConfig',
      ),
      'a bad AVC record': (
        stream([
          videoTag(0, [0, 1, 2], packetType: 0, key: true),
        ]),
        'AVCDecoderConfigurationRecord',
      ),
      'a bad AudioSpecificConfig': (stream([aacTag(0, hex('1680'), packetType: 0)]), 'sampling frequency'),
      'a NAL unit overrunning its tag': (
        stream([
          videoTag(0, record, packetType: 0, key: true),
          videoTag(0, [0, 0, 0, 9, 0x65, 0x88], key: true),
        ]),
        'malformed NAL',
      ),
      'a changed video configuration': (
        stream([
          videoTag(0, record, packetType: 0, key: true),
          videoTag(0, key, key: true),
          videoTag(40, _otherPps(record), packetType: 0, key: true),
          videoTag(40, key, key: true),
        ]),
        'video configuration changes',
      ),
      'a changed AudioSpecificConfig': (
        stream([
          aacTag(0, hex('1210'), packetType: 0),
          aacTag(0, [1]),
          aacTag(23, hex('1190'), packetType: 0),
          aacTag(23, [1]),
        ]),
        'audio configuration changes',
      ),
      'a codec switch without a new sequence header': (
        stream([videoTag(0, record, packetType: 0, key: true), videoTag(0, key, key: true, codec: 12)]),
        'codec changes',
      ),
    };
    for (final MapEntry(key: name, value: (input, message)) in cases.entries) {
      test(name, () async {
        final error = await _fails(input);
        expect(error.message, contains(message));
      });
    }
  });

  group('cancellation and integration', () {
    test('isCancelled stops the remux between tags and removes the output', () async {
      var calls = 0;
      final files = MemoryRecordFiles()..put('/in.flv', hevc);
      await expectLater(
        remuxFlvToMp4(files: files, input: '/in.flv', output: '/out.mp4', isCancelled: () => ++calls > 100),
        throwsA(isA<RemuxException>().having((e) => e.message, 'message', 'cancelled')),
      );
      expect(calls, 101);
      expect(await files.exists('/out.mp4'), isFalse);
    });

    test('FlvToMp4Remuxer honours RemuxJob.cancelled', () async {
      final files = MemoryRecordFiles()..put('/in.flv', hevc);
      final job = RemuxJob(
        input: '/in.flv',
        output: '/out.mp4.partial',
        inputBytes: hevc.length,
        onProgress: (_) {},
        cancelled: Future.value(),
      );
      await expectLater(FlvToMp4Remuxer(files: files).remux(job), throwsA(isA<RemuxException>()));
      expect(await files.exists('/out.mp4.partial'), isFalse);
    });

    test('a changing input between the passes is detected', () async {
      final files = _ChangingFiles(hevc);
      await expectLater(
        remuxFlvToMp4(files: files, input: '/in.flv', output: '/out.mp4'),
        throwsA(isA<RemuxException>().having((e) => e.message, 'message', contains('input changed'))),
      );
    });

    test('remuxFiles commits the MP4 and deletes the source', () async {
      final files = MemoryRecordFiles()..put('/rec/a_001.flv', avc);
      final progress = <double>[];
      final outcome = await remuxFiles(
        files: files,
        remuxer: FlvToMp4Remuxer(files: files),
        inputs: ['/rec/a_001.flv'],
        onProgress: progress.add,
      );
      expect(outcome.failure, isNull);
      expect(outcome.outputs, ['/rec/a_001.mp4']);
      expect(await files.exists('/rec/a_001.flv'), isFalse);
      expect(progress.last, 1);
      _sameSamples(avc, files.bytesOf('/rec/a_001.mp4')!);
    });

    test('remuxFiles keeps the source of a damaged segment', () async {
      final files = MemoryRecordFiles()..put('/rec/a_001.flv', Uint8List.sublistView(avc, 0, avc.length - 3));
      final outcome = await remuxFiles(
        files: files,
        remuxer: FlvToMp4Remuxer(files: files),
        inputs: ['/rec/a_001.flv'],
      );
      expect(outcome.failure?.kind, RecordErrorKind.remuxFailed);
      expect(outcome.kept, ['/rec/a_001.flv']);
      expect(files.paths, ['/rec/a_001.flv']);
    });

    test('a writer segment of a legacy codec-12 Annex B stream remuxes to the same samples', () async {
      // A live Huya-style stream (timestamps far from 0, codec 12, start
      // codes) through the recorder's writer (rewrites to Enhanced FLV hvc1),
      // then remuxed.
      final live = flvFile([
        for (final packet in flvPackets(_legacyHevc(hevc, annexB: true)))
          if (packet.length == 13) packet else FlvTag.withTimestamp(packet, FlvTag.timestamp(packet) + 56321999),
      ]);
      final files = MemoryRecordFiles();
      late String segment;
      fakeAsync((async) {
        final layout = SessionLayout.at('/rec', RoomRef('huya', '998'), 'anchor', clock.now());
        final writer = FlvSessionWriter(
          files: files,
          layout: layout,
          gaps: GapLedger(files: files, path: layout.gaps, room: 'huya:998', session: layout.prefix),
        );
        flvPackets(live).forEach(writer.add);
        unawaited(writer.close());
        async.flushMicrotasks();
        segment = writer.segments.single.path;
      });
      final written = files.bytesOf(segment)!;
      expect(
        flvPackets(written)
            .skip(1)
            .where((tag) => FlvTag.type(tag) == FlvTag.video)
            .every((tag) => tagData(tag)[0] & 0x80 != 0),
        isTrue,
        reason: 'the writer rewrote codec 12 to Enhanced FLV',
      );
      final (mp4, _) = await _remux(written);
      final (reference, _) = await _remux(hevc);
      final a = _tracks(reference)['vide']!;
      final b = _tracks(mp4)['vide']!;
      expect(b.sizes, a.sizes);
      for (var i = 0; i < a.sizes.length; i++) {
        expect(b.sample(mp4, i), a.sample(reference, i));
      }
      expect(_tracks(mp4)['soun']!.sizes, _tracks(reference)['soun']!.sizes);
    });
  });
}

/// Serves [_bytes] on the first read pass and, afterwards, a copy of the
/// same length with two neighbouring audio tags of different sizes swapped.
final class _ChangingFiles implements RecordFiles {
  new(this._bytes);

  final Uint8List _bytes;
  final _memory = MemoryRecordFiles();

  @override
  Future<RecordReader> open(String path) async => _ChangingReader(_bytes, _swapped(_bytes));

  static Uint8List _swapped(Uint8List bytes) {
    final packets = flvPackets(bytes);
    for (var i = 1; i + 1 < packets.length; i++) {
      final (a, b) = (packets[i], packets[i + 1]);
      if (FlvTag.type(a) == FlvTag.audio && FlvTag.type(b) == FlvTag.audio && a.length != b.length) {
        if (tagData(a)[1] == 1 && tagData(b)[1] == 1) {
          packets[i] = FlvTag.withTimestamp(b, FlvTag.timestamp(a));
          packets[i + 1] = FlvTag.withTimestamp(a, FlvTag.timestamp(b));
          return flvFile(packets);
        }
      }
    }
    throw StateError('no audio pair');
  }

  @override
  Future<RecordSink> create(String path) => _memory.create(path);

  @override
  Future<void> delete(String path) => _memory.delete(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ChangingReader implements RecordReader {
  new(this._first, this._later);

  final Uint8List _first;
  final Uint8List _later;
  var _starts = 0;

  @override
  int get length => _first.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset == 0) _starts++;
    final source = _starts > 1 ? _later : _first;
    final end = offset + count < source.length ? offset + count : source.length;
    return Uint8List.fromList(source.sublist(offset, end));
  }

  @override
  Future<void> close() async {}
}
