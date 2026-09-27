import 'dart:typed_data';

import 'package:live_media/live_media.dart';
import 'package:live_record/src/remux/codec_config.dart';
import 'package:live_record/src/remux/flv_demux.dart';
import 'package:test/test.dart';

import '../support/flv_build.dart';

/// Real AVCDecoderConfigurationRecords from 2026-09-28 recordings.
final Uint8List _douyu1080 = hex(
  '01640028ffe1001a67640028ac52140780227e5840000003004000000f03c60c216001000568ea58472c',
);
final Uint8List _bilibili720 = hex(
  '01640028ffe1001e67640028ac7289014016e9a808080a000003000200000300781e306144c001000468e93bcbfcf8f800',
);
final Uint8List _huya1440 = hex(
  '01640033ffe1001e67640033ac521402800b5b016a02020280000003008000003c078c1842c001000468ee172cfdf8f800',
);

/// VPS, SPS and PPS of a Huya HEVC stream as its FLV sends them: Annex B.
final Uint8List _huyaHevcAnnexB = hex(
  '0000000140010c01ffff0160000003009000000300000300998820902400'
  '00000001420101016000000300900000030000030099a001402005a16588209924cab016a020202080000003008000001e04'
  '000000014401c172b06240',
);

Uint8List _bits(String bits) {
  final padded = bits.padRight((bits.length + 7) ~/ 8 * 8, '0');
  return Uint8List.fromList([
    for (var i = 0; i < padded.length; i += 8) int.parse(padded.substring(i, i + 8), radix: 2),
  ]);
}

