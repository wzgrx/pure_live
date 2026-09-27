import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_session_cookies.dart';

void main() {
  final source = Uri.parse('https://edge.example/live/root.m3u8');

  test('host-only and domain cookies remain pinned to the issuing origin', () {
    final jar = HlsSessionCookies();
    jar.receive(source, ['host=one; Path=/', 'domain=two; Domain=.example; Path=/']);
    expect(jar.headerFor(source), 'host=one; domain=two');
    for (final other in [
      'https://other.example/live/seg.ts',
      'https://child.edge.example/live/seg.ts',
      'http://edge.example/live/seg.ts',
      'https://edge.example:8443/live/seg.ts',
    ]) {
      expect(jar.headerFor(Uri.parse(other)), isNull, reason: other);
    }
    jar.receive(source, ['foreign=bad; Domain=other.example', 'suffix=bad; Domain=notexample']);
    expect(jar.count, 2);
  });

  test('default paths are directory scoped, case sensitive and separator bounded', () {
    final jar = HlsSessionCookies();
    jar.receive(source, ['session=one', 'invalidPath=two; Path=relative']);
    expect(jar.headerFor(source.resolve('init.mp4')), 'session=one; invalidPath=two');
    expect(jar.headerFor(source.resolve('/live')), isNotNull);
    for (final path in ['/LIVE/seg.ts', '/liveness/seg.ts', '/seg.ts']) {
      expect(jar.headerFor(source.resolve(path)), isNull);
    }
    jar.receive(source.resolve('/root.m3u8'), ['root=three']);
    expect(jar.headerFor(source.resolve('/else/seg.ts')), 'root=three');
  });

  test('same-name values replace per path and longer paths precede general ones', () {
    final jar = HlsSessionCookies();
    jar.receive(source, ['session=root; Path=/', 'session=old; Path=/live', 'session=new; Path=/live']);
    expect(jar.count, 2);
    expect(
      jar.headerFor(source, initialHeader: 'session=stale; caller=keep'),
      'session=new; session=root; caller=keep',
    );
    expect(jar.headerFor(source.resolve('/other')), 'session=root');
  });

  test('expires, deletion and Max-Age precedence use receive time', () {
    var now = DateTime.utc(2026, 9, 7);
    final jar = HlsSessionCookies(now: () => now);
    jar.receive(source, [
      'relative=live; Max-Age=2; Expires=Wed, 01 Jan 2020 00:00:00 GMT',
      'absolute=live; Expires=Mon, 07 Sep 2026 00:00:01 GMT',
      'session=live',
      'expired=gone; Max-Age=0; Expires=Wed, 01 Jan 2030 00:00:00 GMT',
    ]);
    expect(jar.count, 3);
    now = now.add(const Duration(seconds: 1));
    expect(jar.headerFor(source), 'relative=live; session=live');
    now = now.add(const Duration(seconds: 1));
    expect(jar.headerFor(source), 'session=live');
    jar.receive(source, ['session=deleted; Max-Age=-1']);
    expect(jar.headerFor(source), isNull);
    expect(jar.count, 0);
  });

  test('extreme Max-Age remains bounded and expired secure cookies stay expired', () {
    var now = DateTime.utc(2026, 9, 7);
    final jar = HlsSessionCookies(now: () => now);
    jar.receive(source, ['large=one; Max-Age=9223372036854775807', 'secure=two; Secure; Max-Age=1']);
    expect(jar.count, 2);
    now = now.add(const Duration(seconds: 1));
    expect(jar.headerFor(source), 'large=one');
    now = now.add(const Duration(days: 366));
    expect(jar.headerFor(source), isNull);
  });

  test('secure prefixes and malformed entries do not contaminate valid cookies', () {
    final jar = HlsSessionCookies();
    jar.receive(source, [
      'malformed',
      '=empty-name',
      '__Secure-bad=value',
      '__Host-bad=value; Secure; Path=/; Domain=edge.example',
      '__Host-path=value; Secure; Path=/live',
      '__Host-good=value; Secure; Path=/',
      '__Secure-good=value; Secure',
    ]);
    expect(jar.headerFor(source), '__Secure-good=value; __Host-good=value');
    jar.receive(Uri.parse('http://plain.example/live.m3u8'), ['bad=value; Secure']);
    expect(jar.headerFor(Uri.parse('http://plain.example/live.m3u8')), isNull);
  });

  test('cookie count, individual size and aggregate storage remain bounded', () {
    final jar = HlsSessionCookies();
    jar.receive(source, List.generate(100, (i) => 'c$i=v; Path=/'));
    expect(jar.count, HlsSessionCookies.maximumCount);
    expect(jar.headerFor(source), isNot(contains('c0=')));
    jar.receive(source, ['oversized=${'x' * 5000}']);
    expect(jar.headerFor(source), isNot(contains('oversized=')));
    jar.clear();
    jar.receive(source, List.generate(30, (i) => 'large$i=${'x' * 3000}'));
    expect(jar.retainedCharacters, lessThanOrEqualTo(HlsSessionCookies.maximumCharacters));
    expect(jar.count, lessThan(30));
  });

  test('independent sessions and close discard all retained cookie values', () {
    final first = HlsSessionCookies();
    final second = HlsSessionCookies();
    first.receive(source, ['session=one']);
    expect(second.headerFor(source), isNull);
    first.clear();
    expect(first.count, 0);
    expect(first.retainedCharacters, 0);
    expect(first.headerFor(source), isNull);
  });
}
