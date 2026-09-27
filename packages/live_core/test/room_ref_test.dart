import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  group('RoomRef', () {
    test('lower-cases the platform and keeps the room id case', () {
      final ref = RoomRef(' Douyu ', ' AbC123 ');
      expect(ref.platform, 'douyu');
      expect(ref.roomId, 'AbC123');
      expect(ref.key, 'douyu:AbC123');
    });

    test('equal refs compare and hash equal', () {
      expect(RoomRef('huya', '998'), RoomRef('HUYA', '998'));
      expect(RoomRef('huya', '998').hashCode, RoomRef('huya', ' 998').hashCode);
      expect(RoomRef('kick', 'Abc'), isNot(RoomRef('kick', 'abc')));
    });

    test('rejects empty platforms and placeholder room ids', () {
      expect(() => RoomRef('', '1'), throwsFormatException);
      for (final id in ['', ' ', '0', 'null', 'NULL', 'undefined', 'NaN', 'none']) {
        expect(() => RoomRef('bilibili', id), throwsFormatException, reason: id);
      }
    });

    test('parses its own key', () {
      final ref = RoomRef.parse('twitch:SomeChannel');
      expect(ref.platform, 'twitch');
      expect(ref.roomId, 'SomeChannel');
      expect(RoomRef.parse(ref.key), ref);
      expect(() => RoomRef.parse('nocolon'), throwsFormatException);
    });
  });
}
