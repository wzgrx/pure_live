import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/base/base_page_scroll_bone.dart';
import 'package:pure_live/common/base/base_controller.dart';
import 'package:pure_live/common/base/base_page_view.dart';
import 'package:pure_live/common/base/desktop_components.dart';
import 'package:pure_live/common/base/live_directory_controller.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/interface/live_directory.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/popular/popular_controller.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_binding.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_controller.dart';

LiveRoom _room(int id) => LiveRoom(platform: 'fixture', roomId: '$id', status: true);
LiveDirectoryPage _page(int page, Iterable<int> ids, {bool more = true}) =>
    LiveDirectoryPage(rooms: ids.map(_room), page: page, hasMore: more);
List<int> _range(int first, int last) => [for (var id = first; id <= last; id++) id];

class _Source extends LiveSite implements LiveSiteDirectoryPager {
  _Source(this.fetch);
  final Future<LiveDirectoryPage> Function(int, LiveArea?, CancelToken?) fetch;
  final calls = <int>[];
  final tokens = <CancelToken?>[];
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) {
    calls.add(page);
    tokens.add(cancel);
    return fetch(page, category, cancel);
  }
}

class _Controller extends LiveDirectoryController {
  _Controller(
    LiveSiteDirectoryPager source, {
    this.desktop = false,
    super.category,
    super.maxBufferedItems,
    super.maxRequestsPerLoad,
  }) : super(directory: source);
  final bool desktop;
  final errors = <Object>[];
  final finishes = <IndicatorResult>[];
  @override
  bool get usesDesktopPagination => desktop;
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
  @override
  void finishRefreshControllers(IndicatorResult result) {
    finishes.add(result);
    super.finishRefreshControllers(result);
  }

  @override
  void handleError(Object exception, {bool showPageError = false}) {
    errors.add(exception);
    errorMsg.value = exception.toString();
    pageError.value = true;
  }
}

class _OfflineController extends _Controller {
  _OfflineController(super.source);
  @override
  Future<bool> checkNetworkBeforeRequest() async => false;
}

// Exercise the production preflight implementation, including its state
// writes. Only the asynchronous platform read is replaced on this host.
class _PreflightController extends LiveDirectoryController {
  _PreflightController({required super.directory});
  final checks = <Completer<List<ConnectivityResult>?>>[];
  final errors = <Object>[];
  final finishes = <IndicatorResult>[];
  @override
  bool get usesDesktopPagination => false;
  @override
  Future<List<ConnectivityResult>?> readRequestConnectivity() {
    final check = Completer<List<ConnectivityResult>?>();
    checks.add(check);
    return check.future;
  }

  @override
  void handleError(Object error, {bool showPageError = false}) {
    errors.add(error);
    errorMsg.value = error.toString();
    pageError.value = true;
  }

  @override
  void finishRefreshControllers(IndicatorResult result) => finishes.add(result);
}

class _LegacyRetryController extends BasePageScrollAndStateBone<LiveRoom> {
  int refreshes = 0;
  int loads = 0;
  @override
  Future<void> refreshData() async {
    refreshes++;
  }

  @override
  Future<void> loadData() async {
    loads++;
  }

  @override
  Future<void> goToPage(int page) async {}
  @override
  void setPageSize(int? newSize) {}
}

