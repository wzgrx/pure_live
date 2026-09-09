import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_controller.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';
import 'package:pure_live/modules/popular/popular_grid_controller.dart';
import 'package:pure_live/plugins/area_pic_mapper.dart';

// Keep the production connectivity ownership check; only replace its native IO.
mixin _Probe<T> on ServerAllPageController<T> {
  bool desktop = false;
  Future<List<ConnectivityResult>?>? connectivity;
  int reads = 0;
  final finishes = <IndicatorResult>[];
  final errors = <Object>[];

  @override
  bool get usesDesktopPagination => desktop;
  @override
  Future<List<ConnectivityResult>?> readRequestConnectivity() async {
    reads++;
    return connectivity == null ? null : await connectivity!;
  }

  @override
  void finishRefreshControllers(IndicatorResult result) {
    finishes.add(result);
    super.finishRefreshControllers(result);
  }

  @override
  void handleError(Object exception, {bool showPageError = false}) {
    errors.add(exception);
    // Exercise real flags, but keep any unexpected late error off global UI.
    super.handleError(exception, showPageError: true);
  }

  Map<String, Object?> snapshot() => {
    'rows': list.toList(),
    'total': totalCount.value,
    'count': localItemCount,
    'page': currentPage,
    'size': pageSize.value,
    'more': canLoadMore.value,
    'loading': loadding.value,
    'pageLoading': pageLoadding.value,
    'empty': pageEmpty.value,
    'error': pageError.value,
    'login': notLogin.value,
    'message': errorMsg.value,
    'cellular': showCellularBanner.value,
    'finishes': finishes.toList(),
    'errors': errors.toList(),
  };
}

class _All extends ServerAllPageController<int> with _Probe<int> {
  Future<List<int>>? response;
  int requests = 0;
  @override
  Future<List<int>> fetchAllServerData() async {
    requests++;
    return response == null ? [1, 2, 3, 4] : await response!;
  }
}

class _Site extends LiveSite {
  Future<List<LiveCategory>>? categories;
  Future<List<LiveRoom>>? rooms;
  int requests = 0;
  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    requests++;
    return await categories!;
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea area, {int page = 1, int pageSize = 30}) async {
    requests++;
    return await rooms!;
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 20}) async {
    requests++;
    return await rooms!;
  }
}

Site _site(_Site source, {String id = 'fixture'}) => Site(id: id, name: 'Fixture', logo: '', liveSite: source);

class _Areas extends AreasListController with _Probe<LiveArea> {
  _Areas(super.site);
}

class _Rooms extends AreaServerAllController with _Probe<LiveRoom> {
  _Rooms(super.site, super.subCategory);
}

