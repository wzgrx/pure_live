import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';

/// spec/modules/multiview.md ENT-1, ENT-3, LYT-1: rooms brought into
/// multiview (一键多画面, the follows page's multi-select) land in cells a
/// window shows.
void main() {
  MultiviewLayout start(int rooms, WidthClass width, {int capacity = 9}) => multiviewStartLayout(
    rooms,
    preferred: width == WidthClass.compact ? MultiviewLayout.two : MultiviewLayout.four,
    layouts: multiviewLayoutsFor(width, capacity: capacity),
    capacity: capacity,
  );

  test('the layouts of each window class', () {
    expect(multiviewLayoutsFor(WidthClass.compact, capacity: 4), [
      MultiviewLayout.one,
      MultiviewLayout.two,
      MultiviewLayout.four,
    ]);
    expect(multiviewLayoutsFor(WidthClass.expanded, capacity: 4), contains(MultiviewLayout.onePlusN));
    expect(multiviewLayoutsFor(WidthClass.large, capacity: 4), isNot(contains(MultiviewLayout.nine)));
    expect(multiviewLayoutsFor(WidthClass.large, capacity: 9), contains(MultiviewLayout.nine));
  });

  test('how many rooms one entry fills', () {
    expect(multiviewRoomLimit(multiviewLayoutsFor(WidthClass.compact, capacity: 9), capacity: 9), 4);
    expect(multiviewRoomLimit(multiviewLayoutsFor(WidthClass.compact, capacity: 4), capacity: 4), 4);
    expect(multiviewRoomLimit(multiviewLayoutsFor(WidthClass.expanded, capacity: 4), capacity: 4), 4);
    expect(multiviewRoomLimit(multiviewLayoutsFor(WidthClass.expanded, capacity: 9), capacity: 9), 9, reason: '1+N');
    expect(multiviewRoomLimit(multiviewLayoutsFor(WidthClass.extraLarge, capacity: 9), capacity: 9), 9);
  });

  test('the default layout while the rooms fit, else the smallest that shows them all', () {
    expect(start(0, WidthClass.compact), MultiviewLayout.two);
    expect(start(2, WidthClass.compact), MultiviewLayout.two);
    expect(start(3, WidthClass.compact), MultiviewLayout.four, reason: 'phones go up to 2×2');
    expect(start(7, WidthClass.compact), MultiviewLayout.four, reason: 'the most a phone-wide window shows');
    expect(start(4, WidthClass.medium), MultiviewLayout.four);
    expect(start(6, WidthClass.expanded), MultiviewLayout.onePlusN, reason: 'no 3×3 below the large class');
    expect(start(6, WidthClass.large), MultiviewLayout.nine, reason: 'every room on screen at once');
    expect(start(12, WidthClass.large), MultiviewLayout.nine);
    expect(start(3, WidthClass.expanded, capacity: 4), MultiviewLayout.four);
  });
}
