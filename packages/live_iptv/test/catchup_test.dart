import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

/// Ported from 3.x `iptv_programme_policy_test.dart`.
void main() {
  test('programme intervals are half-open', () {
    final start = DateTime(2026, 9, 12, 10);
    final stop = DateTime(2026, 9, 12, 11);
    const tick = Duration(microseconds: 1);
    expect(classifyIptvProgramme(start: start, stop: stop, now: start.subtract(tick)), IptvProgrammePhase.scheduled);
    expect(classifyIptvProgramme(start: start, stop: stop, now: start), IptvProgrammePhase.live);
    expect(classifyIptvProgramme(start: start, stop: stop, now: stop.subtract(tick)), IptvProgrammePhase.live);
    expect(classifyIptvProgramme(start: start, stop: stop, now: stop), IptvProgrammePhase.catchup);
  });

  group('URL without catch-up attributes', () {
    final start = DateTime(2026, 9, 12, 10, 2, 3);
    final stop = DateTime(2026, 9, 12, 11, 4, 5);

    test('playseek keeps fragments and repeated query values, in local time', () {
      final uri = Uri.parse(
        buildIptvCatchupUrl(
          originalUrl: 'https://f/live?token=a&token=b#preview',
          start: start,
          stop: stop,
          type: CatchupUrlType.playseek,
        ),
      );
      expect(uri.fragment, 'preview');
      expect(uri.queryParametersAll['token'], ['a', 'b']);
      expect(uri.queryParameters['playseek'], '20260912100203-20260912110405');
      final utc = buildIptvCatchupUrl(
        originalUrl: 'https://f/live',
        start: start.toUtc(),
        stop: stop.toUtc(),
        type: CatchupUrlType.playseek,
      );
      expect(Uri.parse(utc).queryParameters['playseek'], '20260912100203-20260912110405');
    });

    test('timeshift and offset shapes; a future start gives offset 0', () {
      final shifted = Uri.parse(
        buildIptvCatchupUrl(originalUrl: 'https://f/live?timeshift=old', start: start, stop: stop),
      );
      expect(shifted.queryParametersAll['timeshift'], ['20260912100203']);
      String offset(Duration after) => Uri.parse(
        buildIptvCatchupUrl(
          originalUrl: 'https://f/live?offset=9',
          start: start,
          stop: stop,
          type: CatchupUrlType.offset,
          now: start.add(after),
        ),
      ).queryParameters['offset']!;
      expect(offset(const Duration(seconds: 125)), '125');
      expect(offset(const Duration(minutes: -1)), '0');
    });

    test('rejects bad URLs and intervals', () {
      expect(() => buildIptvCatchupUrl(originalUrl: '  ', start: start, stop: stop), throwsArgumentError);
      expect(() => buildIptvCatchupUrl(originalUrl: 'relative/live', start: start, stop: stop), throwsArgumentError);
      expect(() => buildIptvCatchupUrl(originalUrl: 'https://f/live', start: start, stop: start), throwsArgumentError);
    });
  });

  group('provider modes', () {
    final start = DateTime.utc(2026, 9, 12, 10, 2, 3);
    final stop = DateTime.utc(2026, 9, 12, 11, 4, 5);
    final now = DateTime.utc(2026, 9, 12, 12);
    String build(String url, {String? mode, String? source, double? correction, String? id, DateTime? from}) =>
        buildIptvCatchupUrl(
          originalUrl: url,
          start: from ?? start,
          stop: stop,
          now: now,
          mode: mode,
          source: source,
          correctionHours: correction,
          catchupId: id,
        );

    test('templates expand epochs, durations and formatted UTC times', () {
      final uri = Uri.parse(
        build(
          'https://f/live',
          mode: 'default',
          source:
              r'https://archive/s?start={utc}&end=${end}&duration={duration}&minutes={duration:60}&date={utc:Ymd-HMS}',
        ),
      );
      expect(uri.queryParameters['start'], '${start.millisecondsSinceEpoch ~/ 1000}');
      expect(uri.queryParameters['end'], '${stop.millisecondsSinceEpoch ~/ 1000}');
      expect(uri.queryParameters['duration'], '3722');
      expect(uri.queryParameters['minutes'], '62');
      expect(uri.queryParameters['date'], '20260912-100203');
    });

    test('append keeps live parameters and applies the correction', () {
      final uri = Uri.parse(
        build(
          'https://f/live?token=a&token=b#preview',
          mode: 'append',
          source: '&start={Y}{m}{d}{H}{M}{S}&offset={offset:60}',
          correction: -2.5,
          from: DateTime.utc(2026, 9, 12, 10),
        ),
      );
      expect(uri.fragment, 'preview');
      expect(uri.queryParametersAll['token'], ['a', 'b']);
      expect(uri.queryParameters['start'], '20260912073000');
      expect(uri.queryParameters['offset'], '270');
    });

    test('shift, catch-up ids, vod, Flussonic and Xtream Codes', () {
      final shift = Uri.parse(build('https://f/live#p', mode: 'shift'));
      expect(shift.queryParameters['utc'], '${start.millisecondsSinceEpoch ~/ 1000}');
      expect(shift.queryParameters['lutc'], '${now.millisecondsSinceEpoch ~/ 1000}');
      expect(shift.fragment, 'p');
      expect(Uri.parse(build('https://f/live', source: 'https://a/e/{catchup-id}', id: 'ep-42')).path, '/e/ep-42');
      expect(build('https://f/live', mode: 'vod', id: 'https://a/ep-43'), 'https://a/ep-43');
      expect(() => build('https://f/live', mode: 'default', source: 'https://a/{catchup-id}'), throwsFormatException);
      final hour = DateTime.utc(2026, 9, 12, 10);
      expect(
        Uri.parse(build('http://f:8888/151/mpegts?token=s', mode: 'fs', from: hour)).path,
        '/151/timeshift_abs-1789207200.ts',
      );
      expect(
        Uri.parse(build('http://f:8888/325/mono.m3u8', mode: 'flussonic-hls', from: hour)).path,
        '/325/mono-timeshift_rel-7200.m3u8',
      );
      expect(
        Uri.parse(build('http://f:8080/live/user/pass/1477.m3u8', mode: 'xc', from: hour)).path,
        '/timeshift/user/pass/64/2026-09-12:10-00/1477.m3u8',
      );
    });

    test('disabled and unknown modes do not invent requests', () {
      expect(() => build('https://f/live', mode: 'disabled'), throwsUnsupportedError);
      expect(() => build('https://f/live', mode: 'provider-private'), throwsUnsupportedError);
      expect(() => build('https://f/live.ts', mode: 'xc'), throwsFormatException);
    });
  });

  test('availability: disabled, archive window, missing ids and unknown modes', () {
    final now = DateTime.utc(2026, 9, 12, 12);
    IptvCatchupAvailability check(Duration ago, {String? mode, String? source, double? days, String? id}) =>
        evaluateIptvCatchupAvailability(
          programmeStop: now.subtract(ago),
          now: now,
          mode: mode,
          source: source,
          days: days,
          catchupId: id,
        );
    expect(check(const Duration(days: 10)), IptvCatchupAvailability.available);
    expect(check(const Duration(hours: 1), mode: 'disabled'), IptvCatchupAvailability.disabled);
    expect(check(const Duration(hours: 1), days: 0), IptvCatchupAvailability.disabled);
    expect(check(const Duration(days: 3, microseconds: 1), days: 3), IptvCatchupAvailability.outsideWindow);
    expect(check(const Duration(days: 3), days: 3), IptvCatchupAvailability.available);
    expect(check(Duration.zero, source: 'https://a/{catchup-id}'), IptvCatchupAvailability.unsupported);
    expect(check(Duration.zero, mode: 'vod'), IptvCatchupAvailability.unsupported);
    expect(check(Duration.zero, mode: 'private'), IptvCatchupAvailability.unsupported);
    expect(check(Duration.zero, mode: 'private', source: 'https://a/{utc}'), IptvCatchupAvailability.available);
  });
}
