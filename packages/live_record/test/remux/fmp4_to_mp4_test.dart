import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/fake_hls.dart';
import '../support/mp4_reader.dart';
import 'ts_to_mp4_test.dart' show sameAsReference, tracksOf;

final _fixed = Clock.fixed(DateTime.utc(2026, 9, 28, 12));

Future<(Uint8List, RemuxResult)> _remux(List<int> input) async {
  final files = MemoryRecordFiles()..put('/in.m4s', input);
  final result = await withClock(_fixed, () => remuxFmp4ToMp4(files: files, input: '/in.m4s', output: '/out.mp4'));
  return (files.bytesOf('/out.mp4')!, result);
}

Future<RemuxException> _fails(List<int> input) async {
  final files = MemoryRecordFiles()..put('/in.m4s', input);
  try {
    await remuxFmp4ToMp4(files: files, input: '/in.m4s', output: '/out.mp4');
  } on RemuxException catch (error) {
    expect(await files.exists('/out.mp4'), isFalse);
    return error;
  }
  fail('expected a RemuxException');
}

void main() {
  final whole = [...fmp4Init, ...fmp4Fragments[0], ...fmp4Fragments[1]];

  test('the fragments of ffmpeg HLS fMP4 become the samples of ffmpeg -c copy, entries copied as they are', () async {
    final (mp4, result) = await _remux(whole);
    sameAsReference(mp4, File('test/fixtures/remux/avc_aac.m4s.ffmpeg.mp4').readAsBytesSync(), hevc: false);
    expect((result.videoSamples, result.audioSamples, result.keyframes), (60, 88, 2));
    expect(result.videoCodec, VideoCodec.avc);
    expect(result.audioSampleRate, 44100);
    final moov = parseBoxes(mp4)[1];
    expect(moov.find('trak/mdia/minf/stbl/stsd/avc1/avcC'), isNotNull);
    expect(moov.all('trak').last.find('mdia/minf/stbl/stsd/mp4a/esds'), isNotNull);
    expect(tracksOf(mp4)['vide']!.syncSamples, [1, 31]);
  });

  test('a repeated stretch (timestamps back to the start) joins after what was written', () async {
    final (mp4, _) = await _remux([...whole, ...fmp4Fragments[0]]);
    final video = tracksOf(mp4)['vide']!;
    expect(video.sizes, hasLength(90));
    final steps = [for (var i = 1; i < video.sizes.length; i++) video.decodeTimes[i] - video.decodeTimes[i - 1]];
    // The new stretch starts after everything written (the audio ends 43 ms after the last frame).
    expect(steps.every((step) => step > 0 && step / video.timescale <= 0.1), isTrue, reason: '$steps');
  });

  test('damage: a cut fragment, a missing initialisation section, a second one, encryption', () async {
    expect(
      (await _fails([...fmp4Init, ...fmp4Fragments[0].sublist(0, 5000)])).message,
      anyOf(contains('cut off'), contains('outside the file')),
    );
    expect((await _fails(fmp4Fragments[0])).message, contains('before the initialisation section'));
    expect((await _fails([...fmp4Init, ...fmp4Fragments[0], ...fmp4Init])).message, contains('second'));
    final encrypted = Uint8List.fromList(fmp4Init);
    final avc1 = String.fromCharCodes(encrypted).indexOf('avc1');
    encrypted.setRange(avc1, avc1 + 4, 'encv'.codeUnits);
    expect((await _fails([...encrypted, ...fmp4Fragments[0]])).message, contains('encrypted'));
  });
}