void main() {
  group('BitReader', () {
    test('reads bits, Exp-Golomb and signed Exp-Golomb values', () {
      final r = BitReader(
        _bits(
          '101'
          '1'
          '010'
          '011'
          '00100'
          '010'
          '011',
        ),
      );
      expect(r.bits(3), 5);
      expect(r.ue(), 0);
      expect(r.ue(), 1);
      expect(r.ue(), 2);
      expect(r.ue(), 3);
      expect(r.se(), 1);
      expect(r.se(), -1);
    });

    test('throws FormatException past the end', () {
      final r = BitReader(Uint8List.fromList([0]));
      expect(() => r.bits(9), throwsFormatException);
      expect(() => BitReader(Uint8List(2)).ue(), throwsFormatException);
    });

    test('unescapeRbsp drops emulation prevention bytes after the header', () {
      expect(unescapeRbsp(Uint8List.fromList([0x67, 0, 0, 3, 1, 0, 0, 3, 0]), 1), [0, 0, 1, 0, 0, 0]);
    });
  });

  group('H.264 SPS', () {
    test('real records give their cropped size', () {
      final douyu = VideoConfig.parse(VideoCodec.avc, _douyu1080);
      expect((douyu.width, douyu.height, douyu.lengthSize), (1920, 1080, 4));
      expect(douyu.parameterSets, hasLength(2));
      final bilibili = VideoConfig.parse(VideoCodec.avc, _bilibili720);
      expect((bilibili.width, bilibili.height), (1280, 720));
      final huya = VideoConfig.parse(VideoCodec.avc, _huya1440);
      expect((huya.width, huya.height, huya.sarWidth, huya.sarHeight), (2560, 1440, 1, 1));
      final fixture = VideoConfig.parse(VideoCodec.avc, avcRecordOf(remuxFixture('avc_aac.flv')));
      expect((fixture.width, fixture.height), (64, 48));
    });

    test('an unreadable SPS leaves the size unknown but the record usable', () {
      final record = hex('016400 28ffe1 0002 6764 01 0002 68ea');
      final config = VideoConfig.parse(VideoCodec.avc, record);
      expect((config.width, config.height), (0, 0));
    });

    test('malformed records throw FormatException', () {
      expect(() => VideoConfig.parse(VideoCodec.avc, hex('00640028ff')), throwsFormatException);
      expect(() => VideoConfig.parse(VideoCodec.avc, hex('01640028ffe1001a6764')), throwsFormatException);
      expect(() => VideoConfig.parse(VideoCodec.avc, hex('01640028fee1000167 00')), throwsFormatException);
      expect(() => VideoConfig.parse(VideoCodec.avc, hex('01640028ffe0 00')), throwsFormatException);
    });

    test('sameAs compares parameter sets, not record padding', () {
      final a = VideoConfig.parse(VideoCodec.avc, _douyu1080);
      final padded = Uint8List.fromList([..._douyu1080, 0xfc, 0xf8, 0xf8, 0]);
      expect(a.sameAs(VideoConfig.parse(VideoCodec.avc, padded)), isTrue);
      expect(a.sameAs(VideoConfig.parse(VideoCodec.avc, _bilibili720)), isFalse);
      final otherPps = Uint8List.fromList(_douyu1080)..[_douyu1080.length - 1] ^= 1;
      expect(a.sameAs(VideoConfig.parse(VideoCodec.avc, otherPps)), isFalse);
    });

    test('an Annex B sequence header becomes an avcC with 4-byte lengths', () {
      final real = VideoConfig.parse(VideoCodec.avc, _douyu1080);
      final annexB = Uint8List.fromList([
        for (final set in real.parameterSets) ...[0, 0, 0, 1, ...set],
      ]);
      final built = VideoConfig.fromAnnexB(VideoCodec.avc, annexB);
      expect(built.annexB, isTrue);
      expect(built.sameAs(real), isTrue);
      expect((built.width, built.height), (1920, 1080));
      // High profile: chroma format and bit depths follow the parameter sets.
      expect(built.record.sublist(built.record.length - 4), [0xfd, 0xf8, 0xf8, 0]);
    });
  });

  group('H.265 SPS', () {
    test('an Annex B sequence header becomes an hvcC', () {
      final config = VideoConfig.fromAnnexB(VideoCodec.hevc, _huyaHevcAnnexB);
      expect((config.width, config.height, config.lengthSize), (2560, 1440, 4));
      expect(config.parameterSets.map((nal) => (nal[0] >> 1) & 0x3f), [32, 33, 34]);
      final record = config.record;
      expect(record[0], 1);
      expect(record[1], 0x01, reason: 'general profile space 0, tier 0, Main');
      expect(record[12], 153, reason: 'general_level_idc');
      expect(record[16] & 0x03, 1, reason: '4:2:0');
      expect(record[21] & 0x03, 3, reason: '4-byte NAL lengths');
      expect(record[22], 3, reason: 'VPS, SPS and PPS arrays');
      // Parsing the built record gives the same stream back.
      expect(VideoConfig.parse(VideoCodec.hevc, record).sameAs(config), isTrue);
    });

    test('the fixture hvcC gives its size', () {
      final packets = flvPackets(remuxFixture('hevc_aac.flv'));
      final tag = packets.skip(1).firstWhere(FlvTag.isVideoConfig);
      final config = VideoConfig.parse(VideoCodec.hevc, Uint8List.fromList(tagData(tag).sublist(5)));
      expect((config.width, config.height), (64, 48));
    });

    test('a sequence header without SPS or PPS throws', () {
      expect(() => VideoConfig.fromAnnexB(VideoCodec.hevc, hex('0000000140010c01')), throwsFormatException);
      expect(() => VideoConfig.fromAnnexB(VideoCodec.avc, hex('000000016764')), throwsFormatException);
    });
  });

  group('Annex B', () {
    test('splitAnnexB handles 3- and 4-byte start codes and trailing zeros', () {
      final units = splitAnnexB(hex('00000001 0901 000001 6588 8000 0000 000001 06050000'));
      expect(units, [
        [0x09, 0x01],
        [0x65, 0x88, 0x80],
        [0x06, 0x05],
      ]);
      expect(isAnnexB(hex('00000001 09')), isTrue);
      expect(isAnnexB(hex('000001 09')), isTrue);
      expect(isAnnexB(hex('00000002 0901')), isFalse);
    });

    test('lengthPrefixed round-trips with isLengthPrefixed', () {
      final data = lengthPrefixed([hex('0901'), hex('658880')], 4);
      expect(data, hex('00000002 0901 00000003 658880'));
      expect(isLengthPrefixed(data, 4), isTrue);
      expect(isLengthPrefixed(Uint8List.fromList([...data, 0, 0]), 4), isTrue);
      expect(isLengthPrefixed(Uint8List.fromList([...data, 1]), 4), isFalse);
      expect(isLengthPrefixed(hex('00000009 0901'), 4), isFalse);
      expect(lengthPrefixed([hex('0901')], 2), hex('0002 0901'));
      expect(() => lengthPrefixed([Uint8List(256)], 1), throwsFormatException);
    });
  });

  group('AAC', () {
    test('AudioSpecificConfig: LC, rates, channels, frame length', () {
      final lc = AacConfig.parse(hex('1210'));
      expect((lc.objectType, lc.sampleRate, lc.channelConfig, lc.frameSamples), (2, 44100, 2, 1024));
      final lc48 = AacConfig.parse(hex('1190'));
      expect((lc48.sampleRate, lc48.channelCount), (48000, 2));
      final implicitSbr = AacConfig.parse(hex('121056e500'));
      expect((implicitSbr.objectType, implicitSbr.sampleRate), (2, 44100));
      final explicitSbr = AacConfig.parse(hex('2b118800'));
      expect((explicitSbr.objectType, explicitSbr.sampleRate, explicitSbr.frameSamples), (2, 24000, 1024));
      expect(AacConfig.parse(hex('1214')).frameSamples, 960);
      final escaped = AacConfig.parse(
        _bits(
          '00010'
          '1111'
          '000000001010110001000100'
          '0001'
          '0',
        ),
      );
      expect((escaped.sampleRate, escaped.channelCount), (44100, 1));
      expect(AacConfig.parse(hex('1238')).channelCount, 8);
      expect(AacConfig.parse(hex('1200')).channelCount, 2);
    });

    test('bad configs throw FormatException', () {
      expect(() => AacConfig.parse(hex('12')), throwsFormatException);
      expect(
        () => AacConfig.parse(
          _bits(
            '00010'
            '1101'
            '0010',
          ),
        ),
        throwsFormatException,
      );
    });

    test('ADTS headers are recognised only when they frame the whole payload', () {
      final frame = Uint8List.fromList([...adtsHeader(5), 1, 2, 3, 4, 5]);
      expect(AacConfig.adtsHeaderLength(frame), 7);
      expect(AacConfig.adtsHeaderLength(Uint8List.fromList([...frame, 0])), 0);
      expect(AacConfig.adtsHeaderLength(hex('21 1a cc 9d ff ff b0 80')), 0);
      final config = AacConfig.fromAdts(frame);
      expect(config.asc, hex('1210'));
    });
  });

  test('onMetaData values are read from the fixture script tag', () {
    final script = flvPackets(remuxFixture('avc_aac.flv'))
        .skip(1)
        .firstWhere((tag) => FlvTag.type(tag) == FlvTag.script);
    final metadata = readOnMetaData(tagData(script));
    expect(metadata['width'], 64);
    expect(metadata['height'], 48);
    expect(metadata['stereo'], isTrue);
    expect(readOnMetaData(hex('02000a6f6e4d65746144617461 08 0000')), isEmpty);
    expect(readOnMetaData(hex('0200036162 63')), isEmpty);
  });
}
