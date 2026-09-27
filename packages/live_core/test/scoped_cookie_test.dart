import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  const cookie = ScopedCookie(name: 'a', value: '1', domain: 'nicovideo.jp', path: '/hls/segments/1/video');

  test('domain and path match as in RFC 6265', () {
    expect(cookie.appliesTo(Uri.parse('https://nicovideo.jp/hls/segments/1/video')), isTrue);
    expect(cookie.appliesTo(Uri.parse('https://a.dmc.nicovideo.jp/hls/segments/1/video/2.cmfv')), isTrue);
    expect(cookie.appliesTo(Uri.parse('https://a.nicovideo.jp/hls/segments/1/video2.cmfv')), isFalse);
    expect(cookie.appliesTo(Uri.parse('https://a.nicovideo.jp/hls/segments/1/audio/2.cmfa')), isFalse);
    expect(cookie.appliesTo(Uri.parse('https://notnicovideo.jp/hls/segments/1/video/2.cmfv')), isFalse);
    const root = ScopedCookie(name: 'b', value: '2', domain: '.example.test', path: '/');
    expect(root.appliesTo(Uri.parse('https://cdn.example.test/x')), isTrue);
    expect(root.appliesTo(Uri.parse('https://example.test')), isTrue);
  });

  test('a recipe reads its cookies at every request and sends the matching ones', () {
    var cookies = [cookie];
    final recipe = HlsRelayRecipe(cookies: () => cookies);
    final url = Uri.parse('https://a.nicovideo.jp/hls/segments/1/video/2.cmfv');
    expect(recipe.cookieHeaderFor(url), 'a=1');
    cookies = [cookie, const ScopedCookie(name: 'c', value: '3', domain: 'nicovideo.jp', path: '/hls/')];
    expect(recipe.cookieHeaderFor(url), 'a=1; c=3');
    expect(recipe.cookieHeaderFor(Uri.parse('https://a.nicovideo.jp/other')), isNull);
    expect(const HlsRelayRecipe().cookieHeaderFor(url), isNull);
  });
}