class _Popular extends PopularServerAllController with _Probe<LiveRoom> {
  _Popular(super.site);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Hive.openBox('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  tearDownAll(Hive.close);

  T track<T extends ServerAllPageController<dynamic>>(T controller) {
    addTearDown(controller.onDelete);
    return controller;
  }

  for (final desktop in [false, true]) {
    for (final fails in [false, true]) {
      test('closed ${desktop ? "desktop" : "mobile"} ignores late ${fails ? "error" : "rows"}', () async {
        final gate = Completer<List<int>>();
        final c = track(
          _All()
            ..desktop = desktop
            ..response = gate.future,
        );
        final operation = c.loadData();
        await Future<void>.delayed(Duration.zero);
        expect(c.requests, 1);
        c.onDelete();
        expect(c.isClosed, isTrue);
        final before = c.snapshot();
        expect(c.hasActiveLoad, isTrue);
        if (fails) {
          gate.completeError(StateError('late error'));
        } else {
          gate.complete([9, 8]);
        }
        await operation;
        expect(c.snapshot(), before);
        expect(c.hasActiveLoad, isFalse);
      });
    }

    test('closed cached pager ignores all paging and refresh entrypoints desktop=$desktop', () async {
      final c = track(
        _All()
          ..desktop = desktop
          ..pageSize.value = 2,
      );
      await c.loadData();
      expect(c.list, desktop ? [1, 2] : [1, 2, 3, 4]);
      c.onDelete();
      final before = c.snapshot();
      await c.goToPage(2);
      c.setPageSize(1);
      c.processLocalPaging();
      await c.loadData();
      await c.loadMoreData();
      await c.refreshData();
      expect(c.snapshot(), before);
      expect(c.requests, 1);
    });
  }

  for (final fails in [false, true]) {
    test('connectivity ${fails ? "failure" : "success"} after delete does not finish or fetch', () async {
      final gate = Completer<List<ConnectivityResult>?>();
      final c = track(_All()..connectivity = gate.future);
      final operation = c.loadData();
      expect(c.reads, 1);
      c.onDelete();
      final before = c.snapshot();
      if (fails) {
        gate.completeError(StateError('plugin'));
      } else {
        gate.complete([ConnectivityResult.mobile]);
      }
      await operation;
      expect(c.requests, 0);
      expect(c.snapshot(), before);
      expect(c.hasActiveLoad, isFalse);
    });
  }

  test('deleted controller starts no connectivity or fetch', () async {
    final c = track(_All())..onDelete();
    final before = c.snapshot();
    await c.loadData();
    await c.refreshData();
    expect(c.reads, 0);
    expect(c.requests, 0);
    expect(c.snapshot(), before);
  });

  test('queued refresh is observed but never restarted after deletion', () async {
    final gate = Completer<List<int>>();
    final c = track(_All()..response = gate.future);
    final operation = c.loadData();
    await Future<void>.delayed(Duration.zero);
    final refresh = c.refreshData();
    c.onDelete();
    final before = c.snapshot();
    gate.complete([8]);
    await Future.wait([operation, refresh]);
    expect(c.snapshot(), before);
    expect(c.requests, 1);
    expect(c.hasActiveLoad, isFalse);
  });

  test('open owner publishes, presents errors and can recover', () async {
    final c = track(_All());
    await c.loadData();
    expect(c.list, [1, 2, 3, 4]);
    final gate = Completer<List<int>>();
    c.response = gate.future;
    final refresh = c.refreshData();
    await Future<void>.delayed(Duration.zero);
    gate.completeError(StateError('current failure'));
    await refresh;
    expect(c.errors, hasLength(1));
    expect(c.pageError.value, isTrue);
    expect(c.finishes.last, IndicatorResult.fail);
    c.response = Future.value([5]);
    await c.refreshData();
    expect(c.list, [5]);
    expect(c.pageError.value, isFalse);
    expect(c.loadding.value, isFalse);
  });

  for (final id in ['fixture', Sites.douyinSite]) {
    test('open taxonomy still publishes rows and artwork id=$id', () async {
      final name = 'live-owner-artwork-$id';
      final picture = 'https://fixture.invalid/live-$id.png';
      final source = _Site()
        ..categories = Future.value([
          LiveCategory(
            id: 'live',
            name: 'Live',
            children: [LiveArea(areaId: 'live', areaName: name, areaPic: picture)],
          ),
        ]);
      final c = track(_Areas(_site(source, id: id)));
      await c.loadData();
      expect(c.categories.single.id, 'live');
      expect(c.list.single.areaId, 'live');
      expect(AreaPicMapper.getPic(name), picture);
      expect(HivePrefUtil.getString('cached_area_pics'), contains(picture));
      expect(c.errors, isEmpty);
    });

    test('late taxonomy has no page or artwork cache side effects id=$id', () async {
      final gate = Completer<List<LiveCategory>>();
      final source = _Site()..categories = gate.future;
      final c = track(_Areas(_site(source, id: id)));
      final operation = c.loadData();
      await Future<void>.delayed(Duration.zero);
      expect(source.requests, 1);
      final name = 'lifetime-artwork-$id';
      final beforePic = AreaPicMapper.getPic(name);
      final beforeCache = HivePrefUtil.getString('cached_area_pics');
      c.onDelete();
      final before = c.snapshot();
      gate.complete([
        LiveCategory(
          id: 'late',
          name: 'Late',
          children: [LiveArea(areaId: 'late', areaName: name, areaPic: 'https://fixture.invalid/$id.png')],
        ),
      ]);
      await operation;
      expect(c.categories, isEmpty);
      expect(c.snapshot(), before);
      expect(AreaPicMapper.getPic(name), beforePic);
      expect(HivePrefUtil.getString('cached_area_pics'), beforeCache);
    });
  }

  test('closed category ignores cached selection and direct projection', () async {
    final source = _Site()
      ..categories = Future.value([
        LiveCategory(
          id: 'a',
          name: 'A',
          children: [LiveArea(areaId: 'a')],
        ),
        LiveCategory(
          id: 'b',
          name: 'B',
          children: [LiveArea(areaId: 'b')],
        ),
      ]);
    final c = track(_Areas(_site(source)));
    await c.loadData();
    c.onDelete();
    final before = c.snapshot();
    c.selectCategory(1);
    c.processLocalPaging();
    expect(c.tabIndex.value, 0);
    expect(c.snapshot(), before);
  });

  for (final error in [null, '-352', "NoSuchMethodError: '[]'"]) {
    test('open area room response retains normal row/login behavior error=$error', () async {
      final gate = Completer<List<LiveRoom>>();
      final source = _Site()..rooms = gate.future;
      final row = LiveRoom(roomId: 'fixture', area: 'original');
      final c = track(_Rooms(_site(source), LiveArea(areaId: 'a', areaName: 'new area')));
      final operation = c.loadData();
      await Future<void>.delayed(Duration.zero);
      if (error == null) {
        gate.complete([row]);
      } else {
        gate.completeError(Exception(error));
      }
      await operation;
      expect(c.notLogin.value, error != null);
      expect(c.list, error == null ? [row] : isEmpty);
      expect(row.area, error == null ? 'new area' : 'original');
      expect(c.errors, isEmpty);
    });

    test('late area room response has no row/login side effects error=$error', () async {
      final gate = Completer<List<LiveRoom>>();
      final source = _Site()..rooms = gate.future;
      final row = LiveRoom(roomId: 'fixture', area: 'original');
      final c = track(_Rooms(_site(source), LiveArea(areaId: 'a', areaName: 'new area')));
      final operation = c.loadData();
      await Future<void>.delayed(Duration.zero);
      expect(source.requests, 1);
      c.onDelete();
      final before = c.snapshot();
      if (error == null) {
        gate.complete([row]);
      } else {
        gate.completeError(Exception(error));
      }
      await operation;
      expect(row.area, 'original');
      expect(c.snapshot(), before);
    });
  }

  test('late popular response does not read a released settings service', () async {
    expect(Get.isRegistered<SettingsService>(), isFalse);
    final gate = Completer<List<LiveRoom>>();
    final source = _Site()..rooms = gate.future;
    final c = track(_Popular(_site(source)));
    // Call the actual hook directly so a settings read cannot be hidden by
    // the parent pager's late-error guard.
    final operation = c.fetchAllServerData();
    await Future<void>.delayed(Duration.zero);
    expect(source.requests, 1);
    c.onDelete();
    final before = c.snapshot();
    gate.complete([LiveRoom(roomId: 'fixture')]);
    expect(await operation, isEmpty);
    expect(c.snapshot(), before);
  });
}
