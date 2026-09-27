import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/features/about/releases.dart';
import 'package:pure_live_app/features/about/semver.dart';
import 'package:pure_live_app/features/about/update_page.dart';

/// Answers requests from a function, recording them.
final class _FakeHttp implements LiveHttp {
  new(this.answer);

  final LiveResponse Function(LiveRequest request) answer;
  final requests = <LiveRequest>[];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    return answer(request);
  }

  @override
  void close() {}
}

LiveResponse _json(Object body, {int status = 200, Uri? url}) =>
    LiveResponse(status: status, bytes: utf8.encode(jsonEncode(body)), url: url ?? Uri.parse('https://api.github.com'));

const _sha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _sha2 = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

Map<String, Object?> _release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
  String body = '',
  List<Map<String, Object?>> assets = const [],
}) => {
  'tag_name': tag,
  'name': tag,
  'body': body,
  'draft': draft,
  'prerelease': prerelease,
  'published_at': '2026-09-27T02:00:00Z',
  'html_url': 'https://github.com/wzgrx/pure_live/releases/tag/$tag',
  'assets': assets,
};

Map<String, Object?> _asset(String name, {String? digest, int size = 1000}) => {
  'name': name,
  'size': size,
  'browser_download_url': 'https://github.com/wzgrx/pure_live/releases/download/v/$name',
  'digest': ?digest,
};

