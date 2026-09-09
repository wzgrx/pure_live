import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/zhanqi/zhanqi_api.dart';
import 'package:pure_live/core/site/zhanqi/zhanqi_player_layout.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/zhanqi/player-layout.json').readAsStringSync()) as Map<String, dynamic>;
String _encode(Object json) => base64.encode(utf8.encode(jsonEncode(json)));
ZhanqiPlayerLayout _parse(Map<String, dynamic> json) =>
    ZhanqiPlayerLayout.parseEncoded(_encode(json), expectedRoomId: '101', expectedVideoId: '101_fixture');
Matcher _failure(ZhanqiLayoutFailure kind) => throwsA(isA<ZhanqiLayoutException>().having((e) => e.kind, 'kind', kind));
Matcher _apiFailure(ZhanqiFailure kind) => throwsA(isA<ZhanqiException>().having((e) => e.kind, 'kind', kind));
Map<String, dynamic> _room() =>
    jsonDecode(File('test/fixtures/zhanqi/room.json').readAsStringSync()) as Map<String, dynamic>;
ZhanqiRoomSnapshot _parseRoom(Map<String, dynamic> json) =>
    ZhanqiApi.parseRoom(json, code: '301', expectedRoomId: '101', expectedOwnerId: '201');

void main() {
  test('observed player matrix has one enabled quality and four aliases of one source', () {
    final layout = _parse(_fixture());
    expect(layout.videoId, '101_fixture');
    expect(layout.defaultQualityIndex, 2);
    expect(layout.qualityNames, ['原画', '超清HD', '超清', '高清', '标清']);
    expect(layout.enabledQualityIndices, [2]);
    expect(layout.defaultQualityEnabled, isTrue);
    expect(layout.cells, hasLength(4));
    expect(layout.cells.every((cell) => cell.cdnKey == 202 && cell.suffix.isEmpty), isTrue);
    expect(layout.sourceGroups, hasLength(1));
    expect(layout.sourceGroups[(202, '')]!.map((cell) => cell.lineIndex), [0, 1, 2, 3]);
  });
  test('configuration lists, cells, and identity groups are immutable', () {
    final layout = _parse(_fixture());
    for (final mutate in <void Function()>[
      () => layout.lineNames.clear(),
      () => layout.qualityNames.clear(),
      () => layout.suffixes.clear(),
      () => layout.cells.clear(),
      () => layout.enabledQualityIndices.clear(),
      () => layout.sourceGroups.clear(),
      () => layout.sourceGroups.values.first.clear(),
    ]) {
      expect(mutate, throwsUnsupportedError);
    }
  });
  test('same CDN suffix in different quality columns is still one source identity', () {
    final json = _fixture();
    json['square'][0][0] = 202;
    final layout = _parse(json);
    expect(layout.enabledQualityIndices, [0, 2]);
    expect(layout.sourceGroups, hasLength(1));
    expect(layout.sourceGroups.values.single.map((cell) => cell.qualityIndex), [0, 2, 2, 2, 2]);
  });
  test('a different suffix remains a different declaration without a fabricated resolution', () {
    final json = _fixture();
    json['square'][0][3] = 202;
    final layout = _parse(json);
    expect(layout.enabledQualityIndices, [2, 3]);
    expect(layout.sourceGroups.keys, contains((202, '_480p')));
    expect(layout.qualityNames[3], '高清');
  });
  test('unknown CDN ids remain visible metadata rather than guessed URLs or dropped qualities', () {
    final json = _fixture();
    json['square'][0][1] = 999;
    final layout = _parse(json);
    expect(layout.enabledQualityIndices, [1, 2]);
    expect(layout.sourceGroups.keys, contains((999, '_720phd')));
  });
  test('short rows keep missing cells disabled and preserve original indices', () {
    final json = _fixture();
    json['square'][0] = [0, 0];
    final layout = _parse(json);
    expect(layout.cells.map((cell) => cell.lineIndex), [1, 2, 3]);
  });
  test('an all-disabled layout remains empty, including an inactive default column', () {
    final json = _fixture();
    json['square'] = List.generate(4, (_) => List.filled(5, 0));
    final layout = _parse(json);
    expect(layout.cells, isEmpty);
    expect(layout.enabledQualityIndices, isEmpty);
    expect(layout.defaultQualityEnabled, isFalse);
  });
  for (final invalid in [
    'version',
    'status',
    'fractional-status',
    'video',
    'line-count',
    'rates-empty',
    'suffix-count',
    'suffix-path',
    'labels-type',
    'long-label',
    'default-overflow',
    'default-negative',
    'row-overflow',
    'cdn-negative',
    'cdn-string',
    'cdn-double',
    'cdn-budget',
    'trule',
  ]) {
    test('malformed layout $invalid is not partially published', () {
      final json = _fixture();
      switch (invalid) {
        case 'version':
          json['ver'] = '2.0';
        case 'status':
          json['status'] = 0;
        case 'fractional-status':
          json['status'] = 4.0;
        case 'video':
          json['vid'] = '102_fixture';
        case 'line-count':
          json['line'] = ['only'];
        case 'rates-empty':
          json['rate'] = [];
        case 'suffix-count':
          json['suffix'] = [''];
        case 'suffix-path':
          json['suffix'][2] = '/../other';
        case 'labels-type':
          json['rate'][2] = 720;
        case 'long-label':
          json['line'][0] = 'a' * 257;
        case 'default-overflow':
          json['rateIndex'] = 5;
        case 'default-negative':
          json['rateIndex'] = -1;
        case 'row-overflow':
          json['square'][0].add(202);
        case 'cdn-negative':
          json['square'][0][2] = -1;
        case 'cdn-string':
          json['square'][0][2] = '202';
        case 'cdn-double':
          json['square'][0][2] = 202.0;
        case 'cdn-budget':
          json['square'][0][2] = 10000;
        case 'trule':
          json['trule'] = {};
      }
      expect(
        () => _parse(json),
        _failure(invalid == 'video' ? ZhanqiLayoutFailure.identity : ZhanqiLayoutFailure.schema),
      );
    });
  }
  test('encoded byte budget and strict UTF8/JSON are enforced', () {
    for (final value in [
      '',
      '!' * 4,
      'A' * 65537,
      base64.encode([0xc3, 0x28]),
      _encode([]),
    ]) {
      expect(
        () => ZhanqiPlayerLayout.parseEncoded(value, expectedRoomId: '101', expectedVideoId: '101_fixture'),
        _failure(ZhanqiLayoutFailure.schema),
      );
    }
  });
  test('expected room and video identity are validated before configuration parsing', () {
    for (final pair in [
      ('0', '0_fixture'),
      ('../101', '101_fixture'),
      ('101', '102_fixture'),
      ('101', '101_a/other'),
    ]) {
      expect(
        () => ZhanqiPlayerLayout.parseEncoded(_encode(_fixture()), expectedRoomId: pair.$1, expectedVideoId: pair.$2),
        _failure(ZhanqiLayoutFailure.identity),
      );
    }
  });
  test('API prioritizes current h5Cdns over cdns and malformed legacy HLS', () {
    final json = _room();
    json['data']['videoId'] = '101_fixture';
    final flash = json['data']['flashvars'];
    flash['h5Cdns'] = _encode(_fixture());
    flash['cdns'] = 'invalid ignored field';
    flash['VideoLevels'] = 'invalid ignored legacy source';
    final room = _parseRoom(json);
    expect(room.playerLayout!.enabledQualityIndices, [2]);
    expect(room.declaredStream, isNull);
    expect(room.reportedLive, isTrue);
  });
  test('API uses cdns only when h5Cdns is absent or empty', () {
    final json = _room();
    json['data']['videoId'] = '101_fixture';
    json['data']['flashvars']['cdns'] = _encode(_fixture());
    for (final value in [null, '']) {
      json['data']['flashvars']['h5Cdns'] = value;
      expect(_parseRoom(json).playerLayout, isNotNull);
    }
  });
  test('malformed current config does not silently fall back to legacy media', () {
    final json = _room();
    json['data']['videoId'] = '101_fixture';
    json['data']['flashvars']['cdns'] = _encode(_fixture());
    for (final value in ['%%%bad', 1]) {
      json['data']['flashvars']['h5Cdns'] = value;
      expect(() => _parseRoom(json), _apiFailure(ZhanqiFailure.schema));
    }
  });
  test('current layout validates broadcast ownership and leaves offline metadata independent', () {
    final json = _room();
    json['data']['videoId'] = '101_other';
    json['data']['flashvars']['h5Cdns'] = _encode(_fixture());
    expect(() => _parseRoom(json), _apiFailure(ZhanqiFailure.identity));
    json['data']['status'] = '0';
    final room = _parseRoom(json);
    expect(room.reportedLive, isFalse);
    expect(room.playerLayout, isNull);
    expect(room.declaredStream, isNull);
  });
}
