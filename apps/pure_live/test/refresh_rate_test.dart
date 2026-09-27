import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/refresh_rate.dart';

void main() {
  test('F-SET-08: 均衡 raises the rate for a gesture and settles 1.5 s later', () {
    fakeAsync((async) {
      final requests = <bool>[];
      final controller = RefreshRateController(({required high}) async => requests.add(high))
        ..mode = RefreshRateMode.balanced;
      expect(requests, [false]);
      controller
        ..pointerDown()
        ..pointerDown()
        ..pointerUp();
      expect(requests, [false, true], reason: 'one change per gesture');
      controller.pointerUp();
      async.elapse(const Duration(milliseconds: 1400));
      expect(controller.high, isTrue);
      async.elapse(const Duration(milliseconds: 200));
      expect(requests, [false, true, false]);
    });
  });

  test('F-SET-08: 最高 holds while in front; 省电 never asks', () {
    final requests = <bool>[];
    final controller = RefreshRateController(({required high}) async => requests.add(high))
      ..mode = RefreshRateMode.performance;
    expect(controller.high, isTrue);
    controller.resumed = false;
    expect(controller.high, isFalse);
    controller.resumed = true;
    expect(controller.high, isTrue);
    controller
      ..mode = RefreshRateMode.powerSaving
      ..pointerDown();
    expect(controller.high, isFalse);
    expect(requests, [true, false, true, false]);
  });
}
