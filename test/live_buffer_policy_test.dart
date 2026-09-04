import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/utils/live_buffer_policy.dart';

void main() {
  test('live memory budget overrides inherited on-disk and unbounded time caching', () async {
    final properties = <String, String>{'cache': 'yes', 'cache-on-disk': 'yes', 'cache-secs': '3600000'};
    await LiveBufferPolicy.apply((name, value) async {
      properties[name] = value;
    });
    expect(properties['cache'], 'yes');
    expect(properties['cache-on-disk'], 'no');
    expect(double.parse(properties['cache-secs']!), lessThanOrEqualTo(6));
    expect(properties['demuxer-max-bytes'], '${32 * 1024 * 1024}');
    expect(properties['demuxer-max-back-bytes'], '${4 * 1024 * 1024}');
  });

  test('live player keeps a bounded low-latency native buffer budget', () {
    expect(LiveBufferPolicy.forwardBytes, 32 * 1024 * 1024);
    expect(LiveBufferPolicy.backBytes, 4 * 1024 * 1024);
    expect(LiveBufferPolicy.readaheadSeconds, 2);
    expect(LiveBufferPolicy.cacheSeconds, 6);
    expect(LiveBufferPolicy.forwardBytes + LiveBufferPolicy.backBytes, lessThanOrEqualTo(36 * 1024 * 1024));
  });

  test('policy is explicit and idempotent without changing pause or decoder settings', () async {
    final properties = <String, String>{'cache-pause': 'yes', 'hwdec': 'auto-safe'};
    Future<void> setProperty(String name, String value) async {
      properties[name] = value;
    }

    await LiveBufferPolicy.apply(setProperty);
    final first = Map<String, String>.from(properties);
    await LiveBufferPolicy.apply(setProperty);
    expect(properties, first);
    expect(properties['cache-pause'], 'yes');
    expect(properties['hwdec'], 'auto-safe');
    expect(properties.keys, hasLength(8));
  });

  test('unsupported native property is surfaced to the adapter rather than ignored', () async {
    await expectLater(
      LiveBufferPolicy.apply((name, value) async {
        if (name == 'cache-on-disk') throw StateError('native property rejected');
      }),
      throwsStateError,
    );
  });
}
