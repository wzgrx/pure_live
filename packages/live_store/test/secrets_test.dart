import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

Uint8List key(int seed) => Uint8List.fromList(List.generate(32, (index) => (index * 7 + seed) & 0xff));

void main() {
  group('AesGcmSecretCipher', () {
    test('round-trips and rejects another key, reference or tampering', () async {
      final cipher = AesGcmSecretCipher(key(1));
      final aad = Uint8List.fromList(utf8.encode('cookie/douyu'));
      final sealed = await cipher.seal(Uint8List.fromList(utf8.encode('acf_auth=secret')), aad);
      expect(utf8.decode(await cipher.open(sealed, aad)), 'acf_auth=secret');
      expect(sealed.first, 1, reason: 'version byte');
      expect(utf8.decode(sealed, allowMalformed: true), isNot(contains('secret')));
      await expectLater(AesGcmSecretCipher(key(2)).open(sealed, aad), throwsA(anything));
      await expectLater(cipher.open(sealed, Uint8List.fromList(utf8.encode('cookie/huya'))), throwsA(anything));
      final tampered = Uint8List.fromList(sealed)..[sealed.length - 1] ^= 1;
      await expectLater(cipher.open(tampered, aad), throwsA(anything));
      final again = await cipher.seal(Uint8List.fromList(utf8.encode('acf_auth=secret')), aad);
      expect(again, isNot(sealed), reason: 'random nonce');
    });

    test('needs a 32-byte key and hides it', () {
      expect(() => AesGcmSecretCipher(Uint8List(16)), throwsArgumentError);
      expect(AesGcmSecretCipher(key(1)).toString(), isNot(contains('1')));
    });
  });

  group('SecretStore', () {
    late Directory directory;

    setUp(() async => directory = await Directory.systemTemp.createTemp('live_store_secrets'));
    tearDown(() => directory.delete(recursive: true));

    Future<SecretStore> open(int seed, [List<String>? log]) => SecretStore.open(
      cipher: AesGcmSecretCipher(key(seed)),
      backend: FileSecretBackend.inRoot(directory.path),
      log: StoreLog((message) => log?.add(message)),
    );

    test('stores cookies encrypted at rest and reads them back', () async {
      final store = await open(1);
      final changes = <String>[];
      final platforms = <String>[];
      store.changes.listen(changes.add);
      store.cookieChanges.listen(platforms.add);
      await store.write(SecretRefs.cookie('Douyu'), 'acf_auth=very-secret');
      await store.write(SecretRefs.douyuLtp0, 'ltp0-secret');
      await store.write(SecretRefs.webdav('p1'), 'hunter2');
      await pumpEventQueue();
      expect(store.cookieFor('douyu'), 'acf_auth=very-secret');
      expect(changes, ['cookie/douyu', 'cookie/douyu.ltp0', 'webdav/p1']);
      expect(platforms, ['douyu', 'douyu']);
      expect(store.toString(), allOf(isNot(contains('very-secret')), isNot(contains('hunter2'))));

      final file = File('${directory.path}/DB/secrets.json');
      final text = file.readAsStringSync();
      expect(text, isNot(contains('very-secret')));
      expect(text, isNot(contains('hunter2')));
      expect(text, contains('cookie/douyu'), reason: 'reference names are not secret');
      await store.dispose();

      final reopened = await open(1);
      expect(reopened.cookieFor('douyu'), 'acf_auth=very-secret');
      expect(reopened.read(SecretRefs.webdav('p1')), 'hunter2');
      await reopened.write(SecretRefs.cookie('douyu'), '  ');
      expect(reopened.cookieFor('douyu'), isNull);
      expect(reopened.refs, {SecretRefs.douyuLtp0, SecretRefs.webdav('p1')});
    });

    test('a secret of another key reads as signed out and survives other writes', () async {
      final first = await open(1);
      await first.write(SecretRefs.cookie('bilibili'), 'SESSDATA=x');
      final log = <String>[];
      final other = await open(2, log);
      expect(other.cookieFor('bilibili'), isNull);
      expect(other.unreadable, {'cookie/bilibili'});
      expect(log.single, contains('cookie/bilibili'));
      expect(log.single, isNot(contains('SESSDATA')));
      await other.write(SecretRefs.cookie('huya'), 'huya=1');
      expect((await open(1)).cookieFor('bilibili'), 'SESSDATA=x', reason: 'kept for the original key');
      await other.write(SecretRefs.cookie('bilibili'), 'SESSDATA=new');
      expect(other.unreadable, isEmpty);
      expect((await open(2)).cookieFor('bilibili'), 'SESSDATA=new');
    });

    test('a swapped blob does not decrypt under another reference', () async {
      final backend = MemorySecretBackend();
      final cipher = AesGcmSecretCipher(key(1));
      final store = await SecretStore.open(cipher: cipher, backend: backend);
      await store.write('cookie/a', 'value-a');
      backend.blobs['cookie/b'] = backend.blobs['cookie/a']!;
      final reopened = await SecretStore.open(cipher: cipher, backend: backend);
      expect(reopened.read('cookie/a'), 'value-a');
      expect(reopened.read('cookie/b'), isNull);
    });

    test('a corrupt secrets file means signed out, not a crash', () async {
      File('${directory.path}/DB/secrets.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{broken');
      final store = await open(1);
      expect(store.refs, isEmpty);
    });

    test('memory store and reference helpers', () async {
      final store = await SecretStore.memory({'cookie/huya': 'x'});
      expect(store.cookieFor('HUYA'), 'x');
      expect(SecretRefs.platformOf('cookie/douyu.did'), 'douyu');
      expect(SecretRefs.platformOf('webdav/1'), isNull);
      expect(SecretRefs.xtream('7'), 'iptv/xtream/7');
      await store.removeWhere((ref) => ref.startsWith('cookie/'));
      expect(store.refs, isEmpty);
    });
  });
}