void main() {
  group('SemVer', () {
    SemVer v(String text) => SemVer.tryParse(text)!;

    test('parses tags and follows SemVer precedence', () {
      expect(v('v4.0.0-preview.2+40002').toString(), '4.0.0-preview.2');
      expect(v('4.0.0').isPreRelease, isFalse);
      expect(SemVer.tryParse('v4'), isNull);
      expect(SemVer.tryParse('release-4.0.0'), isNull);
      final ordered = [
        '3.2.11',
        '4.0.0-preview.1',
        '4.0.0-preview.2',
        '4.0.0-preview.10',
        '4.0.0-rc.1',
        '4.0.0',
        '4.0.1',
        '4.1.0',
        '10.0.0',
      ].map(v).toList();
      for (var i = 0; i + 1 < ordered.length; i++) {
        expect(ordered[i] < ordered[i + 1], isTrue, reason: '${ordered[i]} < ${ordered[i + 1]}');
      }
      expect(v('4.0.0+1'), v('4.0.0+2'));
      expect(v('4.0.0-alpha') < v('4.0.0-alpha.1'), isTrue);
      expect(v('4.0.0-1') < v('4.0.0-alpha'), isTrue);
    });

    test('this build is a preview', () {
      expect(SemVer.tryParse(appVersion), isNotNull);
    });
  });

  group('releases', () {
    test('parses GitHub releases with asset digests and checksums in the notes', () {
      final release = Release.fromGitHub(
        _release(
          'v4.0.0-preview.2',
          prerelease: true,
          body: '更新说明\n\n| 文件 | SHA-256 |\n| PureLive-4.0.0-preview.2-windows-setup.exe | `$_sha2` |',
          assets: [
            _asset('PureLive-4.0.0-preview.2-arm64-v8a.apk', digest: 'sha256:$_sha'),
            _asset('PureLive-4.0.0-preview.2-windows-setup.exe'),
            _asset('PureLive-4.0.0-preview.2-windows-portable.zip'),
            _asset('native-sources.tar.xz'),
          ],
        ),
      )!;
      expect(release.version.toString(), '4.0.0-preview.2');
      expect(release.preRelease, isTrue);
      expect(release.notes, startsWith('更新说明'));
      expect(release.assets[0].sha256, _sha);
      expect(release.assets[0].kind, AssetKind.androidApk);
      expect(release.assets[0].abi, 'arm64-v8a');
      expect(release.assets[1].sha256, _sha2);
      expect(release.assets[1].kind, AssetKind.windowsSetup);
      expect(release.assets[2].kind, AssetKind.windowsPortable);
      expect(release.assets[2].sha256, isNull);
      expect(release.assets[3].kind, AssetKind.other);
      expect(release.publishedAt, DateTime.utc(2026, 9, 27, 2));
    });

    test('skips drafts and tags that are not versions', () {
      expect(Release.fromGitHub(_release('v4.0.0', draft: true)), isNull);
      expect(Release.fromGitHub(_release('nightly')), isNull);
      expect(Release.fromGitHub('not a map'), isNull);
    });

    test('classifies files by platform and ABI', () {
      (AssetKind, String?) of(String name) => ReleaseAsset.classify(name);
      expect(of('app-armeabi-v7a-release.apk'), (AssetKind.androidApk, 'armeabi-v7a'));
      expect(of('app-x86_64-release.apk'), (AssetKind.androidApk, 'x86_64'));
      expect(of('PureLive.apk'), (AssetKind.androidApk, 'universal'));
      expect(of('PureLive-Setup.exe'), (AssetKind.windowsSetup, null));
      expect(of('PureLive.msix'), (AssetKind.other, null));
      expect(of('PureLive-macos.dmg'), (AssetKind.macos, null));
      expect(of('PureLive-linux-x64.tar.gz'), (AssetKind.linux, null));
      expect(of('SHA256SUMS'), (AssetKind.checksums, null));
    });

    test('picks the newest release of the build channel', () {
      final releases = [
        _release('v3.2.11'),
        _release('v4.0.0-preview.1', prerelease: true),
        _release('v4.0.0-preview.3', prerelease: true),
        _release('v4.0.0-preview.2', prerelease: true),
        _release('v4.0.0-preview.4', prerelease: true, draft: true),
      ].map(Release.fromGitHub).nonNulls.toList();
      final preview1 = SemVer.tryParse('4.0.0-preview.1')!;
      expect(UpdateChecker.newest(releases, preview1)?.tag, 'v4.0.0-preview.3');
      expect(UpdateChecker.newest(releases, SemVer.tryParse('4.0.0-preview.3')!), isNull);
      // A release build does not see previews, and 3.x tags never count.
      expect(UpdateChecker.newest(releases, SemVer.tryParse('4.0.0')!), isNull);
      expect(UpdateChecker.v4Releases(releases, includePreRelease: true).map((release) => release.tag), [
        'v4.0.0-preview.3',
        'v4.0.0-preview.2',
        'v4.0.0-preview.1',
      ]);
      final stable = [...releases, Release.fromGitHub(_release('v4.0.0'))!];
      expect(UpdateChecker.newest(stable, SemVer.tryParse('4.0.0-preview.3')!)?.tag, 'v4.0.0');
      expect(UpdateChecker.newest(stable, SemVer.tryParse('3.9.0')!)?.tag, 'v4.0.0');
    });

    test('recommends the APK of this ABI, then universal; installer before portable', () {
      final release = Release.fromGitHub(
        _release(
          'v4.0.0',
          assets: [
            _asset('a-universal.apk'),
            _asset('a-armeabi-v7a.apk'),
            _asset('a-arm64-v8a.apk'),
            _asset('a-windows-portable.zip'),
            _asset('a-setup.exe'),
          ],
        ),
      )!;
      expect(recommendedAssets(release, platform: 'android', abi: 'arm64-v8a').map((asset) => asset.name), [
        'a-arm64-v8a.apk',
        'a-universal.apk',
      ]);
      expect(recommendedAssets(release, platform: 'windows').map((asset) => asset.name), [
        'a-setup.exe',
        'a-windows-portable.zip',
      ]);
    });
  });

  group('checker', () {
    test('reads the releases API with a user agent and maps the rate limit', () async {
      final http = _FakeHttp((request) => _json([_release('v4.0.0-preview.2', prerelease: true)]));
      final checker = UpdateChecker(http, userAgent: 'PureLive/test');
      final releases = await checker.releases();
      expect(releases.single.tag, 'v4.0.0-preview.2');
      final request = http.requests.single;
      expect(request.url.toString(), 'https://api.github.com/repos/wzgrx/pure_live/releases?per_page=30');
      expect(request.headers['user-agent'], 'PureLive/test');
      expect(request.site, UpdateChecker.site);

      final limited = UpdateChecker(_FakeHttp((_) => _json({'message': 'API rate limit exceeded'}, status: 403)));
      await expectLater(
        limited.releases(),
        throwsA(isA<UpdateCheckException>().having((e) => e.error, 'error', UpdateCheckError.rateLimited)),
      );
      final offline = UpdateChecker(_FakeHttp((_) => throw const TransportFailure('github', TransportReason.connect)));
      await expectLater(
        offline.releases(),
        throwsA(isA<UpdateCheckException>().having((e) => e.error, 'error', UpdateCheckError.network)),
      );
    });

    test('fills missing checksums from the SHA256SUMS asset', () async {
      final release = Release.fromGitHub(
        _release('v4.0.0', assets: [_asset('a-arm64-v8a.apk'), _asset('SHA256SUMS')]),
      )!;
      final http = _FakeHttp(
        (request) => LiveResponse(status: 200, bytes: utf8.encode('$_sha  a-arm64-v8a.apk\n'), url: request.url),
      );
      final filled = await UpdateChecker(http).withChecksumFile(release);
      expect(filled.assets.first.sha256, _sha);
      expect(http.requests.single.url.path, endsWith('/SHA256SUMS'));
    });
  });

  test('SHA-256 of a stream', () async {
    final hash = await sha256Of(Stream.fromIterable([utf8.encode('abc')]));
    expect(hash, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
}
