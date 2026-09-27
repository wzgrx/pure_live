import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/video_processor_service.dart';

void main() {
  test('copy-remux progress uses output bytes despite a timestamp sentinel', () {
    expect(
      VideoProcessorService.mergeProgress(
        elapsedMilliseconds: 9223372013568000,
        recordedSeconds: 32,
        outputBytes: 75,
        inputBytes: 100,
      ),
      0.75,
    );
  });
  test('progress never reaches completion before the output commits', () {
    expect(
      VideoProcessorService.mergeProgress(
        elapsedMilliseconds: 32000,
        recordedSeconds: 32,
        outputBytes: 110,
        inputBytes: 100,
      ),
      0.99,
    );
  });
  test('plausible media time remains a fallback when byte progress is absent', () {
    expect(
      VideoProcessorService.mergeProgress(
        elapsedMilliseconds: 16000,
        recordedSeconds: 32,
        outputBytes: 0,
        inputBytes: 100,
      ),
      0.5,
    );
  });
  test('non-finite, negative and sentinel counters never become fake progress', () {
    for (final value in [double.nan, double.infinity, -1, 9223372013568000]) {
      expect(
        VideoProcessorService.mergeProgress(
          elapsedMilliseconds: value,
          recordedSeconds: 32,
          outputBytes: value,
          inputBytes: 100,
        ),
        0,
      );
    }
  });
  test('unknown input size and duration stay indeterminate rather than complete', () {
    expect(
      VideoProcessorService.mergeProgress(
        elapsedMilliseconds: 16000,
        recordedSeconds: 0,
        outputBytes: 100,
        inputBytes: 0,
      ),
      0,
    );
  });
}
