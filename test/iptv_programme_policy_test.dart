import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/iptv_programme_policy.dart';

void main() {
  group('IPTV programme interval policy', () {
    final start = DateTime(2026, 9, 12, 10);
    final stop = DateTime(2026, 9, 12, 11);

    test('uses half-open boundaries shared by the schedule and tap action', () {
      expect(
        classifyIptvProgramme(start: start, stop: stop, now: start.subtract(const Duration(microseconds: 1))),
        IptvProgrammePhase.scheduled,
      );
      expect(classifyIptvProgramme(start: start, stop: stop, now: start), IptvProgrammePhase.live);
      expect(
        classifyIptvProgramme(start: start, stop: stop, now: stop.subtract(const Duration(microseconds: 1))),
        IptvProgrammePhase.live,
      );
      expect(classifyIptvProgramme(start: start, stop: stop, now: stop), IptvProgrammePhase.catchup);
    });
  });

  group('IPTV catch-up URL policy', () {
    final start = DateTime(2026, 9, 12, 10, 2, 3);
    final stop = DateTime(2026, 9, 12, 11, 4, 5);

    test('playseek keeps fragments and repeated existing query values', () {
      final result = buildIptvCatchupUrl(
        originalUrl: 'https://fixture/live?token=a&token=b#preview',
        start: start,
        stop: stop,
        type: CatchupUrlType.playseek,
      );
      final uri = Uri.parse(result);

      expect(uri.fragment, 'preview');
      expect(uri.queryParametersAll['token'], ['a', 'b']);
      expect(uri.queryParametersAll['playseek'], ['20260912100203-20260912110405']);
    });

    test('default mode replaces one existing timeshift without moving the fragment', () {
      final result = buildIptvCatchupUrl(
        originalUrl: 'https://fixture/live?timeshift=old&token=stable#player',
        start: start,
        stop: stop,
      );
      final uri = Uri.parse(result);

      expect(uri.fragment, 'player');
      expect(uri.queryParametersAll['timeshift'], ['20260912100203']);
      expect(uri.queryParameters['token'], 'stable');
    });

    test('offset mode uses the supplied clock and replaces owned parameters', () {
      final result = buildIptvCatchupUrl(
        originalUrl: 'https://fixture/live?catchup=old&offset=9&token=stable',
        start: start,
        stop: stop,
        type: CatchupUrlType.offset,
        now: start.add(const Duration(seconds: 125)),
      );
      final uri = Uri.parse(result);

      expect(uri.queryParameters['catchup'], 'default');
      expect(uri.queryParametersAll['offset'], ['125']);
      expect(uri.queryParameters['token'], 'stable');
    });

    test('offset mode clamps a future start to zero', () {
      final uri = Uri.parse(
        buildIptvCatchupUrl(
          originalUrl: 'https://fixture/live',
          start: start,
          stop: stop,
          type: CatchupUrlType.offset,
          now: start.subtract(const Duration(minutes: 1)),
        ),
      );

      expect(uri.queryParameters['offset'], '0');
    });

    test('rejects empty or relative URLs and a non-positive programme interval', () {
      expect(() => buildIptvCatchupUrl(originalUrl: '  ', start: start, stop: stop), throwsArgumentError);
      expect(() => buildIptvCatchupUrl(originalUrl: 'relative/live', start: start, stop: stop), throwsArgumentError);
      expect(
        () => buildIptvCatchupUrl(originalUrl: 'https://fixture/live', start: start, stop: start),
        throwsArgumentError,
      );
    });
  });
}
