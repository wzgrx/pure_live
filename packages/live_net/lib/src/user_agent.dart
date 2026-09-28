import 'dart:math';

import 'package:meta/meta.dart';

/// A desktop browser identity for platforms that reject obvious clients
/// (3.x's `FakeUserAgent`, used by Kuaishou's room pages).
///
/// Written the way current browsers send it (User-Agent reduction, Chrome
/// 113 and later): the version is `<major>.0.0.0` and macOS is always
/// `10_15_7`. 3.x wrote full build numbers, replaced every character of the
/// macOS version with `-` (an unescaped `.` in a regular expression), gave
/// Safari Chrome's version numbers, and used versions from 2021 to 2023.
@immutable
final class BrowserUserAgent {
  /// Creates an identity.
  const new({required this.userAgent, required this.platform, required this.browser, required this.version});

  /// A random identity among Chrome on macOS, Windows and Linux, Edge on
  /// Windows and Safari on macOS.
  factory random([Random? random]) {
    final pick = random ?? Random();
    final chrome = chromeMajors[pick.nextInt(chromeMajors.length)];
    final edge = edgeMajors[pick.nextInt(edgeMajors.length)];
    final safari = safariVersions[pick.nextInt(safariVersions.length)];
    const webkit = 'AppleWebKit/537.36 (KHTML, like Gecko)';
    final all = [
      BrowserUserAgent(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) $webkit Chrome/$chrome.0.0.0 Safari/537.36',
        platform: 'macOS',
        browser: 'Chrome',
        version: '$chrome',
      ),
      BrowserUserAgent(
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) $webkit Chrome/$chrome.0.0.0 Safari/537.36',
        platform: 'Windows',
        browser: 'Chrome',
        version: '$chrome',
      ),
      BrowserUserAgent(
        userAgent: 'Mozilla/5.0 (X11; Linux x86_64) $webkit Chrome/$chrome.0.0.0 Safari/537.36',
        platform: 'Linux',
        browser: 'Chrome',
        version: '$chrome',
      ),
      BrowserUserAgent(
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) $webkit Chrome/$edge.0.0.0 Safari/537.36 Edg/$edge.0.0.0',
        platform: 'Windows',
        browser: 'Edge',
        version: '$edge',
      ),
      BrowserUserAgent(
        userAgent:
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) '
            'Version/$safari Safari/605.1.15',
        platform: 'macOS',
        browser: 'Safari',
        version: safari,
      ),
    ];
    return all[pick.nextInt(all.length)];
  }

  /// Chrome majors picked from; refresh with the stable channel
  /// (versionhistory.googleapis.com; 155 on 2026-09-28).
  static const List<int> chromeMajors = [153, 154, 155];

  /// Edge majors picked from (edgeupdates.microsoft.com; 154 on 2026-09-28).
  static const List<int> edgeMajors = [153, 154];

  /// Safari versions picked from (Safari follows macOS; 27.0 on 2026-09-28).
  static const List<String> safariVersions = ['26.6', '27.0'];

  /// The `User-Agent` header value.
  final String userAgent;

  /// `macOS`, `Windows` or `Linux`.
  final String platform;

  /// `Chrome`, `Edge` or `Safari`.
  final String browser;

  /// The version as written in the User-Agent (a Chromium major, or
  /// Safari's `major.minor`).
  final String version;

  /// Major version.
  String get majorVersion => version.split('.').first;

  /// The client hints this browser sends with every request: none for
  /// Safari, the brand list, mobile flag and quoted platform for Chromium.
  /// 3.x sent Chrome's brands even with a Safari User-Agent, and an unquoted
  /// platform.
  Map<String, String> get clientHints {
    if (browser == 'Safari') return const {};
    final brand = browser == 'Edge' ? 'Microsoft Edge' : 'Google Chrome';
    return {
      'sec-ch-ua': '"$brand";v="$majorVersion", "Chromium";v="$majorVersion", "Not=A?Brand";v="24"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"$platform"',
    };
  }

  /// `User-Agent` together with [clientHints].
  Map<String, String> get headers => {'user-agent': userAgent, ...clientHints};
}