Future<void> _until(bool Function() predicate) async {
  for (var turn = 0; turn < 100; turn++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected asynchronous phase was not reached');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // These are paging/UI tests, not persistence tests. File-backed writes
    // scheduled by the real Get root otherwise outlive the widget fake clock.
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put(SettingsService());
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 15));
  });

  test('legacy pagers retain refresh-based retry and their existing content presentation', () async {
    final controller = _LegacyRetryController();
    addTearDown(controller.onClose);
    await controller.retryData();
    expect(controller.refreshes, 1);
    expect(controller.loads, 0);
    expect(controller.retryActionLabel, 'retry');
    expect(controller.showInlineError, isFalse);
  });

  test('current preflight applies mobile, dismissal, wifi and offline states', () async {
    final source = _Source((page, _, _) async => _page(page, [1], more: false));
    final controller = _PreflightController(directory: source);
    addTearDown(controller.onClose);
    final originalDismissal = BaseController.neverShowCellularBanner;
    addTearDown(() => BaseController.neverShowCellularBanner = originalDismissal);
    BaseController.neverShowCellularBanner = false;
    var read = controller.checkNetworkBeforeRequest();
    controller.checks.last.complete([ConnectivityResult.mobile]);
    expect(await read, isTrue);
    expect(controller.showCellularBanner.value, isTrue);
    BaseController.neverShowCellularBanner = true;
    read = controller.checkNetworkBeforeRequest();
    controller.checks.last.complete([ConnectivityResult.mobile]);
    expect(await read, isTrue);
    expect(controller.showCellularBanner.value, isFalse);
    read = controller.checkNetworkBeforeRequest();
    controller.checks.last.complete([ConnectivityResult.wifi]);
    expect(await read, isTrue);
    expect(controller.showCellularBanner.value, isFalse);
    read = controller.checkNetworkBeforeRequest();
    controller.checks.last.complete([ConnectivityResult.none]);
    expect(await read, isFalse);
    expect(controller.errors, ['network_disconnected']);
    expect(source.calls, isEmpty);
  });

  for (final close in [false, true]) {
    test('plugin failure keeps fail-open behavior only for a current owner ($close)', () async {
      final source = _Source((page, _, _) async => _page(page, [1], more: false));
      final controller = _PreflightController(directory: source);
      final read = controller.checkNetworkBeforeRequest();
      if (close) {
        controller.onClose();
      } else {
        addTearDown(controller.onClose);
      }
      controller.checks.single.completeError(StateError('plugin unavailable'));
      expect(await read, !close);
      expect(controller.errors, isEmpty);
      expect(controller.showCellularBanner.value, isFalse);
      if (close) {
        expect(await controller.checkNetworkBeforeRequest(), isFalse);
        expect(controller.checks, hasLength(1));
        await controller.retryData();
      }
      expect(source.calls, isEmpty);
    });
  }

  test('repeated retries share one pending native request', () async {
    final response = Completer<LiveDirectoryPage>();
    var call = 0;
    final source = _Source((page, _, _) async {
      if (call++ == 0) throw StateError('temporary');
      return response.future;
    });
    final controller = _Controller(source);
    addTearDown(controller.onClose);
    await controller.loadData();
    final one = controller.retryData();
    final two = controller.retryData();
    await _until(() => source.calls.length == 2);
    response.complete(_page(1, [99], more: false));
    await Future.wait([one, two]);
    expect(source.calls, [1, 1]);
    expect(controller.list.single.roomId, '99');
    expect(controller.loadding.value, isFalse);
  });

  for (final result in [ConnectivityResult.none, ConnectivityResult.mobile]) {
    test('closed directory ignores a late $result connectivity result', () async {
      final source = _Source((page, _, _) async => _page(page, [1], more: false));
      final controller = _PreflightController(directory: source);
      final pending = controller.loadData();
      expect(controller.checks, hasLength(1));
      controller.onClose();
      controller.checks.single.complete([result]);
      await pending;
      expect(controller.errors, isEmpty);
      expect(controller.showCellularBanner.value, isFalse);
      expect(controller.finishes, isEmpty);
      expect(source.calls, isEmpty);
    });
  }

  for (final replace in ['refresh', 'resize']) {
    test('$replace owns preflight state before an old callback completes', () async {
      final source = _Source((page, _, _) async => _page(page, [99], more: false));
      final controller = _PreflightController(directory: source);
      addTearDown(controller.onClose);
      final old = controller.loadData();
      late final Future<void> replacement;
      if (replace == 'refresh') {
        replacement = controller.refreshData();
      } else {
        controller.setPageSize(40);
        replacement = controller.loadData();
      }
      controller.checks.first.complete([ConnectivityResult.mobile]);
      await _until(() => controller.checks.length == 2);
      final leakedBanner = controller.showCellularBanner.value;
      controller.checks.last.complete([ConnectivityResult.wifi]);
      await Future.wait([old, replacement]);
      expect(leakedBanner, isFalse);
      expect(controller.showCellularBanner.value, isFalse);
      expect(controller.errors, isEmpty);
      expect(source.calls, [1]);
      expect(controller.list.single.roomId, '99');
    });
  }

  for (final desktop in [false, true]) {
    test('capacity notice survives cached repaging and retry starts a fresh snapshot ($desktop)', () async {
      var refreshed = false;
      final source = _Source(
        (page, _, _) async =>
            refreshed ? _page(page, [99], more: false) : _page(page, page == 1 ? _range(1, 20) : _range(21, 25)),
      );
      final controller = _Controller(source, desktop: desktop, maxBufferedItems: 22)..pageSize.value = 20;
      addTearDown(controller.onClose);
      await controller.loadData();
      await controller.loadMoreData();
      expect(controller.errorMsg.value, 'directory_cache_limit');
      controller.setPageSize(10);
      await controller.loadData();
      expect(controller.errorMsg.value, 'directory_cache_limit');
      expect(controller.pageError.value, isTrue);
      expect(controller.totalCount.value, isNull);
      await controller.loadMoreData();
      expect(source.calls, [1, 2]);
      expect(controller.errorMsg.value, 'directory_cache_limit');
      refreshed = true;
      await controller.retryData();
      expect(source.calls, [1, 2, 1]);
      expect(controller.list.single.roomId, '99');
      expect(controller.pageError.value, isFalse);
    });
  }

  test('retry retains a failed desktop jump rather than fetching native page one', () async {
    var fail = true;
    final source = _Source((page, _, _) async {
      if (page == 2 && fail) throw StateError('temporary');
      return _page(page, _range((page - 1) * 20 + 1, page * 20), more: page < 4);
    });
    final controller = _Controller(source, desktop: true)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.goToPage(3);
    expect(controller.currentPage, 1);
    fail = false;
    await controller.retryData();
    expect(source.calls, [1, 2, 2, 3]);
    expect(controller.currentPage, 3);
    expect(controller.list.map((r) => r.roomId), _range(41, 60).map((i) => '$i'));
  });

  for (final desktop in [false, true]) {
    test('failed refresh preserves the committed page and metadata ($desktop)', () async {
      var refreshing = false;
      final response = Completer<LiveDirectoryPage>();
      final source = _Source((page, _, _) async {
        if (refreshing) return response.future;
        return _page(page, _range(1, 60), more: false);
      });
      final controller = _Controller(source, desktop: desktop)..pageSize.value = 20;
      addTearDown(controller.onClose);
      await controller.loadData();
      if (desktop) {
        await controller.goToPage(3);
      } else {
        await controller.loadMoreData();
        await controller.loadMoreData();
      }
      final rooms = controller.list.toList();
      refreshing = true;
      final refresh = controller.refreshData();
      await _until(() => source.calls.length == 2);
      final pendingPage = controller.currentPage;
      response.completeError(StateError('refresh failed'));
      await refresh;
      expect(pendingPage, 3, reason: 'pending refresh must not relabel old cards');
      expect(controller.currentPage, 3);
      expect(controller.list, rooms);
      expect(controller.totalCount.value, 60);
      expect(controller.canLoadMore.value, isFalse);
      expect(controller.pageError.value, isTrue);
      expect(controller.loadding.value, isFalse);
    });
  }

  test('refresh retry stages empty pages without resetting its cursor or old snapshot', () async {
    var refreshing = false;
    final source = _Source((page, _, _) async {
      if (!refreshing) return _page(page, _range(1, 60), more: false);
      return page < 3 ? _page(page, []) : _page(page, [99], more: false);
    });
    final controller = _Controller(source, desktop: true, maxRequestsPerLoad: 2)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.goToPage(3);
    refreshing = true;
    await controller.refreshData();
    expect(controller.currentPage, 3);
    expect(controller.totalCount.value, 60);
    expect(controller.list.first.roomId, '41');
    await controller.retryData();
    expect(source.calls, [1, 1, 2, 3]);
    expect(controller.currentPage, 1);
    expect(controller.totalCount.value, 1);
    expect(controller.list.single.roomId, '99');
    expect(controller.pageError.value, isFalse);
  });

  for (final action in ['navigate', 'resize', 'load-more']) {
    test('$action after a failed refresh never mixes directory snapshots', () async {
      var phase = 'initial';
      final source = _Source((page, _, _) async {
        if (phase == 'fail') throw StateError('refresh failed');
        if (phase == 'retry') return _page(page, [99], more: false);
        return _page(page, _range(1, 60), more: false);
      });
      final controller = _Controller(source, desktop: true)..pageSize.value = 20;
      addTearDown(controller.onClose);
      await controller.loadData();
      await controller.goToPage(3);
      phase = 'fail';
      await controller.refreshData();
      phase = 'retry';
      if (action == 'navigate') {
        await controller.goToPage(2);
        expect(source.calls, [1, 1]);
        expect(controller.currentPage, 2);
        expect(controller.list.first.roomId, '21');
        expect(controller.totalCount.value, 60);
      } else if (action == 'resize') {
        controller.setPageSize(10);
        await controller.loadData();
        expect(source.calls, [1, 1]);
        expect(controller.currentPage, 5);
        expect(controller.list.first.roomId, '41');
        expect(controller.list, hasLength(10));
        expect(controller.totalCount.value, 60);
      } else {
        await controller.loadMoreData();
        expect(source.calls, [1, 1, 1]);
        expect(controller.currentPage, 1);
        expect(controller.list.single.roomId, '99');
      }
    });
  }

  for (final ids in [
    <int>[],
    [1, 99],
  ]) {
    test('successful refresh commits its own cards, page and end metadata ($ids)', () async {
      var refreshing = false;
      final source = _Source((page, _, _) async => _page(page, refreshing ? ids : _range(1, 60), more: false));
      final controller = _Controller(source, desktop: true)..pageSize.value = 20;
      addTearDown(controller.onClose);
      await controller.loadData();
      await controller.goToPage(3);
      refreshing = true;
      await controller.refreshData();
      expect(controller.currentPage, 1);
      expect(controller.totalCount.value, ids.length);
      expect(controller.list.map((r) => r.roomId), ids.map((id) => '$id'));
      expect(controller.canLoadMore.value, isFalse);
      expect(controller.pageEmpty.value, ids.isEmpty);
      expect(controller.pageError.value, isFalse);
    });
  }

  test('partial fresh snapshot replaces old rows and retries only its own cursor', () async {
    var refreshing = false;
    var fail = true;
    final source = _Source((page, _, _) async {
      if (!refreshing) return _page(page, _range(1, 60), more: false);
      if (page == 1) return _page(page, _range(101, 105));
      if (fail) throw StateError('fresh second page failed');
      return _page(page, _range(106, 120), more: false);
    });
    final controller = _Controller(source, desktop: true)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.goToPage(3);
    refreshing = true;
    await controller.refreshData();
    expect(controller.currentPage, 1);
    expect(controller.list.map((r) => r.roomId), _range(101, 105).map((id) => '$id'));
    expect(controller.totalCount.value, isNull);
    expect(controller.pageError.value, isTrue);
    fail = false;
    await controller.retryData();
    expect(source.calls, [1, 1, 2, 2]);
    expect(controller.list.map((r) => r.roomId), _range(101, 120).map((id) => '$id'));
    expect(controller.totalCount.value, 20);
    expect(controller.canLoadMore.value, isFalse);
  });

  test('navigation abandons failed refresh but retains the old native cursor', () async {
    var failing = false;
    final source = _Source((page, _, _) async {
      if (failing) throw StateError('refresh failed');
      return _page(page, page == 1 ? _range(1, 60) : _range(61, 80), more: page == 1);
    });
    final controller = _Controller(source, desktop: true)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.goToPage(3);
    failing = true;
    await controller.refreshData();
    failing = false;
    await controller.goToPage(4);
    expect(source.calls, [1, 1, 2]);
    expect(controller.currentPage, 4);
    expect(controller.list.map((r) => r.roomId), _range(61, 80).map((id) => '$id'));
    expect(controller.totalCount.value, 80);
  });

  test('refresh capacity failure retains old catalogue and refresh action resets only staging', () async {
    var phase = 'initial';
    final source = _Source(
      (page, _, _) async => _page(page, phase == 'retry' ? [99] : _range(1, phase == 'initial' ? 60 : 61), more: false),
    );
    final controller = _Controller(source, desktop: true, maxBufferedItems: 60)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.goToPage(3);
    phase = 'overflow';
    await controller.refreshData();
    expect(controller.currentPage, 3);
    expect(controller.totalCount.value, 60);
    expect(controller.list.first.roomId, '41');
    expect(controller.errorMsg.value, 'directory_cache_limit');
    expect(controller.retryActionLabel, 'refresh');
    phase = 'retry';
    await controller.retryData();
    expect(source.calls, [1, 1, 1]);
    expect(controller.currentPage, 1);
    expect(controller.list.single.roomId, '99');
    expect(controller.totalCount.value, 1);
  });

  test('offline refresh retains committed end metadata through production preflight', () async {
    final source = _Source((page, _, _) async => _page(page, _range(1, 60), more: false));
    final controller = _PreflightController(directory: source)..pageSize.value = 20;
    addTearDown(controller.onClose);
    final initial = controller.loadData();
    controller.checks.single.complete([ConnectivityResult.wifi]);
    await initial;
    await controller.loadMoreData();
    await controller.loadMoreData();
    final refresh = controller.refreshData();
    await _until(() => controller.checks.length == 2);
    controller.checks.last.complete([ConnectivityResult.none]);
    await refresh;
    expect(source.calls, [1]);
    expect(controller.currentPage, 3);
    expect(controller.totalCount.value, 60);
    expect(controller.list, hasLength(60));
    expect(controller.canLoadMore.value, isFalse);
    expect(controller.errors, ['network_disconnected']);
    expect(controller.loadding.value, isFalse);
  });

  for (final action in ['refresh', 'resize', 'close']) {
    test('$action supersedes a staging response without consuming old catalogue rows', () async {
      final response = Completer<LiveDirectoryPage>();
      var call = 0;
      final source = _Source((page, _, _) async {
        switch (call++) {
          case 0:
            return _page(page, _range(1, 60), more: false);
          case 1:
            return response.future;
          default:
            return _page(page, [99], more: false);
        }
      });
      final controller = _Controller(source, desktop: true)..pageSize.value = 20;
      if (action != 'close') addTearDown(controller.onClose);
      await controller.loadData();
      await controller.goToPage(3);
      final stale = controller.refreshData();
      await _until(() => source.calls.length == 2);
      late final Future<void> replacement;
      if (action == 'refresh') {
        replacement = controller.refreshData();
      } else if (action == 'resize') {
        controller.setPageSize(10);
        replacement = controller.loadData();
      } else {
        controller.onClose();
        replacement = Future.value();
      }
      final cancelled = source.tokens[1]!.isCancelled;
      response.complete(_page(1, [777], more: false));
      await Future.wait([stale, replacement]);
      expect(cancelled, isTrue);
      expect(controller.list.any((room) => room.roomId == '777'), isFalse);
      if (action == 'refresh') {
        expect(source.calls, [1, 1, 1]);
        expect(controller.list.single.roomId, '99');
        expect(controller.currentPage, 1);
      } else if (action == 'resize') {
        expect(source.calls, [1, 1]);
        expect(controller.currentPage, 5);
        expect(controller.list.map((r) => r.roomId), _range(41, 50).map((id) => '$id'));
      } else {
        expect(source.calls, [1, 1]);
        expect(controller.currentPage, 3);
        expect(controller.list.first.roomId, '41');
      }
      expect(controller.errors, isEmpty);
    });
  }

  testWidgets('desktop refresh and inline retry keep the selected page aligned with its cards', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var phase = 'initial';
    final source = _Source((page, _, _) async {
      if (phase == 'fail') throw StateError('refresh failed');
      return _page(page, phase == 'retry' ? [99] : _range(1, 60), more: false);
    });
    final controller = _Controller(source, desktop: true)..pageSize.value = 20;
    addTearDown(controller.onClose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
    await controller.loadData();
    await controller.goToPage(3);
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: BasePageView<LiveDirectoryController, LiveRoom>(
            controller: controller,
            showScrollToTopBtn: false,
            contentBuilder: (_, rooms, scroll) =>
                ListView(controller: scroll, children: [for (final room in rooms) Text('room:${room.roomId}')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('room:41'), findsOneWidget);
    final thirdPage = find.ancestor(
      of: find.descendant(of: find.byType(DesktopPaginationBar), matching: find.text('3')),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(thirdPage).onTap, isNull);
    phase = 'fail';
    await tester.tap(find.text('refresh'));
    await tester.pumpAndSettle();
    expect(find.text('room:41'), findsOneWidget);
    expect(tester.widget<InkWell>(thirdPage).onTap, isNull);
    expect(controller.currentPage, 3);
    expect(find.byType(MaterialBanner), findsOneWidget);
    phase = 'retry';
    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
    expect(find.text('room:99'), findsOneWidget);
    expect(find.text('room:41'), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(source.calls, [1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual full-page retry resumes after empty-page budget, not page one', (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = _Source((page, _, _) async => page < 3 ? _page(page, []) : _page(page, [99], more: false));
    final controller = _Controller(source, maxRequestsPerLoad: 2)..pageSize.value = 20;
    addTearDown(controller.onClose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
    await controller.loadData();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: BasePageView<LiveDirectoryController, LiveRoom>(
            controller: controller,
            showScrollToTopBtn: false,
            contentBuilder: (_, rooms, scroll) =>
                ListView(controller: scroll, children: [for (final r in rooms) Text('room:${r.roomId}')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('retry'), findsOneWidget);
    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
    expect(source.calls, [1, 2, 3]);
    expect(find.text('room:99'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capacity is a visible notice above retained cards, with a working refresh action', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var refreshed = false;
    final source = _Source((page, _, _) async => refreshed ? _page(page, [99], more: false) : _page(page, [page]));
    final controller = _Controller(source, maxBufferedItems: 1)..pageSize.value = 2;
    addTearDown(controller.onClose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
    await controller.loadData();
    await tester.pumpWidget(
      GetMaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: BasePageView<LiveDirectoryController, LiveRoom>(
            controller: controller,
            showScrollToTopBtn: false,
            contentBuilder: (_, rooms, scroll) =>
                ListView(controller: scroll, children: [for (final r in rooms) Text('room:${r.roomId}')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('room:1'), findsOneWidget);
    expect(find.text('directory_cache_limit'), findsOneWidget);
    const longMessage =
        '目录缓存已达到上限，请刷新后继续浏览。 The directory cache is full; refresh to browse a new snapshot. '
        '此前成功加载的内容仍然保留，当前提示应在窄屏和大字体下换行，恢复动作独立放置。';
    controller.errorMsg.value = longMessage;
    await tester.pumpAndSettle();
    expect(find.text(longMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
    refreshed = true;
    await tester.tap(find.text('refresh'));
    await tester.pumpAndSettle();
    expect(find.text('room:99'), findsOneWidget);
    expect(find.text('directory_cache_limit'), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(source.calls, [1, 2, 1]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline retry resumes a failed native page without replacing successful cards', (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var fail = true;
    final source = _Source((page, _, _) async {
      if (page == 1) return _page(1, [1]);
      if (fail) throw StateError('temporary');
      return _page(2, [2], more: false);
    });
    final controller = _Controller(source)..pageSize.value = 2;
    addTearDown(controller.onClose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
    await controller.loadData();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: BasePageView<LiveDirectoryController, LiveRoom>(
            controller: controller,
            showScrollToTopBtn: false,
            contentBuilder: (_, rooms, scroll) =>
                ListView(controller: scroll, children: [for (final r in rooms) Text('room:${r.roomId}')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('room:1'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsOneWidget);
    fail = false;
    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
    expect(source.calls, [1, 2, 2]);
    expect(find.text('room:1'), findsOneWidget);
    expect(find.text('room:2'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _Source mixed() => _Source(
    (page, _, _) async => switch (page) {
      1 => _page(1, _range(1, 22)),
      2 => _page(2, []), // Filtering can remove a whole page without ending it.
      3 => _page(3, _range(20, 42), more: false),
      _ => throw StateError('No extra terminal request expected'),
    },
  );

  test('mobile consumes overflow, empty live pages and duplicates without lost cards', () async {
    final source = mixed();
    final controller = _Controller(source)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    expect(controller.list.map((r) => r.roomId), _range(1, 20).map((i) => '$i'));
    expect(source.calls, [1]);
    await controller.loadMoreData();
    expect(controller.list.map((r) => r.roomId), _range(1, 40).map((i) => '$i'));
    expect(source.calls, [1, 2, 3]);
    expect(controller.canLoadMore.value, isTrue); // Two buffered rows remain.
    await controller.loadMoreData();
    expect(controller.list.map((r) => r.roomId), _range(1, 42).map((i) => '$i'));
    expect(controller.canLoadMore.value, isFalse);
    expect(controller.totalCount.value, 42);
    await controller.loadMoreData();
    expect(source.calls, [1, 2, 3]);
  });

  test('desktop navigation and size changes retain all native page tails', () async {
    final source = mixed();
    final controller = _Controller(source, desktop: true)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.goToPage(2);
    expect(controller.list.map((r) => r.roomId), _range(21, 40).map((i) => '$i'));
    await controller.goToPage(3);
    expect(controller.list.map((r) => r.roomId), ['41', '42']);
    controller.setPageSize(12);
    await controller.loadData();
    expect(controller.currentPage, 4);
    expect(controller.list.map((r) => r.roomId), _range(37, 42).map((i) => '$i'));
    controller.setPageSize(80);
    await controller.loadData();
    expect(controller.currentPage, 1);
    expect(controller.list, hasLength(42));
    expect(controller.canLoadMore.value, isFalse);
    expect(source.calls, [1, 2, 3]);
  });

  test('configured page sizes above 200 are supported within native request and memory budgets', () async {
    final source = _Source((page, _, _) async => _page(page, _range((page - 1) * 20 + 1, page * 20), more: page < 16));
    final controller = _Controller(source, desktop: true)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    controller.setPageSize(320);
    await controller.loadData();
    expect(controller.pageSize.value, 320);
    expect(controller.list.map((r) => r.roomId), _range(1, 320).map((i) => '$i'));
    expect(source.calls, _range(1, 16));
    expect(controller.canLoadMore.value, isFalse);
    controller.setPageSize(0);
    expect(controller.pageSize.value, 320);
  });

  testWidgets('partial failure keeps actual page content mounted and retry completes its visible rows', (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var fail = true;
    final source = _Source((page, _, _) async {
      if (page == 1) return _page(1, [1, 2]);
      if (fail) throw StateError('temporary');
      return _page(2, [3, 4], more: false);
    });
    final controller = _Controller(source)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: BasePageView<LiveDirectoryController, LiveRoom>(
            controller: controller,
            showScrollToTopBtn: false,
            showPageSizeSelector: false,
            errorBuilder: (_, _) => const Text('FULL_PAGE_ERROR'),
            contentBuilder: (_, rooms, scroll) =>
                ListView(controller: scroll, children: [for (final room in rooms) Text('room:${room.roomId}')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('room:1'), findsOneWidget);
    expect(find.text('room:2'), findsOneWidget);
    expect(find.text('FULL_PAGE_ERROR'), findsNothing);
    fail = false;
    await controller.loadMoreData();
    await tester.pumpAndSettle();
    expect(find.text('room:4'), findsOneWidget);
    expect(find.text('room:1'), findsOneWidget);
    expect(find.text('FULL_PAGE_ERROR'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    // EasyRefresh schedules a zero-duration ballistic-layout callback.
    // Drain that event after disposal and retain the no-exception assertion.
    await tester.pump(Duration.zero);
    expect(tester.takeException(), isNull);
  });

  for (final desktop in [false, true]) {
    test('partial request failure resumes the SAME native and client page ($desktop)', () async {
      var fail = true;
      final source = _Source((page, _, _) async {
        if (page == 1) return _page(1, _range(1, 5));
        if (fail) throw StateError('temporary');
        return _page(2, _range(6, 25), more: false);
      });
      final controller = _Controller(source, desktop: desktop)..pageSize.value = 20;
      addTearDown(controller.onClose);
      await controller.loadData();
      expect(controller.list, hasLength(5));
      expect(controller.canLoadMore.value, isTrue);
      fail = false;
      await controller.loadMoreData();
      expect(source.calls, [1, 2, 2]);
      expect(controller.currentPage, 1);
      expect(controller.list.map((r) => r.roomId), _range(1, 20).map((i) => '$i'));
      expect(controller.pageError.value, isFalse);
      await controller.loadMoreData();
      expect(controller.list.map((r) => r.roomId), _range(desktop ? 21 : 1, 25).map((i) => '$i'));
      expect(controller.canLoadMore.value, isFalse);
    });
  }

  test('request budget is explicit and empty pages do not become a false terminal page', () async {
    final source = _Source((page, _, _) async => page < 3 ? _page(page, []) : _page(page, [1, 2], more: false));
    final controller = _Controller(source, maxRequestsPerLoad: 2)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    expect(source.calls, [1, 2]);
    expect(controller.errors, hasLength(1));
    expect(controller.canLoadMore.value, isTrue);
    expect(controller.pageEmpty.value, isFalse);
    await controller.loadMoreData();
    expect(source.calls, [1, 2, 3]);
    expect(controller.list, hasLength(2));
    expect(controller.canLoadMore.value, isFalse);
  });

  test(
    'offline preflight finishes the refresh indicator without discarding visible cards or requesting a page',
    () async {
      final source = mixed();
      final controller = _OfflineController(source)..list.assignAll([_room(99)]);
      addTearDown(controller.onClose);
      await controller.refreshData();
      expect(source.calls, isEmpty);
      expect(controller.list.single.roomId, '99');
      expect(controller.finishes, [IndicatorResult.fail]);
      expect(controller.loadding.value, isFalse);
      expect(controller.pageLoadding.value, isFalse);
    },
  );

  test('bounded cache never partially commits a native page and refresh releases its state', () async {
    final source = _Source(
      (page, _, _) async => _page(page, page == 1 ? _range(1, 20) : _range(21, 25), more: page == 1),
    );
    final controller = _Controller(source, maxBufferedItems: 22)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.loadMoreData();
    expect(controller.list, hasLength(20));
    expect(controller.errors, hasLength(1));
    expect(controller.totalCount.value, isNull); // Limit != known directory total.
    expect(controller.canLoadMore.value, isFalse);
    await controller.refreshData();
    expect(source.calls, [1, 2, 1]);
    expect(controller.list, hasLength(20));
    expect(controller.canLoadMore.value, isTrue);
  });

  test('refresh suppresses an old response and replaces the visible snapshot', () async {
    final entered = Completer<void>();
    final release = Completer<LiveDirectoryPage>();
    var calls = 0;
    final source = _Source((page, _, _) async {
      if (calls++ == 0) {
        entered.complete();
        return release.future;
      }
      return _page(1, [101, 102], more: false);
    });
    final controller = _Controller(source);
    addTearDown(controller.onClose);
    final old = controller.loadData();
    await entered.future;
    final refresh = controller.refreshData();
    expect(source.tokens.first!.isCancelled, isTrue);
    release.complete(_page(1, [1, 2], more: false));
    await old;
    await refresh;
    expect(controller.list.map((r) => r.roomId), ['101', '102']);
    expect(controller.errors, isEmpty);
    expect(controller.loadding.value, isFalse);
    expect(source.calls, [1, 1]);
  });

  test('repeated refresh coalesces behind one active request', () async {
    final entered = Completer<void>();
    final release = Completer<LiveDirectoryPage>();
    var calls = 0;
    final source = _Source((page, _, _) async {
      if (calls++ == 0) {
        entered.complete();
        return release.future;
      }
      return _page(1, [101], more: false);
    });
    final controller = _Controller(source);
    addTearDown(controller.onClose);
    final old = controller.loadData();
    await entered.future;
    final one = controller.refreshData();
    final two = controller.refreshData();
    release.complete(_page(1, [1], more: false));
    await Future.wait([old, one, two]);
    expect(source.calls, [1, 1]);
    expect(controller.list.single.roomId, '101');
  });

  test('page-size changes during a request suppress the old shape and finish the newest shape', () async {
    final entered = Completer<void>();
    final release = Completer<LiveDirectoryPage>();
    var calls = 0;
    final source = _Source((page, _, _) async {
      if (calls++ == 0) {
        entered.complete();
        return release.future;
      }
      return _page(page, _range((page - 1) * 22 + 1, page * 22), more: page < 4);
    });
    final controller = _Controller(source, desktop: true)..pageSize.value = 20;
    addTearDown(controller.onClose);
    final old = controller.loadData();
    await entered.future;
    controller.setPageSize(40);
    controller.setPageSize(80);
    final resized = controller.loadData();
    expect(source.tokens.first!.isCancelled, isTrue);
    release.complete(_page(1, _range(1001, 1022)));
    await old;
    await resized;
    expect(controller.list.map((r) => r.roomId), _range(1, 80).map((i) => '$i'));
    expect(source.calls, [1, 1, 2, 3, 4]);
    expect(controller.loadding.value, isFalse);
  });

  test('close cancels ownership and late results do not repopulate cards', () async {
    final entered = Completer<void>();
    final release = Completer<LiveDirectoryPage>();
    final source = _Source((page, _, _) {
      entered.complete();
      return release.future;
    });
    final controller = _Controller(source);
    final operation = controller.loadData();
    await entered.future;
    controller.onClose();
    release.complete(_page(1, [1], more: false));
    await operation;
    expect(source.tokens.single!.isCancelled, isTrue);
    expect(controller.list, isEmpty);
    expect(controller.errors, isEmpty);
  });

  test('bad page echo is retryable and does not consume rows', () async {
    var valid = false;
    final source = _Source((page, _, _) async => _page(valid ? page : page + 1, [1], more: false));
    final controller = _Controller(source);
    addTearDown(controller.onClose);
    await controller.loadData();
    expect(controller.list, isEmpty);
    expect(controller.canLoadMore.value, isTrue);
    valid = true;
    await controller.loadMoreData();
    expect(source.calls, [1, 1]);
    expect(controller.list.single.roomId, '1');
  });

  test('popular route chooses the optional native contract without changing registry or other routes', () async {
    final source = mixed();
    final site = Site(id: 'fixture', name: 'Fixture', logo: '', liveSite: source);
    final owner = PopularController();
    addTearDown(owner.onClose);
    owner.initControllers([site]);
    final controller = Get.find<BasePageScrollAndStateBone<LiveRoom>>(tag: 'fixture');
    expect(controller, isA<LiveDirectoryController>());
    controller.pageSize.value = 80;
    await controller.loadData();
    expect(controller.list, hasLength(42));
    expect(controller.canLoadMore.value, isFalse);
    expect(source.calls, [1, 2, 3]);
  });

  test('category type and identity are forwarded, and snapshots are independently copied', () async {
    final category = LiveArea(platform: 'fixture', areaType: 'tag', areaId: '1', areaName: 'New');
    final original = _page(1, [1], more: false);
    final source = _Source((page, area, _) async {
      expect(identical(area, category), isTrue);
      return original;
    });
    final controller = _Controller(source, category: category);
    addTearDown(controller.onClose);
    await controller.loadData();
    expect(controller.list.single.area, 'New');
    expect(original.rooms.single.area, isNull);
  });

  test('actual category binding selects native pages and separates catalog/tag controller keys', () async {
    final tag = LiveArea(platform: 'fixture', areaType: 'tag', areaId: '1', areaName: 'New');
    final catalog = LiveArea(platform: 'fixture', areaType: 'catalog', areaId: '1', areaName: 'Music');
    final source = _Source((page, area, _) async {
      expect(identical(area, tag), isTrue);
      return _page(page, [1, 2], more: false);
    });
    final site = Site(id: 'fixture', name: 'Fixture', logo: '', liveSite: source);
    expect(areaRoomsControllerTag(site, tag), isNot(areaRoomsControllerTag(site, catalog)));
    final controller = AreaRoomsBinding.createController(site, tag);
    addTearDown(controller.onClose);
    expect(controller, isA<LiveDirectoryController>());
    await controller.loadData();
    expect(controller.list, hasLength(2));
    expect(controller.list.every((room) => room.area == 'New'), isTrue);
    final other = Site(id: Sites.twitcastingSite, name: 'TwitCasting', logo: '', liveSite: LiveSite());
    final legacy = AreaRoomsBinding.createController(other, tag);
    addTearDown(legacy.onClose);
    expect(legacy, isA<AreaServerFixedController>());
  });
}
