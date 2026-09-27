import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  test('width classes follow principles §5.1', () {
    expect(WidthClass.of(393), WidthClass.compact);
    expect(WidthClass.of(600), WidthClass.medium);
    expect(WidthClass.of(840), WidthClass.expanded);
    expect(WidthClass.of(1280), WidthClass.large);
    expect(WidthClass.of(1920), WidthClass.extraLarge);
    expect(HeightClass.of(400), HeightClass.compact);
    expect(HeightClass.of(900), HeightClass.expanded);
  });

  test('landscape phones use a rail, not the expanded-width layout', () {
    final phone = WindowLayout(const Size(393, 852));
    final landscape = WindowLayout(const Size(852, 393));
    expect(phone.navigation, NavigationKind.bar);
    expect(landscape.width, WidthClass.expanded);
    expect(landscape.isShortLandscape, isTrue);
    expect(landscape.navigation, NavigationKind.rail);
    expect(WindowLayout(const Size(1440, 900)).navigation, NavigationKind.extendedRail);
  });

  test('grid columns come from the content width and the minimum card width', () {
    final phone = WindowLayout(const Size(393, 852));
    // 393 - 2 × 16 margin = 361 → ⌊(361 + 8) / (160 + 8)⌋ = 2.
    expect(phone.columnsFor(393 - 2 * phone.margin), 2);
    final desktop = WindowLayout(const Size(1920, 1080));
    // 1920 - 240 rail - 2 × 32 = 1616 → ⌊1632 / 216⌋ = 7.
    expect(desktop.columnsFor(1920 - 240 - 2 * desktop.margin), 7);
    expect(desktop.columnsFor(100), 2);
    expect(desktop.columnsFor(10000), 8);
  });
}
