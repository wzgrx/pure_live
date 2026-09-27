import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/web_dav/webdav_config.dart';

void main() {
  test('accepts HTTP directory endpoints without changing their stored text', () {
    for (final address in [
      'https://dav.example.test/dav/',
      '  https://dav.example.test/dav/  ',
      'HTTP://localhost:8080/dav',
      'http://127.0.0.1:8080/',
      'https://[::1]:8443/dav/',
      'https://dav.example.test/My Files/',
      'https://dav.example.test/My%20Files/%E5%A4%87%E4%BB%BD/',
    ]) {
      expect(WebDAVConfig.isValidAddress(address), isTrue, reason: address);
      final config = WebDAVConfig(name: 'fixture', address: address, username: 'user', password: ' secret ');
      expect(WebDAVConfig.fromJson(config.toJson()).toJson(), config.toJson());
      expect(config.fullUrl, address);
    }
  });

  test('rejects malformed endpoints and unsupported URL components', () {
    for (final address in [
      '',
      '  ',
      'not-a-url',
      '/dav/',
      '//example.test/dav/',
      'ftp://example.test/dav/',
      'file:///dav/',
      'https://',
      'https:///dav',
      'https://example.test:0/dav/',
      'https://example.test:65536/dav/',
      'https://example.test:bad/dav/',
      'https://[::1/dav/',
      'https://bad host/dav/',
      'https://bad%20host/dav/',
      'https://example.test/da\nv/',
      r'https://example.test\dav',
      'https://user:secret@example.test/dav/',
      'https://@example.test/dav/',
      'https://example.test/dav/?token=fixture',
      'https://example.test/dav/?',
      'https://example.test/dav/#folder',
      'https://example.test/dav/#',
    ]) {
      expect(WebDAVConfig.isValidAddress(address), isFalse, reason: address);
    }
  });
}
