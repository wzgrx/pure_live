import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

/// 08:00–09:00 Beijing time (00:00–01:00 UTC); now is 12:00 Beijing time.
final _programme = IptvProgramme(
  channelId: 'CCTV1',
  start: DateTime.utc(2026, 9, 27),
  stop: DateTime.utc(2026, 9, 27, 1),
  title: '朝闻天下',
  catchupId: 'https://vod.fixture/archive/1.m3u8',
);
final _now = DateTime.utc(2026, 9, 27, 4);
const _beijing = Duration(hours: 8);
const _start = 1790467200;
const _stop = 1790470800;
const _nowEpoch = 1790481600;

String url(String stream, IptvCatchup catchup, {IptvProgramme? programme}) => catchupUrl(
  url: stream,
  catchup: catchup,
  programme: programme ?? _programme,
  now: _now,
  utcOffset: _beijing,
).toString();

void main() {
  group('rules', () {
    test('no attributes: playseek in local time, replacing an old one and keeping the rest', () {
      expect(
        url('http://39.134.65.162/PLTV/88888888/224/3221225804/index.m3u8', IptvCatchup.none),
        'http://39.134.65.162/PLTV/88888888/224/3221225804/index.m3u8?playseek=20260927080000-20260927090000',
      );
      expect(
        url('http://fixture/live.m3u8?a=1&a=2&playseek=old', const IptvCatchup(mode: 'playseek')),
        'http://fixture/live.m3u8?a=1&a=2&playseek=20260927080000-20260927090000',
      );
      expect(
        url('http://fixture/live.m3u8', const IptvCatchup(mode: 'default')),
        'http://fixture/live.m3u8?playseek=20260927080000-20260927090000',
      );
    });

    test('default with an absolute template replaces the URL', () {
      expect(
        url(
          'http://fixture/live.m3u8',
          const IptvCatchup(mode: 'default', source: r'http://archive.fixture/{utc}/{utcend}/${duration}?now={lutc}'),
        ),
        'http://archive.fixture/$_start/$_stop/3600?now=$_nowEpoch',
      );
    });

    test('append (and default with a relative template) add to the query', () {
      const aptv = IptvCatchup(mode: 'append', source: r'?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}');
      expect(
        url('http://fixture/live.m3u8?token=x#frag', aptv),
        'http://fixture/live.m3u8?token=x&playseek=20260927080000-20260927090000#frag',
      );
      expect(
        url('http://fixture/live.m3u8', const IptvCatchup(mode: 'default', source: '&begin={utc}')),
        'http://fixture/live.m3u8?begin=$_start',
      );
      expect(
        url('http://fixture/live.m3u8', const IptvCatchup(mode: 'append')),
        'http://fixture/live.m3u8?playseek=20260927080000-20260927090000',
      );
    });

    test('shift appends utc and lutc; offset sets the seconds since the start', () {
      expect(
        url('http://fixture/live.m3u8?a=1', const IptvCatchup(mode: 'shift')),
        'http://fixture/live.m3u8?a=1&utc=$_start&lutc=$_nowEpoch',
      );
      expect(
        url('http://fixture/live.m3u8', const IptvCatchup(mode: 'offset')),
        'http://fixture/live.m3u8?catchup=default&offset=14400',
      );
    });

    test('formatted, divided and local fields', () {
      const source =
          r'http://a.fixture/{utc:Y-m-d H:M:S}/{utcend:YmdHMS}/{Y}{m}{d}{H}{M}{S}/{duration:60}/{offset:3600}/${(b)timestamp}/${now:YmdHMS}';
      expect(
        url('http://fixture/live', const IptvCatchup(mode: 'default', source: source)),
        'http://a.fixture/2026-09-27%2000:00:00/20260927010000/20260927080000/60/4/$_start/20260927040000',
      );
    });

    test('catchup-correction shifts the programme times', () {
      expect(
        url('http://fixture/live', const IptvCatchup(correction: 1)),
        'http://fixture/live?playseek=20260927090000-20260927100000',
      );
    });

    test('flussonic, xtream codes and vod', () {
      expect(
        url('http://fs.fixture/ch1/index.m3u8?token=t', const IptvCatchup(mode: 'flussonic')),
        'http://fs.fixture/ch1/timeshift_rel-14400.m3u8?token=t',
      );
      expect(
        url('http://fs.fixture/ch1/mono.m3u8', const IptvCatchup(mode: 'flussonic-hls')),
        'http://fs.fixture/ch1/mono-timeshift_rel-14400.m3u8',
      );
      expect(
        url('http://fs.fixture/ch1/mpegts', const IptvCatchup(mode: 'fs')),
        'http://fs.fixture/ch1/timeshift_abs-$_start.ts',
      );
      expect(
        url('http://xc.fixture:8080/live/user/pass/123.ts', const IptvCatchup(mode: 'xc')),
        'http://xc.fixture:8080/timeshift/user/pass/60/2026-09-27:08-00/123.ts',
      );
      expect(url('http://fixture/live', const IptvCatchup(mode: 'vod')), 'https://vod.fixture/archive/1.m3u8');
      expect(
        url('http://fixture/live', const IptvCatchup(mode: 'vod', source: 'http://vod.fixture/?id={catchup-id}')),
        'http://vod.fixture/?id=https://vod.fixture/archive/1.m3u8',
      );
    });

    test('errors: disabled, unknown fields, unknown modes, bad divisors', () {
      final fails = throwsA(isA<CatchupError>());
      expect(() => url('http://fixture/live', IptvCatchup.disabled), fails);
      expect(() => url('http://fixture/live', const IptvCatchup(mode: 'default', source: '?x={nonsense}')), fails);
      expect(() => url('http://fixture/live', const IptvCatchup(mode: 'magic')), fails);
      expect(() => url('http://fixture/live', const IptvCatchup(mode: 'default', source: '?d={duration:0}')), fails);
      expect(() => url('http://fixture/live?q=1', const IptvCatchup(mode: 'xc')), fails);
      expect(() => url('not a url', IptvCatchup.none), fails);
    });
  });

  group('availability and phase', () {
    test('phases are half-open', () {
      expect(programmePhase(_programme, DateTime.utc(2026, 9, 26, 23)), ProgrammePhase.upcoming);
      expect(programmePhase(_programme, _programme.start), ProgrammePhase.live);
      expect(programmePhase(_programme, _programme.stop), ProgrammePhase.past);
    });

    test('disabled, expired and unsupported settings', () {
      expect(catchupAvailability(IptvCatchup.none, _programme, _now), CatchupAvailability.available);
      expect(catchupAvailability(IptvCatchup.disabled, _programme, _now), CatchupAvailability.disabled);
      final threeDaysLater = _now.add(const Duration(days: 3));
      expect(
        catchupAvailability(const IptvCatchup(mode: 'default', days: 1), _programme, threeDaysLater),
        CatchupAvailability.expired,
      );
      expect(
        catchupAvailability(const IptvCatchup(mode: 'default', days: 7), _programme, threeDaysLater),
        CatchupAvailability.available,
      );
      final noId = IptvProgramme(channelId: 'a', start: _programme.start, stop: _programme.stop, title: 't');
      expect(
        catchupAvailability(const IptvCatchup(mode: 'default', source: 'http://v/{catchup-id}'), noId, _now),
        CatchupAvailability.unsupported,
      );
      expect(catchupAvailability(const IptvCatchup(mode: 'vod'), noId, _now), CatchupAvailability.unsupported);
      expect(catchupAvailability(const IptvCatchup(mode: 'magic'), noId, _now), CatchupAvailability.unsupported);
    });
  });
}
