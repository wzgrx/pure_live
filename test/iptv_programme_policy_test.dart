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

    test('provider default source expands UTC, duration and formatted timestamps', () {
      final result = buildIptvCatchupUrl(
        originalUrl: 'https://fixture/live',
        start: DateTime.utc(2026, 9, 12, 10, 2, 3),
        stop: DateTime.utc(2026, 9, 12, 11, 4, 5),
        now: DateTime.utc(2026, 9, 12, 12),
        mode: 'default',
        source: r'https://archive/stream?start={utc}&end=${end}&duration={duration}&minutes={duration:60}&date={utc:Ymd-HMS}',
      );
      final uri = Uri.parse(result);

      expect(uri.queryParameters['start'], '${DateTime.utc(2026, 9, 12, 10, 2, 3).millisecondsSinceEpoch ~/ 1000}');
      expect(uri.queryParameters['end'], '${DateTime.utc(2026, 9, 12, 11, 4, 5).millisecondsSinceEpoch ~/ 1000}');
      expect(uri.queryParameters['duration'], '3722');
      expect(uri.queryParameters['minutes'], '62');
      expect(uri.queryParameters['date'], '20260912-100203');
    });

    test('append mode keeps repeated live parameters and places expanded query before the fragment', () {
      final result = buildIptvCatchupUrl(
        originalUrl: 'https://fixture/live?token=a&token=b#preview',
        start: DateTime.utc(2026, 9, 12, 10),
        stop: DateTime.utc(2026, 9, 12, 11),
        now: DateTime.utc(2026, 9, 12, 12),
        mode: 'append',
        source: '&start={Y}{m}{d}{H}{M}{S}&offset={offset:60}',
        correctionHours: -2.5,
      );
      final uri = Uri.parse(result);

      expect(uri.fragment, 'preview');
      expect(uri.queryParametersAll['token'], ['a', 'b']);
      expect(uri.queryParameters['start'], '20260912073000');
      expect(uri.queryParameters['offset'], '270');
    });

    test('shift mode generates the standard start and live UTC query', () {
      final start = DateTime.utc(2026, 9, 12, 10);
      final now = DateTime.utc(2026, 9, 12, 12);
      final uri = Uri.parse(
        buildIptvCatchupUrl(
          originalUrl: 'https://fixture/live#preview',
          start: start,
          stop: start.add(const Duration(hours: 1)),
          now: now,
          mode: 'shift',
        ),
      );

      expect(uri.queryParameters['utc'], '${start.millisecondsSinceEpoch ~/ 1000}');
      expect(uri.queryParameters['lutc'], '${now.millisecondsSinceEpoch ~/ 1000}');
      expect(uri.fragment, 'preview');
    });

    test('programme catch-up IDs expand provider templates and VOD sources', () {
      final templated = buildIptvCatchupUrl(
        originalUrl: 'https://fixture/live',
        start: start,
        stop: stop,
        mode: 'default',
        source: 'https://archive/episode/{catchup-id}?start={utc}',
        catchupId: 'episode-42',
      );
      final direct = buildIptvCatchupUrl(
        originalUrl: 'https://fixture/live',
        start: start,
        stop: stop,
        mode: 'vod',
        catchupId: 'https://archive/episode-43',
      );

      expect(Uri.parse(templated).path, '/episode/episode-42');
      expect(Uri.parse(templated).queryParameters['start'], '${start.toUtc().millisecondsSinceEpoch ~/ 1000}');
      expect(direct, 'https://archive/episode-43');
      expect(
        () => buildIptvCatchupUrl(
          originalUrl: 'https://fixture/live',
          start: start,
          stop: stop,
          mode: 'default',
          source: 'https://archive/{catchup-id}',
        ),
        throwsFormatException,
      );
    });

    test('Flussonic and Xtream Codes modes generate documented provider URLs', () {
      final absolute = Uri.parse(
        buildIptvCatchupUrl(
          originalUrl: 'http://fixture:8888/151/mpegts?token=stable',
          start: DateTime.utc(2026, 9, 12, 10),
          stop: DateTime.utc(2026, 9, 12, 11),
          now: DateTime.utc(2026, 9, 12, 12),
          mode: 'fs',
        ),
      );
      final relative = Uri.parse(
        buildIptvCatchupUrl(
          originalUrl: 'http://fixture:8888/325/mono.m3u8?token=stable',
          start: DateTime.utc(2026, 9, 12, 10),
          stop: DateTime.utc(2026, 9, 12, 11),
          now: DateTime.utc(2026, 9, 12, 12),
          mode: 'flussonic-hls',
        ),
      );
      final xtream = Uri.parse(
        buildIptvCatchupUrl(
          originalUrl: 'http://fixture:8080/live/user/password/1477.m3u8',
          start: DateTime.utc(2026, 9, 12, 10),
          stop: DateTime.utc(2026, 9, 12, 11, 2),
          mode: 'xc',
        ),
      );

      expect(absolute.path, '/151/timeshift_abs-1789207200.ts');
      expect(absolute.queryParameters['token'], 'stable');
      expect(relative.path, '/325/mono-timeshift_rel-7200.m3u8');
      expect(relative.queryParameters['token'], 'stable');
      expect(xtream.path, '/timeshift/user/password/62/2026-09-12:10-00/1477.m3u8');
    });

    test('explicitly disabled and unknown or malformed modes do not invent provider requests', () {
      expect(
        () => buildIptvCatchupUrl(originalUrl: 'https://fixture/live', start: start, stop: stop, mode: 'disabled'),
        throwsUnsupportedError,
      );
      expect(
        () => buildIptvCatchupUrl(
          originalUrl: 'https://fixture/live',
          start: start,
          stop: stop,
          mode: 'provider-private',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => buildIptvCatchupUrl(originalUrl: 'https://fixture/live.ts', start: start, stop: stop, mode: 'xc'),
        throwsFormatException,
      );
    });
  });

  group('IPTV provider catch-up availability', () {
    final now = DateTime.utc(2026, 9, 12, 12);

    test('honors explicit disablement and archive windows without narrowing an unspecified legacy feed', () {
      expect(
        evaluateIptvCatchupAvailability(programmeStop: now.subtract(const Duration(days: 10)), now: now),
        IptvCatchupAvailability.available,
      );
      expect(
        evaluateIptvCatchupAvailability(
          programmeStop: now.subtract(const Duration(hours: 1)),
          now: now,
          mode: 'disabled',
        ),
        IptvCatchupAvailability.disabled,
      );
      expect(
        evaluateIptvCatchupAvailability(
          programmeStop: now.subtract(const Duration(days: 3, microseconds: 1)),
          now: now,
          mode: 'append',
          source: '&start={utc}',
          days: 3,
        ),
        IptvCatchupAvailability.outsideWindow,
      );
      expect(
        evaluateIptvCatchupAvailability(
          programmeStop: now.subtract(const Duration(days: 3)),
          now: now,
          mode: 'append',
          source: '&start={utc}',
          days: 3,
        ),
        IptvCatchupAvailability.available,
      );
    });

    test('requires either a built-in mode or a provider source template', () {
      expect(
        evaluateIptvCatchupAvailability(programmeStop: now, now: now, mode: 'provider-private'),
        IptvCatchupAvailability.unsupported,
      );
      expect(
        evaluateIptvCatchupAvailability(
          programmeStop: now,
          now: now,
          mode: 'provider-private',
          source: 'https://archive/{utc}',
        ),
        IptvCatchupAvailability.available,
      );
      expect(
        evaluateIptvCatchupAvailability(
          programmeStop: now,
          now: now,
          mode: 'default',
          source: 'https://archive/{catchup-id}',
        ),
        IptvCatchupAvailability.unsupported,
      );
      expect(
        evaluateIptvCatchupAvailability(
          programmeStop: now,
          now: now,
          mode: 'vod',
          catchupId: 'https://archive/episode',
        ),
        IptvCatchupAvailability.available,
      );
    });
  });
}
