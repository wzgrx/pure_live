import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';

void main() {
  final source = Uri.parse('https://cdn.example/live/channel/master.m3u8?token=a%2Fb%2Bc%3D&rootOnly=1');
  final policy = HlsSourceQueryPolicy.fromSource(source);

  test('selected source identity includes path and fresh signature', () {
    expect(policy.matchesSource(source), isTrue);
    expect(policy.matchesSource(source.replace(path: '/live/channel/720.m3u8')), isFalse);
    expect(policy.matchesSource(source.replace(query: 'token=new')), isFalse);
    expect(policy.toString(), isNot(contains('a%2Fb')));
  });

  test('nested media gets only the exact token pair and retains signed query bytes', () {
    final target = source.resolve('720/segment.ts?x=1&x=2&sig=a%2Fb+z&flag#part');
    final result = policy.apply(target);
    expect(result.query, 'x=1&x=2&sig=a%2Fb+z&flag&token=a%2Fb%2Bc%3D');
    expect(result.fragment, 'part');
    expect(result.queryParameters['token'], 'a/b+c=');
    expect(result.queryParameters.containsKey('rootOnly'), isFalse);
    expect(policy.apply(result), result);
    expect(policy.apply(source), source);
  });

  for (final query in ['token=own', 'token=', 'token=a&token=b', 'to%6Ben=own&sig=x']) {
    test('explicit child token is preserved: $query', () {
      final target = source.resolve('child.m3u8?$query');
      expect(policy.apply(target), target);
    });
  }

  for (final url in [
    'https://other.example/live/channel/segment.ts',
    'https://cdn.example:8443/live/channel/segment.ts',
    'http://cdn.example/live/channel/segment.ts',
    'https://user@cdn.example/live/channel/segment.ts',
    'https://cdn.example/live/other/segment.ts',
    'https://cdn.example/live/channel-other/segment.ts',
    'https://cdn.example/live/channel',
    'https://cdn.example/live/channel/../../other/segment.ts',
    'https://cdn.example/live/channel/%2e%2e/other/segment.ts',
    'https://cdn.example/live/channel/child%2F..%2Fsegment.ts',
    'https://cdn.example/live/channel/child%5Csegment.ts',
    'https://cdn.example/live/channel/%00segment.ts',
    'https://cdn.example/live/channel/%FFsegment.ts',
    'https://cdn.example/live/channel/segment.ts?bad=%FF',
    'file:///live/channel/segment.ts',
  ]) {
    test('no implicit propagation outside unambiguous source scope: $url', () {
      final target = Uri.parse(url);
      expect(policy.apply(target), target);
    });
  }

  test('standard relative resolution can return from a nested list into the selected directory', () {
    final target = source.resolve('nested/child.m3u8').resolve('../segment.ts');
    expect(policy.apply(target).queryParameters['token'], 'a/b+c=');
  });

  for (final url in [
    'https://cdn.example/live/master.m3u8',
    'https://cdn.example/live/master.m3u8?token=',
    'https://cdn.example/live/master.m3u8?token=a&token=b',
    'https://cdn.example/live/master.m3u8?token=a&to%6Ben=b',
    'https://cdn.example/live/master.m3u8?token=a%0Ab',
    'https://cdn.example/live/master.m3u8?token=%FF',
    'https://cdn.example/live/master.m3u8?token=a#fragment',
    'https://user@cdn.example/live/master.m3u8?token=a',
    'file:///live/master.m3u8?token=a',
    'https://cdn.example/live/?token=a',
  ]) {
    test('invalid or ambiguous policy source is rejected: $url', () {
      expect(() => HlsSourceQueryPolicy.fromSource(Uri.parse(url)), throwsFormatException);
    });
  }

  test('source token storage is bounded', () {
    final longToken = List.filled(16385, 'a').join();
    expect(() => HlsSourceQueryPolicy.fromSource(source.replace(query: 'token=$longToken')), throwsFormatException);
  });

  test('construction diagnostics do not echo malformed source secrets', () {
    try {
      HlsSourceQueryPolicy.fromSource(source.replace(query: 'token=SECRET_VALUE%FF'));
      fail('malformed UTF-8 source accepted');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains('SECRET_VALUE')));
    }
  });
}
