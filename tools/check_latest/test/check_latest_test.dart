import 'package:check_latest/check_latest.dart';
import 'package:test/test.dart';

void main() {
  test('readEnvFile skips comments and blank lines', () {
    final env = readEnvFile('# pinned\nFLUTTER_VERSION=3.47.5\n\n  GRADLE_VERSION = 9.8.0 \nbroken\n');
    expect(env, {'FLUTTER_VERSION': '3.47.5', 'GRADLE_VERSION': '9.8.0'});
  });

  test('readDirectHostedDependencies keeps hosted direct dependencies only', () {
    const lock = '''
packages:
  args:
    dependency: "direct main"
    source: hosted
    version: "2.7.0"
  lints:
    dependency: "direct dev"
    source: hosted
    version: "6.0.0"
  collection:
    dependency: transitive
    source: hosted
    version: "1.19.1"
  media_kit:
    dependency: "direct main"
    source: path
    version: "1.2.0"
''';
    expect(readDirectHostedDependencies(lock), {'args': '2.7.0', 'lints': '6.0.0'});
  });

  test('highestStable ignores prefixes that do not match and pre-releases', () {
    expect(highestStable(['n8.1', 'n9.0.2', 'n9.1-dev', 'n10.0-rc1', 'v99.0']), '');
    expect(highestStable(['n8.1', 'n9.0.2', 'n9.1-dev', 'n10.0.0-rc1', 'v99.0'], prefix: 'n'), '9.0.2');
    expect(highestStable(['9.4.1', '9.5.0-alpha01', '9.3.0']), '9.4.1');
  });

  test('isBehind compares versions, not strings', () {
    expect(const Finding('toolchain', 'NDK', '27.3.13750724', '30.0.16248370').isBehind, isTrue);
    expect(const Finding('toolchain', 'JDK', '27', '27').isBehind, isFalse);
    expect(const Finding('toolchain', 'JDK', '26', '27').isBehind, isTrue);
    expect(const Finding('toolchain', 'Gradle', '9.8', '9.8.0').isBehind, isFalse);
    expect(const Finding('fork', 'media_kit', 'abc', 'def').isBehind, isTrue);
    expect(const Finding('pub', 'args', '2.7.0', '').isBehind, isFalse);
  });
}
