import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/core/web/cookie_text.dart';
import 'package:pure_live_app/core/web/web_engine.dart';

void main() {
  test('F-ACC-01: a pasted cookie loses control characters, the Cookie: prefix and outer blanks', () {
    expect(normalizeCookie('  Cookie: SESSDATA=a%2Cb;\r\n bili_jct=c \t'), 'SESSDATA=a%2Cb; bili_jct=c');
    expect(normalizeCookie('\u0000\n'), '');
  });

  test('F-ACC-01: the browser cookies become one header, first of a name kept, junk dropped', () {
    final header = cookieHeader(const [
      WebCookie(name: 'SESSDATA', value: 'abc%2C123'),
      WebCookie(name: 'bili_jct', value: 'x\ny'),
      WebCookie(name: 'SESSDATA', value: 'shadowed'),
      WebCookie(name: 'bad name', value: 'v'),
      WebCookie(name: 'empty', value: ' '),
      WebCookie(name: 'DedeUserID', value: '42'),
    ]);
    expect(header, 'SESSDATA=abc%2C123; bili_jct=xy; DedeUserID=42');
    expect(cookieHeader(const []), '');
  });

  test('a field is read by its exact name', () {
    const cookie = 'buvid3=b; DedeUserID=42; DedeUserID__ckMd5=m';
    expect(cookieField(cookie, 'DedeUserID'), '42');
    expect(cookieField(cookie, 'dedeuserid'), isNull);
    expect(cookieField('DedeUserID=', 'DedeUserID'), isNull);
  });

  test('only web addresses may load', () {
    expect(isWebAddress(Uri.parse('https://passport.bilibili.com/login')), isTrue);
    expect(isWebAddress(Uri.parse('bilibili://live/1')), isFalse);
    expect(isWebAddress(Uri.parse('javascript:alert(1)')), isFalse);
    expect(isWebAddress(Uri.parse('https:///nohost')), isFalse);
  });
}
