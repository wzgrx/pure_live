import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/cc/cc_catalog.dart';

void main() {
  test('legacy HTML and game_list are not accepted as the new catalogue', () {
    for (final old in <Object>[
      '<!DOCTYPE html><html></html>',
      {'game_list': []},
    ]) {
      expect(() => CCCatalog.parse(old, {}), throwsFormatException);
    }
  });
  test('failed envelopes and unbounded metadata do not become empty successful tabs', () {
    for (final bad in <Object>[
      {'code': 500, 'result': []},
      {'code': 200, 'result': List.filled(2001, {})},
      {'code': 200, 'result': null},
    ]) {
      expect(() => CCCatalog.parse(bad, {}), throwsFormatException);
    }
  });
}
