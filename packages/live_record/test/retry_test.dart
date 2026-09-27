import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    test('regular: retryDelay, bounded by maxRetries (§11.5)', () {
      final policy = RetryPolicy(const RecordSettings(maxRetries: 3));
      expect([policy.regular(), policy.regular(), policy.regular()], everyElement(const Duration(seconds: 30)));
      expect(policy.regular(), isNull, reason: 'exhausted after maxRetries');
    });

    test('regular with backoff doubles up to maxCheckInterval', () {
      final policy = RetryPolicy(
        const RecordSettings(maxRetries: 10, retryDelay: Duration(seconds: 60), backoff: true),
      );
      expect([for (var i = 0; i < 5; i++) policy.regular()!.inSeconds], [60, 120, 240, 300, 300]);
    });

    test('fast: 2 s doubling to 15 s, never exhausted (§11.4)', () {
      final policy = RetryPolicy(const RecordSettings());
      expect([for (var i = 0; i < 6; i++) policy.fast().inSeconds], [2, 4, 8, 15, 15, 15]);
    });

    test('same URL after 5xx: 1, 2, 4 s, then give up (§5.4)', () {
      final policy = RetryPolicy(const RecordSettings());
      expect(
        [policy.sameUrl(), policy.sameUrl(), policy.sameUrl(), policy.sameUrl()],
        [const Duration(seconds: 1), const Duration(seconds: 2), const Duration(seconds: 4), null],
      );
    });

    test('10 s of healthy media resets every counter (§3)', () {
      final policy = RetryPolicy(const RecordSettings(maxRetries: 1))
        ..regular()
        ..fast()
        ..fast()
        ..http4xx();
      expect(policy.regular(), isNull);
      policy.healthy();
      expect(policy.regularFailures, 0);
      expect(policy.fast(), const Duration(seconds: 2));
      expect(policy.http4xx(), 1);
    });
  });

  group('qualities and lines (§4.2, §4.3)', () {
    const q1 = Quality(id: '0', label: '原画', rank: 10);
    const q2 = Quality(id: '4', label: '蓝光 4M', rank: 8);
    const q3 = Quality(id: '3', label: '超清', rank: 6);
    const q4 = Quality(id: '2', label: '高清', rank: 4);

    test('exact label match (ignoring case, whitespace, _ and -) goes first', () {
      expect(orderQualities([q1, q2, q3, q4], RecordQuality.bluRay4M).map((q) => q.id), ['4', '0', '3', '2']);
      expect(orderQualities([q1, q2, q3, q4], RecordQuality.original).first, q1);
    });

    test('without a match, the nearest relative position among the five tiers', () {
      expect(orderQualities([q1, q4], RecordQuality.smooth).first, q4);
      expect(orderQualities([q1, q4], RecordQuality.bluRay8M).first, q1);
      expect(orderQualities([q1, q2, q4], RecordQuality.bluRay4M).first, q2);
    });

    test('de-duplicates by id and sorts by rank', () {
      const dup = Quality(id: '0', label: 'again', rank: 1);
      expect(orderQualities([q4, q1, dup], RecordQuality.original).map((q) => q.id), ['0', '2']);
    });

    test('the cursor walks lines, then qualities, then reports exhaustion at the origin', () {
      final cursor = LineCursor([q1, q2]);
      expect((cursor.quality, cursor.lineIndex), (q1, 0));
      expect(cursor.fail(linesInQuality: 2), isTrue);
      expect((cursor.quality, cursor.lineIndex), (q1, 1));
      expect(cursor.fail(linesInQuality: 2), isTrue);
      expect((cursor.quality, cursor.lineIndex), (q2, 0));
      expect(cursor.fail(linesInQuality: 1), isFalse, reason: 'every line failed');
      expect((cursor.quality, cursor.lineIndex), (q1, 0), reason: 'back to the original quality, line 1');
    });

    test('a persisted cursor restarts at its quality and line', () {
      final cursor = LineCursor([q1, q2], start: const RecordCursor(qualityId: '4', lineIndex: 1));
      expect((cursor.quality, cursor.lineIndex), (q2, 1));
      expect(cursor.position, const RecordCursor(qualityId: '4', lineIndex: 1));
      final unknown = LineCursor([q1, q2], start: const RecordCursor(qualityId: 'gone', lineIndex: 3));
      expect((unknown.quality, unknown.lineIndex), (q1, 0));
    });
  });

  test('settings clamp to the documented ranges (§20)', () {
    final settings = const RecordSettings(
      maxConcurrent: 50,
      maxRetries: 0,
      retryDelay: Duration(seconds: 1),
      liveCheckInterval: Duration(hours: 1),
      maxCheckInterval: Duration(seconds: 10),
      readTimeout: Duration(seconds: 20),
      splitMegabytes: 10,
    ).clamped();
    expect(settings.maxConcurrent, 10);
    expect(settings.maxRetries, 1);
    expect(settings.retryDelay, const Duration(seconds: 5));
    expect(settings.liveCheckInterval, const Duration(seconds: 300));
    expect(settings.maxCheckInterval, const Duration(seconds: 300));
    expect(settings.readTimeout, const Duration(seconds: 30));
    expect(settings.splitMegabytes, 64);
  });
}
