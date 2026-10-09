// A11.6: back from a page the settings opened, the list is where it was.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../scroll_support.dart';
import '../../support.dart';
import 'settings_harness.dart';

/// The scroll position of the list keyed [key].
ScrollPosition _position(WidgetTester tester, String key) => scrollPositionOf(tester, find.byKey(ValueKey(key)));

/// Scrolls the list keyed [key] down by [by]; where it stopped.
Future<double> _scroll(WidgetTester tester, String key, double by) => scrollDown(tester, find.byKey(ValueKey(key)), by);

/// Brings [row] of the list keyed [key] into view, taps it and returns
/// where the list was when it was tapped.
Future<double> _open(WidgetTester tester, String key, Finder row) async {
  final list = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(row, 120, scrollable: list);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  final pixels = _position(tester, key).pixels;
  await tester.tap(row);
  await settleSettings(tester);
  return pixels;
}

void main() {
  setUpAll(loadStrings);

  group('phone (one column)', () {
    testWidgets('overview → a page → back (button and system back): the overview is where it was', (tester) async {
      await pumpSettings(tester, width: 400, height: 800);
      await _scroll(tester, 'settings-overview', 600);
      final before = await _open(tester, 'settings-overview', settingsSection(SettingsSection.network));
      expect(find.byKey(const ValueKey('settings-page-network')), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settleSettings(tester);
      expect(_position(tester, 'settings-overview').pixels, before);

      final again = await _open(tester, 'settings-overview', settingsSection(SettingsSection.danmaku));
      expect(find.byKey(const ValueKey('settings-page-danmaku')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settleSettings(tester);
      expect(_position(tester, 'settings-overview').pixels, again);
    });

    testWidgets('two levels deep: video → its sub-page → back → back, each list where it was', (tester) async {
      await pumpSettings(tester, width: 400, height: 800);
      await _scroll(tester, 'settings-overview', 300);
      final overview = await _open(tester, 'settings-overview', settingsSection(SettingsSection.video));
      await _scroll(tester, 'settings-section-view-video', 500);
      final video = await _open(tester, 'settings-section-view-video', settingsRow('portrait'));
      expect(find.byKey(const ValueKey('settings-section-view-portrait')), findsOneWidget);
      await _scroll(tester, 'settings-section-view-portrait', 300);

      await tester.binding.handlePopRoute();
      await settleSettings(tester);
      expect(_position(tester, 'settings-section-view-video').pixels, video);
      await tester.binding.handlePopRoute();
      await settleSettings(tester);
      expect(_position(tester, 'settings-overview').pixels, overview);
    });

    testWidgets('a page opened as a route (backup) → back: the overview is where it was', (tester) async {
      final h = await pumpSettings(tester, width: 400, height: 800);
      await _scroll(tester, 'settings-overview', 600);
      final before = await _open(tester, 'settings-overview', settingsSection(SettingsSection.backup));
      expect(h.opened.last, RoutePath.kBackup);
      AppNavigator.router.pop();
      await settleSettings(tester);
      expect(_position(tester, 'settings-overview').pixels, before);
    });

    testWidgets('the danmaku page → the block list (a route) → back: the page is where it was', (tester) async {
      final h = await pumpSettings(tester, width: 400, height: 800);
      await _open(tester, 'settings-overview', settingsSection(SettingsSection.danmaku));
      final before = await _open(tester, 'settings-page-danmaku', find.byKey(const ValueKey('danmaku-link-block')));
      expect(before, greaterThan(0));
      expect(h.opened.last, RoutePath.kSettingsDanmuShield);
      AppNavigator.router.pop();
      await settleSettings(tester);
      expect(_position(tester, 'settings-page-danmaku').pixels, before);
    });

    testWidgets('search results → the page of a result → back: the results are where they were', (tester) async {
      await pumpSettings(tester, width: 400, height: 800);
      await searchSettingsFor(tester, '弹幕');
      // The block list's row (a page of its own) at the top of the list,
      // the rows before it scrolled away.
      final row = settingsRow('video_block_list');
      await _position(tester, 'settings-search-results').ensureVisible(tester.renderObject(row));
      await tester.pumpAndSettle();
      final before = await _open(tester, 'settings-search-results', row);
      expect(before, greaterThan(0));
      expect(find.byKey(const ValueKey('settings-page-video')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settleSettings(tester);
      expect(_position(tester, 'settings-search-results').pixels, before);

      // Another search starts at its top.
      await searchSettingsFor(tester, '代理');
      expect(_position(tester, 'settings-search-results').pixels, 0);
    });
  });

  group('wide (two panes)', () {
    for (final (name, size) in [
      ('1280 × 800', const Size(1280, 800)),
      ('landscape phone 852 × 393', const Size(852, 393)),
    ]) {
      testWidgets('$name: the overview stays put; the right pane keeps its page under a sub-page', (tester) async {
        final h = await pumpSettings(tester, width: size.width, height: size.height);
        await _scroll(tester, 'settings-overview', 400);
        final overview = await _open(tester, 'settings-overview', settingsSection(SettingsSection.video));
        expect(find.byKey(const ValueKey('settings-page-video')), findsOneWidget);
        expect(_position(tester, 'settings-overview').pixels, overview);
        await _scroll(tester, 'settings-section-view-video', 500);
        final video = await _open(tester, 'settings-section-view-video', settingsRow('portrait'));
        await tester.binding.handlePopRoute();
        await settleSettings(tester);
        expect(_position(tester, 'settings-section-view-video').pixels, video);
        expect(_position(tester, 'settings-overview').pixels, overview);

        final backup = await _open(tester, 'settings-overview', settingsSection(SettingsSection.backup));
        expect(h.opened.last, RoutePath.kBackup);
        AppNavigator.router.pop();
        await settleSettings(tester);
        expect(_position(tester, 'settings-overview').pixels, backup);
        expect(_position(tester, 'settings-section-view-video').pixels, video);
      });
    }

    testWidgets('turning across 840 keeps the open page where it was', (tester) async {
      await pumpSettings(tester, width: 1280, height: 700);
      await _open(tester, 'settings-overview', settingsSection(SettingsSection.video));
      final before = await _scroll(tester, 'settings-section-view-video', 500);
      tester.view.physicalSize = const Size(500, 1100);
      await settleSettings(tester);
      expect(find.byKey(const ValueKey('settings-overview')), findsNothing);
      expect(_position(tester, 'settings-section-view-video').pixels, before);
    });

    testWidgets('turning across 840 keeps the overview where it was', (tester) async {
      await pumpSettings(tester, width: 1280, height: 700);
      final before = await _scroll(tester, 'settings-overview', 300);
      tester.view.physicalSize = const Size(500, 1100);
      await settleSettings(tester);
      expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
      expect(_position(tester, 'settings-overview').pixels, before);
      tester.view.physicalSize = const Size(1280, 700);
      await settleSettings(tester);
      expect(_position(tester, 'settings-overview').pixels, before);
    });
  });
}
