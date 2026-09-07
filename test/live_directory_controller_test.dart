import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/base/base_page_scroll_bone.dart';
import 'package:pure_live/common/base/base_page_view.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('native-directory-');
    Hive.init(directory.path);
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
    await Hive.close();
    await directory.delete(recursive: true);
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
      MaterialApp(
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
    expect(find.text('room:1'), findsOneWidget);
    expect(find.text('room:2'), findsOneWidget);
    expect(find.text('FULL_PAGE_ERROR'), findsNothing);
    fail = false;
    await controller.loadMoreData();
    await tester.pump();
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
